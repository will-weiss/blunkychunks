--- Blunkychunks in LOVE. A match starts from the setup screen (setup.tl),
--- where the board's diameter and personal area, the chunk size and the shot
--- clock are picked and each home is given to a bot, the keyboard or a
--- gamepad. With --play the match starts
--- straight away, you on the keyboard as Player 1 against two bots; with
--- --bots three bots play each other. During a match a gamepad can still join
--- by pressing Start, taking over the first bot's home, and Back hands it
--- back (see controls.tl); Esc goes back to the setup screen.
---
---   make run                          # build and launch on the 22-8 board
---   make run ARGS="--play"            # skip the setup screen
---   make run DIAMETER=12 NOTCH=5      # any other notched board
---   make bots                         # an all-bot match
---   make run ARGS="--seed 42"         # a reproducible match
---   make run ARGS="--fast"            # a 2 second shot clock
---   make run ARGS="--size 8"          # chunks of 8 triangles
---   make run ARGS="--shot out.png"    # screenshot after a few seconds, then quit
---   make run ARGS="--host"            # host a networked match (setup screen)
---   make run ARGS="--join 10.0.0.2"   # join one
---   make server                       # a headless server (see netplay.tl)
---
--- Play is continuous: chunks slide one step per tick while every player's
--- shot clock counts down. The clocks are staggered, so they run out in turn,
--- and each time one does that player's aim fires. Keys and buttons are
--- listed on screen (see `legend`).

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local match = require("match")
local controls = require("controls")
local draw = require("draw")
local setup = require("setup")
local server = require("server")
local client = require("client")
local netplay = require("netplay")

local record Fonts
   small: love.Font
   body: love.Font
   big: love.Font
   title: love.Font
end

local record Game
   state: sim.State
   match: match.Match
   hooks: match.Hooks
   time: number -- ms into the match, as far as the screen has got
   over: boolean
   seed: integer
   effects: {draw.Effect}
   seats: {controls.Seat} -- per player: who plays them
   online: boolean -- a networked match: `net` plays it, and only our own seats aim here
   quiet: boolean -- catching up on a networked match: no effects
end

local SHOT_SECONDS <const> = 8.0
local STEP_MS <const> = 280

--- The screen: the board on the left with the humans' queues under it, the
--- key legend and the players' panels down the right.
local SIDE_X <const> = 1440 - 446
local SIDE_W <const> = 422
local BOARD_W <const> = SIDE_X - 24 - 24
local QUEUE_H <const> = 120
local QUEUE_Y <const> = 900 - 12 - QUEUE_H

local view: draw.View
local fonts: Fonts
local game: Game -- the match, or the last one while on the setup screen
local menu: setup.State -- the setup screen, while it's up
local menu_pads: {love.Joystick: controls.Seat} = {} -- per gamepad: its stick, on the setup screen
local previews: {string: draw.View} = {} -- per board on the setup screen
local next_seed: integer
local shot_path: string
local shot_after: number
local shot_seconds = SHOT_SECONDS
local keyboard = true -- whether the keyboard starts out playing Player 1
local board_n, board_r = 11, 8
local chunk_size = 14
local flick_fires = true -- whether a gamepad's flick fires at once, or waits for the clock
local net: netplay.Session -- hosting or joined
local headless: server.Server -- with --server: the server and nothing else
local port = server.PORT
local lobby_cursor = 1 -- on the lobby screen, which home is picked

local function effect(g: Game, i: integer, text: string, hex: string, life: number)
   if g.quiet then return end
   local B = g.state.board
   local x, y = draw.screen(view, board.centroid(B.a[i], B.b[i], view.side))
   local r, gg, b = draw.rgb(hex)
   g.effects[#g.effects + 1] = {
      x = x - 6, y = y - 9, text = text,
      r = r, g = gg, b = b, ttl = life, life = life,
   }
end

