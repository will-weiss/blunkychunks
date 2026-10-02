--- A connection between the server and its clients, whatever carries it.
--- The server's end talks to every client by peer number; a client's end
--- talks only to the server, as peer 0. Messages are strings (see wire.tl)
--- and arrive reliably, in the order they were sent, or the peer
--- disconnects.
---
--- Two kinds: enetlink.tl carries them over UDP in the LOVE build, and the
--- in-memory hub here carries them inside one process with whatever delay a
--- test asks for.

local record link
   record Event
      kind: string -- "connect", "disconnect" or "receive"
      peer: integer
      data: string
   end

   record Link
      send: function(peer: integer, data: string)
      poll: function(): {Event}
      drop: function(peer: integer) -- disconnect a peer (a client drops 0)
      close: function()
   end

   --- An in-memory network. `now` gives the time in ms, `delay` how long a
   --- message should take to arrive (it is never sooner than the one sent
   --- before it, so the order holds). `sent` sees every message, for tests
   --- that check what each client is told.
   record Hub
      now: function(): number
      delay: function(from: integer, to: integer): number
      sent: function(from: integer, to: integer, data: string)
      queues: {integer: {Pending}} -- per receiving end (0 is the server)
      last: {string: number} -- per direction, when its last message arrives
      ends: integer
      open: {integer: boolean}
   end

   record Pending
      at: number
      event: Event
   end
end

local type Event = link.Event
local type Hub = link.Hub
local type Link = link.Link

--- A new in-memory network.
function link.hub(now: (function(): number), delay?: (function(integer, integer): number)): Hub
   return {
      now = now,
      delay = delay or function(): number return 0 end,
      queues = { [0] = {} },
      last = {},
      ends = 0,
      open = {},
   }
end

local function post(hub: Hub, from: integer, to: integer, event: Event)
   local q = hub.queues[to]
   if not q then return end
   local key = from .. ">" .. to
   local at = math.max(hub.now() + hub.delay(from, to), hub.last[key] or 0)
   hub.last[key] = at
   q[#q + 1] = { at = at, event = event }
end

local function take(hub: Hub, who: integer): {Event}
   local q = hub.queues[who]
   local out: {Event} = {}
   if not q then return out end
   local now = hub.now()
   local keep: {link.Pending} = {}
   for _, item in ipairs(q) do
      if item.at <= now then out[#out + 1] = item.event else keep[#keep + 1] = item end
   end
   hub.queues[who] = keep
   return out
end

--- The server's end of `hub`.
function link.serve(hub: Hub): Link
   return {
      send = function(peer: integer, data: string)
         if not hub.open[peer] then return end
         if hub.sent then hub.sent(0, peer, data) end
         post(hub, 0, peer, { kind = "receive", peer = 0, data = data })
      end,
      poll = function(): {Event} return take(hub, 0) end,
      drop = function(peer: integer)
         if not hub.open[peer] then return end
         hub.open[peer] = nil
         post(hub, 0, peer, { kind = "disconnect", peer = 0 })
         post(hub, peer, 0, { kind = "disconnect", peer = peer })
      end,
      close = function()
         for peer in pairs(hub.open) do post(hub, 0, peer, { kind = "disconnect", peer = 0 }) end
         hub.open = {}
         hub.queues[0] = nil
      end,
   }
end

--- A new client's end of `hub`, connecting as it's made.
function link.connect(hub: Hub): Link
   hub.ends = hub.ends + 1
   local me = hub.ends
   hub.queues[me] = {}
   hub.open[me] = true
   post(hub, me, 0, { kind = "connect", peer = me })
   post(hub, 0, me, { kind = "connect", peer = 0 })
   return {
      send = function(_: integer, data: string)
         if not hub.open[me] then return end
         if hub.sent then hub.sent(me, 0, data) end
         post(hub, me, 0, { kind = "receive", peer = me, data = data })
      end,
      poll = function(): {Event} return take(hub, me) end,
      drop = function()
         if not hub.open[me] then return end
         hub.open[me] = nil
         post(hub, me, 0, { kind = "disconnect", peer = me })
      end,
      close = function()
         if hub.open[me] then
            hub.open[me] = nil
            post(hub, me, 0, { kind = "disconnect", peer = me })
         end
      end,
   }
end

return link
