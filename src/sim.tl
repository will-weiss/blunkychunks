--- The blunkychunks rules engine. Pure integer lattice logic on top of
--- board.tl; nothing here knows about pixels or LOVE.
---
--- A match is a `State`: the chunks currently on the board (each with the
--- lattice step it takes every tick and the wall it is heading for), an
--- occupancy map, the three players' HP and banks, and whose sweep it is.
---
--- Turn flow, driven by the caller:
---
---   1. `fire` the players' shots (already placed flush against a wall).
---   2. `tick` repeatedly until it reports that nothing moved.
---   3. `end_turn` flips the sweep direction.
---
--- One tick advances every chunk that can move by one lattice step, all at
--- once. A chunk is blocked when any of its triangles would land on, or sweep
--- through, a triangle of a chunk that is not itself moving the same way.
--- Triangles whose destination is off the board leave through the chunk's
--- target wall: an opponent's wall costs them 1 HP and pays the firer 1 HP; a
--- neutral wall just swallows them. Then any two edge-adjacent triangles of
--- the same colour from different chunks clear, and chunks that fall apart
--- split into independent chunks with the same heading and owner.

local bc = require("blunkychunks")
local board = require("board")

local record sim
   record Chunk
      id: integer
      owner: integer
      step: bc.AB
      target: integer
      cells: {bc.Cell}
      moved: boolean
   end

   record Player
      hp: integer
      bank: {{bc.Cell}}
   end

   record Hit
      owner: integer
      wall: integer
      victim: integer
      cell: bc.Cell
   end

   record TickResult
      moved: integer
      hits: {Hit}
      cleared: {bc.Cell}
   end

   record Shot
      player: integer
      wall: integer
      slot: integer
      cells: {bc.Cell}
   end

   record State
      n: integer
      size: integer
      chunks: {Chunk}
      occ: {string: Chunk}
      players: {Player}
      turn: board.Turn
      round: integer
      next_id: integer
      rng: function(): number
   end

   START_HP: integer
   BANK: integer
end

local type Cell = bc.Cell
local type AB = bc.AB
local type Chunk = sim.Chunk
local type State = sim.State

sim.START_HP = 10
sim.BANK = 3

local key = board.key

--- The player (1-based) defending wall `j`, or nil for a neutral wall.
function sim.wall_owner(j: integer): integer
   for p, pl in ipairs(board.PLAYERS) do
      if pl.wall == j then return p end
   end
   return nil
end

--- A fresh match on a hexagon of side `n`, chunks of `size` triangles.
function sim.new(n: integer, size: integer, rng: function(): number): State
   local players: {sim.Player} = {}
   for p = 1, #board.PLAYERS do
      local bank: {{Cell}} = {}
      for i = 1, sim.BANK do bank[i] = bc.generate(size, rng) end
      players[p] = { hp = sim.START_HP, bank = bank }
   end
   return {
      n = n,
      size = size,
      chunks = {},
      occ = {},
      players = players,
      turn = "A",
      round = 1,
      next_id = 1,
      rng = rng,
   }
end

