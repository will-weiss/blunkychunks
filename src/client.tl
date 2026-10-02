--- A player's end of a networked match. It keeps its own full copy of the
--- match and plays it out, a moment behind the server, from what the server
--- announces (see server.tl): the shots as each shot clock runs out, the
--- ready vote's skips and speed changes, and `at`, how far the server has
--- got. Ticks are never sent; every copy works them out alike.
---
--- The copy runs `delay` behind the server's clock (half the round trip
--- plus a margin), so a shot normally arrives before it is needed. If it
--- hasn't, the copy waits for it rather than guess.
---
--- What this player aims goes to the server alone (`aim`), and only when
--- it changes.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local match = require("match")
local link = require("link")
local wire = require("wire")
local server = require("server")

local type Msg = wire.Msg

local record client
   record Seat
      kind: string -- "bot" or "human"
      brain: string
      client: integer
      slot: string
      name: string
   end

   record Lobby
      config: server.Config
      running: boolean
      seats: {Seat}
   end

   --- The match as this client plays it.
   record Game
      state: sim.State
      m: match.Match
      seed: integer
      config: server.Config
      t0: number -- the server ms it started
      shots: {integer: {integer: Msg}} -- per player, per shot clock: what the server said
      timeline: {Msg} -- skips and speed changes still to come, in order
      through: integer -- the server has said everything up to this ms
      ready: {integer: boolean}
      catching_up: boolean -- far behind (just joined): skip the effects
   end

   --- What the game hears from its client.
   record Hooks
      lobby: function()
      start: function(Game)
      locked: function(p: integer, r: sim.LockResult)
      ticked: function(r: sim.TickResult)
      owner: function()
   end

   record Client
      link: link.Link
      now: function(): number -- local ms
      name: string
      token: string
      hooks: Hooks
      status: string -- "connecting", "lobby", "playing" or "gone"
      why: string -- for "gone"
      id: integer
      owner: boolean
      lobby: Lobby
      game: Game
      offset: number -- server ms minus local ms
      rtt: number -- the best round trip seen lately, ms
      pings: {{number}} -- recent { round trip, offset }
      next_ping: number
      sent_aims: {integer: string}
      said_hash: integer
      began: number -- local ms it started connecting
   end

   CONNECT_TIMEOUT: number
end

local type Client = client.Client
local type Game = client.Game

--- How long to wait for the host to answer before giving up, in ms.
client.CONNECT_TIMEOUT = 10000

local MARGIN <const> = 60 -- ms the copy runs behind, beyond half a round trip
local HASH_EVERY <const> = 16 -- ticks

--- A client on `link`, telling the time with `now` (ms). `name` is what
--- others see; `token`, if it's the host's, makes this client the owner.
function client.new(l: link.Link, now: (function(): number), name: string, hooks: client.Hooks, token?: string): Client
   local c: Client = {
      link = l,
      now = now,
      name = name,
      token = token,
      hooks = hooks,
      status = "connecting",
      owner = false,
      offset = 0,
      rtt = 1000,
      pings = {},
      next_ping = 0,
      sent_aims = {},
      said_hash = 0,
      began = now(),
   }
   return c
end

local function send(c: Client, msg: Msg)
   c.link.send(0, wire.encode(msg))
end

--- The server's clock, as near as this client can tell.
function client.server_now(c: Client): number
   return c.now() + c.offset
end

--- How far into the match the copy should be showing: the server's clock
--- less the delay.
function client.view(c: Client): number
   local g = c.game
   if not g then return 0 end
   return client.server_now(c) - g.t0 - (c.rtt / 2 + MARGIN)
end

--- How far into the match the server is.
function client.server_time(c: Client): number
   local g = c.game
   if not g then return 0 end
   return client.server_now(c) - g.t0
end

local function read_config(msg: Msg): server.Config
   return {
      n = wire.int(msg, "n") or 11,
      r = wire.int(msg, "r") or 8,
      size = wire.int(msg, "size") or 14,
      clock = wire.int(msg, "clock") or 8000,
      step = wire.int(msg, "step") or 280,
      flick = msg.flick == true,
   }
end

