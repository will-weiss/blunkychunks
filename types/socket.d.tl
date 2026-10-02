--- The slice of LuaSocket (bundled with LOVE 11.4) used to find this
--- machine's address on the local network.

local record socket
   record UDP
      userdata
      setpeername: function(UDP, string, integer): integer, string
      getsockname: function(UDP): string, integer
      close: function(UDP)
   end

   udp: function(): UDP
end

return socket
