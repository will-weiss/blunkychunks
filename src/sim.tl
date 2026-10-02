--- The blunkychunks rules engine: integer logic on the board matrix from
--- board.tl. Nothing here knows about pixels or LOVE.
---
--- A match is a `State`: the board, the chunks on it with their headings, an
--- occupancy matrix, and each player's bank and status. Play is continuous and
--- the caller runs the clocks:
---
---   * every tick, `tick` slides each chunk that can move by one step;
---   * each player has their own shot clock, staggered so they run out in
---     turn (`clocks`, `run_down`); when one does, `lock_in` fires that
---     player's aim, or knocks them out if they have no legal one.
---
--- A step is blocked by a wall, by another player's home (their dashed line),
--- or by a triangle that isn't moving the same way. Your own dashed line never
--- blocks you. When chunks moving different ways would step into the same
--- cell, the one fired first takes its step and the others wait. A triangle
--- stopped by a wall while still in its owner's home has hit their back wall,
--- and the owner is out. After every tick and every lock-in, two same-coloured
--- triangles of different chunks that share an edge both clear, and chunks
--- that fall apart split, keeping heading, owner and when they were fired.

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
      fired: integer -- fire order, lower first; the pieces of a split keep their chunk's
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
      cells: {board.Tri} -- where what's left of the shot comes to rest
      hits: {board.Tri} -- the shot's triangles that clear, where they clear
      cleared: {board.Tri} -- the triangles at rest they clear
      look: Look
   end

   record TickResult
      moved: integer
      cleared: {board.Tri}
      hits: {board.Tri} -- triangles stopped by their own back wall
      out: {integer} -- players knocked out by those hits
   end

   record LockResult
      fired: Shot -- nil when there was no legal aim
      out: boolean -- knocked out for having no legal aim
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
      fired = state.next_id,
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

--- `cells` in edge-connected pieces.
local function connected(B: board.Board, cells: {Tri}): {{Tri}}
   local near = B.near
   local pool: {integer: Tri} = {}
   for _, c in ipairs(cells) do pool[c.i] = c end

   local pieces: {{Tri}} = {}
   for _, start in ipairs(cells) do
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
   return pieces
end

