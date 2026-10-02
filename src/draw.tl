--- Rendering for the LOVE build: the board, chunks (live and
--- aimed), ghosts, headings and the players' panels. Pure output -- nothing
--- here changes the simulation. All the sqrt(3) lives in board.tl's drawing
--- helpers.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local setup = require("setup")

local record draw
   --- Where and how big the board is on screen, and which player's home is
   --- at the bottom (`south`): the board is turned by `turn` radians.
   record View
      board: board.Board
      side: number
      cx: number
      cy: number
      south: integer
      turn: number
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

   --- Who is at a player's panel: `label` names their controller. In a
   --- networked match `remote` seats are played elsewhere, so their aim is
   --- unknown here, and `ready` is a player's vote to fire now.
   record Seat
      label: string
      remote: boolean
      ready: boolean
   end

   --- A human's queue: the bank chunks either side of the one in use, as
   --- they'd sit on the board, and what takes each.
   record Queue
      player: integer
      left: {bc.Cell}
      right: {bc.Cell}
      keys: {string}
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

--- How far the board is turned as drawn, in sixths of a turn clockwise,
--- for player `south`'s corner to point straight down and the board's sides
--- to stand upright, like a Tetris well with that player at the bottom.
--- Corner c points at 60c degrees in board space; straight down is 90.
--- Player 1 at the bottom is a twelfth of a turn anticlockwise.
function draw.spin(south: integer): number
   return 1.5 - board.PLAYERS[south].corner
end

--- A board-space vector turned by `angle` radians.
local function turn(angle: number, x: number, y: number): number, number
   local c, s = math.cos(angle), math.sin(angle)
   return x * c - y * s, x * s + y * c
end

--- Headings as they point on screen, by (heading - corner at the bottom)
--- mod 6 (cf. board.HEADING_NAMES, which name them in board space).
local SCREEN_HEADINGS <const> = { "SE", "S", "SW", "NW", "N", "NE" }

--- Homes as they sit on screen, by (corner - corner at the bottom) / 2.
local SCREEN_HOMES <const> = { "south", "northwest", "northeast" }

--- Board space -> screen.
function draw.screen(v: View, p: XY): number, number
   local x, y = turn(v.turn, p.x, p.y)
   return v.cx + x, v.cy + y
end

--- Draw in board space until `leave`: the origin at the board's centre,
--- turned as the board is drawn.
local function enter(v: View)
   love.graphics.push()
   love.graphics.translate(v.cx, v.cy)
   love.graphics.rotate(v.turn)
end

local function leave()
   love.graphics.pop()
end

local function tri_fill(v: View, i: integer, ox: number, oy: number)
   local p = cache(v).corners[i]
   love.graphics.polygon("fill", p[1] + ox, p[2] + oy, p[3] + ox, p[4] + oy, p[5] + ox, p[6] + oy)
end

local function segment(s: board.Seg, ox: number, oy: number)
   love.graphics.line(s.x1 + ox, s.y1 + oy, s.x2 + ox, s.y2 + oy)
end

