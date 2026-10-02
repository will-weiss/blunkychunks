# Notched Board Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hexagon / turn A-B / HP rules with the notched-board rules in README.md: three V-shaped homes, chunks that slide until they hit triangles or an opponent's dashed line, rotation, three headings per player, a continuous shot clock, a ghost with three looks, and "out" when you can't place or hit your own back wall.

**Architecture:** The board becomes one flat, integer-indexed matrix framed in walls (`board.new(n, r)`), numbered exactly like `layouts.tl`'s `notched-hexagon-filled --cells` labels. Each heading is then a fixed index offset and no lookup can return nil. `sim.tl` keeps the existing tick fixpoint, clears and splits, rewritten on that matrix, and adds dashed-line blocking, the back-wall loss, placements, the ghost and lock-in. The bots, the LÖVE game and the README figures are rebuilt on top.

**Tech Stack:** Teal (`tl`) compiled to Lua 5.1 for LÖVE 11.4 (LuaJIT). Tests run under the system Lua via `tl run`.

**Spec:** `docs/superpowers/specs/2026-10-01-notched-board-design.md`. The rules as players read them are in `README.md`.

## Global Constraints

- Game modules (`blunkychunks.tl`, `board.tl`, `src/*.tl`) must run under LuaJIT, so they can't use 5.3+ library functions: no `table.unpack`, no two-argument `math.atan`, no `utf8`. `//` is fine, because `tl gen --gen-target=5.1` turns it into `math.floor(a / b)`. Don't use `goto`: no file here does.
- Rules logic is exact integer arithmetic. `board.new`, `sim.tl` and `bots.tl` never call `board.point`, `board.centroid`, `board.corners`, or anything else taking a `side`. Floats belong only in `draw.tl`, `render.tl` and `layouts.tl`.
- Every per-cell array (`kind`, `touch`, `a`, `b`, `occ`, `paint`) is full from 1 to `w * h`, so no lookup returns nil.
- The board size comes from `--diameter` / `--notch` (`board.options`, defaults 22 and 8). Nothing hard-codes a size.
- The (x, y) numbering is exactly the one `tl run layouts.tl -- --board notched-hexagon-filled --cells` prints.
- Match the surrounding style: a `---` doc comment on every function and record, 3-space indents, Teal records, plain prose comments.
- Commit only when Will asks, and make a branch first, since the repo is on `main`. Each task's commit step is where a commit would go.
- `layouts.tl` holds Will's uncommitted work. Task 4 changes only its helper functions. Leave everything under `images/layouts/` alone.

## Review Focus

1. **A board too small for the chunk size** (e.g. `make run DIAMETER=2 NOTCH=1` with chunks of 14) has to end in a draw at the first shot clock, not crash. Pinned by `bots_test.a_home_too_small_for_any_chunk_ends_in_a_draw` (Task 3).
2. **The ghost must always come to rest on the board.** Its slide loop has no step limit, so from any home triangle on any of its player's headings, with or without piles in the way, it must stop on a middle or home cell. Pinned by `sim_test.the_ghost_always_comes_to_rest_on_the_board` (Task 2).
3. **An out player's chunks keep sliding, blocking and clearing** like anyone's. Pinned by `sim_test.an_out_players_chunks_keep_sliding` (Task 2).
4. **Your aim while your own last chunk flies through the spot you chose** should hop to the nearest legal spot and come back once the spot is free. This is UI only, so it's a manual check in Task 5, Step 8.
5. **The board fits the window at every size and stays smooth on large boards** (12-5, 22-8, 34-17). These are manual screenshot checks in Task 5, Steps 7–8.

## File Structure

| File | Change | Responsibility |
| ---- | ------ | -------------- |
| `blunkychunks.tl` | modify | chunk generation (unchanged), plus `rotate` (60° steps, exact) and `CODE` (colour → 1..3) |
| `board.tl` | replace | notched shape (`beyond`, `notched`, `rhombus`), the matrix (`board.new`: kinds, touch, offsets, homes), shapes and spots, `options`, drawing geometry |
| `src/sim.tl` | replace | rules: `new`, `add_chunk`, `tick`, `fire`, `placements`, `legal`, `can_head`, `ghost`, `lock_in`, `alive`/`over`/`winner` |
| `src/bots.tl` | replace | `choose`, `plan`, `refresh` |
| `src/draw.tl` | replace | layout, board, chunks, ghosts, arrows, thumbnails, panels, legend, effects |
| `src/main.tl` | replace | LÖVE callbacks, the continuous loop, the human's aim |
| `src/conf.tl` | modify | 1440×900 window |
| `Makefile` | replace | `DIAMETER`/`NOTCH` for run, bots, soak, images; `soak` and `images` targets; check covers the scripts |
| `render.tl` | replace | `images/board.svg`, `images/shots.svg` |
| `layouts.tl` | modify | uses `board.notched` / `board.rhombus` instead of its own copies |
| `tests/run.tl` | replace | runs all suites, or just the ones named |
| `tests/board_test.tl` | replace | the matrix pinned to the lattice and to the layouts picture |
| `tests/sim_test.tl` | replace | the rules |
| `tests/bots_test.tl` | create | the bots |
| `tests/soak.tl` | replace | headless continuous bot matches with invariant checks |
| `images/turn-a.svg`, `images/turn-b.svg` | delete | old turn figures |

From Task 1 until Task 5, the old `src/*.tl`, `render.tl`, `tests/sim_test.tl` and `tests/soak.tl` still use the old board API. So until Task 5 lands, run only the suites and `tl check`s each task names, and don't run `make check`, `make test` or `make run`.

---

### Task 1: The board matrix

**Files:**
- Modify: `blunkychunks.tl` (four edits below)
- Replace: `board.tl`
- Replace: `tests/run.tl`
- Replace: `tests/board_test.tl`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `bc.rotate(cells: {bc.Cell}, k: integer): {bc.Cell}`: k sixths of a turn counterclockwise as drawn, about vertex z = 1.
  - `bc.CODE: {bc.Color: integer}`: `red = 1, green = 2, blue = 3`.
  - Constants `board.WALL = -1` and `board.MIDDLE = 0`.
  - `board.PLAYERS[p] = { name, color, corner }`, with corners 2, 4, 0.
  - `board.HEADING_NAMES = { "E","SE","SW","W","NW","NE" }`.
  - `board.HEADINGS[p]`: three heading indices, the middle one straight across.
  - `board.STEPS[h]: bc.AB`.
  - Records:
    - `board.Tri { i, color }`;
    - `board.Offset { dx, dy, color }`;
    - `board.Shape { cells: {Offset}, w, h }`;
    - `board.Spot { x, y }`;
    - `board.Board { n, r, s, w, h, size, kind, touch, a, b, step, pass, near, cells, homes, box }`;
    - `board.Geometry { grid, outline, walls }`.
  - Shape helpers:
    - `board.strips(a, b)`, `board.contains(n, a, b)`;
    - `board.beyond(n, j, a, b)`;
    - `board.notched(n, r, a, b)`;
    - `board.rhombus(s, a, b)`.
  - Matrix:
    - `board.new(n, r): Board`;
    - `board.xy_of(s, a, b): x, y`;
    - `board.index(B, x, y)`, `board.xy(B, i)`, `board.index_of(B, a, b)`;
    - `board.facing(i)`: 1 for up, 2 for down.
  - Shapes: `board.shape(B, cells): Shape`; `board.place(B, shape, x, y): {Tri}`, which returns nil outside the matrix and errors on an odd x.
  - `board.options(argv): n, r`.
  - Drawing:
    - `board.point`, `board.centroid`, `board.corners`;
    - `board.vertices(a, b): {AB}`;
    - `board.corner(n, side, i)`, `board.wall(n, side, j)`;
    - `board.geometry(B, side): Geometry`;
    - `board.swept(a, b, step)`, a test oracle.
  - `board.key(a, b)`, kept for `layouts.tl`.

- [ ] **Step 1: Make the test runner take suite names**

Replace `tests/run.tl` with:

```lua
--- Minimal test runner: `tl run tests/run.tl` (or `make test`) runs every
--- suite; `tl run tests/run.tl -- board sim` runs just those.
---
--- Each tests/*_test.tl module returns a { name = function } table. Every
--- function is run in a pcall; a failure prints its message and the run exits
--- non-zero so `make test` fails.

local SUITES: {string} = { "board", "sim", "bots" }

local argv = _G.arg as {string} or {}
local suites: {string} = #argv > 0 and argv or SUITES

local passed, failed = 0, 0

for _, short in ipairs(suites) do
   local name = "tests." .. short .. "_test"
   local suite = require(name) as {string: function()}
   local names: {string} = {}
   for k in pairs(suite) do names[#names + 1] = k end
   table.sort(names)
   for _, k in ipairs(names) do
      local ok, err = pcall(suite[k]) as (boolean, any)
      if ok then
         passed = passed + 1
      else
         failed = failed + 1
         print(("FAIL %s.%s\n     %s"):format(name, k, tostring(err)))
      end
   end
end

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
```

- [ ] **Step 2: Write the board tests**

Replace `tests/board_test.tl` with:

```lua
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
```

- [ ] **Step 3: Run them and watch them fail**

Run: `tl run tests/run.tl -- board`
Expected: `0 passed, 13 failed`, every failure ending `attempt to call a nil value (field 'new')`. The old `board.tl` has no `board.new`.

- [ ] **Step 4: Add rotation and colour codes to `blunkychunks.tl`**

In the header comment, replace

```lua
--- ones a fired chunk may use.
```

with

```lua
--- ones a sliding chunk may use. Rotating by 60 degrees about a lattice vertex
--- also maps cells to cells, swapping up and down (see `rotate`).
```

In `record blunkychunks`, after `COLORS: {Color}`, add

```lua
   CODE: {Color: integer}
```

After `blunkychunks.COLORS = { "red", "green", "blue" }`, add

```lua

--- Each color's place in COLORS, for integer-valued colour matrices.
blunkychunks.CODE = { red = 1, green = 2, blue = 3 }
```

Just above `--- The centroid of a cell, in SVG space (y down).`, add

```lua
--- `cells` turned `k` times by 60 degrees counterclockwise (as drawn, y down)
--- about the lattice vertex z = 1. Multiplying by the unit 1 + w turns the
--- plane by 60 degrees, and z -> 1 + (z - 1)(1 + w) is, in (a, b),
---
---   (a, b) -> (a - b, a - 1)
---
--- which flips every cell's orientation, so the result is still made of cells.
--- Exact; k may be any integer.
function blunkychunks.rotate(cells: {Cell}, k: integer): {Cell}
   local out: {Cell} = {}
   for i, c in ipairs(cells) do
      out[i] = { a = c.a, b = c.b, color = c.color }
   end
   for _ = 1, k % 6 do
      for _, c in ipairs(out) do
         c.a, c.b = c.a - c.b, c.a - 1
      end
   end
   return out
end

```

- [ ] **Step 5: Write the board**

Replace `board.tl` with:

```lua
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
---   Player 1  southwest  corner 2, past walls 1 and 2
---   Player 2  northwest  corner 4, past walls 3 and 4
---   Player 3  east       corner 0, past walls 5 and 0
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

--- Player 1 holds the southwest home; 2 and 3 follow clockwise.
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
--- from the home's other arm. East fires SW, W or NW.
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
```

- [ ] **Step 6: Run the tests and the type check**

Run: `tl run tests/run.tl -- board`
Expected: `13 passed, 0 failed`

Run: `tl check blunkychunks.tl board.tl tests/board_test.tl tests/run.tl`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add blunkychunks.tl board.tl tests/run.tl tests/board_test.tl
git commit -m "Board: the notched hexagon as one integer matrix framed in walls"
```

---

### Task 2: The rules engine

**Files:**
- Replace: `src/sim.tl`
- Replace: `tests/sim_test.tl`

**Interfaces:**
- Consumes: from Task 1:
  - `board.new`, `board.Board` (its `kind`, `touch`, `step`, `pass`, `near`, `homes`, `box` and `cells` fields);
  - `board.facing`, `board.shape`, `board.place`;
  - `board.HEADINGS`, `board.PLAYERS`;
  - `bc.CODE`, `bc.COLORS`, `bc.generate`.
- Produces:
  - Enums: `sim.Out` is `"stuck"` or `"friendly"`; `sim.Look` is `"clear"`, `"home"` or `"friendly"`.
  - Records:
    - `sim.Chunk { id, owner, heading, cells: {board.Tri}, moved, flying }`;
    - `sim.Player { alive, out: Out, bank: {{bc.Cell}} }`;
    - `sim.Shot { player, slot, heading, cells: {board.Tri} }`;
    - `sim.Ghost { cells: {integer}, look: Look }`;
    - `sim.TickResult { moved, cleared, hits, out }`;
    - `sim.LockResult { fired, out, cleared }`;
    - `sim.State { board, size, occ, paint, chunks, by_id, players, next_id, rng }`;
    - `sim.BANK = 3`.
  - Setting up and firing:
    - `sim.new(B, size, rng): State`;
    - `sim.add_chunk(state, owner, heading, cells): Chunk`, which errors on a wall or a taken cell;
    - `sim.fire(state, shots): {board.Tri}`.
  - `sim.tick(state): TickResult`.
  - Aiming:
    - `sim.placements(state, p, shape): {board.Spot}`;
    - `sim.legal(state, p, cells): boolean`;
    - `sim.can_head(p, h): boolean`;
    - `sim.ghost(state, p, cells, heading): Ghost`.
  - `sim.lock_in(state, shots): LockResult`.
  - Outcome: `sim.alive(state): integer`, `sim.over(state): boolean`, `sim.winner(state): integer`.

- [ ] **Step 1: Write the rules tests**

Replace `tests/sim_test.tl` with:

```lua
local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local A = require("tests.assert")

local type Tri = board.Tri
local type State = sim.State

local record T
end

local WALL, MIDDLE = board.WALL, board.MIDDLE
local E <const>, SE <const>, SW <const>, W <const> = 1, 2, 3, 4

--- A 6-2 board (central side 3, notch 2) with chunks of four.
local function fresh(): State
   return sim.new(board.new(3, 2), 4, bc.seeded_random(1))
end

local function tri(i: integer, color: bc.Color): Tri
   return { i = i, color = color }
end

local function kind(s: State, i: integer): integer
   return s.board.kind[i]
end

local function step(s: State, i: integer, h: integer): integer
   return i + s.board.step[h]
end

local function pass(s: State, i: integer, h: integer): integer
   return i + s.board.pass[h][board.facing(i)]
end

--- The first board index satisfying `pred`.
local function find(s: State, pred: function(integer): boolean): integer
   for _, i in ipairs(s.board.cells) do
      if pred(i) then return i end
   end
   error("no cell fits")
end

--- A middle cell from which heading h stays in the middle for `len` steps.
local function lane(s: State, h: integer, len: integer): integer
   return find(s, function(i: integer): boolean
      local j = i
      for _ = 1, len do
         if kind(s, j) ~= MIDDLE or kind(s, pass(s, j, h)) ~= MIDDLE then return false end
         j = step(s, j, h)
      end
      return kind(s, j) == MIDDLE
   end)
end

--- A legal aim for player p: bank slot 1, unrotated, first spot, straight across.
local function aim(s: State, p: integer): sim.Shot
   local shape = board.shape(s.board, s.players[p].bank[1])
   local spot = sim.placements(s, p, shape)[1]
   return {
      player = p, slot = 1, heading = board.HEADINGS[p][2],
      cells = board.place(s.board, shape, spot.x, spot.y),
   }
end

