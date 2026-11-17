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
-- a line said once per account, ever (a found add-on, the first hello): OmaDoomedDB.told[key]
function ns.tellOnce(key, msg)
  local db = OmaDoomedDB; if not db then return end
  db.told = db.told or {}
  if db.told[key] then return end
  db.told[key] = true; ns.say(msg)
end
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
  s:Word('list', function(rest) return ns.moblist and ns.moblist.slash(rest) end)
  s:Word('cc', function(rest) return ns.ccSlash and ns.ccSlash(rest) end)
  s:Exact('report', function() return ns.saveReport and ns.saveReport('command') end)
  s:Exact('report show', function() return ns.showReport and ns.showReport() end)
  s:Exact('cpu', function() if ns.perf then for _, l in ipairs(ns.perfLines(ns.perf())) do print(l) end end end)
  s:Exact('errors', function() local e = ns.log:List(); for i = math.min(8, #e), 1, -1 do print(e[i]) end end)
  s:Exact('options', function() return ns.openSettings and ns.openSettings() end)
  s:Exact('glyph', function() return ns.rings and ns.rings.glyphTest and ns.rings.glyphTest() end)
  -- /omadoomed ending: when each DoT lights, where that number comes from, and whether the curves are up to date
  s:Exact('ending', function()
    local R = ns.rings; if not (R and R.windowFor) then return end
    local out = {}
    local function line(m) out[#out + 1] = m; print('|cffb48cffOmaDoomed ending|r ' .. m) end
    for _, k in ipairs(R.SEATS or {}) do line(('%s: lights at %.1f s left (%s)'):format(k, R.windowFor(k), R.windowSource(k))) end
    line(('kill bar on your target: same windows; crowd control and other debuffs: %d s (Ending soon)'):format(R.lowSecs and R.lowSecs() or 5))
    line(('curves built on %s; now %s -> %s'):format(tostring(R.builtOn), R.castPrint(), R.builtOn == R.castPrint() and 'up to date' or 'STALE (rebuilding)'))
    if R.builtOn ~= R.castPrint() and R.recheckWindows then R.recheckWindows() end
    line(('ring font %s, measured %s, band light %s, outer glow %s, breathing %s'):format(tostring(R.GLYPH), tostring(R.GLYPH_MEASURED), tostring(R.GLYPH_LIGHT), tostring(R.HALO), tostring(not (ns.db and ns.db.lowlook == 'steady'))))
    ns.db.ending = out
  end)
  -- the tracking's trace log, for bug reports (off by default: it costs a line per unmatched hit)
  s:Word('trace', function(rest)
    local t = OmaDoomedDB and OmaDoomedDB.track; if not t then return end
    if rest == 'on' then t.omaTrace = true; t.log = t.log or {} elseif rest == 'off' then t.omaTrace = nil; t.log = {} end
    ns.say('trace log ' .. (t.omaTrace and 'on' or 'off') .. '.')
  end)
  s:Exact('settings', function() return ns.openSettings and ns.openSettings() end)
  -- which bar each plate and the target frame use (for bug reports), and the target frame's bar: pick | clear | <name>
  s:Exact('plates', function() if ns.barLines then for _, l in ipairs(ns.barLines()) do ns.say(l) end end end)
  s:Word('frame', function(rest) return ns.frameSlash and ns.frameSlash(rest) end, true)
end

local fresh   -- no saved data before this login: a new install
local f = CreateFrame('Frame')
f:RegisterEvent('ADDON_LOADED')
f:SetScript('OnEvent', function(self, event, name)
  if event == 'ADDON_LOADED' then
    if name ~= ADDON then return end
    self:UnregisterEvent('ADDON_LOADED')
    fresh = OmaDoomedDB == nil or next(OmaDoomedDB) == nil
    OmaDoomedDB = OmaDoomedDB or {}
    if ns.settings then
      ns.settings:Migrate(OmaDoomedDB, ns.MIGRATIONS or {}, ns.error)
      ns.settings:Fill(OmaDoomedDB)
    end
    ns.db = OmaDoomedDB
    if not ns.isWarlock() then if ns.trackOff then ns.trackOff() end; return end
    ns.warlock = true
    slash()
    if ns.buildSettings then
      local ok, err = pcall(ns.buildSettings)
      if ok and ns.previewStart then pcall(ns.previewStart) end   -- the preview window docks beside Options (sheet 60)
      if not ok then ns.say('settings page failed: ' .. tostring(err)) end
    end
    self:RegisterEvent('PLAYER_LOGIN')
  elseif event == 'PLAYER_LOGIN' then
    self:UnregisterEvent('PLAYER_LOGIN')
    if ns.spells then pcall(ns.spells.learnClientNames) end
    for _, p in pairs(ns.parts) do local ok, err = pcall(p.start); if not ok then ns.error('start: ' .. tostring(err)) end end
    for _, s in ipairs(ns.starts) do local ok, err = pcall(s); if not ok then ns.error('start: ' .. tostring(err)) end end
    -- one hello per account: what it is (a new install) or what changed (an upgrade), and where the settings are
    if ns.hello then ns.tellOnce('hello1', fresh and ns.hello.new or ns.hello.upgrade) end
  end
end)
