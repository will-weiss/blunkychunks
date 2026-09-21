--- Blunkychunks in LOVE: three random bots play each other.
---
---   make run                       # build and launch
---   make run ARGS="--seed 42"      # a reproducible match
---   make run ARGS="--fast"         # 1 second placement phase
---   make run ARGS="--shot out.png" # screenshot after a few seconds, then quit
---
--- Keys: space skips the countdown, +/- change slide speed, R restarts,
--- escape quits.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local bots = require("bots")
local draw = require("draw")

local enum Phase
   "placing"
   "sliding"
   "over"
end

local record Fonts
   small: love.Font
   body: love.Font
   big: love.Font
   title: love.Font
end

local record Game
   state: sim.State
   phase: Phase
   timer: number
   pending: {sim.Shot}
   tick_timer: number
   step_seconds: number
   seed: integer
   winner: integer
   effects: {draw.Effect}
   phase_moves: integer
   stalemate: boolean
   shot_path: string
   shot_after: number
end

local N <const> = 11
local SIZE <const> = 14
local PLACE_SECONDS <const> = 8.0
local STEP_SECONDS <const> = 0.28

local view: draw.View = { n = N, side = 30, cx = 400, cy = 400 }
local fonts: Fonts
local game: Game
local place_seconds = PLACE_SECONDS

--- Start a placement phase. If nobody can place anything and the last slide
--- moved nothing either, the board is jammed for good: call it a stalemate.
local function begin_placing(g: Game)
   g.pending = bots.plan(g.state)
   if #g.pending == 0 and g.phase_moves == 0 and #g.state.chunks > 0 then
      g.phase = "over"
      g.stalemate = true
      return
   end
   g.phase = "placing"
   g.timer = place_seconds
end

local function new_game(seed: integer): Game
   local g: Game = {
      state = sim.new(N, SIZE, bc.seeded_random(seed)),
      phase = "placing",
      timer = 0,
      pending = {},
      tick_timer = 0,
      step_seconds = STEP_SECONDS,
      seed = seed,
      winner = nil,
      effects = {},
      phase_moves = -1,
      stalemate = false,
   }
   begin_placing(g)
   return g
end

local function flag(args: {string}, name: string): string
   for i, a in ipairs(args) do
      if a == name then return args[i + 1] or "" end
   end
   return nil
end

--- Apply one simulation tick and spawn effects for what happened.
local function do_tick(g: Game)
   local r = sim.tick(g.state)
   g.phase_moves = g.phase_moves + r.moved
   for _, hit in ipairs(r.hits) do
      local p = board.centroid(hit.cell.a, hit.cell.b, view.side)
      local pl = board.PLAYERS[hit.owner]
      local rr, gg, bb = draw.rgb(hit.victim and pl.color or draw.MUTED)
      g.effects[#g.effects + 1] = {
         x = view.cx + p.x - 6, y = view.cy + p.y - 8,
         text = hit.victim and "-1" or "~",
         r = rr, g = gg, b = bb, ttl = 0.9, life = 0.9,
      }
   end
   for _, c in ipairs(r.cleared) do
      local p = board.centroid(c.a, c.b, view.side)
      local rr, gg, bb = draw.rgb(bc.FILL[c.color])
      g.effects[#g.effects + 1] = {
         x = view.cx + p.x - 4, y = view.cy + p.y - 8,
         text = "x", r = rr, g = gg, b = bb, ttl = 0.7, life = 0.7,
      }
   end
   if r.moved == 0 then
      g.winner = sim.winner(g.state)
      if g.winner then
         g.phase = "over"
      else
         sim.end_turn(g.state)
         begin_placing(g)
      end
   end
end

local function lock_in(g: Game)
   sim.fire(g.state, g.pending)
   g.pending = {}
   g.phase = "sliding"
   g.tick_timer = 0
   g.phase_moves = 0
   do_tick(g)
end

function love.load(args: {string})
   draw.background()
   fonts = {
      small = love.graphics.newFont(12),
      body = love.graphics.newFont(15),
      big = love.graphics.newFont(20),
      title = love.graphics.newFont(26),
   }
   local seed = tonumber(flag(args, "--seed") or "") or os.time()
   if flag(args, "--fast") then place_seconds = 1.0 end
   local shot = flag(args, "--shot")
   game = new_game(math.floor(seed))
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

   if g.phase == "placing" then
      g.timer = g.timer - dt
      if g.timer <= 0 then lock_in(g) end
   elseif g.phase == "sliding" then
      g.tick_timer = g.tick_timer + dt
      while g.phase == "sliding" and g.tick_timer >= g.step_seconds do
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

