--- The slice of lua-enet (bundled with LOVE 11.4) that enetlink.tl uses.

local record enet
   record Peer
      userdata
      send: function(Peer, string, ?integer, ?string)
      disconnect: function(Peer, ?integer)
      disconnect_now: function(Peer, ?integer)
      index: function(Peer): integer
      round_trip_time: function(Peer): integer
   end

   record Event
      type: string -- "connect", "disconnect" or "receive"
      peer: Peer
      data: any -- the message for "receive"
      channel: integer
   end

   record Host
      userdata
      connect: function(Host, string, ?integer, ?integer): Peer
      service: function(Host, ?integer): Event
      flush: function(Host)
      destroy: function(Host)
      get_socket_address: function(Host): string
   end

   host_create: function(?string, ?integer, ?integer, ?integer, ?integer): Host
end

return enet
