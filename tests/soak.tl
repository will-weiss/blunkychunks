--- Headless soak: whole matches between random bots on the continuous clock,
--- checking the engine's invariants after every tick and every lock-in.
---
---   tl run tests/soak.tl -- --seeds 20 --diameter 22 --notch 8 --size 14
---
--- As in the game, ticks are 0.28 s apart and each player's 8 s shot clock
--- is staggered a third of a clock behind the one before.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local bots = require("bots")

local argv = _G.arg as {string} or {}

local function num(name: string, fallback: integer): integer
   for i, a in ipairs(argv) do
      if a == "--" .. name then return math.floor(tonumber(argv[i + 1] or "") or fallback) end
   end
   return fallback
end

local n, r = board.options(argv)
local SEEDS = num("seeds", 5)
local SIZE = num("size", 14)
local STEP <const> = 0.28
local PERIOD <const> = 8.0
local MAX_TICKS <const> = 12000

local function check(state: sim.State, where: string)
   local B = state.board
   local cells = 0
   for i = 1, B.size do
      assert(state.occ[i] ~= nil and state.paint[i] ~= nil, where .. ": hole in the matrix at " .. i)
      if state.occ[i] ~= 0 then cells = cells + 1 end
      assert((state.occ[i] == 0) == (state.paint[i] == 0), where .. ": paint out of step at " .. i)
   end
   local total = 0
   for _, chunk in ipairs(state.chunks) do
      assert(#chunk.cells > 0, where .. ": empty chunk survived")
      assert(state.by_id[chunk.id] == chunk, where .. ": chunk missing from by_id")
      for _, c in ipairs(chunk.cells) do
         total = total + 1
         local k = B.kind[c.i]
         assert(k ~= board.WALL, where .. ": a triangle in the wall")
         assert(k == board.MIDDLE or k == chunk.owner, where .. ": a triangle in another player's home")
         assert(state.occ[c.i] == chunk.id, where .. ": occupancy mismatch")
         assert(state.paint[c.i] == bc.CODE[c.color], where .. ": paint mismatch")
         for _, d in ipairs(B.near[board.facing(c.i)]) do
            local other = state.occ[c.i + d]
            if other ~= 0 and other ~= chunk.id then
               assert(state.paint[c.i + d] ~= state.paint[c.i], where .. ": same-colour contact survived")
            end
         end
      end
   end
   assert(total == cells, where .. ": occupancy count mismatch")
end

local outs: {string: integer} = {}
for seed = 1, SEEDS do
   local state = sim.new(board.new(n, r), SIZE, bc.seeded_random(seed))
   local fired, ticks, clears, hits = 0, 0, 0, 0
   local clocks = sim.clocks(PERIOD)
   local shots = bots.plan(state)
   while not sim.over(state) and ticks < MAX_TICKS do
      local res = sim.tick(state)
      ticks = ticks + 1
      clears = clears + #res.cleared
      hits = hits + #res.hits
      check(state, ("seed %d tick %d"):format(seed, ticks))
      for _, p in ipairs(sim.run_down(state, clocks, STEP, PERIOD)) do
         if sim.over(state) then break end
         local lock = sim.lock_in(state, p, bots.refresh(state, p, shots[p]))
         if lock.fired then fired = fired + 1 end
         clears = clears + #lock.cleared
         check(state, ("seed %d tick %d Player %d's lock-in"):format(seed, ticks, p))
         shots[p] = state.players[p].alive and bots.choose(state, p) or nil
      end
   end
   local how: {string} = {}
   for p, pl in ipairs(state.players) do
      how[p] = pl.alive and "in" or tostring(pl.out)
      if not pl.alive then outs[pl.out] = (outs[pl.out] or 0) + 1 end
   end
   local winner = sim.winner(state)
   print(("seed %2d: %3d shots, %5d ticks, %4d clears, %d back-wall hits, %-8s %-8s %-8s %s"):format(
      seed, fired, ticks, clears, hits, how[1], how[2], how[3],
      sim.over(state) and (winner and ("Player " .. winner .. " wins") or "draw") or "unfinished"))
end
print(("outs: %d stuck, %d friendly"):format(outs.stuck or 0, outs.friendly or 0))
print("ok")
