# Notched board rules: design

Date: 2026-10-01. Scope: replace the hexagon, turn A/B, neutral-wall and HP
rules with the notched-board rules described in README.md. That means the
rules engine, the bots, the LÖVE game, the README figures and the tests. This
supersedes the rules parts of `2026-09-21-core-game-design.md`.

README.md is the player-facing statement of the rules. This document records
the decisions behind it and pins down exactly what the engine computes.

## Decisions taken with the author

- **Board.** The notched hexagon from `layouts.tl`, with diameter 22 and notch
  8 by default. Both are chosen at launch (`make run DIAMETER=… NOTCH=…`) and no
  code assumes a size.
- **Homes.** Player 1 is southwest (corner 2, past walls 1 and 2), Player 2
  northwest (corner 4, walls 3 and 4) and Player 3 east (corner 0, walls 5 and
  0). The **dashed line** is the two central walls a home lies past. The **back
  wall** is the rest of the home's outline, notch edges included.
- **Placement.** A chunk must be wholly in its owner's home and on free cells,
  and at least one of its triangles must have a corner on the back wall. Any of
  the six 60° rotations is allowed. Chunks are never flipped.
- **Headings.** Each player has three, at 60c + 120°, 60c + 180° and 60c + 240°
  for their corner c (east: SW, W, NW). The author first proposed SW and NW
  only, and W was added for one reason: with only those two, the corner diamond
  (128 of east's 352 triangles, and 30 of the 44 on its back wall) could never
  fire out of the home.
- **Sliding.** A step is blocked by:
  - a triangle that isn't moving the same way, whether it is the destination or
    the triangle passed over;
  - another player's home, including a player who is out;
  - a wall.

  Your own dashed line never blocks you. A blocked chunk keeps its heading.
- **No HP and no scoring.**
- **Loss.** A player is out when either:
  - they have no legal aim at lock-in, because they ran out of time or nothing
    fits;
  - one of their triangles **standing in their own home** is stopped by a wall.

  A wall met from the middle (the notch-corner case) is only a stop.
- **Pile-blocked shots.** A shot that ends partly in its own home is legal
  buildup. The ghost shows it in amber, and it is not a loss.
- **Elimination.** Last one standing wins. The chunks of a player who is out
  stay on the board as ordinary obstacles. If everyone left goes out at the
  same moment, it's a draw.
- **Timing.** Play is continuous: an 8 s shot clock and 0.28 s ticks run at
  once, and each lock-in fires every live player's aim.
- **Ghost.**
  - It slides against chunks at rest and looks through chunks in flight and
    through the other players' aims.
  - Its look is `friendly` when any triangle's straight path stays in the home
    until it meets a wall. This is pure geometry and holds whatever is in the
    way.
  - Otherwise the look is `home` if the landing touches the player's own home,
    and `clear` if not.
  - The colours are ink, amber and red, with the aimed chunk greyed out for red.
    Ink is used instead of the owner's colour because Player 1's colour is red.
- **Engine representation.** The author's matrix: one flat, integer-indexed
  array with a frame of walls, exactly as
  `tl run layouts.tl -- --board notched-hexagon-filled --cells` labels it.
  Every lookup lands in the array and never returns nil.

## Engine semantics

### The matrix (`board.tl`)

For central side `n` and notch `r`, let `s = n + r + 1`. The matrix is the
rhombus of side 2s, made of the cells with k1 and k3 in `[-s, s-1]`. It has
`w = 4s` columns and `h = 2s` rows:

```
y = s - k1          x = b + y + s          i = (y - 1) * w + x
```

Every (x, y) in the rectangle is a cell. Odd x (and so odd i) points down;
even x points up. `kind[i]` is `WALL = -1`, `MIDDLE = 0`, or the player 1..3
whose home the cell is in. The walls are at least one strip deep everywhere, so
the step and pass-over offsets below never leave the matrix or wrap onto
another row.

| heading | name | `step[h]` | `pass[h]` for up / down |
| ------- | ---- | --------- | ----------------------- |
| 1       | E    | `+2`      | `+1` / `+1`             |
| 2       | SE   | `-w`      | `-w-1` / `+1`           |
| 3       | SW   | `-w-2`    | `-w-1` / `-1`           |
| 4       | W    | `-2`      | `-1` / `-1`             |
| 5       | NW   | `+w`      | `-1` / `+w+1`           |
| 6       | NE   | `+w+2`    | `+1` / `+w+1`           |

The edge neighbours are `i-1`, `i+1`, and `i-w-1` for an up triangle or
`i+w+1` for a down one. `touch[i]` marks a home cell sharing a lattice vertex
with a wall cell. All of these tables are built once by `board.new` from exact
Eisenstein arithmetic, and the tests pin them back to that arithmetic.

### A tick (`sim.tick`)

1. **Static pass.** For each chunk and each triangle, look at the passed-over
   cell and the destination:
   - a wall blocks, and counts as a back-wall hit when the triangle is in its
     owner's home and the owner is alive;
   - another player's home blocks;
   - anything else goes on the chunk's sweep list.
2. **Fixpoint.** This is the existing algorithm, unchanged. A chunk is blocked
   if its sweep meets a triangle that isn't moving with the same heading, or
   claims a cell a chunk with another heading also claims.
3. **Move.** Every unblocked chunk moves at once.
4. **Flags.** `moved` and `flying` are set to whether the chunk moved this
   tick. A newly fired chunk is flying until its first tick.
5. **Outs.** Players with a back-wall hit go out with reason `"friendly"`.
6. **Clears.** Same-colour triangles of different chunks that share an edge
   clear, and broken chunks split, keeping owner, heading and flags.

### Lock-in (`sim.lock_in`)

Each live player's first shot in the list is checked. It is legal when its
heading is one of theirs and its cells are a legal placement as the board
stands right now. A player with no legal shot goes out with reason `"stuck"`.
All checks happen before anything is placed. The legal shots then fire: they
are added in flight, their bank slots are refilled, and clears run.

### Bots (`bots.tl`)

A bot shuffles its 18 (chunk, rotation) options. For each it tries up to 4
random legal spots, with all three headings at every spot, and returns the
first shot whose ghost is `clear`. Failing that it takes the best it saw,
preferring `home` over `friendly`. Bots plan when the clock starts. At lock-in,
`bots.refresh` re-chooses for any bot whose plan is no longer legal.

### The game (`main.tl`, `draw.tl`)

- **Aim tracking.** Your aim remembers the spot you chose as an Eisenstein
  centroid sum. After every tick, lock-in or keypress it snaps to the nearest
  legal spot by the exact Eisenstein norm, so it stays put while chunks move and
  while you rotate.
- **Walking the back wall.** `←`/`→` move along the back wall. The spots are
  ordered counterclockwise round the board's centre by exact cross product;
  each home spans under 180°, so the order is total.
- **No legal spot.** If the selected chunk and rotation fit nowhere, they are
  outlined in red where they were.
- **Window.** The window is 1440×900 and the board is fitted to it at any size.
- **Outlines.** Silhouettes are built from shared lattice vertices. This fixes
  the old outline bug (see below).

## Modules

| File                 | Role                                                                   |
| -------------------- | ---------------------------------------------------------------------- |
| `blunkychunks.tl`    | chunk generation (unchanged), plus `rotate` and colour `CODE`s           |
| `board.tl`           | notched shape, the matrix (`board.new`), shapes and spots, options, drawing geometry |
| `src/sim.tl`         | the rules: tick, clears, splits, placements, ghost, lock-in, outcome    |
| `src/bots.tl`        | random bots that prefer clear landings                                  |
| `src/draw.tl`        | board, chunks, ghosts, arrows, panels, legend                           |
| `src/main.tl`        | LÖVE callbacks, the continuous loop, the human's aim                    |
| `render.tl`          | README figures `images/board.svg` and `images/shots.svg`                |
| `layouts.tl`         | uses `board.notched` / `board.rhombus` instead of its own copies        |
| `tests/*`            | board, sim and bots suites; headless soak                               |

## Findings from the prototype

The whole design was built and run in a scratch clone before this spec was
written. The plan's code is that clone's code.

- **Soak results.** With random bots on 22-8, every match ended after 19–22
  shot clocks, about three minutes of play. Every out was "no legal aim" (the
  bots never fire on themselves), and 2 of 8 matches were three-way draws. The
  middle jams from head-on traffic (W against E, and so on), and the homes then
  fill up behind it. 12-5 with chunks of 6 behaves the same, and 34-17 runs
  about 50 clocks.
- **Outline bug.** The old `draw.chunk` and `render.tl` silhouettes were wrong
  for every point-up triangle. The shortcut "neighbour i faces the edge opposite
  corner i" only holds for point-down cells. The new code takes each edge from
  the two lattice vertices the cells share.
- **Screenshot stalls.** A LÖVE window launched from a script with its output
  sent to `/dev/null` can stall in the background and never reach its
  `--shot` time. Pipe the output instead (`| cat`).

## Out of scope

Mouse aiming, smarter bots, sound, and the ideas listed in the README.
