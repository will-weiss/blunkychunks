# Networked Play: Options and Plan

**Status:** built (2026-10-02) on branch `networking`. The decisions are
recorded in [Decisions](#decisions), with what each alternative would take,
and [As built](#as-built) maps the design to the code. The README's
*Playing over a network* section is the player-facing version.

**Goal:** three people on three machines play one match. Every client keeps its
own full copy of the match and simulates it. The network carries only **moves**,
and a move is only announced once it is public. Your aim stays private until
your shot clock runs out.

---

## 1. What is public and what is private

The game suits this model well. Between two shot clocks the match is fully
deterministic: chunks slide, clear and split by integer rules with no inputs.
The only inputs are the **shots**, one per live player per shot clock (one every
2⅔ s on the default clock).

| Information | Who knows it | When it is announced |
| --- | --- | --- |
| Board size, notch, chunk size, shot clock, match seed | everyone | at match start |
| Chunks on the board, their headings, clears, splits | everyone, by simulating | never sent; derived |
| Shot clocks (when each player fires) | everyone, by simulating | never sent; derived |
| Who is out by friendly fire | everyone, by simulating | never sent; derived |
| A fired shot: player, cells, heading (and slot) | everyone | the moment that player's clock runs out |
| Out for having no legal aim ("stuck") | everyone | the same moment, instead of a shot |
| **Your aim**: slot, rotation, heading, spot | you (and the server, see §4) | when it fires, as the shot |
| **Your bank** (the 3 chunks you can pick from) | *Decision D1* | public, or only as each one is fired |
| The ghost of your aim | you | never; each client computes its own |

The panels currently draw every player's aim, including the bots'. In network
play a client draws only its own seats' aims. Others show clock and status, and
their bank only if D1 makes banks public.

**No reason to send late.** When P1's clock runs out, nothing P2 or P3 will do
has been revealed, and P1's client already knows the board at that moment. So
holding back a shot gains nothing. Only shots are hidden, and each one stops
being hidden at the moment it matters. That is why "announce moves only" works
without commit-reveal cryptography.

---

## 2. What has to change before any networking (determinism)

Two clients given the same seed and the same shots must produce bit-identical
states. Today that isn't guaranteed. These are bugs to fix whatever networking
option we pick, and they can be tested headless:

1. **Fires and ticks interleave by frame timing.** `love.update` runs
   `run_clocks(g, dt)` and then ticks. The clocks are float seconds and the tick
   accumulator depends on `dt`, so whether a shot lands before or after a given
   tick depends on the frame rate. **Fix:** an integer millisecond timeline.
   Ticks fall at `k * 280` ms. Shot clocks run out at integer ms (the stagger
   rounds: 8000, 10667, 13333). When a shot and a tick fall on the same ms, the
   shot goes first, which is what happens now within a frame. One `sim.advance(state, to_ms, verdicts)`
   drives both.
2. **Bots and banks share one RNG** (`state.rng`). `bots.choose` shuffles with
   it, so a bot planning on one client would change everyone's next chunks.
   **Fix:** separate streams. Banks get one stream per player, seeded from the
   match seed (or privately, D1). Bots get their own local stream that is never
   part of the state.
3. **Split order depends on `pairs`.** `remove_cells` walks `pairs(gone)`, and
   the order of `touched` decides which pieces get which new chunk ids. Ids break
   ties in the tick's fire order. LuaJIT's integer hashing is stable in practice,
   but "in practice" isn't enough. **Fix:** sort `touched` by id.
4. **Aims are made legal in UI code.** `controls.refresh_aim` hops your aim to
   the nearest legal spot every tick and falls back from a friendly heading. Over
   the network your client sees the board slightly late (§3), so the spot you
   aimed at can become illegal in the last ~100 ms. Today that would put you out
   as "stuck". **Fix:** move this into the rules as
   `sim.settle(state, p, intent) -> Shot`. An *intent* is `{slot, turn,
   prefer_heading, want}`, where `want` is the integer `(a, b)` centre the aim is
   trying to stay near, as `controls` already keeps it. Lock-in settles the
   intent against the true state at the deadline. Every client and the server
   reach the same cells, and local play keeps behaving as it does now.
5. **Speed `+`/`-` changes the tick length mid-match.** In network play it
   becomes a match option chosen on the setup screen. Changing it mid-match is
   off.
6. **A state hash.** `sim.hash(state)` is FNV-1a over `occ`, `paint`, chunk
   headings and `alive`, all integers. It's used for desync checks and tests.
7. **A match log.** `{config, seed, verdicts = {ms, player, shot | "stuck"}}`.
   Replaying a log reproduces the match exactly. It is the save format, the
   reconnect mechanism and the best test oracle.

After this, `main.tl`'s loop becomes a thin driver around a new `src/match.tl`
that owns the timeline, clocks and verdicts. Local play feeds it verdicts from
local seats, and network play feeds it verdicts from the server.

---

## 3. Keeping time

Each client runs the match at **server time minus a small delay**. The delay
starts at about one-way latency plus 60 ms. The client also **never simulates
past a deadline whose verdict it hasn't received yet.** Every deadline is known
in advance, because shot clocks are derived state. So "do I have the verdict for
P2 at 13 333 ms?" is a simple lookup, and stalling is the only safeguard needed.

- With 280 ms ticks, a verdict arriving up to ~140 ms late on average needs no
  stall at all. It only has to arrive before the next tick.
- Clock sync: on connect, and every few seconds after, the client pings and
  keeps the minimum-RTT sample (NTP-style). Then
  `server_now ≈ local_now + offset`.
- **Your own clock is drawn against server time.** It reaches zero when the
  server locks your aim, so it runs out `delay` earlier than the board you're
  looking at catches up. `sim.settle` (§2.4) keeps that gap from costing you a
  shot.

**Options considered:**

| Option | Verdict |
| --- | --- |
| **Delayed lockstep on shots, stall if missing** (above) | **Recommended.** Simple. Inputs come every 2⅔ s, so stalls are rare and short. |
| Rollback: run in real time, guess "no shot", rewind when it arrives | Works, since copying the state is cheap, but a guessed "no shot" is always wrong at a deadline. Every shot would arrive as a correction a step or two in. More complexity for no visible gain at 280 ms ticks. |
| Server streams snapshots, clients only render | Not what was asked. It also needs ~1782 cells × 20 Hz, or a delta format. Kept only as a fallback for resync (§6). |
| Client sends its shot at its own local deadline; server waits for it | The whole table waits on the slowest player, and the server has to pick a timeout. Worse than the server owning the deadline. |

---

## 4. Who is the server

The server's job is small: own the clock, collect each player's latest aim
intent privately, and at each deadline announce the shot (or "stuck").

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| **A. Listen server in the host's game** | One player picks *Host* on the setup screen. The game runs the server module in-process and also plays as a normal client. | No infrastructure. Same binary. LAN play just works. | The host's process holds everyone's intents, so a host could cheat by reading memory. Internet play needs the host to forward a UDP port. |
| **B. Headless dedicated server** | The same server module run with `love build --server` (a `conf.lua` with no window or graphics), on a VPS or someone's machine. | Neutral and authoritative. Runs the exact same LuaJIT and sim as the clients. Validates shots. Internet play without port forwarding. | Something has to be hosted (a tiny VPS or fly.io UDP). |
| C. Dumb relay | The server only timestamps and forwards. Clients settle intents themselves. | Tiny. Could be written in any language. | Can't validate anything. Can't keep banks private (D1). The relay still has to own deadlines, so it's barely simpler than A/B. |
| D. Pure P2P mesh | Each client broadcasts its own shot. | No server. | Nobody arbitrates "was it on time?". Three clocks disagree. Rejected. |

**Recommendation: A and B are one module.** `src/net/server.tl` runs the sim
like any client (it's cheap), plus the clocks, the bots, the bank seeds and the
intents. The game embeds it for *Host* (A). `--server` runs it headless (B).
Build A first; B is an afternoon after that.

**Bots** run on the server, so their aims are as private as anyone's. They
choose against the true state at the deadline, exactly as they do locally.

---

## 5. Transport and protocol

**Transport: ENet** (`require "enet"`), which ships inside LÖVE 11.4. It gives
reliable, ordered channels over UDP and connection handling, so there's nothing
to vendor. We need a `types/enet.d.tl` declaration for the parts we use. The
alternatives are luasocket TCP (also bundled, but head-of-line blocking and we'd
write our own framing) and WebSockets (a pure-Lua library to vendor, only worth
it for a browser build). Both lose to ENet.

**Encoding:** a small hand-written serializer for flat tables of integers and
strings in `src/net/wire.tl`. Messages are tiny. A shot is about 14 cell indices.

**Messages** (channel 0 reliable-ordered; pings unsequenced):

| Direction | Message | Contents |
| --- | --- | --- |
| C→S | `hello` | protocol version, name |
| S→C | `welcome` | your client id, lobby seats |
| C→S | `sit` / `stand` | home `p`, local controller kind |
| S→C | `seats` | who is at each home (remote / bot / free) |
| S→C | `start` | config (n, r, chunk size, clock ms, tick ms), public seed, start server-ms |
| S→C | `bank` | *(private banks only, to the owner)* slot, new chunk |
| C→S | `aim` | intent `{slot, turn, prefer, want}`, sent on change and throttled to ~20 Hz. **Only ever goes to the server.** |
| C→S | `ready` | "fire now" in network play (D2) |
| S→C | `verdict` | deadline ms, player, then `{slot, heading, cells}` or `stuck` |
| S→C | `skip` | *(only if D2 keeps the time skip)* at ms, to ms |
| C↔S | `ping` / `pong` | for clock sync |
| C→S | `hash` | ms, `sim.hash`, every ~2 s |
| S→C | `log` | the full match log, for joining late or reconnecting |
| S→C | `over` | winner or draw |

A verdict carries the settled cells, not the intent. Clients check it with
`sim.legal` and the bank shape (if they know it) before applying it. A failed
check is a desync, handled by §6.

---

## 6. Joining, reconnecting, desyncs

- **Late join / reconnect / spectate:** the server sends the `log`. The client
  replays it headless up to `server_now - delay` (a few thousand ticks take
  milliseconds) and carries on. No snapshot format needed.
- **Desync:** clients send `hash` every ~2 s, and the server compares it with
  its own. On a mismatch the server sends `log` again and the client rebuilds.
  If that keeps happening it's a bug, so the server logs both states.
- **Disconnect mid-match:** the seat passes to a bot (as `Back` does for a
  gamepad today), and the player can reclaim it on reconnect.

---

## 7. Rules and UI decisions

### D1. Are banks public?

- **Public** (default today: everyone sees every bank). Bank streams come from
  the match seed, so every client generates every bank. Opponents know your
  three candidates but not which one, its rotation, heading or spot.
- **Private.** Each player's bank stream is seeded with a secret only the server
  and that player know. The server sends your new chunk to you only. Others see
  your chunk when its verdict arrives, and the cells in the verdict are all they
  need. Panels show other players' banks as three blank slots. Option C can't
  validate this.

**Recommendation: private.** "What I'm about to fire is private" reads naturally
as including the candidates, and it costs one extra message per shot.

### D2. What does "Fire now" (`Space`) do over the network?

Today it skips *every* clock ahead. Over the network, one player could then cut
the other two's thinking time.

- **a. Ready, skip when all are ready.** `Space` locks your current intent (you
  can still change it until your deadline, or not, see D3). When every live
  *human* is ready, the server sends `skip` to the next deadline. With bots only
  in the other seats, it behaves like today.
- **b. Off in network play.** The clocks just run.
- **c. As today.** Any player skips everyone. Simple, but griefable.

**Recommendation: a.** It keeps the pace up when everyone's ready, and nobody
loses time they wanted.

### D3. Can you change your aim after pressing Ready?

Recommendation: yes. Ready is only a vote to skip, and the shot is whatever your
intent is at the deadline.

### D4. Mid-match options

`+`/`-` speed and `R` new match become host-only, or setup-screen-only. **Recommendation:**
speed is a setup option, `R` is host-only, `Esc` leaves the match.

---

## 8. Setup screen

A new first row, **Play: here / host / join**.

- **here:** today's screen, unchanged.
- **host:** shows your address and port (default 47419). A home's row gains a
  fourth kind, *remote*, filled when someone joins and sits. You start the match.
- **join:** an address field, then the host's lobby read-only, except that you
  can sit your keyboard or gamepads at free homes. One client may have several
  local seats, e.g. two gamepads on one machine.

`controls.Seat.kind` gains `"remote"`: a seat with no local aim, drawn without
its bank and aim.

---

## 9. Phased plan

Each phase ends in something that runs and has tests. Phase 1 ships even if
networking never does: it makes `--seed` replays exact and fixes three
latent bugs.

1. **Determinism and the match driver (no networking).** Integer ms timeline,
   RNG streams, sorted splits, `sim.settle`, `sim.hash`, the match log and
   replay, and `src/match.tl` extracted from `main.tl`. Tests: replaying a log
   matches live play by hash; frame rate doesn't change a match (the same seed
   driven with `dt` = 1/30 vs 1/144 vs random ends in the same hash); the soak
   test also checks replay.
2. **Server and client over a fake transport.** `src/net/server.tl`,
   `src/net/client.tl`, `src/net/wire.tl`, plus an in-memory transport with
   adjustable latency, jitter and loss (ENet is reliable, so loss shows up as
   delay). Tests: three clients plus a server in one process, 0–300 ms random
   latency, every client's hash agrees at every deadline; no client ever
   receives another's intent or private bank (a test spies on every message).
3. **ENet transport and host/join** on the setup screen. Manual check: three
   `love` windows on one Mac via `127.0.0.1`, then two machines on a LAN.
4. **Headless server** (`make server`, `love build --server`). `make dist`
   works unchanged.
5. **Reconnect, late join, desync recovery** from §6.
6. **Later, if wanted:** LAN discovery (UDP broadcast), a hosted server, a
   lobby list, names.

Estimated size: phase 1 is the largest. It touches `sim.tl`, `bots.tl`,
`controls.tl` and `main.tl`, and adds `match.tl` (~400 lines changed or added). Phases 2–3 add
~700 lines under `src/net/`.

---

## 10. Risks

- **Cross-platform determinism.** Everything is integer, on doubles under 2^53,
  and the same LuaJIT build ships everywhere. The remaining risk is iteration
  order, and fixing item 3 plus the `hash` checks covers it.
- **The aim lands slightly early** (by `delay`, ~50–150 ms). `sim.settle` keeps
  it from putting you out, but the last tenth of a second of input before your
  clock hits zero may not count. The clock is drawn against server time, so what
  you see is honest.
- **The host can read intents** in option A. That's fine among friends. Use B
  for anything else.
- **UDP port forwarding** for internet play under option A. B avoids it.

---

## Decisions

Chosen 2026-10-02. D1–D3 were Will's calls. D4–D7 went with the
recommendation, except where noted.

### D1. Banks: **public** (chosen) / private

**Chosen: public.** Every client deals every bank from the match seed
(`sim.State.rng`, consumed only by `sim.fire`), so banks are part of the shared
state and `sim.hash` covers them. Opponents *could* know your three chunks. The
panels don't show them (only your own queue is drawn), but a modified client
could. What stays private is the aim: which slot, rotation, heading and spot.

**To switch to private:** give each player their own bank stream seeded with a
per-player secret the server keeps (`sim.new` takes one rng; make it one per
player). Send each new chunk to its owner only (a `bank` message). Take other
players' banks out of `sim.hash` and out of the state on clients: they only
ever need a shot's cells, which the `shot` verdict already carries. The server
already validates shots against its own copy, so nothing else changes.

### D2. Firing now online: **ready vote** (chosen) / off / skip as local

**Chosen: a ready vote.** `fire`, or `flick` when flicks fire, sends
`ready{p, on}`. The server broadcasts it for the panels. When every live
*human* seat is ready, the server calls `match.skip` to the soonest of their
clocks and announces `skip{ms, p}`. Bots never hold up the vote. A player's
ready clears when they fire.

**Alternatives:** *off*: drop the `ready` handler in `server.tl`, and
`seat_action` in `main.tl` does nothing online. *Skip as local*: skip on any
one player's `ready` (`vote` stops requiring all), which is griefable.

### D3. Changing your aim after Ready: **yes** (chosen)

Ready is only a vote. Intents keep streaming, and the shot is whatever the
intent is at the deadline. Pressing fire again takes the vote back.
**Alternative:** freeze the intent on ready. Ignore `aim` from a ready player
in `server.tl`, and lock the seat's aim in `controls`.

### D4. Mid-match options: speed **host-only live** (changed), `R` host-only

**Changed from the recommendation** ("speed as a setup option"): `+`/`-` stay
live for the owner and go out as `step{ms, step}` timeline events. It's the
same mechanism as `skip`, so it cost nothing and keeps local play's keys
unchanged. `R` (`again`) and `Esc` (`lobby`) are owner-only, and anyone
else's `Esc` leaves. **Alternative:** a *Slide step* row on the setup screen
feeding `server.Config.step` (already in the config and the `start` message),
with the owner's `step` message removed.

### D5. Server: listen server + headless, **one module** (chosen)

`server.tl` runs inside the host's game (`netplay.host`: an ENet server, plus
this game as its first client holding the owner token) or headless
(`--server`, `make server`: the first client to join owns it). **Alternatives
not built:** a dumb relay (C) or pure P2P (D), both rejected in §4.

### D6. Time sync: **delayed lockstep, stall if missing** (chosen)

As §3, with one addition: the server also sends `at{ms}`, "nothing more is
coming before this". A client never plays past it, so a `skip` or `step`,
which can't be predicted the way shot clocks can, is never missed. A client
plays to `min(server_now - (rtt/2 + 60), through)`. **Alternative:** rollback,
rejected in §3.

### D7. Determinism first: **yes** (chosen)

Phase 1 (match.tl, settle, RNG split, sorted splits, hash, replay) landed
first, and every networking piece builds on it.

## As built

| Piece | File | Notes |
| --- | --- | --- |
| Integer-ms timeline, `advance` / `skip` / `set_step` | `src/match.tl` | Replaces `sim.clocks` / `sim.run_down`. Ties: clock before tick, lower player first. |
| `settle`, `spots`, `centre`, `hash`, `think` rng, sorted splits | `src/sim.tl` | `controls.refresh_aim` and `controls.shot` now go through `sim.settle`. |
| Bots think with `state.think` | `src/bots.tl` | Never touches the bank stream. |
| Wire format | `src/wire.tl` | Hand-written, never `load`s, rejects anything malformed. |
| Transport interface + in-memory hub | `src/link.tl` | The hub keeps FIFO order under random delay, and can spy on messages for tests. |
| ENet transport | `src/enetlink.tl` | LÖVE only. Reliable channel 0. |
| Server | `src/server.tl` | Lobby, owner, intents, bots, verdicts, ready vote, hash check and resync, late join via log. |
| Client | `src/client.tl` | Clock sync (best of 8 pings), timeline queue, stalls, hash every 16 ticks. |
| LÖVE glue | `src/netplay.tl`, `src/main.tl`, `src/setup.tl`, `src/draw.tl`, `src/conf.tl` | Play row (here / host / join), address row, remote seats, lobby screen, `--host`, `--join`, `--server`, `--port`. |

**Messages as built:** client to server: `hello`, `sit`, `stand`, `aim`,
`ready`, `ping`, `hash`, and from the owner only `config`, `start`, `again`,
`lobby`, `step`. Server to client: `welcome`, `refuse`, `owner`, `lobby`,
`start` (config, seed, start time, full log, `through`), `shot`, `skip`,
`step`, `at`, `ready`, `pong`. `tests/net_test.tl` checks that no client is
ever sent anything outside that list.

**Tests:** `tests/match_test.tl` covers ordering, skips, stalls, frame-rate
independence and replay. `tests/net_test.tl` runs three clients over a
0–150 ms jittery hub and checks that every copy agrees to the hash and tick,
that no aims leak, the vote, a late joiner, desync recovery, a player leaving,
owner-only actions, a speed change and a version mismatch. `tests/wire_test.tl`
covers the encoding. `make soak` replays every match from its shots and checks
the hash.

**Checked by hand:** under LÖVE (LuaJIT) over real UDP on localhost:
headless server plus clients agreeing on the hash at the end, the GUI joining
a headless server, and the host's setup screen showing a network joiner.
Not yet tried across two machines or over the internet.
