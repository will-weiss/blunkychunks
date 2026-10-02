--- A match's timeline: the board's ticks and everyone's shot clocks, in
--- whole milliseconds, played out in one fixed order whatever the frame rate.
--- sim.tl has the rules; this decides when they happen.
---
---   * Ticks fall every `step` ms, the first one `step` ms in.
---   * Each player's shot clock runs out every `period` ms, staggered a third
---     of a clock apart: Player 1's first runs out at `period`, Player 2's a
---     third of one later, Player 3's two thirds later (rounded down to the
---     ms). An out player's clock stops.
---   * A shot clock running out at the same ms as a tick goes first; two
---     running out at once go lowest player first.
---
--- When a clock runs out, the match asks `decide` for that player's shot. In
--- a local match that's the seat's aim; in a networked one it's whatever the
--- server announced, and `decide` can say it hasn't heard yet, which stops the
--- match there until it has. Given the same shots, two matches play out the
--- same, so a networked player only ever needs to be sent the shots.

local board = require("board")
local sim = require("sim")

local record match
   record Match
      state: sim.State
      period: integer -- ms per shot clock
      step: integer -- ms per tick
      now: integer -- ms: everything up to here has happened
      deadline: {integer} -- per player: the ms their shot clock runs out
      next_tick: integer -- the ms of the next tick
      last_tick: integer -- the ms of the last one (0 before the first)
      ticks: integer -- ticks so far
      shots: {integer} -- per player: how many of their shot clocks have run out
   end

   --- What the match asks and tells its caller as it plays out.
   record Hooks
      --- Player `p`'s `k`th shot clock ran out: their shot (nil for none).
      --- Return false to stop the match here until it is known.
      decide: function(p: integer, k: integer): boolean, sim.Shot
      locked: function(p: integer, r: sim.LockResult)
      ticked: function(r: sim.TickResult)
   end
end

local type Match = match.Match
local type Hooks = match.Hooks

--- A match on `state` with a `period` ms shot clock and a tick every `step` ms.
function match.new(state: sim.State, period: integer, step: integer): Match
   local n = #board.PLAYERS
   local deadline: {integer} = {}
   local shots: {integer} = {}
   for p = 1, n do
      deadline[p] = period + period * (p - 1) // n
      shots[p] = 0
   end
   return {
      state = state,
      period = period,
      step = step,
      now = 0,
      deadline = deadline,
      next_tick = step,
      last_tick = 0,
      ticks = 0,
      shots = shots,
   }
end

--- The live player whose shot clock runs out next (lowest first on a tie),
--- or nil if nobody is in.
function match.soonest(m: Match): integer
   local best: integer
   for p, pl in ipairs(m.state.players) do
      if pl.alive and (not best or m.deadline[p] < m.deadline[best]) then best = p end
   end
   return best
end

--- When the next thing happens, and which player's clock it is (nil for a
--- tick). A clock moved into the past by `skip` runs out now.
local function next_event(m: Match): integer, integer
   local p = match.soonest(m)
   if p and m.deadline[p] <= m.next_tick then return math.max(m.deadline[p], m.now), p end
   return m.next_tick, nil
end

--- Play the match out to `to` ms. Returns false if it stopped short because
--- `decide` didn't know a shot yet (`now` is then as far as it got), true
--- once it is at `to` or the match is over.
function match.advance(m: Match, to: integer, hooks: Hooks): boolean
   local state = m.state
   while not sim.over(state) do
      local t, p = next_event(m)
      if t > to then break end
      if p then
         local known, shot = hooks.decide(p, m.shots[p] + 1)
         if not known then
            m.now = math.max(m.now, t - 1)
            return false
         end
         local r = sim.lock_in(state, p, shot)
         m.shots[p] = m.shots[p] + 1
         repeat m.deadline[p] = m.deadline[p] + m.period until m.deadline[p] > t
         m.now = t
         if hooks.locked then hooks.locked(p, r) end
      else
         local r = sim.tick(state)
         m.ticks = m.ticks + 1
         m.last_tick = t
         m.next_tick = t + m.step
         m.now = t
         if hooks.ticked then hooks.ticked(r) end
      end
   end
   m.now = math.max(m.now, to)
   return true
end

--- Fire now: every live clock skips ahead by however long player `p`'s has
--- left (if `p` is nil or out, the soonest one's), keeping the stagger, so
--- `p`'s runs out now and any due before it run out first. The clocks that
--- ran out go off on the next `advance`, which can be to `now`.
function match.skip(m: Match, p?: integer)
   if not (p and m.state.players[p].alive) then p = match.soonest(m) end
   if not p then return end
   local by = m.deadline[p] - m.now
   if by <= 0 then return end
   for q, pl in ipairs(m.state.players) do
      if pl.alive then m.deadline[q] = m.deadline[q] - by end
   end
end

--- Tick every `step` ms from now on, the next one `step` after the last.
function match.set_step(m: Match, step: integer)
   m.next_tick = math.max(m.now, m.last_tick + step)
   m.step = step
end

--- The ms player `p`'s shot clock has left at `t`.
function match.left(m: Match, p: integer, t: number): number
   return math.max(0, m.deadline[p] - t)
end

return match