local function read_lobby(msg: Msg): client.Lobby
   local seats: {client.Seat} = {}
   local list = msg.seats
   if type(list) == "table" then
      for p = 1, #board.PLAYERS do
         local s = (list as {any})[p]
         if type(s) == "table" then
            local t = s as Msg
            seats[p] = {
               kind = wire.str(t, "kind") or "bot", brain = wire.str(t, "brain"),
               client = wire.int(t, "client"), slot = wire.str(t, "slot"), name = wire.str(t, "name"),
            }
         end
      end
   end
   for p = 1, #board.PLAYERS do seats[p] = seats[p] or { kind = "bot" } end
   return { config = read_config(msg), running = msg.running == true, seats = seats }
end

--- A shot as the server announced it.
local function read_shot(msg: Msg): sim.Shot
   local slot, heading, flat = wire.int(msg, "slot"), wire.int(msg, "heading"), wire.ints(msg, "cells")
   if not (slot and heading and flat) then return nil end
   local cells: {board.Tri} = {}
   for k = 1, #flat - 1, 2 do cells[#cells + 1] = { i = flat[k], color = bc.COLORS[flat[k + 1]] } end
   return { player = wire.int(msg, "p"), slot = slot, heading = heading, cells = cells }
end

local function note(g: Game, msg: Msg)
   local t = wire.str(msg, "t")
   if t == "shot" then
      local p, k = wire.int(msg, "p"), wire.int(msg, "k")
      if p and k and g.shots[p] then g.shots[p][k] = msg end
   elseif t == "skip" or t == "step" then
      g.timeline[#g.timeline + 1] = msg
   end
end

--- A match starting (or this client joining one, or being sent it again
--- after falling out of step): build the copy and queue what has happened.
local function start(c: Client, msg: Msg)
   local config = read_config(msg)
   local seed = wire.int(msg, "seed") or 1
   local state = sim.new(board.new(config.n, config.r), config.size, bc.seeded_random(seed))
   local g: Game = {
      state = state,
      m = match.new(state, config.clock, config.step),
      seed = seed,
      config = config,
      t0 = wire.int(msg, "at") or 0,
      shots = {},
      timeline = {},
      through = wire.int(msg, "through") or 0,
      ready = {},
   }
   for p = 1, #board.PLAYERS do g.shots[p] = {} end
   local log = msg.log
   if type(log) == "table" then
      for _, item in ipairs(log as {any}) do
         if type(item) == "table" then note(g, item as Msg) end
      end
   end
   c.game = g
   c.status = "playing"
   c.sent_aims = {}
   c.said_hash = 0
   if c.hooks.start then c.hooks.start(g) end
end

local function receive(c: Client, msg: Msg)
   local t = wire.str(msg, "t")
   local g = c.game
   if t == "welcome" then
      c.id = wire.int(msg, "id")
      c.owner = msg.owner == true
      local s = wire.int(msg, "s")
      if s then c.offset = s - c.now() end
      c.status = "lobby"
   elseif t == "refuse" then
      c.status, c.why = "gone", wire.str(msg, "why") or "refused"
   elseif t == "owner" then
      c.owner = true
      if c.hooks.owner then c.hooks.owner() end
   elseif t == "lobby" then
      c.lobby = read_lobby(msg)
      if not c.lobby.running then
         c.game = nil
         if c.status == "playing" then c.status = "lobby" end
      end
      if c.hooks.lobby then c.hooks.lobby() end
   elseif t == "start" then
      start(c, msg)
   elseif t == "pong" then
      local sent, s = wire.int(msg, "c"), wire.int(msg, "s")
      if sent and s then
         local now = c.now()
         local rtt = math.max(0, now - sent)
         table.insert(c.pings, { rtt, s + rtt / 2 - now })
         if #c.pings > 8 then table.remove(c.pings, 1) end
         local best = c.pings[1]
         for _, ping in ipairs(c.pings) do
            if ping[1] < best[1] then best = ping end
         end
         c.rtt, c.offset = best[1], best[2]
      end
   elseif g and t == "at" then
      g.through = math.max(g.through, wire.int(msg, "ms") or 0)
   elseif g and t == "ready" then
      local p = wire.int(msg, "p")
      if p then g.ready[p] = msg.on == true or nil end
   elseif g then
      note(g, msg)
   end
end

--- Play the copy on as far as the server has said and the view has got.
local function play(c: Client)
   local g = c.game
   local m = g.m
   local hooks: match.Hooks = {
      decide = function(p: integer, k: integer): boolean, sim.Shot
         local msg = g.shots[p][k]
         if not msg then return false, nil end
         return true, read_shot(msg)
      end,
      locked = function(p: integer, r: sim.LockResult)
         g.ready[p] = nil
         if c.hooks.locked then c.hooks.locked(p, r) end
      end,
      ticked = function(r: sim.TickResult)
         if c.hooks.ticked then c.hooks.ticked(r) end
         if m.ticks % HASH_EVERY == 0 then
            send(c, { t = "hash", tick = m.ticks, h = sim.hash(g.state) })
         end
      end,
   }
   local to = math.min(math.floor(client.view(c)), g.through)
   g.catching_up = to - m.now > 1000
   while g.timeline[1] do
      local item = g.timeline[1]
      local ms = wire.int(item, "ms") or 0
      if ms > to then break end
      if not match.advance(m, ms, hooks) then return end
      if wire.str(item, "t") == "skip" then
         match.skip(m, wire.int(item, "p"))
      else
         match.set_step(m, wire.int(item, "step") or m.step)
      end
      table.remove(g.timeline, 1)
   end
   match.advance(m, to, hooks)
end

--- Handle what has arrived, keep the clocks in step and play the match on.
function client.update(c: Client)
   for _, e in ipairs(c.link.poll()) do
      if e.kind == "connect" then
         send(c, { t = "hello", v = server.PROTOCOL, name = c.name, token = c.token })
      elseif e.kind == "disconnect" then
         if c.status ~= "gone" then c.status, c.why = "gone", c.why or "lost the connection" end
      elseif e.kind == "receive" then
         local msg = wire.decode(e.data)
         if msg then receive(c, msg) end
      end
   end
   if c.status == "connecting" and c.now() - c.began > client.CONNECT_TIMEOUT then
      c.link.close()
      c.status, c.why = "gone", "no answer from the host. Check they're hosting, and that this machine can reach that address"
   end
   if c.status == "gone" or c.status == "connecting" then return end
   local now = c.now()
   if now >= c.next_ping then
      send(c, { t = "ping", c = math.floor(now) })
      c.next_ping = now + (#c.pings < 5 and 200 or 2000)
   end
   if c.game then play(c) end
end

--- Player `p` (one of this client's) is aiming `intent`: tell the server if
--- that's new.
function client.aim(c: Client, p: integer, intent: sim.Intent)
   local msg: Msg = { t = "aim", p = p, slot = intent.slot, turn = intent.turn, prefer = intent.prefer }
   if intent.want then msg.wa, msg.wb, msg.count = intent.want.a, intent.want.b, intent.count end
   local said = ("%d %d %d %s %s %s"):format(intent.slot, intent.turn, intent.prefer,
      tostring(msg.wa), tostring(msg.wb), tostring(msg.count))
   if c.sent_aims[p] == said then return end
   c.sent_aims[p] = said
   send(c, msg)
end

--- Player `p` (one of this client's) votes to fire now, or takes it back.
function client.ready(c: Client, p: integer, on: boolean)
   send(c, { t = "ready", p = p, on = on })
end

--- Sit this client's controller `slot` (e.g. "keys") at home `p`, or the
--- first a bot has.
function client.sit(c: Client, slot: string, p?: integer)
   send(c, { t = "sit", slot = slot, p = p })
end

--- Controller `slot` gets up, leaving its home to a bot.
function client.stand(c: Client, slot: string)
   send(c, { t = "stand", slot = slot })
end

--- The owner's: the match's options and the bots' brains.
function client.configure(c: Client, config: server.Config, brains: {integer: string})
   send(c, {
      t = "config", n = config.n, r = config.r, size = config.size, clock = config.clock,
      step = config.step, flick = config.flick, brains = brains,
   })
end

--- The owner's: start a match, start another, back to the lobby, or change
--- the slide speed.
function client.start(c: Client) send(c, { t = "start" }) end
function client.again(c: Client) send(c, { t = "again" }) end
function client.to_lobby(c: Client) send(c, { t = "lobby" }) end
function client.set_step(c: Client, step: integer) send(c, { t = "step", step = step }) end

--- The seat at player `p`'s home, if it's one of this client's.
function client.mine(c: Client, p: integer): string
   local seat = c.lobby and c.lobby.seats[p]
   if seat and seat.kind == "human" and seat.client == c.id then return seat.slot end
   return nil
end

--- Leave.
function client.close(c: Client)
   c.link.close()
   c.status, c.why = "gone", "left"
end

return client
