-- OmaDoomed's DoT tracking: the glue between the engine (Track/Engine.lua, built from DoesItDie by
-- tools/import_doesitdie.py) and OmaDoomed. Loaded first in Track/.
--
-- The engine keeps its own namespace, OMA.track, so its names (db, refresh, display...) never meet OmaDoomed's.
-- It was written to drive a display; OmaDoomed draws its own, so the display hooks here do nothing, and refresh
-- runs the engine's housekeeping (expiry, missed ticks) and tells OmaDoomed something may have changed.
--
-- What OmaDoomed reads:  ns.dotsFor(unit)  -> list of { name, spellID, school, damage, appliedAt, expiresAt,
-- provisional }, oldest first, damage rounded (the same shape DoesItDie.GetDoTs gives).
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

-- The engine calls this every 0.1 s and after casts, ticks and target changes.
function T.refresh()
  if T.tracking then T.tracking.housekeep(GetTime()) end
  if OMA.onTrackChanged then OMA.onTrackChanged() end
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