--- Put a chunk on the board. `cells` must be free; this is also how tests
--- build scenarios.
function sim.add_chunk(state: State, owner: integer, step: AB, target: integer, cells: {Cell}): Chunk
   local chunk: Chunk = {
      id = state.next_id,
      owner = owner,
      step = { a = step.a, b = step.b },
      target = target,
      cells = {},
      moved = false,
   }
   state.next_id = state.next_id + 1
   for i, c in ipairs(cells) do
      local k = key(c.a, c.b)
      if state.occ[k] then
         error(("cell (%d, %d) is already occupied"):format(c.a, c.b))
      end
      chunk.cells[i] = { a = c.a, b = c.b, color = c.color }
      state.occ[k] = chunk
   end
   state.chunks[#state.chunks + 1] = chunk
   return chunk
end

--- Cells no new chunk may be placed on: everything on the board plus the
--- cells of shots already chosen this turn but not yet fired.
function sim.blocked_set(state: State, pending: {sim.Shot}): {string: boolean}
   local set: {string: boolean} = {}
   for k in pairs(state.occ) do set[k] = true end
   for _, shot in ipairs(pending or {}) do
      for _, c in ipairs(shot.cells) do set[key(c.a, c.b)] = true end
   end
   return set
end

--- Remove the cells listed in `gone` (a set of keys) from the board.
--- Returns the chunks that lost cells.
local function remove_cells(state: State, gone: {string: boolean}): {Chunk}
   local touched: {Chunk} = {}
   local seen: {integer: boolean} = {}
   for k in pairs(gone) do
      local chunk = state.occ[k]
      if chunk then
         state.occ[k] = nil
         if not seen[chunk.id] then
            seen[chunk.id] = true
            touched[#touched + 1] = chunk
         end
      end
   end
   for _, chunk in ipairs(touched) do
      local kept: {Cell} = {}
      for _, c in ipairs(chunk.cells) do
         if not gone[key(c.a, c.b)] then kept[#kept + 1] = c end
      end
      chunk.cells = kept
   end
   return touched
end

--- Drop empty chunks from the list.
local function prune(state: State)
   local kept: {Chunk} = {}
   for _, chunk in ipairs(state.chunks) do
      if #chunk.cells > 0 then kept[#kept + 1] = chunk end
   end
   state.chunks = kept
end

--- Split `chunk` into edge-connected components. The first component keeps
--- the chunk's identity; every other one becomes a new chunk with the same
--- owner, step and target (and `moved` flag, so animation carries over).
local function split(state: State, chunk: Chunk)
   local pool: {string: Cell} = {}
   for _, c in ipairs(chunk.cells) do pool[key(c.a, c.b)] = c end

   local components: {{Cell}} = {}
   for _, start in ipairs(chunk.cells) do
      local sk = key(start.a, start.b)
      if pool[sk] then
         local comp: {Cell} = {}
         local queue: {Cell} = { start }
         pool[sk] = nil
         while #queue > 0 do
            local c = table.remove(queue)
            comp[#comp + 1] = c
            for _, nb in ipairs(bc.neighbors(c.a, c.b)) do
               local nk = key(nb.a, nb.b)
               local other = pool[nk]
               if other then
                  pool[nk] = nil
                  queue[#queue + 1] = other
               end
            end
         end
         components[#components + 1] = comp
      end
   end

   if #components <= 1 then return end
   chunk.cells = components[1]
   for i = 2, #components do
      local piece: Chunk = {
         id = state.next_id,
         owner = chunk.owner,
         step = { a = chunk.step.a, b = chunk.step.b },
         target = chunk.target,
         cells = components[i],
         moved = chunk.moved,
      }
      state.next_id = state.next_id + 1
      for _, c in ipairs(piece.cells) do state.occ[key(c.a, c.b)] = piece end
      state.chunks[#state.chunks + 1] = piece
   end
end

--- Clear every pair of edge-adjacent same-colour triangles that belong to
--- different chunks, then split whatever fell apart. Returns the cleared
--- cells.
local function resolve_clears(state: State): {Cell}
   local gone: {string: boolean} = {}
   local cleared: {Cell} = {}
   for _, chunk in ipairs(state.chunks) do
      for _, c in ipairs(chunk.cells) do
         for _, nb in ipairs(bc.neighbors(c.a, c.b)) do
            local nk = key(nb.a, nb.b)
            local other = state.occ[nk]
            if other and other ~= chunk then
               local oc: Cell = nil
               for _, x in ipairs(other.cells) do
                  if x.a == nb.a and x.b == nb.b then oc = x break end
               end
               if oc and oc.color == c.color then
                  local ck = key(c.a, c.b)
                  if not gone[ck] then gone[ck] = true cleared[#cleared + 1] = c end
                  if not gone[nk] then gone[nk] = true cleared[#cleared + 1] = oc end
               end
            end
         end
      end
   end
   if #cleared == 0 then return cleared end
   local touched = remove_cells(state, gone)
   for _, chunk in ipairs(touched) do
      if #chunk.cells > 0 then split(state, chunk) end
   end
   prune(state)
   return cleared
end

--- Lock in the turn's shots: each becomes a chunk on its player's heading for
--- the turn (see `board.target_wall`), and the fired bank slot is refilled.
--- Chunks that land touching a same-colour triangle clear immediately.
function sim.fire(state: State, shots: {sim.Shot}): {Cell}
   for _, shot in ipairs(shots) do
      sim.add_chunk(state, shot.player,
         board.step(shot.player, state.turn),
         board.target_wall(shot.player, shot.wall, state.turn),
         shot.cells)
      local player = state.players[shot.player]
      if shot.slot then
         player.bank[shot.slot] = bc.generate(state.size, state.rng)
      end
   end
   return resolve_clears(state)
end

local function same_step(x: Chunk, y: Chunk): boolean
   return x.step.a == y.step.a and x.step.b == y.step.b
end

--- Advance the board one lattice step.
function sim.tick(state: State): sim.TickResult
   local n = state.n
   local moving: {integer: boolean} = {}
   for _, chunk in ipairs(state.chunks) do
      moving[chunk.id] = true
      chunk.moved = false
   end

   -- The cells each chunk would pass over or land on, on the board only.
   local sweeps: {integer: {string}} = {}
   for _, chunk in ipairs(state.chunks) do
      local list: {string} = {}
      for _, c in ipairs(chunk.cells) do
         local m = board.swept(c.a, c.b, chunk.step)
         if board.contains(n, m.a, m.b) then list[#list + 1] = key(m.a, m.b) end
         local da, db = c.a + chunk.step.a, c.b + chunk.step.b
         if board.contains(n, da, db) then list[#list + 1] = key(da, db) end
      end
      sweeps[chunk.id] = list
   end

   -- Fixpoint: block anything whose sweep hits a triangle that is standing
   -- still or moving another way, or whose sweep crosses such a chunk's.
   local changed = true
   while changed do
      changed = false
      local claims: {string: Chunk} = {}
      for _, chunk in ipairs(state.chunks) do
         if moving[chunk.id] then
            local blocked = false
            for _, k in ipairs(sweeps[chunk.id]) do
               local other = state.occ[k]
               if other and other ~= chunk and (not moving[other.id] or not same_step(other, chunk)) then
                  blocked = true
                  break
               end
               local rival = claims[k]
               if rival and rival ~= chunk and not same_step(rival, chunk) then
                  blocked = true
                  moving[rival.id] = nil
                  break
               end
               claims[k] = chunk
            end
            if blocked then
               moving[chunk.id] = nil
               changed = true
            end
         end
      end
   end

   -- Move everything that can, all at once.
   local result: sim.TickResult = { moved = 0, hits = {}, cleared = {} }
   local movers: {Chunk} = {}
   for _, chunk in ipairs(state.chunks) do
      if moving[chunk.id] then
         movers[#movers + 1] = chunk
         for _, c in ipairs(chunk.cells) do state.occ[key(c.a, c.b)] = nil end
      end
   end
   for _, chunk in ipairs(movers) do
      chunk.moved = true
      result.moved = result.moved + 1
      local kept: {Cell} = {}
      for _, c in ipairs(chunk.cells) do
         local da, db = c.a + chunk.step.a, c.b + chunk.step.b
         if board.contains(n, da, db) then
            local moved_cell: Cell = { a = da, b = db, color = c.color }
            kept[#kept + 1] = moved_cell
            state.occ[key(da, db)] = chunk
         else
            local victim = sim.wall_owner(chunk.target)
            result.hits[#result.hits + 1] = { owner = chunk.owner, wall = chunk.target, victim = victim, cell = c }
            if victim then
               state.players[victim].hp = state.players[victim].hp - 1
               if victim ~= chunk.owner then
                  state.players[chunk.owner].hp = state.players[chunk.owner].hp + 1
               end
            end
         end
      end
      chunk.cells = kept
   end
   prune(state)

   -- Exits can also disconnect a chunk.
   for _, chunk in ipairs(movers) do
      if #chunk.cells > 0 then split(state, chunk) end
   end

   result.cleared = resolve_clears(state)
   return result
end

--- Flip the sweep direction for the next turn.
function sim.end_turn(state: State)
   state.turn = state.turn == "A" and "B" or "A"
   state.round = state.round + 1
end

--- The player who has both opponents at or below zero, or nil.
function sim.winner(state: State): integer
   for p, pl in ipairs(state.players) do
      if pl.hp > 0 then
         local others_down = true
         for q, other in ipairs(state.players) do
            if q ~= p and other.hp > 0 then others_down = false end
         end
         if others_down then return p end
      end
   end
   return nil
end

return sim
