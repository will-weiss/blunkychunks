--- Blunkychunks in LOVE: you play Player 1 (the southwest home) against two
--- random bots, or with --bots three bots play each other.
---
---   make run                          # build and launch on the 22-8 board
---   make run DIAMETER=12 NOTCH=5      # any other notched board
---   make bots                         # an all-bot match
---   make run ARGS="--seed 42"         # a reproducible match
---   make run ARGS="--fast"            # a 2 second shot clock
---   make run ARGS="--size 8"          # chunks of 8 triangles
---   make run ARGS="--shot out.png"    # screenshot after a few seconds, then quit
---
--- Play is continuous: chunks slide one step per tick while the shot clock
--- counts down, and each time it runs out every player's aim fires at once.
--- Keys are listed on screen (see `controls`).

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local bots = require("bots")
local draw = require("draw")

local record Fonts
   small: love.Font
   body: love.Font
   big: love.Font
   title: love.Font
end

--- The human's aim. `want` is the spot they last chose, as the Eisenstein sum
--- of its triangles' coordinates over `count` triangles, so the aim stays put
--- (as near as it can) while chunks move and while they rotate.
local record Aim
   slot: integer
   turn: integer -- rotation, 0..5 sixths of a turn counterclockwise
   heading: integer -- which of the player's three headings, 1..3
   want: bc.AB
   count: integer
   spots: {board.Spot} -- legal spots for this chunk and rotation, along the back wall
   pick: integer -- the spot in use, or nil when the chunk fits nowhere
   shape: board.Shape
   cells: {board.Tri} -- the aim's triangles (or where it would be, if it fits nowhere)
   ghost: sim.Ghost
end

local record Game
   state: sim.State
   over: boolean
   clock: number -- seconds left on the shot clock
   tick_timer: number
   step_seconds: number
   seed: integer
   effects: {draw.Effect}
   bot_shots: {sim.Shot}
   shot_path: string
   shot_after: number
   human: boolean
   aim: Aim
end

local SHOT_SECONDS <const> = 8.0
local STEP_SECONDS <const> = 0.28
local HUMAN <const> = 1

local view: draw.View
local fonts: Fonts
local game: Game
local shot_seconds = SHOT_SECONDS
local human_mode = true
local board_n, board_r = 11, 8
local chunk_size = 14

local function skip(g: Game): {integer: boolean}
   return g.human and { [HUMAN] = true } or nil
end

--- Sums of the Eisenstein coordinates of `cells`.
local function centre(B: board.Board, cells: {board.Tri}): bc.AB
   local a, b = 0, 0
   for _, t in ipairs(cells) do a, b = a + B.a[t.i], b + B.b[t.i] end
   return { a = a, b = b }
end

--- Squared distance (times count^2) between two centroids given as sums, by
--- the Eisenstein norm N(x + yw) = x^2 - xy + y^2. Exact.
local function far(u: bc.AB, nu: integer, v: bc.AB, nv: integer): integer
   local x, y = u.a * nv - v.a * nu, u.b * nv - v.b * nu
   return x * x - x * y + y * y
end

--- Put `spots` in order along the back wall, counterclockwise as drawn round
--- the board's centre z = 1. Every home lies within a 120 degree sector of
--- it, so the sign of the cross product orders them. Exact.
local function along_wall(B: board.Board, shape: board.Shape, spots: {board.Spot}): {board.Spot}
   local k = #shape.cells
   local key: {board.Spot: bc.AB} = {}
   for _, s in ipairs(spots) do
      local c = centre(B, board.place(B, shape, s.x, s.y))
      key[s] = { a = c.a - k, b = c.b }
   end
   table.sort(spots, function(p: board.Spot, q: board.Spot): boolean
      local u, v = key[p], key[q]
      local cross = u.a * v.b - u.b * v.a
      if cross ~= 0 then return cross > 0 end
      if p.y ~= q.y then return p.y < q.y end
      return p.x < q.x
   end)
   return spots
end

