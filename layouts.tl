--- Draws alternative board layouts cut from the triangular tiling, to SVG.
---
---   tl run layouts.tl                         # images/layouts/*.svg
---   tl run layouts.tl -- --n 6 --side 20      # inner hexagon of side 6
---   tl run layouts.tl -- --n 10 --r 3         # setback of 3 rows
---   tl run layouts.tl -- --out /tmp/layouts   # somewhere other than images/layouts
---
--- Standalone: it reads board.strips for the lattice geometry but nothing in
--- the game consults these shapes.
---
--- Shapes
--- ------
--- Every shape here is an intersection of half-planes bounded by lattice lines,
--- so membership is exact integer arithmetic on the strip coordinates
--- (k1, k2, k3) from board.tl, where the hexagon of side n is all three in
--- [-n, n-1]. Splitting that into its two halves gives two big triangles:
---
---   up   = every k <= n - 1      (sides on walls 1, 3, 5)
---   down = every k >= -n         (sides on walls 0, 2, 4)
---
--- whose intersection is the hexagon and whose union is the hexagram. Each of
--- the hexagram's six points is a triangle of side n pointing straight out
--- through one of the hexagon's walls, so cropping the points flat with faces
--- perpendicular to the line to the centre is just intersecting with a bigger
--- hexagon: keeping `r` rows of each point means a hexagon of side n + r.
---
---   r = 0      the hexagon itself
---   r = n      the full hexagram
---   0 < r < n  a cropped star: six flat faces of length n - r, each between
---              two slanted edges of length r, so r = n / 2 makes all 18
---              edges the same length
---
--- Cell counts are exact: 6n^2 for the hexagon, plus n^2 - (n - r)^2 per point.
---
--- Filled notches
--- --------------
--- Between neighbouring points the cropped star has a notch at each corner of
--- the inner hexagon: a 60 degree wedge lying beyond both walls that meet
--- there. Within the hexagon of side n + r that wedge is a rhombus of side r
--- (2r^2 cells), and filling it restores that corner of the outer hexagon.
--- Filling every other one (corners 0, 2, 4: east, southwest, northwest)
--- keeps the board's three-fold symmetry.

local bc = require("blunkychunks")
local board = require("board")

local type XY = bc.XY
local type AB = bc.AB

local GRID <const> = "#9aa5b1"
local WALL <const> = "#1f2933"
local INK <const> = "#1f2933"
local PAPER <const> = "#ffffff"
local UP_FILL <const> = "#eef1f4"
local INNER <const> = "#7b8794"

local PAD <const> = 30.0
local TITLE_H <const> = 56.0

local function f(v: number): string
   return ("%.2f"):format(v)
end

--- A layout: a name, a one-line note, and an exact membership test.
local record Layout
   file: string
   name: string
   note: string
   contains: function(integer, integer): boolean
   expect: integer -- the cell count the formula above predicts
end

local function in_up(n: integer, a: integer, b: integer): boolean
   local k1, k2, k3 = board.strips(a, b)
   return k1 <= n - 1 and k2 <= n - 1 and k3 <= n - 1
end

local function in_down(n: integer, a: integer, b: integer): boolean
   local k1, k2, k3 = board.strips(a, b)
   return k1 >= -n and k2 >= -n and k3 >= -n
end

--- The hexagram on an inner hexagon of side `n`, keeping `r` rows of each point.
local function star(n: integer, r: integer): function(integer, integer): boolean
   return function(a: integer, b: integer): boolean
      return board.contains(n + r, a, b) and (in_up(n, a, b) or in_down(n, a, b))
   end
end

--- Which strip family, and which end of it, wall `j` sits at (as in board.tl).
local WALL_STRIP <const>: {integer: {integer, integer}} = {
   [0] = { 2, -1 }, [1] = { 1, 1 }, [2] = { 3, -1 },
   [3] = { 2, 1 }, [4] = { 1, -1 }, [5] = { 3, 1 },
}

--- Is cell (a, b) past wall `j` of the hexagon of side `n`? Exact.
local function beyond(n: integer, j: integer, a: integer, b: integer): boolean
   local k = { board.strips(a, b) }
   local fam = WALL_STRIP[j]
   local v = k[fam[1]]
   if fam[2] == 1 then return v >= n end
   return v < -n
end

