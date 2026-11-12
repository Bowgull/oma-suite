-- OmaDoomed's DoT tracking: the glue between the engine (Track/Engine.lua, built from DoesItDie by
-- tools/import_doesitdie.py) and OmaDoomed. Loaded first in Track/.
--
-- The engine keeps its own namespace, OMA.track, so its names (db, refresh, display...) never meet OmaDoomed's.
-- It was written to drive a display; OmaDoomed draws its own, so the display hooks here do nothing, and refresh
-- runs the engine's housekeeping (expiry, missed ticks) and tells OmaDoomed something may have changed.
--
-- What OmaDoomed reads:  ns.dotsFor(unit)  -> list of { name, spellID, school, damage, appliedAt, expiresAt,
-- provisional }, oldest first, damage rounded (ns.dotsRaw: the same, uncopied). ns.trackOff() switches every tracking frame off (other classes).
local _, OMA = ...
local T = {}
OMA.track = T

local function noop() end
T.display = setmetatable({
  schoolColors = {},
  attach = function() return true end,        -- "found the target frame": OmaDoomed attaches its own
  hasHealthBar = function() return true end,
}, { __index = function() return noop end })
T.registerOptions, T.openOptions, T.playFlash = noop, noop, noop
T.probeNameplates, T.toggleExecuteProbe, T.toggleTickViewer = noop, noop, noop

-- The engine calls this every 0.1 s and after casts, ticks and target changes. T.omaHousekeep: Forever.lua's pruning.
function T.refresh()
  if T.tracking then
    local now = GetTime()
    T.tracking.housekeep(now)
    if T.omaHousekeep then T.omaHousekeep(now) end
  end
  if OMA.onTrackChanged then OMA.onTrackChanged() end
end

-- every tracking frame's off switch (Engine, Wrack, Forever); Core.lua calls this for other classes
local offs = {}
function OMA.trackOffWith(fn) offs[#offs + 1] = fn end
function OMA.trackOff()
  if T.tracking and T.tracking.off then T.tracking.off() end
  for _, fn in ipairs(offs) do fn() end
end

function OMA.dotsFor(unit)
  if not T.tracking or type(unit) ~= 'string' then return {} end
  local okKey, key = pcall(T.tracking.unitKey, unit)
  if not okKey or not key then return {} end
  local list = T.dotBreakdownForUnit(unit)
  local out = {}
  for i, e in ipairs(list) do
    out[i] = { name = e.name, spellID = e.spellID, school = e.school, damage = math.floor(e.damage + 0.5),
      appliedAt = e.appliedAt, expiresAt = e.expiresAt, provisional = e.provisional or false }
  end
  return out
end
-- A number that changes whenever the engine's DoTs on the mob behind `unit` change (a tick, a miss, a cast, a
-- refresh, an expiry). Cheap and makes no tables: the kill bar asks it on every health change to tell a DoT's tick
-- from anyone else's hit. nil when it can't tell (then treat it as changed).
local function stamp(unit)
  local okKey, key = pcall(T.tracking.unitKey, unit)
  if not okKey or not key then return 0 end
  local dots = T.tracking.dotsByTarget and T.tracking.dotsByTarget[key]
  if not dots then return 0 end
  local s, n = 0, 0
  for _, d in pairs(dots) do
    n = n + 1
    s = s + (d.nextTickAt or 0) * 1.7 + (d.expiresAt or 0) * 1.3 + (d.appliedAt or 0) + (d.lastTickAt or 0) * .7
      + (d.ticksSeen or 0) * 7 + (d.missed or 0) * 11 + (d.tickSum or 0) * .01 + (d.omaScale or 1) * 13
  end
  return s + n * 1000
end
function OMA.dotsStamp(unit)
  if not T.tracking then return 0 end
  local ok, v = pcall(stamp, unit)
  if ok then return v end
end
-- The same list without the copy (the engine makes a fresh one per call): damage rounded in place. For the views,
-- which read it at once and keep nothing. An empty answer is one shared table: never write to it.
local EMPTY = {}
function OMA.dotsRaw(unit)
  if not T.tracking or type(unit) ~= 'string' then return EMPTY end
  local okKey, key = pcall(T.tracking.unitKey, unit)
  if not okKey or not key then return EMPTY end
  local list = T.dotBreakdownForUnit(unit)
  for _, e in ipairs(list) do e.damage = math.floor(e.damage + 0.5); e.provisional = e.provisional or false end
  return list
end
