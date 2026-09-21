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
--- of walls. A player's heading is fixed by their own wall `w` and the turn,
--- whichever of their two walls they launch from:
---
---   Turn A (clockwise):        launch from your wall or the one counter-
---                              clockwise of it; travel at 180 + 60w degrees,
---                              which from your own wall reaches wall w+2.
---   Turn B (counterclockwise): launch from your wall or the one clockwise of
---                              it; travel at 240 + 60w degrees, which from
---                              your own wall reaches wall w-2.
---
--- From the loaned wall the same heading runs to wall w+3, the neutral wall
--- opposite your own, so a loaned shot is an interceptor rather than an
--- attack. On turn A Player 1 (bottom wall) heads northwest at Player 2,
--- Player 2 east at Player 3 and Player 3 southwest at Player 1; turn B
--- reverses the whole cycle.
---
--- Exactness
--- ---------
--- Everything the rules depend on -- membership (`contains`), depth toward a
--- wall (`depth`, `placements`), the per-tick step (`step`) and the cell a
--- sliding triangle passes over (`swept`) -- is integer arithmetic on (a, b).
--- Functions that mention `side` or a normal vector produce screen geometry
--- for drawing and are never consulted by the simulation.

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

--- Exact integer division by 3, rounding toward minus infinity. Lua's `%`
--- already floors, so `x - x % 3` is a multiple of 3 and the division is exact
--- on doubles and Lua integers alike (no `//`, which is 5.3+).
local function idiv3(x: integer): integer
   return math.floor((x - x % 3) / 3)
end

--- Strip coordinates
--- -----------------
--- The lattice lines come in three parallel families, each parallel to one
--- opposite pair of walls, and every cell sits in exactly one strip of each
--- family. The board is centred on a lattice vertex (z = 1 in Eisenstein
--- coordinates, the apex of cell (0, 0)), and about that vertex the three
--- families are images of each other under 120 degree rotation, so:
---
---   k1 = floor((2a - b) / 3) - 1    horizontal strips, walls 1 (max) / 4 (min)
---   k2 = floor(-(a + b) / 3)        strips parallel to walls 0 / 3, wall 3 at max
---   k3 = floor((2b - a) / 3)        strips parallel to walls 2 / 5, wall 5 at max
---
--- A hexagon of side n is exactly the cells with all three in [-n, n-1]. This
--- is the whole of the gameplay geometry: everything with a sqrt(3) in it
--- below is for drawing.
function board.strips(a: integer, b: integer): integer, integer, integer
   return idiv3(2 * a - b) - 1, idiv3(-(a + b)), idiv3(2 * b - a)
end

--- Is cell (a, b) inside the hexagon of side `n`? Exact.
function board.contains(n: integer, a: integer, b: integer): boolean
   if not bc.is_cell(a, b) then return false end
   local k1, k2, k3 = board.strips(a, b)
   return k1 >= -n and k1 < n
      and k2 >= -n and k2 < n
      and k3 >= -n and k3 < n
end

--- Which strip family, and which end of it, wall `j` sits at.
local WALL_STRIP <const>: {integer: {integer, integer}} = {
   [0] = { 2, -1 }, [1] = { 1, 1 }, [2] = { 3, -1 },
   [3] = { 2, 1 }, [4] = { 1, -1 }, [5] = { 3, 1 },
}

--- How deep toward wall `j` cell (a, b) sits: an integer that grows by one per
--- strip, largest for the cells whose edge or apex lies on the wall. Exact.
function board.depth(j: integer, a: integer, b: integer): integer
   local k = { board.strips(a, b) }
   local f = WALL_STRIP[j]
   return f[2] * k[f[1]]
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

--- The heading player `p` (1-based) fires on this turn, as a unit vector. It
--- depends on the player's own wall `w` alone, not on the launch wall.
---
--- Turn A aims at wall w+2 (180 + 60w degrees), turn B at wall w-2 (240 + 60w).
--- Both are multiples of 60 degrees, i.e. genuine lattice directions.
function board.fire_dir(p: integer, turn: Turn): XY
   local w = board.PLAYERS[p].wall
   local t = ((turn == "A" and 180 or 240) + 60 * w) * math.pi / 180
   return { x = math.cos(t), y = math.sin(t) }
