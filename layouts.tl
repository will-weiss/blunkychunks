--- Draws alternative board layouts cut from the triangular tiling, to SVG.
---
---   tl run layouts.tl                         # every board into images/layouts/
---   tl run layouts.tl -- --board notched-hexagon --diameter 12 --notch 5
---                                             # -> notched-hexagon-12-5.svg
---   tl run layouts.tl -- --side 30            # draw each triangle 30px wide
---   tl run layouts.tl -- --cells              # label every cell (x, y); *-cells.svg
---   tl run layouts.tl -- --out /tmp/layouts   # somewhere other than images/layouts
---
--- Boards: hexagon, triangle, hexagram, truncated-hexagram, notched-hexagon.
---
---   --diameter  the central hexagon's width in triangles, so its side n is
---               half of it (must be even; default 20)
---   --notch     the setback r: rows kept on each star point, which is also the
---               side of each notch (default diameter / 4)
---
--- Cell labels
--- -----------
--- With --cells each triangle is labelled (x, y), counted from the board's
--- southwest corner so both are never negative:
---
---   y  the row, 0 along the bottom and one more per row going north
---   x  the triangle's place along its row, one per triangle going east, with
---      the columns leaning northwest (parallel to the southwest wall), so
---      x stays the same climbing that wall and (0, 0) is the corner triangle
---
--- Up and down triangles alternate along a row, so x + y is even for one
--- orientation and odd for the other. Labels are derived from (a, b) with
--- integer arithmetic only: b already counts half-triangle steps east, and the
--- horizontal strip k1 counts rows.
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
---
--- The cells outside the hexagram are exactly those past two neighbouring
--- walls, so the cropped star is the outer hexagon minus all six notches, and
--- the notched hexagon is it minus just corners 1, 3 and 5. Put that way it
--- needs no star points to crop, so r can exceed n: opposite walls can't both
--- be crossed, so the three notches never overlap, and the count is
--- 6(n + r)^2 - 6r^2 for any r.

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
   file: string -- the board's name, as --board takes it
   params: {integer} -- what the image name adds after it: diameter, then notch
   name: string
   note: string
   contains: function(integer, integer): boolean
   expect: integer -- the cell count the formula above predicts
   invalid: string -- why this board can't be drawn with these settings, if it can't
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

--- The hexagon of side n + r with the notches at `corners` cut out. Corner j
--- sits between walls j - 1 and j, so its notch is the cells past both.
local function notched(n: integer, r: integer, corners: {integer}): function(integer, integer): boolean
   return function(a: integer, b: integer): boolean
      if not board.contains(n + r, a, b) then return false end
      for _, j in ipairs(corners) do
         if beyond(n, (j - 1) % 6, a, b) and beyond(n, j, a, b) then return false end
      end
      return true
   end
end

--- Every board, or the reason it can't be drawn at this size.
local function layouts(n: integer, r: integer): {Layout}
   local cropped = 6 * n * n + 6 * (n * n - (n - r) * (n - r))
   return {
      {
         file = "hexagon", params = { 2 * n }, name = ("Hexagon, side %d"):format(n),
         note = "the central hexagon every star is built on",
         contains = function(a: integer, b: integer): boolean return board.contains(n, a, b) end,
         expect = 6 * n * n,
      },
      {
         file = "triangle", params = { 2 * n }, name = ("Triangle, side %d"):format(3 * n),
         note = "one of the hexagram's two triangles",
         contains = function(a: integer, b: integer): boolean
            return bc.is_cell(a, b) and in_up(n, a, b)
         end,
         expect = 9 * n * n,
      },
      {
         file = "hexagram", params = { 2 * n }, name = ("Hexagram, inner side %d"):format(n),
         note = "both triangles, points sharp",
         contains = star(n, n),
         expect = 12 * n * n,
      },
      {
         file = "truncated-hexagram", params = { 2 * n, r },
         name = ("Truncated hexagram, inner side %d, notch %d"):format(n, r),
         note = ("flat faces %d long, slanted edges %d long"):format(n - r, r),
         contains = star(n, r),
         expect = cropped,
         invalid = r >= n and ("--notch must be below the inner side %d"):format(n) or nil,
      },
      {
         file = "notched-hexagon", params = { 2 * n, r },
         name = ("Notched hexagon, inner side %d, notch %d"):format(n, r),
         note = "east, southwest and northwest notches filled in",
         contains = notched(n, r, { 1, 3, 5 }),
         expect = 6 * (n + r) * (n + r) - 3 * 2 * r * r,
      },
   }
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

