--- Rendering for the LOVE build: the board in its walls, chunks (live and
--- aimed), ghosts, headings and the players' panels. Pure output -- nothing
--- here changes the simulation. All the sqrt(3) lives in board.tl's drawing
--- helpers.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local setup = require("setup")

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
      color: string -- the title's colour, INK if nil
      keys: {{string, string}}
   end

   --- Who is at a player's panel: `label` names their controller, and
   --- `slots`, for a human, what picks each bank slot.
   record Seat
      label: string
      slots: {string}
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

--- Where a ghost lands: its triangles in faded colours, outlined in its look's
--- colour. Its hits, the triangles that clear against a same-coloured one, are
--- in full colour and crossed out, where they clear.
function draw.ghost(v: View, ghost: sim.Ghost)
   local B = v.board
   local all: {Tri} = {}
   for _, t in ipairs(ghost.cells) do
      color(bc.FILL[t.color], 0.3)
      tri_fill(v, t.i, 0, 0)
      all[#all + 1] = t
   end
   for _, t in ipairs(ghost.hits) do
      color(bc.FILL[t.color])
      tri_fill(v, t.i, 0, 0)
      all[#all + 1] = t
   end
   love.graphics.setColor(1, 1, 1)
   love.graphics.setLineWidth(2)
   local r = v.side * 0.16
   for _, t in ipairs(ghost.hits) do
      local p = board.centroid(B.a[t.i], B.b[t.i], v.side)
      local x, y = v.cx + p.x, v.cy + p.y
      love.graphics.line(x - r, y - r, x + r, y + r)
      love.graphics.line(x - r, y + r, x + r, y - r)
   end
   color(draw.look_color(ghost.look), 0.95)
   love.graphics.setLineWidth(2.5)
   silhouette(v, all, 0, 0)
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

--- Player panels down the right-hand side: name, shot clock or status, bank
--- and aim. `aims` holds what each player is aiming (bots and human alike),
--- `clocks` the seconds left on each one's shot clock, `seats` who is
--- playing each one.
function draw.panels(state: sim.State, aims: {integer: draw.Aim}, clocks: {number}, seats: {draw.Seat},
                     x: number, y: number, w: number, small: love.Font, big: love.Font)
   local h = 228
   for p, pl in ipairs(board.PLAYERS) do
      local top = y + (p - 1) * (h + 14)
      local me = state.players[p]
      local seat = seats[p]
      local human = seat and seat.slots ~= nil
      color(pl.color, me.alive and 0.10 or 0.04)
      love.graphics.rectangle("fill", x, top, w, h, 8, 8)
      color(pl.color, me.alive and 1 or 0.4)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", x, top, w, h, 8, 8)

      love.graphics.setFont(big)
      color(pl.color)
      local home = ({ "southwest", "northwest", "east" })[p]
      love.graphics.print(pl.name, x + 14, top + 10)
      love.graphics.setFont(small)
      color(MUTED)
      love.graphics.print(seat and ("%s  -  %s"):format(home, seat.label) or home, x + 14, top + 38)
      if me.alive then
         local left = ("%.1f s"):format(math.max(0, clocks[p]))
         love.graphics.setFont(big)
         color(INK)
         love.graphics.print(left, x + w - 14 - big:getWidth(left), top + 10)
         love.graphics.setFont(small)
         color(MUTED)
         love.graphics.print("shot clock", x + w - 14 - small:getWidth("shot clock"), top + 38)
      else
         local status = OUT_NOTE[me.out]
         color(DANGER)
         love.graphics.print(status, x + w - 14 - small:getWidth(status), top + 16)
      end

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
         if human then
            color(aim and aim.slot == i and pl.color or MUTED)
            love.graphics.print(seat.slots[i] or tostring(i), bx + 8, by + 4)
         end
      end

      if me.alive then
         local note: string
         local hue = MUTED
         if not aim then
            note = "nothing fits"
            hue = DANGER
         elseif not aim.look then
            note = human and "this chunk doesn't fit like this: rotate or pick another" or "re-aiming"
            hue = human and DANGER or MUTED
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
--- chips with their descriptions, wrapping within `w`. The legend sits on
--- `bottom`, growing upward as it needs more lines.
function draw.controls(groups: {draw.KeyGroup}, x: number, bottom: number, w: number, font: love.Font)
   love.graphics.setFont(font)
   local line_h = font:getHeight() + 10
   local indent = 0.0
   for _, group in ipairs(groups) do indent = math.max(indent, font:getWidth(group.title) + 16) end

   -- Lay the chips out first, to know how many lines they take.
   local record Chip
      key: string
      what: string
      x: number
      line: integer
   end
   local chips: {Chip} = {}
   local starts: {integer} = {}
   local line = 0
   for g, group in ipairs(groups) do
      local cx = x + indent
      starts[g] = line
      for _, k in ipairs(group.keys) do
         local item = font:getWidth(k[1]) + 12 + 6 + font:getWidth(k[2]) + 18
         if cx > x + indent and cx + item > x + w then cx, line = x + indent, line + 1 end
         chips[#chips + 1] = { key = k[1], what = k[2], x = cx, line = line }
         cx = cx + item
      end
      line = line + 1
   end

   local top = bottom - line * line_h
   for g, group in ipairs(groups) do
      color(group.color or INK)
      love.graphics.print(group.title, x, top + starts[g] * line_h + 3)
   end
   for _, c in ipairs(chips) do
      local cy = top + c.line * line_h
      local kw = font:getWidth(c.key) + 12
      color("#ffffff")
      love.graphics.rectangle("fill", c.x, cy, kw, font:getHeight() + 6, 4, 4)
      color(GRID)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", c.x, cy, kw, font:getHeight() + 6, 4, 4)
      color(INK)
      love.graphics.print(c.key, c.x + 6, cy + 3)
      color(MUTED)
      love.graphics.print(c.what, c.x + kw + 6, cy + 3)
   end
end

--- The setup screen's rows from `x`, `y`, `w` wide: each a label and its
--- value, the one under the cursor highlighted with arrows either side of
--- its value, and the last (Start) drawn as a button.
function draw.setup(lines: {setup.Line}, cursor: integer, x: number, y: number, w: number,
                    body: love.Font, big: love.Font)
   local h, gap = 50, 8
   for i, line in ipairs(lines) do
      local top = y + (i - 1) * (h + gap)
      if i == #lines then top = top + 18 end
      local here = i == cursor
      local hue = line.color or INK
      if i == #lines then
         color(here and INK or "#ffffff")
         love.graphics.rectangle("fill", x, top, w, h, 8, 8)
         color(INK)
         love.graphics.setLineWidth(2)
         love.graphics.rectangle("line", x, top, w, h, 8, 8)
         love.graphics.setFont(big)
         if here then love.graphics.setColor(1, 1, 1) end
         love.graphics.printf(line.label, x, top + (h - big:getHeight()) / 2, w, "center")
      else
         if line.color then
            color(line.color, here and 0.18 or 0.08)
         else
            color(here and AMBER or "#ffffff", here and 0.18 or 0.6)
         end
         love.graphics.rectangle("fill", x, top, w, h, 8, 8)
         color(here and hue or GRID)
         love.graphics.setLineWidth(here and 2 or 1)
         love.graphics.rectangle("line", x, top, w, h, 8, 8)
         love.graphics.setFont(big)
         color(hue)
         love.graphics.print(line.label, x + 16, top + (h - big:getHeight()) / 2)
         local value = here and ("<   %s   >"):format(line.value) or line.value
         color(here and INK or MUTED)
         love.graphics.print(value, x + w - 16 - big:getWidth(value), top + (h - big:getHeight()) / 2)
      end
   end
   love.graphics.setFont(body)
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
