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

--- X heading east and Y heading west both want to land on i + 2.
function T.the_first_fired_takes_a_contested_step()
   local s = fresh()
   local i = lane(s, E, 2)
   local x = sim.add_chunk(s, 1, E, { tri(i, "red") })
   local y = sim.add_chunk(s, 2, W, { tri(i + 4, "green") })
   A.eq(sim.tick(s).moved, 1, "only one moved")
   A.eq(s.occ[i + 2], x.id, "X, fired first, stepped in")
   A.eq(s.occ[i + 4], y.id, "Y waited")
end

function T.fire_order_decides_a_contest_not_list_order()
   local s = fresh()
   local i = lane(s, E, 2)
   local x = sim.add_chunk(s, 1, E, { tri(i, "red") })
   local y = sim.add_chunk(s, 2, W, { tri(i + 4, "green") })
   x.fired = y.fired + 1
   A.eq(sim.tick(s).moved, 1, "only one moved")
   A.eq(s.occ[i + 2], y.id, "Y, fired first, stepped in")
   A.eq(s.occ[i], x.id, "X waited")
end

--- X would win i + 2 from Y, but X is stuck head-on against Z, so Y goes.
function T.a_first_fired_chunk_that_cannot_move_does_not_hold_up_the_other()
   local s = fresh()
   local i = lane(s, E, 2)
   local x = sim.add_chunk(s, 1, E, { tri(i, "red") })
   local z = sim.add_chunk(s, 3, W, { tri(i + 1, "green") })
   local y = sim.add_chunk(s, 2, W, { tri(i + 4, "blue") })
   A.eq(sim.tick(s).moved, 1, "only Y moved")
   A.eq(s.occ[i], x.id, "X stuck")
   A.eq(s.occ[i + 1], z.id, "Z stuck")
   A.eq(s.occ[i + 2], y.id, "Y stepped in")
end

--- C, fired last, contests i + 4 with Y; but A, fired first, is right behind
--- C going the same way, and a convoy goes with its earliest chunk.
function T.a_convoy_contests_as_its_earliest_chunk()
   local s = fresh()
   local i = lane(s, E, 3)
   local a = sim.add_chunk(s, 1, E, { tri(i, "red") })
   local y = sim.add_chunk(s, 2, W, { tri(i + 6, "green") })
   local c = sim.add_chunk(s, 1, E, { tri(i + 2, "blue") })
   A.eq(sim.tick(s).moved, 2, "the convoy moved")
   A.eq(s.occ[i + 2], a.id, "A stepped on")
   A.eq(s.occ[i + 4], c.id, "C stepped into the contested cell")
   A.eq(s.occ[i + 6], y.id, "Y waited")
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
   local fired = s.next_id
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
         A.eq(chunk.fired, fired, "and when it was fired")
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
   local last = g.cells[1].i
   A.truthy(last ~= i, "it travelled")
   A.eq(g.cells[1].color, "red", "keeps its colour")
   local blocker = sim.add_chunk(s, 1, E, { tri(last, "green") })
   blocker.flying = false
   A.eq(sim.ghost(s, 3, shot, h).cells[1].i, last - B.step[h], "stops one step short of a chunk at rest")
   blocker.flying = true
   A.eq(sim.ghost(s, 3, shot, h).cells[1].i, last, "looks straight through a chunk in flight")
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
   A.eq(g.cells[1].i, i, "can't move at all")
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

