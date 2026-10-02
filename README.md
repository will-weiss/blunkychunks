# Blunkychunks

## Description

A 3 player game played on a notched hexagon cut from a triangular tiling. Each
player has a home, a V-shaped lobe outside the dashed middle of the board, and
fires procedurally generated "blunkychunks" from it across the middle at the
other two.

A chunk keeps sliding until something stops it: other triangles, or an
opponent's dashed line. So chunks fired at you pile up against your dashed line,
Tetris style, and the shots you fire back can get stuck in your own home behind
that pile. Your home sits back from the middle, which leaves you some room to
dig your way out by clearing triangles of matching colours. When there is no
room left in your home to place a chunk, you are out. The last player standing
wins.

## The board

![The board: three homes around the dashed middle](images/board.svg)

The board starts as a hexagon of side 19 with three of its corners notched out.
What is left is a central hexagon of side 11 (the middle, 22 triangles across)
with three homes wrapped around alternate corners of it. Each home is a V
outside two of the middle's walls. Player 1 has the south home, its corner
pointing straight down, and Player 2 (northwest) and Player 3 (northeast)
follow clockwise.

- Your **dashed line** is the two dashed edges between your home and the
  middle.
- Your **back wall** is the rest of your home's outline: the black edge of the
  board, including the two short edges along the notches.

On the default board the middle holds 726 triangles and each home 352, 1782
in all. Other sizes work the same way: the middle's diameter (an even number of
triangles) and the notch can be set when you start the game, e.g.
`make run DIAMETER=12 NOTCH=5`. A middle of side n with notch r has 6n²
triangles in the middle and 4nr in each home. A player's colour is only a label
for their home and their chunks; it has nothing to do with the colours of the
triangles.

## Blunkychunks

A blunkychunk is a connected shape made of triangles from the tiling, each
coloured red, green or blue. No two triangles that share an edge may have the
same colour. Chunks are grown procedurally one triangle at a time from a seed,
so the same seed always yields the same chunk; the default size is 14 triangles.

![Ten sample blunkychunks](images/sample_blunkychunks.svg)

Before it is fired a chunk may be turned in 60 degree steps. Turning swaps its
point-up and point-down triangles, but it is never flipped over. Once fired it
only slides, and a slide keeps every triangle's orientation.

## Aiming

Each player has a bank of three chunks. Before your shot clock runs out you
choose:

- a chunk from your bank;
- one of its six rotations;
- one of your three headings;
- a spot for it in your home.

A spot must lie wholly inside your home, must not overlap any triangle already
there, and must touch your back wall: at least one triangle of the chunk has a
corner on it.

Your three headings point back across the board from your corner. South fires
northwest, north or northeast; northwest fires northeast, southeast or south;
northeast fires south, southwest or northwest. Straight across (north, for
south) gets out of your home from anywhere in it. Each of the other two runs
parallel to one of your dashed walls, so it only gets out from the far arm of
your V. Fired from the arm it runs along, a chunk slides down that arm into the
notch edge at its end, which is your own back wall.

You can't aim friendly fire: changing heading skips any heading that would
run the chunk into your own back wall from where it is, and if a slide,
rotation or new chunk makes the heading you chose friendly, your aim falls
back to straight across until it's safe again, then returns to your choice.

![An aim for each player and where it would land](images/shots.svg)

## The shot clock

Play is continuous. Each player has their own shot clock of 8 seconds: when
yours runs out your aim fires, and your clock starts again straight away. The
clocks are staggered a third of a clock apart, so they run out in turn, Player
1's, then Player 2's, then Player 3's, and someone fires every 2⅔ seconds.
Everyone's first clock is the full 8 seconds, plus 2⅔ for each player before
them. Chunks already on the board keep sliding the whole time. When a chunk is
fired its slot in your bank is refilled with a fresh one.

What fires is the legal shot nearest to what you were aiming: your chunk and
rotation at the spot along your back wall closest to where you put it, on your
heading unless that has become friendly fire. So a chunk sliding into your
spot just as your clock runs out moves your shot over rather than putting you
out. You are only out of moves when nothing in your bank fits anywhere.

Time is kept in whole milliseconds, and the board's ticks and everyone's
clocks happen in one fixed order: a clock running out at the same moment as a
tick goes first, and two at once go lowest player first. Player 2's first
clock is 10.666 seconds, Player 3's 13.333. The same seed and the same shots
always make the same match, on any machine and at any frame rate.

## Sliding

Every tick (0.28 seconds) each chunk takes one step along its heading. A step
is blocked by:

- a triangle that isn't moving the same way, whether it is the one the chunk
  would land on or the one it would pass over on the way;
- another player's home: chunks stop at an opponent's dashed line, including
  the dashed line of a player who is already out;
- the edge of the board.

Your own dashed line never blocks your chunks. Chunks moving the same way don't
block each other, so a convoy moves together.

When chunks moving different ways would step into the same space, landing on or
passing over the same triangle, and nothing else stops them, the one fired
first takes its step and the others wait. A convoy goes as its earliest-fired
chunk, and the pieces of a chunk that splits count as fired when it was.

