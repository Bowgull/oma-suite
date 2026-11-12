-- OmaDoomed's start-up: saved data (OmaDoomedDB, upgraded by numbered steps, defaults from the settings table in
-- Settings.lua), the log, the bus, /omadoomed. Warlocks only: on any other class nothing is built, no events are
-- registered and no game setting is touched.
local ADDON, ns = ...
local Core = LibStub('OmaCore-1.0')
ns.omaCoreBuild = nil
ns.core = Core
ns.say = function(m) print('|cffb48cffOmaDoomed:|r ' .. tostring(m)) end
ns.parts = {}      -- kill bar parts with on/off and a slash (doomed, platebar)
ns.starts = {}     -- start functions, run in file order at a warlock's login

-- errors are kept (last 30, saved on /reload) instead of popping up: /omadoomed errors shows them
ns.log = Core.NewLog({ name = ADDON, store = function() return OmaDoomedDB end, say = ns.say, report = '/omadoomed report' })
function ns.err(m) ns.log:Note(m) end              -- diagnostics
function ns.error(m) ns.log:Error(m) end           -- a caught error; nothing stopped
function ns.fail(m, part) ns.log:Fail(m, part) end -- a caught error that switched `part` off for the session
ns.bus = Core.NewBus(function(event, err) ns.log:Error(tostring(event) .. ': ' .. tostring(err)) end)

function ns.isWarlock()
  local ok, class = pcall(function() return select(2, UnitClass('player')) end)
  return ok and class == 'WARLOCK'
end

local function slash()
  local s = Core.NewSlash('OMADOOMED', '/omadoomed', function(m)
    local p = ns.parts.doomed
    if p and p.slash then return p.slash(m) end
  end, function(err) ns.error('slash: ' .. tostring(err)) end)
  s:Word('rings', function(rest) return ns.ringsSlash and ns.ringsSlash(rest) end)
  s:Exact('report', function() return ns.saveReport and ns.saveReport('command') end)
  s:Exact('report show', function() return ns.showReport and ns.showReport() end)
  s:Exact('cpu', function() if ns.perf then for _, l in ipairs(ns.perfLines(ns.perf())) do print(l) end end end)
  s:Exact('errors', function() local e = ns.log:List(); for i = math.min(8, #e), 1, -1 do print(e[i]) end end)
  s:Exact('options', function() return ns.openSettings and ns.openSettings() end)
  s:Exact('settings', function() return ns.openSettings and ns.openSettings() end)
end

local f = CreateFrame('Frame')
f:RegisterEvent('ADDON_LOADED')
f:SetScript('OnEvent', function(self, event, name)
  if event == 'ADDON_LOADED' then
    if name ~= ADDON then return end
    self:UnregisterEvent('ADDON_LOADED')
    OmaDoomedDB = OmaDoomedDB or {}
    if ns.settings then
      ns.settings:Migrate(OmaDoomedDB, ns.MIGRATIONS or {}, ns.error)
      ns.settings:Fill(OmaDoomedDB)
    end
    ns.db = OmaDoomedDB
    if not ns.isWarlock() then return end
    ns.warlock = true
    slash()
    if ns.buildSettings then
      local ok, err = pcall(ns.buildSettings)
      if not ok then ns.say('settings page failed: ' .. tostring(err)) end
    end
    self:RegisterEvent('PLAYER_LOGIN')
  elseif event == 'PLAYER_LOGIN' then
    self:UnregisterEvent('PLAYER_LOGIN')
    if ns.spells then pcall(ns.spells.learnClientNames) end
    for _, p in pairs(ns.parts) do local ok, err = pcall(p.start); if not ok then ns.error('start: ' .. tostring(err)) end end
    for _, s in ipairs(ns.starts) do local ok, err = pcall(s); if not ok then ns.error('start: ' .. tostring(err)) end end
  end
end)