local function turn_label(turn: board.Turn): string
   return turn == "A" and "Turn A - clockwise" or "Turn B - counterclockwise"
end

function love.draw()
   local g = game
   local s = g.state

   draw.grid(view)

   -- Chunks on the board, sliding ones interpolated back toward where they were.
   local progress = g.phase == "sliding" and math.min(1, g.tick_timer / g.step_seconds) or 1
   for _, chunk in ipairs(s.chunks) do
      local ox, oy = 0.0, 0.0
      if chunk.moved and progress < 1 then
         local o = bc.centroid(0, 0, view.side)
         local p = bc.centroid(chunk.step.a, chunk.step.b, view.side)
         ox, oy = -(p.x - o.x) * (1 - progress), -(p.y - o.y) * (1 - progress)
      end
      draw.chunk(view, chunk.cells, ox, oy, 1, board.PLAYERS[chunk.owner].color)
   end

   -- Pending shots as ghosts with their headings.
   if g.phase == "placing" then
      for _, shot in ipairs(g.pending) do
         local owner = board.PLAYERS[shot.player].color
         draw.chunk(view, shot.cells, 0, 0, 0.45, owner)
         draw.arrow(view, shot.cells, board.fire_dir(shot.player, s.turn), owner, 0.8)
      end
   end

   draw.walls(view, s.turn)
   draw.effects(g.effects, fonts.big)

   -- Header.
   love.graphics.setFont(fonts.title)
   local rr, gg, bb = draw.rgb(draw.INK)
   love.graphics.setColor(rr, gg, bb)
   love.graphics.print(("Round %d  -  %s"):format(s.round, turn_label(s.turn)), 24, 18)

   love.graphics.setFont(fonts.body)
   rr, gg, bb = draw.rgb(draw.MUTED)
   love.graphics.setColor(rr, gg, bb)
   local status: string
   if g.phase == "placing" then
      status = ("placing - firing in %.1fs   (space to fire now)"):format(math.max(0, g.timer))
   elseif g.phase == "sliding" then
      status = ("sliding - %d chunk%s on the board"):format(#s.chunks, #s.chunks == 1 and "" or "s")
   elseif g.stalemate then
      status = "stalemate - the board is jammed and nothing fits against any wall"
   else
      status = "game over"
   end
   love.graphics.print(status, 24, 52)
   love.graphics.print(("seed %d   step %.2fs (+/-)   R restart"):format(g.seed, g.step_seconds), 24, 770)

   draw.panels(s, g.pending, g.phase == "placing", 830, 100, 420, fonts.small, fonts.big)

   if g.phase == "over" then
      love.graphics.setColor(1, 1, 1, 0.75)
      love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
      love.graphics.setFont(fonts.title)
      if g.winner then
         local pl = board.PLAYERS[g.winner]
         rr, gg, bb = draw.rgb(pl.color)
         love.graphics.setColor(rr, gg, bb)
         love.graphics.printf(pl.name .. " wins", 0, 360, love.graphics.getWidth(), "center")
      else
         rr, gg, bb = draw.rgb(draw.INK)
         love.graphics.setColor(rr, gg, bb)
         love.graphics.printf("Stalemate", 0, 360, love.graphics.getWidth(), "center")
      end
      rr, gg, bb = draw.rgb(draw.MUTED)
      love.graphics.setColor(rr, gg, bb)
      love.graphics.setFont(fonts.body)
      love.graphics.printf("press R for a new match", 0, 400, love.graphics.getWidth(), "center")
   end
end

function love.keypressed(key: string)
   local g = game
   if key == "escape" then
      love.event.quit()
   elseif key == "space" and g.phase == "placing" then
      lock_in(g)
   elseif key == "r" then
      game = new_game(g.seed + 1)
   elseif key == "=" or key == "+" or key == "kp+" then
      g.step_seconds = math.max(0.04, g.step_seconds / 1.5)
   elseif key == "-" or key == "kp-" then
      g.step_seconds = math.min(2, g.step_seconds * 1.5)
   end
end
