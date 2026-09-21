--- Draws the blunkychunks board to SVG.
---
---   tl run render.tl                          # board.svg, turn-a.svg, turn-b.svg
---
--- `tl run` parses flags itself, so anything meant for this script goes after a
--- `--` separator:
---
---   tl run render.tl -- --n 6 --side 40       # a smaller board
---   tl run render.tl -- --seed 42             # a different pair of turns
---
--- Compiled, there is nothing to separate:
---
---   tl gen --gen-target=5.1 *.tl && lua render.lua --n 6 --side 40
---
--- Turn A sweeps clockwise and turn B counterclockwise; see board.tl for what
--- that means for who may fire from where.

local bc = require("blunkychunks")
local board = require("board")

local type XY = bc.XY
local type Cell = bc.Cell
local type Turn = board.Turn

local SQRT3 <const> = math.sqrt(3)

local GRID <const> = "#9aa5b1"
local WALL <const> = "#1f2933"
local INK <const> = "#1f2933"
local PAPER <const> = "#ffffff"

local LABEL_OFF <const> = 26.0
local PAD_X <const> = 26.0
local PAD_Y <const> = 70.0

local function f(v: number): string
   return ("%.2f"):format(v)
end

--- An SVG document being assembled line by line.
local record Canvas
   parts: {string}
   ox: number
   oy: number
end

local function canvas(width: number, height: number): Canvas
   return {
      parts = {
         ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" width="%d" height="%d">')
            :format(f(width), f(height), math.floor(width + 0.5), math.floor(height + 0.5)),
         ('  <rect width="100%%" height="100%%" fill="%s"/>'):format(PAPER),
      },
      ox = width / 2,
      oy = height / 2,
   }
end

