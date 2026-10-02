--- The screen before a match: pick the board, chunk size and shot clock, and
--- who plays each home -- a bot, the keyboard or a gamepad. Every controller
--- shares one cursor down the rows; on an option row left and right change
--- it, and on a player's row they cycle who sits there. A gamepad can also
--- just press Start to take the first home a bot has.
---
--- Like controls.tl, nothing here touches LOVE beyond holding on to a
--- gamepad's joystick, so it runs (and is tested) under plain Lua.

local board = require("board")
local controls = require("controls")

local record setup
   --- Who sits at a home: kind "bot", "keys" or "pad" (with its `pad`).
   record Pick
      kind: controls.Kind
      pad: love.Joystick
   end

   --- One line of the screen, as drawn.
   record Line
      label: string
      value: string
      color: string -- the label's colour, for a player's row
      player: integer -- the home it seats, for a player's row
   end

   record State
      boards: {{integer, integer}} -- the boards to choose from, as { n, r }
      board: integer
      chunk: integer -- triangles per chunk
      clocks: {number} -- the shot clocks to choose from, in seconds
      clock: integer
      picks: {Pick} -- per player
      cursor: integer -- the row the cursor is on
   end

   BOARDS: {{integer, integer}}
   CLOCKS: {number}
   MIN_CHUNK: integer
   MAX_CHUNK: integer
end

local type Pick = setup.Pick
local type State = setup.State

--- Notched boards known to play well, as { n, r } (the middle's side and
--- the notch): drawn as diameter-notch, e.g. 22-8.
setup.BOARDS = { { 6, 5 }, { 10, 5 }, { 10, 8 }, { 11, 8 }, { 11, 12 }, { 17, 5 }, { 17, 17 } }
setup.CLOCKS = { 2, 4, 6, 8, 10, 12, 15 }
setup.MIN_CHUNK = 3
setup.MAX_CHUNK = 24

-- Rows: the three options, a row per player, then Start.
local BOARD_ROW <const> = 1
local CHUNK_ROW <const> = 2
local CLOCK_ROW <const> = 3
local FIRST_PLAYER_ROW <const> = 4

local function start_row(): integer
   return FIRST_PLAYER_ROW + #board.PLAYERS
end

--- Index of `x` in `list` (by `same`), or nil.
local function find<T>(list: {T}, same: function(T): boolean): integer
   for i, v in ipairs(list) do
      if same(v) then return i end
   end
   return nil
end

--- A setup screen starting from board n-r, `chunk` triangles a chunk, a
--- `clock` second shot clock and `picks` (each player a bot if left out).
--- A board or clock not in the usual lists is added to them.
function setup.new(n: integer, r: integer, chunk: integer, clock: number, picks?: {Pick}): State
   local s: State = { boards = {}, clocks = {}, chunk = chunk, picks = {}, cursor = start_row() }
   for i, nr in ipairs(setup.BOARDS) do s.boards[i] = nr end
   for i, c in ipairs(setup.CLOCKS) do s.clocks[i] = c end
   s.board = find(s.boards, function(nr: {integer, integer}): boolean return nr[1] == n and nr[2] == r end)
   if not s.board then
      table.insert(s.boards, { n, r })
      table.sort(s.boards, function(x: {integer, integer}, y: {integer, integer}): boolean
         if x[1] ~= y[1] then return x[1] < y[1] end
         return x[2] < y[2]
      end)
      s.board = find(s.boards, function(nr: {integer, integer}): boolean return nr[1] == n and nr[2] == r end)
   end
   s.clock = find(s.clocks, function(c: number): boolean return c == clock end)
   if not s.clock then
      table.insert(s.clocks, clock)
      table.sort(s.clocks)
      s.clock = find(s.clocks, function(c: number): boolean return c == clock end)
   end
   for p = 1, #board.PLAYERS do
      local was = picks and picks[p]
      s.picks[p] = was and { kind = was.kind, pad = was.pad } or { kind = "bot" }
   end
   return s
end

--- What the match will be played with: the board's n and r, the chunk size
--- and the shot clock.
function setup.options(s: State): integer, integer, integer, number
   local nr = s.boards[s.board]
   return nr[1], nr[2], s.chunk, s.clocks[s.clock]
end

--- The player `kind` of controller (and `pad`, for a gamepad) sits at, if any.
function setup.seat_of(s: State, kind: controls.Kind, pad?: love.Joystick): integer
   return find(s.picks, function(pick: Pick): boolean return pick.kind == kind and pick.pad == pad end)
