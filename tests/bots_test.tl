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
   A.eq(shots[1], nil, "not the human")
   A.eq(shots[2], nil, "not a player who is out")
   A.eq(shots[3].player, 3, "Player 3 planned")
end

function T.refresh_keeps_a_legal_aim_and_replaces_a_stale_one()
   local s = fresh()
   local shots = bots.plan(s)
   local keep, stale = shots[1], shots[3]
   sim.add_chunk(s, 3, board.HEADINGS[3][2], { { i = stale.cells[1].i, color = "red" } })
   A.eq(bots.refresh(s, 1, keep), keep, "the legal aim is kept as it was")
   local again = bots.refresh(s, 3, stale)
   A.truthy(again ~= stale, "the stale aim is replaced")
   A.truthy(sim.legal(s, 3, again.cells), "by a legal one")
   A.truthy(sim.legal(s, 2, bots.refresh(s, 2, nil).cells), "and a missing one chosen afresh")
end

--- Player 1's bank, every triangle `color`.
local function paint_bank(s: sim.State, color: bc.Color)
   for _, chunk in ipairs(s.players[1].bank) do
      for _, c in ipairs(chunk) do c.color = color end
   end
end

--- A triangle of `color` at rest at `i`.
local function rest(s: sim.State, owner: integer, i: integer, color: bc.Color)
   sim.add_chunk(s, owner, board.HEADINGS[owner][2], { { i = i, color = color } }).flying = false
end

--- How a ghost scores for greedyclear: at-rest triangles it clears from
--- Player p's home, and triangles it clears in all.
local function clears(s: sim.State, p: integer, g: sim.Ghost): integer, integer
   local home = 0
   for _, t in ipairs(g.cleared) do
      if s.board.kind[t.i] == p then home = home + 1 end
   end
   return home, #g.hits + #g.cleared
end

function T.greedyclear_clears_a_triangle_left_in_its_home()
   local s = fresh()
   paint_bank(s, "red")
   -- A red at rest on Player 1's dashed line, where every shot heads out.
   local B = s.board
   local i: integer = nil
   for _, j in ipairs(B.homes[1]) do
      for _, d in ipairs(B.near[board.facing(j)]) do
         if B.kind[j + d] == board.MIDDLE then i = j end
      end
      if i then break end
   end
   rest(s, 2, i, "red")
   local shot = bots.choose(s, 1, "greedyclear")
   A.truthy(sim.legal(s, 1, shot.cells), "legal")
   local home = clears(s, 1, sim.ghost(s, 1, shot.cells, shot.heading))
   A.truthy(home >= 1, "clears the red from its home")
end

function T.greedyclear_clears_what_it_can_elsewhere_when_its_home_is_empty()
   local s = fresh()
   paint_bank(s, "red")
   local B = s.board
   local mid: {integer} = {}
   for _, j in ipairs(B.cells) do
      if B.kind[j] == board.MIDDLE then mid[#mid + 1] = j end
   end
   rest(s, 2, mid[math.floor(#mid / 2)], "red")
   local shot = bots.choose(s, 1, "greedyclear")
   local _, all = clears(s, 1, sim.ghost(s, 1, shot.cells, shot.heading))
   A.truthy(all >= 2, "clears the red in the middle, and itself with it")
end

--- On a busy board, frozen at rest so the ghosts see everything, no legal
--- shot beats greedyclear's: none clears more from its home, and of those
--- that clear as much none clears more in all.
function T.greedyclear_takes_the_best_shot_there_is()
   local s = fresh()
   for _ = 1, 4 do
      for p = 1, 3 do sim.lock_in(s, p, bots.choose(s, p)) end
      for _ = 1, 6 do sim.tick(s) end
   end
   for _, chunk in ipairs(s.chunks) do chunk.flying = false end
   for p = 1, 3 do
      if s.players[p].alive then
         local shot = bots.choose(s, p, "greedyclear")
         local home, all = clears(s, p, sim.ghost(s, p, shot.cells, shot.heading))
         for _, chunk in ipairs(s.players[p].bank) do
            for turn = 0, 5 do
               local shape = board.shape(s.board, bc.rotate(chunk, turn))
               for _, spot in ipairs(sim.placements(s, p, shape)) do
                  local cells = board.place(s.board, shape, spot.x, spot.y)
                  for _, h in ipairs(board.HEADINGS[p]) do
                     local g = sim.ghost(s, p, cells, h)
                     if g.look ~= "friendly" then
                        local h2, a2 = clears(s, p, g)
                        A.truthy(h2 < home or (h2 == home and a2 <= all),
                           ("Player %d: %d/%d beats greedyclear's %d/%d"):format(p, h2, a2, home, all))
                     end
                  end
               end
            end
         end
      end
   end
end

--- On a board whose homes are smaller than a chunk nothing ever fits, so the
--- players go out in turn as their clocks run out, and the last one's left
--- standing: no crash.
function T.a_home_too_small_for_any_chunk_leaves_the_last_clock_standing()
   local s = sim.new(board.new(1, 1), 14, bc.seeded_random(1))
   A.eq(#s.board.homes[1], 4, "four triangles per home")
   A.eq(next(bots.plan(s)), nil, "no bot finds a shot")
   A.truthy(sim.lock_in(s, 1, bots.refresh(s, 1, nil)).out, "Player 1 out first")
   A.truthy(sim.lock_in(s, 2, bots.refresh(s, 2, nil)).out, "then Player 2")
   A.truthy(sim.over(s), "over")
   A.eq(sim.winner(s), 3, "Player 3 left standing")
end

return T