local function emit(c: Canvas, line: string)
   c.parts[#c.parts + 1] = line
end

local function finish(c: Canvas): string
   emit(c, "</svg>")
   return table.concat(c.parts, "\n") .. "\n"
end

--- Board space -> document space.
local function at(c: Canvas, p: XY): XY
   return { x = p.x + c.ox, y = p.y + c.oy }
end

local function line(c: Canvas, p: XY, q: XY, attrs: string)
   local a, b = at(c, p), at(c, q)
   emit(c, ('    <line x1="%s" y1="%s" x2="%s" y2="%s" %s/>')
      :format(f(a.x), f(a.y), f(b.x), f(b.y), attrs))
end

local function polygon(c: Canvas, pts: {XY}, attrs: string)
   local out: {string} = {}
   for i, p in ipairs(pts) do
      local q = at(c, p)
      out[i] = f(q.x) .. "," .. f(q.y)
   end
   emit(c, ('    <polygon points="%s" %s/>'):format(table.concat(out, " "), attrs))
end

local function text(c: Canvas, p: XY, body: string, attrs: string, angle: number)
   local q = at(c, p)
   local rot = angle ~= 0
      and (' transform="rotate(%s %s %s)"'):format(f(angle), f(q.x), f(q.y))
      or ""
   emit(c, ('    <text x="%s" y="%s"%s %s>%s</text>'):format(f(q.x), f(q.y), rot, attrs, body))
end

local function add(p: XY, d: XY, t: number): XY
   return { x = p.x + d.x * t, y = p.y + d.y * t }
end

local function dot(p: XY, q: XY): number
   return p.x * q.x + p.y * q.y
end

--- The grid of triangles, drawn once.
local function draw_grid(c: Canvas, n: integer, side: number)
   emit(c, ('  <g stroke="%s" stroke-width="0.8" stroke-linecap="round" fill="none">'):format(GRID))
   for _, s in ipairs(board.grid_segments(n, side)) do
      line(c, { x = s.x1, y = s.y1 }, { x = s.x2, y = s.y2 }, "")
   end
   emit(c, "  </g>")
end

--- The six walls, with the three defended ones in their player's color, plus a
--- label sitting just outside each of those.
---
--- Given a turn, the neutral wall each player may *also* fire from that turn is
--- drawn dashed in their color, so the two walls open to them read as a pair.
--- Every wall is spoken for on any given turn: three owned, three on loan.
local function draw_walls(c: Canvas, n: integer, side: number, turn: Turn)
   local own: {integer: string} = {}
   local lent: {integer: string} = {}
   for i, p in ipairs(board.PLAYERS) do
      own[p.wall] = p.color
      if turn then
         lent[board.launch_walls(i, turn)[2]] = p.color
      end
   end

   emit(c, '  <g stroke-width="4" stroke-linecap="round" fill="none">')
   for j = 0, 5 do
      local w = board.wall(n, side, j)
      local attrs: string
      if own[j] then
         attrs = ('stroke="%s"'):format(own[j])
      elseif lent[j] then
         attrs = ('stroke="%s" stroke-dasharray="12 9"'):format(lent[j])
      else
         attrs = ('stroke="%s"'):format(WALL)
      end
      line(c, { x = w.x1, y = w.y1 }, { x = w.x2, y = w.y2 }, attrs)
   end
   emit(c, "  </g>")

   emit(c, '  <g font-family="Helvetica, Arial, sans-serif" font-size="17" font-weight="600"'
      .. ' text-anchor="middle" dominant-baseline="middle">')
   for _, p in ipairs(board.PLAYERS) do
      local w = board.wall(n, side, p.wall)
      local mid: XY = { x = (w.x1 + w.x2) / 2, y = (w.y1 + w.y2) / 2 }
      local out = board.wall_normal(p.wall)
      -- Run the label along its wall, flipped when it would read upside down.
      -- Wall j joins corners at 60j and 60(j+1) degrees, so the chord it spans
      -- points at 60j + 120 -- no need for math.atan, which is 5.3+ with two
      -- arguments and so would break under LuaJIT.
      local angle = (60 * p.wall + 120) % 360
      while angle > 90 do angle = angle - 180 end
      text(c, add(mid, out, LABEL_OFF), p.name, ('fill="%s"'):format(p.color), angle)
   end
   emit(c, "  </g>")
end

--- One chunk: its triangles, then its silhouette in the owner's color.
local function draw_chunk(c: Canvas, cells: {Cell}, side: number, owner: string)
   emit(c, '  <g stroke-width="0.9" stroke-linejoin="round">')
   for _, cell in ipairs(cells) do
      polygon(c, board.corners(cell.a, cell.b, side),
         ('fill="%s" stroke="%s"'):format(bc.FILL[cell.color], PAPER))
   end
   emit(c, "  </g>")

   -- The silhouette is every edge the chunk does not share with itself.
   local inside: {string: boolean} = {}
   for _, cell in ipairs(cells) do
      inside[board.key(cell.a, cell.b)] = true
   end
   emit(c, ('  <g stroke="%s" stroke-width="2.6" stroke-linecap="round" fill="none">'):format(owner))
   for _, cell in ipairs(cells) do
      local pts = board.corners(cell.a, cell.b, side)
      for i, nb in ipairs(bc.neighbors(cell.a, cell.b)) do
         if not inside[board.key(nb.a, nb.b)] then
            -- `neighbors` and `cell_corners` both run counterclockwise from the
            -- same start, so neighbour i faces the edge opposite corner i.
            line(c, pts[i % 3 + 1], pts[(i + 1) % 3 + 1], "")
         end
      end
   end
   emit(c, "  </g>")
end

--- The heading: a dashed lane down the rest of the board, and a solid arrow
--- just ahead of the chunk.
local function draw_arrow(c: Canvas, shot: board.Shot, n: integer, side: number, owner: string)
   local centre: XY = { x = 0, y = 0 }
   for _, cell in ipairs(shot.cells) do
      local p = board.centroid(cell.a, cell.b, side)
      centre.x, centre.y = centre.x + p.x, centre.y + p.y
   end
   centre.x, centre.y = centre.x / #shot.cells, centre.y / #shot.cells

   -- Clear the chunk itself before starting the arrow.
   local lead = 0.0
   for _, cell in ipairs(shot.cells) do
      local p = board.centroid(cell.a, cell.b, side)
      local d = dot({ x = p.x - centre.x, y = p.y - centre.y }, shot.dir)
      if d > lead then lead = d end
   end
   lead = lead + side * 0.9

   local runway = board.exit_distance(n, side, centre, shot.dir) - side * 0.35
   if runway <= lead then return end

   local tail = add(centre, shot.dir, lead)
   local head = add(centre, shot.dir, math.min(lead + side * 2.6, runway))
   local far = add(centre, shot.dir, runway)

   emit(c, ('  <g stroke="%s" fill="%s">'):format(owner, owner))
   line(c, head, far, 'stroke-width="1.6" stroke-dasharray="3 7" opacity="0.45"')
   line(c, tail, head, 'stroke-width="3.4" stroke-linecap="round"')
   local perp: XY = { x = -shot.dir.y, y = shot.dir.x }
   local base = add(head, shot.dir, -side * 0.72)
   polygon(c, {
      head,
      add(base, perp, side * 0.34),
      add(base, perp, -side * 0.34),
   }, 'stroke="none"')
   emit(c, "  </g>")
end

local function title(c: Canvas, n: integer, side: number, body: string, note: string)
   local top = -(n * side * SQRT3 / 2)
   text(c, { x = 0, y = top - 44 }, body,
      ('fill="%s" font-family="Helvetica, Arial, sans-serif" font-size="19"'
         .. ' font-weight="600" text-anchor="middle" dominant-baseline="middle"'):format(INK), 0)
   text(c, { x = 0, y = top - 23 }, note,
      ('fill="%s" font-family="Helvetica, Arial, sans-serif" font-size="12"'
         .. ' text-anchor="middle" dominant-baseline="middle"'):format(GRID), 0)
end

--- The empty board.
local function render_board(n: integer, side: number): string
   local r = n * side
   local c = canvas(2 * r + 2 * PAD_X, 2 * (r * SQRT3 / 2) + 2 * PAD_Y)
   draw_grid(c, n, side)
   draw_walls(c, n, side, nil)
   return finish(c)
end

--- The board with one shot per player.
local function render_turn(n: integer, side: number, turn: Turn, size: integer, seed: integer): string
   local r = n * side
   local c = canvas(2 * r + 2 * PAD_X, 2 * (r * SQRT3 / 2) + 2 * PAD_Y)
   local rng = bc.seeded_random(seed)

   draw_grid(c, n, side)
   local shots: {board.Shot} = {}
   for p = 1, #board.PLAYERS do
      shots[p] = board.shoot(n, p, turn, size, rng)
      draw_chunk(c, shots[p].cells, side, board.PLAYERS[p].color)
   end
   draw_walls(c, n, side, turn)
   for p, shot in ipairs(shots) do
      draw_arrow(c, shot, n, side, board.PLAYERS[p].color)
   end

   title(c, n, side,
      turn == "A" and "Turn A &#8212; clockwise" or "Turn B &#8212; counterclockwise",
      "solid wall = your own &#183; dashed = also yours to fire from this turn")
   return finish(c)
end

local function write(path: string, body: string)
   local fh, err = io.open(path, "w")
   if not fh then error(err) end
   fh:write(body)
   fh:close()
   print(("wrote %s (%d bytes)"):format(path, #body))
end

local function main(argv: {string})
   local function flag(name: string, fallback: number): number
      for i, a in ipairs(argv) do
         if a == "--" .. name then
            local v = tonumber(argv[i + 1])
            if not v then error("--" .. name .. " needs a number") end
            return v
         end
      end
      return fallback
   end
   local function opt(name: string, fallback: string): string
      for i, a in ipairs(argv) do
         if a == "--" .. name then return argv[i + 1] or fallback end
      end
      return fallback
   end

   local n = math.floor(flag("n", 11))
   local side = flag("side", 26)
   local size = math.floor(flag("size", 14))
   local seed = math.floor(flag("seed", 7))
   local dir = opt("out", ".")

   write(dir .. "/board.svg", render_board(n, side))
   write(dir .. "/turn-a.svg", render_turn(n, side, "A", size, seed))
   write(dir .. "/turn-b.svg", render_turn(n, side, "B", size, seed))
end

main(_G.arg as {string} or {})
