local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local bots = require("bots")
for _, cfg in ipairs({ { 3, 5, 6 }, { 11, 8, 14 }, { 17, 17, 14 } }) do
   local s = sim.new(board.new(cfg[1], cfg[2]), cfg[3], bc.seeded_random(3))
   for _ = 1, 6 do
      for p = 1, 3 do sim.lock_in(s, p, bots.choose(s, p)) end
      for _ = 1, 10 do sim.tick(s) end
   end
   for _, c in ipairs(s.chunks) do c.flying = false end
   local t = os.clock()
   for p = 1, 3 do
      local shot = bots.choose(s, p, "greedyclear")
      local g = sim.ghost(s, p, shot.cells, shot.heading)
      io.write(("p%d hits=%d cleared=%d look=%s  "):format(p, #g.hits, #g.cleared, g.look))
   end
   print(("\n%d-%d size %d: %.3f s per greedy choice"):format(2 * cfg[1], cfg[2], cfg[3], (os.clock() - t) / 3))
end
