--- Networked matches inside one process: a server and clients over the
--- in-memory hub (link.tl), with uneven delays, checking that every copy of
--- the match agrees and that nobody is told anyone else's aim.

local bc = require("blunkychunks")
local board = require("board")
local sim = require("sim")
local link = require("link")
local wire = require("wire")
local server = require("server")
local client = require("client")
local A = require("tests.assert")

local record T
end

--- What a server may ever tell a client.
local TOLD <const>: {string: boolean} = {
   welcome = true, refuse = true, owner = true, lobby = true, start = true,
   shot = true, skip = true, step = true, at = true, ready = true, pong = true,
}

local record World
   time: number
   hub: link.Hub
   srv: server.Server
   clients: {client.Client}
   told: {integer: {string}} -- per client, the kinds of message it was sent
   rng: function(): number
end

local function world(seed: integer, max_delay: number): World
   local w: World = { time = 0, clients = {}, told = {}, rng = bc.seeded_random(seed) }
   local function now(): number return w.time end
   w.hub = link.hub(now, function(): number return math.floor(w.rng() * max_delay) end)
   w.hub.sent = function(_: integer, to: integer, data: string)
      if to == 0 then return end
      local msg = wire.decode(data)
      w.told[to] = w.told[to] or {}
      table.insert(w.told[to], msg and (msg.t as string) or "garbage")
   end
   w.srv = server.new(link.serve(w.hub), now,
      { n = 6, r = 5, size = 6, clock = 3000, step = 280, flick = true }, "secret", seed)
   return w
end