A blocked chunk keeps its heading
and moves on as soon as the way clears, so when part of a pile clears, whatever
was stacked behind it slides on.

## Clearing triangles

Whenever two triangles of the same colour from different chunks share an edge,
both clear. This is checked after every tick and as soon as chunks are fired.
If a clear leaves a chunk in pieces, each piece carries on independently with
the same heading.

## The ghost

Before you fire you see a ghost of where your aim will come to rest, in its own
colours, faded. It slides against the chunks currently at rest, and looks
straight through chunks still in flight and through the other players' aims,
which can't be known yet.

On the way it clears just as the real chunk would. A **hit** is a triangle that
meets one of the same colour at rest, as it's fired or after any step: the
ghost shows it in full colour and crossed out, where the two meet. Whatever is
left slides on without it, in pieces if the hit cut it in two, and the ghost
shows where each piece comes to rest.

Its outline's colour says what will happen:

- **Ink:** it lands clear of your home.
- **Amber:** it lands with part of it still in your home, because a pile is in
  the way. That's legal: it stays there, keeps its heading, and is how your
  home fills up.
- **Red:** friendly fire. Some triangle of the chunk can never leave your home
  on this heading, so if nothing stops it for good it will hit your back wall.
  The aimed chunk is greyed out. Your own aim never shows this (see Aiming),
  but a bot with nothing else that fits may fire one.

## Losing and winning

You are out when either of these happens:

- your shot clock runs out and you have no legal aim, because you ran out of
  time or nothing fits anywhere in your home;
- one of your triangles is stopped by your own back wall.

Only your own back wall counts. At each notch corner the middle's corner
triangles can step straight into the notch, but a chunk stopped there from the
middle has just come to rest like any other.

When you are out, your chunks stay on the board as ordinary obstacles that can
still clear. The last player standing wins. If everyone still in goes out at the
same moment, it's a draw.

## Playing

The game is written in Teal and runs in LÖVE 11.4.

| Command                       | What it does                                           |
| ----------------------------- | ------------------------------------------------------ |
| `make run`                    | open the setup screen, then play (`ARGS="--play"` skips it: you as Player 1 against two bots) |
| `make bots`                   | watch three bots play each other                       |
| `make host`                   | host a networked match: the setup screen, open for others to join |
| `make join HOST=10.0.0.2`     | join one (`HOST` defaults to this machine)             |
| `make server`                 | a headless server for networked matches (no window)    |
| `make run DIAMETER=12 NOTCH=5` | play on another size of board (also for `bots`, `soak`, `images`) |
| `make run ARGS="--seed 42"`   | a reproducible match; `--fast` for a 2 second clock, `--size 8` for smaller chunks |
| `make test`                   | the rules engine's tests                               |
| `make soak`                   | whole bot matches played headless, checking the engine (`ARGS="--greedy 1"` makes Player 1 a greedyclear bot) |
| `make images`                 | redraw the figures in this README                      |
| `make dist`                   | package standalone builds for macOS, Windows and Linux into `dist/` (`make mac`, `windows`, `linux` or `love` for one) |

| Key                | Does                                |
| ------------------ | ----------------------------------- |
| `Z` / `C`          | take the chunk on the left / right of your queue |
| `Q` / `E`          | rotate counterclockwise / clockwise |
| `←` `→` or `A` `D` | slide the chunk along your back wall |
| `↑` `↓` or `Tab`   | change heading                      |
| `Space` / `Enter`  | fire now: every clock skips ahead to when yours runs out, so any due sooner fire first (watching `make bots`, `Space` skips to the next shot) |
| `+` / `-`          | slide faster / slower               |
| `R`                | new match                           |
| `Esc`              | back to the setup screen            |

A match starts from the setup screen: pick the board's diameter and personal
area (the notch), the chunk size and shot clock, each a step of one (the
diameter, always even, steps by two), whether a controller's flick fires at
once or waits for the shot clock, and who plays each home. Every controller shares one cursor: `↑` `↓`
choose a row, `←` `→` change it (on a player's row, cycling between the two
kinds of bot, the keyboard and each plugged-in gamepad), and `Enter` starts the match (`Esc`
quits). Any gamepad drives the same cursor with its D-pad or stick, seated or
not, and `A` selects the row: it steps an option on, sits that gamepad at a
player's row, or starts the match from Start. A gamepad can also press `Start`
to take the first home a bot has, `Start` again to begin, and `B` or `Back` to
give the home back.

There are two kinds of bot. A plain **Bot** tries a few random shots and
takes the first that lands clear of its home. A **Greedyclear bot** tries
every chunk, rotation, spot and heading it has, and takes the shot that
clears the most triangles from its own home; between equals, the one that
clears the most triangles in all. Neither fires a shot that would hit its own
back wall unless nothing else fits.

Gamepads can play during a match too, as many as there are bots to take over: press `Start`
on one to take the first bot's home, and `Back` (or unplugging it) hands that
home back to a bot. The legend at the top right of the screen lists the keys
and buttons for every controller in play.

