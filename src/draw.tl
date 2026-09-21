--- Rendering for the LOVE build: the board, chunks (live and ghosted),
--- headings, and the players' panels. Pure output -- nothing here mutates the
--- simulation. All the sqrt(3) lives in board.corners / board.centroid.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")

local record draw
   --- Where and how big the board is on screen.
   record View
      n: integer
      side: number
      cx: number
      cy: number
   end

   --- A floating bit of text (e.g. "-1" at a wall hit).
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

   INK: string
   MUTED: string
end

local type XY = bc.XY
local type Cell = bc.Cell
local type View = draw.View

local PAPER <const> = { 0.97, 0.97, 0.96 }
local GRID <const> = "#c5ccd3"
local WALL <const> = "#1f2933"
local INK <const> = "#1f2933"
local MUTED <const> = "#7b8794"

local grid_cache: {integer: {board.Seg}} = {}

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

--- Board space -> screen.
local function at(v: View, p: XY): number, number
   return v.cx + p.x, v.cy + p.y
end

function draw.background()
   love.graphics.setBackgroundColor(PAPER[1], PAPER[2], PAPER[3])
end

--- The triangle grid.
function draw.grid(v: View)
   local segs = grid_cache[v.n]
   if not segs then
      segs = board.grid_segments(v.n, v.side)
      grid_cache[v.n] = segs
   end
   color(GRID)
   love.graphics.setLineWidth(1)
   for _, s in ipairs(segs) do
      local x1, y1 = at(v, { x = s.x1, y = s.y1 })
      local x2, y2 = at(v, { x = s.x2, y = s.y2 })
      love.graphics.line(x1, y1, x2, y2)
   end
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

--- The six walls: defended walls solid in their player's colour, the wall on
--- loan to each player this turn dashed in that colour, neutral walls dark.
function draw.walls(v: View, turn: board.Turn)
   local own: {integer: string} = {}
   local lent: {integer: string} = {}
   for i, p in ipairs(board.PLAYERS) do
      own[p.wall] = p.color
      lent[board.launch_walls(i, turn)[2]] = p.color
   end
   love.graphics.setLineWidth(5)
   for j = 0, 5 do
      local w = board.wall(v.n, v.side, j)
      local x1, y1 = at(v, { x = w.x1, y = w.y1 })
      local x2, y2 = at(v, { x = w.x2, y = w.y2 })
      if own[j] then
         color(own[j])
         love.graphics.line(x1, y1, x2, y2)
      elseif lent[j] then
         color(lent[j])
         dashed(x1, y1, x2, y2, 14, 10)
      else
         color(WALL)
         love.graphics.line(x1, y1, x2, y2)
      end
   end
end

--- One chunk, shifted by (ox, oy) pixels (for slide animation), at `alpha`,
--- outlined in `owner` colour along every edge it does not share with itself.
function draw.chunk(v: View, cells: {Cell}, ox: number, oy: number, alpha: number, owner: string)
   local inside: {string: boolean} = {}
   for _, c in ipairs(cells) do inside[board.key(c.a, c.b)] = true end

   love.graphics.setLineWidth(1)
   for _, c in ipairs(cells) do
      local pts = board.corners(c.a, c.b, v.side)
      local x1, y1 = at(v, pts[1])
      local x2, y2 = at(v, pts[2])
      local x3, y3 = at(v, pts[3])
      color(bc.FILL[c.color], alpha)
      love.graphics.polygon("fill", x1 + ox, y1 + oy, x2 + ox, y2 + oy, x3 + ox, y3 + oy)
      love.graphics.setColor(PAPER[1], PAPER[2], PAPER[3], alpha)
      love.graphics.polygon("line", x1 + ox, y1 + oy, x2 + ox, y2 + oy, x3 + ox, y3 + oy)
   end

   color(owner, alpha)
   love.graphics.setLineWidth(2.5)
   for _, c in ipairs(cells) do
      local pts = board.corners(c.a, c.b, v.side)
      for i, nb in ipairs(bc.neighbors(c.a, c.b)) do
         if not inside[board.key(nb.a, nb.b)] then
            -- neighbour i faces the edge opposite corner i
            local p, q = pts[i % 3 + 1], pts[(i + 1) % 3 + 1]
            local x1, y1 = at(v, p)
            local x2, y2 = at(v, q)
            love.graphics.line(x1 + ox, y1 + oy, x2 + ox, y2 + oy)
         end
      end
   end
end