function T.new_match_starts_everyone_in_on_an_empty_matrix()
   local s = fresh()
   A.eq(#s.players, 3, "three players")
   for _, p in ipairs(s.players) do
      A.truthy(p.alive, "alive")
      A.eq(#p.bank, 3, "bank of three")
      for _, chunk in ipairs(p.bank) do A.eq(#chunk, 4, "chunk size") end
   end
   for i = 1, s.board.size do
      A.eq(s.occ[i], 0, "empty")
      A.eq(s.paint[i], 0, "unpainted")
   end
   A.eq(sim.alive(s), 3, "all in")
   A.truthy(not sim.over(s), "not over")
end

function T.add_chunk_refuses_walls_and_taken_cells()
   local s = fresh()
   local wall = find(s, function(i: integer): boolean return kind(s, i) > 0 and kind(s, i + 2) == WALL end) + 2
   A.truthy(not pcall(sim.add_chunk, s, 1, E, { tri(wall, "red") }), "wall refused")
   local i = lane(s, E, 1)
   sim.add_chunk(s, 1, E, { tri(i, "red") })
   A.truthy(not pcall(sim.add_chunk, s, 2, E, { tri(i, "green") }), "taken cell refused")
end

function T.free_chunk_slides_one_step_per_tick()
   local s = fresh()
   local i = lane(s, E, 2)
   local c = sim.add_chunk(s, 2, E, { tri(i, "red") })
   A.truthy(c.flying, "a fired chunk is in flight")
   local r = sim.tick(s)
   A.eq(r.moved, 1, "one chunk moved")
   A.eq(s.occ[i], 0, "old cell vacated")
   A.eq(s.occ[step(s, i, E)], c.id, "advanced one step")
   A.eq(s.paint[step(s, i, E)], bc.CODE.red, "paint moves with it")
   A.truthy(c.moved and c.flying, "moved and still flying")
end

function T.your_own_dashed_line_lets_you_out()
   local s = fresh()
   local i = find(s, function(i: integer): boolean
      return kind(s, i) == 3 and kind(s, step(s, i, W)) == MIDDLE and kind(s, pass(s, i, W)) ~= WALL
   end)
   sim.add_chunk(s, 3, W, { tri(i, "red") })
   local r = sim.tick(s)
   A.eq(r.moved, 1, "crossed into the middle")
   A.eq(sim.alive(s), 3, "nobody out")
end

function T.an_opponents_dashed_line_stops_you()
   local s = fresh()
   local i = find(s, function(i: integer): boolean
      return kind(s, i) == MIDDLE and (kind(s, step(s, i, SW)) == 1 or kind(s, pass(s, i, SW)) == 1)
   end)
   local c = sim.add_chunk(s, 3, SW, { tri(i, "red") })
   for _ = 1, 3 do
      local r = sim.tick(s)
      A.eq(r.moved, 0, "held at Player 1's dashed line")
      A.eq(#r.out, 0, "nobody out")
   end
   A.truthy(not c.flying, "a stopped chunk is at rest")
end

function T.friendly_fire_knocks_out_the_owner()
   local s = fresh()
   local i = find(s, function(i: integer): boolean
      return kind(s, i) == 3 and kind(s, step(s, i, SW)) == WALL
   end)
   local c = sim.add_chunk(s, 3, SW, { tri(i, "blue") })
   local r = sim.tick(s)
   A.eq(r.moved, 0, "stopped by the wall")
   A.eq(#r.out, 1, "one player out")
   A.eq(r.out[1], 3, "Player 3 hit their own back wall")
   A.eq(#r.hits, 1, "one triangle hit")
   A.eq(r.hits[1].i, i, "the hit is where the triangle is")
   A.truthy(not s.players[3].alive, "out")
   A.eq(s.players[3].out, "friendly", "out by friendly fire")
   A.eq(s.occ[i], c.id, "the chunk stays on the board")
   local again = sim.tick(s)
   A.eq(#again.out, 0, "only knocked out once")
   A.eq(#again.hits, 0, "an out player's hits don't count")
end

--- At a notch corner the middle's corner triangles can step straight into the
--- notch wall. That's a stop like any other, not friendly fire.
function T.a_wall_met_from_the_middle_is_only_a_stop()
   local s = fresh()
   local i = find(s, function(i: integer): boolean
      return kind(s, i) == MIDDLE and kind(s, step(s, i, SE)) == WALL
   end)
   sim.add_chunk(s, 2, SE, { tri(i, "green") })
   local r = sim.tick(s)
   A.eq(r.moved, 0, "stopped")
   A.eq(#r.out, 0, "nobody out")
   A.eq(sim.alive(s), 3, "all still in")
end

function T.head_on_chunks_block_each_other()
   local s = fresh()
   local i = lane(s, E, 2)
   sim.add_chunk(s, 2, E, { tri(i, "red") })
   sim.add_chunk(s, 1, W, { tri(step(s, i, E), "green") })
   A.eq(sim.tick(s).moved, 0, "nothing moved")
end

function T.a_passed_over_cell_blocks_even_when_the_destination_is_free()
   local s = fresh()
   local i = lane(s, E, 2)
   sim.add_chunk(s, 2, E, { tri(i, "red") })
   sim.add_chunk(s, 1, W, { tri(pass(s, i, E), "green") })
   A.eq(sim.tick(s).moved, 0, "nothing moved")
end

function T.a_convoy_moves_together()
   local s = fresh()
   local i = lane(s, E, 3)
   local x = sim.add_chunk(s, 2, E, { tri(i, "red") })
   local y = sim.add_chunk(s, 2, E, { tri(step(s, i, E), "green") })
   A.eq(sim.tick(s).moved, 2, "both moved")
   A.eq(s.occ[step(s, i, E)], x.id, "X advanced")
   A.eq(s.occ[step(s, step(s, i, E), E)], y.id, "Y advanced")
end

function T.a_blocked_chunk_stalls_the_one_behind()
   local s = fresh()
   local i = lane(s, E, 3)
   local j = step(s, i, E)
   sim.add_chunk(s, 2, E, { tri(i, "red") })
   sim.add_chunk(s, 2, E, { tri(j, "green") })
   sim.add_chunk(s, 1, W, { tri(step(s, j, E), "red") })
   A.eq(sim.tick(s).moved, 0, "the convoy stalls behind the blocker")
end

function T.clear_on_contact_removes_exactly_the_pair()
   local s = fresh()
   local B = s.board
   -- P and Q block each other head-on, so P stands still while X slides in
   -- along the row below (or above) and lands edge to edge with it.
   local function v_of(i: integer): integer return i + B.near[board.facing(i)][3] end
   local i = find(s, function(i: integer): boolean
      local v = v_of(i)
      for _, j in ipairs({ i, i + 1, i + 2, v, v - 1, v - 2 }) do
         if kind(s, j) ~= MIDDLE then return false end
      end
      return true
   end)
   local v = v_of(i)
   sim.add_chunk(s, 1, E, { tri(i, "red") })
   local q = sim.add_chunk(s, 2, W, { tri(i + 2, "green") })
   sim.add_chunk(s, 3, E, { tri(v - 2, "red") })
   local r = sim.tick(s)
   A.eq(r.moved, 1, "only X moved")
   A.eq(#r.cleared, 2, "the red pair cleared")
   A.eq(s.occ[i], 0, "P gone")
   A.eq(s.occ[v], 0, "X gone")
   A.eq(s.occ[i + 2], q.id, "Q untouched")
end

function T.fire_puts_chunks_in_flight_and_refills_the_bank()
   local s = fresh()
   local before = s.players[1].bank[1]
   local shot = aim(s, 1)
   sim.fire(s, { shot })
   A.eq(#s.chunks, 1, "one chunk on the board")
   A.eq(s.chunks[1].owner, 1, "Player 1's")
   A.eq(s.chunks[1].heading, board.HEADINGS[1][2], "on the chosen heading")
   A.truthy(s.chunks[1].flying, "in flight")
   A.truthy(s.players[1].bank[1] ~= before, "slot refilled")
   A.eq(#s.players[1].bank, 3, "bank still three")
end

function T.fire_clears_same_colour_neighbours_at_once()
   local s = fresh()
   local i = lane(s, E, 1)
   local cleared = sim.fire(s, {
      { player = 1, heading = E, cells = { tri(i, "red") } },
      { player = 2, heading = E, cells = { tri(i + 1, "red") } },
   })
   A.eq(#cleared, 2, "both cleared")
   A.eq(#s.chunks, 0, "nothing left")
end

function T.a_chunk_cut_in_two_splits_into_pieces()
   local s = fresh()
   local B = s.board
   -- R stands still; a chain fired with its red middle against R loses that
   -- middle, and its two ends go on as separate chunks.
   local function m_of(i: integer): integer return i + B.near[board.facing(i)][3] end
   local i = find(s, function(i: integer): boolean
      local m = m_of(i)
      for _, j in ipairs({ i, m - 1, m, m + 1 }) do
         if kind(s, j) ~= MIDDLE then return false end
      end
      return true
   end)
   local m = m_of(i)
   sim.add_chunk(s, 1, E, { tri(i, "red") })
   local cleared = sim.fire(s, { {
      player = 3, heading = W,
      cells = { tri(m - 1, "green"), tri(m, "red"), tri(m + 1, "blue") },
   } })
   A.eq(#cleared, 2, "R and the red middle cleared")
   local pieces = 0
   for _, chunk in ipairs(s.chunks) do
      if chunk.owner == 3 then
         pieces = pieces + 1
         A.eq(#chunk.cells, 1, "each piece is one triangle")
         A.eq(chunk.heading, W, "pieces keep the heading")
         A.eq(s.by_id[chunk.id], chunk, "pieces are indexed")
      end
   end
   A.eq(pieces, 2, "two independent pieces")
end

function T.placements_lie_in_the_home_touch_the_back_wall_and_skip_taken_cells()
   local s = fresh()
   local B = s.board
   local one = board.shape(B, { { a = 0, b = 0, color = "red" } }) -- one point-down triangle
   local want = 0
   for _, i in ipairs(B.homes[1]) do
      if B.touch[i] and i % 2 == 1 then want = want + 1 end
   end
   local spots = sim.placements(s, 1, one)
   A.eq(#spots, want, "one spot per point-down triangle touching the back wall")
   for _, spot in ipairs(spots) do
      A.truthy(sim.legal(s, 1, board.place(B, one, spot.x, spot.y)), "every spot is legal")
   end
   local first = board.place(B, one, spots[1].x, spots[1].y)
   sim.add_chunk(s, 1, board.HEADINGS[1][2], first)
   A.eq(#sim.placements(s, 1, one), want - 1, "a taken cell is skipped")
   A.truthy(not sim.legal(s, 1, first), "and no longer legal")
end

function T.nothing_is_legal_outside_your_home_or_away_from_the_back_wall()
   local s = fresh()
   local B = s.board
   local mid = find(s, function(i: integer): boolean return kind(s, i) == MIDDLE end)
   A.truthy(not sim.legal(s, 1, { tri(mid, "red") }), "the middle is not your home")
   local theirs = B.homes[2][1]
   A.truthy(not sim.legal(s, 1, { tri(theirs, "red") }), "nor is another home")
   local inner = find(s, function(i: integer): boolean return kind(s, i) == 1 and not B.touch[i] end)
   A.truthy(not sim.legal(s, 1, { tri(inner, "red") }), "a chunk must touch the back wall")
   A.truthy(not sim.legal(s, 1, {}), "an empty aim is not legal")
end

function T.a_full_home_has_no_placements()
   local s = fresh()
   local B = s.board
   local all: {Tri} = {}
   for _, i in ipairs(B.homes[1]) do all[#all + 1] = tri(i, "red") end
   sim.add_chunk(s, 1, board.HEADINGS[1][2], all)
   local one = board.shape(B, { { a = 0, b = 0, color = "red" } })
   A.eq(#sim.placements(s, 1, one), 0, "nothing fits")
end

function T.the_ghost_stops_at_chunks_at_rest_and_looks_through_flying_ones()
   local s = fresh()
   local B = s.board
   local h = board.HEADINGS[3][2] -- W, straight across
   local i = find(s, function(i: integer): boolean return kind(s, i) == 3 and B.touch[i] end)
   local shot = { tri(i, "red") }
   local g = sim.ghost(s, 3, shot, h)
   A.eq(g.look, "clear", "an empty board: it lands clear")
   local last = g.cells[1]
   A.truthy(last ~= i, "it travelled")
   local blocker = sim.add_chunk(s, 1, E, { tri(last, "green") })
   blocker.flying = false
   A.eq(sim.ghost(s, 3, shot, h).cells[1], last - B.step[h], "stops one step short of a chunk at rest")
   blocker.flying = true
   A.eq(sim.ghost(s, 3, shot, h).cells[1], last, "looks straight through a chunk in flight")
end

function T.the_ghost_warns_when_a_pile_keeps_you_in_your_home()
   local s = fresh()
   local h = board.HEADINGS[3][2]
   local i = find(s, function(i: integer): boolean
      return kind(s, i) == 3 and kind(s, step(s, i, h)) == 3 and kind(s, pass(s, i, h)) == 3
   end)
   local pile = sim.add_chunk(s, 1, E, { tri(step(s, i, h), "green") })
   pile.flying = false
   local g = sim.ghost(s, 3, { tri(i, "red") }, h)
   A.eq(g.cells[1], i, "can't move at all")
   A.eq(g.look, "home", "lands in your own home")
end

function T.the_ghost_calls_out_friendly_fire()
   local s = fresh()
   local i = find(s, function(i: integer): boolean
      return kind(s, i) == 3 and kind(s, step(s, i, SW)) == WALL
   end)
   A.eq(sim.ghost(s, 3, { tri(i, "red") }, SW).look, "friendly", "runs into your back wall")
   -- One doomed triangle is enough, even if the rest would get out.
   local out = find(s, function(j: integer): boolean
      return kind(s, j) == 3 and kind(s, step(s, j, SW)) == MIDDLE
   end)
   A.eq(sim.ghost(s, 3, { tri(out, "red") }, SW).look ~= "friendly", true, "this one alone gets out")
   A.eq(sim.ghost(s, 3, { tri(i, "red"), tri(out, "green") }, SW).look, "friendly", "together: friendly")
end

--- From every triangle of every home, on each of its player's headings, the
--- ghost comes to rest on the board -- never in a wall, never in an
--- opponent's home -- with and without chunks in the way.
function T.the_ghost_always_comes_to_rest_on_the_board()
   local s = fresh()
   local B = s.board
   local function sweep()
      for p = 1, 3 do
         for _, i in ipairs(B.homes[p]) do
            if s.occ[i] == 0 then
               for _, h in ipairs(board.HEADINGS[p]) do
                  local g = sim.ghost(s, p, { tri(i, "red") }, h)
                  local k = kind(s, g.cells[1])
                  A.truthy(k == MIDDLE or k == p, "rests on the board in the middle or at home")
               end
            end
         end
      end
   end
   sweep()
   local mid = 0
   for _, i in ipairs(B.cells) do
      if kind(s, i) == MIDDLE and i % 5 == 0 then
         sim.add_chunk(s, 1, E, { tri(i, "blue") }).flying = false
         mid = mid + 1
      end
   end
   A.truthy(mid > 0, "some chunks at rest in the way")
   sweep()
end

function T.an_out_players_chunks_keep_sliding()
   local s = fresh()
   local i = lane(s, E, 2)
   local c = sim.add_chunk(s, 2, E, { tri(i, "red") })
   s.players[2].alive, s.players[2].out = false, "stuck"
   A.eq(sim.tick(s).moved, 1, "still slides")
   A.eq(s.occ[step(s, i, E)], c.id, "one step on")
end

function T.lock_in_fires_legal_aims_and_knocks_out_the_rest()
   local s = fresh()
   local good = aim(s, 1)
   local bad = aim(s, 3)
   bad.cells = { tri(find(s, function(i: integer): boolean return kind(s, i) == MIDDLE end), "red") }
   local before = s.players[1].bank[1]
   local r = sim.lock_in(s, { good, bad }) -- Player 2 has no aim at all
   A.eq(#r.fired, 1, "one shot fired")
   A.eq(r.fired[1].player, 1, "Player 1's")
   A.truthy(s.players[1].bank[1] ~= before, "its slot refilled")
   A.eq(#r.out, 2, "two out")
   A.eq(r.out[1], 2, "Player 2 had no aim")
   A.eq(r.out[2], 3, "Player 3's aim was illegal")
   A.eq(s.players[2].out, "stuck", "stuck")
   A.eq(s.players[3].out, "stuck", "stuck")
   A.eq(sim.winner(s), 1, "last one standing")
   A.truthy(sim.over(s), "match over")
end

function T.lock_in_refuses_a_heading_that_is_not_yours()
   local s = fresh()
   local shot = aim(s, 1)
   shot.heading = board.HEADINGS[3][1] -- SW belongs to Player 3 (and 2), not 1
   local r = sim.lock_in(s, { shot, aim(s, 2), aim(s, 3) })
   A.eq(#r.out, 1, "one out")
   A.eq(r.out[1], 1, "Player 1")
end

function T.lock_in_leaves_players_who_are_already_out_alone()
   local s = fresh()
   s.players[2].alive, s.players[2].out = false, "friendly"
   local r = sim.lock_in(s, { aim(s, 1), aim(s, 3) })
   A.eq(#r.out, 0, "nobody new out")
   A.eq(#r.fired, 2, "both live players fired")
   A.eq(s.players[2].out, "friendly", "still out the way they went out")
end

function T.last_one_standing_wins_and_all_out_at_once_is_a_draw()
   local s = fresh()
   A.eq(sim.winner(s), nil, "no winner at the start")
   s.players[1].alive = false
   A.eq(sim.winner(s), nil, "two left")
   A.truthy(not sim.over(s), "still playing")
   local r = sim.lock_in(s, {}) -- neither of the last two has an aim
   A.eq(#r.out, 2, "both out together")
   A.truthy(sim.over(s), "over")
   A.eq(sim.winner(s), nil, "a draw")
end

function T.an_empty_board_tick_moves_nothing()
   local s = fresh()
   local r = sim.tick(s)
   A.eq(r.moved, 0, "nothing to move")
   A.eq(#r.cleared, 0, "nothing to clear")
end

return T
```

- [ ] **Step 2: Run them and watch them fail**

Run: `tl run tests/run.tl -- sim`
Expected: `1 passed, 27 failed`. The failures say things like `attempt to index a nil value (field 'board')`, because the old `sim.new` takes a size where the new one takes a board.

- [ ] **Step 3: Write the engine**

Replace `src/sim.tl` with:

```lua
--- The blunkychunks rules engine: integer logic on the board matrix from
--- board.tl. Nothing here knows about pixels or LOVE.
---
--- A match is a `State`: the board, the chunks on it with their headings, an
--- occupancy matrix, and each player's bank and status. Play is continuous and
--- the caller runs two clocks at once:
---
---   * every tick, `tick` slides each chunk that can move by one step;
---   * every shot clock, `lock_in` fires each live player's aim, and knocks
---     out anyone without a legal one.
---
--- A step is blocked by a wall, by another player's home (their dashed line),
--- or by a triangle that isn't moving the same way. Your own dashed line never
--- blocks you. A triangle stopped by a wall while still in its owner's home has
--- hit their back wall, and the owner is out. After every tick and every
--- lock-in, two same-coloured triangles of different chunks that share an edge
--- both clear, and chunks that fall apart split, keeping heading and owner.

local bc = require("blunkychunks")
local board = require("board")

local record sim
   enum Out
      "stuck" -- had no legal aim when the shot clock ran out
      "friendly" -- hit their own back wall
   end

   enum Look
      "clear" -- the ghost lands clear of your home
      "home" -- the ghost lands with part still in your home
      "friendly" -- some triangle can never leave your home on this heading
   end

   record Chunk
      id: integer
      owner: integer
      heading: integer
      cells: {board.Tri}
      moved: boolean -- moved on the last tick, for animation
      flying: boolean -- fired since, or moved on, the last tick; ghosts look through it
   end

   record Player
      alive: boolean
      out: Out
      bank: {{bc.Cell}}
   end

   --- One player's aim for a shot clock: which bank slot it uses (nil for
   --- none), its heading and the triangles it would place.
   record Shot
      player: integer
      slot: integer
      heading: integer
      cells: {board.Tri}
   end

   record Ghost
      cells: {integer}
      look: Look
   end

   record TickResult
      moved: integer
      cleared: {board.Tri}
      hits: {board.Tri} -- triangles stopped by their own back wall
      out: {integer} -- players knocked out by those hits
   end

   record LockResult
      fired: {Shot}
      out: {integer} -- players with no legal aim
      cleared: {board.Tri}
   end

   record State
      board: board.Board
      size: integer -- triangles per generated chunk
      occ: {integer} -- per index: the chunk there, 0 if empty
      paint: {integer} -- per index: its colour's bc.CODE, 0 if empty
      chunks: {Chunk}
      by_id: {integer: Chunk}
      players: {Player}
      next_id: integer
      rng: function(): number
   end

   BANK: integer
end

local type Tri = board.Tri
local type Chunk = sim.Chunk
local type State = sim.State

local WALL <const> = board.WALL
local MIDDLE <const> = board.MIDDLE

sim.BANK = 3

--- A fresh match on board `B` with chunks of `size` triangles.
function sim.new(B: board.Board, size: integer, rng: function(): number): State
   local players: {sim.Player} = {}
   for p = 1, #board.PLAYERS do
      local bank: {{bc.Cell}} = {}
      for i = 1, sim.BANK do bank[i] = bc.generate(size, rng) end
      players[p] = { alive = true, bank = bank }
   end
   local occ, paint: {integer}, {integer} = {}, {}
   for i = 1, B.size do occ[i], paint[i] = 0, 0 end
   return {
      board = B,
      size = size,
      occ = occ,
      paint = paint,
      chunks = {},
      by_id = {},
      players = players,
      next_id = 1,
      rng = rng,
   }
end

local function new_chunk(state: State, owner: integer, heading: integer): Chunk
   local chunk: Chunk = {
      id = state.next_id,
      owner = owner,
      heading = heading,
      cells = {},
      moved = false,
      flying = true,
   }
   state.next_id = state.next_id + 1
   state.chunks[#state.chunks + 1] = chunk
   state.by_id[chunk.id] = chunk
   return chunk
end

local function occupy(state: State, chunk: Chunk, c: Tri)
   state.occ[c.i] = chunk.id
   state.paint[c.i] = bc.CODE[c.color]
end

--- Put a chunk on the board, in flight. Its cells must be free board cells;
--- this is also how tests build scenarios.
function sim.add_chunk(state: State, owner: integer, heading: integer, cells: {Tri}): Chunk
   for _, c in ipairs(cells) do
      if state.board.kind[c.i] == WALL then error(("cell %d is wall"):format(c.i)) end
      if state.occ[c.i] ~= 0 then error(("cell %d is already occupied"):format(c.i)) end
   end
   local chunk = new_chunk(state, owner, heading)
   for k, c in ipairs(cells) do
      chunk.cells[k] = { i = c.i, color = c.color }
      occupy(state, chunk, chunk.cells[k])
   end
   return chunk
end

--- Empty the cells in `gone` and return the chunks that lost any.
local function remove_cells(state: State, gone: {integer: boolean}): {Chunk}
   local touched: {Chunk} = {}
   local seen: {integer: boolean} = {}
   for i in pairs(gone) do
      local id = state.occ[i]
      if id ~= 0 then
         state.occ[i], state.paint[i] = 0, 0
         if not seen[id] then
            seen[id] = true
            touched[#touched + 1] = state.by_id[id]
         end
      end
   end
   for _, chunk in ipairs(touched) do
      local kept: {Tri} = {}
      for _, c in ipairs(chunk.cells) do
         if not gone[c.i] then kept[#kept + 1] = c end
      end
      chunk.cells = kept
   end
   return touched
end

--- Drop empty chunks.
local function prune(state: State)
   local kept: {Chunk} = {}
   for _, chunk in ipairs(state.chunks) do
      if #chunk.cells > 0 then
         kept[#kept + 1] = chunk
      else
         state.by_id[chunk.id] = nil
      end
   end
   state.chunks = kept
end

--- Split `chunk` into edge-connected pieces. The first keeps the chunk's
--- identity; each other one becomes a new chunk with the same owner, heading
--- and flags.
local function split(state: State, chunk: Chunk)
   local near = state.board.near
   local pool: {integer: Tri} = {}
   for _, c in ipairs(chunk.cells) do pool[c.i] = c end

   local pieces: {{Tri}} = {}
   for _, start in ipairs(chunk.cells) do
      if pool[start.i] then
         local piece: {Tri} = {}
         local queue: {Tri} = { start }
         pool[start.i] = nil
         while #queue > 0 do
            local c = table.remove(queue)
            piece[#piece + 1] = c
            for _, d in ipairs(near[board.facing(c.i)]) do
               local other = pool[c.i + d]
               if other then
                  pool[c.i + d] = nil
                  queue[#queue + 1] = other
               end
            end
         end
         pieces[#pieces + 1] = piece
      end
   end

   if #pieces <= 1 then return end
   chunk.cells = pieces[1]
   for k = 2, #pieces do
      local piece = new_chunk(state, chunk.owner, chunk.heading)
      piece.moved, piece.flying = chunk.moved, chunk.flying
      piece.cells = pieces[k]
      for _, c in ipairs(piece.cells) do state.occ[c.i] = piece.id end
   end
end

--- Clear every pair of edge-adjacent same-colour triangles of different
--- chunks, then split whatever fell apart. Returns the cleared triangles.
local function resolve_clears(state: State): {Tri}
   local near, occ, paint = state.board.near, state.occ, state.paint
   local gone: {integer: boolean} = {}
   local cleared: {Tri} = {}
   for _, chunk in ipairs(state.chunks) do
      for _, c in ipairs(chunk.cells) do
         for _, d in ipairs(near[board.facing(c.i)]) do
            local j = c.i + d
            local other = occ[j]
            if other ~= 0 and other ~= chunk.id and paint[j] == paint[c.i] then
               if not gone[c.i] then
                  gone[c.i] = true
                  cleared[#cleared + 1] = { i = c.i, color = c.color }
               end
               if not gone[j] then
                  gone[j] = true
                  cleared[#cleared + 1] = { i = j, color = bc.COLORS[paint[j]] }
               end
            end
         end
      end
   end
   if #cleared == 0 then return cleared end
   for _, chunk in ipairs(remove_cells(state, gone)) do
      if #chunk.cells > 0 then split(state, chunk) end
   end
   prune(state)
   return cleared
end

--- Put the shots on the board, refilling each fired bank slot. Chunks that
--- land touching a same-colour triangle clear at once.
function sim.fire(state: State, shots: {sim.Shot}): {Tri}
   for _, shot in ipairs(shots) do
      sim.add_chunk(state, shot.player, shot.heading, shot.cells)
      if shot.slot then
         state.players[shot.player].bank[shot.slot] = bc.generate(state.size, state.rng)
      end
   end
   return resolve_clears(state)
end

--- Advance the board one step.
function sim.tick(state: State): sim.TickResult
   local B = state.board
   local kind, occ = B.kind, state.occ
   local result: sim.TickResult = { moved = 0, cleared = {}, hits = {}, out = {} }

   -- Walls and dashed lines never move, so each chunk checks them once and
   -- keeps the list of cells it would pass over or land on.
   local moving: {integer: boolean} = {}
   local sweeps: {integer: {integer}} = {}
   local hit_wall: {integer: boolean} = {}
   for _, chunk in ipairs(state.chunks) do
      chunk.moved = false
      local step, pass = B.step[chunk.heading], B.pass[chunk.heading]
      local live = state.players[chunk.owner].alive
      local list: {integer} = {}
      local free = true
      for _, c in ipairs(chunk.cells) do
         local here = kind[c.i]
         local hit = false
         for _, j in ipairs({ c.i + pass[board.facing(c.i)], c.i + step }) do
            local k = kind[j]
            if k == WALL then
               free = false
               if here == chunk.owner and live then hit = true end
            elseif k ~= MIDDLE and k ~= chunk.owner then
               free = false
            else
               list[#list + 1] = j
            end
         end
         if hit then
            result.hits[#result.hits + 1] = { i = c.i, color = c.color }
            hit_wall[chunk.owner] = true
         end
      end
      if free then
         moving[chunk.id] = true
         sweeps[chunk.id] = list
      end
   end

   -- Fixpoint: block anything whose sweep meets a triangle that is standing
   -- still or moving another way, or crosses the sweep of such a chunk.
   local changed = true
   while changed do
      changed = false
      local claims: {integer: Chunk} = {}
      for _, chunk in ipairs(state.chunks) do
         if moving[chunk.id] then
            local blocked = false
            for _, j in ipairs(sweeps[chunk.id]) do
               local other = occ[j]
               if other ~= 0 and other ~= chunk.id
                  and (not moving[other] or state.by_id[other].heading ~= chunk.heading) then
                  blocked = true
                  break
               end
               local rival = claims[j]
               if rival and rival ~= chunk and rival.heading ~= chunk.heading then
                  blocked = true
                  moving[rival.id] = nil
                  break
               end
               claims[j] = chunk
            end
            if blocked then
               moving[chunk.id] = nil
               changed = true
            end
         end
      end
   end

   -- Move everything that can, all at once.
   local movers: {Chunk} = {}
   for _, chunk in ipairs(state.chunks) do
      if moving[chunk.id] then
         movers[#movers + 1] = chunk
         for _, c in ipairs(chunk.cells) do occ[c.i], state.paint[c.i] = 0, 0 end
      end
   end
   for _, chunk in ipairs(movers) do
      chunk.moved = true
      local step = B.step[chunk.heading]
      for _, c in ipairs(chunk.cells) do
         c.i = c.i + step
         occupy(state, chunk, c)
      end
   end
   result.moved = #movers
   for _, chunk in ipairs(state.chunks) do chunk.flying = chunk.moved end

   for p, pl in ipairs(state.players) do
      if hit_wall[p] and pl.alive then
         pl.alive, pl.out = false, "friendly"
         result.out[#result.out + 1] = p
      end
   end

   result.cleared = resolve_clears(state)
   return result
end

--- Every anchor where `shape` is a legal placement for player `p`: wholly in
--- their home, on free cells, with some triangle touching their back wall.
function sim.placements(state: State, p: integer, shape: board.Shape): {board.Spot}
   local B = state.board
   local kind, touch, occ, w = B.kind, B.touch, state.occ, B.w
   local box = B.box[p]
   local out: {board.Spot} = {}
   -- Anchors have even x. The home's box sits at least two columns in from
   -- the matrix's edges, so starting two short of it can't wrap a row.
   local x0 = box[1] - 2 - box[1] % 2
   for y = box[3], box[4] - shape.h do
      for x = x0, box[2] - shape.w, 2 do
         local ok, touching = true, false
         for _, o in ipairs(shape.cells) do
            local i = (y + o.dy - 1) * w + x + o.dx
            if kind[i] ~= p or occ[i] ~= 0 then
               ok = false
               break
            end
            if touch[i] then touching = true end
         end
         if ok and touching then out[#out + 1] = { x = x, y = y } end
      end
   end
   return out
end

--- Is `cells` a legal placement for player `p` right now?
function sim.legal(state: State, p: integer, cells: {Tri}): boolean
   if not cells or #cells == 0 then return false end
   local B = state.board
   local touching = false
   for _, c in ipairs(cells) do
      if B.kind[c.i] ~= p or state.occ[c.i] ~= 0 then return false end
      if B.touch[c.i] then touching = true end
   end
   return touching
end

--- Can player `p` fire heading `h`?
function sim.can_head(p: integer, h: integer): boolean
   for _, x in ipairs(board.HEADINGS[p]) do
      if x == h then return true end
   end
   return false
end

--- Where `cells`, fired by `p` on `heading`, would come to rest: slid against
--- walls, other players' homes and chunks at rest, looking straight through
--- chunks in flight (and through the other players' aims, which aren't on the
--- board yet). Its look is "friendly" if any triangle can't leave p's home on
--- this heading -- pure geometry, so it holds whatever is in the way --
--- otherwise "home" if it lands with part in p's home, otherwise "clear".
function sim.ghost(state: State, p: integer, cells: {Tri}, heading: integer): sim.Ghost
   local B = state.board
   local kind, occ, by_id = B.kind, state.occ, state.by_id
   local step, pass = B.step[heading], B.pass[heading]

   local friendly = false
   for _, c in ipairs(cells) do
      local i = c.i
      while kind[i] == p do
         if kind[i + pass[board.facing(i)]] == WALL or kind[i + step] == WALL then
            friendly = true
            break
         end
         i = i + step
      end
      if friendly then break end
   end

   local at: {integer} = {}
   for k, c in ipairs(cells) do at[k] = c.i end
   local function stops(j: integer): boolean
      local k = kind[j]
      if k == WALL or (k ~= MIDDLE and k ~= p) then return true end
      local id = occ[j]
      return id ~= 0 and not by_id[id].flying
   end
   while true do
      local blocked = false
      for _, i in ipairs(at) do
         if stops(i + pass[board.facing(i)]) or stops(i + step) then
            blocked = true
            break
         end
      end
      if blocked then break end
      for k = 1, #at do at[k] = at[k] + step end
   end

   local look: sim.Look = "clear"
   if friendly then
      look = "friendly"
   else
      for _, i in ipairs(at) do
         if kind[i] == p then look = "home" end
      end
   end
   return { cells = at, look = look }
end

--- The shot clock ran out: every live player's aim fires together. Anyone
--- alive without a legal aim (none in `shots`, a placement that no longer
--- fits, or a heading that isn't theirs) is out. Aims are all checked before
--- any is placed; they can't collide, as each lies in its own home.
function sim.lock_in(state: State, shots: {sim.Shot}): sim.LockResult
   local result: sim.LockResult = { fired = {}, out = {}, cleared = {} }
   local aim: {integer: sim.Shot} = {}
   for _, shot in ipairs(shots) do
      if not aim[shot.player] then aim[shot.player] = shot end
   end
   for p, pl in ipairs(state.players) do
      if pl.alive then
         local shot = aim[p]
         if shot and sim.can_head(p, shot.heading) and sim.legal(state, p, shot.cells) then
            result.fired[#result.fired + 1] = shot
         else
            pl.alive, pl.out = false, "stuck"
            result.out[#result.out + 1] = p
         end
      end
   end
   result.cleared = sim.fire(state, result.fired)
   return result
end

--- How many players are still in.
function sim.alive(state: State): integer
   local n = 0
   for _, pl in ipairs(state.players) do
      if pl.alive then n = n + 1 end
   end
   return n
end

--- Is the match over: at most one player left?
function sim.over(state: State): boolean
   return sim.alive(state) <= 1
end

--- The last player standing, or nil (still playing, or a draw).
function sim.winner(state: State): integer
   if sim.alive(state) ~= 1 then return nil end
   for p, pl in ipairs(state.players) do
      if pl.alive then return p end
   end
   return nil
end

return sim
```

- [ ] **Step 4: Run the tests and the type check**

Run: `tl run tests/run.tl -- board sim`
Expected: `41 passed, 0 failed`

Run: `tl check blunkychunks.tl board.tl src/sim.tl tests/sim_test.tl tests/run.tl`
Expected: no output.

- [ ] **Step 5: Check that the key rules are really pinned**

Break each rule in turn, run `tl run tests/run.tl -- sim`, and put the line back with `git checkout src/sim.tl` before trying the next:

| Edit in `src/sim.tl` | Test that must fail |
| --- | --- |
| `elseif k ~= MIDDLE and k ~= chunk.owner then` → `elseif false then` | `an_opponents_dashed_line_stops_you` |
| `if here == chunk.owner and live then hit = true end` → `if live then hit = true end` | `a_wall_met_from_the_middle_is_only_a_stop` |
| `return id ~= 0 and not by_id[id].flying` → `return id ~= 0` | `the_ghost_stops_at_chunks_at_rest_and_looks_through_flying_ones` |

Expected: each edit fails exactly that one test (`27 passed, 1 failed`).

- [ ] **Step 6: Commit**

```bash
git add src/sim.tl tests/sim_test.tl
git commit -m "Rules: dashed lines, back walls, rotation-ready placements, ghosts and lock-in on the matrix"
```

---

### Task 3: Bots and the soak

**Files:**
- Replace: `src/bots.tl`
- Create: `tests/bots_test.tl`
- Replace: `tests/soak.tl`

**Interfaces:**
- Consumes: from Task 2: `sim.placements`, `sim.ghost`, `sim.legal`, `sim.lock_in`, `sim.tick`, `sim.over`, `sim.winner` and `sim.Shot`. From Task 1: `board.shape`, `board.place`, `board.HEADINGS`, `board.options`, `bc.rotate`.
- Produces:
  - `bots.choose(state, p): sim.Shot`, which returns nil when nothing fits;
  - `bots.plan(state, skip?): {sim.Shot}`: one shot for each live bot not in `skip`;
  - `bots.refresh(state, shots, skip?): {sim.Shot}`: keeps the shots that are still legal and re-chooses the rest.

- [ ] **Step 1: Write the bots tests**

Create `tests/bots_test.tl`:

```lua
local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local bots = require("bots")
local A = require("tests.assert")

local record T
end

local function fresh(): sim.State
   return sim.new(board.new(6, 5), 6, bc.seeded_random(3))
end

function T.choose_finds_a_legal_shot_that_lands_clear_on_an_empty_board()
   local s = fresh()
   for p = 1, 3 do
      local shot = bots.choose(s, p)
      A.truthy(shot, "found a shot")
      A.eq(shot.player, p, "for the right player")
      A.truthy(sim.legal(s, p, shot.cells), "legal")
      A.truthy(sim.can_head(p, shot.heading), "on one of their headings")
      A.eq(sim.ghost(s, p, shot.cells, shot.heading).look, "clear", "lands clear")
   end
end

function T.choose_gives_up_when_nothing_fits()
   local s = fresh()
   local all: {board.Tri} = {}
   for _, i in ipairs(s.board.homes[1]) do all[#all + 1] = { i = i, color = "red" } end
   sim.add_chunk(s, 1, board.HEADINGS[1][2], all)
   A.eq(bots.choose(s, 1), nil, "a full home has no shot")
end

function T.plan_skips_the_human_and_players_who_are_out()
   local s = fresh()
   s.players[2].alive = false
   local shots = bots.plan(s, { [1] = true })
   A.eq(#shots, 1, "one bot left to plan")
   A.eq(shots[1].player, 3, "Player 3")
end

function T.refresh_keeps_legal_aims_and_replaces_stale_ones()
   local s = fresh()
   local shots = bots.plan(s)
   A.eq(#shots, 3, "three plans")
   local keep, stale = shots[1], shots[3]
   sim.add_chunk(s, 3, board.HEADINGS[3][2], { { i = stale.cells[1].i, color = "red" } })
   local again = bots.refresh(s, shots)
   A.eq(#again, 3, "still three")
   A.eq(again[1], keep, "the legal aim is kept as it was")
   A.truthy(again[3] ~= stale, "the stale aim is replaced")
   A.truthy(sim.legal(s, 3, again[3].cells), "by a legal one")
end

--- On a board whose homes are smaller than a chunk nothing ever fits, so the
--- first shot clock knocks everyone out together: a draw, not a crash.
function T.a_home_too_small_for_any_chunk_ends_in_a_draw()
   local s = sim.new(board.new(1, 1), 14, bc.seeded_random(1))
   A.eq(#s.board.homes[1], 4, "four triangles per home")
   A.eq(#bots.plan(s), 0, "no bot finds a shot")
   local r = sim.lock_in(s, bots.refresh(s, {}))
   A.eq(#r.out, 3, "all out at once")
   A.truthy(sim.over(s), "over")
   A.eq(sim.winner(s), nil, "a draw")
end

return T
```

- [ ] **Step 2: Run them and watch them fail**

Run: `tl run tests/run.tl -- bots`
Expected: `0 passed, 5 failed`. The old bots call `sim.blocked_set`, which no longer exists.

- [ ] **Step 3: Write the bots**

Replace `src/bots.tl` with:

```lua
--- Random bots. A bot tries its chunks and rotations in random order and a
--- few random spots for each, trying all three headings at every spot. It
--- takes the first shot whose ghost lands clear. Failing that it takes one that
--- lands in its own home, and fires on itself only when nothing else fits.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")

local record bots
end

local record Option
   slot: integer
   turn: integer
end

--- Random spots tried per chunk and rotation.
local TRIES <const> = 4

local RANK <const>: {sim.Look: integer} = { clear = 3, home = 2, friendly = 1 }

local function shuffle<T>(list: {T}, rng: function(): number)
   for i = #list, 2, -1 do
      local j = math.floor(rng() * i) + 1
      list[i], list[j] = list[j], list[i]
   end
end

--- Player `p`'s shot, or nil when nothing in their bank fits anywhere.
function bots.choose(state: sim.State, p: integer): sim.Shot
   local B, rng = state.board, state.rng
   local bank = state.players[p].bank
   local options: {Option} = {}
   for slot = 1, #bank do
      for turn = 0, 5 do options[#options + 1] = { slot = slot, turn = turn } end
   end
   shuffle(options, rng)

   local best: sim.Shot = nil
   local best_rank = 0
   for _, opt in ipairs(options) do
      local shape = board.shape(B, bc.rotate(bank[opt.slot], opt.turn))
      local spots = sim.placements(state, p, shape)
      for _ = 1, math.min(TRIES, #spots) do
         local spot = spots[math.floor(rng() * #spots) + 1]
         local cells = board.place(B, shape, spot.x, spot.y)
         local headings: {integer} = {}
         for k, h in ipairs(board.HEADINGS[p]) do headings[k] = h end
         shuffle(headings, rng)
         for _, h in ipairs(headings) do
            local rank = RANK[sim.ghost(state, p, cells, h).look]
            if rank > best_rank then
               best, best_rank = { player = p, slot = opt.slot, heading = h, cells = cells }, rank
               if rank == RANK.clear then return best end
            end
         end
      end
   end
   return best
end

--- Every live bot's shot for this shot clock, leaving out players in `skip`
--- (e.g. a human). Bots with nothing that fits have no shot.
function bots.plan(state: sim.State, skip?: {integer: boolean}): {sim.Shot}
   local shots: {sim.Shot} = {}
   for p, pl in ipairs(state.players) do
      if pl.alive and not (skip and skip[p]) then
         local shot = bots.choose(state, p)
         if shot then shots[#shots + 1] = shot end
      end
   end
   return shots
end

--- `shots` again at lock-in: chunks have moved since they were planned, so a
--- bot whose aim no longer fits (or who had none) chooses afresh.
function bots.refresh(state: sim.State, shots: {sim.Shot}, skip?: {integer: boolean}): {sim.Shot}
   local mine: {integer: sim.Shot} = {}
   for _, shot in ipairs(shots) do mine[shot.player] = shot end
   local out: {sim.Shot} = {}
   for p, pl in ipairs(state.players) do
      if pl.alive and not (skip and skip[p]) then
         local shot = mine[p]
         if not (shot and sim.legal(state, p, shot.cells)) then shot = bots.choose(state, p) end
         if shot then out[#out + 1] = shot end
      end
   end
   return out
end

return bots
```

- [ ] **Step 4: Run every suite**

Run: `tl run tests/run.tl`
Expected: `46 passed, 0 failed`

- [ ] **Step 5: Write the soak**

Replace `tests/soak.tl` with:

```lua
--- Headless soak: whole matches between random bots on the continuous clock,
--- checking the engine's invariants after every tick and every lock-in.
---
---   tl run tests/soak.tl -- --seeds 20 --diameter 22 --notch 8 --size 14
---
--- Each shot clock is 8 s of 0.28 s ticks, as in the game.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local bots = require("bots")

local argv = _G.arg as {string} or {}

local function num(name: string, fallback: integer): integer
   for i, a in ipairs(argv) do
      if a == "--" .. name then return math.floor(tonumber(argv[i + 1] or "") or fallback) end
   end
   return fallback
end

local n, r = board.options(argv)
local SEEDS = num("seeds", 5)
local SIZE = num("size", 14)
local TICKS_PER_CLOCK <const> = 28
local MAX_CLOCKS <const> = 400

local function check(state: sim.State, where: string)
   local B = state.board
   local cells = 0
   for i = 1, B.size do
      assert(state.occ[i] ~= nil and state.paint[i] ~= nil, where .. ": hole in the matrix at " .. i)
      if state.occ[i] ~= 0 then cells = cells + 1 end
      assert((state.occ[i] == 0) == (state.paint[i] == 0), where .. ": paint out of step at " .. i)
   end
   local total = 0
   for _, chunk in ipairs(state.chunks) do
      assert(#chunk.cells > 0, where .. ": empty chunk survived")
      assert(state.by_id[chunk.id] == chunk, where .. ": chunk missing from by_id")
      for _, c in ipairs(chunk.cells) do
         total = total + 1
         local k = B.kind[c.i]
         assert(k ~= board.WALL, where .. ": a triangle in the wall")
         assert(k == board.MIDDLE or k == chunk.owner, where .. ": a triangle in another player's home")
         assert(state.occ[c.i] == chunk.id, where .. ": occupancy mismatch")
         assert(state.paint[c.i] == bc.CODE[c.color], where .. ": paint mismatch")
         for _, d in ipairs(B.near[board.facing(c.i)]) do
            local other = state.occ[c.i + d]
            if other ~= 0 and other ~= chunk.id then
               assert(state.paint[c.i + d] ~= state.paint[c.i], where .. ": same-colour contact survived")
            end
         end
      end
   end
   assert(total == cells, where .. ": occupancy count mismatch")
end

local outs: {string: integer} = {}
for seed = 1, SEEDS do
   local state = sim.new(board.new(n, r), SIZE, bc.seeded_random(seed))
   local clocks, ticks, clears, hits = 0, 0, 0, 0
   local shots = bots.plan(state)
   while not sim.over(state) and clocks < MAX_CLOCKS do
      for t = 1, TICKS_PER_CLOCK do
         local res = sim.tick(state)
         ticks = ticks + 1
         clears = clears + #res.cleared
         hits = hits + #res.hits
         check(state, ("seed %d clock %d tick %d"):format(seed, clocks, t))
         if sim.over(state) then break end
      end
      if sim.over(state) then break end
      local res = sim.lock_in(state, bots.refresh(state, shots))
      clears = clears + #res.cleared
      check(state, ("seed %d clock %d lock-in"):format(seed, clocks))
      clocks = clocks + 1
      shots = bots.plan(state)
   end
   local how: {string} = {}
   for p, pl in ipairs(state.players) do
      how[p] = pl.alive and "in" or tostring(pl.out)
      if not pl.alive then outs[pl.out] = (outs[pl.out] or 0) + 1 end
   end
   local winner = sim.winner(state)
   print(("seed %2d: %3d clocks, %5d ticks, %4d clears, %d back-wall hits, %-8s %-8s %-8s %s"):format(
      seed, clocks, ticks, clears, hits, how[1], how[2], how[3],
      sim.over(state) and (winner and ("Player " .. winner .. " wins") or "draw") or "unfinished"))
end
print(("outs: %d stuck, %d friendly"):format(outs.stuck or 0, outs.friendly or 0))
print("ok")
```

- [ ] **Step 6: Run the soak at three sizes**

Run: `tl run tests/soak.tl -- --seeds 3`
Expected: three `seed` lines, each ending `Player N wins` or `draw`, then `outs: … stuck, 0 friendly` and `ok`. That takes about 3 s; the matches last about 20 clocks.

Run: `tl run tests/soak.tl -- --seeds 2 --diameter 12 --notch 5 --size 6`
Expected: two finished matches, then `ok`.

Run: `tl run tests/soak.tl -- --seeds 1 --diameter 34 --notch 17`
Expected: one finished match of about 50 clocks, then `ok`. That takes about 8 s.

Run: `tl check src/bots.tl tests/bots_test.tl tests/soak.tl`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add src/bots.tl tests/bots_test.tl tests/soak.tl
git commit -m "Bots that prefer clear landings, and a continuous-clock soak"
```

---

### Task 4: The README figures, and `layouts.tl` on `board.tl`

**Files:**
- Modify: `layouts.tl` (helpers only, on top of Will's uncommitted changes)
- Replace: `render.tl`
- Regenerate: `images/board.svg`, `images/shots.svg` (the README already ships both, made by this exact code)
- Delete: `images/turn-a.svg`, `images/turn-b.svg`

**Interfaces:**
- Consumes: `board.notched`, `board.rhombus`, `board.geometry`, `board.vertices`, `board.point`, `board.wall` and `board.options`. Also `sim.new`, `sim.placements`, `sim.ghost` and `sim.add_chunk`.
- Produces: `tl run render.tl [-- --diameter D --notch R --side S --size N --seed K --cells --out DIR]` writes `DIR/board.svg` and `DIR/shots.svg`.

- [ ] **Step 1: Record what `layouts.tl` draws now**

Run:

```bash
mkdir -p /tmp/blunky-layouts-before
tl run layouts.tl -- --out /tmp/blunky-layouts-before
tl run layouts.tl -- --board notched-hexagon-filled --diameter 12 --notch 5 --cells --out /tmp/blunky-layouts-before
```

- [ ] **Step 2: Point `layouts.tl` at `board.tl`'s shapes**

Replace the paragraph

```lua
--- Standalone: it reads board.strips for the lattice geometry but nothing in
--- the game consults these shapes.
```

with

```lua
--- It reads board.tl for the lattice geometry. The notched hexagon and its walls
--- are board.tl's own (board.notched, board.rhombus), so the notched pictures
--- show exactly the board the game plays on; nothing in the game consults the
--- other shapes.
```

Delete everything from `--- Which strip family, and which end of it, wall `j` sits at (as in board.tl).` down to the end of `local function rhombus`, which covers `WALL_STRIP`, `beyond`, `notched` and `rhombus`. Put this in its place:

```lua
--- The notched hexagon, as the game plays it.
local function notched(n: integer, r: integer): function(integer, integer): boolean
   return function(a: integer, b: integer): boolean return board.notched(n, r, a, b) end
end

```

In `layouts`, change both `contains = notched(n, r, { 1, 3, 5 }),` to `contains = notched(n, r),`. Then change

```lua
         field = function(a: integer, b: integer): boolean return rhombus(n + r + 1, a, b) end,
```

to

```lua
         field = function(a: integer, b: integer): boolean return board.rhombus(n + r + 1, a, b) end,
```

- [ ] **Step 3: Check the pictures didn't change**

Run:

```bash
mkdir -p /tmp/blunky-layouts-after
tl run layouts.tl -- --out /tmp/blunky-layouts-after
tl run layouts.tl -- --board notched-hexagon-filled --diameter 12 --notch 5 --cells --out /tmp/blunky-layouts-after
diff -rq /tmp/blunky-layouts-before /tmp/blunky-layouts-after && echo identical
```

Expected: `identical`

- [ ] **Step 4: Write the figure renderer**

Replace `render.tl` with:

```lua
--- Draws the README's figures of the notched board to SVG.
---
---   tl run render.tl                                   # images/board.svg, images/shots.svg
---   tl run render.tl -- --diameter 12 --notch 5         # another board
---   tl run render.tl -- --side 30 --seed 3              # bigger triangles, other chunks
---   tl run render.tl -- --cells                         # label every cell (x, y)
---   tl run render.tl -- --out /tmp/out                  # somewhere other than images/
---
--- board.svg is the empty board: the homes, their back walls and the dashed
--- lines. shots.svg is one aim per player with its heading and its ghost, one
--- of each look: Player 3 lands clear, a pile keeps Player 1's shot in their
--- own home, and Player 2 aims a heading that can't get out of their home.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")

local type XY = bc.XY
local type Tri = board.Tri
local type Board = board.Board

local INK <const> = "#1f2933"
local GRID <const> = "#c5ccd3"
local DASH <const> = "#52606d"
local MUTED <const> = "#7b8794"
local PAPER <const> = "#ffffff"
local AMBER <const> = "#d99a00"
local DANGER <const> = "#c0392b"
local STONE <const> = { "#b9ad9b", "#a99d8b", "#c4b9a8", "#9f9381", "#b2a593" }
local TINT <const> = { "#f9e4e5", "#e2e8f6", "#e2f0e5" }
local PAD <const> = 30.0
local TITLE_H <const> = 56.0

local function f(v: number): string
   return ("%.2f"):format(v)
end

--- An SVG being assembled line by line, with board space mapped onto it.
local record Canvas
   parts: {string}
   ox: number
   oy: number
   side: number
   board: Board
   w: number
   h: number
end

local function emit(c: Canvas, s: string)
   c.parts[#c.parts + 1] = s
end

local function poly(c: Canvas, i: integer, attrs: string)
   local out: {string} = {}
   for k, p in ipairs(board.corners(c.board.a[i], c.board.b[i], c.side)) do
      out[k] = f(p.x + c.ox) .. "," .. f(p.y + c.oy)
   end
   emit(c, ('    <polygon points="%s" %s/>'):format(table.concat(out, " "), attrs))
end

local function seg(c: Canvas, s: board.Seg)
   emit(c, ('    <line x1="%s" y1="%s" x2="%s" y2="%s"/>')
      :format(f(s.x1 + c.ox), f(s.y1 + c.oy), f(s.x2 + c.ox), f(s.y2 + c.oy)))
end

local function text(c: Canvas, p: XY, body: string, attrs: string)
   emit(c, ('  <text x="%s" y="%s" font-family="Helvetica, Arial, sans-serif" %s>%s</text>')
      :format(f(p.x + c.ox), f(p.y + c.oy), attrs, body))
end

--- A canvas fitted round the board and its drawn walls, with room for a title.
local function canvas(B: Board, side: number): Canvas
   local g = board.geometry(B, side)
   local xmin, xmax, ymin, ymax = math.huge, -math.huge, math.huge, -math.huge
   local all: {integer} = {}
   for _, i in ipairs(B.cells) do all[#all + 1] = i end
   for _, i in ipairs(g.walls) do all[#all + 1] = i end
   for _, i in ipairs(all) do
      for _, p in ipairs(board.corners(B.a[i], B.b[i], side)) do
         xmin, xmax = math.min(xmin, p.x), math.max(xmax, p.x)
         ymin, ymax = math.min(ymin, p.y), math.max(ymax, p.y)
      end
   end
   local w, h = xmax - xmin + 2 * PAD, ymax - ymin + 2 * PAD + TITLE_H
   local c: Canvas = {
      parts = {
         ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" width="%d" height="%d">')
            :format(f(w), f(h), math.floor(w + 0.5), math.floor(h + 0.5)),
         ('  <rect width="100%%" height="100%%" fill="%s"/>'):format(PAPER),
      },
      ox = PAD - xmin, oy = PAD + TITLE_H - ymin, side = side, board = B, w = w, h = h,
   }
   return c
end

local function title(c: Canvas, body: string, note: string)
   local attrs = 'text-anchor="middle" dominant-baseline="middle"'
   emit(c, ('  <text x="%s" y="%s" fill="%s" font-family="Helvetica, Arial, sans-serif" font-size="19" font-weight="600" %s>%s</text>')
      :format(f(c.w / 2), f(PAD + 4), INK, attrs, body))
   emit(c, ('  <text x="%s" y="%s" fill="%s" font-family="Helvetica, Arial, sans-serif" font-size="12" %s>%s</text>')
      :format(f(c.w / 2), f(PAD + 26), MUTED, attrs, note))
end

--- Stone walls, tinted homes, the grid, dashed lines and back walls.
local function draw_board(c: Canvas)
   local B = c.board
   local g = board.geometry(B, c.side)
   emit(c, '  <g stroke="none">')
   for _, i in ipairs(g.walls) do
      local a, b = B.a[i], B.b[i]
      poly(c, i, ('fill="%s"'):format(STONE[(a * a * 7 + b * b * 13 + a * b * 5 + a * 3 + b) % #STONE + 1]))
   end
   for _, i in ipairs(B.cells) do
      local k = B.kind[i]
      poly(c, i, ('fill="%s"'):format(k > 0 and TINT[k] or PAPER))
   end
   emit(c, "  </g>")
   emit(c, ('  <g stroke="%s" stroke-width="0.8" stroke-linecap="round">'):format(GRID))
   for _, s in ipairs(g.grid) do seg(c, s) end
   emit(c, "  </g>")
   emit(c, ('  <g stroke="%s" stroke-width="2" stroke-dasharray="6 5" stroke-linecap="round">'):format(DASH))
   for j = 0, 5 do seg(c, board.wall(B.n, c.side, j)) end
   emit(c, "  </g>")
   emit(c, ('  <g stroke="%s" stroke-width="3.5" stroke-linecap="round">'):format(INK))
   for _, s in ipairs(g.outline) do seg(c, s) end
   emit(c, "  </g>")
end

--- Each player's name in the corner diamond of their home, halfway out from
--- the central hexagon's corner to the board's.
local function draw_names(c: Canvas)
   local B = c.board
   for p, pl in ipairs(board.PLAYERS) do
      local t = pl.corner * math.pi / 3
      local rad = (B.n + B.r / 2) * c.side
      local x, y = rad * math.cos(t), rad * math.sin(t)
      local where = ({ "southwest", "northwest", "east" })[p]
      text(c, { x = x, y = y - 4 }, pl.name,
         ('fill="%s" font-size="18" font-weight="600" text-anchor="middle"'):format(pl.color))
      text(c, { x = x, y = y + 15 }, where, ('fill="%s" font-size="12" text-anchor="middle"'):format(MUTED))
   end
end

--- Every cell's (x, y), small, at its centroid.
local function draw_labels(c: Canvas)
   local B = c.board
   emit(c, ('  <g fill="%s" font-family="Helvetica, Arial, sans-serif" font-size="%s" text-anchor="middle" dominant-baseline="central">')
      :format(MUTED, f(c.side * 0.2)))
   for i = 1, B.size do
      if B.kind[i] ~= board.WALL then
         local p = board.centroid(B.a[i], B.b[i], c.side)
         local x, y = board.xy(B, i)
         local nudge = c.side * 0.05 * (bc.is_up(B.a[i], B.b[i]) and 1 or -1)
         emit(c, ('    <text x="%s" y="%s">%d,%d</text>'):format(f(p.x + c.ox), f(p.y + c.oy + nudge), x, y))
      end
   end
   emit(c, "  </g>")
end

--- The outline of `cells`: every edge they don't share with each other.
local function silhouette(c: Canvas, cells: {integer}, attrs: string)
   local B = c.board
   local inside: {integer: boolean} = {}
   for _, i in ipairs(cells) do inside[i] = true end
   emit(c, ('  <g %s fill="none" stroke-linecap="round">'):format(attrs))
   for _, i in ipairs(cells) do
      for _, d in ipairs(B.near[board.facing(i)]) do
         if not inside[i + d] then
            local pts: {XY} = {}
            for _, v in ipairs(board.vertices(B.a[i], B.b[i])) do
               for _, u in ipairs(board.vertices(B.a[i + d], B.b[i + d])) do
                  if u.a == v.a and u.b == v.b then pts[#pts + 1] = board.point(v.a, v.b, c.side) end
               end
            end
            seg(c, { x1 = pts[1].x, y1 = pts[1].y, x2 = pts[2].x, y2 = pts[2].y })
         end
      end
   end
   emit(c, "  </g>")
end

local function indices(cells: {Tri}): {integer}
   local out: {integer} = {}
   for k, t in ipairs(cells) do out[k] = t.i end
   return out
end

--- A chunk's triangles and its outline in its owner's colour.
local function draw_chunk(c: Canvas, cells: {Tri}, owner: string, opacity: number)
   emit(c, ('  <g stroke="%s" stroke-width="0.9" opacity="%s">'):format(PAPER, f(opacity)))
   for _, t in ipairs(cells) do poly(c, t.i, ('fill="%s"'):format(bc.FILL[t.color])) end
   emit(c, "  </g>")
   silhouette(c, indices(cells), ('stroke="%s" stroke-width="2.6" opacity="%s"'):format(owner, f(opacity)))
end

local function look_color(look: sim.Look): string
   return look == "clear" and INK or look == "home" and AMBER or DANGER
end

--- A ghost: a wash and an outline in its look's colour.
local function draw_ghost(c: Canvas, cells: {integer}, look: sim.Look)
   local hex = look_color(look)
   emit(c, ('  <g fill="%s" fill-opacity="0.18" stroke="none">'):format(hex))
   for _, i in ipairs(cells) do poly(c, i, "") end
   emit(c, "  </g>")
   silhouette(c, cells, ('stroke="%s" stroke-width="2.6" stroke-dasharray="5 3"'):format(hex))
end

--- An arrow from just ahead of `cells` along `heading`.
local function draw_arrow(c: Canvas, cells: {Tri}, heading: integer, hex: string)
   local B = c.board
   local st = board.STEPS[heading]
   local o, q = bc.centroid(0, 0, 1), bc.centroid(st.a, st.b, 1)
   local dx, dy = q.x - o.x, q.y - o.y
   local cx, cy = 0.0, 0.0
   for _, t in ipairs(cells) do
      local p = board.centroid(B.a[t.i], B.b[t.i], c.side)
      cx, cy = cx + p.x, cy + p.y
   end
   cx, cy = cx / #cells, cy / #cells
   local lead = 0.0
   for _, t in ipairs(cells) do
      local p = board.centroid(B.a[t.i], B.b[t.i], c.side)
      lead = math.max(lead, (p.x - cx) * dx + (p.y - cy) * dy)
   end
   lead = lead + c.side * 0.8
   local s = c.side
   local tail: XY = { x = cx + dx * lead, y = cy + dy * lead }
   local head: XY = { x = cx + dx * (lead + 2.4 * s), y = cy + dy * (lead + 2.4 * s) }
   local base: XY = { x = head.x - dx * 0.7 * s, y = head.y - dy * 0.7 * s }
   emit(c, ('  <g stroke="%s" fill="%s">'):format(hex, hex))
   emit(c, ('    <line x1="%s" y1="%s" x2="%s" y2="%s" stroke-width="3.4" stroke-linecap="round"/>')
      :format(f(tail.x + c.ox), f(tail.y + c.oy), f(head.x + c.ox), f(head.y + c.oy)))
   emit(c, ('    <polygon points="%s,%s %s,%s %s,%s" stroke="none"/>'):format(
      f(head.x + c.ox), f(head.y + c.oy),
      f(base.x - dy * 0.34 * s + c.ox), f(base.y + dx * 0.34 * s + c.oy),
      f(base.x + dy * 0.34 * s + c.ox), f(base.y - dx * 0.34 * s + c.oy)))
   emit(c, "  </g>")
end

--- The first aim for player p, over their bank's chunks and rotations and
--- every spot, whose ghost has look `want` on heading `h` (any of theirs if
--- nil) and passes `accept`, if given. Deterministic.
local function find_aim(state: sim.State, p: integer, want: sim.Look, h: integer,
                        accept?: function(sim.Shot, sim.Ghost): boolean): sim.Shot
   local B = state.board
   for slot = 1, #state.players[p].bank do
      for turn = 0, 5 do
         local shape = board.shape(B, bc.rotate(state.players[p].bank[slot], turn))
         for _, spot in ipairs(sim.placements(state, p, shape)) do
            local cells = board.place(B, shape, spot.x, spot.y)
            for _, heading in ipairs(board.HEADINGS[p]) do
               if not h or heading == h then
                  local g = sim.ghost(state, p, cells, heading)
                  local shot: sim.Shot = { player = p, slot = slot, heading = heading, cells = cells }
                  if g.look == want and (not accept or accept(shot, g)) then return shot end
               end
            end
         end
      end
   end
   error(("no %s aim for player %d"):format(want, p))
end

--- How many steps a ghost travels from its aim.
local function travel(B: Board, shot: sim.Shot, g: sim.Ghost): integer
   return (g.cells[1] - shot.cells[1].i) // B.step[shot.heading]
end

--- A short note beside a ghost.
local function note(c: Canvas, cells: {integer}, body: string, hex: string, dx: number, dy: number)
   local B = c.board
   local x, y = 0.0, 0.0
   for _, i in ipairs(cells) do
      local q = board.centroid(B.a[i], B.b[i], c.side)
      x, y = x + q.x, y + q.y
   end
   text(c, { x = x / #cells + dx, y = y / #cells + dy }, body,
      ('fill="%s" font-size="13" font-weight="600" text-anchor="middle" stroke="%s" stroke-width="4" paint-order="stroke"'):format(hex, PAPER))
end

local function render_board(B: Board, side: number, labels: boolean): string
   local c = canvas(B, side)
   draw_board(c)
   if labels then draw_labels(c) else draw_names(c) end
   title(c, ("The board: notched hexagon, diameter %d, notch %d"):format(2 * B.n, B.r),
      "each home is a V outside the dashed middle &#183; its black outline is its back wall")
   emit(c, "</svg>")
   return table.concat(c.parts, "\n") .. "\n"
end

local function render_shots(B: Board, side: number, size: integer, seed: integer, labels: boolean): string
   local state = sim.new(B, size, bc.seeded_random(seed))
   local straight1 = board.HEADINGS[1][2]

   -- Player 1 straight across, then a pile at rest in the middle just ahead,
   -- far enough out that it lies wholly in the middle but close enough that the
   -- shot stops with part still in Player 1's home.
   local mine = find_aim(state, 1, "clear", straight1)
   local pile: {Tri} = nil
   for k = 1, 2 * B.s do
      local ahead, stop = true, false
      local moved: {Tri} = {}
      for n, t in ipairs(mine.cells) do
         local i = t.i + (k + 1) * B.step[straight1]
         moved[n] = { i = i, color = bc.COLORS[(n % 3) + 1] }
         if B.kind[i] ~= board.MIDDLE then ahead = false end
         if B.kind[t.i + k * B.step[straight1]] == 1 then stop = true end
      end
      if ahead and stop then pile = moved break end
   end
   if not pile then error("no spot for the pile") end
   sim.add_chunk(state, 3, board.HEADINGS[3][2], pile).flying = false
   local in_pile: {integer: boolean} = {}
   for _, t in ipairs(pile) do in_pile[t.i] = true end

   -- Player 3 straight across, landing clear against a dashed line rather
   -- than the pile.
   local clear = find_aim(state, 3, "clear", board.HEADINGS[3][2], function(shot: sim.Shot, g: sim.Ghost): boolean
      for _, i in ipairs(g.cells) do
         local j = i + B.step[shot.heading]
         if in_pile[j] or in_pile[i + B.pass[shot.heading][board.facing(i)]] then return false end
      end
      return travel(B, shot, g) > 0
   end)
   -- Player 2 on a heading that runs along their own arm into their own back
   -- wall, far enough from it that the ghost stands apart from the aim.
   local friendly = find_aim(state, 2, "friendly", nil, function(shot: sim.Shot, g: sim.Ghost): boolean
      for _, i in ipairs(g.cells) do
         if B.kind[i] ~= 2 then return false end
      end
      return travel(B, shot, g) >= 6
   end)

   local c = canvas(B, side)
   draw_board(c)
   draw_chunk(c, pile, board.PLAYERS[3].color, 1)
   for _, shot in ipairs({ clear, friendly, mine }) do
      local g = sim.ghost(state, shot.player, shot.cells, shot.heading)
      local owner = board.PLAYERS[shot.player].color
      draw_ghost(c, g.cells, g.look)
      draw_chunk(c, shot.cells, owner, g.look == "friendly" and 0.35 or 1)
      draw_arrow(c, shot.cells, shot.heading, g.look == "clear" and owner or look_color(g.look))
      if g.look == "clear" then
         note(c, g.cells, "lands clear", INK, 0, -2.2 * side)
      elseif g.look == "home" then
         note(c, g.cells, "stopped in its own home", AMBER, -5.5 * side, 0.4 * side)
      else
         note(c, g.cells, "friendly fire", DANGER, 0, 2.6 * side)
      end
   end
   note(c, indices(pile), "a pile at rest", MUTED, 4.2 * side, 0.4 * side)
   if labels then draw_labels(c) end
   title(c, "Aims and their ghosts",
      "ink: lands clear &#183; amber: lands in your own home &#183; red: friendly fire")
   emit(c, "</svg>")
   return table.concat(c.parts, "\n") .. "\n"
end

local function write(path: string, body: string)
   local fh, err = io.open(path, "w")
   if not fh then error(err) end
   fh:write(body)
   fh:close()
   print(("wrote %s (%d bytes)"):format(path, #body))
end

local function main(argv: {string})
   local function opt(name: string, fallback: string): string
      for i, a in ipairs(argv) do
         if a == "--" .. name then return argv[i + 1] or fallback end
      end
      return fallback
   end
   local n, r = board.options(argv)
   local side = tonumber(opt("side", "20")) or error("--side needs a number")
   local size = math.floor(tonumber(opt("size", "14")) or error("--size needs a number"))
   local seed = math.floor(tonumber(opt("seed", "7")) or error("--seed needs a number"))
   local dir = opt("out", "images")
   local labels = false
   for _, a in ipairs(argv) do
      if a == "--cells" then labels = true end
   end
   local B = board.new(n, r)
   os.execute(("mkdir -p '%s'"):format(dir))
   write(dir .. "/board.svg", render_board(B, side, labels))
   write(dir .. "/shots.svg", render_shots(B, side, size, seed, labels))
end

main(_G.arg as {string} or {})
```

- [ ] **Step 5: Render, and compare with the figures the README already uses**

Run:

```bash
rm -rf /tmp/blunky-figs && tl run render.tl -- --out /tmp/blunky-figs
cmp /tmp/blunky-figs/board.svg images/board.svg && cmp /tmp/blunky-figs/shots.svg images/shots.svg && echo identical
```

Expected: `wrote /tmp/blunky-figs/board.svg (360146 bytes)`, `wrote /tmp/blunky-figs/shots.svg (375173 bytes)`, then `identical`. The README already ships these exact figures. Then run `tl run render.tl` (no `--out`) so `images/` is written by the code itself.

Open `images/shots.svg` and check it shows:
- Player 3's westward shot with an ink ghost marked "lands clear";
- Player 1's shot with an amber ghost behind a pile, marked "stopped in its own home";
- Player 2's greyed-out shot in its top arm with a red ghost at that arm's notch edge, marked "friendly fire".

- [ ] **Step 6: Drop the old turn figures**

```bash
git rm images/turn-a.svg images/turn-b.svg
grep -n "turn-a\|turn-b" README.md
```

Expected: `grep` prints nothing.

Run: `tl check render.tl layouts.tl`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add layouts.tl render.tl images/board.svg images/shots.svg
git commit -m "README figures for the notched board; layouts.tl draws board.tl's shapes"
```

---

### Task 5: The game in LÖVE

**Files:**
- Replace: `src/draw.tl`
- Replace: `src/main.tl`
- Modify: `src/conf.tl`
- Replace: `Makefile`

**Interfaces:**
- Consumes: everything above. `main.tl` reads `board.options(args)` in `love.load` and also accepts `--size`, `--seed`, `--fast`, `--bots`, `--shot` and `--after`.
- Produces:
  - Records: `draw.View { board, side, cx, cy }`, `draw.Aim { slot, heading, look }`, `draw.Effect`, `draw.KeyGroup`.
  - Layout and board: `draw.layout(B, x, y, w, h): View`; `draw.board(v)`.
  - Chunks and aims:
    - `draw.chunk(v, cells, ox, oy, alpha, owner)`;
    - `draw.ghost(v, cells, look)`, `draw.look_color(look)`;
    - `draw.grey(v, cells)`, `draw.misfit(v, cells)`;
    - `draw.step_offset(v, heading)`, `draw.arrow(v, cells, heading, hex, alpha)`.
  - The rest of the screen:
    - `draw.thumb(cells, x, y, side, alpha)`;
    - `draw.panels(state, aims, x, y, w, small, big, human?)`;
    - `draw.controls`, `draw.effects`.
  - Make targets: `make run|bots|soak|images DIAMETER=… NOTCH=… ARGS="…"`.

- [ ] **Step 1: Write the drawing**

Replace `src/draw.tl` with:

```lua
--- Rendering for the LOVE build: the board in its walls, chunks (live and
--- aimed), ghosts, headings and the players' panels. Pure output -- nothing
--- here changes the simulation. All the sqrt(3) lives in board.tl's drawing
--- helpers.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")

local record draw
   --- Where and how big the board is on screen.
   record View
      board: board.Board
      side: number
      cx: number
      cy: number
   end

   --- A floating bit of text, e.g. "x" where triangles cleared.
   record Effect
      x: number
      y: number
      text: string
      r: number
      g: number
      b: number
      ttl: number
      life: number
   end

   --- A titled row of { key, what it does } pairs for the on-screen legend.
   record KeyGroup
      title: string
      keys: {{string, string}}
   end

   --- What a player is aiming this shot clock, for the panels.
   record Aim
      slot: integer
      heading: integer
      look: sim.Look -- nil when the chunk fits nowhere
   end

   INK: string
   MUTED: string
   AMBER: string
   DANGER: string
end

local type XY = bc.XY
local type View = draw.View
local type Tri = board.Tri

local PAPER <const> = { 0.97, 0.97, 0.96 }
local GRID <const> = "#c5ccd3"
local INK <const> = "#1f2933"
local MUTED <const> = "#7b8794"
local DASH <const> = "#52606d"
local AMBER <const> = "#d99a00"
local DANGER <const> = "#c0392b"
local STONE <const> = { "#b9ad9b", "#a99d8b", "#c4b9a8", "#9f9381", "#b2a593" }

--- "#rrggbb" -> r, g, b in 0..1.
function draw.rgb(hex: string): number, number, number
   local r = tonumber(hex:sub(2, 3), 16)
   local g = tonumber(hex:sub(4, 5), 16)
   local b = tonumber(hex:sub(6, 7), 16)
   return r / 255, g / 255, b / 255
end

local function color(hex: string, alpha?: number)
   local r, g, b = draw.rgb(hex)
   love.graphics.setColor(r, g, b, alpha or 1)
end

function draw.background()
   love.graphics.setBackgroundColor(PAPER[1], PAPER[2], PAPER[3])
end

--- Per board and side: every cell's corners on screen, and the board's lines.
local record Cache
   corners: {{number}}
   geometry: board.Geometry
end

local caches: {board.Board: {number: Cache}} = {}

local function cache(v: View): Cache
   local by_side = caches[v.board]
   if not by_side then
      by_side = {}
      caches[v.board] = by_side
   end
   local c = by_side[v.side]
   if not c then
      local B = v.board
      c = { corners = {}, geometry = board.geometry(B, v.side) }
      for i = 1, B.size do
         local pts = board.corners(B.a[i], B.b[i], v.side)
         c.corners[i] = { pts[1].x, pts[1].y, pts[2].x, pts[2].y, pts[3].x, pts[3].y }
      end
      by_side[v.side] = c
   end
   return c
end

--- Board space -> screen.
local function at(v: View, p: XY): number, number
   return v.cx + p.x, v.cy + p.y
end

local function tri_fill(v: View, i: integer, ox: number, oy: number)
   local p = cache(v).corners[i]
   local x, y = v.cx + ox, v.cy + oy
   love.graphics.polygon("fill", p[1] + x, p[2] + y, p[3] + x, p[4] + y, p[5] + x, p[6] + y)
end

local function segment(v: View, s: board.Seg, ox: number, oy: number)
   love.graphics.line(v.cx + s.x1 + ox, v.cy + s.y1 + oy, v.cx + s.x2 + ox, v.cy + s.y2 + oy)
end

--- The biggest view of board `B` that fits the rectangle, centred in it.
function draw.layout(B: board.Board, x: number, y: number, w: number, h: number): View
   local xmin, xmax, ymin, ymax = math.huge, -math.huge, math.huge, -math.huge
   local g = board.geometry(B, 1)
   local cells: {integer} = {}
   for _, i in ipairs(B.cells) do cells[#cells + 1] = i end
   for _, i in ipairs(g.walls) do cells[#cells + 1] = i end
   for _, i in ipairs(cells) do
      for _, p in ipairs(board.corners(B.a[i], B.b[i], 1)) do
         xmin, xmax = math.min(xmin, p.x), math.max(xmax, p.x)
         ymin, ymax = math.min(ymin, p.y), math.max(ymax, p.y)
      end
   end
   local side = math.floor(math.min(w / (xmax - xmin), h / (ymax - ymin)) * 4) / 4
   return {
      board = B,
      side = side,
      cx = x + w / 2 - (xmin + xmax) / 2 * side,
      cy = y + h / 2 - (ymin + ymax) / 2 * side,
   }
end

local function dashed(x1: number, y1: number, x2: number, y2: number, dash: number, gap: number)
   local dx, dy = x2 - x1, y2 - y1
   local len = math.sqrt(dx * dx + dy * dy)
   local ux, uy = dx / len, dy / len
   local t = 0.0
   while t < len do
      local e = math.min(t + dash, len)
      love.graphics.line(x1 + ux * t, y1 + uy * t, x1 + ux * e, y1 + uy * e)
      t = e + gap
   end
end

--- The board: stone walls, each home tinted in its player's colour, the grid,
--- the dashed lines round the middle and the back walls in ink.
function draw.board(v: View)
   local B = v.board
   local c = cache(v)
   for _, i in ipairs(c.geometry.walls) do
      local h = (B.a[i] * B.a[i] * 7 + B.b[i] * B.b[i] * 13 + B.a[i] * B.b[i] * 5 + B.a[i] * 3 + B.b[i]) % #STONE
      color(STONE[h + 1])
      tri_fill(v, i, 0, 0)
   end
   for _, i in ipairs(B.cells) do
      local k = B.kind[i]
      if k > 0 then
         local r, g, b = draw.rgb(board.PLAYERS[k].color)
         love.graphics.setColor(PAPER[1] + (r - PAPER[1]) * 0.12, PAPER[2] + (g - PAPER[2]) * 0.12,
            PAPER[3] + (b - PAPER[3]) * 0.12)
      else
         love.graphics.setColor(1, 1, 1)
      end
      tri_fill(v, i, 0, 0)
   end
   color(GRID)
   love.graphics.setLineWidth(1)
   for _, s in ipairs(c.geometry.grid) do segment(v, s, 0, 0) end
   color(DASH)
   love.graphics.setLineWidth(2)
   for j = 0, 5 do
      local s = board.wall(B.n, v.side, j)
      local x1, y1 = at(v, { x = s.x1, y = s.y1 })
      local x2, y2 = at(v, { x = s.x2, y = s.y2 })
      dashed(x1, y1, x2, y2, v.side * 0.45, v.side * 0.35)
   end
   color(INK)
   love.graphics.setLineWidth(3.5)
   for _, s in ipairs(c.geometry.outline) do segment(v, s, 0, 0) end
end

--- The silhouette of `cells`: every edge they don't share with each other.
local function silhouette(v: View, cells: {Tri}, ox: number, oy: number)
   local B = v.board
   local inside: {integer: boolean} = {}
   for _, t in ipairs(cells) do inside[t.i] = true end
   for _, t in ipairs(cells) do
      for _, d in ipairs(B.near[board.facing(t.i)]) do
         if not inside[t.i + d] then
            -- The two corners the cells share, exactly, then drawn.
            local pts: {XY} = {}
            for _, p in ipairs(board.vertices(B.a[t.i], B.b[t.i])) do
               for _, q in ipairs(board.vertices(B.a[t.i + d], B.b[t.i + d])) do
                  if p.a == q.a and p.b == q.b then pts[#pts + 1] = board.point(p.a, p.b, v.side) end
               end
            end
            love.graphics.line(v.cx + pts[1].x + ox, v.cy + pts[1].y + oy, v.cx + pts[2].x + ox, v.cy + pts[2].y + oy)
         end
      end
   end
end

--- A chunk's triangles, shifted by (ox, oy) pixels for animation, at `alpha`,
--- outlined in its owner's colour.
function draw.chunk(v: View, cells: {Tri}, ox: number, oy: number, alpha: number, owner: string)
   for _, t in ipairs(cells) do
      color(bc.FILL[t.color], alpha)
      tri_fill(v, t.i, ox, oy)
   end
   love.graphics.setColor(PAPER[1], PAPER[2], PAPER[3], alpha)
   love.graphics.setLineWidth(1)
   local corners = cache(v).corners
   for _, t in ipairs(cells) do
      local p = corners[t.i]
      local x, y = v.cx + ox, v.cy + oy
      love.graphics.polygon("line", p[1] + x, p[2] + y, p[3] + x, p[4] + y, p[5] + x, p[6] + y)
   end
   color(owner, alpha)
   love.graphics.setLineWidth(2.5)
   silhouette(v, cells, ox, oy)
end

--- The colour that goes with a ghost's look: ink when it lands clear, amber
--- when it lands in your own home, red only for friendly fire.
function draw.look_color(look: sim.Look): string
   return look == "clear" and INK or look == "home" and AMBER or DANGER
end

--- Where a ghost lands: a light wash and an outline, coloured by its look.
function draw.ghost(v: View, cells: {integer}, look: sim.Look)
   local hex = draw.look_color(look)
   local tris: {Tri} = {}
   for k, i in ipairs(cells) do tris[k] = { i = i, color = "red" } end
   color(hex, 0.22)
   for _, t in ipairs(tris) do tri_fill(v, t.i, 0, 0) end
   color(hex, 0.95)
   love.graphics.setLineWidth(2.5)
   silhouette(v, tris, 0, 0)
end

--- Grey `cells` out, for an aim that would be friendly fire.
function draw.grey(v: View, cells: {Tri})
   love.graphics.setColor(PAPER[1], PAPER[2], PAPER[3], 0.7)
   for _, t in ipairs(cells) do tri_fill(v, t.i, 0, 0) end
end

--- A red outline round an aim that fits nowhere.
function draw.misfit(v: View, cells: {Tri})
   color(DANGER, 0.9)
   love.graphics.setLineWidth(3)
   silhouette(v, cells, 0, 0)
end

--- The pixel offset of one step on `heading`.
function draw.step_offset(v: View, heading: integer): number, number
   local st = board.STEPS[heading]
   local o = bc.centroid(0, 0, v.side)
   local p = bc.centroid(st.a, st.b, v.side)
   return p.x - o.x, p.y - o.y
end

--- A short arrow just ahead of `cells` along `heading`.
function draw.arrow(v: View, cells: {Tri}, heading: integer, owner: string, alpha: number)
   local B = v.board
   local sx, sy = draw.step_offset(v, heading)
   local len = math.sqrt(sx * sx + sy * sy)
   local dx, dy = sx / len, sy / len
   local cx, cy = 0.0, 0.0
   for _, t in ipairs(cells) do
      local p = board.centroid(B.a[t.i], B.b[t.i], v.side)
      cx, cy = cx + p.x, cy + p.y
   end
   cx, cy = cx / #cells, cy / #cells
   local lead = 0.0
   for _, t in ipairs(cells) do
      local p = board.centroid(B.a[t.i], B.b[t.i], v.side)
      lead = math.max(lead, (p.x - cx) * dx + (p.y - cy) * dy)
   end
   lead = lead + v.side * 0.8
   local tx, ty = cx + dx * lead, cy + dy * lead
   local hx, hy = cx + dx * (lead + v.side * 2), cy + dy * (lead + v.side * 2)
   local px, py = -dy, dx
   local bx, by = hx - dx * v.side * 0.7, hy - dy * v.side * 0.7
   color(owner, alpha)
   love.graphics.setLineWidth(3)
   love.graphics.line(v.cx + tx, v.cy + ty, v.cx + hx, v.cy + hy)
   love.graphics.polygon("fill", v.cx + hx, v.cy + hy,
      v.cx + bx + px * v.side * 0.35, v.cy + by + py * v.side * 0.35,
      v.cx + bx - px * v.side * 0.35, v.cy + by - py * v.side * 0.35)
end

--- A bank chunk (Eisenstein cells) drawn small, centred at (x, y).
function draw.thumb(cells: {bc.Cell}, x: number, y: number, side: number, alpha: number)
   local cx, cy = 0.0, 0.0
   for _, c in ipairs(cells) do
      local p = bc.centroid(c.a, c.b, side)
      cx, cy = cx + p.x, cy + p.y
   end
   cx, cy = cx / #cells, cy / #cells
   for _, c in ipairs(cells) do
      local pts = bc.cell_corners(c.a, c.b, side)
      color(bc.FILL[c.color], alpha)
      love.graphics.polygon("fill", x - cx + pts[1].x, y - cy + pts[1].y, x - cx + pts[2].x, y - cy + pts[2].y,
         x - cx + pts[3].x, y - cy + pts[3].y)
      love.graphics.setColor(1, 1, 1, alpha)
      love.graphics.setLineWidth(1)
      love.graphics.polygon("line", x - cx + pts[1].x, y - cy + pts[1].y, x - cx + pts[2].x, y - cy + pts[2].y,
         x - cx + pts[3].x, y - cy + pts[3].y)
   end
end

local LOOK_NOTE <const>: {sim.Look: string} = {
   clear = "lands clear",
   home = "lands in your own home",
   friendly = "FRIENDLY FIRE",
}

local OUT_NOTE <const>: {sim.Out: string} = {
   stuck = "out: no legal shot",
   friendly = "out: friendly fire",
}

--- Player panels down the right-hand side: name, status, bank and aim.
--- `aims` holds what each player is aiming (bots and human alike); `human`,
--- if set, is the player at the keyboard.
function draw.panels(state: sim.State, aims: {integer: draw.Aim}, x: number, y: number, w: number,
                     small: love.Font, big: love.Font, human?: integer)
   local h = 228
   for p, pl in ipairs(board.PLAYERS) do
      local top = y + (p - 1) * (h + 14)
      local me = state.players[p]
      color(pl.color, me.alive and 0.10 or 0.04)
      love.graphics.rectangle("fill", x, top, w, h, 8, 8)
      color(pl.color, me.alive and 1 or 0.4)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", x, top, w, h, 8, 8)

      love.graphics.setFont(big)
      color(pl.color)
      local home = ({ "southwest", "northwest", "east" })[p]
      love.graphics.print(("%s%s"):format(pl.name, p == human and " (you)" or ""), x + 14, top + 10)
      love.graphics.setFont(small)
      color(MUTED)
      love.graphics.print(home, x + 14, top + 38)
      local status = me.alive and "in" or OUT_NOTE[me.out]
      color(me.alive and INK or DANGER)
      love.graphics.print(status, x + w - 14 - small:getWidth(status), top + 16)

      local aim = aims[p]
      local slot_w = (w - 28) / 3
      for i = 1, #me.bank do
         local bx, by = x + 14 + (i - 1) * slot_w, top + 62
         if me.alive and aim and aim.slot == i then
            color(pl.color, 0.28)
         else
            love.graphics.setColor(1, 1, 1, 0.6)
         end
         love.graphics.rectangle("fill", bx + 2, by, slot_w - 4, 104, 6, 6)
         draw.thumb(me.bank[i], bx + slot_w / 2, by + 52, 9, me.alive and 1 or 0.35)
         if p == human then
            color(aim and aim.slot == i and pl.color or MUTED)
            love.graphics.print(tostring(i), bx + 8, by + 4)
         end
      end

      if me.alive then
         local note: string
         local hue = MUTED
         if not aim then
            note = "nothing fits"
            hue = DANGER
         elseif not aim.look then
            note = p == human and "this chunk doesn't fit like this: rotate or pick another" or "re-aiming"
            hue = p == human and DANGER or MUTED
         else
            note = ("aiming %s, %s"):format(board.HEADING_NAMES[aim.heading], LOOK_NOTE[aim.look])
            hue = aim.look == "clear" and INK or aim.look == "home" and AMBER or DANGER
         end
         color(hue)
         love.graphics.printf(note, x + 14, top + 176, w - 28, "left")
      end
   end
end

--- The key legend: each group starts a new line with its title, then key
--- chips with their descriptions, wrapping within `w`.
function draw.controls(groups: {draw.KeyGroup}, x: number, y: number, w: number, font: love.Font)
   love.graphics.setFont(font)
   local line_h = font:getHeight() + 10
   local cy = y
   for _, group in ipairs(groups) do
      color(INK)
      love.graphics.print(group.title, x, cy + 3)
      local indent = x + 110
      local cx = indent
      for _, k in ipairs(group.keys) do
         local kw = font:getWidth(k[1]) + 12
         local item = kw + 6 + font:getWidth(k[2]) + 18
         if cx > indent and cx + item > x + w then
            cx, cy = indent, cy + line_h
         end
         color("#ffffff")
         love.graphics.rectangle("fill", cx, cy, kw, font:getHeight() + 6, 4, 4)
         color(GRID)
         love.graphics.setLineWidth(1)
         love.graphics.rectangle("line", cx, cy, kw, font:getHeight() + 6, 4, 4)
         color(INK)
         love.graphics.print(k[1], cx + 6, cy + 3)
         color(MUTED)
         love.graphics.print(k[2], cx + kw + 6, cy + 3)
         cx = cx + item
      end
      cy = cy + line_h
   end
end

--- Floating text effects.
function draw.effects(list: {draw.Effect}, font: love.Font)
   love.graphics.setFont(font)
   for _, e in ipairs(list) do
      local a = math.max(0, e.life / e.ttl)
      love.graphics.setColor(e.r, e.g, e.b, a)
      love.graphics.print(e.text, e.x, e.y - (1 - a) * 18)
   end
end

draw.INK = INK
draw.MUTED = MUTED
draw.AMBER = AMBER
draw.DANGER = DANGER

return draw
```

- [ ] **Step 2: Write the game loop**

Replace `src/main.tl` with:

```lua
--- Blunkychunks in LOVE: you play Player 1 (the southwest home) against two
--- random bots, or with --bots three bots play each other.
---
---   make run                          # build and launch on the 22-8 board
---   make run DIAMETER=12 NOTCH=5      # any other notched board
---   make bots                         # an all-bot match
---   make run ARGS="--seed 42"         # a reproducible match
---   make run ARGS="--fast"            # a 2 second shot clock
---   make run ARGS="--size 8"          # chunks of 8 triangles
---   make run ARGS="--shot out.png"    # screenshot after a few seconds, then quit
---
--- Play is continuous: chunks slide one step per tick while the shot clock
--- counts down, and each time it runs out every player's aim fires at once.
--- Keys are listed on screen (see `controls`).

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local bots = require("bots")
local draw = require("draw")

local record Fonts
   small: love.Font
   body: love.Font
   big: love.Font
   title: love.Font
end

--- The human's aim. `want` is the spot they last chose, as the Eisenstein sum
--- of its triangles' coordinates over `count` triangles, so the aim stays put
--- (as near as it can) while chunks move and while they rotate.
local record Aim
   slot: integer
   turn: integer -- rotation, 0..5 sixths of a turn counterclockwise
   heading: integer -- which of the player's three headings, 1..3
   want: bc.AB
   count: integer
   spots: {board.Spot} -- legal spots for this chunk and rotation, along the back wall
   pick: integer -- the spot in use, or nil when the chunk fits nowhere
   shape: board.Shape
   cells: {board.Tri} -- the aim's triangles (or where it would be, if it fits nowhere)
   ghost: sim.Ghost
end

local record Game
   state: sim.State
   over: boolean
   clock: number -- seconds left on the shot clock
   tick_timer: number
   step_seconds: number
   seed: integer
   effects: {draw.Effect}
   bot_shots: {sim.Shot}
   shot_path: string
   shot_after: number
   human: boolean
   aim: Aim
end

local SHOT_SECONDS <const> = 8.0
local STEP_SECONDS <const> = 0.28
local HUMAN <const> = 1

local view: draw.View
local fonts: Fonts
local game: Game
local shot_seconds = SHOT_SECONDS
local human_mode = true
local board_n, board_r = 11, 8
local chunk_size = 14

local function skip(g: Game): {integer: boolean}
   return g.human and { [HUMAN] = true } or nil
end

--- Sums of the Eisenstein coordinates of `cells`.
local function centre(B: board.Board, cells: {board.Tri}): bc.AB
   local a, b = 0, 0
   for _, t in ipairs(cells) do a, b = a + B.a[t.i], b + B.b[t.i] end
   return { a = a, b = b }
end

--- Squared distance (times count^2) between two centroids given as sums, by
--- the Eisenstein norm N(x + yw) = x^2 - xy + y^2. Exact.
local function far(u: bc.AB, nu: integer, v: bc.AB, nv: integer): integer
   local x, y = u.a * nv - v.a * nu, u.b * nv - v.b * nu
   return x * x - x * y + y * y
end

--- Put `spots` in order along the back wall, counterclockwise as drawn round
--- the board's centre z = 1. Every home lies within a 120 degree sector of
--- it, so the sign of the cross product orders them. Exact.
local function along_wall(B: board.Board, shape: board.Shape, spots: {board.Spot}): {board.Spot}
   local k = #shape.cells
   local key: {board.Spot: bc.AB} = {}
   for _, s in ipairs(spots) do
      local c = centre(B, board.place(B, shape, s.x, s.y))
      key[s] = { a = c.a - k, b = c.b }
   end
   table.sort(spots, function(p: board.Spot, q: board.Spot): boolean
      local u, v = key[p], key[q]
      local cross = u.a * v.b - u.b * v.a
      if cross ~= 0 then return cross > 0 end
      if p.y ~= q.y then return p.y < q.y end
      return p.x < q.x
   end)
   return spots
end

--- Recompute the human's aim against the board as it is now.
local function refresh_aim(g: Game)
   local aim = g.aim
   if not aim or not g.state.players[HUMAN].alive then return end
   local B = g.state.board
   local chunk = g.state.players[HUMAN].bank[aim.slot]
   aim.shape = board.shape(B, bc.rotate(chunk, aim.turn))
   aim.spots = along_wall(B, aim.shape, sim.placements(g.state, HUMAN, aim.shape))
   aim.pick = nil
   local best = math.huge
   for i, s in ipairs(aim.spots) do
      local d = aim.want and far(centre(B, board.place(B, aim.shape, s.x, s.y)), #aim.shape.cells, aim.want, aim.count)
         or math.abs(i - (#aim.spots + 1) / 2)
      if d < best then best, aim.pick = d, i end
   end
   local h = board.HEADINGS[HUMAN][aim.heading]
   if aim.pick then
      local s = aim.spots[aim.pick]
      aim.cells = board.place(B, aim.shape, s.x, s.y)
      aim.ghost = sim.ghost(g.state, HUMAN, aim.cells, h)
      if not aim.want then aim.want, aim.count = centre(B, aim.cells), #aim.cells end
   else
      aim.ghost = nil
   end
end

--- Choose spot `i` of the current list as the one to hold on to.
local function choose_spot(g: Game, i: integer)
   local aim = g.aim
   local s = aim.spots[i]
   if not s then return end
   local cells = board.place(g.state.board, aim.shape, s.x, s.y)
   aim.want, aim.count = centre(g.state.board, cells), #cells
   refresh_aim(g)
end

--- The human's shot as aimed, or nil when it fits nowhere.
local function human_shot(g: Game): sim.Shot
   local aim = g.aim
   if not g.human or not aim or not aim.pick then return nil end
   return { player = HUMAN, slot = aim.slot, heading = board.HEADINGS[HUMAN][aim.heading], cells = aim.cells }
end

local function effect(g: Game, i: integer, text: string, hex: string, life: number)
   local B = g.state.board
   local p = board.centroid(B.a[i], B.b[i], view.side)
   local r, gg, b = draw.rgb(hex)
   g.effects[#g.effects + 1] = {
      x = view.cx + p.x - 6, y = view.cy + p.y - 9, text = text,
      r = r, g = gg, b = b, ttl = life, life = life,
   }
end

--- Mark a player who just went out in the middle of their home.
local function out_effect(g: Game, p: integer)
   local home = g.state.board.homes[p]
   effect(g, home[(#home + 1) // 2], "OUT", draw.DANGER, 2.5)
end

local function check_over(g: Game)
   if sim.over(g.state) then g.over = true end
end

local function do_tick(g: Game)
   local r = sim.tick(g.state)
   for _, t in ipairs(r.cleared) do effect(g, t.i, "x", bc.FILL[t.color], 0.7) end
   for _, t in ipairs(r.hits) do effect(g, t.i, "!", draw.DANGER, 1.2) end
   for _, p in ipairs(r.out) do out_effect(g, p) end
   check_over(g)
   if not g.over then refresh_aim(g) end
end

local function lock_in(g: Game)
   local shots = bots.refresh(g.state, g.bot_shots, skip(g))
   local mine = human_shot(g)
   if mine then shots[#shots + 1] = mine end
   local r = sim.lock_in(g.state, shots)
   for _, t in ipairs(r.cleared) do effect(g, t.i, "x", bc.FILL[t.color], 0.7) end
   for _, p in ipairs(r.out) do out_effect(g, p) end
   g.clock = shot_seconds
   check_over(g)
   if g.over then return end
   g.bot_shots = bots.plan(g.state, skip(g))
   if g.aim and g.aim.want and mine then
      -- The chunk just fired; aim the next one from the same place.
      g.aim.want, g.aim.count = centre(g.state.board, mine.cells), #mine.cells
   end
   refresh_aim(g)
end

local function new_game(seed: integer): Game
   local B = board.new(board_n, board_r)
   view = draw.layout(B, 24, 92, 1440 - 24 - 470, 900 - 92 - 112)
   local g: Game = {
      state = sim.new(B, chunk_size, bc.seeded_random(seed)),
      over = false,
      clock = shot_seconds,
      tick_timer = 0,
      step_seconds = STEP_SECONDS,
      seed = seed,
      effects = {},
      bot_shots = {},
      human = human_mode,
   }
   g.bot_shots = bots.plan(g.state, skip(g))
   if g.human then
      g.aim = { slot = 1, turn = 0, heading = 2 }
      refresh_aim(g)
   end
   return g
end

local function flag(args: {string}, name: string): string
   for i, a in ipairs(args) do
      if a == name then return args[i + 1] or "" end
   end
   return nil
end

function love.load(args: {string})
   draw.background()
   fonts = {
      small = love.graphics.newFont(12),
      body = love.graphics.newFont(15),
      big = love.graphics.newFont(20),
      title = love.graphics.newFont(26),
   }
   board_n, board_r = board.options(args)
   chunk_size = math.floor(tonumber(flag(args, "--size") or "") or chunk_size)
   local seed = tonumber(flag(args, "--seed") or "") or os.time()
   if flag(args, "--fast") then shot_seconds = 2.0 end
   if flag(args, "--bots") then human_mode = false end
   game = new_game(math.floor(seed))
   local shot = flag(args, "--shot")
   if shot then
      game.shot_path = shot
      game.shot_after = tonumber(flag(args, "--after") or "") or 3.0
   end
end

function love.update(dt: number)
   local g = game
   for i = #g.effects, 1, -1 do
      g.effects[i].life = g.effects[i].life - dt
      if g.effects[i].life <= 0 then table.remove(g.effects, i) end
   end

   if not g.over then
      g.clock = g.clock - dt
      if g.clock <= 0 then lock_in(g) end
      g.tick_timer = g.tick_timer + dt
      while not g.over and g.tick_timer >= g.step_seconds do
         g.tick_timer = g.tick_timer - g.step_seconds
         do_tick(g)
      end
   end

   if g.shot_path then
      g.shot_after = g.shot_after - dt
      if g.shot_after <= 0 then
         love.graphics.captureScreenshot(g.shot_path)
         g.shot_path = nil
         love.event.quit()
      end
   end
end

--- Every key the game listens to, grouped for the on-screen legend.
local function controls(g: Game): {draw.KeyGroup}
   local groups: {draw.KeyGroup} = {}
   if g.human then
      groups[#groups + 1] = {
         title = "You (" .. board.PLAYERS[HUMAN].name .. ")",
         keys = {
            { "1 2 3", "pick chunk" },
            { "Q / E", "rotate" },
            { "Left Right / A D", "slide along your back wall" },
            { "Up Down / Tab", "heading" },
            { "Space / Enter", "fire now" },
         },
      }
   else
      groups[#groups + 1] = { title = "Bots", keys = { { "Space", "fire now" } } }
   end
   groups[#groups + 1] = {
      title = "Game",
      keys = { { "+ / -", "slide speed" }, { "R", "new match" }, { "Esc", "quit" } },
   }
   return groups
end

function love.draw()
   local g = game
   local s = g.state
   local B = s.board

   draw.board(view)

   -- Chunks, the ones that moved last tick drawn back toward where they were.
   local progress = g.over and 1 or math.min(1, g.tick_timer / g.step_seconds)
   for _, chunk in ipairs(s.chunks) do
      local ox, oy = 0.0, 0.0
      if chunk.moved and progress < 1 then
         local sx, sy = draw.step_offset(view, chunk.heading)
         ox, oy = -sx * (1 - progress), -sy * (1 - progress)
      end
      draw.chunk(view, chunk.cells, ox, oy, 1, board.PLAYERS[chunk.owner].color)
   end

   -- Aims: the bots' faintly, the human's with its heading and ghost.
   local aims: {integer: draw.Aim} = {}
   if not g.over then
      for _, shot in ipairs(g.bot_shots) do
         if s.players[shot.player].alive then
            local hex = board.PLAYERS[shot.player].color
            draw.chunk(view, shot.cells, 0, 0, 0.35, hex)
            draw.arrow(view, shot.cells, shot.heading, hex, 0.5)
            aims[shot.player] = {
               slot = shot.slot, heading = shot.heading,
               look = sim.legal(s, shot.player, shot.cells)
                  and sim.ghost(s, shot.player, shot.cells, shot.heading).look or nil,
            }
         end
      end
      local aim = g.aim
      if g.human and aim and s.players[HUMAN].alive then
         local hex = board.PLAYERS[HUMAN].color
         local h = board.HEADINGS[HUMAN][aim.heading]
         if aim.pick then
            draw.ghost(view, aim.ghost.cells, aim.ghost.look)
            draw.chunk(view, aim.cells, 0, 0, 0.85, hex)
            if aim.ghost.look == "friendly" then draw.grey(view, aim.cells) end
            draw.arrow(view, aim.cells, h, aim.ghost.look == "clear" and hex or draw.look_color(aim.ghost.look), 1)
            aims[HUMAN] = { slot = aim.slot, heading = h, look = aim.ghost.look }
         else
            if aim.cells then draw.misfit(view, aim.cells) end
            aims[HUMAN] = { slot = aim.slot, heading = h }
         end
      end
   end

   draw.effects(g.effects, fonts.big)

   -- Header.
   love.graphics.setFont(fonts.title)
   local rr, gg, bb = draw.rgb(draw.INK)
   love.graphics.setColor(rr, gg, bb)
   local alive = sim.alive(s)
   love.graphics.print(g.over and "Match over" or ("Shot clock %.1f s"):format(math.max(0, g.clock)), 24, 18)
   love.graphics.setFont(fonts.body)
   rr, gg, bb = draw.rgb(draw.MUTED)
   love.graphics.setColor(rr, gg, bb)
   love.graphics.print(("%d chunk%s on the board  -  %d player%s in  -  %d-%d board"):format(
      #s.chunks, #s.chunks == 1 and "" or "s", alive, alive == 1 and "" or "s", 2 * B.n, B.r), 24, 54)

   draw.controls(controls(g), 24, 900 - 96, 940, fonts.small)
   love.graphics.setColor(rr, gg, bb)
   love.graphics.setFont(fonts.small)
   love.graphics.print(("seed %d   step %.2fs"):format(g.seed, g.step_seconds), 1440 - 180, 900 - 24)

   draw.panels(s, aims, 1440 - 446, 92, 422, fonts.small, fonts.big, g.human and HUMAN or nil)

   if g.over then
      love.graphics.setColor(1, 1, 1, 0.75)
      love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
      love.graphics.setFont(fonts.title)
      local winner = sim.winner(s)
      if winner then
         rr, gg, bb = draw.rgb(board.PLAYERS[winner].color)
         love.graphics.setColor(rr, gg, bb)
         love.graphics.printf(board.PLAYERS[winner].name .. " wins", 0, 400, love.graphics.getWidth(), "center")
      else
         rr, gg, bb = draw.rgb(draw.INK)
         love.graphics.setColor(rr, gg, bb)
         love.graphics.printf("Draw", 0, 400, love.graphics.getWidth(), "center")
      end
      rr, gg, bb = draw.rgb(draw.MUTED)
      love.graphics.setColor(rr, gg, bb)
      love.graphics.setFont(fonts.body)
      love.graphics.printf("press R for a new match", 0, 440, love.graphics.getWidth(), "center")
   end
end

--- Aiming keys for the human. Returns true if the key was handled.
local function human_key(g: Game, key: string): boolean
   local aim = g.aim
   if not g.human or g.over or not aim or not g.state.players[HUMAN].alive then return false end
   local slot = tonumber(key) or tonumber(key:match("^kp(%d)$") or "")
   if slot and slot >= 1 and slot <= sim.BANK then
      aim.slot = math.floor(slot)
      refresh_aim(g)
   elseif key == "q" then
      aim.turn = (aim.turn + 1) % 6
      refresh_aim(g)
   elseif key == "e" then
      aim.turn = (aim.turn + 5) % 6
      refresh_aim(g)
   elseif key == "left" or key == "a" then
      if aim.pick then choose_spot(g, math.max(1, aim.pick - 1)) end
   elseif key == "right" or key == "d" then
      if aim.pick then choose_spot(g, math.min(#aim.spots, aim.pick + 1)) end
   elseif key == "up" or key == "tab" then
      aim.heading = aim.heading % 3 + 1
      refresh_aim(g)
   elseif key == "down" then
      aim.heading = (aim.heading + 1) % 3 + 1
      refresh_aim(g)
   elseif key == "return" or key == "kpenter" then
      lock_in(g)
   else
      return false
   end
   return true
end

function love.keypressed(key: string)
   local g = game
   if human_key(g, key) then return end
   if key == "escape" then
      love.event.quit()
   elseif key == "space" and not g.over then
      lock_in(g)
   elseif key == "r" then
      game = new_game(g.seed + 1)
   elseif key == "=" or key == "+" or key == "kp+" then
      g.step_seconds = math.max(0.04, g.step_seconds / 1.5)
   elseif key == "-" or key == "kp-" then
      g.step_seconds = math.min(2, g.step_seconds * 1.5)
   end
end
```

- [ ] **Step 3: Make the window bigger**

In `src/conf.tl`, change `t.window.width = 1280` to `t.window.width = 1440`, and `t.window.height = 800` to `t.window.height = 900`.

- [ ] **Step 4: Wire the board size through the Makefile**

Replace `Makefile` with:

```make
# Blunkychunks build.
#
#   make          compile every .tl into build/ as Lua 5.1
#   make run      compile, then launch the game in LOVE (you are Player 1)
#   make bots     compile, then launch an all-bot match
#   make check    type-check all Teal sources (game, tests and scripts)
#   make test     run the rules-engine tests under the system Lua
#   make soak     play whole bot matches headless, checking invariants
#   make images   redraw the README's figures
#   make clean    remove build/
#
# The board is the notched hexagon; pick its size with DIAMETER (the central
# hexagon's width in triangles, even) and NOTCH, for run, bots, soak and images:
#   make run DIAMETER=12 NOTCH=5
# Anything else goes in ARGS, e.g. make run ARGS="--seed 42 --fast".
# Override LOVE if the binary lives somewhere else:
#   make run LOVE=/path/to/love

TL       ?= tl
LOVE     ?= /Applications/love.app/Contents/MacOS/love
OUT      := build
DIAMETER ?= 22
NOTCH    ?= 8
BOARD    := --diameter $(DIAMETER) --notch $(NOTCH)

SHARED := blunkychunks.tl board.tl
GAME   := $(wildcard src/*.tl)
TESTS  := $(wildcard tests/*.tl)

LUA := $(patsubst %.tl,$(OUT)/%.lua,$(SHARED)) \
       $(patsubst src/%.tl,$(OUT)/%.lua,$(GAME))

.PHONY: all game run bots check test soak images clean

all: game

game: $(LUA)

$(OUT):
	mkdir -p $(OUT)

$(OUT)/%.lua: src/%.tl | $(OUT)
	$(TL) gen --gen-target=5.1 -c -o $@ $<

$(OUT)/%.lua: %.tl | $(OUT)
	$(TL) gen --gen-target=5.1 -c -o $@ $<

run: game
	$(LOVE) $(OUT) $(BOARD) $(ARGS)

bots: game
	$(LOVE) $(OUT) --bots $(BOARD) $(ARGS)

check:
	$(TL) check $(SHARED) $(GAME) $(TESTS) render.tl layouts.tl

test:
	$(TL) run tests/run.tl

soak:
	$(TL) run tests/soak.tl -- $(BOARD) $(ARGS)

images:
	$(TL) run render.tl -- $(BOARD) $(ARGS)

clean:
	rm -rf $(OUT)
```

- [ ] **Step 5: Type-check, test, soak**

Run: `make check`
Expected: only the `tl check …` command line, then no errors.

Run: `make test`
Expected: `46 passed, 0 failed`

Run: `make soak ARGS="--seeds 3"`
Expected: three finished matches, then `ok`.

- [ ] **Step 6: Build**

Run: `rm -rf build && make`
Expected: seven `Wrote: build/….lua` lines (blunkychunks, board, bots, conf, draw, main, sim).

- [ ] **Step 7: Screenshots at three sizes**

LÖVE writes screenshots to `~/Library/Application Support/LOVE/blunkychunks/`. Pipe the output through `cat`: launched from a script with its output thrown away, the window can stall in the background and never reach `--after`.

```bash
make run ARGS="--seed 7 --shot aim.png --after 3" | cat
make run ARGS="--seed 11 --fast --shot late.png --after 26" | cat
make run DIAMETER=12 NOTCH=5 ARGS="--size 6 --seed 3 --fast --shot small.png --after 9" | cat
make bots DIAMETER=34 NOTCH=17 ARGS="--seed 4 --fast --shot big.png --after 9" | cat
```

Expected:

| Screenshot | What it should show |
| --- | --- |
| `aim.png` | stone walls round the board; the three homes tinted; the dashed middle; one aim in each home touching its back wall, with an arrow; your ghost in ink; each panel saying `aiming …, lands clear` |
| `late.png` | about 40 chunks; your idle aim's panel line in amber, `lands in your own home`; red chunks piling up in your home |
| `small.png` | the 12-5 board filling the board area |
| `big.png` | the 34-17 board filling the board area, with the bots playing |

- [ ] **Step 8: Play it by hand (Review Focus 4 and 5)**

Run `make run`, then:
- Press `1`, `2` and `3`, and `Q`/`E`. The aim switches chunk and rotation without jumping across the home.
- Hold `→`. The aim walks along your back wall from the upper left down to the bottom right, and `←` walks it back.
- `Up`/`Tab` cycles through NW, NE and E, and the panel names each one.
- Aim straight up an arm to get a red ghost: the aimed chunk greys out and the panel says `FRIENDLY FIRE`. Fire it with `Space`, and when it reaches the notch edge an `!` and then `OUT` appear and your panel says `out: friendly fire`.
- Press `R`. Fire a chunk, and before it has left your home choose the spot it just left. The aim should hop to the nearest free spot, then return once the chunk has gone.
- `make bots DIAMETER=34 NOTCH=17` stays smooth.

- [ ] **Step 9: Commit**

```bash
git add src/draw.tl src/main.tl src/conf.tl Makefile
git commit -m "Play the notched board in LOVE: continuous clock, rotation, headings and ghosts"
```
