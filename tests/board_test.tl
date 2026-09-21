local bc = require("blunkychunks")
local board = require("board")
local A = require("tests.assert")

local type Cell = bc.Cell

local record T
end

--- A player's heading depends only on who they are and which turn it is,
--- never on which of their two walls they launch from. In board space (y
--- down) turn A sends Player 1 northwest, 2 east, 3 southwest; turn B sends
--- 1 northeast, 2 southeast, 3 west.
function T.heading_is_fixed_per_player_and_turn()
   local want: {string: {integer: number}} = {
      A = { [1] = 240, [2] = 0, [3] = 120 },
      B = { [1] = 300, [2] = 60, [3] = 180 },
   }
   for _, turn in ipairs({ "A", "B" }) do
      for p = 1, 3 do
         local t = want[turn][p] * math.pi / 180
         local d = board.fire_dir(p, turn as board.Turn)
         A.near(d.x, math.cos(t), ("player %d turn %s dx"):format(p, turn))
         A.near(d.y, math.sin(t), ("player %d turn %s dy"):format(p, turn))
      end
   end
end

--- The lattice step for a heading must point exactly along `fire_dir`, keep
--- triangle orientation, and be the shortest such translation (one side).
function T.step_matches_fire_dir()
   for p = 1, 3 do
      for _, turn in ipairs({ "A", "B" }) do
         local s = board.step(p, turn as board.Turn)
         A.eq(bc.mod3(s.a + s.b), 0, "step keeps orientation")
         local o = bc.centroid(0, 0, 1)
         local q = bc.centroid(s.a, s.b, 1)
         local d = board.fire_dir(p, turn as board.Turn)
         local dx, dy = q.x - o.x, q.y - o.y
         A.near(math.sqrt(dx * dx + dy * dy), 1, "step is one side long")
         A.near(dx, d.x, ("player %d turn %s dx"):format(p, turn))
         A.near(dy, d.y, ("player %d turn %s dy"):format(p, turn))
      end
   end
end

--- From your own wall you head for the opponent two walls around the sweep;
--- from the loaned wall the same heading carries you to the neutral wall
--- opposite your own.
function T.target_wall_by_launch_wall()
   for p = 1, 3 do
      local w = board.PLAYERS[p].wall
      for _, turn in ipairs({ "A", "B" }) do
         local own, lent = table.unpack(board.launch_walls(p, turn as board.Turn))
         A.eq(own, w, "first launch wall is your own")
         local ahead = turn == "A" and (w + 2) % 6 or (w - 2) % 6
         A.eq(board.target_wall(p, own, turn as board.Turn), ahead,
            ("player %d turn %s own wall attacks"):format(p, turn))
         A.eq(board.target_wall(p, lent, turn as board.Turn), (w + 3) % 6,
            ("player %d turn %s loaned wall intercepts"):format(p, turn))
      end
   end
end

--- Does the centroid ray from cell `c` along `dir` leave the hexagon through
--- wall `k`? True when the ray crosses wall k's line at a point that is still
--- inside every other wall (so the crossing lies on the wall's segment; the
--- shared corners count for both walls).
local function exits_via(n: integer, c: bc.AB, dir: bc.XY, k: integer): boolean
   local apothem = n * math.sqrt(3) / 2
   local p = board.centroid(c.a, c.b, 1)
   local m = board.wall_normal(k)
   local denom = dir.x * m.x + dir.y * m.y
   if denom <= 1e-9 then return false end
   local t = (apothem - (p.x * m.x + p.y * m.y)) / denom
   if t < -1e-9 then return false end
   local q: bc.XY = { x = p.x + dir.x * t, y = p.y + dir.y * t }
   for w = 0, 5 do
      local wn = board.wall_normal(w)
      if q.x * wn.x + q.y * wn.y > apothem + 1e-6 then return false end
   end
   return true
end

--- Any cell a player's chunk launched from wall j can occupy (its backward
--- ray leaves through wall j) must leave the board through the target wall
--- when stepped forward. Covers own-wall attacks and loan-wall interceptors.
function T.lane_lands_on_target_wall()
   local n = 5
   local cells = board.cells(n)
   for p = 1, 3 do
      for _, turn in ipairs({ "A", "B" }) do
         local dir = board.fire_dir(p, turn as board.Turn)
         local back: bc.XY = { x = -dir.x, y = -dir.y }
         for _, j in ipairs(board.launch_walls(p, turn as board.Turn)) do
            local target = board.target_wall(p, j, turn as board.Turn)
            local lane = 0
            for _, c in ipairs(cells) do
               if exits_via(n, c, back, j) then
                  lane = lane + 1
                  A.truthy(exits_via(n, c, dir, target),
                     ("player %d wall %d turn %s: lane cell (%d,%d) misses wall %d"):format(p, j, turn, c.a, c.b, target))
               end
            end
            A.truthy(lane > 0, "lane is non-empty")
         end
      end
   end
end

--- Float oracle for `contains`: every corner of the cell inside the hexagon.
--- The game never uses this; it just pins the integer version to the picture.
local function float_contains(n: integer, a: integer, b: integer): boolean
   if not bc.is_cell(a, b) then return false end
   local apothem = n * math.sqrt(3) / 2 + 1e-9
   for _, p in ipairs(board.corners(a, b, 1)) do
      if math.abs(p.y) > apothem
         or math.abs(math.sqrt(3) / 2 * p.x + 0.5 * p.y) > apothem
         or math.abs(math.sqrt(3) / 2 * p.x - 0.5 * p.y) > apothem then
         return false
      end
   end
   return true
