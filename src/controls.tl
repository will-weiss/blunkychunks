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
      "remote" -- played on another machine (or by the server's bot) in a networked match
   end

   --- Everything a human can ask of their seat, whatever they hold.
   enum Action
      "slot1"
      "slot2"
      "slot3"
      "slot_prev" -- the bank chunk shown left of the one in use
      "slot_next" -- the bank chunk shown right of it
      "turn_ccw"
      "turn_cw"
      "left"
      "right"
      "heading_next"
      "heading_prev"
      "fire"
      "flick" -- the left stick flicked across the board and let go
      "join"
      "leave"
   end

   --- A human's aim. `want` is the spot they last chose, as the Eisenstein sum
   --- of its triangles' coordinates over `count` triangles, so the aim stays
   --- put (as near as it can) while chunks move and while they rotate.
   record Aim
      slot: integer
      turn: integer -- rotation, 0..5 sixths of a turn counterclockwise
      heading: integer -- which of the player's three headings is in use, 1..3
      prefer: integer -- the heading last chosen, in use whenever it isn't friendly fire
      want: bc.AB
      count: integer
      spots: {board.Spot} -- legal spots for this chunk and rotation, along the back wall
      pick: integer -- the spot in use, or nil when the chunk fits nowhere
      along: number -- while the left stick places: how far along the back wall, 0..1
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

   --- The left stick, which both places and fires. `aiming` is set while it
   --- points across the board, picking a heading, rather than placing.
   record Flick
      x: number
      y: number
      aiming: boolean
   end

   record Seat
      player: integer
      kind: Kind
      pad: love.Joystick -- the gamepad, for kind "pad"
      stick: {string: integer} -- per stick axis: -1, 0 or 1, the way it was last pushed
      dial: Dial -- the right stick, turned round to rotate
      flick: Flick -- the left stick, to place and fire
      held: {Action: number} -- repeating actions held down: seconds to their next repeat
      aim: Aim -- humans
      plan: sim.Shot -- bots: what they will fire
      brain: bots.Brain -- bots: how they choose it
      name: string -- remote seats: who, as the server calls them
   end
end

local type Seat = controls.Seat
local type Action = controls.Action

--- The board heading a human seat is aiming along.
local function heading(seat: Seat): integer
   return board.HEADINGS[seat.player][seat.aim.heading]
end

--- Would the aim's cells, fired on heading `n` of the seat's three, be
--- friendly fire?
local function friendly(state: sim.State, seat: Seat, n: integer): boolean
   return sim.friendly(state, seat.player, seat.aim.cells, board.HEADINGS[seat.player][n])
end

--- The spot of `n` along the back wall that is `along` (0..1) of the way.
local function along_pick(along: number, n: integer): integer
   return math.max(1, math.min(n, math.floor(along * (n - 1) + 0.5) + 1))
end

--- What a human's aim is after, as sim.settle takes it (and as it goes to
--- the server in a networked match).
function controls.intent(aim: controls.Aim): sim.Intent
   return { slot = aim.slot, turn = aim.turn, prefer = aim.prefer, want = aim.want, count = aim.count }
end

--- Recompute a human's aim against the board as it is now: the rules'
--- `settle`, except that while the left stick places, it picks the spot.
local function refresh_aim(state: sim.State, seat: Seat)
   local aim, p = seat.aim, seat.player
   if not aim or not state.players[p].alive then return end
   local along = aim.along
   local s = sim.settle(state, p, controls.intent(aim), along and function(n: integer): integer return along_pick(along, n) end)
   aim.shape, aim.spots, aim.pick, aim.heading = s.shape, s.spots, s.pick, s.heading
   if s.pick then
      aim.cells = s.cells
      aim.ghost = sim.ghost(state, p, aim.cells, heading(seat))
      if not aim.want or aim.along then aim.want, aim.count = sim.centre(state.board, aim.cells), #aim.cells end
   else
      aim.ghost = nil
   end
end

--- Step the aim's heading `by` (1 or 2, i.e. -1) round its three, past any
--- that would be friendly fire from where it is, and prefer it from now on.
local function turn_heading(state: sim.State, seat: Seat, by: integer)
   local aim = seat.aim
   local n = aim.heading
   for _ = 1, 2 do
      n = (n + by - 1) % 3 + 1
      if not aim.pick or not friendly(state, seat, n) then
         aim.prefer = n
         return
      end
   end
end

--- Choose spot `i` of the current list as the one to hold on to.
local function choose_spot(state: sim.State, seat: Seat, i: integer)
   local aim = seat.aim
   local s = aim.spots[i]
   if not s then return end
   local cells = board.place(state.board, aim.shape, s.x, s.y)
   aim.want, aim.count = sim.centre(state.board, cells), #cells
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
   local seat: Seat = { player = p, kind = kind, pad = pad, stick = {}, dial = { x = 0, y = 0, swept = 0, turns = 0 }, flick = { x = 0, y = 0 }, held = {}, aim = { slot = 1, turn = 0, heading = 2, prefer = 2 } }
   refresh_aim(state, seat)
   return seat
end

function controls.is_human(seat: Seat): boolean
   return seat.kind == "keys" or seat.kind == "pad"
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
   if not seat.aim then return nil end
   return sim.settle(state, seat.player, controls.intent(seat.aim)).shot
end

