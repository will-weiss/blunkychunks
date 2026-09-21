# Core game in LÖVE — design

Date: 2026-09-21. Scope: a playable Blunkychunks match in LÖVE 11.4 with three
random bots and no human input. All code is Teal (`.tl`) compiled to Lua 5.1.

## Decisions taken with the author

- **Wall hits consume triangles.** Each triangle that crosses an opponent's
  wall is removed, costs the defender 1 HP and gives the original firer 1 HP.
  The rest of the chunk keeps sliding, so an unblocked chunk deals its full
  size in damage.
- **Loan-wall shots are interceptors.** Geometry forces a shot from a loaned
  neutral wall to land on the neutral wall two steps around. Triangles that
  leave through a neutral wall vanish with no HP change.

## Assumptions (not spelled out in Rules.md)

- A bank holds 3 chunks; firing one replaces it with a fresh one.
- Bots choose at the start of the 8 second placement phase; choices show as
  ghosts until lock-in. Bots place in random order and cannot overlap each
  other or chunks already on the board. A bot whose chosen chunk fits nowhere
  on the chosen wall tries its other options and passes if nothing fits.
- A slide tick advances every chunk on the board one lattice step (`side`
  length, one of the six 60° headings). A step is blocked when the swept cells
  (the triangle passed through plus the destination) hold a triangle of a
  chunk that is not moving the same way. Blocked chunks keep their heading and
  retry every tick, including in later turns.
- After each tick, every pair of edge-adjacent same-colour triangles from
  different chunks clears (both go). A chunk whose cells become disconnected
  splits into independent chunks with the same heading and owner.
- The sliding phase ends when a tick moves nothing; the next turn's placement
  phase then begins with the sweep direction flipped.
- HP starts at 10. A player wins when both opponents are at or below 0.
  Everyone at or below 0 is not a win; play continues.

## Exactness

All rules logic is integer arithmetic on Eisenstein coordinates (a, b). The
hexagon is the set of cells whose three strip coordinates
`floor((2a-b)/3)-1`, `floor(-(a+b)/3)`, `floor((2b-a)/3)` all lie in
`[-n, n-1]`; depth toward a wall is one of those coordinates with a sign; the
per-tick step is a lookup into the six unit translations; the cell a sliding
triangle passes over is the common neighbour of start and destination.
Anything mentioning `side`, `sqrt(3)` or a normal vector is drawing only.

## Finding: stalemates

With random bots, 7 of the first 10 seeds jam between rounds 10 and 18: blocked
chunks pile up faster than colour clears remove them, until no bank chunk fits
flush against any legal wall and every player passes. The game detects this
(no shots and the previous slide moved nothing) and shows a stalemate screen.
The other 3 seeds ended with a winner inside 2 to 15 rounds, because an
unblocked 14-chunk deals 14 damage. Both dynamics are rules questions for the
author, not engine bugs.

## Modules

| File | Role |
|------|------|
| `blunkychunks.tl` | (existing) cells, neighbours, chunk generation |
| `board.tl` | (existing) hexagon, walls, headings, placement. Gains `step` and `placements` |
| `src/sim.tl` | pure rules engine: state, firing, tick, clears, splits, HP |
| `src/bots.tl` | random strategy over the legal options |
| `src/draw.tl` | rendering of board, chunks, ghosts, HP and banks |
| `src/main.tl` | LÖVE callbacks and the placing → sliding → over state machine |
| `src/conf.tl` | window config |
| `types/love.d.tl` | the slice of the LÖVE API used, for `tl check` |
| `tests/*.tl` | rules-engine tests run with `tl run tests/run.tl` |

## Controls

Space skips the countdown. `+`/`-` change slide speed. `R` restarts. Escape quits.
