--- Random bots. Each turn a bot picks a chunk from its bank, one of its two
--- legal walls, and a spot along that wall, all uniformly at random. If the
--- pick does not fit it tries its other chunk/wall combinations in random
--- order, and passes if nothing fits anywhere.

local board = require("board")
local sim = require("sim")

local record bots
end

local record Option
   slot: integer
   wall: integer
end

local function shuffle<T>(list: {T}, rng: function(): number)
   for i = #list, 2, -1 do
      local j = math.floor(rng() * i) + 1
      list[i], list[j] = list[j], list[i]
   end
end

--- One player's shot, or nil when no chunk in their bank fits.
function bots.choose(state: sim.State, p: integer, blocked: {string: boolean}): sim.Shot
   local player = state.players[p]
   local options: {Option} = {}
   for slot = 1, #player.bank do
      for _, wall in ipairs(board.launch_walls(p, state.turn)) do
         options[#options + 1] = { slot = slot, wall = wall }
      end
   end
   shuffle(options, state.rng)

   for _, opt in ipairs(options) do
      local chunk = player.bank[opt.slot]
      local spots = board.placements(state.n, chunk, opt.wall, blocked)
      if #spots > 0 then
         local t = spots[math.floor(state.rng() * #spots) + 1]
         return {
            player = p,
            wall = opt.wall,
            slot = opt.slot,
            cells = board.translate(chunk, t),
         }
      end
   end
   return nil
end

--- Every bot's shot for this turn. Bots place in random order and each sees
--- the earlier placements, so no two shots overlap.
function bots.plan(state: sim.State): {sim.Shot}
   local order: {integer} = {}
   for p = 1, #state.players do order[p] = p end
   shuffle(order, state.rng)

   local shots: {sim.Shot} = {}
   for _, p in ipairs(order) do
      local shot = bots.choose(state, p, sim.blocked_set(state, shots))
      if shot then shots[#shots + 1] = shot end
   end
   return shots
end

return bots
