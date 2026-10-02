local wire = require("wire")
local A = require("tests.assert")

local record T
end

function T.a_message_comes_back_as_it_went()
   local msg = wire.decode(wire.encode({
      t = "shot", p = 2, k = -7, cells = { 10, 1, 11, 3 }, on = true, off = false,
      name = "a {tricky} s3:name;", nested = { deep = { x = 1 } },
   }))
   A.eq(msg.t, "shot", "string")
   A.eq(wire.int(msg, "k"), -7, "negative integer")
   A.eq(table.concat(wire.ints(msg, "cells"), ","), "10,1,11,3", "list")
   A.eq(msg.on, true, "true")
   A.eq(msg.off, false, "false")
   A.eq(msg.name, "a {tricky} s3:name;", "a string that looks like the format")
   A.eq(((msg.nested as {string: any}).deep as {string: any}).x, 1, "nested tables")
end

function T.floats_and_functions_are_refused()
   A.truthy(not pcall(wire.encode, { x = 0.5 }), "a float")
   A.truthy(not pcall(wire.encode, { f = print }), "a function")
end

function T.garbage_is_dropped_not_run()
   for _, bad in ipairs({ "", "{", "{s1:t", "{s1:ti5}", "{s1:ts99:x}", "i5;", "{s1:ti5;}x", "os.exit()",
                          ("{s1:a"):rep(40) }) do
      local msg, err = wire.decode(bad)
      A.eq(msg, nil, "dropped: " .. bad)
      A.truthy(err, "with a reason")
   end
end

function T.typed_fields_ignore_the_wrong_type()
   local msg = wire.decode(wire.encode({ n = "5", s = 5, l = { 1, "x" } }))
   A.eq(wire.int(msg, "n"), nil, "a string isn't an integer")
   A.eq(wire.str(msg, "s"), nil, "an integer isn't a string")
   A.eq(wire.ints(msg, "l"), nil, "nor is a mixed list a list of integers")
end

return T
