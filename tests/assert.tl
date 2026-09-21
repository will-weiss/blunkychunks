--- Tiny assertion helpers shared by the test suites.

local record assert_
end

function assert_.eq(got: any, want: any, msg: string)
   if got ~= want then
      error(("%s: got %s, want %s"):format(msg or "eq", tostring(got), tostring(want)), 2)
   end
end

function assert_.near(got: number, want: number, msg: string)
   if math.abs(got - want) > 1e-6 then
      error(("%s: got %s, want %s"):format(msg or "near", tostring(got), tostring(want)), 2)
   end
end

function assert_.truthy(v: any, msg: string)
   if not v then error((msg or "expected truthy") .. ": got " .. tostring(v), 2) end
end

return assert_
