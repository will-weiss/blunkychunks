local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local controls = require("controls")
local A = require("tests.assert")

local record T
end

local function fresh(): sim.State
   return sim.new(board.new(6, 5), 6, bc.seeded_random(3))
end

function T.a_human_seat_aims_a_legal_shot_on_its_heading()
   local s = fresh()
   for p = 1, 3 do
      local seat = controls.human(s, p, "keys")
      local shot = controls.shot(s, seat)
      A.truthy(shot, "aimed")
      A.eq(shot.player, p, "for its player")
      A.eq(shot.slot, 1, "from the first slot")
      A.truthy(sim.legal(s, p, shot.cells), "legal")
      A.eq(shot.heading, controls.heading(seat), "along its heading")
      A.truthy(sim.can_head(p, shot.heading), "one of the player's")
   end
end

function T.sliding_moves_along_the_wall_and_stops_at_its_ends()
   local s = fresh()
   local seat = controls.human(s, 1, "keys")
   local aim = seat.aim
   A.truthy(#aim.spots > 1, "room to slide")
   for _ = 1, #aim.spots do controls.act(s, seat, "left") end
   A.eq(aim.pick, 1, "at one end")
   controls.act(s, seat, "right")
   A.eq(aim.pick, 2, "one step along")
   A.truthy(sim.legal(s, 1, controls.shot(s, seat).cells), "still legal")
   for _ = 1, #aim.spots do controls.act(s, seat, "right") end
   A.eq(aim.pick, #aim.spots, "at the other end")
end

function T.a_human_never_aims_friendly_fire()
   local s = fresh()
   for p = 1, 3 do
      local seat = controls.human(s, p, "keys")
      local aim = seat.aim
      for turn = 0, 5 do
         aim.turn = turn
         controls.update(s, seat)
         for i = 1, #aim.spots do
            while aim.pick < i do controls.act(s, seat, "right") end
            for _ = 1, 4 do
               A.eq(sim.friendly(s, p, aim.cells, controls.heading(seat)), false, "not friendly")
               A.truthy(aim.ghost.look ~= "friendly", "nor its ghost")
               controls.act(s, seat, "heading_next")
            end
         end
         for _ = 1, #aim.spots do controls.act(s, seat, "left") end
      end
   end
end

function T.a_heading_set_aside_for_friendly_fire_comes_back()
   local s = fresh()
   local seat = controls.human(s, 1, "keys")
   local aim = seat.aim
   local function bad(n: integer): boolean
      return sim.friendly(s, 1, aim.cells, board.HEADINGS[1][n])
   end
   -- Find a side heading that is fine at one end of the wall but friendly
   -- somewhere along it.
   for _ = 1, #aim.spots do controls.act(s, seat, "left") end
   for _, n in ipairs({ 1, 3 }) do
      if not bad(n) then
         while aim.heading ~= n do controls.act(s, seat, "heading_next") end
         local start = aim.pick
         while aim.pick < #aim.spots do
            controls.act(s, seat, "right")
            if aim.prefer == n and aim.heading ~= n then
               A.eq(bad(n), true, "set aside only when friendly")
               while aim.pick > start do controls.act(s, seat, "left") end
               A.eq(aim.heading, n, "back on it at the start")
               return
            end
         end
      end
   end
   A.truthy(false, "no spot where a side heading is friendly")
end

function T.actions_pick_turn_and_head()
   local s = fresh()
   local seat = controls.human(s, 2, "pad")
   A.truthy(controls.act(s, seat, "slot3"), "slot3 handled")
   A.eq(seat.aim.slot, 3, "picked slot 3")
   controls.act(s, seat, "turn_ccw")
   A.eq(seat.aim.turn, 1, "turned counterclockwise")
   controls.act(s, seat, "turn_cw")
   controls.act(s, seat, "turn_cw")
   A.eq(seat.aim.turn, 5, "and back round clockwise")
   local first = seat.aim.heading
   for _ = 1, 3 do controls.act(s, seat, "heading_next") end
   A.eq(seat.aim.heading, first, "three headings round")
   controls.act(s, seat, "heading_next")
   controls.act(s, seat, "heading_prev")
   A.eq(seat.aim.heading, first, "prev undoes next")
   A.eq(controls.act(s, seat, "fire"), false, "fire is the game's")
end

function T.out_players_ignore_actions()
   local s = fresh()
   local seat = controls.human(s, 1, "keys")
   s.players[1].alive = false
   A.eq(controls.act(s, seat, "slot2"), false, "not handled")
   A.eq(seat.aim.slot, 1, "aim unchanged")
end

function T.a_bot_seat_plans_and_replans_after_firing()
   local s = fresh()
   local seat = controls.bot(s, 3)
   A.truthy(seat.plan, "planned")
   local shot = controls.shot(s, seat)
   A.truthy(sim.legal(s, 3, shot.cells), "fires a legal shot")
   local r = sim.lock_in(s, 3, shot)
   controls.fired(s, seat, r)
   A.truthy(seat.plan and seat.plan ~= shot, "plans the next one")
   A.eq(seat.aim, nil, "no aim of its own")
end

function T.a_greedyclear_bot_seat_keeps_its_brain()
   local s = fresh()
   local seat = controls.bot(s, 2, "greedyclear")
   A.eq(seat.brain, "greedyclear", "greedyclear")
   A.truthy(sim.legal(s, 2, controls.shot(s, seat).cells), "fires a legal shot")
   A.eq(controls.bot(s, 1).brain, "random", "random by default")
end

function T.a_human_aims_the_next_chunk_from_where_the_last_fired()
   local s = fresh()
   local seat = controls.human(s, 1, "keys")
   controls.act(s, seat, "right")
   local shot = controls.shot(s, seat)
   local r = sim.lock_in(s, 1, shot)
   controls.fired(s, seat, r)
   controls.update(s, seat)
   A.truthy(controls.shot(s, seat), "aiming again")
end

function T.keys_and_buttons_map_to_the_same_actions()
   A.eq(controls.key_action("1"), "slot1", "1")
   A.eq(controls.button_action("x"), "slot1", "X")
   A.eq(controls.key_action("q"), controls.button_action("leftshoulder"), "rotate")
   A.eq(controls.key_action("left"), controls.button_action("dpleft"), "slide")
   A.eq(controls.key_action("space"), controls.button_action("a"), "fire")
   A.eq(controls.key_action("r"), nil, "R is the game's")
   A.eq(controls.button_action("start"), "join", "Start joins")
end

function T.held_slides_and_turns_repeat_until_let_go()
   local s = fresh()
   local seat = controls.human(s, 2, "pad")
   controls.hold(seat, "turn_cw")
   controls.hold(seat, "heading_next")
   A.eq(#controls.repeats(seat, 0.2), 0, "a wait before repeating")
   local r = controls.repeats(seat, 0.1)
   A.eq(#r, 1, "then one repeat")
   A.eq(r[1], "turn_cw", "of the turn, not the heading")
   A.eq(#controls.repeats(seat, 0.33), 4, "then steadily")
   controls.release(seat, "turn_cw")
   A.eq(#controls.repeats(seat, 1), 0, "until let go")
end

function T.the_stick_acts_once_per_push_then_repeats_while_held()
   local s = fresh()
   local seat = controls.human(s, 2, "pad")
   A.eq(controls.axis_action(seat, "leftx", 0.2), nil, "a nudge is nothing")
   A.eq(controls.axis_action(seat, "leftx", -0.8), "left", "a push left")
   A.eq(controls.axis_action(seat, "leftx", -1.0), nil, "held, no second push")
   A.eq(controls.repeats(seat, 0.3)[1], "left", "but held over, it repeats")
   A.eq(controls.axis_action(seat, "leftx", -0.4), nil, "easing off isn't letting go")
   A.eq(controls.axis_action(seat, "leftx", 0.0), nil, "let go")
   A.eq(#controls.repeats(seat, 1), 0, "and the repeats stop")
   A.eq(controls.axis_action(seat, "leftx", 0.9), "right", "a push right")
   A.eq(controls.axis_action(seat, "lefty", -0.9), "heading_next", "up")
   A.eq(controls.axis_action(seat, "triggerleft", 1.0), nil, "triggers do nothing")
end

--- Move the left stick to (x, y) in small steps, as a real one moves, and
--- collect what it asked for.
local function move(s: sim.State, seat: controls.Seat, x: number, y: number): controls.Action
   local f = seat.flick
   local x0, y0 = f.x, f.y
   local out: controls.Action
   for i = 1, 20 do
      out = controls.flick_action(s, seat, "leftx", x0 + (x - x0) * i / 20) or out
      out = controls.flick_action(s, seat, "lefty", y0 + (y - y0) * i / 20) or out
   end
   return out
end

--- Push player p's left stick out to `r` (from the middle), `off` degrees
--- clockwise as seen from the way their corner points as drawn.
local function point(s: sim.State, seat: controls.Seat, off: number, r?: number): controls.Action
   r = r or 1
   local t = math.rad(60 * board.PLAYERS[seat.player].corner - 30 + off)
   move(s, seat, 0, 0)
   return move(s, seat, r * math.cos(t), r * math.sin(t))
end

local function let_go(s: sim.State, seat: controls.Seat): controls.Action
   return move(s, seat, 0, 0)
end

--- Degrees clockwise as seen from player p's corner to the aim's centroid,
--- as drawn (a twelfth of a turn anticlockwise from board space).
local function drawn_off(s: sim.State, seat: controls.Seat): number
   local x, y = 0.0, 0.0
   for _, t in ipairs(seat.aim.cells) do
      local c = board.centroid(s.board.a[t.i], s.board.b[t.i], 1)
      x, y = x + c.x, y + c.y
   end
   local deg = math.deg(math.atan(y / x)) + (x < 0 and 180 or 0) - 30
   return (deg - (60 * board.PLAYERS[seat.player].corner - 30) + 180) % 360 - 180
end

function T.the_left_stick_places_the_chunk_round_the_home()
   local s = fresh()
   for p = 1, 3 do
      local seat = controls.human(s, p, "pad")
      local aim = seat.aim
      A.truthy(#aim.spots > 2, "room to place")
      A.eq(point(s, seat, 120), nil, "pointing at the home doesn't fire")
      A.eq(aim.pick, 1, "fully clockwise: the back wall's start")
      local start = drawn_off(s, seat)
      A.truthy(start > 0, "which is clockwise of the corner as drawn")
      point(s, seat, -120)
      A.eq(aim.pick, #aim.spots, "fully anticlockwise: its end")
      A.truthy(drawn_off(s, seat) < 0, "anticlockwise of the corner")
      point(s, seat, 0)
      A.eq(aim.pick, (#aim.spots + 1) // 2 + (#aim.spots % 2 == 0 and 1 or 0), "straight at the corner: the middle")
      local t = math.rad(60 * board.PLAYERS[p].corner - 30)
      move(s, seat, 0.45 * math.cos(t), 0.45 * math.sin(t))
      A.eq(aim.pick, (#aim.spots + 1) // 2 + (#aim.spots % 2 == 0 and 1 or 0), "eased off, nothing changes")
      point(s, seat, 90)
      local held = aim.pick
      A.eq(let_go(s, seat), nil, "letting go from the home isn't a flick")
      A.eq(aim.pick, held, "and the chunk stays put")
      A.eq(aim.along, nil, "no longer following the stick")
      A.truthy(sim.legal(s, p, controls.shot(s, seat).cells), "a legal shot")
   end
end

function T.the_left_stick_follows_its_angle_while_the_chunk_rotates()
   local s = fresh()
   local seat = controls.human(s, 1, "pad")
   point(s, seat, 120)
   for _ = 1, 6 do
      controls.act(s, seat, "turn_cw")
      if seat.aim.pick then A.eq(seat.aim.pick, 1, "still at the start") end
   end
end

function T.a_flick_across_the_board_picks_a_heading_and_fires_when_let_go()
   local s = fresh()
   for p = 1, 3 do
      local seat = controls.human(s, p, "pad")
      local aim = seat.aim
      point(s, seat, 0)
      local spot = aim.pick
      A.eq(let_go(s, seat), nil, "placed")
      for _, case in ipairs({ { 180, 2 }, { -165, 2 }, { 165, 2 }, { 140, 1 }, { 125, 1 }, { -140, 3 }, { -125, 3 } }) do
         A.eq(point(s, seat, case[1]), nil, "pointing across doesn't fire yet")
         A.eq(aim.prefer, case[2], ("%d degrees picks heading %d"):format(case[1], case[2]))
         A.eq(let_go(s, seat), "flick", "letting go is the flick")
         A.eq(aim.pick, spot, "the chunk stayed where it was placed")
      end
      point(s, seat, 180)
      local c = 60 * board.PLAYERS[p].corner - 30
      for _, off in ipairs({ 120, 0 }) do
         move(s, seat, math.cos(math.rad(c + off)), math.sin(math.rad(c + off)))
      end
      A.eq(let_go(s, seat), nil, "swung round the rim to the home and let go there: no flick")
      A.eq(controls.flick_action(s, seat, "triggerleft", 1), nil, "triggers do nothing")
   end
end

--- Feed the right stick round to `deg` degrees (clockwise as seen) from
--- straight up, in small steps from `from`, and collect what it asked for.
local function dial_to(seat: controls.Seat, from: number, deg: number): {controls.Action}
   local out: {controls.Action} = {}
   local step = deg > from and 1 or -1
   for a = from + step, deg, step do
      local t = math.rad(a - 90)
      for _, axis in ipairs({ "rightx", "righty" }) do
         local v = axis == "rightx" and math.cos(t) or math.sin(t)
         for _, act in ipairs(controls.dial_actions(seat, axis, v)) do out[#out + 1] = act end
      end
   end
   return out
end

function T.the_right_stick_dials_rotations_from_where_it_is_pushed()
   local s = fresh()
   local seat = controls.human(s, 2, "pad")
   A.eq(#controls.dial_actions(seat, "righty", -1.0), 0, "pushed up: the anchor")
   A.eq(#dial_to(seat, 0, 9), 0, "9 degrees is nothing")
   local r = dial_to(seat, 9, 11)
   A.eq(#r, 1, "past 10 degrees, one rotation")
   A.eq(r[1], "turn_cw", "clockwise")
   A.eq(#dial_to(seat, 11, 89), 0, "still one at 89")
   A.eq(#dial_to(seat, 89, 91), 1, "two past 90")
   A.eq(#dial_to(seat, 91, 88), 0, "a wobble back under 90 keeps two")
   A.eq(#dial_to(seat, 88, 91), 0, "and nothing doubles going over again")
   A.eq(#dial_to(seat, 91, 86), 1, "back a few degrees past 90 is one")
   A.eq(#dial_to(seat, 86, 91), 1, "and over 90 again is two")
   A.eq(#dial_to(seat, 91, 400), 5, "seven round past a full turn")
   r = dial_to(seat, 400, 5)
   A.eq(#r, 7, "turning back undoes them all")
   A.eq(r[1], "turn_ccw", "counterclockwise")
   A.eq(#dial_to(seat, 5, 11), 1, "one again past 10")
   A.eq(#dial_to(seat, 11, 8), 0, "still one a little under 10")
   A.eq(#dial_to(seat, 8, 11), 0, "nothing more back over it")
   r = dial_to(seat, 11, -20)
   A.eq(#r, 2, "back through the anchor and one the other way")
   A.eq(r[1], "turn_ccw", "counterclockwise")
   controls.dial_actions(seat, "rightx", 0)
   controls.dial_actions(seat, "righty", 0)
   A.eq(#controls.dial_actions(seat, "rightx", 1.0), 0, "let go, then pushed right: a new anchor")
   A.eq(#dial_to(seat, 90, 70), 1, "so turning from there counts from there")
   A.eq(#controls.dial_actions(seat, "leftx", 1.0), 0, "the left stick doesn't dial")
end

function T.every_controller_has_a_legend()
   for _, kind in ipairs({ "keys", "pad" } as {controls.Kind}) do
      A.truthy(#controls.legend(kind) > 0, kind .. " legend")
      A.eq(#controls.slot_keys(kind), sim.BANK, kind .. " slot keys")
   end
   A.eq(controls.legend("bot"), nil, "bots need none")
end

return T
