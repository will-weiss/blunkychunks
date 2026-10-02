--- The blunkychunks board: the notched hexagon in its walls, laid out as one
--- flat, integer-indexed matrix.
---
--- Shape
--- -----
--- `n` is the side of the central hexagon (half of --diameter) and `r` the
--- notch. The central hexagon's walls 0..5 run clockwise from the right-hand
--- vertex, wall j from corner j to corner j+1. The board is the hexagon of side
--- n + r with the notches at corners 1, 3 and 5 cut out (the cells past both
--- walls that meet there), which leaves three homes, each a V wrapped round
--- one of the central hexagon's corners 0, 2 and 4:
---
---   Player 1  south      corner 2, past walls 1 and 2   (southwest)
---   Player 2  northwest  corner 4, past walls 3 and 4   (northwest)
---   Player 3  northeast  corner 0, past walls 5 and 0   (east)
---
--- The compass names are as the game draws the board: draw.tl turns board
--- space a twelfth of a turn anticlockwise, so Player 1's corner points
--- straight down. The bracketed names, like every other compass word in this
--- file (the heading names, "southwest corner", "right-hand vertex"), are
--- board space as it is laid out here and by layouts.tl, before that turn.
---
--- A home's dashed line is the two central walls it lies past. Its back wall is
--- the rest of its outline, which is the edge of the board. Each home holds
--- 4nr triangles and the middle 6n^2.
---
--- The matrix
--- ----------
--- The board sits in the rhombus of side 2s, s = n + r + 1, whose rows are the
--- k1 strips and whose columns pair up into k3 strips (see layouts.tl, which
--- draws it). Every cell of the rhombus that is not on the board is wall.
--- Cells are numbered (x, y) from the southwest corner, exactly as
--- `tl run layouts.tl -- --board notched-hexagon-filled --cells` labels them:
---
---   y = s - k1         the row: 1 along the bottom, 2s rows in all
---   x = b + y + s      along the row: 4s columns, leaning northwest
---
--- and stored flat at i = (y - 1) * w + x, w = 4s. Every (x, y) in that
--- rectangle is a cell, so every array here is full and no lookup returns
--- nil. Up and down triangles alternate along a row while each column keeps
--- one orientation: odd x points down and even x points up, and as w is even
--- the same goes for i.
---
--- The walls are at least one strip deep everywhere, so from a board cell a
--- step, or the cell a step passes over, is always another index of the
--- matrix -- a wall, if nothing else -- and never wraps onto another row.
---
--- Exactness
--- ---------
--- Everything the rules use is integer arithmetic. Functions taking a `side`
--- produce screen geometry for drawing and are never consulted by the rules.

local bc = require("blunkychunks")

local record board
   record Player
      name: string
      color: string
      corner: integer
   end

   record Seg
      x1: number
      y1: number
      x2: number
      y2: number
   end

   --- A triangle on the board: its index and its colour.
   record Tri
      i: integer
      color: bc.Color
   end

   --- One triangle of a Shape, relative to the shape's anchor.
   record Offset
      dx: integer
      dy: integer
      color: bc.Color
   end

   --- A chunk as matrix offsets from an anchor (x, y). The lowest row is
   --- dy = 0 and the leftmost column dx = 0 or 1; anchors have even x, so
   --- each offset's parity is still its orientation.
   record Shape
      cells: {Offset}
      w: integer -- largest dx
      h: integer -- largest dy
   end

   --- Where a Shape's anchor goes.
   record Spot
      x: integer
      y: integer
   end

   record Board
      n: integer
      r: integer
      s: integer
      w: integer
      h: integer
      size: integer -- w * h
      kind: {integer} -- WALL, MIDDLE, or the player whose home it is
      touch: {boolean} -- a home triangle with a corner on its back wall
      a: {integer} -- Eisenstein coordinates, for drawing
      b: {integer}
      step: {integer} -- per heading: the index offset of one step
      pass: {{integer}} -- per heading, [1] up / [2] down: the cell a step passes over
      near: {{integer}} -- [1] up / [2] down: the three edge neighbours
      cells: {integer} -- every board (non-wall) index, ascending
      homes: {{integer}} -- per player, their home's indices
      box: {{integer}} -- per player, their home's xmin, xmax, ymin, ymax
   end

   --- Screen geometry for drawing a board at some `side`.
   record Geometry
      grid: {Seg} -- edges between two board triangles
      outline: {Seg} -- edges between a board triangle and a wall
      walls: {integer} -- wall indices within one strip of the board
   end

   WALL: integer
   MIDDLE: integer
   PLAYERS: {Player}
   HEADING_NAMES: {string}
   HEADINGS: {{integer}}
   STEPS: {bc.AB}
   key: function(integer, integer): string
