--- Blunkychunks in LOVE: you play Player 1 against two random bots, or (with
--- --bots) three bots play each other.
---
---   make run                       # build and launch, you are Player 1
---   make bots                      # build and launch an all-bot match
---   make run ARGS="--seed 42"      # a reproducible match
---   make run ARGS="--fast"         # 1 second placement phase
---   make run ARGS="--shot out.png" # screenshot after a few seconds, then quit
---
--- Keys are listed on screen (see `controls`).

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

   -- The human's pick for this turn (Player 1 unless --bots).
   human: boolean
   sel_slot: integer
   sel_wall: integer
   spots: {bc.AB}
   sel_spot: integer
   passing: boolean
end

local N <const> = 11
local SIZE <const> = 14
local PLACE_SECONDS <const> = 8.0
local STEP_SECONDS <const> = 0.28

local HUMAN <const> = 1

local view: draw.View = { n = N, side = 30, cx = 400, cy = 400 }
local fonts: Fonts
local game: Game
local place_seconds = PLACE_SECONDS
local human_mode = true

--- Recompute where the human's selected chunk fits against the selected wall,
--- ordered left to right on screen (screen x grows with b). Keeps the spot
--- nearest the previous one when there was one.
local function refresh_spots(g: Game)
   local prev = g.spots and g.spots[g.sel_spot]
   local wall = board.launch_walls(HUMAN, g.state.turn)[g.sel_wall]
   local chunk = g.state.players[HUMAN].bank[g.sel_slot]
   local spots = board.placements(N, chunk, wall, sim.blocked_set(g.state, g.pending))
   table.sort(spots, function(x: bc.AB, y: bc.AB): boolean
      if x.b ~= y.b then return x.b < y.b end
      return x.a < y.a
   end)
   g.spots = spots
   g.sel_spot = math.max(1, math.floor((#spots + 1) / 2))
   if prev then
      local best = math.huge
      for i, t in ipairs(spots) do
         local d = math.abs(t.b - prev.b)
         if d < best then best, g.sel_spot = d, i end
      end
   end
end

--- The human's shot as currently selected, or nil if passing / nothing fits.
local function human_shot(g: Game): sim.Shot
   if not g.human or g.passing or g.phase ~= "placing" then return nil end
   local t = g.spots[g.sel_spot]
   if not t then return nil end
   return {
      player = HUMAN,
      wall = board.launch_walls(HUMAN, g.state.turn)[g.sel_wall],
      slot = g.sel_slot,
      cells = board.translate(g.state.players[HUMAN].bank[g.sel_slot], t),
   }
end

--- Bot shots plus the human's, i.e. everything that fires on lock-in.
local function all_shots(g: Game): {sim.Shot}
   local out: {sim.Shot} = {}
   for i, shot in ipairs(g.pending) do out[i] = shot end
   local mine = human_shot(g)
   if mine then out[#out + 1] = mine end
   return out
end

--- Start the human's turn on the first chunk/wall that fits, own wall first.
local function begin_human(g: Game)
   g.passing = false
   g.spots = nil
   for _, w in ipairs({ g.sel_wall or 1, 3 - (g.sel_wall or 1) }) do
      for slot = 1, sim.BANK do
         g.sel_slot, g.sel_wall = slot, w
         refresh_spots(g)
         if #g.spots > 0 then return end
      end
   end
end

--- Start a placement phase. If nobody can place anything and the last slide
--- moved nothing either, the board is jammed for good: call it a stalemate.
local function begin_placing(g: Game)
   g.pending = bots.plan(g.state, g.human and { [HUMAN] = true } or nil)
   g.phase = "placing"
   if g.human then begin_human(g) end
   if #all_shots(g) == 0 and g.phase_moves == 0 and #g.state.chunks > 0 then
      g.phase = "over"
      g.stalemate = true
      return
   end
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
      human = human_mode,
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
   sim.fire(g.state, all_shots(g))
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
   if flag(args, "--bots") then human_mode = false end
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

--- Every key the game listens to, grouped for the on-screen legend.
local function controls(g: Game): {draw.KeyGroup}
   local groups: {draw.KeyGroup} = {}
   if g.human then
      groups[#groups + 1] = {
         title = "You (" .. board.PLAYERS[HUMAN].name .. ")",
         keys = {
            { "1 2 3", "pick chunk" },
            { "W / Tab", "own / loaned wall" },
            { "Left Right / A D", "slide along wall" },
            { "X", g.passing and "unpass" or "pass" },
            { "Space / Enter", "fire now" },
         },
      }
   else
      groups[#groups + 1] = { title = "Bots", keys = { { "Space", "skip countdown" } } }
   end
   groups[#groups + 1] = {
      title = "Game",
      keys = {
         { "+ / -", "slide speed" },
         { "R", "new match" },
         { "Esc", "quit" },
      },
   }
   return groups
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

   -- Pending shots as ghosts with their headings; the human's stands out.
   local shots = all_shots(g)
   if g.phase == "placing" then
      for _, shot in ipairs(shots) do
         local owner = board.PLAYERS[shot.player].color
         local mine = g.human and shot.player == HUMAN
         draw.chunk(view, shot.cells, 0, 0, mine and 0.75 or 0.45, owner)
         draw.arrow(view, shot.cells, board.fire_dir(shot.player, s.turn), owner, mine and 1 or 0.8)
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

   draw.controls(controls(g), 24, 704, 780, fonts.small)
   rr, gg, bb = draw.rgb(draw.MUTED)
   love.graphics.setColor(rr, gg, bb)
   love.graphics.setFont(fonts.small)
   love.graphics.print(("seed %d   step %.2fs"):format(g.seed, g.step_seconds), 1060, 770)

   draw.panels(s, shots, g.phase == "placing", 830, 100, 420, fonts.small, fonts.big,
      g.human and HUMAN or nil)

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

--- Placement keys for the human. Returns true if the key was handled.
local function human_key(g: Game, key: string): boolean
   if not g.human or g.phase ~= "placing" then return false end
   local slot = tonumber(key) or tonumber(key:match("^kp(%d)$") or "")
   if slot and slot >= 1 and slot <= sim.BANK then
      g.sel_slot, g.passing = math.floor(slot), false
      refresh_spots(g)
   elseif key == "w" or key == "tab" then
      g.sel_wall, g.passing = 3 - g.sel_wall, false
      g.spots = nil
      refresh_spots(g)
   elseif key == "left" or key == "a" then
      g.sel_spot, g.passing = math.max(1, g.sel_spot - 1), false
   elseif key == "right" or key == "d" then
      g.sel_spot, g.passing = math.min(math.max(1, #g.spots), g.sel_spot + 1), false
   elseif key == "x" then
      g.passing = not g.passing
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