Your queue sits under the board: the chunk you're aiming is on the board, and
the other two in your bank are shown either side of it, full size and turned
as you have it. Taking the left or right one puts the one you were aiming on
the other side, so the three cycle round. Nobody else's bank is shown.

| Button               | Does                                 |
| -------------------- | ------------------------------------ |
| `LB` / `RB`          | take the chunk on the left / right of your queue |
| right stick, round   | rotate the way you turn it           |
| left stick at your home | place the chunk there             |
| left stick flicked across | pick a heading, and fire (see below) |
| D-pad ← →            | slide the chunk along your back wall |
| D-pad ↑ ↓            | change heading                       |
| `A`                  | fire now                             |
| `Start` / `Back`     | join / leave                         |

Holding a slide (on the keyboard or the D-pad), or `Q` / `E`, keeps it going.

The left stick places and fires. It is read as the board is drawn, so for
Player 1 down is towards their home and up is across the board; for the
others it's turned round to their corner. Whichever half of the stick it
points into decides what it does. In the half facing your home (within 90°
of your corner) it places: its angle sets where the chunk sits along your
back wall, one end of your V at one edge of that half and the other end at
the other. Let go and the chunk stays where you put it. In the half facing
across the board it aims and leaves the chunk be: within 30° of straight
across picks straight across, and further round either side picks the side
heading that way. Swing back into your home's half and you are placing
again. Letting the stick go back to the middle while aiming is the
**flick**. On the setup screen, *Controller flick* says what it does: it
either fires at once, as `A` does, or just sets the heading and waits for
your shot clock. The right stick can rotate the chunk the whole time. A
flick at a heading that would be friendly fire from where the chunk is falls
back to straight across, as changing heading does.

The right stick is a dial. Push it out anywhere and that's the anchor; turn it
round from there and the chunk rotates the same way. The first 10° gives one
rotation, and after that it snaps to the nearest 60° (89° is one rotation,
91° is two). Turning back undoes them, though only 3° past each mark, so a
stick resting on one doesn't flicker. Letting the stick go drops the
anchor.

## Playing over a network

Up to three people on different machines can play one match. Pick
**Play: host for others to join** on the setup screen (or `make host`) and it
shows an address like `192.168.1.20:47419`. Everyone else picks
**Play: join someone's match**, types that address in and joins. Each newcomer
takes the first home a bot has, and the host's screen shows them by name. The
host sets the options and the bots and starts the match. On the lobby screen a
joiner can move to another free home (`Enter`, or `A` on a gamepad), give it
back (`Backspace`, or `B`) or just watch. Several controllers on one machine
can each take a home.

Every machine plays its own copy of the match. The only things sent are the
shots, each one as its player's shot clock runs out. Until then nobody else
knows what you're aiming, not even which chunk. Bots run on the host, so
their aims are as hidden as anyone's.

A few things work differently from a match on one machine:

- **Firing now is a vote.** `Space`, `Enter`, `A` (and a flick, if
  *Controller flick* fires at once) mark you **ready**. You can keep changing
  your aim, and pressing again takes the vote back. Once every player still in
  is ready, the clocks skip ahead to the soonest of their clocks, firing any
  bot due before it. Bots never hold up the vote.
- **The host runs the match.** Only the host can change the slide speed
  (`+` / `-`), start another match (`R`), or take everyone back to the lobby
  (`Esc`). Anyone else's `Esc` leaves.
- **Your shot clock runs out a moment before your board catches up.** Each
  copy runs slightly behind the host, about half the round trip plus 60 ms,
  so every shot has arrived before it's needed. Your clock is shown against
  the host's, so what you see is when your shot really goes.
- **Leaving hands your home to a bot**, and anyone can join a match under way
  and take a bot's home. A late joiner first catches up from the shots so far.

`make server` runs a server with no game of its own, for a machine everyone
can reach. Its options come from the command line (`DIAMETER`, `NOTCH`,
`ARGS="--size 8 --clock 6 --port 47419"`), and the first to join runs it from
the lobby screen. The game uses UDP port 47419 (`--port` changes it). Across
the internet, the host needs that port forwarded to their machine.

## Ideas

- Lean into the tetris-like quality and control the pieces as they go? If we do
  this then probably the pieces only need to be launched from exactly your side
- Defenses = singleton triangles of your color that your blunkychunks can pass
  through, but others cannot (without clearing them properly). You start the
  game with some and periodically get more that you can place directly onto the
  board on your turn (on your part of the playing field)
- Leaning further into the rotation quality with changing colors
- Having your player color mean something (so your blunkychunks are weighted to
  have more of other people's )
- If a blunkychunk "splits" perhaps it goes in the two other 60deg different
  directions. So if the blunkychunk was originally going east and it splits then
  the upper half starts going northeast and the lower half southeast.
- Points system? Combos for bigger groups and/or perfect fits?
- Theme related to elements with red = fire, earth = green, blue = water. These
  could rotate?
- Monks? Trunks? Junk? Sunk?
