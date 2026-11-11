-- WoW: Forever rules the tracking needs that DoesItDie doesn't know (OmaDoomed's own; see
-- reports/OmaDoomed blind spots.md and reports/Forever warlock DoT audit.md).
--   * One Bane per warlock per target: Bane of Doom or Bane of Havoc replaces your Bane of Agony on that mob.
--   * A mob that evades (resets) loses your DoTs.
--   * Amplify Curse: your next Bane of Agony does 50% more (the buff lasts 30 s). Curse of Weakness or Curse of
--     Exhaustion use it up too.
--   * Conflagrate eats your Immolate, unless Shadow and Flame keeps it (20% chance per rank: at 5/5 always kept; at
--     1-4 it may or may not, so the engine's missed-tick rule decides).
--   * Curse of the Elements on a mob: magic damage taken +4/6/8/10% by rank, 5 min, for every DoT of yours on it.
--     Your next other Curse on that mob ends it (one Curse per warlock per target).
--   * Shadow and Flame: after Conflagrate, Shadow damage +4% per rank for 20 s; after Shadowburn, Fire the same.
-- Sources: reports/Forever warlock full catalog.md (game client data, build 1.60.1.70888).
-- (A DoT that stops ticking is dropped by the engine itself after two missed ticks: Track/Engine.lua, "OMA".)
local _, OMA = ...
local T = OMA.track

local function readable(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end
local AGONY = { ['Bane of Agony'] = true, ['Curse of Agony'] = true }
local REPLACES_AGONY = { ['Bane of Doom'] = true, ['Bane of Havoc'] = true }
local AMPLIFY_SECONDS, AMPLIFY = 30, 1.5
local AMPLIFY_EATERS = { ['Curse of Weakness'] = true, ['Curse of Exhaustion'] = true }
local CURSES = { ['Curse of Weakness'] = true, ['Curse of Recklessness'] = true, ['Curse of Tongues'] = true,
  ['Curse of Exhaustion'] = true, ['Curse of the Elements'] = true }
local COE_SECONDS, COE_BY_RANK = 300, { 4, 6, 8, 10 }
local SF_SECONDS, SF_PER_RANK = 20, 4
local SHADOW, FIRE = 32, 4

local amplifyUntil = 0
local coe = {}                 -- mob key -> { pct, untilT }
local sfShadowUntil, sfFireUntil = 0, 0

-- Talent ranks, read out of combat (Classic-style talent API; anything missing reads as 0).
local talents = {}
local function readTalents()
  if InCombatLockdown and InCombatLockdown() then return end
  if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return end
  local ok = pcall(function()
    local found = {}
    for tab = 1, GetNumTalentTabs() do
      for i = 1, GetNumTalents(tab) do
        local name, _, _, _, rank = GetTalentInfo(tab, i)
        if type(name) == 'string' and type(rank) == 'number' then found[name] = rank end
      end
    end
    talents = found
  end)
  return ok
end
OMA.readTalents = readTalents
local function rank(name) return talents[name] or 0 end

-- Curse of the Elements' percent for this rank, from its description ("... damage taken by 10%"), else by rank order.
local function coePercent(spellID)
  local get = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
  local ok, desc = pcall(get, spellID)
  if ok and readable(desc) and type(desc) == 'string' then
    local pct = desc:match('[Dd]amage taken by (%d+)%%') or desc:match('(%d+)%% [Mm]agic damage') or desc:match('(%d+)%%[^%d]*$')
    if tonumber(pct) then return tonumber(pct) end
  end
  return COE_BY_RANK[#COE_BY_RANK]
end

-- How much harder a DoT tick at time `at` on mob `key` hits than the learned size says (the engine calls this per tick).
function T.omaTickMult(dot, at, key)
  local m = 1
  local c = key and coe[key]
  if c and at <= c.untilT then m = m * (1 + c.pct / 100) end
  if dot.school == SHADOW and at <= sfShadowUntil then m = m * (1 + SF_PER_RANK * rank('Shadow and Flame') / 100) end
  if dot.school == FIRE and at <= sfFireUntil then m = m * (1 + SF_PER_RANK * rank('Shadow and Flame') / 100) end
  return m
end

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
f:RegisterEvent('PLAYER_LOGIN'); f:RegisterEvent('PLAYER_REGEN_ENABLED'); f:RegisterEvent('CHARACTER_POINTS_CHANGED')
pcall(f.RegisterEvent, f, 'PLAYER_TALENT_UPDATE')
f:SetScript('OnEvent', function(_, event, unit, a2, a3)
  if event == 'PLAYER_LOGIN' or event == 'PLAYER_REGEN_ENABLED' or event == 'CHARACTER_POINTS_CHANGED' or event == 'PLAYER_TALENT_UPDATE' then
    readTalents(); return
  end
  if not T.tracking then return end
  if event == 'UNIT_SPELLCAST_SUCCEEDED' then
    local castGUID, spellID = a2, a3
    local name = spellName(spellID)
    if not name then return end
    local now = GetTime()
    if name == 'Amplify Curse' then amplifyUntil = now + AMPLIFY_SECONDS; return end
    local key = readable(castGUID) and T.tracking.castTargetKey(castGUID) or nil
    local dots = dotsAt(key)
    if CURSES[name] and key then
      if name == 'Curse of the Elements' then coe[key] = { pct = coePercent(spellID), untilT = now + COE_SECONDS }
      else coe[key] = nil end
      if AMPLIFY_EATERS[name] then amplifyUntil = 0 end
      T.refresh(); return
    end
    if name == 'Conflagrate' then
      if rank('Shadow and Flame') > 0 then sfShadowUntil = now + SF_SECONDS end
      if dots and dots['Immolate'] and rank('Shadow and Flame') < 5 then
        if rank('Shadow and Flame') == 0 then dots['Immolate'] = nil; T.tracking.trace('DROP Immolate: eaten by Conflagrate') end
      end
      T.refresh(); return
    end
    if name == 'Shadowburn' and rank('Shadow and Flame') > 0 then sfFireUntil = now + SF_SECONDS; T.refresh(); return end
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
      T.tracking.dotsByTarget[key] = nil; coe[key] = nil
      T.tracking.trace('DROP all DoTs on ' .. tostring(key) .. ': it evaded (reset)')
      T.refresh()
    end
  end
end)
