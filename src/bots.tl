--- Random bots. A bot tries its chunks and rotations in random order and a
--- few random spots for each, trying all three headings at every spot. It
--- takes the first shot whose ghost lands clear. Failing that it takes one that
--- lands in its own home, and fires on itself only when nothing else fits.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")

local record bots
end

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

--- Player `p`'s shot, or nil when nothing in their bank fits anywhere.
function bots.choose(state: sim.State, p: integer): sim.Shot
   local B, rng = state.board, state.rng
   local bank = state.players[p].bank
   local options: {Option} = {}
   for slot = 1, #bank do
      for turn = 0, 5 do options[#options + 1] = { slot = slot, turn = turn } end
   end
   shuffle(options, rng)

   local best: sim.Shot = nil
   local best_rank = 0
   for _, opt in ipairs(options) do
      local shape = board.shape(B, bc.rotate(bank[opt.slot], opt.turn))
      local spots = sim.placements(state, p, shape)
      for _ = 1, math.min(TRIES, #spots) do
         local spot = spots[math.floor(rng() * #spots) + 1]
         local cells = board.place(B, shape, spot.x, spot.y)
         local headings: {integer} = {}
         for k, h in ipairs(board.HEADINGS[p]) do headings[k] = h end
         shuffle(headings, rng)
         for _, h in ipairs(headings) do
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

--- Every live bot's shot for this shot clock, leaving out players in `skip`
--- (e.g. a human). Bots with nothing that fits have no shot.
function bots.plan(state: sim.State, skip?: {integer: boolean}): {sim.Shot}
   local shots: {sim.Shot} = {}
   for p, pl in ipairs(state.players) do
      if pl.alive and not (skip and skip[p]) then
         local shot = bots.choose(state, p)
         if shot then shots[#shots + 1] = shot end
      end
   end
   return shots
end

--- `shots` again at lock-in: chunks have moved since they were planned, so a
--- bot whose aim no longer fits (or who had none) chooses afresh.
function bots.refresh(state: sim.State, shots: {sim.Shot}, skip?: {integer: boolean}): {sim.Shot}
   local mine: {integer: sim.Shot} = {}
   for _, shot in ipairs(shots) do mine[shot.player] = shot end
   local out: {sim.Shot} = {}
   for p, pl in ipairs(state.players) do
      if pl.alive and not (skip and skip[p]) then
         local shot = mine[p]
         if not (shot and sim.legal(state, p, shot.cells)) then shot = bots.choose(state, p) end
         if shot then out[#out + 1] = shot end
      end
   end
   return out
end

return bots
