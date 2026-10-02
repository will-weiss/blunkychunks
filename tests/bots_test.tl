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
