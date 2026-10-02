--- Blunkychunks in LOVE: you play Player 1 (the southwest home) on the
--- keyboard against two random bots, or with --bots three bots play each
--- other. A gamepad joins by pressing Start, taking over the first bot's home,
--- and Back hands it back; several can play at once (see controls.tl).
---
---   make run                          # build and launch on the 22-8 board
---   make run DIAMETER=12 NOTCH=5      # any other notched board
---   make bots                         # an all-bot match
---   make run ARGS="--seed 42"         # a reproducible match
---   make run ARGS="--fast"            # a 2 second shot clock
---   make run ARGS="--size 8"          # chunks of 8 triangles
---   make run ARGS="--shot out.png"    # screenshot after a few seconds, then quit
---
--- Play is continuous: chunks slide one step per tick while every player's
--- shot clock counts down. The clocks are staggered, so they run out in turn,
--- and each time one does that player's aim fires. Keys and buttons are
--- listed on screen (see `legend`).

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local controls = require("controls")
local draw = require("draw")

local record Fonts
   small: love.Font
   body: love.Font
   big: love.Font
   title: love.Font
end

local record Game
   state: sim.State
   over: boolean
   clocks: {number} -- per player: seconds left on their shot clock
   tick_timer: number
   step_seconds: number
   seed: integer
   effects: {draw.Effect}
   seats: {controls.Seat} -- per player: who plays them
   shot_path: string
   shot_after: number
end

local SHOT_SECONDS <const> = 8.0
local STEP_SECONDS <const> = 0.28

local view: draw.View
local fonts: Fonts
local game: Game
local shot_seconds = SHOT_SECONDS
local keyboard = true -- whether the keyboard starts out playing Player 1
local board_n, board_r = 11, 8
local chunk_size = 14

local function effect(g: Game, i: integer, text: string, hex: string, life: number)
   local B = g.state.board
   local p = board.centroid(B.a[i], B.b[i], view.side)
   local r, gg, b = draw.rgb(hex)
   g.effects[#g.effects + 1] = {
      x = view.cx + p.x - 6, y = view.cy + p.y - 9, text = text,
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

local function do_tick(g: Game)
   local r = sim.tick(g.state)
   for _, t in ipairs(r.cleared) do effect(g, t.i, "x", bc.FILL[t.color], 0.7) end
   for _, t in ipairs(r.hits) do effect(g, t.i, "!", draw.DANGER, 1.2) end
   for _, p in ipairs(r.out) do out_effect(g, p) end
   check_over(g)
   if not g.over then
      for _, seat in ipairs(g.seats) do controls.update(g.state, seat) end
   end
end

--- Player `p`'s shot clock ran out: fire their seat's aim.
local function lock_in(g: Game, p: integer)
   local s = g.state
   local seat = g.seats[p]
   local r = sim.lock_in(s, p, controls.shot(s, seat))
   for _, t in ipairs(r.cleared) do effect(g, t.i, "x", bc.FILL[t.color], 0.7) end
   if r.out then out_effect(g, p) end
   check_over(g)
   if g.over then return end
   controls.fired(s, seat, r)
   for _, other in ipairs(g.seats) do controls.update(s, other) end
end

--- Run the shot clocks down by `dt`, firing each one that runs out in turn.
local function run_clocks(g: Game, dt: number)
   for _, p in ipairs(sim.run_down(g.state, g.clocks, dt, shot_seconds)) do
      if g.over then return end
      lock_in(g, p)
   end
end

--- The live player whose shot clock runs out next.
local function soonest(g: Game): integer
   local best: integer
   for p, pl in ipairs(g.state.players) do
      if pl.alive and (not best or g.clocks[p] < g.clocks[best]) then best = p end
   end
   return best
end

--- Fire now: skip the clocks ahead to when player `p`'s runs out (if `p`
--- is nil or out, the next one to), so any that would run out first fire first.
local function skip_ahead(g: Game, p?: integer)
   if not (p and g.state.players[p].alive) then p = soonest(g) end
   if p then run_clocks(g, g.clocks[p]) end
end

