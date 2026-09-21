--- Headless soak: play whole matches with the random bots and check the
--- engine's invariants after every tick. `tl run tests/soak.tl -- 20` plays
--- 20 seeds.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local bots = require("bots")

local argv = _G.arg as {string} or {}
local seeds = math.floor(tonumber(argv[1] or "") or 5)
local N, SIZE = 11, 14

local function check_invariants(state: sim.State, where: string)
   local count = 0
   for k, chunk in pairs(state.occ) do
      count = count + 1
      local found = false
      for _, c in ipairs(chunk.cells) do
         if board.key(c.a, c.b) == k then found = true end
      end
      assert(found, where .. ": occupancy points at a chunk that lacks the cell " .. k)
   end
   local total = 0
   for _, chunk in ipairs(state.chunks) do
      assert(#chunk.cells > 0, where .. ": empty chunk survived")
      for _, c in ipairs(chunk.cells) do
         total = total + 1
         assert(board.contains(N, c.a, c.b), where .. ": cell off the board")
         assert(state.occ[board.key(c.a, c.b)] == chunk, where .. ": occupancy mismatch")
         for _, nb in ipairs(bc.neighbors(c.a, c.b)) do
            local other = state.occ[board.key(nb.a, nb.b)]
            if other and other ~= chunk then
               for _, oc in ipairs(other.cells) do
                  if oc.a == nb.a and oc.b == nb.b then
                     assert(oc.color ~= c.color, where .. ": same-colour contact survived")
                  end
               end
            end
         end
      end
   end
   assert(total == count, where .. ": occupancy size mismatch")
end

for seed = 1, seeds do
   local state = sim.new(N, SIZE, bc.seeded_random(seed))
   local rounds, ticks, hits, clears, passes = 0, 0, 0, 0, 0
   local first_pass: integer = nil
   local winner: integer = nil
   while rounds < 400 do
      local shots = bots.plan(state)
      passes = passes + (3 - #shots)
      if #shots < 3 and not first_pass then first_pass = state.round end
      if #shots == 0 then
         -- Jammed: nothing fits anywhere. Stop unless the board can still move.
         local r = sim.tick(state)
         if r.moved == 0 then break end
      end
      sim.fire(state, shots)
      check_invariants(state, ("seed %d round %d fire"):format(seed, state.round))
      local guard = 0
      while true do
         local r = sim.tick(state)
         ticks = ticks + 1
         hits = hits + #r.hits
         clears = clears + #r.cleared
         check_invariants(state, ("seed %d round %d tick %d"):format(seed, state.round, guard))
         guard = guard + 1
         assert(guard < 500, "sliding phase never settles")
         if r.moved == 0 then break end
      end
      winner = sim.winner(state)
      if winner then break end
      sim.end_turn(state)
      rounds = rounds + 1
   end
   print(("seed %2d: %3d rounds, %4d ticks, %3d hits, %3d clears, %3d passes (first at round %s), hp %3d/%3d/%3d, winner %s"):format(
      seed, rounds, ticks, hits, clears, passes, tostring(first_pass),
      state.players[1].hp, state.players[2].hp, state.players[3].hp, tostring(winner)))
end
print("ok")
