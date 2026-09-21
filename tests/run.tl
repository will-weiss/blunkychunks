--- Minimal test runner: `tl run tests/run.tl` (or `make test`).
---
--- Each tests/*_test.tl module returns a { name = function } table. Every
--- function is run in a pcall; a failure prints its message and the run exits
--- non-zero so `make test` fails.

local suites: {string} = {
   "tests.board_test",
   "tests.sim_test",
}

local passed, failed = 0, 0

for _, name in ipairs(suites) do
   local suite = require(name) as {string: function()}
   local names: {string} = {}
   for k in pairs(suite) do names[#names + 1] = k end
   table.sort(names)
   for _, k in ipairs(names) do
      local ok, err = pcall(suite[k]) as (boolean, any)
      if ok then
         passed = passed + 1
      else
         failed = failed + 1
         print(("FAIL %s.%s\n     %s"):format(name, k, tostring(err)))
      end
   end
end

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