--- The seat's shot fired (`r` is what came of it): bots plan their next,
--- humans aim the next chunk from where the last one went.
function controls.fired(state: sim.State, seat: Seat, r: sim.LockResult)
   if seat.kind == "bot" then
      seat.plan = state.players[seat.player].alive and bots.choose(state, seat.player, seat.brain) or nil
   elseif r.fired and seat.aim and seat.aim.want then
      seat.aim.want, seat.aim.count = sim.centre(state.board, r.fired.cells), #r.fired.cells
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
   elseif action == "slot_prev" or action == "slot_next" then
      local n = #state.players[seat.player].bank
      aim.slot = (aim.slot - 1 + (action == "slot_next" and 1 or n - 1)) % n + 1
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
      turn_heading(state, seat, 1)
   elseif action == "heading_prev" then
      turn_heading(state, seat, 2)
   else
      return false
   end
   refresh_aim(state, seat)
   return true
end

local KEYS <const>: {string: Action} = {
   z = "slot_prev", c = "slot_next",
   q = "turn_ccw", e = "turn_cw",
   left = "left", a = "left", right = "right", d = "right",
   up = "heading_next", tab = "heading_next", down = "heading_prev",
   ["return"] = "fire", kpenter = "fire", space = "fire",
}

local BUTTONS <const>: {string: Action} = {
   leftshoulder = "slot_prev", rightshoulder = "slot_next",
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

--- The action a stick movement asks for, if any, on the setup screen: one per push, after which
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

--- The left stick places the chunk while it points within `HOME` degrees
--- either side of the player's corner, the half of the stick facing their
--- home, and aims while it points across the board, the other half. Aiming,
--- straight across is within `ACROSS` degrees of dead ahead, and the side
--- headings either side of that.
local HOME <const> = 90
local ACROSS <const> = 30

--- Which way player `p`'s corner points as drawn, in degrees clockwise from
--- east as seen (y down), like the stick's own angle. draw.tl turns board
--- space so player `south`'s corner points straight down (90), and corner c
--- points at 60c in it.
local function corner_angle(p: integer, south: integer): number
   return 60 * (board.PLAYERS[p].corner - board.PLAYERS[south].corner) + 90
end

--- What a left-stick movement asks for: "flick" when it is let go while
--- aiming, else nil. Pushed out towards the home, its angle places the
--- chunk along the back wall, one end to the other as it goes round.
--- Pushed out across the board, it aims, picking the heading it points at
--- and leaving the chunk where it is. Whichever half it is in decides, so
--- swinging back towards the home places again. Letting go after aiming is
--- the flick. Let go, the chunk stays where it was placed; easing the stick
--- between the two thresholds changes nothing. `south` is the player whose
--- home is drawn at the bottom (Player 1 if left out).
function controls.flick_action(state: sim.State, seat: Seat, axis: string, value: number, south?: integer): Action
   local f = seat.flick
   if not f then return nil end
   if axis == "leftx" then f.x = value elseif axis == "lefty" then f.y = value else return nil end
   local aim = seat.aim
   if not aim or not state.players[seat.player].alive then return nil end
   local r = math.sqrt(f.x * f.x + f.y * f.y)
   if r < REST then
      local flicked = f.aiming
      f.aiming, aim.along = false, nil
      return flicked and aim.pick and "flick" or nil
   end
   if r < PUSH then return nil end
   local off = (angle(f.x, f.y) - corner_angle(seat.player, south or 1) + 180) % 360 - 180
   f.aiming = math.abs(off) > HOME
   if not f.aiming then
      -- Clockwise from the corner as seen is the back wall's start.
      aim.along = (HOME - off) / (2 * HOME)
      if #aim.spots > 0 and aim.pick ~= along_pick(aim.along, #aim.spots) then refresh_aim(state, seat) end
   else
      local n = math.abs(off) >= 180 - ACROSS and 2 or off > 0 and 1 or 3
      if aim.prefer ~= n then
         aim.prefer = n
         refresh_aim(state, seat)
      end
   end
   return nil
end

--- A seat played elsewhere in a networked match, by `name` ("bot" for one
--- of the server's bots). It has no aim here: nobody else's aim is known.
function controls.remote(p: integer, name: string): Seat
   return { player = p, kind = "remote", name = name }
end

--- What to call the seat's controller on screen.
function controls.label(seat: Seat): string
   if seat.kind == "keys" then return "keyboard" end
   if seat.kind == "pad" then return "controller" end
   if seat.kind == "remote" then return seat.name or "bot" end
   return "bot"
end

--- What takes the queued chunk on the left and on the right, for the queue.
function controls.queue_keys(kind: controls.Kind): {string}
   if kind == "keys" then return { "Z", "C" } end
   if kind == "pad" then return { "LB", "RB" } end
   return nil
end

--- The legend for a match played on this machine.
local function legend_here(kind: controls.Kind): {{string, string}}
   if kind == "keys" then
      return {
         { "Z / C", "take the left / right chunk" },
         { "Q / E", "rotate" },
         { "Left Right / A D", "slide" },
         { "Up Down / Tab", "heading" },
         { "Space / Enter", "fire now" },
      }
   elseif kind == "pad" then
      return {
         { "LB / RB", "take the left / right chunk" },
         { "right stick", "rotate" },
         { "left stick", "point to place, flick to fire" },
         { "D-pad", "slide, heading" },
         { "A", "fire now" },
         { "Back", "leave" },
      }
   end
   return nil
end

--- The on-screen legend for a kind of controller, as { key, what it does }.
--- In a networked match (`vote`) firing now is a vote: see README.
function controls.legend(kind: controls.Kind, vote?: boolean): {{string, string}}
   local list = legend_here(kind)
   if vote and list then
      for _, pair in ipairs(list) do
         if pair[2] == "fire now" then pair[2] = "ready (fires once all are)" end
      end
   end
   return list
end

return controls