--- Recompute the human's aim against the board as it is now.
local function refresh_aim(g: Game)
   local aim = g.aim
   if not aim or not g.state.players[HUMAN].alive then return end
   local B = g.state.board
   local chunk = g.state.players[HUMAN].bank[aim.slot]
   aim.shape = board.shape(B, bc.rotate(chunk, aim.turn))
   aim.spots = along_wall(B, aim.shape, sim.placements(g.state, HUMAN, aim.shape))
   aim.pick = nil
   local best = math.huge
   for i, s in ipairs(aim.spots) do
      local d = aim.want and far(centre(B, board.place(B, aim.shape, s.x, s.y)), #aim.shape.cells, aim.want, aim.count)
         or math.abs(i - (#aim.spots + 1) / 2)
      if d < best then best, aim.pick = d, i end
   end
   local h = board.HEADINGS[HUMAN][aim.heading]
   if aim.pick then
      local s = aim.spots[aim.pick]
      aim.cells = board.place(B, aim.shape, s.x, s.y)
      aim.ghost = sim.ghost(g.state, HUMAN, aim.cells, h)
      if not aim.want then aim.want, aim.count = centre(B, aim.cells), #aim.cells end
   else
      aim.ghost = nil
   end
end

--- Choose spot `i` of the current list as the one to hold on to.
local function choose_spot(g: Game, i: integer)
   local aim = g.aim
   local s = aim.spots[i]
   if not s then return end
   local cells = board.place(g.state.board, aim.shape, s.x, s.y)
   aim.want, aim.count = centre(g.state.board, cells), #cells
   refresh_aim(g)
end

--- The human's shot as aimed, or nil when it fits nowhere.
local function human_shot(g: Game): sim.Shot
   local aim = g.aim
   if not g.human or not aim or not aim.pick then return nil end
   return { player = HUMAN, slot = aim.slot, heading = board.HEADINGS[HUMAN][aim.heading], cells = aim.cells }
end

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
   if not g.over then refresh_aim(g) end
end

local function lock_in(g: Game)
   local shots = bots.refresh(g.state, g.bot_shots, skip(g))
   local mine = human_shot(g)
   if mine then shots[#shots + 1] = mine end
   local r = sim.lock_in(g.state, shots)
   for _, t in ipairs(r.cleared) do effect(g, t.i, "x", bc.FILL[t.color], 0.7) end
   for _, p in ipairs(r.out) do out_effect(g, p) end
   g.clock = shot_seconds
   check_over(g)
   if g.over then return end
   g.bot_shots = bots.plan(g.state, skip(g))
   if g.aim and g.aim.want and mine then
      -- The chunk just fired; aim the next one from the same place.
      g.aim.want, g.aim.count = centre(g.state.board, mine.cells), #mine.cells
   end
   refresh_aim(g)
end

local function new_game(seed: integer): Game
   local B = board.new(board_n, board_r)
   view = draw.layout(B, 24, 92, 1440 - 24 - 470, 900 - 92 - 112)
   local g: Game = {
      state = sim.new(B, chunk_size, bc.seeded_random(seed)),
      over = false,
      clock = shot_seconds,
      tick_timer = 0,
      step_seconds = STEP_SECONDS,
      seed = seed,
      effects = {},
      bot_shots = {},
      human = human_mode,
   }
   g.bot_shots = bots.plan(g.state, skip(g))
   if g.human then
      g.aim = { slot = 1, turn = 0, heading = 2 }
      refresh_aim(g)
   end
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
   if flag(args, "--bots") then human_mode = false end
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
      g.clock = g.clock - dt
      if g.clock <= 0 then lock_in(g) end
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

--- Every key the game listens to, grouped for the on-screen legend.
local function controls(g: Game): {draw.KeyGroup}
   local groups: {draw.KeyGroup} = {}
   if g.human then
      groups[#groups + 1] = {
         title = "You (" .. board.PLAYERS[HUMAN].name .. ")",
         keys = {
            { "1 2 3", "pick chunk" },
            { "Q / E", "rotate" },
            { "Left Right / A D", "slide along your back wall" },
            { "Up Down / Tab", "heading" },
            { "Space / Enter", "fire now" },
         },
      }
   else
      groups[#groups + 1] = { title = "Bots", keys = { { "Space", "fire now" } } }
   end
   groups[#groups + 1] = {
      title = "Game",
      keys = { { "+ / -", "slide speed" }, { "R", "new match" }, { "Esc", "quit" } },
   }
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

   -- Aims: the bots' faintly, the human's with its heading and ghost.
   local aims: {integer: draw.Aim} = {}
   if not g.over then
      for _, shot in ipairs(g.bot_shots) do
         if s.players[shot.player].alive then
            local hex = board.PLAYERS[shot.player].color
            draw.chunk(view, shot.cells, 0, 0, 0.35, hex)
            draw.arrow(view, shot.cells, shot.heading, hex, 0.5)
            aims[shot.player] = {
               slot = shot.slot, heading = shot.heading,
               look = sim.legal(s, shot.player, shot.cells)
                  and sim.ghost(s, shot.player, shot.cells, shot.heading).look or nil,
            }
         end
      end
      local aim = g.aim
      if g.human and aim and s.players[HUMAN].alive then
         local hex = board.PLAYERS[HUMAN].color
         local h = board.HEADINGS[HUMAN][aim.heading]
         if aim.pick then
            draw.ghost(view, aim.ghost.cells, aim.ghost.look)
            draw.chunk(view, aim.cells, 0, 0, 0.85, hex)
            if aim.ghost.look == "friendly" then draw.grey(view, aim.cells) end
            draw.arrow(view, aim.cells, h, aim.ghost.look == "clear" and hex or draw.look_color(aim.ghost.look), 1)
            aims[HUMAN] = { slot = aim.slot, heading = h, look = aim.ghost.look }
         else
            if aim.cells then draw.misfit(view, aim.cells) end
            aims[HUMAN] = { slot = aim.slot, heading = h }
         end
      end
   end

   draw.effects(g.effects, fonts.big)

   -- Header.
   love.graphics.setFont(fonts.title)
   local rr, gg, bb = draw.rgb(draw.INK)
   love.graphics.setColor(rr, gg, bb)
   local alive = sim.alive(s)
   love.graphics.print(g.over and "Match over" or ("Shot clock %.1f s"):format(math.max(0, g.clock)), 24, 18)
   love.graphics.setFont(fonts.body)
   rr, gg, bb = draw.rgb(draw.MUTED)
   love.graphics.setColor(rr, gg, bb)
   love.graphics.print(("%d chunk%s on the board  -  %d player%s in  -  %d-%d board"):format(
      #s.chunks, #s.chunks == 1 and "" or "s", alive, alive == 1 and "" or "s", 2 * B.n, B.r), 24, 54)

   draw.controls(controls(g), 24, 900 - 96, 940, fonts.small)
   love.graphics.setColor(rr, gg, bb)
   love.graphics.setFont(fonts.small)
   love.graphics.print(("seed %d   step %.2fs"):format(g.seed, g.step_seconds), 1440 - 180, 900 - 24)

   draw.panels(s, aims, 1440 - 446, 92, 422, fonts.small, fonts.big, g.human and HUMAN or nil)

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

--- Aiming keys for the human. Returns true if the key was handled.
local function human_key(g: Game, key: string): boolean
   local aim = g.aim
   if not g.human or g.over or not aim or not g.state.players[HUMAN].alive then return false end
   local slot = tonumber(key) or tonumber(key:match("^kp(%d)$") or "")
   if slot and slot >= 1 and slot <= sim.BANK then
      aim.slot = math.floor(slot)
      refresh_aim(g)
   elseif key == "q" then
      aim.turn = (aim.turn + 1) % 6
      refresh_aim(g)
   elseif key == "e" then
      aim.turn = (aim.turn + 5) % 6
      refresh_aim(g)
   elseif key == "left" or key == "a" then
      if aim.pick then choose_spot(g, math.max(1, aim.pick - 1)) end
   elseif key == "right" or key == "d" then
      if aim.pick then choose_spot(g, math.min(#aim.spots, aim.pick + 1)) end
   elseif key == "up" or key == "tab" then
      aim.heading = aim.heading % 3 + 1
      refresh_aim(g)
   elseif key == "down" then
      aim.heading = (aim.heading + 1) % 3 + 1
      refresh_aim(g)
   elseif key == "return" or key == "kpenter" then
      lock_in(g)
   else
      return false
   end
   return true
end

function love.keypressed(key: string)
   local g = game
   if human_key(g, key) then return end
   if key == "escape" then
      love.event.quit()
   elseif key == "space" and not g.over then
      lock_in(g)
   elseif key == "r" then
      game = new_game(g.seed + 1)
   elseif key == "=" or key == "+" or key == "kp+" then
      g.step_seconds = math.max(0.04, g.step_seconds / 1.5)
   elseif key == "-" or key == "kp-" then
      g.step_seconds = math.min(2, g.step_seconds * 1.5)
   end
end