local function join(w: World, name: string, token?: string): client.Client
   local c = client.new(link.connect(w.hub), function(): number return w.time end, name, {}, token)
   w.clients[#w.clients + 1] = c
   return c
end

--- Run the world for `ms`, 10 ms a frame. `each` runs every frame.
local function run(w: World, ms: number, each?: function())
   local stop = w.time + ms
   while w.time < stop do
      w.time = w.time + 10
      server.update(w.srv)
      for _, c in ipairs(w.clients) do
         if c.status ~= "gone" then client.update(c) end
      end
      if each then each() end
   end
end

--- Every seated human on every client fiddles with their aim now and then:
--- a random chunk, rotation, heading and spot, sent as it changes, and a
--- ready vote some of the time.
local function fiddle(w: World): function()
   return function()
      for _, c in ipairs(w.clients) do
         local g = c.game
         if g and c.status == "playing" and w.rng() < 0.02 then
            for p = 1, 3 do
               if client.mine(c, p) and g.state.players[p].alive then
                  local intent: sim.Intent = {
                     slot = 1 + math.floor(w.rng() * 3), turn = math.floor(w.rng() * 6),
                     prefer = 1 + math.floor(w.rng() * 3),
                  }
                  local s = sim.settle(g.state, p, intent)
                  if #s.spots > 0 then
                     local spot = s.spots[1 + math.floor(w.rng() * #s.spots)]
                     local cells = board.place(g.state.board, s.shape, spot.x, spot.y)
                     intent.want, intent.count = sim.centre(g.state.board, cells), #cells
                  end
                  client.aim(c, p, intent)
                  if w.rng() < 0.3 then client.ready(c, p, true) end
               end
            end
         end
      end
   end
end

--- Run until the server's match is over (or `limit` ms), then long enough
--- for every client to catch up.
local function finish(w: World, limit: number, each?: function())
   local stop = w.time + limit
   while not sim.over(w.srv.state) and w.time < stop do run(w, 100, each) end
   run(w, 2000)
end

--- Every client still connected has the server's match.
local function agree(w: World, what: string)
   local want = sim.hash(w.srv.state)
   for i, c in ipairs(w.clients) do
      if c.status ~= "gone" then
         A.truthy(c.game, what .. ": client " .. i .. " has the match")
         A.eq(c.game.m.ticks, w.srv.m.ticks, what .. ": client " .. i .. " is at the server's tick")
         A.eq(sim.hash(c.game.state), want, what .. ": client " .. i .. " agrees")
      end
   end
end

--- Three players on three clients, the first the owner, all sat and started.
local function three(seed: integer, max_delay: number): World
   local w = world(seed, max_delay)
   join(w, "Ada", "secret")
   join(w, "Bo")
   join(w, "Cy")
   run(w, 500)
   for _, c in ipairs(w.clients) do
      A.eq(c.status, "lobby", "in the lobby")
      client.sit(c, "keys")
   end
   run(w, 500)
   A.truthy(w.clients[1].owner, "the token holder owns it")
   A.truthy(not w.clients[2].owner, "nobody else does")
   for p = 1, 3 do A.eq(w.srv.seats[p].kind, "human", "every home taken") end
   client.start(w.clients[1])
   run(w, 300)
   return w
end

function T.every_copy_of_a_match_agrees_over_an_uneven_network()
   local w = three(11, 150)
   finish(w, 120000, fiddle(w))
   A.truthy(sim.over(w.srv.state), "the match finished")
   agree(w, "at the end")
end

function T.a_client_is_never_told_anyone_elses_aim()
   local w = three(12, 80)
   finish(w, 60000, fiddle(w))
   for id, kinds in pairs(w.told) do
      for _, t in ipairs(kinds) do
         A.truthy(TOLD[t], ("client %d was sent a %s"):format(id, t))
      end
   end
end

function T.the_ready_vote_skips_once_every_human_is_ready()
   local w = three(13, 50)
   run(w, 500)
   local m = w.srv.m
   local before = m.deadline[1]
   for _, c in ipairs(w.clients) do
      for p = 1, 3 do
         if client.mine(c, p) then client.ready(c, p, true) end
      end
   end
   run(w, 300)
   A.truthy(m.shots[1] >= 1, "Player 1 fired early")
   A.truthy(m.now < before, "before their clock ran out")
   local skipped = false
   for _, msg in ipairs(w.srv.log) do
      if msg.t == "skip" then skipped = true end
   end
   A.truthy(skipped, "a skip was announced")
   run(w, 1000)
   agree(w, "after the skip")
end

function T.the_vote_waits_for_everyone()
   local w = three(14, 50)
   run(w, 500)
   for i = 1, 2 do
      for p = 1, 3 do
         if client.mine(w.clients[i], p) then client.ready(w.clients[i], p, true) end
      end
   end
   run(w, 1000)
   A.eq(w.srv.m.shots[1], 0, "no skip with one player still aiming")
end

function T.a_late_joiner_catches_up()
   local w = three(15, 100)
   run(w, 8000, fiddle(w))
   local late = join(w, "Late")
   run(w, 1500)
   A.eq(late.status, "playing", "watching")
   finish(w, 120000, fiddle(w))
   agree(w, "the late joiner too")
end

function T.a_client_out_of_step_is_sent_the_match_again()
   local w = three(16, 60)
   local lines: {string} = {}
   w.srv.log_line = function(line: string) lines[#lines + 1] = line end
   run(w, 6000, fiddle(w))
   -- Knock client 2's copy out of step: its next chunk gets another id.
   local state = w.clients[2].game.state
   state.next_id = state.next_id + 1
   run(w, 8000, fiddle(w))
   local resent = false
   for _, line in ipairs(lines) do
      if line:find("fell out of step") then resent = true end
   end
   A.truthy(resent, "the server noticed and sent the match again")
   finish(w, 120000, fiddle(w))
   agree(w, "after the resync")
end

function T.a_player_who_leaves_is_replaced_by_a_bot()
   local w = three(17, 60)
   run(w, 4000, fiddle(w))
   client.close(w.clients[3])
   run(w, 500)
   A.eq(w.srv.seats[3].kind, "bot", "a bot took over")
   finish(w, 120000, fiddle(w))
   agree(w, "the two left")
end

function T.only_the_owner_runs_the_match()
   local w = world(18, 20)
   join(w, "Ada", "secret")
   local bo = join(w, "Bo")
   run(w, 300)
   client.start(bo)
   run(w, 300)
   A.truthy(not w.srv.running, "Bo can't start it")
   client.start(w.clients[1])
   run(w, 300)
   A.truthy(w.srv.running, "Ada can")
   client.to_lobby(bo)
   run(w, 300)
   A.truthy(w.srv.running, "Bo can't stop it")
end

function T.a_speed_change_reaches_every_copy()
   local w = three(19, 80)
   run(w, 2000, fiddle(w))
   client.set_step(w.clients[1], 100)
   run(w, 3000, fiddle(w))
   A.eq(w.srv.m.step, 100, "the server's ticks are faster")
   finish(w, 120000, fiddle(w))
   agree(w, "after the speed change")
end

function T.a_client_with_another_version_is_turned_away()
   local w = world(20, 0)
   local c = join(w, "Old")
   run(w, 20)
   c.link.send(0, wire.encode({ t = "hello", v = 999, name = "Old" }))
   run(w, 100)
   A.eq(c.status, "gone", "refused")
end

return T
