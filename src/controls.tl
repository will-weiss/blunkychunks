--- Who is playing each home: the keyboard, a gamepad or a bot. Each player
--- has a `Seat`, and the game only talks to seats: it tells them the board
--- moved (`update`), asks for their shot when their clock runs out (`shot`),
--- tells them what fired (`fired`) and hands them input as `Action`s (`act`).
--- What a seat aims, and how, is up to it; bots.tl does the bots' thinking.
---
--- Nothing here touches LOVE beyond holding on to a seat's joystick, so it
--- runs (and is tested) under plain Lua.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local bots = require("bots")

local record controls
   enum Kind
      "keys"
      "pad"
      "bot"
   end

   --- Everything a human can ask of their seat, whatever they hold.
   enum Action
      "slot1"
      "slot2"
      "slot3"
      "turn_ccw"
      "turn_cw"
      "left"
      "right"
      "heading_next"
      "heading_prev"
      "fire"
      "join"
      "leave"
   end

   --- A human's aim. `want` is the spot they last chose, as the Eisenstein sum
   --- of its triangles' coordinates over `count` triangles, so the aim stays
   --- put (as near as it can) while chunks move and while they rotate.
   record Aim
      slot: integer
      turn: integer -- rotation, 0..5 sixths of a turn counterclockwise
      heading: integer -- which of the player's three headings, 1..3
      want: bc.AB
      count: integer
      spots: {board.Spot} -- legal spots for this chunk and rotation, along the back wall
      pick: integer -- the spot in use, or nil when the chunk fits nowhere
      shape: board.Shape
      cells: {board.Tri} -- the aim's triangles (or where it would be, if it fits nowhere)
      ghost: sim.Ghost
   end

   --- The right stick as a dial. Where it is first pushed is the anchor;
   --- `swept` is how far it has turned since, in degrees, clockwise as seen.
   record Dial
      x: number
      y: number
      on: boolean -- pushed out, with an anchor
      last: number -- its angle when last seen, in degrees
      swept: number
      turns: integer -- rotations applied since the anchor, clockwise positive
   end

   record Seat
      player: integer
      kind: Kind
      pad: love.Joystick -- the gamepad, for kind "pad"
      stick: {string: integer} -- per stick axis: -1, 0 or 1, the way it was last pushed
      dial: Dial -- the right stick, turned round to rotate
      held: {Action: number} -- repeating actions held down: seconds to their next repeat
      aim: Aim -- humans
      plan: sim.Shot -- bots: what they will fire
      brain: bots.Brain -- bots: how they choose it
   end
end

local type Seat = controls.Seat
local type Action = controls.Action

--- Sums of the Eisenstein coordinates of `cells`.
local function centre(B: board.Board, cells: {board.Tri}): bc.AB
   local a, b = 0, 0
   for _, t in ipairs(cells) do a, b = a + B.a[t.i], b + B.b[t.i] end
   return { a = a, b = b }
end

--- Squared distance (times count^2) between two centroids given as sums, by
--- the Eisenstein norm N(x + yw) = x^2 - xy + y^2. Exact.
local function far(u: bc.AB, nu: integer, v: bc.AB, nv: integer): integer
   local x, y = u.a * nv - v.a * nu, u.b * nv - v.b * nu
   return x * x - x * y + y * y
end

--- Put `spots` in order along the back wall, counterclockwise as drawn round
--- the board's centre z = 1. Every home lies within a 120 degree sector of
--- it, so the sign of the cross product orders them. Exact.
local function along_wall(B: board.Board, shape: board.Shape, spots: {board.Spot}): {board.Spot}
   local k = #shape.cells
   local key: {board.Spot: bc.AB} = {}
   for _, s in ipairs(spots) do
      local c = centre(B, board.place(B, shape, s.x, s.y))
      key[s] = { a = c.a - k, b = c.b }
   end
   table.sort(spots, function(p: board.Spot, q: board.Spot): boolean
      local u, v = key[p], key[q]
      local cross = u.a * v.b - u.b * v.a
      if cross ~= 0 then return cross > 0 end
      if p.y ~= q.y then return p.y < q.y end
      return p.x < q.x
   end)
   return spots
