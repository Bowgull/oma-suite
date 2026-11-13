-- A small fake of the WoW client for offline tests (LuaJIT = Lua 5.1, like WoW).
-- What it gives: a clock you move by hand, frames that take events, an event bus, units you describe with tables,
-- secret values (Forever hides numbers in combat), and a loader that runs add-on files the way WoW does.
-- Anything an add-on calls that isn't faked here raises an error naming it, so a missing stub is never silent.
local W = {}

-- ---------- clock ----------
W.now = 1000
function GetTime() return W.now end
function debugprofilestop() return os.clock() * 1000 end   -- the game's millisecond stopwatch
function GetTimePreciseSec() return W.now end
function W.advance(dt, step)
  step = step or 0.1
  local target = W.now + dt
  while W.now < target - 1e-9 do
    W.now = math.min(target, W.now + step)
    W.runUpdates(step)
  end
end

-- ---------- secret values ----------
-- A secret is a table WoW code can pass around but must not compare or do maths on. Any arithmetic or comparison
-- raises, like Forever's real secrets do.
local SECRET = {}
local function boom() error('attempt to use a secret value', 2) end
SECRET.__index = boom; SECRET.__add = boom; SECRET.__sub = boom; SECRET.__mul = boom; SECRET.__div = boom
SECRET.__lt = boom; SECRET.__le = boom; SECRET.__unm = boom; SECRET.__concat = boom
SECRET.__tostring = function() return '<secret>' end
function W.secret(v) return setmetatable({ v = v }, SECRET) end
function issecretvalue(v) return getmetatable(v) == SECRET end
function W.reveal(v) if issecretvalue(v) then return rawget(v, 'v') end return v end

-- ---------- frames and events ----------
-- Every frame is kept in creation order. Events and OnUpdates only walk the frames that ever asked for them (kept in
-- creation order too), so thousands of quiet frames (aura buttons, cooldowns) cost nothing per event.
local frames, listening, updating = {}, {}, {}
W.frames = frames
local function enlist(list, f, flag)
  if rawget(f, flag) then return end   -- rawget: UI fakes answer any unknown key
  rawset(f, flag, true)
  local i = #list
  while i > 0 and rawget(list[i], 'idx') > rawget(f, 'idx') do i = i - 1 end
  table.insert(list, i + 1, f)
