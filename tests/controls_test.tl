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

function T.every_controller_has_a_legend()
   for _, kind in ipairs({ "keys", "pad" } as {controls.Kind}) do
      A.truthy(#controls.legend(kind) > 0, kind .. " legend")
      A.eq(#controls.slot_keys(kind), sim.BANK, kind .. " slot keys")
   end
   A.eq(controls.legend("bot"), nil, "bots need none")
end

return T