end

--- The board heading a human seat is aiming along.
local function heading(seat: Seat): integer
   return board.HEADINGS[seat.player][seat.aim.heading]
end

--- Recompute a human's aim against the board as it is now.
local function refresh_aim(state: sim.State, seat: Seat)
   local aim, p = seat.aim, seat.player
   if not aim or not state.players[p].alive then return end
   local B = state.board
   local chunk = state.players[p].bank[aim.slot]
   aim.shape = board.shape(B, bc.rotate(chunk, aim.turn))
   aim.spots = along_wall(B, aim.shape, sim.placements(state, p, aim.shape))
   aim.pick = nil
   local best = math.huge
   for i, s in ipairs(aim.spots) do
      local d = aim.want and far(centre(B, board.place(B, aim.shape, s.x, s.y)), #aim.shape.cells, aim.want, aim.count)
         or math.abs(i - (#aim.spots + 1) / 2)
      if d < best then best, aim.pick = d, i end
   end
   if aim.pick then
      local s = aim.spots[aim.pick]
      aim.cells = board.place(B, aim.shape, s.x, s.y)
      aim.ghost = sim.ghost(state, p, aim.cells, heading(seat))
      if not aim.want then aim.want, aim.count = centre(B, aim.cells), #aim.cells end
   else
      aim.ghost = nil
   end
end

--- Choose spot `i` of the current list as the one to hold on to.
local function choose_spot(state: sim.State, seat: Seat, i: integer)
   local aim = seat.aim
   local s = aim.spots[i]
   if not s then return end
   local cells = board.place(state.board, aim.shape, s.x, s.y)
   aim.want, aim.count = centre(state.board, cells), #cells
   refresh_aim(state, seat)
end

--- A bot seat for player `p` with `brain` (random if left out), with its
--- first shot planned.
function controls.bot(state: sim.State, p: integer, brain?: bots.Brain): Seat
   local seat: Seat = { player = p, kind = "bot", brain = brain or "random" }
   if state.players[p].alive then seat.plan = bots.choose(state, p, seat.brain) end
   return seat
end

--- A human seat for player `p`, on the keyboard or on gamepad `pad`.
function controls.human(state: sim.State, p: integer, kind: controls.Kind, pad?: love.Joystick): Seat
   local seat: Seat = { player = p, kind = kind, pad = pad, stick = {}, dial = { x = 0, y = 0, swept = 0, turns = 0 }, held = {}, aim = { slot = 1, turn = 0, heading = 2 } }
   refresh_aim(state, seat)
   return seat
end

function controls.is_human(seat: Seat): boolean
   return seat.kind ~= "bot"
end

--- The board heading a human seat is aiming along.
function controls.heading(seat: Seat): integer
   return heading(seat)
end

--- The board moved (a tick, or someone fired): humans re-aim against it.
--- Bots keep their plan and check it when their clock runs out.
function controls.update(state: sim.State, seat: Seat)
   if seat.aim then refresh_aim(state, seat) end
end

--- The seat's shot as its clock runs out, or nil when nothing it has fits.
function controls.shot(state: sim.State, seat: Seat): sim.Shot
   if seat.kind == "bot" then return bots.refresh(state, seat.player, seat.plan, seat.brain) end
   local aim = seat.aim
   if not aim or not aim.pick then return nil end
   return { player = seat.player, slot = aim.slot, heading = heading(seat), cells = aim.cells }
end

--- The seat's shot fired (`r` is what came of it): bots plan their next,
--- humans aim the next chunk from where the last one went.
function controls.fired(state: sim.State, seat: Seat, r: sim.LockResult)
   if seat.kind == "bot" then
      seat.plan = state.players[seat.player].alive and bots.choose(state, seat.player, seat.brain) or nil
   elseif r.fired and seat.aim.want then
      seat.aim.want, seat.aim.count = centre(state.board, r.fired.cells), #r.fired.cells
   end
end

--- Apply an aiming action. Returns true if it was one; "fire", "join" and
--- "leave" are the game's to handle, so they return false.
function controls.act(state: sim.State, seat: Seat, action: Action): boolean
   local aim = seat.aim
   if not aim or not state.players[seat.player].alive then return false end
   local slot = action:match("^slot(%d)$")
   if slot then
      local n = math.floor(tonumber(slot))
      if n > #state.players[seat.player].bank then return false end
      aim.slot = n
   elseif action == "turn_ccw" then
      aim.turn = (aim.turn + 1) % 6
   elseif action == "turn_cw" then
      aim.turn = (aim.turn + 5) % 6
   elseif action == "left" then
      if aim.pick then choose_spot(state, seat, math.max(1, aim.pick - 1)) end
      return true
   elseif action == "right" then
      if aim.pick then choose_spot(state, seat, math.min(#aim.spots, aim.pick + 1)) end
      return true
   elseif action == "heading_next" then
      aim.heading = aim.heading % 3 + 1
   elseif action == "heading_prev" then
      aim.heading = (aim.heading + 1) % 3 + 1
   else
      return false
   end
   refresh_aim(state, seat)
   return true
end

local KEYS <const>: {string: Action} = {
   ["1"] = "slot1", ["2"] = "slot2", ["3"] = "slot3",
   kp1 = "slot1", kp2 = "slot2", kp3 = "slot3",
   q = "turn_ccw", e = "turn_cw",
   left = "left", a = "left", right = "right", d = "right",
   up = "heading_next", tab = "heading_next", down = "heading_prev",
   ["return"] = "fire", kpenter = "fire", space = "fire",
}

local BUTTONS <const>: {string: Action} = {
   x = "slot1", y = "slot2", b = "slot3",
   leftshoulder = "turn_ccw", rightshoulder = "turn_cw",
   dpleft = "left", dpright = "right",
   dpup = "heading_next", dpdown = "heading_prev",
   a = "fire", start = "join", back = "leave",
}

--- The action a keyboard key asks for, if any.
function controls.key_action(key: string): Action
   return KEYS[key]
end

--- The action a gamepad button asks for, if any.
function controls.button_action(button: string): Action
   return BUTTONS[button]
end

--- How far a stick must go to count as a push, and come back to let go.
local PUSH <const> = 0.6
local REST <const> = 0.3

--- Actions that repeat while held, how long a hold waits before the first
--- repeat, and how often it repeats after that, in seconds.
local REPEATS <const>: {Action: boolean} = { left = true, right = true, turn_ccw = true, turn_cw = true }
local DELAY <const> = 0.25
local RATE <const> = 0.08

--- `action` was pressed: if it repeats, start its clock.
function controls.hold(seat: Seat, action: Action)
   if seat.held and action and REPEATS[action] then seat.held[action] = DELAY end
end

--- `action` was let go: stop repeating it.
function controls.release(seat: Seat, action: Action)
   if seat.held and action then seat.held[action] = nil end
end

--- The repeats due from held actions `dt` seconds on, in order.
function controls.repeats(seat: Seat, dt: number): {Action}
   local out: {Action} = {}
   if not seat.held then return out end
   for action, left in pairs(seat.held) do
      left = left - dt
      while left <= 0 do
         out[#out + 1] = action
         left = left + RATE
      end
      seat.held[action] = left
   end
   return out
end

local function stick_action(axis: string, dir: integer): Action
   if axis == "leftx" then return dir < 0 and "left" or "right" end
   return dir < 0 and "heading_next" or "heading_prev"
end

--- The action a stick movement asks for, if any: one per push, after which
--- holding the stick over repeats it as a held button would (see `repeats`).
--- `seat.stick` remembers each axis's push.
function controls.axis_action(seat: Seat, axis: string, value: number): Action
   if axis ~= "leftx" and axis ~= "lefty" then return nil end
   local was = seat.stick[axis] or 0
   local now = value >= PUSH and 1 or value <= -PUSH and -1 or math.abs(value) < REST and 0 or was
   seat.stick[axis] = now
   if now == was then return nil end
   if was ~= 0 then controls.release(seat, stick_action(axis, was)) end
   if now == 0 then return nil end
   local action = stick_action(axis, now)
   controls.hold(seat, action)
   return action
end

--- How far the dial must turn from its anchor to rotate once, and then how
--- much more each further rotation takes: it snaps to the nearest sixth.
local NUDGE <const> = 10
local SIXTH <const> = 60
--- How far back past a threshold the dial must go to undo a rotation, so a
--- stick held on one doesn't flicker.
local SLACK <const> = 3

--- The angle of (x, y) in degrees, -180..180. Lua 5.1's math.atan2 is gone
--- from later Luas, and one-argument atan is in both.
local function angle(x: number, y: number): number
   if x == 0 then return y > 0 and 90 or y < 0 and -90 or 0 end
   local t = math.deg(math.atan(y / x))
   if x > 0 then return t end
   return y >= 0 and t + 180 or t - 180
end

--- Rotations, clockwise positive, for a dial swept `swept` degrees from its anchor.
local function dial_turns(swept: number): integer
   local size = math.abs(swept)
   if size < NUDGE then return 0 end
   local n = math.max(1, math.floor(size / SIXTH + 0.5))
   return swept < 0 and -n or n
end

--- Rotations for a dial at `swept` that was at `turns`. Rotations are added
--- right at their thresholds but only undone `SLACK` degrees back past them.
local function settle(turns: integer, swept: number): integer
   local want = dial_turns(swept)
   local s = turns > 0 and 1 or turns < 0 and -1 or 0
   if s == 0 or want * s > turns * s then return want end
   local back = dial_turns(swept + s * SLACK)
   if back * s >= turns * s then return turns end
   if back * s <= 0 then return want end -- back through the anchor: count from there
   return back
end

--- The rotations a right-stick movement asks for, in order. Pushing the stick
--- out sets an anchor; turning it round from there clockwise rotates the chunk
--- clockwise, a first rotation after a small turn and one per sixth of a turn
--- (to the nearest) after that, and turning back undoes them, a few degrees
--- late so a stick held on a threshold stays put. Letting the
--- stick go drops the anchor.
function controls.dial_actions(seat: Seat, axis: string, value: number): {Action}
   local out: {Action} = {}
   local d = seat.dial
   if not d then return out end
   if axis == "rightx" then d.x = value elseif axis == "righty" then d.y = value else return out end
   local r = math.sqrt(d.x * d.x + d.y * d.y)
   if not d.on then
      if r >= PUSH then d.on, d.last, d.swept, d.turns = true, angle(d.x, d.y), 0, 0 end
      return out
   end
   if r < REST then
      d.on = false
      return out
   end
   -- Stick y points down, so the angle grows clockwise as seen.
   local now = angle(d.x, d.y)
   local step = (now - d.last + 180) % 360 - 180
   d.last, d.swept = now, d.swept + step
   local want = settle(d.turns, d.swept)
   while d.turns < want do d.turns = d.turns + 1; out[#out + 1] = "turn_cw" end
   while d.turns > want do d.turns = d.turns - 1; out[#out + 1] = "turn_ccw" end
   return out
end

--- What to call the seat's controller on screen.
function controls.label(seat: Seat): string
   if seat.kind == "keys" then return "keyboard" end
   if seat.kind == "pad" then return "controller" end
   return "bot"
end

--- What picks each bank slot, for the panels.
function controls.slot_keys(kind: controls.Kind): {string}
   if kind == "keys" then return { "1", "2", "3" } end
   if kind == "pad" then return { "X", "Y", "B" } end
   return nil
end

--- The on-screen legend for a kind of controller, as { key, what it does }.
function controls.legend(kind: controls.Kind): {{string, string}}
   if kind == "keys" then
      return {
         { "1 2 3", "pick chunk" },
         { "Q / E", "rotate" },
         { "Left Right / A D", "slide" },
         { "Up Down / Tab", "heading" },
         { "Space / Enter", "fire now" },
      }
   elseif kind == "pad" then
      return {
         { "X Y B", "pick chunk" },
         { "LB / RB / right stick", "rotate" },
         { "D-pad / stick", "slide, heading" },
         { "A", "fire now" },
         { "Back", "leave" },
      }
   end
   return nil
end

return controls