end

local type XY = bc.XY
local type AB = bc.AB
local type Seg = board.Seg
local type Tri = board.Tri
local type Shape = board.Shape
local type Board = board.Board

local SQRT3 <const> = math.sqrt(3)

board.WALL = -1
board.MIDDLE = 0

local WALL <const> = board.WALL
local MIDDLE <const> = board.MIDDLE

--- Player 1 holds the south home (southwest in board space); 2 and 3 follow
--- clockwise.
board.PLAYERS = {
   { name = "Player 1", color = bc.FILL.red, corner = 2 },
   { name = "Player 2", color = bc.FILL.blue, corner = 4 },
   { name = "Player 3", color = bc.FILL.green, corner = 0 },
}

--- Headings 1..6 point at 0, 60, ... 300 degrees as drawn (y down).
board.HEADING_NAMES = { "E", "SE", "SW", "W", "NW", "NE" }

--- The same six headings as the shortest orientation-keeping Eisenstein
--- translations. Only tests and drawing use these; the rules use `step`.
board.STEPS = {
   { a = 1, b = 2 }, { a = 2, b = 1 }, { a = 1, b = -1 },
   { a = -1, b = -2 }, { a = -2, b = -1 }, { a = -1, b = 1 },
}

--- Each player fires the three headings pointing back across the board from
--- their corner c: 60c + 120, 60c + 180 and 60c + 240 degrees. The middle one
--- runs straight across, and gets out from anywhere in the home. The other two
--- each run parallel to one of the home's dashed walls, so they only get out
--- from the home's other arm. In board space east fires SW, W or NW; as drawn,
--- that is Player 3 in the northeast firing S, SW or NW.
board.HEADINGS = {}
for p, pl in ipairs(board.PLAYERS) do
   local c = pl.corner
   board.HEADINGS[p] = { (c + 2) % 6 + 1, (c + 3) % 6 + 1, (c + 4) % 6 + 1 }
end

--- Cell (0, 0)'s centroid sits at the origin, but the board's centre is the
--- six-fold lattice vertex at that cell's apex. Everything drawn gets shifted
--- up by this much so the hexagon is centred on (0, 0).
local function origin_shift(side: number): number
   return side / SQRT3
end

--- Any Eisenstein point -- a cell's centroid or a lattice vertex -- in board
--- space (y down, board centred on the origin).
function board.point(a: integer, b: integer, side: number): XY
   local p = bc.centroid(a, b, side)
   return { x = p.x, y = p.y - origin_shift(side) }
end

--- A cell's centroid in board space.
function board.centroid(a: integer, b: integer, side: number): XY
   return board.point(a, b, side)
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

--- A cell's three corners as lattice points, the Eisenstein integers with
--- (a + b) % 3 == 1: z + 1, z + w, z + w^2 for a point-down cell z and
--- z - 1, z - w, z - w^2 for a point-up one. Exact.
function board.vertices(a: integer, b: integer): {AB}
   if bc.is_up(a, b) then
      return { { a = a - 1, b = b }, { a = a, b = b - 1 }, { a = a + 1, b = b + 1 } }
   end
   return { { a = a + 1, b = b }, { a = a, b = b + 1 }, { a = a - 1, b = b - 1 } }