end

--- The six shortest orientation-preserving translations: (da + db) % 3 == 0
--- and one side long. In board space they point at 0, 60, ... 300 degrees.
local STEPS <const>: {AB} = {
   { a = 1, b = 2 }, { a = 2, b = 1 }, { a = 1, b = -1 },
   { a = -1, b = -2 }, { a = -2, b = -1 }, { a = -1, b = 1 },
}

--- The lattice step player `p`'s chunks take each tick: STEPS[i] points at
--- 60(i - 1) degrees, and `fire_dir` is 180 + 60w (turn A) or 240 + 60w
--- (turn B) for the player's own wall `w`, so this is a pure index lookup.
function board.step(p: integer, turn: Turn): AB
   local w = board.PLAYERS[p].wall
   local i = ((turn == "A" and 3 or 4) + w) % 6 + 1
   return { a = STEPS[i].a, b = STEPS[i].b }
end

--- The cell a triangle sweeps through when it takes `step` from (a, b): the
--- one neighbour it shares with its destination. A rigid slide of one side
--- passes right over that opposite-orientation triangle, so it must be free
--- too. Exact.
function board.swept(a: integer, b: integer, step: AB): AB
   local dest = bc.neighbors(a + step.a, b + step.b)
   for _, p in ipairs(bc.neighbors(a, b)) do
      for _, q in ipairs(dest) do
         if p.a == q.a and p.b == q.b then return { a = p.a, b = p.b } end
      end
   end
   error(("(%d, %d) is not a unit step"):format(step.a, step.b))
end

--- The wall player `p`'s chunk travels toward when launched from wall `j`
--- this turn: the opponent two walls around the sweep from their own wall,
--- or, from the loaned wall, the neutral wall opposite their own.
function board.target_wall(p: integer, j: integer, turn: Turn): integer
   local w = board.PLAYERS[p].wall
   if j ~= w then return (w + 3) % 6 end
   return turn == "A" and (w + 2) % 6 or (w - 2) % 6
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

local board_sets: {integer: {string: boolean}} = {}

--- The cell set of the hexagon of side `n`, computed once per size.
function board.cached_cell_set(n: integer): {string: boolean}
   local set = board_sets[n]
   if not set then
      set = board.cell_set(board.cells(n))
      board_sets[n] = set
   end
   return set
end

--- Every legal translation that lands `chunk` flush against wall `j`.
---
--- Only translations with (da + db) % 3 == 0 preserve triangle orientation, so
--- those are the only ones a fired chunk may use. Among the translations that
--- land the whole chunk on the board without touching a `blocked` cell we keep
--- the ones pressed hardest against wall `j` (maximum `depth`). Exact. Empty
--- when nothing fits.
function board.placements(n: integer, chunk: {Cell}, j: integer, blocked: {string: boolean}): {AB}
   local set = board.cached_cell_set(n)

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
               local k = key(c.a + da, c.b + db)
               if not set[k] or blocked[k] then
                  ok = false
                  break
               end
               local d = board.depth(j, c.a + da, c.b + db)
               if d > reach then reach = d end
            end
            if ok then
               if reach > best then
                  best, bests = reach, { { a = da, b = db } }
               elseif reach == best then
                  bests[#bests + 1] = { a = da, b = db }
               end
            end
         end
      end
   end

   return bests
end

--- `chunk` translated by `t`.
function board.translate(chunk: {Cell}, t: AB): {Cell}
   local out: {Cell} = {}
   for i, c in ipairs(chunk) do
      out[i] = { a = c.a + t.a, b = c.b + t.b, color = c.color }
   end
   return out
end

--- Slide `chunk` onto an empty board so that it rests against wall `j`,
--- picking one of the flush placements at random so chunks scatter along the
--- wall rather than always centring.
function board.place(n: integer, chunk: {Cell}, j: integer, rng: function(): number): {Cell}
   local bests = board.placements(n, chunk, j, {})
   if #bests == 0 then
      error(("no placement of a %d-cell chunk fits against wall %d"):format(#chunk, j))
   end
   return board.translate(chunk, bests[math.floor(rng() * #bests) + 1])
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
      dir = board.fire_dir(p, turn),
      cells = board.place(n, chunk, j, rng),
   }
end

return board
