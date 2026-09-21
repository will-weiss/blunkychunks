--- The blunkychunks board: a hexagon of side `n` cut from the triangular
--- tiling, its three defended walls, and the rules for firing a chunk at one.
---
--- Wall numbering
--- --------------
--- Walls are indexed 0..5 clockwise from the right-hand vertex, so wall j runs
--- from corner j to corner j+1 and its outward normal points at 30 + 60j
--- degrees. Players hold the odd walls; the even walls are neutral.
---
---                      4 (neutral)
---                   ___________
---       3 (P2)     /           \     5 (P3)
---                 /             \
---                 \             /
---       2 (neutral)\___________/      0 (neutral)
---                      1 (P1)
---
--- Firing
--- ------
--- A chunk translates by Eisenstein steps, so it can only travel along the
--- three lattice directions -- each of which is parallel to one opposite pair
--- of walls. From wall j the two legal headings aim at walls j+2 and j-2; j+2
--- sweeps clockwise and j-2 counterclockwise.
---
---   Turn A (clockwise):        launch from your wall or the one counter-
---                              clockwise of it; travel toward wall j+2.
---   Turn B (counterclockwise): launch from your wall or the one clockwise of
---                              it; travel toward wall j-2.
---
--- On turn A that sends Player 1's shot from their own wall straight at Player
--- 2's; on turn B the whole cycle reverses.

local bc = require("blunkychunks")

local record board
   record Player
      name: string
      color: string
      wall: integer
   end

   record Seg
      x1: number
      y1: number
      x2: number
      y2: number
   end

   record Shot
      player: integer
      wall: integer
      dir: bc.XY
      cells: {bc.Cell}
   end

   enum Turn
      "A"
      "B"
   end

   PLAYERS: {Player}
   key: function(integer, integer): string
end

local type XY = bc.XY
local type AB = bc.AB
local type Cell = bc.Cell
local type Seg = board.Seg
local type Turn = board.Turn

local SQRT3 <const> = math.sqrt(3)
local EPS <const> = 1e-9

--- Player 1 holds the bottom wall; 2 and 3 follow clockwise every other wall.
board.PLAYERS = {
   { name = "Player 1", color = bc.FILL.red, wall = 1 },
   { name = "Player 2", color = bc.FILL.blue, wall = 3 },
   { name = "Player 3", color = bc.FILL.green, wall = 5 },
}

--- Cell (0, 0)'s centroid sits at the origin, but the board's centre is the
--- six-fold lattice vertex at that cell's apex. Everything drawn gets shifted
--- up by this much so the hexagon is centred on (0, 0).
local function origin_shift(side: number): number
   return side / SQRT3
end

--- A cell's centroid in board space (y down, board centred on the origin).
function board.centroid(a: integer, b: integer, side: number): XY
   local p = bc.centroid(a, b, side)
   return { x = p.x, y = p.y - origin_shift(side) }
end

--- A cell's three corners in board space.
function board.corners(a: integer, b: integer, side: number): {XY}
   local shift = origin_shift(side)
   local out: {XY} = {}
   for i, p in ipairs(bc.cell_corners(a, b, side)) do
      out[i] = { x = p.x, y = p.y - shift }
   end
   return out
end

--- Is every corner of cell (a, b) inside the hexagon of side `n`?
---
--- Testing corners rather than the centroid matters: point-up and point-down
--- triangles sit at different depths within a row, so no single bound on the
--- centroid separates the two orientations correctly.
function board.contains(n: integer, a: integer, b: integer): boolean
   if not bc.is_cell(a, b) then return false end
   local apothem = n * SQRT3 / 2 + EPS
   for _, p in ipairs(board.corners(a, b, 1)) do
      if math.abs(p.y) > apothem
         or math.abs(SQRT3 / 2 * p.x + 0.5 * p.y) > apothem
         or math.abs(SQRT3 / 2 * p.x - 0.5 * p.y) > apothem then
         return false
      end
   end
   return true
end

