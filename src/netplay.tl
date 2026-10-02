--- Networked play in the LOVE build: hosting (a server in this game, with
--- this game as its first client, the owner) or joining someone else's,
--- over ENet. main.tl drives a session; this keeps it in step with the
--- setup screen and turns the lobby into seats.

local board = require("board")
local sim = require("sim")
local controls = require("controls")
local setup = require("setup")
local server = require("server")
local client = require("client")
local enetlink = require("enetlink")

local record netplay
   record Session
      srv: server.Server -- when hosting
      c: client.Client
      address: string -- where others can reach the host, for the screen
      said: string -- the host's last options and seats sent, so they go once
      said_at: number
   end
end

local type Session = netplay.Session

local function now(): number
   return love.timer.getTime() * 1000
end

--- What this machine's player is called.
local function my_name(): string
   return os.getenv("USER") or os.getenv("USERNAME") or "Player"
end

--- Host a match on `port`, starting from `config` and match `seed`. Returns
--- the session, or nil and why not.
function netplay.host(port: integer, config: server.Config, seed: integer, hooks: client.Hooks): Session, string
   local l, err = enetlink.serve(port)
   if not l then return nil, err end
   local token = ("%d-%d"):format(math.floor(now() * 1000) % 1000000007, math.random(1, 1000000000))
   local srv = server.new(l, now, config, token, seed)
   srv.log_line = function(line: string) print("server: " .. line) end
   local cl, why = enetlink.connect("127.0.0.1", port)
   if not cl then
      server.close(srv)
      return nil, why
   end
   local ip = enetlink.local_address()
   return {
      srv = srv,
      c = client.new(cl, now, my_name(), hooks, token),
      address = ("%s:%d"):format(ip or "this machine's address", port),
   }, nil
end

--- Join the match hosted at `address` (the port defaulting to `port`).
function netplay.join(address: string, port: integer, hooks: client.Hooks): Session, string
   if address == "" then return nil, "type in the host's address first" end
   local l, err = enetlink.connect(address, port)
   if not l then return nil, err end
   return { c = client.new(l, now, my_name(), hooks), address = address }, nil
end

--- A headless server on `port`: no game of its own, the first to join
--- owning it.
function netplay.serve(port: integer, config: server.Config, seed: integer): server.Server, string
   local l, err = enetlink.serve(port)
   if not l then return nil, err end
   local srv = server.new(l, now, config, nil, seed)
   srv.log_line = print
   return srv, nil
end

--- Run the session: the server, if hosting, then this game's client.
function netplay.update(s: Session)
   if s.srv then server.update(s.srv) end
   client.update(s.c)
end

--- Leave (and if hosting, shut the server down, which ends it for everyone).
function netplay.close(s: Session)
   client.close(s.c)
   if s.srv then server.close(s.srv) end
end

--- The name a controller of this machine goes by on the server.
function netplay.slot(kind: controls.Kind, pad?: love.Joystick): string
   if kind == "pad" and pad then return ("pad%d"):format(pad:getID()) end
   return "keys"
end

--- The controller a slot name means here, if it's still plugged in.
local function controller(slot: string): controls.Kind, love.Joystick
   if slot == "keys" then return "keys", nil end
   local id = tonumber(slot:match("^pad(%d+)$") or "")
   if not id then return nil, nil end
   for _, pad in ipairs(love.joystick.getJoysticks()) do
      if pad:getID() == id then return "pad", pad end
   end
   return nil, nil
end

--- A match's options, as the setup screen has them.
function netplay.config(menu: setup.State, step: integer): server.Config
   local n, r, chunk, clock, flick = setup.options(menu)
   return { n = n, r = r, size = chunk, clock = math.floor(clock * 1000 + 0.5), step = step, flick = flick }
end

--- The host's setup screen changed (or the lobby did): send the options and
--- the bots' brains, and sit this machine's controllers where the screen
--- has them. Sent only when something changed, or again after a second in
--- case a sit lost a race.
function netplay.push(s: Session, menu: setup.State, step: integer)
   local c = s.c
   if not (s.srv and c.lobby and c.status == "lobby") then return end
   local config = netplay.config(menu, step)
   local brains: {integer: string} = {}
   local want: {string: integer} = {}
   for p, pick in ipairs(menu.picks) do
      if pick.kind == "bot" then brains[p] = pick.brain or "random" end
      if pick.kind == "keys" or pick.kind == "pad" then want[netplay.slot(pick.kind, pick.pad)] = p end
   end
   local plan: {string} = { ("%d %d %d %d %s"):format(config.n, config.r, config.size, config.clock, tostring(config.flick)) }
   for p = 1, #board.PLAYERS do plan[#plan + 1] = brains[p] or "-" end
   for p, seat in ipairs(c.lobby.seats) do plan[#plan + 1] = ("%d=%s/%s"):format(p, tostring(seat.client), tostring(seat.slot)) end
   local said = table.concat(plan, " ")
   if said == s.said and now() - s.said_at < 1000 then return end
   s.said, s.said_at = said, now()

   client.configure(c, config, brains)
   for slot, p in pairs(want) do
      if client.mine(c, p) ~= slot then client.sit(c, slot, p) end
   end
   for p = 1, #board.PLAYERS do
      local slot = client.mine(c, p)
      if slot and want[slot] == nil then client.stand(c, slot) end
   end
end

--- The lobby changed: show who joined over the network on the host's
--- setup screen.
function netplay.remotes(s: Session, menu: setup.State)
   local c = s.c
   if not c.lobby then return end
   for p, seat in ipairs(c.lobby.seats) do
      if seat.kind == "human" and seat.client ~= c.id then
         setup.remote(menu, p, seat.name)
      else
         setup.remote(menu, p, nil)
      end
   end
end

--- What to call the lobby's seat at `p`.
function netplay.who(s: Session, p: integer): string
   local seat = s.c.lobby and s.c.lobby.seats[p]
   if not seat or seat.kind ~= "human" then
      return seat and seat.brain == "greedyclear" and "greedyclear bot" or "bot"
   end
   if seat.client == s.c.id then return "you" end
   return seat.name or "?"
end

--- Seats for the match as the lobby has them: this machine's controllers
--- where it sits them (keeping `old` seats that haven't changed), and every
--- other home played elsewhere.
function netplay.seats(s: Session, state: sim.State, old?: {controls.Seat}): {controls.Seat}
   local out: {controls.Seat} = {}
   for p = 1, #board.PLAYERS do
      local slot = client.mine(s.c, p)
      local kind, pad: controls.Kind, love.Joystick
      if slot then kind, pad = controller(slot) end
      local was = old and old[p]
      if kind and was and was.kind == kind and was.pad == pad then
         out[p] = was
      elseif kind then
         out[p] = controls.human(state, p, kind, pad)
      else
         out[p] = controls.remote(p, netplay.who(s, p))
      end
   end
   return out
end

--- Tell the server what this machine's players are aiming.
function netplay.aims(s: Session, state: sim.State, seats: {controls.Seat})
   for p, seat in ipairs(seats) do
      if seat.aim and state.players[p].alive then client.aim(s.c, p, controls.intent(seat.aim)) end
   end
end

return netplay