end

--- The six cells round lattice vertex v: v +- 1, v +- w, v +- w^2.
local function around(v: AB): {AB}
   return {
      { a = v.a + 1, b = v.b }, { a = v.a - 1, b = v.b },
      { a = v.a, b = v.b + 1 }, { a = v.a, b = v.b - 1 },
      { a = v.a + 1, b = v.b + 1 }, { a = v.a - 1, b = v.b - 1 },
   }
end

--- Exact integer division by 3, rounding toward minus infinity. Lua's `%`
--- already floors, so `x - x % 3` is a multiple of 3 and the division is exact
--- on doubles and Lua integers alike.
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
--- A hexagon of side n is exactly the cells with all three in [-n, n-1].
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

--- Is cell (a, b) past wall `j` of the hexagon of side `n`? Exact.
function board.beyond(n: integer, j: integer, a: integer, b: integer): boolean
   local k = { board.strips(a, b) }
   local fam = WALL_STRIP[j]
   local v = k[fam[1]]
   if fam[2] == 1 then return v >= n end
   return v < -n
end

--- Is (a, b) on the notched board: the hexagon of side n + r without the
--- notches at corners 1, 3 and 5? Corner j sits between walls j - 1 and j, so
--- its notch is the cells past both. Opposite walls can't both be crossed, so
--- the notches never overlap and the board holds 6(n + r)^2 - 6r^2 cells for
--- any r. Exact.
function board.notched(n: integer, r: integer, a: integer, b: integer): boolean
   if not board.contains(n + r, a, b) then return false end
   for _, j in ipairs({ 1, 3, 5 }) do
      if board.beyond(n, (j - 1) % 6, a, b) and board.beyond(n, j, a, b) then return false end
   end
   return true
end

--- Is (a, b) in the rhombus of side 2s round the hexagon of side `s`: its rows
--- and leaning columns, with the third family free? 8s^2 cells. Exact.
function board.rhombus(s: integer, a: integer, b: integer): boolean
   if not bc.is_cell(a, b) then return false end
   local k1, _, k3 = board.strips(a, b)
   return k1 >= -s and k1 < s and k3 >= -s and k3 < s
end

--- The matrix (x, y) of cell (a, b) for a rhombus of side 2s. Exact, and
--- defined for every cell, in the rhombus or not.
function board.xy_of(s: integer, a: integer, b: integer): integer, integer
   local k1 = board.strips(a, b)
   local y = s - k1
   return b + y + s, y
end

--- The home cell (a, b) of the notched board lies in, or MIDDLE.
local function home_of(n: integer, a: integer, b: integer): integer
   for p, pl in ipairs(board.PLAYERS) do
      local c = pl.corner
      if board.beyond(n, (c - 1) % 6, a, b) or board.beyond(n, c, a, b) then return p end
   end
   return MIDDLE
end

--- Matrix index of (x, y).
function board.index(B: Board, x: integer, y: integer): integer
   return (y - 1) * B.w + x
end

--- Matrix (x, y) of index `i`.
function board.xy(B: Board, i: integer): integer, integer
   local y = (i - 1) // B.w + 1
   return i - (y - 1) * B.w, y
end

--- Matrix index of cell (a, b), or nil outside the rhombus.
function board.index_of(B: Board, a: integer, b: integer): integer
   if not board.rhombus(B.s, a, b) then return nil end
   local x, y = board.xy_of(B.s, a, b)
   return board.index(B, x, y)
end

