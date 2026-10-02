--- The bots, each with a brain:
---
---   * random: tries its chunks and rotations in random order and a few
---     random spots for each, trying all three headings at every spot. It
---     takes the first shot whose ghost lands clear. Failing that it takes one
---     that lands in its own home.
---   * greedyclear: tries every chunk, rotation, spot and heading, and takes
---     the shot whose ghost clears the most triangles at rest in its own home;
---     between those, the one that clears the most triangles in all; then one
---     that lands clear over one that lands in its home. Ties go at random.
---
--- Neither fires on itself (a ghost that looks "friendly") unless nothing
--- else fits.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")

local record bots
   enum Brain
      "random"
      "greedyclear"
   end

   BRAINS: {Brain}
end

local type Brain = bots.Brain

bots.BRAINS = { "random", "greedyclear" }

local record Option
   slot: integer
   turn: integer
end

--- Random spots tried per chunk and rotation.
local TRIES <const> = 4

local RANK <const>: {sim.Look: integer} = { clear = 3, home = 2, friendly = 1 }

local function shuffle<T>(list: {T}, rng: function(): number)
   for i = #list, 2, -1 do
      local j = math.floor(rng() * i) + 1
      list[i], list[j] = list[j], list[i]
   end
end

--- Player `p`'s headings in random order.
local function headings(p: integer, rng: function(): number): {integer}
   local hs: {integer} = {}
   for k, h in ipairs(board.HEADINGS[p]) do hs[k] = h end
   shuffle(hs, rng)
   return hs
end

--- Every bank slot and rotation for player `p`, in random order.
local function options(state: sim.State, p: integer): {Option}
   local out: {Option} = {}
   for slot = 1, #state.players[p].bank do
      for turn = 0, 5 do out[#out + 1] = { slot = slot, turn = turn } end
   end
   shuffle(out, state.think)
   return out
end

local function random_shot(state: sim.State, p: integer): sim.Shot
   local B, rng = state.board, state.think
   local bank = state.players[p].bank
   local best: sim.Shot = nil
   local best_rank = 0
   for _, opt in ipairs(options(state, p)) do
      local shape = board.shape(B, bc.rotate(bank[opt.slot], opt.turn))
      local spots = sim.placements(state, p, shape)
      for _ = 1, math.min(TRIES, #spots) do
         local spot = spots[math.floor(rng() * #spots) + 1]
         local cells = board.place(B, shape, spot.x, spot.y)
         for _, h in ipairs(headings(p, rng)) do
            local rank = RANK[sim.ghost(state, p, cells, h).look]
            if rank > best_rank then
               best, best_rank = { player = p, slot = opt.slot, heading = h, cells = cells }, rank
               if rank == RANK.clear then return best end
            end
         end
      end
   end
   return best
end

--- How good a ghost is to greedyclear, as keys compared in turn: not firing
--- on itself, triangles at rest cleared from its home, triangles cleared in
--- all, and where it lands.
local function greed(state: sim.State, p: integer, g: sim.Ghost): {integer}
   local kind = state.board.kind
   local home = 0
   for _, t in ipairs(g.cleared) do
      if kind[t.i] == p then home = home + 1 end
   end
   return { g.look == "friendly" and 0 or 1, home, #g.hits + #g.cleared, RANK[g.look] }
end

local function better(x: {integer}, y: {integer}): boolean
   for k = 1, #x do
      if x[k] ~= y[k] then return x[k] > y[k] end
   end
   return false
end

local function greedy_shot(state: sim.State, p: integer): sim.Shot
   local B, rng = state.board, state.think
   local bank = state.players[p].bank
   local best: sim.Shot = nil
   local best_score: {integer} = nil
   for _, opt in ipairs(options(state, p)) do
      local shape = board.shape(B, bc.rotate(bank[opt.slot], opt.turn))
      local spots = sim.placements(state, p, shape)
      shuffle(spots, rng)
      for _, spot in ipairs(spots) do
         local cells = board.place(B, shape, spot.x, spot.y)
         for _, h in ipairs(headings(p, rng)) do
            local score = greed(state, p, sim.ghost(state, p, cells, h))
            if not best_score or better(score, best_score) then
               best, best_score = { player = p, slot = opt.slot, heading = h, cells = cells }, score
            end
         end
      end
   end
   return best
end

--- Player `p`'s shot as `brain` (random if left out) would choose it, or nil
--- when nothing in their bank fits anywhere.
function bots.choose(state: sim.State, p: integer, brain?: Brain): sim.Shot
   if brain == "greedyclear" then return greedy_shot(state, p) end
   return random_shot(state, p)
end

--- Every live bot's shot, by player, leaving out players in `skip` (e.g. a
--- human), each with its brain in `brains` (random if left out). Bots with
--- nothing that fits have no shot.
function bots.plan(state: sim.State, skip?: {integer: boolean}, brains?: {integer: Brain}): {integer: sim.Shot}
   local shots: {integer: sim.Shot} = {}
   for p, pl in ipairs(state.players) do
      if pl.alive and not (skip and skip[p]) then shots[p] = bots.choose(state, p, brains and brains[p]) end
   end
   return shots
end

--- Bot `p`'s planned `shot` again as their shot clock runs out: chunks have
--- moved since it was planned, so if it no longer fits (or there was none)
--- the bot chooses afresh with `brain`.
function bots.refresh(state: sim.State, p: integer, shot: sim.Shot, brain?: Brain): sim.Shot
   if shot and sim.legal(state, p, shot.cells) then return shot end
   return bots.choose(state, p, brain)
end

return bots