--- Split `chunk` into edge-connected pieces. The first keeps the chunk's
--- identity; each other one becomes a new chunk with the same owner, heading,
--- fire order and flags.
local function split(state: State, chunk: Chunk)
   local pieces = connected(state.board, chunk.cells)
   if #pieces <= 1 then return end
   chunk.cells = pieces[1]
   for k = 2, #pieces do
      local piece = new_chunk(state, chunk.owner, chunk.heading)
      piece.fired, piece.moved, piece.flying = chunk.fired, chunk.moved, chunk.flying
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
   local free: {Chunk} = {}
   local sweeps: {integer: {integer}} = {}
   local hit_wall: {integer: boolean} = {}
   for _, chunk in ipairs(state.chunks) do
      chunk.moved = false
      local step, pass = B.step[chunk.heading], B.pass[chunk.heading]
      local live = state.players[chunk.owner].alive
      local list: {integer} = {}
      local clear = true
      for _, c in ipairs(chunk.cells) do
         local here = kind[c.i]
         local hit = false
         for _, j in ipairs({ c.i + pass[board.facing(c.i)], c.i + step }) do
            local k = kind[j]
            if k == WALL then
               clear = false
               if here == chunk.owner and live then hit = true end
            elseif k ~= MIDDLE and k ~= chunk.owner then
               clear = false
            else
               list[#list + 1] = j
            end
         end
         if hit then
            result.hits[#result.hits + 1] = { i = c.i, color = c.color }
            hit_wall[chunk.owner] = true
         end
      end
      if clear then
         free[#free + 1] = chunk
         sweeps[chunk.id] = list
      end
   end

   -- In the order they were fired, each chunk moves if it can, together with
   -- the chunks in its way moving the same way (and those in theirs): a convoy
   -- goes when its earliest chunk does. It can't if any of them meets a
   -- triangle that is staying put or moving another way, or a cell an earlier
   -- chunk has already claimed moving another way.
   table.sort(free, function(x: Chunk, y: Chunk): boolean
      if x.fired ~= y.fired then return x.fired < y.fired end
      return x.id < y.id
   end)
   local moving: {integer: boolean} = {}
   local stuck: {integer: boolean} = {}
   local claims: {integer: integer} = {} -- cell -> the heading moving through it
   for _, chunk in ipairs(free) do
      if not moving[chunk.id] and not stuck[chunk.id] then
         local h = chunk.heading
         local convoy: {integer} = { chunk.id }
         local seen: {integer: boolean} = { [chunk.id] = true }
         local ok = true
         local k = 1
         while ok and k <= #convoy do
            for _, j in ipairs(sweeps[convoy[k]]) do
               if claims[j] and claims[j] ~= h then
                  ok = false
                  break
               end
               local other = occ[j]
               if other ~= 0 and not seen[other] then
                  if not sweeps[other] or stuck[other] or state.by_id[other].heading ~= h then
                     ok = false
                     break
                  end
                  seen[other] = true
                  if not moving[other] then convoy[#convoy + 1] = other end
               end
            end
            k = k + 1
         end
         if ok then
            for _, id in ipairs(convoy) do
               moving[id] = true
               for _, j in ipairs(sweeps[id]) do claims[j] = h end
            end
         else
            stuck[chunk.id] = true
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

--- Whether `cells`, fired by `p` on `heading`, would be friendly fire: some
--- triangle can never leave p's home that way, and runs into its back wall
--- unless something stops it for good first. Pure geometry, so it holds
--- whatever is in the way.
function sim.friendly(state: State, p: integer, cells: {Tri}, heading: integer): boolean
   local B = state.board
   local kind = B.kind
   local step, pass = B.step[heading], B.pass[heading]
   for _, c in ipairs(cells) do
      local i = c.i
      while kind[i] == p do
         if kind[i + pass[board.facing(i)]] == WALL or kind[i + step] == WALL then return true end
         i = i + step
      end
   end
   return false
end

--- Where `cells`, fired by `p` on `heading`, would come to rest, played out
--- against the board as it stands: chunks at rest stay put, and chunks in
--- flight (and the other players' aims, which aren't on the board yet) are
--- looked straight through. The shot slides against walls, other players'
--- homes and chunks at rest. Wherever one of its triangles meets a
--- same-coloured one at rest, as it's fired or after any step, both clear: a
--- hit. What's left falls into pieces that slide on independently, as they
--- would for real.
---
--- Its look is "friendly" if any triangle can't leave p's home on this
--- heading -- pure geometry, so it holds whatever is in the way -- otherwise
--- "home" if anything comes to rest in p's home, otherwise "clear".
function sim.ghost(state: State, p: integer, cells: {Tri}, heading: integer): sim.Ghost
   local B = state.board
   local kind, near, occ, paint, by_id = B.kind, B.near, state.occ, state.paint, state.by_id
   local step, pass = B.step[heading], B.pass[heading]

   local friendly = sim.friendly(state, p, cells, heading)

   -- The board as the ghost sees it: triangles at rest, less those it clears.
   local gone: {integer: boolean} = {}
   local function rest(j: integer): boolean
      local id = occ[j]
      return id ~= 0 and not by_id[id].flying and not gone[j]
   end
   local function stops(j: integer): boolean
      local k = kind[j]
      return k == WALL or (k ~= MIDDLE and k ~= p) or rest(j)
   end

   local shot: {Tri} = {}
   for k, c in ipairs(cells) do shot[k] = { i = c.i, color = c.color } end
   local pieces: {{Tri}} = #shot > 0 and { shot } or {}
   local hits: {Tri} = {}
   local struck: {Tri} = {}
   -- The shot's triangles by where they are, and which piece each is in.
   local mine: {integer: Tri}
   local piece_of: {integer: integer}
   local function index()
      mine, piece_of = {}, {}
      for n, piece in ipairs(pieces) do
         for _, t in ipairs(piece) do mine[t.i], piece_of[t.i] = t, n end
      end
   end

   while true do
      -- Hits, against triangles at rest or another piece of the shot.
      index()
      local hit: {Tri: boolean} = {}
      local cleared: {integer} = {}
      for n, piece in ipairs(pieces) do
         for _, t in ipairs(piece) do
            for _, d in ipairs(near[board.facing(t.i)]) do
               local j = t.i + d
               local m = piece_of[j]
               if m then
                  if m ~= n and mine[j].color == t.color then hit[t] = true end
               elseif rest(j) and paint[j] == bc.CODE[t.color] then
                  hit[t] = true
                  cleared[#cleared + 1] = j
               end
            end
         end
      end
      if next(hit) then
         for _, j in ipairs(cleared) do
            if not gone[j] then
               gone[j] = true
               struck[#struck + 1] = { i = j, color = bc.COLORS[paint[j]] }
            end
         end
         local kept: {{Tri}} = {}
         for _, piece in ipairs(pieces) do
            local left: {Tri} = {}
            for _, t in ipairs(piece) do
               if hit[t] then
                  hits[#hits + 1] = { i = t.i, color = t.color }
               else
                  left[#left + 1] = t
               end
            end
            if #left == #piece then
               kept[#kept + 1] = piece
            else
               for _, part in ipairs(connected(B, left)) do kept[#kept + 1] = part end
            end
         end
         pieces = kept
         index()
      end

      -- Every piece that can takes a step, all at once. A piece is held by
      -- whatever would stop a chunk, or by a piece of the shot that is held.
      local moving: {integer: boolean} = {}
      for n, piece in ipairs(pieces) do
         moving[n] = true
         for _, t in ipairs(piece) do
            if stops(t.i + pass[board.facing(t.i)]) or stops(t.i + step) then
               moving[n] = nil
               break
            end
         end
      end
      local changed = true
      while changed do
         changed = false
         for n, piece in ipairs(pieces) do
            if moving[n] then
               for _, t in ipairs(piece) do
                  local a, b = piece_of[t.i + pass[board.facing(t.i)]], piece_of[t.i + step]
                  if (a and not moving[a]) or (b and not moving[b]) then
                     moving[n] = nil
                     changed = true
                     break
                  end
               end
            end
         end
      end
      if not next(moving) then break end
      for n in pairs(moving) do
         for _, t in ipairs(pieces[n]) do t.i = t.i + step end
      end
   end

   local landed: {Tri} = {}
   local look: sim.Look = friendly and "friendly" or "clear"
   for _, piece in ipairs(pieces) do
      for _, t in ipairs(piece) do
         landed[#landed + 1] = t
         if look == "clear" and kind[t.i] == p then look = "home" end
      end
   end
   return { cells = landed, hits = hits, cleared = struck, look = look }
end

--- Player `p`'s shot clock ran out: their aim `shot` fires. If they have no
--- legal aim (no shot, a placement that no longer fits, or a heading that
--- isn't theirs) they are out instead. A player already out is left alone.
function sim.lock_in(state: State, p: integer, shot: sim.Shot): sim.LockResult
   local pl = state.players[p]
   if not pl.alive then return { out = false, cleared = {} } end
   if shot and shot.player == p and sim.can_head(p, shot.heading) and sim.legal(state, p, shot.cells) then
      return { fired = shot, out = false, cleared = sim.fire(state, { shot }) }
   end
   pl.alive, pl.out = false, "stuck"
   return { out = true, cleared = {} }
end

--- Everyone's shot clocks at the start of a match, in seconds left. Each
--- clock runs for `period`, staggered so they run out in turn, Player 1's
--- first, a third of a clock apart: everyone's first clock is a full period
--- plus a third of one for each player before them.
function sim.clocks(period: number): {number}
   local n = #board.PLAYERS
   local clocks: {number} = {}
   for p = 1, n do clocks[p] = period + period * (p - 1) / n end
   return clocks
end

--- Run every live player's shot clock down by `dt` seconds and return the
--- players whose clocks ran out, in the order they did. Each of those starts
--- again from the moment it ran out, so the clocks keep their stagger.
function sim.run_down(state: State, clocks: {number}, dt: number, period: number): {integer}
   local due: {integer} = {}
   for p, pl in ipairs(state.players) do
      if pl.alive then
         clocks[p] = clocks[p] - dt
         if clocks[p] <= 0 then due[#due + 1] = p end
      end
   end
   table.sort(due, function(p: integer, q: integer): boolean
      if clocks[p] ~= clocks[q] then return clocks[p] < clocks[q] end
      return p < q
   end)
   for _, p in ipairs(due) do
      repeat clocks[p] = clocks[p] + period until clocks[p] > 0
   end
   return due
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