--- Who plays each player, as `seats` (or, for a first match, the keyboard
--- on Player 1 unless it's all bots) left them.
local function seat_all(state: sim.State, seats?: {controls.Seat}): {controls.Seat}
   local out: {controls.Seat} = {}
   for p = 1, #state.players do
      local was = seats and seats[p]
      if was and controls.is_human(was) then
         out[p] = controls.human(state, p, was.kind, was.pad)
      elseif not seats and keyboard and p == 1 then
         out[p] = controls.human(state, p, "keys")
      else
         out[p] = controls.bot(state, p)
      end
   end
   return out
end

local function new_game(seed: integer, seats?: {controls.Seat}): Game
   local B = board.new(board_n, board_r)
   view = draw.layout(B, 24, 92, 1440 - 24 - 470, 900 - 92 - 112)
   local g: Game = {
      state = sim.new(B, chunk_size, bc.seeded_random(seed)),
      over = false,
      clocks = sim.clocks(shot_seconds),
      tick_timer = 0,
      step_seconds = STEP_SECONDS,
      seed = seed,
      effects = {},
   }
   g.seats = seat_all(g.state, seats)
   return g
end

local function flag(args: {string}, name: string): string
   for i, a in ipairs(args) do
      if a == name then return args[i + 1] or "" end
   end
   return nil
end

function love.load(args: {string})
   draw.background()
   fonts = {
      small = love.graphics.newFont(12),
      body = love.graphics.newFont(15),
      big = love.graphics.newFont(20),
      title = love.graphics.newFont(26),
   }
   board_n, board_r = board.options(args)
   chunk_size = math.floor(tonumber(flag(args, "--size") or "") or chunk_size)
   local seed = tonumber(flag(args, "--seed") or "") or os.time()
   if flag(args, "--fast") then shot_seconds = 2.0 end
   if flag(args, "--bots") then keyboard = false end
   game = new_game(math.floor(seed))
   local shot = flag(args, "--shot")
   if shot then
      game.shot_path = shot
      game.shot_after = tonumber(flag(args, "--after") or "") or 3.0
   end
end

function love.update(dt: number)
   local g = game
   for i = #g.effects, 1, -1 do
      g.effects[i].life = g.effects[i].life - dt
      if g.effects[i].life <= 0 then table.remove(g.effects, i) end
   end

   if not g.over then
      run_clocks(g, dt)
      g.tick_timer = g.tick_timer + dt
      while not g.over and g.tick_timer >= g.step_seconds do
         g.tick_timer = g.tick_timer - g.step_seconds
         do_tick(g)
      end
   end

   if g.shot_path then
      g.shot_after = g.shot_after - dt
      if g.shot_after <= 0 then
         love.graphics.captureScreenshot(g.shot_path)
         g.shot_path = nil
         love.event.quit()
      end
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
      if seat.kind == "bot" and (g.over or g.state.players[p].alive) then return seat end
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
            keys = controls.legend(kind),
         }
      end
   end
   local free = free_seat(g)
   if free then
      local who = board.PLAYERS[free.player].name
      local hint = idle_pads() > 0 and ("join as " .. who) or ("plug one in and press Start to join as " .. who)
      groups[#groups + 1] = { title = "Controller", keys = { { "Start", hint } } }
   end
   local game_keys: {{string, string}} = { { "+ / -", "slide speed" }, { "R", "new match" }, { "Esc", "quit" } }
   if not seat_of(g, "keys") then table.insert(game_keys, 1, { "Space", "skip to the next shot" }) end
   groups[#groups + 1] = { title = "Game", keys = game_keys }
   return groups
end

function love.draw()
   local g = game
   local s = g.state
   local B = s.board

   draw.board(view)

   -- Chunks, the ones that moved last tick drawn back toward where they were.
   local progress = g.over and 1 or math.min(1, g.tick_timer / g.step_seconds)
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
   if not g.over and #humans == 1 then
      title = ("Your shot clock %.1f s"):format(math.max(0, g.clocks[humans[1]]))
   elseif not g.over then
      local p = soonest(g)
      title = ("%s shoots in %.1f s"):format(board.PLAYERS[p].name, math.max(0, g.clocks[p]))
   end
   love.graphics.print(title, 24, 18)
   love.graphics.setFont(fonts.body)
   rr, gg, bb = draw.rgb(draw.MUTED)
   love.graphics.setColor(rr, gg, bb)
   love.graphics.print(("%d chunk%s on the board  -  %d player%s in  -  %d-%d board"):format(
      #s.chunks, #s.chunks == 1 and "" or "s", alive, alive == 1 and "" or "s", 2 * B.n, B.r), 24, 54)

   draw.controls(legend(g), 24, 900 - 12, 940, fonts.small)
   love.graphics.setColor(rr, gg, bb)
   love.graphics.setFont(fonts.small)
   love.graphics.print(("seed %d   step %.2fs"):format(g.seed, g.step_seconds), 1440 - 180, 900 - 24)

   local tags: {draw.Seat} = {}
   for p, seat in ipairs(g.seats) do
      tags[p] = { label = controls.label(seat), slots = controls.slot_keys(seat.kind) }
   end
   draw.panels(s, aims, g.clocks, tags, 1440 - 446, 92, 422, fonts.small, fonts.big)

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
      love.graphics.printf("press R for a new match", 0, 440, love.graphics.getWidth(), "center")
   end
end

--- `action` from `seat`'s controller: aim, or fire now.
local function seat_action(g: Game, seat: controls.Seat, action: controls.Action)
   if g.over then return end
   if action == "fire" then
      skip_ahead(g, seat.player)
   else
      controls.act(g.state, seat, action)
   end
end

function love.keypressed(key: string)
   local g = game
   local seat = seat_of(g, "keys")
   local action = controls.key_action(key)
   if seat and action then
      seat_action(g, seat, action)
   elseif key == "escape" then
      love.event.quit()
   elseif (key == "space" or key == "return") and not g.over then
      skip_ahead(g)
   elseif key == "r" then
      game = new_game(g.seed + 1, g.seats)
   elseif key == "=" or key == "+" or key == "kp+" then
      g.step_seconds = math.max(0.04, g.step_seconds / 1.5)
   elseif key == "-" or key == "kp-" then
      g.step_seconds = math.min(2, g.step_seconds * 1.5)
   end
end

function love.gamepadpressed(pad: love.Joystick, button: string)
   local g = game
   local seat = seat_of(g, "pad", pad)
   local action = controls.button_action(button)
   if not seat then
      local free = action == "join" and free_seat(g)
      if free then g.seats[free.player] = controls.human(g.state, free.player, "pad", pad) end
   elseif action == "leave" then
      g.seats[seat.player] = controls.bot(g.state, seat.player)
   elseif action then
      seat_action(g, seat, action)
   end
end

function love.gamepadaxis(pad: love.Joystick, axis: string, value: number)
   local seat = seat_of(game, "pad", pad)
   if not seat then return end
   local action = controls.axis_action(seat, axis, value)
   if action then seat_action(game, seat, action) end
end

--- An unplugged gamepad's player goes back to a bot.
function love.joystickremoved(pad: love.Joystick)
   local seat = seat_of(game, "pad", pad)
   if seat then game.seats[seat.player] = controls.bot(game.state, seat.player) end
end
