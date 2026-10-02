local bc = require("blunkychunks")
local board = require("board")
local A = require("tests.assert")

local type Board = board.Board

local record T
end

local WALL, MIDDLE = board.WALL, board.MIDDLE

--- Sizes worth checking: tiny, the README's 12-5 picture, the default 22-8,
--- and a notch wider than the central hexagon.
local SIZES: {{integer, integer}} = { { 1, 1 }, { 3, 2 }, { 6, 5 }, { 11, 8 }, { 5, 9 } }

local function each_board(f: function(Board))
   for _, nr in ipairs(SIZES) do f(board.new(nr[1], nr[2])) end
end

local function label(B: Board, i: integer): string
   local x, y = board.xy(B, i)
   return ("(%d, %d) on %d-%d"):format(x, y, 2 * B.n, B.r)
end

function T.matrix_is_full_and_counts_are_exact()
   each_board(function(B: Board)
      local n, r, s = B.n, B.r, B.s
      A.eq(B.w, 4 * s, "4s columns")
      A.eq(B.h, 2 * s, "2s rows")
      local homes, middle, walls = { 0, 0, 0 }, 0, 0
      for i = 1, B.size do
         A.truthy(B.kind[i] ~= nil and B.a[i] ~= nil and B.touch[i] ~= nil, "no holes at " .. i)
         A.eq(board.index_of(B, B.a[i], B.b[i]), i, "index_of round trip")
         local k = B.kind[i]
         if k == WALL then walls = walls + 1
         elseif k == MIDDLE then middle = middle + 1
         else homes[k] = homes[k] + 1 end
      end
      A.eq(middle, 6 * n * n, "middle is the central hexagon")
      for p = 1, 3 do A.eq(homes[p], 4 * n * r, "home of 4nr") end
      A.eq(#B.cells, 6 * (n + r) * (n + r) - 6 * r * r, "board cells")
      A.eq(walls, 8 * s * s - #B.cells, "the rest is wall")
   end)
end

--- Spot checks against images/layouts/notched-hexagon-filled-12-5-cells.svg.
function T.labels_match_the_layouts_picture()
   local B = board.new(6, 5)
   local function kind(x: integer, y: integer): integer return B.kind[board.index(B, x, y)] end
   local i = board.index(B, 1, 1)
   A.eq(B.a[i], 12, "(1, 1) is a = 12")
   A.eq(B.b[i], -12, "(1, 1) is b = -12")
   A.eq(kind(1, 1), WALL, "(1, 1) is the wall's corner")
   A.eq(kind(23, 23), WALL, "(23, 23) is wall")
   A.eq(kind(25, 23), 2, "(25, 23) is the top of Player 2's home")
   A.eq(kind(24, 7), MIDDLE, "(24, 7) is middle")
   A.eq(kind(25, 7), MIDDLE, "(25, 7) is middle")
   A.eq(kind(24, 6), WALL, "(24, 6) is the notch")
   A.eq(kind(26, 7), 3, "(26, 7) is Player 3's home")
   A.eq(kind(23, 6), 1, "(23, 6) is Player 1's home")
end

function T.parity_is_orientation()
   each_board(function(B: Board)
      for i = 1, B.size do
         A.eq(i % 2 == 0, bc.is_up(B.a[i], B.b[i]), "even index points up at " .. label(B, i))
         A.eq(board.facing(i), bc.is_up(B.a[i], B.b[i]) and 1 or 2, "facing")
      end
   end)
end

function T.steps_and_passes_match_the_lattice()
   each_board(function(B: Board)
      for _, i in ipairs(B.cells) do
         local a, b = B.a[i], B.b[i]
         for h, st in ipairs(board.STEPS) do
            local d = i + B.step[h]
            A.eq(B.a[d], a + st.a, "step a " .. h .. " at " .. label(B, i))
            A.eq(B.b[d], b + st.b, "step b " .. h .. " at " .. label(B, i))
            local m = board.swept(a, b, st)
            local q = i + B.pass[h][board.facing(i)]
            A.eq(B.a[q], m.a, "pass a " .. h .. " at " .. label(B, i))
            A.eq(B.b[q], m.b, "pass b " .. h .. " at " .. label(B, i))
            -- Never wraps onto another row: x moves by at most 2.
            local x = board.xy(B, i)
            local dx = board.xy(B, d)
            A.truthy(math.abs(dx - x) <= 2, "no wrap")
         end
      end
   end)
end

function T.neighbours_match_the_lattice()
   each_board(function(B: Board)
      for _, i in ipairs(B.cells) do
         local want: {string: boolean} = {}
         for _, nb in ipairs(bc.neighbors(B.a[i], B.b[i])) do want[board.key(nb.a, nb.b)] = true end
         for _, d in ipairs(B.near[board.facing(i)]) do
            A.truthy(want[board.key(B.a[i + d], B.b[i + d])], "neighbour at " .. label(B, i))
         end
      end
   end)
end

--- Walking heading h from i while still in home p: does it get out, or run
--- into a wall first?
local function escapes(B: Board, p: integer, i: integer, h: integer): boolean
   while B.kind[i] == p do
      if B.kind[i + B.step[h]] == WALL or B.kind[i + B.pass[h][board.facing(i)]] == WALL then
         return false
      end
      i = i + B.step[h]
   end
   return true
end

--- Straight across gets out from anywhere in the home; each of the other two
--- headings runs parallel to a dashed wall, so only part of the home can use it.
function T.headings_point_back_across_the_board()
   A.eq(board.HEADING_NAMES[board.HEADINGS[3][1]], "SW", "east fires SW")
   A.eq(board.HEADING_NAMES[board.HEADINGS[3][2]], "W", "east fires W")
   A.eq(board.HEADING_NAMES[board.HEADINGS[3][3]], "NW", "east fires NW")
   A.eq(board.HEADING_NAMES[board.HEADINGS[1][2]], "NE", "southwest fires NE straight across")
   A.eq(board.HEADING_NAMES[board.HEADINGS[2][2]], "SE", "northwest fires SE straight across")
   each_board(function(B: Board)
      for p = 1, 3 do
         local hs = board.HEADINGS[p]
         for _, i in ipairs(B.homes[p]) do
            A.truthy(escapes(B, p, i, hs[2]), "straight across escapes from " .. label(B, i))
         end
         for _, h in ipairs({ hs[1], hs[3] }) do
            local out, stuck = 0, 0
            for _, i in ipairs(B.homes[p]) do
               if escapes(B, p, i, h) then out = out + 1 else stuck = stuck + 1 end
            end
            A.truthy(out > 0 and stuck > 0, "a side heading escapes from one arm only")
         end
      end
   end)
end

--- Homes never touch each other, so the only ways out of a home are into the
--- middle or into the wall.
function T.no_step_crosses_from_home_to_home()
   each_board(function(B: Board)
      for _, i in ipairs(B.cells) do
         local k = B.kind[i]
         if k > 0 then
            for h = 1, 6 do
               for _, j in ipairs({ i + B.step[h], i + B.pass[h][board.facing(i)] }) do
                  local kj = B.kind[j]
                  A.truthy(kj == k or kj == MIDDLE or kj == WALL, "home to home at " .. label(B, i))
               end
            end
         end
      end
   end)
end

--- A 120 degree turn about the centre takes each home to the next player's,
--- and keeps the back walls where they were.
function T.homes_are_three_fold_symmetric()
   each_board(function(B: Board)
      for _, i in ipairs(B.cells) do
         local turned = bc.rotate({ { a = B.a[i], b = B.b[i], color = "red" } }, 2)[1]
         local j = board.index_of(B, turned.a, turned.b)
         local k = B.kind[i]
         local want = k == MIDDLE and MIDDLE or (k + 1) % 3 + 1
         A.eq(B.kind[j], want, "kind after a turn at " .. label(B, i))
         A.eq(B.touch[j], B.touch[i], "touch after a turn at " .. label(B, i))
      end
   end)
end

--- Float oracle: a home triangle touches its back wall iff one of its corners,
--- as drawn, is also a corner of a wall triangle.
function T.touch_matches_corner_geometry()
   local function pt(p: bc.XY): string
      return ("%.4f,%.4f"):format(p.x + 0.00001, p.y + 0.00001)
   end
   each_board(function(B: Board)
      local wall_corner: {string: boolean} = {}
      for i = 1, B.size do
         if B.kind[i] == WALL then
            for _, p in ipairs(board.corners(B.a[i], B.b[i], 1)) do wall_corner[pt(p)] = true end
         end
      end
      local touching = 0
      for i = 1, B.size do
         local want = false
         if B.kind[i] > 0 then
            for _, p in ipairs(board.corners(B.a[i], B.b[i], 1)) do
               if wall_corner[pt(p)] then want = true end
            end
         end
         A.eq(B.touch[i], want, "touch at " .. label(B, i))
         if want then touching = touching + 1 end
      end
      A.truthy(touching > 0, "some triangles touch")
   end)
end

function T.outline_is_six_sides_of_the_outer_hexagon()
   each_board(function(B: Board)
      local g = board.geometry(B, 1)
      -- Each notch swaps the outer hexagon's two r-long edges for two r-long
      -- notch edges, so the perimeter is still 6(n + r).
      A.eq(#g.outline, 6 * (B.n + B.r), "outline edges")
      A.eq(#g.grid, (3 * #B.cells - #g.outline) // 2, "every other edge is grid")
      A.truthy(#g.walls > 0, "walls to draw")
   end)
end

function T.rotate_turns_60_degrees_counterclockwise()
   local chunk = bc.generate(9, bc.seeded_random(4))
   local turned = bc.rotate(chunk, 1)
   local c, s = math.cos(math.pi / 3), math.sin(math.pi / 3)
   for k, cell in ipairs(chunk) do
      local p = board.centroid(cell.a, cell.b, 1)
      local q = board.centroid(turned[k].a, turned[k].b, 1)
      -- Counterclockwise as drawn with y down: (x, y) -> (x c + y s, -x s + y c).
      A.near(q.x, p.x * c + p.y * s, "x")
      A.near(q.y, -p.x * s + p.y * c, "y")
      A.eq(turned[k].color, cell.color, "colour kept")
      A.eq(bc.is_up(turned[k].a, turned[k].b), not bc.is_up(cell.a, cell.b), "orientation flips")
   end
   local back = bc.rotate(chunk, 6)
   for k, cell in ipairs(chunk) do
      A.eq(back[k].a, cell.a, "six turns are none")
      A.eq(back[k].b, cell.b, "six turns are none")
   end
   local neg = bc.rotate(chunk, -1)
   local fwd = bc.rotate(chunk, 5)
   for k = 1, #chunk do A.eq(neg[k].a, fwd[k].a, "-1 is 5") end
end

--- A shape placed anywhere is the chunk translated without flipping anything.
function T.shape_and_place_keep_the_chunk()
   local B = board.new(6, 5)
   for turn = 0, 5 do
      local chunk = bc.rotate(bc.generate(10, bc.seeded_random(9)), turn)
      local shape = board.shape(B, chunk)
      local lo = math.huge
      for _, o in ipairs(shape.cells) do lo = math.min(lo, o.dy) end
      A.eq(lo, 0, "lowest row is 0")
      for _, x in ipairs({ 4, 10 }) do
         local tris = board.place(B, shape, x, 5)
         A.truthy(tris, "fits in the matrix")
         for k, t in ipairs(tris) do
            A.eq(bc.is_up(B.a[t.i], B.b[t.i]), bc.is_up(chunk[k].a, chunk[k].b), "orientation kept")
            A.eq(t.color, chunk[k].color, "colour kept")
            A.eq(B.a[t.i] - B.a[tris[1].i], chunk[k].a - chunk[1].a, "a differences kept")
            A.eq(B.b[t.i] - B.b[tris[1].i], chunk[k].b - chunk[1].b, "b differences kept")
         end
      end
   end
   A.eq(board.place(B, board.shape(B, bc.generate(3, bc.seeded_random(1))), B.w, B.h), nil,
      "off the matrix is nil")
   A.truthy(not pcall(board.place, B, board.shape(B, bc.generate(3, bc.seeded_random(1))), 3, 3),
      "odd anchor x is refused")
end

function T.options_read_diameter_and_notch()
   local n, r = board.options({})
   A.eq(n, 11, "default diameter 22")
   A.eq(r, 8, "default notch 8")
   n, r = board.options({ "--diameter", "12", "--notch", "5" })
   A.eq(n, 6, "diameter 12 is side 6")
   A.eq(r, 5, "notch 5")
   A.truthy(not pcall(board.options, { "--diameter", "13" }), "odd diameter refused")
   A.truthy(not pcall(board.options, { "--notch", "0" }), "notch 0 refused")
end

return T