--- The cropped star with the notches at `corners` filled in. Corner j sits
--- between walls j - 1 and j, so its notch is the cells past both.
local function filled_star(n: integer, r: integer, corners: {integer}): function(integer, integer): boolean
   local base = star(n, r)
   return function(a: integer, b: integer): boolean
      if base(a, b) then return true end
      if not board.contains(n + r, a, b) then return false end
      for _, j in ipairs(corners) do
         if beyond(n, (j - 1) % 6, a, b) and beyond(n, j, a, b) then return true end
      end
      return false
   end
end

local function layouts(n: integer, setback: integer): {Layout}
   local out: {Layout} = {
      {
         file = "hexagon", name = ("Hexagon, side %d"):format(n),
         note = "the inner hexagon every star below is built on",
         contains = function(a: integer, b: integer): boolean return board.contains(n, a, b) end,
         expect = 6 * n * n,
      },
      {
         file = "triangle", name = ("Triangle, side %d"):format(3 * n),
         note = "one of the hexagram's two triangles",
         contains = function(a: integer, b: integer): boolean
            return bc.is_cell(a, b) and in_up(n, a, b)
         end,
         expect = 9 * n * n,
      },
      {
         file = "hexagram", name = ("Hexagram, inner side %d"):format(n),
         note = "both triangles, points sharp",
         contains = star(n, n),
         expect = 12 * n * n,
      },
   }
   local seen: {integer: boolean} = {}
   for _, r in ipairs({ n // 4, setback, (3 * n) // 4 }) do
      if r > 0 and r < n and not seen[r] then
         seen[r] = true
         out[#out + 1] = {
            file = ("star-cropped-%d"):format(r),
            name = ("Cropped star, inner side %d, %d of %d rows kept"):format(n, r, n),
            note = ("flat faces %d long, slanted edges %d long"):format(n - r, r),
            contains = star(n, r),
            expect = 6 * n * n + 6 * (n * n - (n - r) * (n - r)),
         }
      end
   end
   local r = setback
   if r > 0 and r <= n then
      out[#out + 1] = {
         file = ("star-cropped-%d-filled"):format(r),
         name = ("Cropped star, %d of %d rows kept, three notches filled"):format(r, n),
         note = "east, southwest and northwest notches filled in",
         contains = filled_star(n, r, { 0, 2, 4 }),
         expect = 6 * n * n + 6 * (n * n - (n - r) * (n - r)) + 3 * 2 * r * r,
      }
   end
   return out
end

--- Every cell of a layout. The hexagram's points reach 2n strips out, and the
--- triangle's corners 2n + 1, so a box of 8n + 8 in (a, b) holds them all.
local function cells_of(n: integer, l: Layout): {AB}
   local lim = 8 * n + 8
   local out: {AB} = {}
   for a = -lim, lim do
      for b = -lim, lim do
         if bc.is_cell(a, b) and l.contains(a, b) then
            out[#out + 1] = { a = a, b = b }
         end
      end
   end
   return out
end

--- Rounded so the two cells sharing an edge agree on its key, and so a tiny
--- negative doesn't print as "-0.0000" on one side and "0.0000" on the other.
local function coord(v: number): string
   local r = math.floor(v * 1e3 + 0.5) / 1e3
   if r == 0 then r = 0 end
   return ("%.3f"):format(r)
end

local function edge_key(p: XY, q: XY): string
   local s = coord(p.x) .. "," .. coord(p.y)
   local t = coord(q.x) .. "," .. coord(q.y)
   return s < t and s .. "|" .. t or t .. "|" .. s
end

local function seg(p: XY, q: XY, ox: number, oy: number, attrs: string): string
   return ('    <line x1="%s" y1="%s" x2="%s" y2="%s"%s/>')
      :format(f(p.x + ox), f(p.y + oy), f(q.x + ox), f(q.y + oy), attrs)
end

--- One layout as an SVG: point-up cells shaded, the grid, the inner hexagon's
--- outline for reference, and the shape's outline (edges only one cell owns).
local function render(n: integer, side: number, l: Layout, cells: {AB}): string
   local edges: {string: {XY}} = {}
   local count: {string: integer} = {}
   local order: {string} = {}
   local xmin, xmax, ymin, ymax = math.huge, -math.huge, math.huge, -math.huge
   local polys: {{XY}} = {}
   for _, c in ipairs(cells) do
      local pts = board.corners(c.a, c.b, side)
      if bc.is_up(c.a, c.b) then polys[#polys + 1] = pts end
      for i = 1, 3 do
         local p, q = pts[i], pts[i % 3 + 1]
         local k = edge_key(p, q)
         if not count[k] then
            count[k] = 0
            edges[k] = { p, q }
            order[#order + 1] = k
         end
         count[k] = count[k] + 1
         xmin, xmax = math.min(xmin, p.x), math.max(xmax, p.x)
         ymin, ymax = math.min(ymin, p.y), math.max(ymax, p.y)
      end
   end

   local w = xmax - xmin + 2 * PAD
   local h = ymax - ymin + 2 * PAD + TITLE_H
   local ox = PAD - xmin
   local oy = PAD + TITLE_H - ymin
   local out: {string} = {
      ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" width="%d" height="%d">')
         :format(f(w), f(h), math.floor(w + 0.5), math.floor(h + 0.5)),
      ('  <rect width="100%%" height="100%%" fill="%s"/>'):format(PAPER),
   }
   local function emit(s: string) out[#out + 1] = s end

   emit(('  <g fill="%s" stroke="none">'):format(UP_FILL))
   for _, pts in ipairs(polys) do
      local ps: {string} = {}
      for i, p in ipairs(pts) do ps[i] = f(p.x + ox) .. "," .. f(p.y + oy) end
      emit(('    <polygon points="%s"/>'):format(table.concat(ps, " ")))
   end
   emit("  </g>")

   emit(('  <g stroke="%s" stroke-width="0.8" stroke-linecap="round">'):format(GRID))
   for _, k in ipairs(order) do
      if count[k] == 2 then emit(seg(edges[k][1], edges[k][2], ox, oy, "")) end
   end
   emit("  </g>")

   if l.file ~= "hexagon" then
      emit(('  <g stroke="%s" stroke-width="2" stroke-dasharray="6 5" stroke-linecap="round">')
         :format(INNER))
      for j = 0, 5 do
         local s = board.wall(n, side, j)
         emit(seg({ x = s.x1, y = s.y1 }, { x = s.x2, y = s.y2 }, ox, oy, ""))
      end
      emit("  </g>")
   end

   emit(('  <g stroke="%s" stroke-width="3.5" stroke-linecap="round">'):format(WALL))
   for _, k in ipairs(order) do
      if count[k] == 1 then emit(seg(edges[k][1], edges[k][2], ox, oy, "")) end
   end
   emit("  </g>")

   local font = 'font-family="Helvetica, Arial, sans-serif" text-anchor="middle" dominant-baseline="middle"'
   emit(('  <text x="%s" y="%s" fill="%s" %s font-size="19" font-weight="600">%s</text>')
      :format(f(w / 2), f(PAD + 4), INK, font, l.name))
   emit(('  <text x="%s" y="%s" fill="%s" %s font-size="12">%s &#183; %d triangles</text>')
      :format(f(w / 2), f(PAD + 26), GRID, font, l.note, #cells))
   emit("</svg>")
   return table.concat(out, "\n") .. "\n"
end

local function write(path: string, body: string)
   local fh, err = io.open(path, "w")
   if not fh then error(err) end
   fh:write(body)
   fh:close()
end

local function main(argv: {string})
   local function opt(name: string, fallback: string): string
      for i, a in ipairs(argv) do
         if a == "--" .. name then return argv[i + 1] or fallback end
      end
      return fallback
   end

   local n = math.floor(tonumber(opt("n", "10")) or error("--n needs a number"))
   local r = math.floor(tonumber(opt("r", tostring(n // 2))) or error("--r needs a number"))
   local side = tonumber(opt("side", "22")) or error("--side needs a number")
   local dir = opt("out", "images/layouts")

   os.execute(("mkdir -p '%s'"):format(dir))
   for _, l in ipairs(layouts(n, r)) do
      local cells = cells_of(n, l)
      if #cells ~= l.expect then
         error(("%s: %d cells, expected %d"):format(l.file, #cells, l.expect))
      end
      local path = ("%s/%s.svg"):format(dir, l.file)
      write(path, render(n, side, l, cells))
      print(("wrote %s (%d triangles)"):format(path, #cells))
   end
end

main(_G.arg as {string} or {})