end

--- Sit `kind` (and `pad`) at player `p`'s home, leaving whichever home it
--- had to a bot.
local function sit(s: State, p: integer, kind: controls.Kind, pad?: love.Joystick)
   if kind ~= "bot" then
      local was = setup.seat_of(s, kind, pad)
      if was then s.picks[was] = { kind = "bot" } end
   end
   s.picks[p] = { kind = kind, pad = pad }
end

--- `pad` takes the first home a bot has. Returns the player, or nil if
--- every home is taken or it already sits at one.
function setup.join(s: State, pad: love.Joystick): integer
   if setup.seat_of(s, "pad", pad) then return nil end
   local p = setup.seat_of(s, "bot")
   if p then sit(s, p, "pad", pad) end
   return p
end

--- `kind` (and `pad`) gets up, leaving its home to a bot.
function setup.leave(s: State, kind: controls.Kind, pad?: love.Joystick)
   local p = setup.seat_of(s, kind, pad)
   if p then s.picks[p] = { kind = "bot" } end
end

--- Move the cursor `dy` rows, stopping at the top and bottom.
function setup.move(s: State, dy: integer)
   s.cursor = math.max(1, math.min(start_row(), s.cursor + dy))
end

--- Whether the cursor is on the Start row.
function setup.on_start(s: State): boolean
   return s.cursor == start_row()
end

--- Change the row under the cursor by `dx` (-1 or 1). `pads` are the
--- gamepads plugged in, for cycling who sits at a player's row: a bot, the
--- keyboard, then each gamepad.
function setup.change(s: State, dx: integer, pads: {love.Joystick})
   local row = s.cursor
   if row == BOARD_ROW then
      s.board = math.max(1, math.min(#s.boards, s.board + dx))
   elseif row == CHUNK_ROW then
      s.chunk = math.max(setup.MIN_CHUNK, math.min(setup.MAX_CHUNK, s.chunk + dx))
   elseif row == CLOCK_ROW then
      s.clock = math.max(1, math.min(#s.clocks, s.clock + dx))
   elseif row >= FIRST_PLAYER_ROW and row < start_row() then
      local p = row - FIRST_PLAYER_ROW + 1
      local who: {Pick} = { { kind = "bot" }, { kind = "keys" } }
      for _, pad in ipairs(pads) do who[#who + 1] = { kind = "pad", pad = pad } end
      local now = s.picks[p]
      local i = find(who, function(w: Pick): boolean return w.kind == now.kind and w.pad == now.pad end) or 1
      local to = who[(i - 1 + dx) % #who + 1]
      sit(s, p, to.kind, to.pad)
   end
end

--- `pad` presses A on the row under the cursor: an option steps on, a
--- player's row seats `pad` there, and Start starts. Returns whether to
--- start the match.
function setup.press(s: State, pad: love.Joystick, pads: {love.Joystick}): boolean
   local row = s.cursor
   if row == start_row() then return true end
   if row >= FIRST_PLAYER_ROW then
      sit(s, row - FIRST_PLAYER_ROW + 1, "pad", pad)
   else
      setup.change(s, 1, pads)
   end
   return false
end

--- What to call a pick on screen: `pads` numbers the gamepads.
local function pick_name(pick: Pick, pads: {love.Joystick}): string
   if pick.kind == "bot" then return "Bot" end
   if pick.kind == "keys" then return "Keyboard" end
   local i = find(pads, function(pad: love.Joystick): boolean return pad == pick.pad end)
   return i and ("Controller %d"):format(i) or "Controller"
end

--- The screen's rows, top to bottom; the cursor is on row `s.cursor`.
function setup.lines(s: State, pads: {love.Joystick}): {setup.Line}
   local n, r, chunk, clock = setup.options(s)
   local lines: {setup.Line} = {
      { label = "Board", value = ("%d-%d"):format(2 * n, r) },
      { label = "Chunk size", value = ("%d triangles"):format(chunk) },
      { label = "Shot clock", value = ("%g s"):format(clock) },
   }
   for p, pl in ipairs(board.PLAYERS) do
      lines[#lines + 1] = { label = pl.name, value = pick_name(s.picks[p], pads), color = pl.color, player = p }
   end
   lines[#lines + 1] = { label = "Start match", value = "" }
   return lines
end

return setup
