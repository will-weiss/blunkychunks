--- blunkychunks -- procedurally generated connected triangle shapes.
---
--- Coordinates
--- -----------
--- Triangles live on the faces of a triangular tiling, which are indexed here
--- by Eisenstein integers: a cell (a, b) means z = a + b*w, where w = e^(2pi i/3).
---
--- The faces of the triangular tiling form a honeycomb lattice, and the
--- honeycomb is exactly the Eisenstein integers with the residue class
--- z = 0 (mod L) removed, where L = 1 - w. Since z = a + b*w = a + b (mod L)
--- and Z[w]/L is Z/3, that residue is just (a + b) % 3. We drop class 1 rather
--- than 0, so that the origin (0, 0) is a valid triangle:
---
---   (a + b) % 3 == 0  ->  a point-down triangle
---   (a + b) % 3 == 2  ->  a point-up triangle
---   (a + b) % 3 == 1  ->  not a cell
---
--- Two cells share an edge iff they differ by an Eisenstein unit, which gives
--- each cell exactly three neighbours (see `neighbors`).
---
--- Translating a chunk means adding (da, db) with (da + db) % 3 == 0; those are
--- the translations that keep every triangle's orientation, so they are the only
--- ones a fired chunk may use.
---
--- Everything here is plain Lua 5.1-compatible once compiled, so it can be
--- dropped straight into a LOVE2D project.

local record blunkychunks
   enum Color
      "red"
      "green"
      "blue"
   end

   --- A bare cell coordinate.
   record AB
      a: integer
      b: integer
   end

   --- A single triangle: Eisenstein coordinates plus its color.
   record Cell
      a: integer
      b: integer
      color: Color
   end

   --- A point in SVG space (y down).
   record XY
      x: number
      y: number
   end

   COLORS: {Color}
   FILL: {Color: string}
   mod3: function(integer): integer
end

local type Color = blunkychunks.Color
local type AB = blunkychunks.AB
local type Cell = blunkychunks.Cell
local type XY = blunkychunks.XY

local SQRT3 <const> = math.sqrt(3)

blunkychunks.COLORS = { "red", "green", "blue" }

blunkychunks.FILL = {
   red = "#d6494f",
   green = "#3f9a55",
   blue = "#3f68c4",
}

--- Non-negative remainder mod 3. (Lua's % already floors, but be explicit.)
local function mod3(n: integer): integer
   return ((n % 3) + 3) % 3
end
blunkychunks.mod3 = mod3

--- Is (a, b) a triangle of the tiling?
function blunkychunks.is_cell(a: integer, b: integer): boolean
   return mod3(a + b) ~= 1
end

--- Does (a, b) point up? (Only meaningful when `is_cell`.)
function blunkychunks.is_up(a: integer, b: integer): boolean
   return mod3(a + b) == 2
end

--- The three edge-sharing neighbours of a cell.
function blunkychunks.neighbors(a: integer, b: integer): {AB}
   local r = mod3(a + b)
   if r == 1 then
      error(("(%d, %d) is not a triangle cell"):format(a, b))
   end
   -- Point-down cells subtract a unit, point-up cells add one; either way the
   -- residue flips, so neighbours always have the opposite orientation.
   if r == 0 then
      return {
         { a = a - 1, b = b },
         { a = a, b = b - 1 },
         { a = a + 1, b = b + 1 },
      }
   end
   return {
      { a = a + 1, b = b },
      { a = a, b = b + 1 },
      { a = a - 1, b = b - 1 },
   }
end

--- Deterministic PRNG (Park-Miller / MINSTD), so a seed reproduces a chunk
--- exactly. Chosen over a bit-twiddling generator because 16807 * 2^31 stays
--- under 2^53: it is exact on LuaJIT's doubles as well as Lua 5.4 integers.
function blunkychunks.seeded_random(seed: integer): function(): number
   local s = seed % 2147483647
   if s <= 0 then s = s + 2147483646 end
   return function(): number
      s = (s * 16807) % 2147483647
      return (s - 1) / 2147483646
   end
end

--- Grow a connected blunkychunk of `size` triangles, rooted at the origin.
---
--- Every pair of edge-sharing triangles gets different colors. Growth is an
--- Eden model: repeatedly pick a uniformly random frontier cell, color it with
--- a color none of its placed neighbours use, and extend the frontier.
function blunkychunks.generate(size: integer, rng: function(): number): {Cell}
   if size < 1 then
      error(("size must be a positive integer, got %d"):format(size))
   end
   rng = rng or math.random

   local colors = blunkychunks.COLORS
   local neighbors = blunkychunks.neighbors

   local function key(a: integer, b: integer): string
      return a .. "," .. b
   end

   local placed: {string: Color} = {}
   local chunk: {Cell} = {}
   local frontier: {AB} = {}

   local function place(a: integer, b: integer, color: Color)
      placed[key(a, b)] = color
      chunk[#chunk + 1] = { a = a, b = b, color = color }
      for _, n in ipairs(neighbors(a, b)) do
         if not placed[key(n.a, n.b)] then
            frontier[#frontier + 1] = n
         end
      end
   end

   place(0, 0, colors[math.floor(rng() * #colors) + 1])

   while #chunk < size and #frontier > 0 do
      -- Swap-remove a random frontier entry.
      local i = math.floor(rng() * #frontier) + 1
      local cand = frontier[i]
      frontier[i] = frontier[#frontier]
      frontier[#frontier] = nil

      if not placed[key(cand.a, cand.b)] then -- it can be queued more than once
         local taken: {Color: boolean} = {}
         for _, n in ipairs(neighbors(cand.a, cand.b)) do
            local c = placed[key(n.a, n.b)]
            if c then taken[c] = true end
         end
         local available: {Color} = {}
         for _, c in ipairs(colors) do
            if not taken[c] then available[#available + 1] = c end
         end
         -- A cell walled in by all three colors can never be colored -- drop it.
         if #available > 0 then
            place(cand.a, cand.b, available[math.floor(rng() * #available) + 1])
         end
      end
   end

   return chunk
end

--- The centroid of a cell, in SVG space (y down). `side` is the edge length.
function blunkychunks.centroid(a: integer, b: integer, side: number): XY
   local scale = side / SQRT3 -- circumradius of a triangle with this edge
   return { x = (b * SQRT3 / 2) * scale, y = (a - b / 2) * scale }
end

--- The three corners of a cell, in SVG space (y down).
---
--- The Eisenstein plane is rotated a quarter turn so that the triangles sit
--- point-up / point-down, matching the game board.
function blunkychunks.cell_corners(a: integer, b: integer, side: number): {XY}
   local r = mod3(a + b)
   if r == 1 then
      error(("(%d, %d) is not a triangle cell"):format(a, b))
   end
   local scale = side / SQRT3
   local cx = a - b / 2 -- centroid = a*1 + b*w
   local cy = b * SQRT3 / 2
   local base = r == 0 and 0 or 60
   local out: {XY} = {}
   for i, d in ipairs({ 0, 120, 240 }) do
      local t = (base + d) * math.pi / 180
      -- (x, y) -> (y, x) rotates by -90 and flips y for SVG's downward axis.
      out[i] = { x = (cy + math.sin(t)) * scale, y = (cx + math.cos(t)) * scale }
   end
   return out
end

return blunkychunks