--- The biggest view of board `B` that fits the rectangle, centred in it,
--- with player `south`'s home (Player 1's if left out) at the bottom.
function draw.layout(B: board.Board, x: number, y: number, w: number, h: number, south?: integer): View
   south = south or 1
   local angle = draw.spin(south) * math.pi / 3
   local xmin, xmax, ymin, ymax = math.huge, -math.huge, math.huge, -math.huge
   for _, i in ipairs(B.cells) do
      for _, p in ipairs(board.corners(B.a[i], B.b[i], 1)) do
         local px, py = turn(angle, p.x, p.y)
         xmin, xmax = math.min(xmin, px), math.max(xmax, px)
         ymin, ymax = math.min(ymin, py), math.max(ymax, py)
      end
   end
   local side = math.floor(math.min(w / (xmax - xmin), h / (ymax - ymin)) * 4) / 4
   return {
      board = B,
      side = side,
      cx = x + w / 2 - (xmin + xmax) / 2 * side,
      cy = y + h / 2 - (ymin + ymax) / 2 * side,
      south = south,
      turn = angle,
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

--- The board: each home tinted in its player's colour, the grid, the dashed
--- lines round the middle and the back walls in ink. The walls themselves
--- aren't drawn; the board sits on bare paper.
function draw.board(v: View)
   local B = v.board
   local c = cache(v)
   enter(v)
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
   for _, s in ipairs(c.geometry.grid) do segment(s, 0, 0) end
   color(DASH)
   love.graphics.setLineWidth(2)
   for j = 0, 5 do
      local s = board.wall(B.n, v.side, j)
      dashed(s.x1, s.y1, s.x2, s.y2, v.side * 0.45, v.side * 0.35)
   end
   color(INK)
   love.graphics.setLineWidth(3.5)
   for _, s in ipairs(c.geometry.outline) do segment(s, 0, 0) end
   leave()
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
            love.graphics.line(pts[1].x + ox, pts[1].y + oy, pts[2].x + ox, pts[2].y + oy)
         end
      end
   end
end

--- A chunk's triangles, shifted by (ox, oy) pixels for animation, at `alpha`,
--- outlined in its owner's colour.
function draw.chunk(v: View, cells: {Tri}, ox: number, oy: number, alpha: number, owner: string)
   enter(v)
   for _, t in ipairs(cells) do
      color(bc.FILL[t.color], alpha)
      tri_fill(v, t.i, ox, oy)
   end
   love.graphics.setColor(PAPER[1], PAPER[2], PAPER[3], alpha)
   love.graphics.setLineWidth(1)
   local corners = cache(v).corners
   for _, t in ipairs(cells) do
      local p = corners[t.i]
      love.graphics.polygon("line", p[1] + ox, p[2] + oy, p[3] + ox, p[4] + oy, p[5] + ox, p[6] + oy)
   end
   color(owner, alpha)
   love.graphics.setLineWidth(2.5)
   silhouette(v, cells, ox, oy)
   leave()
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
   enter(v)
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
      -- Turned back, so the crosses stay upright on screen.
      love.graphics.push()
      love.graphics.translate(p.x, p.y)
      love.graphics.rotate(-v.turn)
      love.graphics.line(-r, -r, r, r)
      love.graphics.line(-r, r, r, -r)
      love.graphics.pop()
   end
   color(draw.look_color(ghost.look), 0.95)
   love.graphics.setLineWidth(2.5)
   silhouette(v, all, 0, 0)
   leave()
end

--- Grey `cells` out, for an aim that would be friendly fire.
function draw.grey(v: View, cells: {Tri})
   love.graphics.setColor(PAPER[1], PAPER[2], PAPER[3], 0.7)
   enter(v)
   for _, t in ipairs(cells) do tri_fill(v, t.i, 0, 0) end
   leave()
end

--- A red outline round an aim that fits nowhere.
function draw.misfit(v: View, cells: {Tri})
   color(DANGER, 0.9)
   love.graphics.setLineWidth(3)
   enter(v)
   silhouette(v, cells, 0, 0)
   leave()
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
   enter(v)
   love.graphics.line(tx, ty, hx, hy)
   love.graphics.polygon("fill", hx, hy,
      bx + px * v.side * 0.35, by + py * v.side * 0.35,
      bx - px * v.side * 0.35, by - py * v.side * 0.35)
   leave()
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

--- Player panels down the right-hand side: name, shot clock or status and
--- aim. Nobody's bank shows here; a human's own is in their queue. `aims`
--- holds what each player is aiming (bots and human alike), `clocks` the
--- seconds left on each one's shot clock, `seats` who is playing each one.
function draw.panels(v: View, state: sim.State, aims: {integer: draw.Aim}, clocks: {number}, seats: {draw.Seat},
                     x: number, y: number, w: number, small: love.Font, big: love.Font)
   local h = 92
   local bottom = board.PLAYERS[v.south].corner
   for p, pl in ipairs(board.PLAYERS) do
      local top = y + (p - 1) * (h + 12)
      local me = state.players[p]
      local seat = seats[p]
      local human = seat and seat.label ~= "bot"
      color(pl.color, me.alive and 0.10 or 0.04)
      love.graphics.rectangle("fill", x, top, w, h, 8, 8)
      color(pl.color, me.alive and 1 or 0.4)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", x, top, w, h, 8, 8)

      love.graphics.setFont(big)
      color(pl.color)
      local home = SCREEN_HOMES[(pl.corner - bottom) % 6 // 2 + 1]
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
         local under = seat and seat.ready and "ready to fire" or "shot clock"
         color(seat and seat.ready and pl.color or MUTED)
         love.graphics.print(under, x + w - 14 - small:getWidth(under), top + 38)
      else
         local status = OUT_NOTE[me.out]
         color(DANGER)
         love.graphics.print(status, x + w - 14 - small:getWidth(status), top + 16)
      end

      local aim = aims[p]
      if me.alive then
         local note: string
         local hue = MUTED
         if seat and seat.remote then
            note = "aiming, out of sight"
         elseif not aim then
            note = "nothing fits"
            hue = DANGER
         elseif not aim.look then
            note = human and "this chunk doesn't fit like this: rotate or take another" or "re-aiming"
            hue = human and DANGER or MUTED
         else
            note = ("aiming %s, %s"):format(SCREEN_HEADINGS[(aim.heading - bottom) % 6 + 1], LOOK_NOTE[aim.look])
            hue = aim.look == "clear" and INK or aim.look == "home" and AMBER or DANGER
         end
         color(hue)
         love.graphics.printf(note, x + 14, top + 62, w - 28, "left")
      end
   end
end

--- A queued chunk, turned as the board is drawn, centred in the box at
--- (x, y), w by h: as large as on the board, unless that won't fit.
local function queued(v: View, cells: {bc.Cell}, owner: string, x: number, y: number, w: number, h: number)
   local xmin, xmax, ymin, ymax = math.huge, -math.huge, math.huge, -math.huge
   for _, c in ipairs(cells) do
      for _, p in ipairs(bc.cell_corners(c.a, c.b, 1)) do
         local px, py = turn(v.turn, p.x, p.y)
         xmin, xmax = math.min(xmin, px), math.max(xmax, px)
         ymin, ymax = math.min(ymin, py), math.max(ymax, py)
      end
   end
   local side = math.min(v.side, (w - 24) / (xmax - xmin), (h - 24) / (ymax - ymin))
   love.graphics.push()
   love.graphics.translate(x + w / 2 - (xmin + xmax) / 2 * side, y + h / 2 - (ymin + ymax) / 2 * side)
   love.graphics.rotate(v.turn)
   for _, c in ipairs(cells) do
      local p = bc.cell_corners(c.a, c.b, side)
      color(bc.FILL[c.color])
      love.graphics.polygon("fill", p[1].x, p[1].y, p[2].x, p[2].y, p[3].x, p[3].y)
      love.graphics.setColor(PAPER[1], PAPER[2], PAPER[3])
      love.graphics.setLineWidth(1)
      love.graphics.polygon("line", p[1].x, p[1].y, p[2].x, p[2].y, p[3].x, p[3].y)
   end
   love.graphics.pop()
   color(owner)
   love.graphics.setLineWidth(2)
   love.graphics.rectangle("line", x, y, w, h, 8, 8)
end

--- Each human's queue along the bottom, `x` to `x + w` and `y` to `y + h`:
--- the chunk they'd take on the left and the one on the right, each in a box
--- with the key that takes it. The chunk in use is on the board, not here.
function draw.queues(v: View, queues: {draw.Queue}, x: number, y: number, w: number, h: number,
                     font: love.Font)
   if #queues == 0 then return end
   love.graphics.setFont(font)
   local part = w / #queues
   for k, q in ipairs(queues) do
      local pl = board.PLAYERS[q.player]
      local px = x + (k - 1) * part
      -- The two boxes sit apart, leaving the middle for the player's name.
      local gap = math.min(part * 0.2, 160)
      local bw = (part - gap) / 2 - 8
      local boxes: {{number, {bc.Cell}, string}} = {
         { px + 4, q.left, q.keys[1] },
         { px + part - 4 - bw, q.right, q.keys[2] },
      }
      for _, b in ipairs(boxes) do
         color(pl.color, 0.08)
         love.graphics.rectangle("fill", b[1], y, bw, h, 8, 8)
         if b[2] then queued(v, b[2], pl.color, b[1], y, bw, h) end
         color(pl.color)
         love.graphics.print(b[3], b[1] + 8, y + 6)
      end
      color(pl.color)
      love.graphics.printf(pl.name, px + 4 + bw, y + h / 2 - font:getHeight(), part - 8 - 2 * bw, "center")
      color(MUTED)
      love.graphics.printf("queue", px + 4 + bw, y + h / 2, part - 8 - 2 * bw, "center")
   end
end

--- Where the key legend's titles and chips go: each group starts a new line
--- with its title, then key chips with their descriptions, wrapping within
--- `w`. `stacked` puts each title on a line of its own, above its chips.
local record Chip
   key: string
   what: string
   x: number
   line: integer
end

local function legend_layout(groups: {draw.KeyGroup}, w: number, font: love.Font, stacked: boolean): {Chip}, {integer}, integer
   local indent = 0.0
   if not stacked then
      for _, group in ipairs(groups) do indent = math.max(indent, font:getWidth(group.title) + 16) end
   end
   local chips: {Chip} = {}
   local starts: {integer} = {}
   local line = 0
   for g, group in ipairs(groups) do
      starts[g] = line
      if stacked then line = line + 1 end
      local cx = indent
      for _, k in ipairs(group.keys) do
         local item = font:getWidth(k[1]) + 12 + 6 + font:getWidth(k[2]) + 18
         if cx > indent and cx + item > w then cx, line = indent, line + 1 end
         chips[#chips + 1] = { key = k[1], what = k[2], x = cx, line = line }
         cx = cx + item
      end
      line = line + 1
   end
   return chips, starts, line
end

--- The key legend's height, `w` wide (see `draw.controls`).
function draw.controls_height(groups: {draw.KeyGroup}, w: number, font: love.Font, stacked: boolean): number
   local _, _, lines = legend_layout(groups, w, font, stacked)
   return lines * (font:getHeight() + 10)
end

--- The key legend from (x, top), `w` wide: each group's title, in its
--- colour, then its key chips.
function draw.controls(groups: {draw.KeyGroup}, x: number, top: number, w: number, font: love.Font, stacked: boolean)
   love.graphics.setFont(font)
   local line_h = font:getHeight() + 10
   local chips, starts = legend_layout(groups, w, font, stacked)
   for g, group in ipairs(groups) do
      color(group.color or INK)
      love.graphics.print(group.title, x, top + starts[g] * line_h + 3)
   end
   for _, c in ipairs(chips) do
      local cx, cy = x + c.x, top + c.line * line_h
      local kw = font:getWidth(c.key) + 12
      color("#ffffff")
      love.graphics.rectangle("fill", cx, cy, kw, font:getHeight() + 6, 4, 4)
      color(GRID)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", cx, cy, kw, font:getHeight() + 6, 4, 4)
      color(INK)
      love.graphics.print(c.key, cx + 6, cy + 3)
      color(MUTED)
      love.graphics.print(c.what, cx + kw + 6, cy + 3)
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
