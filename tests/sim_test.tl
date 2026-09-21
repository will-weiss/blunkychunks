local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local A = require("tests.assert")

local type Cell = bc.Cell

local record T
end

-- Player 2 on turn A: step (1, 2), heading east at wall 5 (Player 3).
local RIGHT = board.step(2, "A")
-- Player 3 on turn B: step (-1, -2), heading west at wall 1 (Player 1).
local LEFT = board.step(3, "B")

local function cell(a: integer, b: integer, color: bc.Color): Cell
   return { a = a, b = b, color = color }
end

local function has(state: sim.State, a: integer, b: integer): boolean
   return state.occ[board.key(a, b)] ~= nil
end

local function fresh(n: integer): sim.State
   return sim.new(n, 4, bc.seeded_random(1))
end

function T.new_match()
   local s = fresh(5)
   A.eq(#s.players, 3, "three players")
   for _, p in ipairs(s.players) do
      A.eq(p.hp, 10, "10 HP")
      A.eq(#p.bank, 3, "bank of three")
      for _, chunk in ipairs(p.bank) do A.eq(#chunk, 4, "chunk size") end
   end
   A.eq(s.turn, "A", "starts on turn A")
   A.eq(#s.chunks, 0, "empty board")
end

function T.free_chunk_slides_one_step_per_tick()
   local s = fresh(5)
   sim.add_chunk(s, 2, RIGHT, 5, { cell(0, 0, "red"), cell(1, 1, "green") })
   local r = sim.tick(s)
   A.eq(r.moved, 1, "one chunk moved")
   A.eq(#r.hits, 0, "no hits")
   A.truthy(has(s, 1, 2) and has(s, 2, 3), "cells advanced by the step")
   A.truthy(not has(s, 0, 0) and not has(s, 1, 1), "old cells vacated")
   A.truthy(s.chunks[1].moved, "moved flag set")
end

function T.exit_through_opponent_wall_scores()
   local s = fresh(2)
   -- (1, 2) is flush against wall 5 on a side-2 board; one step right leaves.
   sim.add_chunk(s, 2, RIGHT, 5, { cell(1, 2, "red") })
   local r = sim.tick(s)
   A.eq(#r.hits, 1, "one hit")
   A.eq(r.hits[1].victim, 3, "Player 3 defends wall 5")
   A.eq(r.hits[1].owner, 2, "fired by Player 2")
   A.eq(s.players[3].hp, 9, "victim loses one")
   A.eq(s.players[2].hp, 11, "firer gains one")
   A.eq(s.players[1].hp, 10, "bystander unchanged")
   A.eq(#s.chunks, 0, "empty chunk removed")
   A.eq((next(s.occ) as string), nil, "occupancy cleared")
end

function T.exit_through_neutral_wall_is_free()
   local s = fresh(2)
   -- Heading left at wall 2 (neutral). (-1, -2) is one step left of (0, 0).
   -- Find a cell on the board whose left step is off the board.
   local start: Cell = nil
   for _, c in ipairs(board.cells(2)) do
      if not board.contains(2, c.a + LEFT.a, c.b + LEFT.b) and board.depth(2, c.a, c.b) == 2 then
         start = cell(c.a, c.b, "blue")
         break
      end
   end
   A.truthy(start, "found a cell flush against wall 2")
   sim.add_chunk(s, 1, LEFT, 2, { start })
   local r = sim.tick(s)
   A.eq(#r.hits, 1, "one hit")
   A.eq(r.hits[1].victim, nil, "neutral wall has no victim")
   for p = 1, 3 do A.eq(s.players[p].hp, 10, "no HP change") end
   A.eq(#s.chunks, 0, "chunk gone")
end

function T.head_on_chunks_block_each_other()
   local s = fresh(5)
   -- X at (0,0) moving right sweeps (1,1) then lands on (1,2).
   -- Y at (1,2) moving left sweeps (1,1) then lands on (0,0).
   sim.add_chunk(s, 2, RIGHT, 5, { cell(0, 0, "red") })
   sim.add_chunk(s, 1, LEFT, 2, { cell(1, 2, "green") })
   local r = sim.tick(s)
   A.eq(r.moved, 0, "nothing moved")
   A.truthy(has(s, 0, 0) and has(s, 1, 2), "both stay put")
end

function T.swept_cell_blocks_even_when_destination_is_free()
   local s = fresh(5)
   -- Y sits on X's swept cell (1,1) heading left; X's destination (1,2) is empty.
   sim.add_chunk(s, 2, RIGHT, 5, { cell(0, 0, "red") })
   sim.add_chunk(s, 1, LEFT, 2, { cell(1, 1, "green") })
   local r = sim.tick(s)
   A.eq(r.moved, 0, "nothing moved")
end

function T.convoy_moves_together()
   local s = fresh(5)
   -- Y directly ahead of X, both heading right: X's destination is Y's cell.
   sim.add_chunk(s, 2, RIGHT, 5, { cell(0, 0, "red") })
   sim.add_chunk(s, 2, RIGHT, 5, { cell(1, 2, "green") })
   local r = sim.tick(s)
   A.eq(r.moved, 2, "both moved")
   A.truthy(has(s, 1, 2) and has(s, 2, 4), "convoy advanced")
end

function T.blocked_chunk_stalls_the_one_behind()
   local s = fresh(5)
   sim.add_chunk(s, 2, RIGHT, 5, { cell(0, 0, "red") })     -- X
   sim.add_chunk(s, 2, RIGHT, 5, { cell(1, 2, "green") })   -- Y, ahead of X
   sim.add_chunk(s, 1, LEFT, 2, { cell(2, 4, "red") })      -- Z, head-on with Y
   local r = sim.tick(s)
   A.eq(r.moved, 0, "convoy stalled by the blocker")
end

function T.clear_on_contact_removes_exactly_the_pair()
   local s = fresh(5)
   -- A standing red cell P, held in place by a head-on partner Q.
   local P = cell(2, 3, "red")
   -- Q sits on P's destination heading right, so both are blocked head-on.
   local Q: Cell = cell(P.a + LEFT.a, P.b + LEFT.b, "green")
   sim.add_chunk(s, 1, LEFT, 2, { P })
   sim.add_chunk(s, 2, RIGHT, 5, { Q })
   local r0 = sim.tick(s)
   A.eq(r0.moved, 0, "P and Q are a standing pair")
   -- Now a red cell X that slides into edge contact with P. P's neighbours:
   -- pick one that is free and reachable by a right-moving cell one step back.
   -- Pick a free neighbour of P that a right-moving red cell can reach: the
   -- cell one step back and the cell it sweeps must both be free and on board.
   local target: bc.AB = nil
   local from: Cell = nil
   for _, nb in ipairs(bc.neighbors(P.a, P.b)) do
      local f: Cell = cell(nb.a - RIGHT.a, nb.b - RIGHT.b, "red")
      local fm = board.swept(f.a, f.b, RIGHT)
      local free = not s.occ[board.key(nb.a, nb.b)]
         and not s.occ[board.key(f.a, f.b)]
         and not s.occ[board.key(fm.a, fm.b)]
      if free and board.contains(5, nb.a, nb.b) and board.contains(5, f.a, f.b) then
         target, from = nb, f
      end
   end
   A.truthy(target, "P has a reachable free neighbour")
   sim.add_chunk(s, 3, RIGHT, 5, { from })
   local r = sim.tick(s)
   A.eq(r.moved, 1, "X moved")
   A.eq(#r.cleared, 2, "the red pair cleared")
   A.truthy(not has(s, P.a, P.b), "P gone")
   A.truthy(not has(s, target.a, target.b), "X gone")
   A.truthy(has(s, Q.a, Q.b), "Q untouched")
end

function T.fire_places_chunks_and_refills_bank()
   local s = fresh(6)
   local before = s.players[1].bank[2]
   local placements = board.placements(6, before, 1, sim.blocked_set(s, {}))
   A.truthy(#placements > 0, "chunk fits")
   local shot: sim.Shot = {
      player = 1, wall = 1, slot = 2,
      cells = board.translate(before, placements[1]),
   }
   sim.fire(s, { shot })
   A.eq(#s.chunks, 1, "one chunk on board")
   A.eq(s.chunks[1].owner, 1, "owned by Player 1")
   A.eq(s.chunks[1].target, 3, "turn A from wall 1 heads for wall 3")
   local st = board.step(1, "A")
   A.eq(st.a, -2, "Player 1 steps northwest on turn A")
   A.eq(st.b, -1, "Player 1 steps northwest on turn A")
   A.eq(s.chunks[1].step.a, st.a, "step a")
   A.eq(s.chunks[1].step.b, st.b, "step b")
   A.truthy(s.players[1].bank[2] ~= before, "slot refilled")
   A.eq(#s.players[1].bank, 3, "bank still three")
end

function T.fire_clears_same_colour_neighbours_immediately()
   local s = fresh(5)
   local a: sim.Shot = { player = 2, wall = 3, slot = nil, cells = { cell(0, 0, "red") } }
   local b: sim.Shot = { player = 2, wall = 3, slot = nil, cells = { cell(1, 1, "red") } }
   local cleared = sim.fire(s, { a, b })
   A.eq(#cleared, 2, "both cleared")
   A.eq(#s.chunks, 0, "nothing left")
end

function T.split_into_components_after_clear()
   local s = fresh(6)
   -- Standing pair to provide a static red cell R at (2,3) (up cell).
   local R = cell(2, 3, "red")
   local Rd = cell(R.a + LEFT.a, R.b + LEFT.b, "green")
   sim.add_chunk(s, 1, LEFT, 2, { R })
   sim.add_chunk(s, 2, RIGHT, 5, { Rd })
   -- A chunk fired adjacent to R with a red cell in the middle of a chain:
   -- R's neighbours: (3,3), (2,4), (1,2). Use (2,4) [down: 6%3=0] as the red
   -- middle; its neighbours: (1,4), (2,3)=R, (3,5). Chain (1,4)-(2,4)-(3,5).
   local shot: sim.Shot = { player = 3, wall = 5, slot = nil,
      cells = { cell(1, 4, "green"), cell(2, 4, "red"), cell(3, 5, "blue") } }
   for _, c in ipairs(shot.cells) do A.truthy(board.contains(6, c.a, c.b), "on board") end
   local cleared = sim.fire(s, { shot })
   A.eq(#cleared, 2, "R and the red middle clear")
   -- The remaining ends are disconnected: they must be separate chunks.
   local ends = 0
   for _, chunk in ipairs(s.chunks) do
      if chunk.owner == 3 then
         ends = ends + 1
         A.eq(#chunk.cells, 1, "each piece has one cell")
         A.eq(chunk.target, board.target_wall(3, 5, "A"), "pieces keep the target")
      end
   end
   A.eq(ends, 2, "two independent pieces")
end

function T.winner_detection()
   local s = fresh(3)
   A.eq(sim.winner(s), nil, "no winner at start")
   s.players[1].hp = 0
   s.players[2].hp = -3
   A.eq(sim.winner(s), 3, "last one standing wins")
   s.players[3].hp = 0
   A.eq(sim.winner(s), nil, "everyone down is not a win")
end

function T.end_turn_flips_sweep()
   local s = fresh(3)
   sim.end_turn(s)
   A.eq(s.turn, "B", "A -> B")
   A.eq(s.round, 2, "round advances")
   sim.end_turn(s)
   A.eq(s.turn, "A", "B -> A")
end

function T.empty_board_tick_moves_nothing()
   local s = fresh(3)
   local r = sim.tick(s)
   A.eq(r.moved, 0, "nothing to move")
end

return T
