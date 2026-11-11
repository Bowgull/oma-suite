-- WoW: Forever rules the tracking needs that DoesItDie doesn't know (OmaDoomed's own; see
-- reports/OmaDoomed blind spots.md and reports/Forever warlock DoT audit.md).
--   * One Bane per warlock per target: Bane of Doom or Bane of Havoc replaces your Bane of Agony on that mob.
--   * A mob that evades (resets) loses your DoTs.
--   * Amplify Curse: your next Bane of Agony does 50% more (the buff lasts 30 s).
-- (A DoT that stops ticking is dropped by the engine itself after two missed ticks: Track/Engine.lua, "OMA".)
local _, OMA = ...
local T = OMA.track

local AGONY = { ['Bane of Agony'] = true, ['Curse of Agony'] = true }
local REPLACES_AGONY = { ['Bane of Doom'] = true, ['Bane of Havoc'] = true }
local AMPLIFY_SECONDS, AMPLIFY = 30, 1.5

local amplifyUntil = 0

local function readable(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end
local function spellName(id)
  if not readable(id) then return nil end
  local get = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
  local ok, name = pcall(get, id)
  if ok and readable(name) and type(name) == 'string' then return name end
end
local function dotsAt(key) return key and T.tracking and T.tracking.dotsByTarget[key] end

local f = CreateFrame('Frame')
f:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
f:RegisterEvent('UNIT_COMBAT')
f:SetScript('OnEvent', function(_, event, unit, a2, a3)
  if not T.tracking then return end
  if event == 'UNIT_SPELLCAST_SUCCEEDED' then
    local castGUID, spellID = a2, a3
    local name = spellName(spellID)
    if not name then return end
    if name == 'Amplify Curse' then amplifyUntil = GetTime() + AMPLIFY_SECONDS; return end
    local key = readable(castGUID) and T.tracking.castTargetKey(castGUID) or nil
    local dots = dotsAt(key)
    if REPLACES_AGONY[name] and dots then
      for n in pairs(AGONY) do
        if dots[n] then dots[n] = nil; T.tracking.trace('DROP ' .. n .. ': replaced by ' .. name) end
      end
      T.refresh()
    elseif AGONY[name] and GetTime() < amplifyUntil then
      amplifyUntil = 0
      local dot = dots and (dots['Bane of Agony'] or dots['Curse of Agony'])
      if dot then dot.omaScale = AMPLIFY; T.tracking.trace(name .. ': Amplify Curse, +50%'); T.refresh() end
    end
  elseif event == 'UNIT_COMBAT' then
    local action = a2
    if not readable(action) or action ~= 'EVADE' then return end
    local okKey, key = pcall(T.tracking.unitKey, unit)
    if okKey and key and T.tracking.dotsByTarget[key] then
      T.tracking.dotsByTarget[key] = nil
      T.tracking.trace('DROP all DoTs on ' .. tostring(key) .. ': it evaded (reset)')
      T.refresh()
    end
  end
end)
