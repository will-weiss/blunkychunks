--- The server for a networked match. It keeps the lobby (the options and who
--- sits at each home), owns the match's clock and plays the match itself,
--- like every client does. It only ever tells the clients:
---
---   * the shots, each as its player's shot clock runs out (`shot`), and who
---     was out for having nothing to fire;
---   * the ready vote's skips (`skip`) and slide speed changes (`step`);
---   * how far the match has got (`at`), so clients know nothing else is
---     coming before then.
---
--- Everything else every client works out for itself. What each player is
--- aiming (`aim`, their sim.Intent) only ever comes to the server, which
--- settles it against the board when their clock runs out. The bots play here
--- too, so their aims are as private as anyone's.
---
--- One client is the owner: the host's own game, or for a headless server the
--- first to connect. Only the owner changes the options, starts a match,
--- starts another, takes everyone back to the lobby or changes the speed.
---
--- Nothing here touches LOVE; the link (link.tl) carries the messages and
--- `now` tells the time, so tests run it under plain Lua.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local match = require("match")
local bots = require("bots")
local controls = require("controls")
local link = require("link")
local wire = require("wire")

local type Msg = wire.Msg

local record server
   --- The match's options.
   record Config
      n: integer
      r: integer
      size: integer
      clock: integer -- ms per shot clock
      step: integer -- ms per tick
      flick: boolean -- whether a gamepad's flick votes ready at once
   end

   --- Who sits at a home: a bot (with its brain), or a client's controller
   --- (`slot` names it on that client, e.g. "keys" or "pad2").
   record Seat
      kind: string -- "bot" or "human"
      brain: bots.Brain
      client: integer
      slot: string
      name: string
   end

   record Peer
      id: integer
      name: string
      owner: boolean
      hello: boolean
   end

   record Server
      link: link.Link
      now: function(): number
      token: string -- a client saying this in its hello is the owner
      log_line: function(string)
      peers: {integer: Peer}
      config: Config
      seats: {Seat}
      seed: integer

      running: boolean
      state: sim.State
      m: match.Match
      t0: number -- server ms the match started
      hooks: match.Hooks
      bot_seats: {integer: controls.Seat}
      intents: {integer: sim.Intent}
      ready: {integer: boolean}
      log: {Msg} -- every shot, skip and step so far, for a late joiner
      hashes: {integer: integer} -- per tick, recent ones
      said_at: integer -- the last `at` sent
      said_ticks: integer
   end

   PROTOCOL: integer
   PORT: integer
end

local type Server = server.Server
local type Seat = server.Seat

server.PROTOCOL = 1
server.PORT = 47419

local HASH_KEEP <const> = 400

--- A server on `link`, telling the time with `now` (ms), with the match
--- options `config`. A client whose hello carries `token` is the owner; with
--- no token the first client to connect is.
function server.new(l: link.Link, now: (function(): number), config: server.Config, token?: string, seed?: integer): Server
   local seats: {Seat} = {}
   for p = 1, #board.PLAYERS do seats[p] = { kind = "bot", brain = "random" } end
   return {
      link = l,
      now = now,
      token = token,
      log_line = function() end,
      peers = {},
      config = config,
      seats = seats,
      seed = seed or math.floor(now()) % 1000000 + 1,
      running = false,
      said_at = 0,
      said_ticks = 0,
   }
end

local function send(srv: Server, peer: integer, msg: Msg)
   srv.link.send(peer, wire.encode(msg))
end

local function broadcast(srv: Server, msg: Msg)
   local data = wire.encode(msg)
   for id, peer in pairs(srv.peers) do
      if peer.hello then srv.link.send(id, data) end
   end
end