--- Stopped edge to edge against a triangle at rest: a different colour just
--- stops it, the same colour is a hit and both clear.
function T.the_ghost_hits_a_same_coloured_triangle_where_it_lands()
   local s = fresh()
   local B = s.board
   local h = board.HEADINGS[3][2]
   local i = find(s, function(i: integer): boolean return kind(s, i) == 3 end)
   local last = sim.ghost(s, 3, { tri(i, "red") }, h).cells[1].i
   local short = last - B.step[h]
   local rest = sim.add_chunk(s, 1, E, { tri(pass(s, short, h), "green") })
   rest.flying = false
   local g = sim.ghost(s, 3, { tri(i, "red") }, h)
   A.eq(g.cells[1].i, short, "a green at rest stops it a step short")
   A.eq(#g.hits, 0, "red against green is no hit")
   rest.cells[1].color, s.paint[rest.cells[1].i] = "red", bc.CODE.red
   g = sim.ghost(s, 3, { tri(i, "red") }, h)
   A.eq(#g.hits, 1, "red against red is a hit")
   A.eq(g.hits[1].i, short, "where it meets the red at rest")
   A.eq(g.hits[1].color, "red", "the hit keeps its colour")
   A.eq(#g.cells, 0, "nothing left to come to rest")
   A.eq(g.look, "clear", "so nothing lands in your home")
end

--- Clears happen after every tick, not just where the shot stops: a
--- same-coloured triangle at rest beside the path takes out the triangle that
--- passes it, and the rest of the shot slides on without it.
function T.the_ghost_clears_on_the_way_and_the_rest_slides_on()
   local s = fresh()
   local B = s.board
   local h = board.HEADINGS[3][2] -- W, straight across
   local below = B.near[1][3] -- a point-up triangle's neighbour in the row below
   -- A point-up red and point-down green side by side in Player 3's home,
   -- and a cell x on the red's way across with a middle triangle below it.
   local x: integer = nil
   local i = find(s, function(i: integer): boolean
      if i % 2 ~= 0 or kind(s, i) ~= 3 or kind(s, i + 1) ~= 3 then return false end
      local alone = sim.ghost(s, 3, { tri(i, "red") }, h).cells[1].i
      local j = i
      while j ~= alone do
         j = j + B.step[h]
         if kind(s, j + below) == MIDDLE then
            x = j
            return true
         end
      end
      return false
   end)
   local green = sim.ghost(s, 3, { tri(i + 1, "green") }, h).cells[1].i
   sim.add_chunk(s, 1, E, { tri(x + below, "red") }).flying = false
   local g = sim.ghost(s, 3, { tri(i, "red"), tri(i + 1, "green") }, h)
   A.eq(#g.hits, 1, "one hit")
   A.eq(g.hits[1].i, x, "the red clears where it passes the red at rest")
   A.eq(#g.cells, 1, "the green carries on")
   A.eq(g.cells[1].i, green, "and lands where it would alone")
   A.eq(g.cells[1].color, "green", "still green")
end

--- A hit that cuts the shot in two leaves pieces that slide on their own: one
--- is stopped by a triangle at rest while the other carries on past it.
function T.the_ghost_splits_into_pieces_that_slide_on_their_own()
   local s = sim.new(board.new(6, 3), 4, bc.seeded_random(1))
   local B = s.board
   local w = B.w
   -- Point-up A, point-down M below it and point-up Z beside M: a chain cut
   -- in two when M meets the green R at rest behind it as the shot is fired.
   local x = find(s, function(x: integer): boolean
      if x % 2 ~= 0 then return false end
      for _, j in ipairs({ x, x - 1, x - 2, x - 3, x - 4, x - w, x - w - 1, x - w - 2 }) do
         if kind(s, j) ~= MIDDLE then return false end
      end
      for j = x - w - 3, x - w - 6, -1 do -- room for Z to get past A
         if kind(s, j) ~= MIDDLE then return false end
      end
      return true
   end)
   local a, m, z = x, x - w - 1, x - w - 2
   sim.add_chunk(s, 1, E, { tri(x - w, "green") }).flying = false
   sim.add_chunk(s, 1, E, { tri(x - 4, "red") }).flying = false -- in A's way
   local z_alone = sim.ghost(s, 3, { tri(z, "blue") }, W).cells[1].i
   A.truthy((z - z_alone) // 2 > 1, "Z alone gets further than A can")
   local g = sim.ghost(s, 3, { tri(a, "red"), tri(m, "green"), tri(z, "blue") }, W)
   A.eq(#g.hits, 1, "M is hit")
   A.eq(g.hits[1].i, m, "as the shot is fired")
   local at: {bc.Color: integer} = {}
   for _, t in ipairs(g.cells) do at[t.color] = t.i end
   A.eq(at.red, x - 2, "A stops a step short of the red at rest")
   A.eq(at.blue, z_alone, "Z slides on as if alone")
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
                  local k = kind(s, g.cells[1].i)
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

function T.lock_in_fires_only_that_players_aim()
   local s = fresh()
   local shot = aim(s, 1)
   local before = s.players[1].bank[1]
   local r = sim.lock_in(s, 1, shot)
   A.eq(r.fired, shot, "Player 1's shot fired")
   A.truthy(not r.out, "not out")
   A.eq(#s.chunks, 1, "one chunk on the board")
   A.truthy(s.players[1].bank[1] ~= before, "its slot refilled")
   A.eq(sim.alive(s), 3, "everyone still in")
end

function T.lock_in_knocks_out_a_player_without_a_legal_aim()
   local s = fresh()
   local r = sim.lock_in(s, 2, nil)
   A.truthy(r.out and not r.fired, "Player 2 had no aim")
   local bad = aim(s, 3)
   bad.cells = { tri(find(s, function(i: integer): boolean return kind(s, i) == MIDDLE end), "red") }
   A.truthy(sim.lock_in(s, 3, bad).out, "Player 3's aim was illegal")
   A.eq(#s.chunks, 0, "nothing fired")
   A.eq(s.players[2].out, "stuck", "stuck")
   A.eq(s.players[3].out, "stuck", "stuck")
   A.eq(sim.winner(s), 1, "last one standing")
   A.truthy(sim.over(s), "match over")
end

function T.lock_in_refuses_a_heading_that_is_not_yours()
   local s = fresh()
   local shot = aim(s, 1)
   shot.heading = board.HEADINGS[3][1] -- SW belongs to Player 3 (and 2), not 1
   A.truthy(sim.lock_in(s, 1, shot).out, "Player 1 out")
end

function T.lock_in_leaves_players_who_are_already_out_alone()
   local s = fresh()
   s.players[2].alive, s.players[2].out = false, "friendly"
   local r = sim.lock_in(s, 2, aim(s, 2))
   A.truthy(not r.out and not r.fired, "nothing fired, nobody newly out")
   A.eq(#s.chunks, 0, "nothing on the board")
   A.eq(s.players[2].out, "friendly", "still out the way they went out")
end

--- A cell of player `p`'s home and a heading that steps it straight into the wall.
local function doomed(s: State, p: integer): integer, integer
   for h = 1, 6 do
      for _, i in ipairs(s.board.homes[p]) do
         if kind(s, step(s, i, h)) == WALL then return i, h end
      end
   end
   error("no cell next to the wall")
end

function T.last_one_standing_wins_and_all_out_at_once_is_a_draw()
   local s = fresh()
   A.eq(sim.winner(s), nil, "no winner at the start")
   s.players[1].alive = false
   A.eq(sim.winner(s), nil, "two left")
   A.truthy(not sim.over(s), "still playing")
   for p = 2, 3 do
      local i, h = doomed(s, p)
      sim.add_chunk(s, p, h, { tri(i, p == 2 and "green" or "blue") })
   end
   A.eq(#sim.tick(s).out, 2, "both hit their back walls together")
   A.truthy(sim.over(s), "over")
   A.eq(sim.winner(s), nil, "a draw")
end

function T.shot_clocks_are_staggered_and_run_out_in_turn()
   local s = fresh()
   local c = sim.clocks(9)
   A.eq(c[1], 9, "Player 1 gets a full clock")
   A.eq(c[2], 12, "Player 2 a third of one more")
   A.eq(c[3], 15, "Player 3 two thirds more")
   for round = 1, 2 do
      for p = 1, 3 do
         local due = sim.run_down(s, c, round == 1 and p == 1 and 9 or 3, 9)
         A.eq(#due, 1, "one clock at a time")
         A.eq(due[1], p, "in turn")
         A.eq(c[p], 9, "and it starts again")
      end
   end
end

function T.a_jump_runs_out_every_clock_it_passes_earliest_first()
   local s = fresh()
   local c = { 6.0, 9.0, 3.0 }
   local due = sim.run_down(s, c, 7, 9)
   A.eq(#due, 2, "two ran out")
   A.eq(due[1], 3, "Player 3's first")
   A.eq(due[2], 1, "then Player 1's")
   A.eq(c[1], 8, "each starts again from when it ran out")
   A.eq(c[2], 2, "the other just runs down")
   A.eq(c[3], 5, "keeping the stagger")
end

function T.an_out_players_clock_stops()
   local s = fresh()
   s.players[1].alive = false
   local c = sim.clocks(9)
   A.eq(#sim.run_down(s, c, 10, 9), 0, "nobody else is due yet")
   A.eq(c[1], 9, "Player 1's clock didn't run")
   A.eq(c[2], 2, "Player 2's did")
end

function T.an_empty_board_tick_moves_nothing()
   local s = fresh()
   local r = sim.tick(s)
   A.eq(r.moved, 0, "nothing to move")
   A.eq(#r.cleared, 0, "nothing to clear")
end

return T
