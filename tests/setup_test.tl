local setup = require("setup")
local A = require("tests.assert")

local record T
end

local pad1 = {} as love.Joystick
local pad2 = {} as love.Joystick

local function fresh(): setup.State
   return setup.new(11, 8, 14, 8, { { kind = "keys" } })
end

function T.it_starts_from_the_given_options_and_seats()
   local s = fresh()
   local n, r, chunk, clock = setup.options(s)
   A.eq(n, 11, "n")
   A.eq(r, 8, "r")
   A.eq(chunk, 14, "chunk")
   A.eq(clock, 8, "clock")
   A.eq(s.picks[1].kind, "keys", "keyboard on Player 1")
   A.eq(s.picks[2].kind, "bot", "a bot on Player 2")
   A.truthy(setup.on_start(s), "cursor on Start")
end

function T.with_no_picks_every_home_is_a_bot()
   local s = setup.new(7, 3, 14, 3)
   A.eq(s.picks[1].kind, "bot", "all bots without picks")
end

function T.each_option_steps_by_one()
   local s = fresh()
   for row = 1, 4 do
      s.cursor = row
      setup.change(s, 1, {})
   end
   local n, r, chunk, clock = setup.options(s)
   A.eq(n, 12, "middle's side")
   A.eq(r, 9, "notch")
   A.eq(chunk, 15, "chunk")
   A.eq(clock, 9, "clock")
   A.eq(setup.lines(s, {})[1].value, "24", "diameter is twice the side")
   A.eq(setup.lines(s, {})[2].value, "9", "personal area")
end

function T.options_change_and_stop_at_their_ends()
   local s = fresh()
   s.cursor = 1
   for _ = 1, 50 do setup.change(s, 1, {}) end
   setup.move(s, 1)
   for _ = 1, 50 do setup.change(s, -1, {}) end
   setup.move(s, 1)
   for _ = 1, 50 do setup.change(s, -1, {}) end
   setup.move(s, 1)
   for _ = 1, 50 do setup.change(s, 1, {}) end
   local n, r, chunk, clock = setup.options(s)
   A.eq(n, setup.MAX_N, "biggest board")
   A.eq(r, setup.MIN_R, "smallest personal area")
   A.eq(chunk, setup.MIN_CHUNK, "smallest chunk")
   A.eq(clock, setup.MAX_CLOCK, "longest clock")
   setup.move(s, -10)
   A.eq(s.cursor, 1, "cursor stops at the top")
   setup.move(s, 100)
   A.truthy(setup.on_start(s), "and at the bottom")
end

function T.a_gamepad_joins_the_first_bot_and_leaves()
   local s = fresh()
   A.eq(setup.join(s, pad1), 2, "first bot's home")
   A.eq(setup.join(s, pad1), nil, "only once")
   A.eq(setup.join(s, pad2), 3, "the next")
   A.eq(setup.seat_of(s, "pad", pad2), 3, "found")
   setup.leave(s, "pad", pad1)
   A.eq(s.picks[2].kind, "bot", "back to a bot")
end

function T.cycling_a_row_moves_a_controller_rather_than_copying_it()
   local s = fresh()
   s.cursor = 6 -- Player 2
   setup.change(s, 1, { pad1 }) -- bot -> greedyclear bot
   A.eq(s.picks[2].kind, "bot", "still a bot")
   A.eq(s.picks[2].brain, "greedyclear", "a greedyclear one")
   A.eq(setup.lines(s, { pad1 })[6].value, "Greedyclear bot", "and says so")
   setup.change(s, 1, { pad1 }) -- greedyclear bot -> keyboard
   A.eq(s.picks[2].kind, "keys", "keyboard on Player 2")
   A.eq(s.picks[1].kind, "bot", "and off Player 1")
   setup.change(s, 1, { pad1 }) -- keyboard -> controller 1
   A.eq(s.picks[2].pad, pad1, "controller on Player 2")
   setup.change(s, 1, { pad1 }) -- wraps to a bot
   A.eq(s.picks[2].kind, "bot", "round to a bot")
   setup.change(s, -1, { pad1 })
   A.eq(s.picks[2].pad, pad1, "and back")
   setup.change(s, 1, { pad1 })
   A.eq(s.picks[2].brain, "random", "a plain bot again")
   A.eq(setup.lines(s, { pad1 })[6].value, "Bot", "called Bot")
end

function T.a_press_selects_the_row_under_the_cursor()
   local s = fresh()
   s.cursor = 1
   A.eq(setup.press(s, pad1, { pad1 }), false, "an option doesn't start")
   A.eq(s.n, 12, "steps the board on")
   s.cursor = 6
   A.eq(setup.press(s, pad1, { pad1 }), false, "a player's row doesn't start")
   A.eq(s.picks[2].pad, pad1, "sits the pad at Player 2")
   A.eq(s.picks[1].kind, "keys", "keyboard stays on Player 1")
   s.cursor = 8
   A.truthy(setup.press(s, pad2, { pad1, pad2 }), "Start starts, seated or not")
end

function T.lines_name_every_row()
   local s = fresh()
   setup.join(s, pad1)
   local lines = setup.lines(s, { pad1 })
   A.eq(#lines, 8, "four options, three players, start")
   A.eq(lines[1].value, "22", "diameter")
   A.eq(lines[2].value, "8", "personal area")
   A.eq(lines[5].value, "Keyboard", "Player 1")
   A.eq(lines[6].value, "Controller 1", "Player 2")
   A.eq(lines[7].value, "Bot", "Player 3")
end

return T