--- What a timeline message is, recorded for late joiners as it's sent.
local function announce(srv: Server, msg: Msg)
   srv.log[#srv.log + 1] = msg
   broadcast(srv, msg)
end

local function lobby_msg(srv: Server): Msg
   local seats: {Msg} = {}
   for p, seat in ipairs(srv.seats) do
      seats[p] = { kind = seat.kind, brain = seat.brain, client = seat.client, slot = seat.slot, name = seat.name }
   end
   local c = srv.config
   return {
      t = "lobby", n = c.n, r = c.r, size = c.size, clock = c.clock, step = c.step, flick = c.flick,
      running = srv.running, seats = seats,
   }
end

local function start_msg(srv: Server): Msg
   local c = srv.config
   return {
      t = "start", seed = srv.seed, n = c.n, r = c.r, size = c.size, clock = c.clock, step = c.step,
      flick = c.flick, at = math.floor(srv.t0), log = srv.log, through = srv.m.now,
   }
end

local function tell_lobby(srv: Server)
   broadcast(srv, lobby_msg(srv))
end

local function human(seat: Seat): boolean
   return seat.kind == "human"
end

--- The default aim of a player who hasn't said: the first chunk, straight
--- across, the middle spot.
local function default_intent(): sim.Intent
   return { slot = 1, turn = 0, prefer = 2 }
end

--- Player `p`'s shot as their clock runs out, announced to everyone.
local function decide(srv: Server, p: integer, k: integer): boolean, sim.Shot
   local state = srv.state
   local shot: sim.Shot
   if human(srv.seats[p]) then
      shot = sim.settle(state, p, srv.intents[p] or default_intent()).shot
   else
      local seat = srv.bot_seats[p]
      if not seat then
         seat = controls.bot(state, p, srv.seats[p].brain)
         srv.bot_seats[p] = seat
      end
      shot = controls.shot(state, seat)
   end
   local msg: Msg = { t = "shot", p = p, k = k }
   if shot then
      local cells: {integer} = {}
      for _, c in ipairs(shot.cells) do
         cells[#cells + 1] = c.i
         cells[#cells + 1] = bc.CODE[c.color]
      end
      msg.slot, msg.heading, msg.cells = shot.slot, shot.heading, cells
   end
   announce(srv, msg)
   return true, shot
end

local function locked(srv: Server, p: integer, r: sim.LockResult)
   srv.ready[p] = nil
   local seat = srv.bot_seats[p]
   if seat and not human(srv.seats[p]) then controls.fired(srv.state, seat, r) end
end

local function ticked(srv: Server)
   local m = srv.m
   srv.hashes[m.ticks] = sim.hash(srv.state)
   srv.hashes[m.ticks - HASH_KEEP] = nil
end

--- Start a match with the lobby as it is.
local function start(srv: Server)
   local c = srv.config
   local state = sim.new(board.new(c.n, c.r), c.size, bc.seeded_random(srv.seed), bc.seeded_random(srv.seed + 7919))
   srv.state = state
   srv.m = match.new(state, c.clock, c.step)
   srv.t0 = srv.now()
   srv.running = true
   srv.bot_seats, srv.intents, srv.ready, srv.log, srv.hashes = {}, {}, {}, {}, {}
   srv.said_at, srv.said_ticks = 0, 0
   srv.hooks = {
      decide = function(p: integer, k: integer): boolean, sim.Shot return decide(srv, p, k) end,
      locked = function(p: integer, r: sim.LockResult) locked(srv, p, r) end,
      ticked = function() ticked(srv) end,
   }
   for p, seat in ipairs(srv.seats) do
      if not human(seat) then srv.bot_seats[p] = controls.bot(state, p, seat.brain) end
   end
   tell_lobby(srv)
   broadcast(srv, start_msg(srv))
   srv.log_line(("match %d started"):format(srv.seed))
end

--- Back to the lobby.
local function stop(srv: Server)
   srv.running = false
   srv.state, srv.m = nil, nil
   tell_lobby(srv)
end

--- The home `client` sits `slot` at: `p` if it's free (a bot's), else the
--- first bot's. Its other seat for that slot, if any, goes back to a bot.
local function sit(srv: Server, client: integer, slot: string, p?: integer)
   if p and (p < 1 or p > #srv.seats or human(srv.seats[p])) then return end
   if not p then
      for q, seat in ipairs(srv.seats) do
         if not human(seat) and (not srv.running or srv.state.players[q].alive) then
            p = q
            break
         end
      end
   end
   if not p then return end
   for q, seat in ipairs(srv.seats) do
      if seat.client == client and seat.slot == slot then srv.seats[q] = { kind = "bot", brain = "random" } end
   end
   srv.seats[p] = { kind = "human", client = client, slot = slot, name = srv.peers[client].name }
   if srv.running then
      srv.bot_seats[p] = nil
      srv.intents[p] = nil
      srv.ready[p] = nil
   end
end

--- Player `p`'s home goes back to a bot.
local function unseat(srv: Server, p: integer)
   local brain = srv.seats[p].brain or "random"
   srv.seats[p] = { kind = "bot", brain = brain }
   if srv.running then
      srv.bot_seats[p] = controls.bot(srv.state, p, brain)
      srv.intents[p] = nil
      srv.ready[p] = nil
   end
end

--- The integer field `k` of `msg`, held to lo..hi, or `fallback`.
local function clamp(msg: Msg, k: string, lo: integer, hi: integer, fallback?: integer): integer
   local v = wire.int(msg, k)
   if not v then return fallback end
   return math.max(lo, math.min(hi, v))
end

--- An aim from the wire, held to what could be real.
local function read_intent(msg: Msg): sim.Intent
   local intent: sim.Intent = {
      slot = clamp(msg, "slot", 1, sim.BANK, 1),
      turn = clamp(msg, "turn", 0, 5, 0),
      prefer = clamp(msg, "prefer", 1, 3, 2),
   }
   local a, b = clamp(msg, "wa", -100000, 100000), clamp(msg, "wb", -100000, 100000)
   local count = clamp(msg, "count", 1, 1000)
   if a and b and count then intent.want, intent.count = { a = a, b = b }, count end
   return intent
end

--- Does `client` play player `p`?
local function plays(srv: Server, client: integer, p: integer): boolean
   local seat = srv.seats[p]
   return seat ~= nil and seat.client == client
end

local OWNER_ONLY <const>: {string: boolean} = { config = true, start = true, again = true, lobby = true, step = true }

local function receive(srv: Server, id: integer, msg: Msg)
   local peer = srv.peers[id]
   local t = wire.str(msg, "t")
   if t == "hello" then
      if wire.int(msg, "v") ~= server.PROTOCOL then
         send(srv, id, { t = "refuse", why = "a different version of the game" })
         srv.link.drop(id)
         return
      end
      peer.hello = true
      peer.name = (wire.str(msg, "name") or ("Player " .. id)):sub(1, 24)
      local claimed = srv.token and wire.str(msg, "token") == srv.token
      local any_owner = false
      for _, other in pairs(srv.peers) do
         if other.owner then any_owner = true end
      end
      peer.owner = claimed or (not srv.token and not any_owner)
      send(srv, id, { t = "welcome", id = id, owner = peer.owner, s = math.floor(srv.now()) })
      send(srv, id, lobby_msg(srv))
      if srv.running then send(srv, id, start_msg(srv)) end
      srv.log_line(("%s joined"):format(peer.name))
      return
   end
   if not peer.hello then return end
   if OWNER_ONLY[t] and not peer.owner then return end

   if t == "ping" then
      send(srv, id, { t = "pong", c = wire.int(msg, "c"), s = math.floor(srv.now()) })
   elseif t == "aim" then
      local p = wire.int(msg, "p")
      if p and plays(srv, id, p) and srv.running then srv.intents[p] = read_intent(msg) end
   elseif t == "ready" then
      local p = wire.int(msg, "p")
      if p and plays(srv, id, p) and srv.running and srv.state.players[p].alive then
         local on = msg.on == true
         if (srv.ready[p] or false) ~= on then
            srv.ready[p] = on or nil
            broadcast(srv, { t = "ready", p = p, on = on })
         end
      end
   elseif t == "sit" then
      local slot = wire.str(msg, "slot")
      if slot then
         sit(srv, id, slot:sub(1, 16), wire.int(msg, "p"))
         tell_lobby(srv)
      end
   elseif t == "stand" then
      local slot = wire.str(msg, "slot")
      for p, seat in ipairs(srv.seats) do
         if seat.client == id and seat.slot == slot then unseat(srv, p) end
      end
      tell_lobby(srv)
   elseif t == "hash" then
      local tick, h = wire.int(msg, "tick"), wire.int(msg, "h")
      local want = tick and srv.running and srv.hashes[tick]
      if want and want ~= h then
         srv.log_line(("%s fell out of step at tick %d: sending the match again"):format(peer.name, tick))
         send(srv, id, start_msg(srv))
      end
   elseif t == "config" and not srv.running then
      local c = srv.config
      c.n = clamp(msg, "n", 1, 40, c.n)
      c.r = clamp(msg, "r", 1, 40, c.r)
      c.size = clamp(msg, "size", 1, 40, c.size)
      c.clock = clamp(msg, "clock", 500, 120000, c.clock)
      c.step = clamp(msg, "step", 20, 5000, c.step)
      if type(msg.flick) == "boolean" then c.flick = msg.flick as boolean end
      local brains = msg.brains
      if type(brains) == "table" then
         for p, seat in ipairs(srv.seats) do
            local b = (brains as {any: any})[p]
            if not human(seat) and (b == "random" or b == "greedyclear") then seat.brain = b as bots.Brain end
         end
      end
      local seed = wire.int(msg, "seed")
      if seed then srv.seed = seed end
      tell_lobby(srv)
   elseif t == "start" and not srv.running then
      start(srv)
   elseif t == "again" then
      srv.seed = srv.seed + 1
      start(srv)
   elseif t == "lobby" and srv.running then
      stop(srv)
   elseif t == "step" and srv.running then
      local step = clamp(msg, "step", 20, 5000)
      if step then
         match.set_step(srv.m, step)
         announce(srv, { t = "step", ms = srv.m.now, step = step })
      end
   end
end

local function disconnected(srv: Server, id: integer)
   local peer = srv.peers[id]
   if not peer then return end
   srv.peers[id] = nil
   for p, seat in ipairs(srv.seats) do
      if seat.client == id then unseat(srv, p) end
   end
   if peer.owner and not srv.token then
      local next_id: integer
      for other, p in pairs(srv.peers) do
         if p.hello and (not next_id or other < next_id) then next_id = other end
      end
      if next_id then
         srv.peers[next_id].owner = true
         send(srv, next_id, { t = "owner" })
      end
   end
   if peer.hello then srv.log_line(("%s left"):format(peer.name)) end
   tell_lobby(srv)
end

--- The ready vote: when every live human is ready, skip the clocks ahead to
--- the soonest of them, firing any bot due before.
local function vote(srv: Server)
   local state, m = srv.state, srv.m
   local soonest: integer
   for p, seat in ipairs(srv.seats) do
      if human(seat) and state.players[p].alive then
         if not srv.ready[p] then return end
         if not soonest or m.deadline[p] < m.deadline[soonest] then soonest = p end
      end
   end
   if not soonest or sim.over(state) or m.deadline[soonest] <= m.now then return end
   match.skip(m, soonest)
   announce(srv, { t = "skip", ms = m.now, p = soonest })
   match.advance(m, m.now, srv.hooks)
end

--- Handle what has arrived and play the match up to now.
function server.update(srv: Server)
   for _, e in ipairs(srv.link.poll()) do
      if e.kind == "connect" then
         srv.peers[e.peer] = { id = e.peer, name = "Player " .. e.peer, owner = false, hello = false }
      elseif e.kind == "disconnect" then
         disconnected(srv, e.peer)
      elseif e.kind == "receive" and srv.peers[e.peer] then
         local msg = wire.decode(e.data)
         if msg then receive(srv, e.peer, msg) end
      end
   end
   if not srv.running then return end
   local m = srv.m
   local logged = #srv.log
   match.advance(m, math.floor(srv.now() - srv.t0), srv.hooks)
   vote(srv)
   if m.ticks ~= srv.said_ticks or #srv.log ~= logged or m.now - srv.said_at >= 100 then
      srv.said_at, srv.said_ticks = m.now, m.ticks
      broadcast(srv, { t = "at", ms = m.now })
   end
end

--- Shut the server down.
function server.close(srv: Server)
   srv.link.close()
end

return server
