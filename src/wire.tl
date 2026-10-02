--- How messages go over the network: a table of integers, strings,
--- booleans and nested tables, written as a string and read back. The
--- reader never runs what it reads (no `load`), and gives up with an error
--- on anything malformed, so a bad packet can be dropped.
---
---   i<digits>;      an integer (negative too)
---   s<len>:<bytes>  a string
---   T  F            true, false
---   { k v k v ... } a table: each key then its value

local record wire
   type Msg = {string: any}
end

local function put(out: {string}, v: any)
   local t = type(v)
   if t == "number" then
      local n = v as number
      if n ~= math.floor(n) or n ~= n or math.abs(n) > 2 ^ 53 then error("wire: only integers go over the wire") end
      out[#out + 1] = ("i%d;"):format(math.floor(n))
   elseif t == "string" then
      local s = v as string
      out[#out + 1] = "s" .. #s .. ":" .. s
   elseif t == "boolean" then
      out[#out + 1] = v and "T" or "F"
   elseif t == "table" then
      out[#out + 1] = "{"
      for k, x in pairs(v as {any: any}) do
         put(out, k)
         put(out, x)
      end
      out[#out + 1] = "}"
   else
      error("wire: can't send a " .. t)
   end
end

--- `msg` as a string.
function wire.encode(msg: wire.Msg): string
   local out: {string} = {}
   put(out, msg)
   return table.concat(out)
end

local MAX_DEPTH <const> = 16

--- The value at `pos` in `s`, and where the next one starts.
local function get(s: string, pos: integer, depth: integer): any, integer
   if depth > MAX_DEPTH then error("wire: nested too deep") end
   local c = s:sub(pos, pos)
   if c == "i" then
      local digits, after = s:match("^(%-?%d+);()", pos + 1)
      if not digits then error("wire: bad integer at " .. pos) end
      return math.floor(tonumber(digits)), math.floor(after as integer)
   elseif c == "s" then
      local len, after = s:match("^(%d+):()", pos + 1)
      if not len then error("wire: bad string at " .. pos) end
      local from, n = math.floor(after as integer), math.floor(tonumber(len))
      if from + n - 1 > #s then error("wire: string runs past the end") end
      return s:sub(from, from + n - 1), from + n
   elseif c == "T" then
      return true, pos + 1
   elseif c == "F" then
      return false, pos + 1
   elseif c == "{" then
      local t: {any: any} = {}
      pos = pos + 1
      while s:sub(pos, pos) ~= "}" do
         if pos > #s then error("wire: table runs past the end") end
         local k, v: any, any
         k, pos = get(s, pos, depth + 1)
         if type(k) ~= "number" and type(k) ~= "string" then error("wire: bad key") end
         v, pos = get(s, pos, depth + 1)
         t[k] = v
      end
      return t, pos + 1
   end
   error("wire: unexpected '" .. c .. "' at " .. pos)
end

--- The message in `s`, or nil and why not.
function wire.decode(s: string): wire.Msg, string
   local ok, v, pos = pcall(get, s, 1, 0)
   if not ok then return nil, tostring(v) end
   if pos ~= #s + 1 then return nil, "wire: trailing bytes" end
   if type(v) ~= "table" then return nil, "wire: not a message" end
   return v as wire.Msg, nil
end

--- Field `k` of `msg` as an integer, or nil if it isn't one.
function wire.int(msg: wire.Msg, k: string): integer
   local v = msg[k]
   if type(v) == "number" then return math.floor(v as number) end
   return nil
end

--- Field `k` of `msg` as a string, or nil if it isn't one.
function wire.str(msg: wire.Msg, k: string): string
   local v = msg[k]
   if type(v) == "string" then return v as string end
   return nil
end

--- Field `k` of `msg` as a list of integers, or nil if it isn't one.
function wire.ints(msg: wire.Msg, k: string): {integer}
   local v = msg[k]
   if type(v) ~= "table" then return nil end
   local t = v as {any: any}
   local out: {integer} = {}
   for i = 1, #(t as {any}) do
      if type(t[i]) ~= "number" then return nil end
      out[i] = math.floor(t[i] as number)
   end
   return out
end

return wire