--- The notched board of central side `n` and notch `r`, framed in walls.
function board.new(n: integer, r: integer): Board
   if n < 1 then error(("the central hexagon needs a side of at least 1, got %d"):format(n)) end
   if r < 1 then error(("the notch must be at least 1, got %d"):format(r)) end
   local s = n + r + 1
   local w, h = 4 * s, 2 * s
   local B: Board = {
      n = n, r = r, s = s, w = w, h = h, size = w * h,
      kind = {}, touch = {}, a = {}, b = {},
      cells = {}, homes = { {}, {}, {} }, box = {},
   }

   -- The rhombus reaches at most 3s + 3 from the origin in a and in b.
   local lim = 4 * s + 4
   local filled = 0
   for a = -lim, lim do
      for b = -lim, lim do
         if board.rhombus(s, a, b) then
            local i = board.index(B, board.xy_of(s, a, b))
            if B.a[i] then error("two cells share matrix index " .. i) end
            B.a[i], B.b[i] = a, b
            B.kind[i] = board.notched(n, r, a, b) and home_of(n, a, b) or WALL
            filled = filled + 1
         end
      end
   end
   if filled ~= B.size then
      error(("the rhombus filled %d of %d matrix cells"):format(filled, B.size))
   end

   for p = 1, #board.PLAYERS do B.box[p] = { w, 1, h, 1 } end
   for i = 1, B.size do
      B.touch[i] = false
      local k = B.kind[i]
      if k ~= WALL then B.cells[#B.cells + 1] = i end
      if k > 0 then
         local home = B.homes[k]
         home[#home + 1] = i
         local x, y = board.xy(B, i)
         local box = B.box[k]
         box[1], box[2] = math.min(box[1], x), math.max(box[2], x)
         box[3], box[4] = math.min(box[3], y), math.max(box[4], y)
         -- Touching the back wall: some corner is shared with a wall cell.
         for _, v in ipairs(board.vertices(B.a[i], B.b[i])) do
            for _, c in ipairs(around(v)) do
               if B.kind[board.index_of(B, c.a, c.b)] == WALL then B.touch[i] = true end
            end
         end
      end
   end

   -- Offsets read off the (x, y) labels: a heading moves (dx, dy) by
   -- E (2, 0), SE (0, -1), SW (-2, -1), W (-2, 0), NW (0, 1), NE (2, 1),
   -- and the triangle passed over depends on which way the mover points.
   B.step = { 2, -w, -w - 2, -2, w, w + 2 }
   B.pass = {
      { 1, 1 }, -- E
      { -w - 1, 1 }, -- SE
      { -w - 1, -1 }, -- SW
      { -1, -1 }, -- W
      { -1, w + 1 }, -- NW
      { 1, w + 1 }, -- NE
   }
   -- A point-up cell's third neighbour is below it, a point-down cell's above.
   B.near = { { -1, 1, -w - 1 }, { -1, 1, w + 1 } }
   return B
end

--- 1 for a point-up index, 2 for point-down: the slot `pass` and `near` use.
function board.facing(i: integer): integer
   return i % 2 + 1
end

--- `cells` (anywhere in Eisenstein coordinates) as a Shape for board `B`.
--- The shift to the anchor is even in x, so orientations survive.
function board.shape(B: Board, cells: {bc.Cell}): Shape
   local xs, ys: {integer}, {integer} = {}, {}
   local xmin, ymin: integer, integer = nil, nil
   for k, c in ipairs(cells) do
      xs[k], ys[k] = board.xy_of(B.s, c.a, c.b)
      if not xmin or xs[k] < xmin then xmin = xs[k] end
      if not ymin or ys[k] < ymin then ymin = ys[k] end
   end
   local sx = xmin - xmin % 2
   local shape: Shape = { cells = {}, w = 0, h = 0 }
   for k, c in ipairs(cells) do
      local o: board.Offset = { dx = xs[k] - sx, dy = ys[k] - ymin, color = c.color }
      shape.cells[k] = o
      shape.w = math.max(shape.w, o.dx)
      shape.h = math.max(shape.h, o.dy)
   end
   return shape
end

--- `shape` with its anchor at (x, y): its triangles on the board, or nil if
--- any would fall outside the matrix. `x` must be even.
function board.place(B: Board, shape: Shape, x: integer, y: integer): {Tri}
   if x % 2 ~= 0 then error(("anchor x must be even, got %d"):format(x)) end
   local out: {Tri} = {}
   for k, o in ipairs(shape.cells) do
      local cx, cy = x + o.dx, y + o.dy
      if cx < 1 or cx > B.w or cy < 1 or cy > B.h then return nil end
      out[k] = { i = board.index(B, cx, cy), color = o.color }
   end
   return out
end

--- --diameter and --notch from a command line: the central hexagon's width in
--- triangles, which must be even, and the notch. Defaults 22 and 8. Returns
--- n (half the diameter) and r.
function board.options(argv: {string}): integer, integer
   local function int(name: string, fallback: integer): integer
      for i, a in ipairs(argv) do
         if a == "--" .. name then
            local v = tonumber(argv[i + 1] or "")
            if not v or v ~= math.floor(v) then error("--" .. name .. " needs a whole number") end
            return math.floor(v)
         end
      end
      return fallback
   end
   local diameter = int("diameter", 22)
   if diameter < 2 or diameter % 2 ~= 0 then
      error("--diameter must be a positive even number of triangles")
   end
   local r = int("notch", 8)
   if r < 1 then error("--notch must be at least 1") end
   return diameter // 2, r
end

local function key(a: integer, b: integer): string
   return a .. "," .. b
end
board.key = key

--- Corner `i` (0-based, clockwise from the right-hand vertex) of the hexagon
--- of side `n`, in board space.
function board.corner(n: integer, side: number, i: integer): XY
   local r = n * side
   local t = i * 60 * math.pi / 180
   return { x = r * math.cos(t), y = r * math.sin(t) }
end

--- Wall `j` of the hexagon of side `n` as a segment. The central hexagon's
--- six walls are the players' dashed lines.
function board.wall(n: integer, side: number, j: integer): Seg
   local p = board.corner(n, side, j)
   local q = board.corner(n, side, (j + 1) % 6)
   return { x1 = p.x, y1 = p.y, x2 = q.x, y2 = q.y }
end

--- The edge cells i and j share, as a segment in board space.
local function shared_edge(B: Board, i: integer, j: integer, side: number): Seg
   local pts: {XY} = {}
   for _, v in ipairs(board.vertices(B.a[i], B.b[i])) do
      for _, u in ipairs(board.vertices(B.a[j], B.b[j])) do
         if u.a == v.a and u.b == v.b then pts[#pts + 1] = board.point(v.a, v.b, side) end
      end
   end
   return { x1 = pts[1].x, y1 = pts[1].y, x2 = pts[2].x, y2 = pts[2].y }
end

--- The board's lines at `side`: grid edges between board triangles, outline
--- edges between the board and its walls, and the walls worth drawing (one
--- strip deep round the board, which takes in the notches).
function board.geometry(B: Board, side: number): board.Geometry
   local g: board.Geometry = { grid = {}, outline = {}, walls = {} }
   for _, i in ipairs(B.cells) do
      for _, d in ipairs(B.near[board.facing(i)]) do
         local j = i + d
         if B.kind[j] == WALL then
            g.outline[#g.outline + 1] = shared_edge(B, i, j, side)
         elseif j > i then
            g.grid[#g.grid + 1] = shared_edge(B, i, j, side)
         end
      end
   end
   for i = 1, B.size do
      if B.kind[i] == WALL and board.contains(B.n + B.r + 1, B.a[i], B.b[i]) then
         g.walls[#g.walls + 1] = i
      end
   end
   return g
end

--- The cell a triangle sweeps through when it takes `step` from (a, b): the
--- one neighbour it shares with its destination. Exact. The rules read this
--- off `Board.pass`; tests use this to check that table.
function board.swept(a: integer, b: integer, step: AB): AB
   local dest = bc.neighbors(a + step.a, b + step.b)
   for _, p in ipairs(bc.neighbors(a, b)) do
      for _, q in ipairs(dest) do
         if p.a == q.a and p.b == q.b then return { a = p.a, b = p.b } end
      end
   end
   error(("(%d, %d) is not a unit step"):format(step.a, step.b))
end

return board
