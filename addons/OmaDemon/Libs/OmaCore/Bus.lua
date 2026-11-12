-- Bus: a small event hub. Listeners run in the order they subscribed; each one is error-guarded, so one failing
-- listener never stops the others (the error goes to the bus's onError).
local _, ns = ...
local Core = ns.omaCoreBuild
if not Core then return end

local Bus = {}
Bus.__index = Bus
Core.BusMethods = Bus

function Core.NewBus(onError) return setmetatable({ map = {}, onError = onError }, Bus) end

function Bus:On(event, fn)
  if type(fn) ~= 'function' then error('Bus:On wants a function', 2) end
  local old, l = self.map[event] or {}, {}
  for i = 1, #old do l[i] = old[i] end            -- copy on write: a Fire in progress keeps its own list
  l[#l + 1] = fn; self.map[event] = l
  return fn
end

function Bus:Off(event, fn)
  local old = self.map[event]; if not old then return end
  local l = {}
  for i = 1, #old do if old[i] ~= fn then l[#l + 1] = old[i] end end
  self.map[event] = (#l > 0) and l or nil
end

function Bus:Fire(event, ...)
  local l = self.map[event]; if not l then return end
  for i = 1, #l do
    local ok, err = pcall(l[i], ...)
    if not ok and self.onError then pcall(self.onError, event, err) end
  end
end

function Bus:Has(event) return self.map[event] ~= nil end