end
local Frame = {}
Frame.__index = Frame
W.Frame = Frame
function Frame:RegisterEvent(e) self.events[e] = true; enlist(listening, self, '_listens') end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:RegisterUnitEvent(e, ...) self.events[e] = { ... }; enlist(listening, self, '_listens') end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:IsEventRegistered(e) return self.events[e] ~= nil end
function Frame:SetScript(k, f) self.scripts[k] = f; if k == 'OnUpdate' and f then enlist(updating, self, '_updates') end end
function Frame:GetScript(k) return self.scripts[k] end
function Frame:HookScript(k, f) local old = self.scripts[k]; self:SetScript(k, function(...) if old then old(...) end; f(...) end) end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:SetShown(v) self.shown = v and true or false end
function Frame:GetName() return self.name end
function CreateFrame(kind, name, parent)
  local f = setmetatable({ kind = kind, name = name, parent = parent, events = {}, scripts = {}, shown = true, idx = #frames + 1 }, Frame)
  frames[#frames + 1] = f
  if name then _G[name] = f end
  return f
end
-- A stamp per call keeps a frame from being called twice if an older frame joins the list mid-call.
local stamp = 0
function W.fire(event, ...)
  stamp = stamp + 1
  local my, i = stamp, 1
  while listening[i] do
    local f = listening[i]; i = i + 1
    local reg = f.events[event]
    if reg and f.scripts.OnEvent and rawget(f, '_fired') ~= my then
      rawset(f, '_fired', my)
      local ok = true
      if type(reg) == 'table' and #reg > 0 then
        ok = false; local unit = ...
        for _, u in ipairs(reg) do if u == unit then ok = true end end
      end
      if ok then f.scripts.OnEvent(f, event, ...) end
    end
  end
end
function W.runUpdates(dt)
  local i = 1
  while updating[i] do
    local f = updating[i]; i = i + 1
    if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end
  end
end
C_Timer = {
  After = function(s, fn) W.timers[#W.timers + 1] = { at = W.now + s, fn = fn } end,
  NewTimer = function(s, fn) local t = { at = W.now + s, fn = fn, Cancel = function(self) self.dead = true end }; W.timers[#W.timers + 1] = t; return t end,
  NewTicker = function(s, fn) local t = { every = s, at = W.now + s, fn = fn, Cancel = function(self) self.dead = true end }; W.timers[#W.timers + 1] = t; return t end,
}
W.timers = {}
local timerFrame = CreateFrame('Frame')
timerFrame:SetScript('OnUpdate', function()
  local due = {}
  for i = #W.timers, 1, -1 do local t = W.timers[i]; if t.dead then table.remove(W.timers, i) elseif W.now >= t.at then due[#due + 1] = t end end
  for _, t in ipairs(due) do
    if t.every then t.at = t.at + t.every else for i, x in ipairs(W.timers) do if x == t then table.remove(W.timers, i) break end end end
    t.fn(t)
  end
end)

-- ---------- units ----------
-- W.units[token] = { guid=, name=, hp=, maxhp=, enemy=true, dead=false }. Health reads are secret while W.combat.
W.units = {}
W.combat = false
local function U(t) return W.units[t] end
function UnitExists(t) return U(t) ~= nil end
function UnitGUID(t) local u = U(t); if not u then return nil end; if u.secretGuid then return W.secret(u.guid) end; return u.guid end
function UnitName(t) return U(t) and U(t).name end
function UnitIsDead(t) return U(t) and U(t).dead or false end
function UnitIsDeadOrGhost(t) return UnitIsDead(t) end
function UnitCanAttack(a, t) return U(t) ~= nil and U(t).enemy or false end
function UnitIsUnit(a, b) return U(a) ~= nil and U(a) == U(b) end
function UnitIsPlayer(t) return U(t) and U(t).player or false end
function UnitLevel(t) return U(t) and U(t).level or 1 end
function UnitHealth(t) local u = U(t); if not u then return 0 end; return W.combat and W.secret(u.hp) or u.hp end
function UnitHealthMax(t) local u = U(t); if not u then return 0 end; return W.combat and W.secret(u.maxhp) or u.maxhp end
function InCombatLockdown() return W.combat end
function UnitAffectingCombat(t) return W.combat end
function IsInGroup() return W.group or false end
function IsInRaid() return false end
function GetLocale() return W.locale or 'enUS' end

-- ---------- misc ----------
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
function tinsert(t, ...) return table.insert(t, ...) end
function tremove(t, ...) return table.remove(t, ...) end
strsplit = function(sep, s) local out = {}; for p in (s .. sep):gmatch('(.-)' .. sep:gsub('%p', '%%%0')) do out[#out + 1] = p end; return unpack(out) end
function hooksecurefunc(a, b, c) local t, k, f = a, b, c; if type(a) == 'string' then t, k, f = _G, a, b end; local old = t[k]; t[k] = function(...) local r = { old(...) }; f(...); return unpack(r) end end
W.printed = {}
function print(...) local p = {}; for i = 1, select('#', ...) do p[i] = tostring((select(i, ...))) end; W.printed[#W.printed + 1] = table.concat(p, ' ') end
date = os.date
SlashCmdList = {}

-- ---------- loader ----------
-- Runs add-on files in order with WoW's (addonName, ns) varargs. Returns ns.
function W.load(dir, addon, files, ns)
  ns = ns or {}
  for _, f in ipairs(files) do
    local chunk, err = loadfile(dir .. '/' .. f)
    if not chunk then error('load ' .. f .. ': ' .. err) end
    chunk(addon, ns)
  end
  return ns
end

-- Strict globals: reading an undefined global raises, naming it (call W.strict() after the add-on's own globals load
-- if you want saved variables to be nil-able: list them in allow).
function W.strict(allow)
  allow = allow or {}
  setmetatable(_G, { __index = function(_, k) if allow[k] then return nil end; error('fakewow: no stub for global "' .. tostring(k) .. '"', 2) end })
end
return W