end

function T.contains_is_exact_and_matches_geometry()
   for n = 1, 11 do
      local count = 0
      for a = -4 * n - 2, 4 * n + 2 do
         for b = -4 * n - 2, 4 * n + 2 do
            local got = board.contains(n, a, b)
            A.eq(got, float_contains(n, a, b), ("contains(%d, %d, %d)"):format(n, a, b))
            if got then count = count + 1 end
         end
      end
      A.eq(count, 6 * n * n, "6n^2 cells")
   end
end

--- `depth` toward wall j must order cells exactly as the projection onto the
--- wall's outward normal does, and the on-board maximum must be the cells
--- touching that wall.
function T.depth_orders_like_wall_normal()
   local n = 5
   local cells = board.cells(n)
   for j = 0, 5 do
      local m = board.wall_normal(j)
      local max_d: integer = -1000
      for _, c in ipairs(cells) do
         max_d = math.max(max_d, board.depth(j, c.a, c.b))
      end
      for i = 1, #cells, 5 do
         for k = 1, #cells, 7 do
            local p, q = cells[i], cells[k]
            local dp, dq = board.depth(j, p.a, p.b), board.depth(j, q.a, q.b)
            local cp, cq = board.centroid(p.a, p.b, 1), board.centroid(q.a, q.b, 1)
            local fp, fq = cp.x * m.x + cp.y * m.y, cq.x * m.x + cq.y * m.y
            if dp > dq then A.truthy(fp > fq + 1e-9, ("wall %d: depth order"):format(j)) end
            if dp < dq then A.truthy(fp < fq - 1e-9, ("wall %d: depth order"):format(j)) end
         end
      end
      -- Every max-depth cell has a corner on the wall's line, and nothing
      -- shallower does.
      local apothem = n * math.sqrt(3) / 2
      for _, c in ipairs(cells) do
         local on_wall = false
         for _, p in ipairs(board.corners(c.a, c.b, 1)) do
            if math.abs(p.x * m.x + p.y * m.y - apothem) < 1e-9 then on_wall = true end
         end
         A.eq(on_wall, board.depth(j, c.a, c.b) == max_d,
            ("wall %d: cell (%d,%d) flush iff max depth"):format(j, c.a, c.b))
      end
   end
end

--- The swept cell is adjacent to both the start and the destination and has
--- the opposite orientation.
function T.swept_cell_is_between()
   for _, c in ipairs({ { a = 0, b = 0 }, { a = 0, b = 2 }, { a = 3, b = -1 } }) do
      for j = 0, 5 do
         for _, turn in ipairs({ "A", "B" }) do
            local s = board.step(j % 3 + 1, turn as board.Turn)
            local m = board.swept(c.a, c.b, s)
            A.eq(bc.is_up(m.a, m.b), not bc.is_up(c.a, c.b), "opposite orientation")
            local function adjacent(p: bc.AB, q: bc.AB): boolean
               for _, nb in ipairs(bc.neighbors(p.a, p.b)) do
                  if nb.a == q.a and nb.b == q.b then return true end
               end
               return false
            end
            A.truthy(adjacent(c, m), "swept touches start")
            A.truthy(adjacent({ a = c.a + s.a, b = c.b + s.b }, m), "swept touches destination")
         end
      end
   end
end

function T.placements_touch_wall_and_avoid_blocked()
   local n = 4
   local chunk: {Cell} = { { a = 0, b = 0, color = "red" } } -- one point-down cell
   local free = board.placements(n, chunk, 1, {})
   A.truthy(#free > 0, "single cell fits somewhere")
   -- Every placement is on the board and flush against wall 1 (bottom):
   -- reach along the normal is the same maximal value for all of them.
   local normal = board.wall_normal(1)
   local reach: number = nil
   for _, t in ipairs(free) do
      A.truthy(board.contains(n, t.a, t.b), "placement on board")
      local c = board.centroid(t.a, t.b, 1)
      local r = c.x * normal.x + c.y * normal.y
      if reach == nil then reach = r end
      A.near(r, reach, "all placements equally flush")
   end
   -- Block one of them; it must disappear from the options.
   local blocked: {string: boolean} = {}
   blocked[board.key(free[1].a, free[1].b)] = true
   local left = board.placements(n, chunk, 1, blocked)
   A.eq(#left, #free - 1, "blocked placement removed")
   for _, t in ipairs(left) do
      A.truthy(not blocked[board.key(t.a, t.b)], "no placement on a blocked cell")
   end
end

function T.placements_empty_when_wall_full()
   local n = 3
   local chunk: {Cell} = { { a = 0, b = 0, color = "red" } }
   local blocked: {string: boolean} = {}
   for _, c in ipairs(board.cells(n)) do blocked[board.key(c.a, c.b)] = true end
   A.eq(#board.placements(n, chunk, 1, blocked), 0, "nothing fits on a full board")
end

function T.place_still_works_for_render()
   local rng = bc.seeded_random(3)
   local chunk = bc.generate(6, rng)
   local placed = board.place(5, chunk, 3, rng)
   A.eq(#placed, 6, "place keeps every cell")
end

return T
