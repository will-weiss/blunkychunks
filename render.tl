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