--- Mark a player who just went out in the middle of their home.
local function out_effect(g: Game, p: integer)
   local home = g.state.board.homes[p]
   effect(g, home[(#home + 1) // 2], "OUT", draw.DANGER, 2.5)
end

local function check_over(g: Game)
   if sim.over(g.state) then g.over = true end
end

--- A tick happened: effects, and humans re-aim against the board.
local function ticked(g: Game, r: sim.TickResult)
   for _, t in ipairs(r.cleared) do effect(g, t.i, "x", bc.FILL[t.color], 0.7) end
   for _, t in ipairs(r.hits) do effect(g, t.i, "!", draw.DANGER, 1.2) end
   for _, p in ipairs(r.out) do out_effect(g, p) end
   check_over(g)
   if not g.over then
      for _, seat in ipairs(g.seats) do controls.update(g.state, seat) end
   end
end

--- Player `p`'s shot clock ran out and `r` is what came of it.
local function locked(g: Game, p: integer, r: sim.LockResult)
   local s = g.state
   for _, t in ipairs(r.cleared) do effect(g, t.i, "x", bc.FILL[t.color], 0.7) end
   if r.out then out_effect(g, p) end
   check_over(g)
   if g.over then return end
   controls.fired(s, g.seats[p], r)
   for _, other in ipairs(g.seats) do controls.update(s, other) end
end

--- How a local match learns each shot (from its seats) and hears what
--- happened.
local function local_hooks(g: Game): match.Hooks
   return {
      decide = function(p: integer): boolean, sim.Shot return true, controls.shot(g.state, g.seats[p]) end,
      locked = function(p: integer, r: sim.LockResult) locked(g, p, r) end,
      ticked = function(r: sim.TickResult) ticked(g, r) end,
   }
end

--- Fire now: skip the clocks ahead to when player `p`'s runs out (if `p`
--- is nil or out, the next one to), so any that would run out first fire first.
local function skip_ahead(g: Game, p?: integer)
   match.skip(g.match, p)
   match.advance(g.match, g.match.now, g.hooks)
end

--- Who plays each player, as `picks` (or, if there are none, the keyboard
--- on Player 1 unless it's all bots) has them.
local function seat_all(state: sim.State, picks?: {setup.Pick}): {controls.Seat}
   local out: {controls.Seat} = {}
   for p = 1, #state.players do
      local was = picks and picks[p]
      if was and was.kind ~= "bot" then
         out[p] = controls.human(state, p, was.kind, was.pad)
      elseif not picks and keyboard and p == 1 then
         out[p] = controls.human(state, p, "keys")
      else
         out[p] = controls.bot(state, p, was and was.brain)
      end
   end
   return out
end

--- Who plays each of `seats`, to seat a new match or the setup screen.
local function picks_of(seats: {controls.Seat}): {setup.Pick}
   local out: {setup.Pick} = {}
   for p, seat in ipairs(seats) do out[p] = { kind = seat.kind, pad = seat.pad, brain = seat.brain } end
   return out
end

local function new_game(seed: integer, picks?: {setup.Pick}): Game
   local B = board.new(board_n, board_r)
   view = draw.layout(B, 24, 92, BOARD_W, QUEUE_Y - 12 - 92)
   local state = sim.new(B, chunk_size, bc.seeded_random(seed), bc.seeded_random(seed + 7919))
   local g: Game = {
      state = state,
      match = match.new(state, math.floor(shot_seconds * 1000 + 0.5), STEP_MS),
      time = 0,
      over = false,
      seed = seed,
      effects = {},
   }
   g.hooks = local_hooks(g)
   g.seats = seat_all(g.state, picks)
   next_seed = seed + 1
   return g
end

--- A networked match starting (or arriving, for a late joiner): play the
--- client's copy of it, seated as the lobby has it.
local function online_game(cg: client.Game)
   local B = cg.state.board
   board_n, board_r, chunk_size = B.n, B.r, cg.config.size
   shot_seconds, flick_fires = cg.config.clock / 1000, cg.config.flick
   view = draw.layout(B, 24, 92, BOARD_W, QUEUE_Y - 12 - 92)
   local g: Game = {
      state = cg.state,
      match = cg.m,
      time = 0,
      over = false,
      seed = cg.seed,
      effects = {},
      online = true,
   }
   g.seats = netplay.seats(net, cg.state)
   check_over(g)
   game = g
   menu = nil
end

--- What a networked match tells this game.
local function net_hooks(): client.Hooks
   return {
      start = function(cg: client.Game) online_game(cg) end,
      lobby = function()
         if menu and net.srv then netplay.remotes(net, menu) end
         local g = game
         if g and g.online then
            if net.c.lobby.running then
               g.seats = netplay.seats(net, g.state, g.seats)
            else
               game = nil
               if net.srv then
                  menu = setup.new(board_n, board_r, chunk_size, shot_seconds, flick_fires, g and picks_of(g.seats), "host")
                  netplay.remotes(net, menu)
               end
            end
         end
      end,
      locked = function(p: integer, r: sim.LockResult)
         if game and game.online then locked(game, p, r) end
      end,
      ticked = function(r: sim.TickResult)
         if game and game.online then ticked(game, r) end
      end,
   }
end

--- Stop hosting or leave the match joined, back to the setup screen saying
--- `why` (if anything).
local function leave_net(why?: string)
   local address = net and not net.srv and net.address or (menu and menu.address) or ""
   local play: setup.Play = net and (net.srv and "host" or "join") or "here"
   local picks = game and picks_of(game.seats) or (menu and menu.picks) or { { kind = "keys" } }
   if net then netplay.close(net) end
   net = nil
   if game and game.online then game = nil end
   menu = setup.new(board_n, board_r, chunk_size, shot_seconds, flick_fires, picks, play == "host" and "here" or play, address)
   menu.note = why
end

--- Start hosting from the setup screen.
local function host_net()
   local s, err = netplay.host(port, netplay.config(menu, STEP_MS), next_seed, net_hooks())
   if not s then
      menu.play, menu.note = "here", "Can't host: " .. err
      return
   end
   net = s
   menu.note = nil
end

--- Join the match at the setup screen's address.
local function join_net()
   local s, err = netplay.join(menu.address, port, net_hooks())
   if not s then
      menu.note = "Can't join: " .. err
      return
   end
   net = s
   lobby_cursor = 1
   menu = nil
end

local function flag(args: {string}, name: string): string
   for i, a in ipairs(args) do
      if a == name then return args[i + 1] or "" end
   end
   return nil
end

function love.load(args: {string})
   if not flag(args, "--server") then
      draw.background()
      fonts = {
         small = love.graphics.newFont(12),
         body = love.graphics.newFont(15),
         big = love.graphics.newFont(20),
         title = love.graphics.newFont(26),
      }
   end
   board_n, board_r = board.options(args)
   chunk_size = math.floor(tonumber(flag(args, "--size") or "") or chunk_size)
   local seed = tonumber(flag(args, "--seed") or "") or os.time()
   if flag(args, "--fast") then shot_seconds = 2.0 end
   if flag(args, "--bots") then keyboard = false end
   port = math.floor(tonumber(flag(args, "--port") or "") or port)
   next_seed = math.floor(seed)
   if flag(args, "--server") then
      local clock = tonumber(flag(args, "--clock") or "") or shot_seconds
      local err: string
      headless, err = netplay.serve(port, {
         n = board_n, r = board_r, size = chunk_size, clock = math.floor(clock * 1000 + 0.5), step = STEP_MS, flick = flick_fires,
      }, next_seed)
      if not headless then
         print(err)
         love.event.quit(1)
         return
      end
      print(("blunkychunks server on port %d: the first to join starts the match"):format(port))
      return
   end
   if flag(args, "--bots") or flag(args, "--play") then
      game = new_game(next_seed)
   else
      menu = setup.new(board_n, board_r, chunk_size, shot_seconds, flick_fires, { { kind = "keys" } })
      if flag(args, "--host") then
         menu.play = "host"
         host_net()
      elseif flag(args, "--join") then
         menu.play, menu.address = "join", flag(args, "--join")
         join_net()
      end
   end
   shot_path = flag(args, "--shot")
   shot_after = tonumber(flag(args, "--after") or "") or 3.0
end

--- Back to the setup screen, with the options and seats of the last match.
local function open_setup()
   menu = setup.new(board_n, board_r, chunk_size, shot_seconds, flick_fires, game and picks_of(game.seats))
   menu_pads = {}
end

--- Start a match as the setup screen has it: here, hosted (once the server
--- starts it, `online_game` takes over) or by joining.
local function start_match()
   if menu.play == "join" then return join_net() end
   board_n, board_r, chunk_size, shot_seconds, flick_fires = setup.options(menu)
   if menu.play == "host" then
      if net and net.c.status == "lobby" then
         netplay.push(net, menu, STEP_MS)
         client.start(net.c)
      end
      return
   end
   game = new_game(next_seed, menu.picks)
   menu = nil
end

--- The setup screen changed: start or stop hosting if its Play row did.
local function menu_changed(was: setup.Play)
   if menu.play == was then return end
   if was == "host" and net then
      netplay.close(net)
      net = nil
   end
   if menu.play == "host" then host_net() end
end

--- `action` from `seat`'s controller: aim, or fire now (a flick too, if
--- the setup screen said so).
local function seat_action(g: Game, seat: controls.Seat, action: controls.Action)
   if g.over then return end
   if g.online and (action == "fire" or (action == "flick" and flick_fires)) then
      -- Over the network firing now is a vote: see the README.
      local ready = net.c.game and net.c.game.ready[seat.player]
      client.ready(net.c, seat.player, action == "flick" or not ready)
   elseif action == "fire" or (action == "flick" and flick_fires) then
      skip_ahead(g, seat.player)
   else
      controls.act(g.state, seat, action)
   end
end

local function take_shot(dt: number)
   if not shot_path then return end
   shot_after = shot_after - dt
   if shot_after <= 0 then
      love.graphics.captureScreenshot(shot_path)
      shot_path = nil
      love.event.quit()
   end
end

function love.update(dt: number)
   if headless then return server.update(headless) end
   take_shot(dt)
   if net then
      netplay.update(net)
      if net.c.status == "gone" then return leave_net(("Disconnected: %s."):format(net.c.why or "lost the connection")) end
      if menu then netplay.push(net, menu, STEP_MS) end
   end
   if menu then return end
   local g = game
   if not g then return end
   for i = #g.effects, 1, -1 do
      g.effects[i].life = g.effects[i].life - dt
      if g.effects[i].life <= 0 then table.remove(g.effects, i) end
   end

   for _, seat in ipairs(g.seats) do
      for _, action in ipairs(controls.repeats(seat, dt)) do seat_action(g, seat, action) end
   end

   if g.online then
      g.time = math.max(g.match.now, client.view(net.c))
      g.quiet = net.c.game and net.c.game.catching_up
      if not g.over then netplay.aims(net, g.state, g.seats) end
   elseif not g.over then
      g.time = math.max(g.time, g.match.now) + dt * 1000
      match.advance(g.match, math.floor(g.time), g.hooks)
   end

end

--- The seat played on `kind` of controller (and `pad`, for a gamepad), if any.
local function seat_of(g: Game, kind: controls.Kind, pad?: love.Joystick): controls.Seat
   for _, seat in ipairs(g.seats) do
      if seat.kind == kind and seat.pad == pad then return seat end
   end
   return nil
end

--- The first bot seat a newcomer could take: one still in, or any once
--- the match is over.
local function free_seat(g: Game): controls.Seat
   for p, seat in ipairs(g.seats) do
      local bot = seat.kind == "bot" or (g.online and seat.kind == "remote" and net.c.lobby.seats[p].kind == "bot")
      if bot and (g.over or g.state.players[p].alive) then return seat end
   end
   return nil
end

--- Gamepads plugged in but not playing.
local function idle_pads(): integer
   local n = 0
   for _, pad in ipairs(love.joystick.getJoysticks()) do
      if pad:isGamepad() and not seat_of(game, "pad", pad) then n = n + 1 end
   end
   return n
end

--- Every key and button the game listens to, grouped for the on-screen legend:
--- one group per kind of controller in play, then how to join, then the
--- game's own keys.
local function legend(g: Game): {draw.KeyGroup}
   local groups: {draw.KeyGroup} = {}
   for _, kind in ipairs({ "keys", "pad" } as {controls.Kind}) do
      local who: {integer} = {}
      local label: string
      for p, seat in ipairs(g.seats) do
         if seat.kind == kind then who[#who + 1], label = p, controls.label(seat) end
      end
      if #who > 0 then
         local names = #who == 1 and board.PLAYERS[who[1]].name or "Players " .. table.concat(who, ", ")
         groups[#groups + 1] = {
            title = ("%s  -  %s"):format(names, label),
            color = #who == 1 and board.PLAYERS[who[1]].color or nil,
            keys = controls.legend(kind, g.online),
         }
      end
   end
   local free = free_seat(g)
   if free then
      local who = board.PLAYERS[free.player].name
      local hint = idle_pads() > 0 and ("join as " .. who) or ("plug one in and press Start to join as " .. who)
      groups[#groups + 1] = { title = "Controller", keys = { { "Start", hint } } }
   end
   local game_keys: {{string, string}} = { { "+ / -", "slide speed" }, { "R", "new match" }, { "Esc", "setup" } }
   if g.online then
      game_keys = net.c.owner and { { "+ / -", "slide speed" }, { "R", "new match" }, { "Esc", "everyone to the lobby" } }
         or { { "Esc", "leave the match" } }
      if not seat_of(g, "keys") and free then table.insert(game_keys, 1, { "Enter", "take a home" }) end
   elseif not seat_of(g, "keys") then
      table.insert(game_keys, 1, { "Space", "skip to the next shot" })
   end
   groups[#groups + 1] = { title = "Game", keys = game_keys }
   return groups
end

--- Gamepads plugged in, in the order the setup screen numbers them.
local function gamepads(): {love.Joystick}
   local out: {love.Joystick} = {}
   for _, pad in ipairs(love.joystick.getJoysticks()) do
      if pad:isGamepad() then out[#out + 1] = pad end
   end
   return out
end

--- The setup screen's keys and buttons, for the legend.
local function menu_legend(): {draw.KeyGroup}
   local start = setup.seat_of(menu, "bot") and "join" or "start"
   return {
      { title = "Keyboard", keys = {
         { "Up Down", "choose" }, { "Left Right", "change" }, { "Enter", "start" }, { "Esc", "quit" },
      } },
      { title = "Controller", keys = {
         { "D-pad / stick", "choose, change" }, { "A", "select" },
         { "Start", ("%s, then start"):format(start) }, { "B / Back", "leave" },
      } },
   }
end

local function draw_menu()
   local n, r = setup.options(menu)
   local key = board.key(n, r)
   if not previews[key] then previews[key] = draw.layout(board.new(n, r), 680, 40, 1440 - 680 - 24, 900 - 40 - 100) end
   draw.board(previews[key])

   love.graphics.setFont(fonts.title)
   local rr, gg, bb = draw.rgb(draw.INK)
   love.graphics.setColor(rr, gg, bb)
   love.graphics.print("Blunkychunks", 60, 40)
   love.graphics.setFont(fonts.body)
   rr, gg, bb = draw.rgb(draw.MUTED)
   love.graphics.setColor(rr, gg, bb)
   local lines = {
      "Set up a match: pick the options, and who plays each home.",
      "Press Start on a controller to take the first home a bot has.",
   }
   if menu.play == "host" and net then
      lines = {
         ("Hosting at %s: others pick Join and type that in."):format(net.address),
         "They take the first free home; set the rest, then start.",
      }
   elseif menu.play == "join" then
      lines = { "Type in the address the host's screen shows, then Join.", "The host picks the options." }
   end
   love.graphics.print(lines[1], 60, 78)
   love.graphics.print(lines[2], 60, 100)
   if menu.note then
      rr, gg, bb = draw.rgb(draw.DANGER)
      love.graphics.setColor(rr, gg, bb)
      love.graphics.print(menu.note, 60, 122)
   end

   draw.setup(setup.lines(menu, gamepads()), menu.cursor, 60, 140, 560, fonts.body, fonts.big)
   local groups = menu_legend()
   draw.controls(groups, 60, 900 - 24 - draw.controls_height(groups, 1300, fonts.small, false), 1300, fonts.small, false)
end

--- A menu move from any controller: up, down, left or right.
local function menu_step(action: controls.Action)
   local was = menu.play
   if action == "heading_next" then
      setup.move(menu, -1)
   elseif action == "heading_prev" then
      setup.move(menu, 1)
   elseif action == "left" then
      setup.change(menu, -1, gamepads())
   elseif action == "right" then
      setup.change(menu, 1, gamepads())
   end
   menu_changed(was)
end

local MENU_KEYS <const>: {string: controls.Action} = {
   up = "heading_next", w = "heading_next", down = "heading_prev", s = "heading_prev",
   left = "left", a = "left", right = "right", d = "right",
}

local function menu_key(key: string)
   if setup.on_address(menu) and (#key == 1 or key == "kp.") then return end -- typing: see love.textinput
   if key == "backspace" then
      setup.backspace(menu)
   elseif MENU_KEYS[key] then
      menu_step(MENU_KEYS[key])
   elseif key == "return" or key == "kpenter" or key == "space" then
      start_match()
   elseif key == "escape" then
      if net then netplay.close(net) end
      love.event.quit()
   end
end

local MENU_BUTTONS <const>: {string: controls.Action} = {
   dpup = "heading_next", dpdown = "heading_prev", dpleft = "left", dpright = "right",
}

local function menu_button(pad: love.Joystick, button: string)
   local seated = setup.seat_of(menu, "pad", pad)
   if MENU_BUTTONS[button] then
      menu_step(MENU_BUTTONS[button])
   elseif button == "a" then
      local was = menu.play
      if setup.press(menu, pad, gamepads()) then return start_match() end
      menu_changed(was)
   elseif button == "start" then
      if seated then start_match() else setup.join(menu, pad) end
   elseif button == "b" or button == "back" then
      setup.leave(menu, "pad", pad)
   end
end

local function menu_axis(pad: love.Joystick, axis: string, value: number)
   if not menu_pads[pad] then menu_pads[pad] = { player = 0, kind = "pad", pad = pad, stick = {} } end
   local action = controls.axis_action(menu_pads[pad], axis, value)
   if action then menu_step(action) end
end

--- The lobby, for someone who joined: who sits where, and the host's options.
local function draw_lobby()
   local c = net.c
   love.graphics.setFont(fonts.title)
   local rr, gg, bb = draw.rgb(draw.INK)
   love.graphics.setColor(rr, gg, bb)
   love.graphics.print("Blunkychunks", 60, 40)
   love.graphics.setFont(fonts.body)
   rr, gg, bb = draw.rgb(draw.MUTED)
   love.graphics.setColor(rr, gg, bb)
   if c.status == "connecting" or not c.lobby then
      love.graphics.print(("Connecting to %s ...   (Esc to give up)"):format(net.address), 60, 78)
      return
   end
   local cfg = c.lobby.config
   local key = board.key(cfg.n, cfg.r)
   if not previews[key] then previews[key] = draw.layout(board.new(cfg.n, cfg.r), 680, 40, 1440 - 680 - 24, 900 - 40 - 100) end
   draw.board(previews[key])
   love.graphics.print(("Joined %s: a %d-%d board, chunks of %d, a %g s shot clock."):format(
      net.address, 2 * cfg.n, cfg.r, cfg.size, cfg.clock / 1000), 60, 78)
   love.graphics.print(c.owner and "You run this server: start the match when everyone's in."
      or "The host starts the match. Pick a home to play, or just watch.", 60, 100)
   local lines: {setup.Line} = {}
   for p, pl in ipairs(board.PLAYERS) do
      local who = netplay.who(net, p)
      local slot = client.mine(c, p)
      if slot then who = slot == "keys" and "You (keyboard)" or "You (controller)" end
      lines[#lines + 1] = { label = pl.name, value = who, color = pl.color, player = p }
   end
   if c.owner then lines[#lines + 1] = { label = "Start match", value = "" } end
   lines[#lines + 1] = { label = "Leave", value = "" }
   draw.setup(lines, lobby_cursor, 60, 140, 560, fonts.body, fonts.big)
   local groups: {draw.KeyGroup} = {
      { title = "Keyboard", keys = { { "Up Down", "choose" }, { "Enter", "take this home" }, { "Backspace", "give it back" }, { "Esc", "leave" } } },
      { title = "Controller", keys = { { "D-pad", "choose" }, { "A", "take this home" }, { "Start", "take a free home" }, { "B / Back", "give it back" } } },
   }
   draw.controls(groups, 60, 900 - 24 - draw.controls_height(groups, 1300, fonts.small, false), 1300, fonts.small, false)
end

function love.draw()
   if menu then return draw_menu() end
   local g = game
   if not g then return draw_lobby() end
   local s = g.state
   local B = s.board

   draw.board(view)

   -- Chunks, the ones that moved last tick drawn back toward where they were.
   local m = g.match
   local progress = g.over and 1 or math.max(0, math.min(1, (g.time - m.last_tick) / (m.next_tick - m.last_tick)))
   for _, chunk in ipairs(s.chunks) do
      local ox, oy = 0.0, 0.0
      if chunk.moved and progress < 1 then
         local sx, sy = draw.step_offset(view, chunk.heading)
         ox, oy = -sx * (1 - progress), -sy * (1 - progress)
      end
      draw.chunk(view, chunk.cells, ox, oy, 1, board.PLAYERS[chunk.owner].color)
   end

   -- Aims: the bots' faintly, the humans' with their headings and ghosts.
   local aims: {integer: draw.Aim} = {}
   if not g.over then
      for p, seat in ipairs(g.seats) do
         local shot = seat.plan
         local aim = seat.aim
         if shot and s.players[p].alive then
            local hex = board.PLAYERS[shot.player].color
            draw.chunk(view, shot.cells, 0, 0, 0.35, hex)
            draw.arrow(view, shot.cells, shot.heading, hex, 0.5)
            aims[shot.player] = {
               slot = shot.slot, heading = shot.heading,
               look = sim.legal(s, shot.player, shot.cells)
                  and sim.ghost(s, shot.player, shot.cells, shot.heading).look or nil,
            }
         end
         if aim and s.players[p].alive then
            local hex = board.PLAYERS[p].color
            local h = controls.heading(seat)
            if aim.pick then
               draw.ghost(view, aim.ghost)
               draw.chunk(view, aim.cells, 0, 0, 0.85, hex)
               if aim.ghost.look == "friendly" then draw.grey(view, aim.cells) end
               draw.arrow(view, aim.cells, h, aim.ghost.look == "clear" and hex or draw.look_color(aim.ghost.look), 1)
               aims[p] = { slot = aim.slot, heading = h, look = aim.ghost.look }
            else
               if aim.cells then draw.misfit(view, aim.cells) end
               aims[p] = { slot = aim.slot, heading = h }
            end
         end
      end
   end

   draw.effects(g.effects, fonts.big)

   -- Header.
   love.graphics.setFont(fonts.title)
   local rr, gg, bb = draw.rgb(draw.INK)
   love.graphics.setColor(rr, gg, bb)
   local alive = sim.alive(s)
   local title = "Match over"
   local humans: {integer} = {}
   for p, seat in ipairs(g.seats) do
      if controls.is_human(seat) and s.players[p].alive then humans[#humans + 1] = p end
   end
   -- Online, a clock runs out when the server's does, a moment before this
   -- copy of the board gets there.
   local clock_time = g.online and client.server_time(net.c) or g.time
   if not g.over and #humans == 1 then
      title = ("Your shot clock %.1f s"):format(match.left(m, humans[1], clock_time) / 1000)
   elseif not g.over then
      local p = match.soonest(m)
      title = ("%s shoots in %.1f s"):format(board.PLAYERS[p].name, match.left(m, p, clock_time) / 1000)
   end
   love.graphics.print(title, 24, 18)
   love.graphics.setFont(fonts.body)
   rr, gg, bb = draw.rgb(draw.MUTED)
   love.graphics.setColor(rr, gg, bb)
   love.graphics.print(("%d chunk%s on the board  -  %d player%s in  -  %d-%d board"):format(
      #s.chunks, #s.chunks == 1 and "" or "s", alive, alive == 1 and "" or "s", 2 * B.n, B.r), 24, 54)

   local groups = legend(g)
   draw.controls(groups, SIDE_X, 18, SIDE_W, fonts.small, true)
   love.graphics.setColor(rr, gg, bb)
   love.graphics.setFont(fonts.small)
   local status = ("seed %d   step %.2fs"):format(g.seed, m.step / 1000)
   if g.online then status = ("online, %d ms round trip   "):format(math.floor(net.c.rtt + 0.5)) .. status end
   love.graphics.print(status, 1440 - 24 - fonts.small:getWidth(status), 900 - 24)

   local tags: {draw.Seat} = {}
   for p, seat in ipairs(g.seats) do
      tags[p] = {
         label = controls.label(seat),
         remote = seat.kind == "remote",
         ready = g.online and net.c.game and net.c.game.ready[p] or false,
      }
   end
   local clocks: {number} = {}
   for p = 1, #s.players do clocks[p] = match.left(m, p, clock_time) / 1000 end
   draw.panels(s, aims, clocks, tags, SIDE_X, 18 + draw.controls_height(groups, SIDE_W, fonts.small, true) + 18,
      SIDE_W, fonts.small, fonts.big)

   -- Each human's queue: the bank chunks either side of the one in use,
   -- turned as they'd go on the board.
   local queues: {draw.Queue} = {}
   for p, seat in ipairs(g.seats) do
      if seat.aim and s.players[p].alive and not g.over then
         local bank = s.players[p].bank
         local n = #bank
         queues[#queues + 1] = {
            player = p,
            left = bc.rotate(bank[(seat.aim.slot - 2) % n + 1], seat.aim.turn),
            right = bc.rotate(bank[seat.aim.slot % n + 1], seat.aim.turn),
            keys = controls.queue_keys(seat.kind),
         }
      end
   end
   draw.queues(view, queues, 24, QUEUE_Y, BOARD_W, QUEUE_H, fonts.body)

   if g.over then
      love.graphics.setColor(1, 1, 1, 0.75)
      love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
      love.graphics.setFont(fonts.title)
      local winner = sim.winner(s)
      if winner then
         rr, gg, bb = draw.rgb(board.PLAYERS[winner].color)
         love.graphics.setColor(rr, gg, bb)
         love.graphics.printf(board.PLAYERS[winner].name .. " wins", 0, 400, love.graphics.getWidth(), "center")
      else
         rr, gg, bb = draw.rgb(draw.INK)
         love.graphics.setColor(rr, gg, bb)
         love.graphics.printf("Draw", 0, 400, love.graphics.getWidth(), "center")
      end
      rr, gg, bb = draw.rgb(draw.MUTED)
      love.graphics.setColor(rr, gg, bb)
      love.graphics.setFont(fonts.body)
      local next_step = "press R for a new match, Esc for the setup screen"
      if g.online then
         next_step = net.c.owner and "press R for a new match, Esc to take everyone back to the lobby"
            or "waiting for the host to start another  -  Esc to leave"
      end
      love.graphics.printf(next_step, 0, 440, love.graphics.getWidth(), "center")
   end
end

--- The lobby screen's rows, for someone who joined: a row per home, then
--- (for the owner of a headless server) Start, then Leave.
local function lobby_rows(): {string}
   local rows: {string} = {}
   for p = 1, #board.PLAYERS do rows[p] = "player" end
   if net.c.owner then rows[#rows + 1] = "start" end
   rows[#rows + 1] = "leave"
   return rows
end

--- On the lobby screen, `slot` (this machine's keyboard or a gamepad)
--- presses select: take the home under the cursor, start, or leave.
local function lobby_select(slot: string)
   local row = lobby_rows()[lobby_cursor]
   if row == "player" then
      client.sit(net.c, slot, lobby_cursor)
   elseif row == "start" then
      client.start(net.c)
   elseif row == "leave" then
      leave_net()
   end
end

local function lobby_key(key: string)
   if key == "up" or key == "w" then
      lobby_cursor = math.max(1, lobby_cursor - 1)
   elseif key == "down" or key == "s" then
      lobby_cursor = math.min(#lobby_rows(), lobby_cursor + 1)
   elseif key == "return" or key == "kpenter" or key == "space" then
      lobby_select("keys")
   elseif key == "backspace" then
      client.stand(net.c, "keys")
   elseif key == "escape" then
      leave_net()
   end
end

local function lobby_button(pad: love.Joystick, button: string)
   local slot = netplay.slot("pad", pad)
   if button == "dpup" then
      lobby_cursor = math.max(1, lobby_cursor - 1)
   elseif button == "dpdown" then
      lobby_cursor = math.min(#lobby_rows(), lobby_cursor + 1)
   elseif button == "a" then
      lobby_select(slot)
   elseif button == "start" then
      client.sit(net.c, slot)
   elseif button == "b" or button == "back" then
      client.stand(net.c, slot)
   end
end

--- A key during a networked match that isn't the keyboard player's.
local function online_key(g: Game, key: string)
   local c = net.c
   if key == "escape" then
      if c.owner then client.to_lobby(c) else leave_net() end
   elseif (key == "space" or key == "return") and not seat_of(g, "keys") then
      client.sit(c, "keys")
   elseif not c.owner then
      return
   elseif key == "r" then
      client.again(c)
   elseif key == "=" or key == "+" or key == "kp+" then
      client.set_step(c, math.max(40, math.floor(g.match.step / 1.5)))
   elseif key == "-" or key == "kp-" then
      client.set_step(c, math.min(2000, math.floor(g.match.step * 1.5)))
   end
end

function love.textinput(text: string)
   if menu then setup.type(menu, text) end
end

function love.quit(): boolean
   if net then netplay.close(net) end
   if headless then server.close(headless) end
   return false
end

function love.keypressed(key: string)
   if menu then return menu_key(key) end
   local g = game
   if not g then
      if net then lobby_key(key) end
      return
   end
   local seat = seat_of(g, "keys")
   local action = controls.key_action(key)
   if seat and action then
      seat_action(g, seat, action)
      controls.hold(seat, action)
   elseif g.online then
      online_key(g, key)
   elseif key == "escape" then
      open_setup()
   elseif (key == "space" or key == "return") and not g.over then
      skip_ahead(g)
   elseif key == "r" then
      game = new_game(next_seed, picks_of(g.seats))
   elseif key == "=" or key == "+" or key == "kp+" then
      match.set_step(g.match, math.max(40, math.floor(g.match.step / 1.5)))
   elseif key == "-" or key == "kp-" then
      match.set_step(g.match, math.min(2000, math.floor(g.match.step * 1.5)))
   end
end

function love.keyreleased(key: string)
   if menu or not game then return end
   local seat = seat_of(game, "keys")
   if seat then controls.release(seat, controls.key_action(key)) end
end

function love.gamepadpressed(pad: love.Joystick, button: string)
   if menu then return menu_button(pad, button) end
   local g = game
   if not g then
      if net then lobby_button(pad, button) end
      return
   end
   local seat = seat_of(g, "pad", pad)
   local action = controls.button_action(button)
   if g.online then
      if not seat and action == "join" then
         client.sit(net.c, netplay.slot("pad", pad))
      elseif seat and action == "leave" then
         client.stand(net.c, netplay.slot("pad", pad))
      elseif seat and action then
         seat_action(g, seat, action)
         controls.hold(seat, action)
      end
   elseif not seat then
      local free = action == "join" and free_seat(g)
      if free then g.seats[free.player] = controls.human(g.state, free.player, "pad", pad) end
   elseif action == "leave" then
      g.seats[seat.player] = controls.bot(g.state, seat.player)
   elseif action then
      seat_action(g, seat, action)
      controls.hold(seat, action)
   end
end

function love.gamepadreleased(pad: love.Joystick, button: string)
   if menu or not game then return end
   local seat = seat_of(game, "pad", pad)
   if seat then controls.release(seat, controls.button_action(button)) end
end

function love.gamepadaxis(pad: love.Joystick, axis: string, value: number)
   if menu then return menu_axis(pad, axis, value) end
   if not game then return end
   local seat = seat_of(game, "pad", pad)
   if not seat then return end
   for _, turn in ipairs(controls.dial_actions(seat, axis, value)) do seat_action(game, seat, turn) end
   local action = controls.flick_action(game.state, seat, axis, value)
   if action then seat_action(game, seat, action) end
end

--- An unplugged gamepad's player goes back to a bot.
function love.joystickremoved(pad: love.Joystick)
   if menu then return setup.leave(menu, "pad", pad) end
   if net then client.stand(net.c, netplay.slot("pad", pad)) end
   if not game or game.online then return end
   local seat = seat_of(game, "pad", pad)
   if seat then game.seats[seat.player] = controls.bot(game.state, seat.player) end
end
