local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local match = require("match")
local controls = require("controls")
local A = require("tests.assert")

local record T
end

local function fresh(period?: integer, step?: integer): match.Match
   return match.new(sim.new(board.new(6, 5), 6, bc.seeded_random(3)), period or 9000, step or 1000)
end

--- Hooks that fire each player's default aim and note what happened, as
--- "p" or "t".
local function quiet(m: match.Match, log: {string}): match.Hooks
   return {
      decide = function(p: integer): boolean, sim.Shot
         return true, sim.settle(m.state, p, { slot = 1, turn = 0, prefer = 2 }).shot
      end,
      locked = function(p: integer) log[#log + 1] = tostring(p) end,
      ticked = function() log[#log + 1] = "t" end,
   }
end

function T.shot_clocks_are_staggered_a_third_apart()
   local m = fresh(8000)
   A.eq(m.deadline[1], 8000, "Player 1 gets a full clock")
   A.eq(m.deadline[2], 10666, "Player 2 a third of one more, to the ms")
   A.eq(m.deadline[3], 13333, "Player 3 two thirds more")
end

function T.clocks_run_out_in_turn_and_start_again()
   -- Nobody fires, so each is out the moment their clock runs out: give
   -- them a shot that's never legal, and watch the order instead.
   local m = fresh(9000, 100000)
   local order: {integer} = {}
   local hooks: match.Hooks = {
      decide = function(p: integer): boolean, sim.Shot
         order[#order + 1] = p
         return true, sim.settle(m.state, p, { slot = 1, turn = 0, prefer = 2 }).shot
      end,
   }
   match.advance(m, 9000 + 9000 + 6000, hooks)
   A.eq(table.concat(order, ","), "1,2,3,1,2,3", "one at a time, in turn")
   A.eq(m.deadline[1], 27000, "each starts again from when it ran out")
   A.eq(m.shots[2], 2, "two shot clocks each")
end

function T.a_shot_clock_goes_before_a_tick_at_the_same_ms()
   local log: {string} = {}
   local m = fresh(3000, 1000)
   match.advance(m, 3000, quiet(m, log))
   A.eq(table.concat(log, ""), "tt1t", "two ticks, Player 1's clock, then the tick at 3 s")
end

function T.skip_brings_a_clock_to_now_and_fires_those_before_it()
   local m = fresh(9000, 100000)
   local log: {string} = {}
   local hooks = quiet(m, log)
   match.advance(m, 1000, hooks)
   match.skip(m, 3)
   A.eq(m.deadline[3], 1000, "Player 3's runs out now")
   A.eq(m.deadline[1], 9000 - 14000, "the others keep the stagger")
   A.eq(m.deadline[2], 12000 - 14000, "all of them")
   match.advance(m, m.now, hooks)
   A.eq(table.concat(log, ""), "123", "earliest first")
end

function T.an_out_players_clock_stops()
   local m = fresh(9000, 100000)
   m.state.players[1].alive = false
   local log: {string} = {}
   match.advance(m, 20000, quiet(m, log))
   A.eq(table.concat(log, ""), "23", "only the others ran out")
   A.eq(m.deadline[1], 9000, "Player 1's clock stopped")
end

function T.an_unknown_shot_stops_the_match_until_it_is_known()
   local m = fresh(3000, 1000)
   local known = false
   local log: {string} = {}
   local hooks = quiet(m, log)
   local fire = hooks.decide
   hooks.decide = function(p: integer, k: integer): boolean, sim.Shot
      if not known then return false, nil end
      return fire(p, k)
   end
   A.eq(match.advance(m, 5000, hooks), false, "stopped short")
   A.eq(table.concat(log, ""), "tt", "at Player 1's clock")
   A.truthy(m.now < 3000, "before it")
   known = true
   A.eq(match.advance(m, 5000, hooks), true, "and on once it's known")
   A.eq(table.concat(log, ""), "tt1t2t3t", "as if it had never stopped")
end

function T.set_step_changes_the_ticks_from_the_last_one()
   local m = fresh(100000, 1000)
   local log: {string} = {}
   match.advance(m, 2500, quiet(m, log))
   match.set_step(m, 300)
   A.eq(m.next_tick, 2500, "the last tick was at 2 s, so the next is due now")
   match.set_step(m, 2000)
   A.eq(m.next_tick, 4000, "and a slower one waits from the last")
end

--- A whole match between bots, its shots logged, advancing by `frames` ms a
--- frame in turn. Returns its hash and the log.
local function bot_match(seed: integer, frames: {integer}): integer, {integer: {sim.Shot}}
   local state = sim.new(board.new(6, 5), 6, bc.seeded_random(seed), bc.seeded_random(seed + 1))
   local m = match.new(state, 3000, 280)
   local seats: {controls.Seat} = {}
   for p = 1, 3 do seats[p] = controls.bot(state, p) end
   local log: {integer: {sim.Shot}} = { {}, {}, {} }
   local hooks: match.Hooks = {
      decide = function(p: integer, k: integer): boolean, sim.Shot
         local shot = controls.shot(state, seats[p])
         log[p][k] = shot or false as sim.Shot
         return true, shot
      end,
      locked = function(p: integer, r: sim.LockResult) controls.fired(state, seats[p], r) end,
   }
   local t, f = 0, 0
   while not sim.over(state) and t < 400000 do
      f = f % #frames + 1
      t = t + frames[f]
      match.advance(m, t, hooks)
   end
   return sim.hash(state), log
end

function T.the_frame_rate_never_changes_a_match()
   local h1 = bot_match(5, { 16 })
   local h2 = bot_match(5, { 7, 33, 1, 250 })
   local h3 = bot_match(5, { 1000 })
   A.eq(h2, h1, "uneven frames")
   A.eq(h3, h1, "one a second")
end

function T.replaying_the_shots_replays_the_match()
   local want, log = bot_match(8, { 16 })
   local state = sim.new(board.new(6, 5), 6, bc.seeded_random(8))
   local m = match.new(state, 3000, 280)
   local hooks: match.Hooks = {
      decide = function(p: integer, k: integer): boolean, sim.Shot
         local shot = log[p][k]
         return true, shot or nil
      end,
   }
   match.advance(m, 400000, hooks)
   A.eq(sim.hash(state), want, "the same hash, without a bot in sight")
end

return T