--- A short arrow just ahead of a chunk showing its heading.
function draw.arrow(v: View, cells: {Cell}, dir: XY, owner: string, alpha: number)
   local cx, cy = 0.0, 0.0
   for _, c in ipairs(cells) do
      local p = board.centroid(c.a, c.b, v.side)
      cx, cy = cx + p.x, cy + p.y
   end
   cx, cy = cx / #cells, cy / #cells
   local lead = 0.0
   for _, c in ipairs(cells) do
      local p = board.centroid(c.a, c.b, v.side)
      local d = (p.x - cx) * dir.x + (p.y - cy) * dir.y
      if d > lead then lead = d end
   end
   lead = lead + v.side * 0.9
   local tail: XY = { x = cx + dir.x * lead, y = cy + dir.y * lead }
   local head: XY = { x = cx + dir.x * (lead + v.side * 2.2), y = cy + dir.y * (lead + v.side * 2.2) }
   local px, py = -dir.y, dir.x
   local bx, by = head.x - dir.x * v.side * 0.7, head.y - dir.y * v.side * 0.7

   color(owner, alpha)
   love.graphics.setLineWidth(3)
   local tx, ty = at(v, tail)
   local hx, hy = at(v, head)
   love.graphics.line(tx, ty, hx, hy)
   local b1x, b1y = at(v, { x = bx + px * v.side * 0.35, y = by + py * v.side * 0.35 })
   local b2x, b2y = at(v, { x = bx - px * v.side * 0.35, y = by - py * v.side * 0.35 })
   love.graphics.polygon("fill", hx, hy, b1x, b1y, b2x, b2y)
end

--- A bank chunk drawn small inside a box centred at (x, y).
function draw.thumb(cells: {Cell}, x: number, y: number, side: number, owner: string, alpha: number)
   local cx, cy = 0.0, 0.0
   for _, c in ipairs(cells) do
      local p = board.centroid(c.a, c.b, side)
      cx, cy = cx + p.x, cy + p.y
   end
   cx, cy = cx / #cells, cy / #cells
   local v: View = { n = 0, side = side, cx = x - cx, cy = y - cy }
   draw.chunk(v, cells, 0, 0, alpha, owner)
end

--- Player panels down the right-hand side: name, HP, bank, this turn's shot.
function draw.panels(state: sim.State, pending: {sim.Shot}, placing: boolean, x: number, y: number, w: number,
                     small: love.Font, big: love.Font)
   local h = 200
   for p, pl in ipairs(board.PLAYERS) do
      local top = y + (p - 1) * (h + 16)
      local me = state.players[p]

      color(pl.color, 0.10)
      love.graphics.rectangle("fill", x, top, w, h, 8, 8)
      color(pl.color)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", x, top, w, h, 8, 8)

      love.graphics.setFont(big)
      color(pl.color)
      love.graphics.print(pl.name, x + 14, top + 10)

      local hp = me.hp
      color(hp > 0 and INK or "#b23a3a")
      love.graphics.print(("HP %d"):format(hp), x + w - 14 - big:getWidth(("HP %d"):format(hp)), top + 10)

      -- HP bar, clamped to 0..START_HP*2 so gains show too.
      local frac = math.max(0, math.min(1, hp / (sim.START_HP * 2)))
      color("#dfe4ea")
      love.graphics.rectangle("fill", x + 14, top + 46, w - 28, 8, 4, 4)
      color(hp > 0 and pl.color or "#b23a3a")
      love.graphics.rectangle("fill", x + 14, top + 46, (w - 28) * frac, 8, 4, 4)
      color(MUTED)
      love.graphics.setLineWidth(1)
      local mid = x + 14 + (w - 28) * 0.5
      love.graphics.line(mid, top + 44, mid, top + 56)

      love.graphics.setFont(small)
      color(MUTED)
      love.graphics.print("bank", x + 14, top + 64)
      local slot_w = (w - 28) / 3
      local firing: integer = nil
      for _, shot in ipairs(pending) do
         if shot.player == p then firing = shot.slot end
      end
      for i = 1, #me.bank do
         local bx = x + 14 + (i - 1) * slot_w
         local by = top + 84
         if firing == i then
            color(pl.color, 0.25)
            love.graphics.rectangle("fill", bx + 2, by, slot_w - 4, 84, 6, 6)
         end
         color("#ffffff", 0.6)
         love.graphics.rectangle("fill", bx + 2, by, slot_w - 4, 84, 6, 6)
         draw.thumb(me.bank[i], bx + slot_w / 2, by + 42, 8, pl.color, 1)
      end

      color(MUTED)
      local note = placing and "passes this turn" or ""
      for _, shot in ipairs(pending) do
         if shot.player == p then
            local own = pl.wall == shot.wall
            note = ("fires from %s wall -> wall %d"):format(
               own and "own" or "loaned", board.target_wall(p, shot.wall, state.turn))
         end
      end
      love.graphics.print(note, x + 14, top + 176)
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

return draw
