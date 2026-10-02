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
   A.eq(#shots, 1, "one bot left to plan")
   A.eq(shots[1].player, 3, "Player 3")
end

function T.refresh_keeps_legal_aims_and_replaces_stale_ones()
   local s = fresh()
   local shots = bots.plan(s)
   A.eq(#shots, 3, "three plans")
   local keep, stale = shots[1], shots[3]
   sim.add_chunk(s, 3, board.HEADINGS[3][2], { { i = stale.cells[1].i, color = "red" } })
   local again = bots.refresh(s, shots)
   A.eq(#again, 3, "still three")
   A.eq(again[1], keep, "the legal aim is kept as it was")
   A.truthy(again[3] ~= stale, "the stale aim is replaced")
   A.truthy(sim.legal(s, 3, again[3].cells), "by a legal one")
end

--- On a board whose homes are smaller than a chunk nothing ever fits, so the
--- first shot clock knocks everyone out together: a draw, not a crash.
function T.a_home_too_small_for_any_chunk_ends_in_a_draw()
   local s = sim.new(board.new(1, 1), 14, bc.seeded_random(1))
   A.eq(#s.board.homes[1], 4, "four triangles per home")
   A.eq(#bots.plan(s), 0, "no bot finds a shot")
   local r = sim.lock_in(s, bots.refresh(s, {}))
   A.eq(#r.out, 3, "all out at once")
   A.truthy(sim.over(s), "over")
   A.eq(sim.winner(s), nil, "a draw")
end

return T
