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

function T.an_unusual_board_or_clock_joins_the_lists()
   local s = setup.new(7, 3, 14, 3)
   local n, r, _, clock = setup.options(s)
   A.eq(n, 7, "n")
   A.eq(r, 3, "r")
   A.eq(clock, 3, "clock")
   A.eq(s.picks[1].kind, "bot", "all bots without picks")
end

function T.options_change_and_stop_at_their_ends()
   local s = fresh()
   s.cursor = 1
   for _ = 1, 20 do setup.change(s, 1, {}) end
   local n, r = setup.options(s)
   A.eq(n, setup.BOARDS[#setup.BOARDS][1], "last board")
   A.eq(r, setup.BOARDS[#setup.BOARDS][2], "last board's notch")
   setup.move(s, 1)
   for _ = 1, 50 do setup.change(s, -1, {}) end
   local _, _, chunk = setup.options(s)
   A.eq(chunk, setup.MIN_CHUNK, "smallest chunk")
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
   s.cursor = 5 -- Player 2
   setup.change(s, 1, { pad1 }) -- bot -> keyboard
   A.eq(s.picks[2].kind, "keys", "keyboard on Player 2")
   A.eq(s.picks[1].kind, "bot", "and off Player 1")
   setup.change(s, 1, { pad1 }) -- keyboard -> controller 1
   A.eq(s.picks[2].pad, pad1, "controller on Player 2")
   setup.change(s, 1, { pad1 }) -- wraps to a bot
   A.eq(s.picks[2].kind, "bot", "round to a bot")
   setup.change(s, -1, { pad1 })
   A.eq(s.picks[2].pad, pad1, "and back")
end

function T.a_press_selects_the_row_under_the_cursor()
   local s = fresh()
   s.cursor = 1
   A.eq(setup.press(s, pad1, { pad1 }), false, "an option doesn't start")
   A.eq(s.board, 5, "steps the board on")
   s.cursor = 5
   A.eq(setup.press(s, pad1, { pad1 }), false, "a player's row doesn't start")
   A.eq(s.picks[2].pad, pad1, "sits the pad at Player 2")
   A.eq(s.picks[1].kind, "keys", "keyboard stays on Player 1")
   s.cursor = 7
   A.truthy(setup.press(s, pad2, { pad1, pad2 }), "Start starts, seated or not")
end

function T.lines_name_every_row()
   local s = fresh()
   setup.join(s, pad1)
   local lines = setup.lines(s, { pad1 })
   A.eq(#lines, 7, "three options, three players, start")
   A.eq(lines[1].value, "22-8", "board as diameter-notch")
   A.eq(lines[4].value, "Keyboard", "Player 1")
   A.eq(lines[5].value, "Controller 1", "Player 2")
   A.eq(lines[6].value, "Bot", "Player 3")
end

return T
