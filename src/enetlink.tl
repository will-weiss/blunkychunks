--- link.tl's Link over UDP with ENet, which ships inside LOVE. Messages go
--- reliably and in order on one channel. Only the LOVE build loads this.

local enet = require("enet")
local socket = require("socket")
local link = require("link")

local record enetlink
end

local CHANNELS <const> = 1
local MAX_PEERS <const> = 32

--- Drain `host`'s events into link events, numbering peers by `id_of`.
local function drain(host: enet.Host, id_of: function(enet.Peer): integer, gone: function(enet.Peer)): {link.Event}
   local out: {link.Event} = {}
   local e = host:service(0)
   while e do
      local id = id_of(e.peer)
      if e.type == "connect" then
         out[#out + 1] = { kind = "connect", peer = id }
      elseif e.type == "disconnect" then
         out[#out + 1] = { kind = "disconnect", peer = id }
         gone(e.peer)
      elseif e.type == "receive" and type(e.data) == "string" then
         out[#out + 1] = { kind = "receive", peer = id, data = e.data as string }
      end
      e = host:service(0)
   end
   return out
end

--- A server listening on `port` on every interface, or nil and why not.
function enetlink.serve(port: integer): link.Link, string
   local host = enet.host_create(("*:%d"):format(port), MAX_PEERS, CHANNELS)
   if not host then return nil, ("can't listen on port %d (is something else using it?)"):format(port) end
   local peers: {integer: enet.Peer} = {}
   local function id_of(peer: enet.Peer): integer
      local id = peer:index()
      peers[id] = peer
      return id
   end
   return {
      send = function(id: integer, data: string)
         local peer = peers[id]
         if peer then peer:send(data, 0, "reliable") end
      end,
      poll = function(): {link.Event}
         local events = drain(host, id_of, function(peer: enet.Peer) peers[peer:index()] = nil end)
         host:flush()
         return events
      end,
      drop = function(id: integer)
         local peer = peers[id]
         if peer then peer:disconnect() end
      end,
      close = function()
         for _, peer in pairs(peers) do peer:disconnect() end
         host:flush()
         host:destroy()
      end,
   }
end

--- A client connecting to `address` ("host" or "host:port", the port
--- defaulting to `port`), or nil and why not.
function enetlink.connect(address: string, port: integer): link.Link, string
   if not address:find(":") then address = ("%s:%d"):format(address, port) end
   local host = enet.host_create(nil, 1, CHANNELS)
   if not host then return nil, "can't open a network socket" end
   local ok, peer = pcall(host.connect, host, address, CHANNELS) as (boolean, enet.Peer)
   if not ok or not peer then return nil, ("can't reach %s"):format(address) end
   local open = true
   return {
      send = function(_: integer, data: string)
         if open then peer:send(data, 0, "reliable") end
      end,
      poll = function(): {link.Event}
         if not open then return {} end
         local events = drain(host, function(): integer return 0 end, function() open = false end)
         host:flush()
         return events
      end,
      drop = function()
         if open then peer:disconnect() end
      end,
      close = function()
         if open then
            peer:disconnect_now()
            open = false
         end
         host:flush()
         host:destroy()
      end,
   }
end

--- This machine's address on the local network, as others would reach it
--- (nil if it can't tell). Nothing is sent: pointing a UDP socket somewhere
--- just makes the system pick the interface it would use.
function enetlink.local_address(): string
   local udp = socket.udp()
   if not udp then return nil end
   udp:setpeername("192.0.2.1", 9)
   local ip = udp:getsockname()
   udp:close()
   if not ip or ip == "0.0.0.0" then return nil end
   return ip
end

return enetlink