--- Every cell of the hexagon of side `n`. There are exactly 6n^2 of them.
function board.cells(n: integer): {AB}
   local out: {AB} = {}
   for a = -4 * n, 4 * n do
      for b = -4 * n, 4 * n do
         if board.contains(n, a, b) then
            out[#out + 1] = { a = a, b = b }
         end
      end
   end
   return out
end

local function key(a: integer, b: integer): string
   return a .. "," .. b
end
board.key = key

--- A membership set, so placement search is a hash lookup per cell.
function board.cell_set(cells: {AB}): {string: boolean}
   local set: {string: boolean} = {}
   for _, c in ipairs(cells) do
      set[key(c.a, c.b)] = true
   end
   return set
end

--- Corner `i` (0-based, clockwise from the right-hand vertex) of the hexagon.
function board.corner(n: integer, side: number, i: integer): XY
   local r = n * side
   local t = i * 60 * math.pi / 180
   return { x = r * math.cos(t), y = r * math.sin(t) }
end

--- Wall `j` as a segment.
function board.wall(n: integer, side: number, j: integer): Seg
   local p = board.corner(n, side, j)
   local q = board.corner(n, side, (j + 1) % 6)
   return { x1 = p.x, y1 = p.y, x2 = q.x, y2 = q.y }
end

--- The outward unit normal of wall `j`, at 30 + 60j degrees.
function board.wall_normal(j: integer): XY
   local t = (30 + 60 * j) * math.pi / 180
   return { x = math.cos(t), y = math.sin(t) }
end

--- The heading a chunk launched from wall `j` travels on, as a unit vector.
---
--- Turn A aims at wall j+2 (180 + 60j degrees), turn B at wall j-2 (240 + 60j).
--- Both are multiples of 60 degrees, i.e. genuine lattice directions.
function board.fire_dir(j: integer, turn: Turn): XY
   local t = ((turn == "A" and 180 or 240) + 60 * j) * math.pi / 180
   return { x = math.cos(t), y = math.sin(t) }
end

--- The two walls player `p` (1-based) may fire from this turn: their own, and
--- the neutral wall on the trailing side of the sweep.
function board.launch_walls(p: integer, turn: Turn): {integer}
   local w = board.PLAYERS[p].wall
   local other = turn == "A" and (w - 1) % 6 or (w + 1) % 6
   return { w, other }
end

--- Every distinct grid edge of the board, deduplicated between shared cells.
function board.grid_segments(n: integer, side: number): {Seg}
   local seen: {string: boolean} = {}
   local out: {Seg} = {}
   for _, c in ipairs(board.cells(n)) do
      local pts = board.corners(c.a, c.b, side)
      for i = 1, 3 do
         local p, q = pts[i], pts[i % 3 + 1]
         local a = ("%.4f,%.4f"):format(p.x, p.y)
         local b = ("%.4f,%.4f"):format(q.x, q.y)
         local k = a < b and a .. "|" .. b or b .. "|" .. a
         if not seen[k] then
            seen[k] = true
            out[#out + 1] = { x1 = p.x, y1 = p.y, x2 = q.x, y2 = q.y }
         end
      end
   end
   return out
end

--- Slide `chunk` onto the board so that it rests against wall `j`.
---
--- Only translations with (da + db) % 3 == 0 preserve triangle orientation, so
--- those are the only ones a fired chunk may use. Among the translations that
--- land the whole chunk on the board we keep the ones pressed hardest against
--- wall `j` (maximum reach along its outward normal) and pick one at random,
--- which scatters the chunk along the wall rather than always centring it.
function board.place(n: integer, chunk: {Cell}, j: integer, rng: function(): number): {Cell}
   local set = board.cell_set(board.cells(n))
   local normal = board.wall_normal(j)

   -- Seeded from the first cell rather than math.maxinteger, which is 5.3+.
   local amin, amax = chunk[1].a, chunk[1].a
   local bmin, bmax = chunk[1].b, chunk[1].b
   for _, c in ipairs(chunk) do
      amin, amax = math.min(amin, c.a), math.max(amax, c.a)
      bmin, bmax = math.min(bmin, c.b), math.max(bmax, c.b)
   end

   local lim = 4 * n
   local best = -math.huge
   local bests: {AB} = {}

   for da = -lim - amin, lim - amax do
      for db = -lim - bmin, lim - bmax do
         if (da + db) % 3 == 0 then
            local ok = true
            local reach = -math.huge
            for _, c in ipairs(chunk) do
               if not set[key(c.a + da, c.b + db)] then
                  ok = false
                  break
               end
               local p = board.centroid(c.a + da, c.b + db, 1)
               local d = p.x * normal.x + p.y * normal.y
               if d > reach then reach = d end
            end
            if ok then
               if reach > best + EPS then
                  best, bests = reach, { { a = da, b = db } }
               elseif reach > best - EPS then
                  bests[#bests + 1] = { a = da, b = db }
               end
            end
         end
      end
   end

   if #bests == 0 then
      error(("no placement of a %d-cell chunk fits against wall %d"):format(#chunk, j))
   end

   local t = bests[math.floor(rng() * #bests) + 1]
   local out: {Cell} = {}
   for i, c in ipairs(chunk) do
      out[i] = { a = c.a + t.a, b = c.b + t.b, color = c.color }
   end
   return out
end

--- How far a ray from `p` along unit `dir` travels before leaving the hexagon.
function board.exit_distance(n: integer, side: number, p: XY, dir: XY): number
   local apothem = n * side * SQRT3 / 2
   local normals = { board.wall_normal(1), board.wall_normal(3), board.wall_normal(5) }
   local t = math.huge
   for _, m in ipairs(normals) do
      local denom = dir.x * m.x + dir.y * m.y
      local here = p.x * m.x + p.y * m.y
      if denom > EPS then
         t = math.min(t, (apothem - here) / denom)
      elseif denom < -EPS then
         t = math.min(t, (-apothem - here) / denom)
      end
   end
   return t
end

--- One player's shot for a turn: a fresh chunk, a launch wall chosen at random
--- from the two legal ones, and the heading it travels on.
function board.shoot(n: integer, p: integer, turn: Turn, size: integer, rng: function(): number): board.Shot
   local options = board.launch_walls(p, turn)
   local j = options[math.floor(rng() * #options) + 1]
   local chunk = bc.generate(size, rng)
   return {
      player = p,
      wall = j,
      dir = board.fire_dir(j, turn),
      cells = board.place(n, chunk, j, rng),
   }
end

return board