--- Every cell's (x, y) label, keyed by board.key, as described at the top.
local function cell_labels(cells: {AB}): {string: {integer, integer}}
   local k1max = -math.huge
   for _, c in ipairs(cells) do
      local k1 = board.strips(c.a, c.b)
      if k1 > k1max then k1max = k1 end
   end
   local qmin = math.huge
   local raw: {{integer, integer}} = {}
   for i, c in ipairs(cells) do
      local y = math.floor(k1max - board.strips(c.a, c.b))
      local q = c.b + y
      raw[i] = { q, y }
      if q < qmin then qmin = q end
   end
   local out: {string: {integer, integer}} = {}
   for i, c in ipairs(cells) do
      out[board.key(c.a, c.b)] = { math.floor(raw[i][1] - qmin), raw[i][2] }
   end
   return out
end

--- One layout as an SVG: point-up cells shaded, the grid, the inner hexagon's
--- outline for reference, the shape's outline (edges only one cell owns) and,
--- if asked, every cell's (x, y).
local function render(n: integer, side: number, l: Layout, cells: {AB}, labels: boolean): string
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

   if labels then
      local xy = cell_labels(cells)
      emit(('  <g fill="%s" font-family="Helvetica, Arial, sans-serif" font-size="%s"'
         .. ' text-anchor="middle" dominant-baseline="central">'):format(INK, f(side * 0.2)))
      for _, c in ipairs(cells) do
         local p = board.centroid(c.a, c.b, side)
         -- Nudge toward the wide end of the triangle, where there's more room.
         local nudge = side * 0.05
         local v = xy[board.key(c.a, c.b)]
         emit(('    <text x="%s" y="%s">%d,%d</text>'):format(
            f(p.x + ox), f(p.y + oy + (bc.is_up(c.a, c.b) and nudge or -nudge)), v[1], v[2]))
      end
      emit("  </g>")
   end

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

   local function int(name: string, fallback: integer): integer
      local v = tonumber(opt(name, tostring(fallback)))
      if not v or v ~= math.floor(v) then error("--" .. name .. " needs a whole number") end
      return math.floor(v)
   end

   local diameter = int("diameter", 20)
   if diameter < 2 or diameter % 2 ~= 0 then
      error("--diameter must be a positive even number of triangles")
   end
   local n = diameter // 2
   local r = int("notch", n // 2)
   if r < 1 then error("--notch must be at least 1") end
   local labels = false
   for _, a in ipairs(argv) do
      if a == "--cells" then labels = true end
   end
   -- Labels need bigger triangles to be legible.
   local side = tonumber(opt("side", labels and "40" or "22")) or error("--side needs a number")
   local dir = opt("out", "images/layouts")
   local pick = opt("board", nil)

   local all = layouts(n, r)
   local chosen: {Layout} = {}
   for _, l in ipairs(all) do
      if not pick or l.file == pick then chosen[#chosen + 1] = l end
   end
   if #chosen == 0 then
      local names: {string} = {}
      for i, l in ipairs(all) do names[i] = l.file end
      error(("no board named %s; try one of: %s"):format(pick, table.concat(names, ", ")))
   end

   os.execute(("mkdir -p '%s'"):format(dir))
   for _, l in ipairs(chosen) do
      if l.invalid then
         if pick then error(l.file .. ": " .. l.invalid) end
         print(("skipped %s: %s"):format(l.file, l.invalid))
      else
         local cells = cells_of(n, l)
         if #cells ~= l.expect then
            error(("%s: %d cells, expected %d"):format(l.file, #cells, l.expect))
         end
         local stem = l.file
         for _, v in ipairs(l.params) do stem = stem .. "-" .. v end
         if labels then stem = stem .. "-cells" end
         local path = ("%s/%s.svg"):format(dir, stem)
         write(path, render(n, side, l, cells, labels))
         print(("wrote %s (%d triangles)"):format(path, #cells))
      end
   end
end

main(_G.arg as {string} or {})
