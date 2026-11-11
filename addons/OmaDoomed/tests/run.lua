-- Offline test runner:  luajit tests/run.lua [pattern]   (from the OmaDoomed folder)
-- Each tests/test_*.lua returns (require helpers like 'load' INSIDE each test, so every test gets a fresh world) a table of name -> function(W, T). Every test gets a fresh fake WoW.
package.path = './tests/?.lua;' .. package.path
local pattern = arg[1]
local files = {}
for f in io.popen('ls tests/test_*.lua 2>/dev/null'):lines() do files[#files + 1] = f end
local pass, fail = 0, 0
local T = {}
function T.eq(a, b, msg) if a ~= b then error((msg or 'eq') .. ': expected ' .. tostring(b) .. ', got ' .. tostring(a), 2) end end
function T.near(a, b, tol, msg) if math.abs(a - b) > (tol or 1e-6) then error((msg or 'near') .. ': expected ' .. tostring(b) .. ' +-' .. tostring(tol) .. ', got ' .. tostring(a), 2) end end
function T.ok(v, msg) if not v then error(msg or 'expected true', 2) end end
for _, file in ipairs(files) do
  local suite = dofile(file)
  local names = {}; for n in pairs(suite) do names[#names + 1] = n end; table.sort(names)
  for _, n in ipairs(names) do
    if not pattern or (file .. ' ' .. n):find(pattern, 1, true) then
      -- fresh world: drop the fake and everything it defined
      local savedMods = {}; for k in pairs(package.loaded) do savedMods[k] = true end
      local saved = {}; for k, v in pairs(_G) do saved[k] = v end
      local W = require('fakewow')
      local ok, err = xpcall(function() suite[n](W, T) end, debug.traceback)
      setmetatable(_G, nil)
      for k in pairs(_G) do if saved[k] == nil then _G[k] = nil end end
      for k, v in pairs(saved) do _G[k] = v end
      for k in pairs(package.loaded) do if not savedMods[k] then package.loaded[k] = nil end end
      if ok then pass = pass + 1 else fail = fail + 1; io.write('FAIL ' .. file .. ' :: ' .. n .. '\n  ' .. tostring(err):gsub('\n', '\n  ') .. '\n') end
    end
  end
end
io.write(('%d passed, %d failed\n'):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
