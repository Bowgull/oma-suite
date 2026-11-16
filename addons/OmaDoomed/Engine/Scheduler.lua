-- Scheduler engine: every repeating job in OmaDoomed runs from one clock. A job runs at most every `every` seconds,
-- or on the next frame when something marks it dirty, and never while its freeze test says wait (the mob list freezes
-- while your mouse is over it, so a row never moves under your cursor). Each run is error-guarded on its own.
--   S.add(name, every, fn[, freeze])   S.mark(name)   S.remove(name)
local ADDON, ns = ...
local S = {}; ns.sched = S

local jobs, order = {}, {}
local clock

local function run(now)
  for i = 1, #order do
    local j = jobs[order[i]]
    if j and (j.dirty or now - j.last >= j.every) and not (j.freeze and j.freeze()) then
      j.last, j.dirty = now, false
      local ok, err = pcall(j.fn, now)
      if not ok and ns.error then ns.error('job ' .. j.name .. ': ' .. tostring(err)) end
    end
  end
end

local function ensure()
  if clock then return end
  clock = CreateFrame('Frame')
  clock:SetScript('OnUpdate', function() run(GetTime()) end)
end

function S.add(name, every, fn, freeze)
  if not jobs[name] then order[#order + 1] = name end
  jobs[name] = { name = name, every = every or 0, fn = fn, freeze = freeze, last = -math.huge, dirty = true }
  ensure()
end
function S.mark(name) local j = jobs[name]; if j then j.dirty = true end end
function S.remove(name)
  jobs[name] = nil
  for i = #order, 1, -1 do if order[i] == name then table.remove(order, i) end end
end
S.run = run   -- tests
