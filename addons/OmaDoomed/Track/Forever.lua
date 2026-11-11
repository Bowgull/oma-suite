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
--   * The eyes (Rings.lua): Blizzard's aura container says whether each of your debuffs is still on a plated mob.
--     A DoT whose debuff has been gone for half a second is dropped, whatever hits keep landing. Improved Shadow
--     Bolt's Shadow Vulnerability seen on a mob: Shadow DoTs there +4% per rank for 12 s from when it appeared.
--   * Claims: a hit on the beat of your own channel (Drain Life, Drain Soul, Wrack, Hellfire, Rain of Fire) or the
--     Firebolt your Imp just cast is that, not a DoT tick, so it can't keep a finished DoT alive.
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
local isbUntil, isbSeen = {}, {}   -- mob key -> end of Shadow Vulnerability; mob key -> seen last poll
local ISB_SECONDS, ISB_PER_RANK = 12, 4
local EYE_GRACE, EYE_GONE = 1.5, 0.5   -- a fresh DoT's debuff can lag its cast; gone this long = really gone

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
  if dot.school == SHADOW and key and isbUntil[key] and at <= isbUntil[key] then m = m * (1 + ISB_PER_RANK * rank('Improved Shadow Bolt') / 100) end
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

-- ---------- the eyes ----------
local missing = setmetatable({}, { __mode = 'k' })   -- dot -> when its debuff was first seen gone
local eyeState                                       -- 'seeing' / 'blind', logged once each (the in-game check)
local function look()
  if not (OMA.eyes and OMA.eyesUnits and OMA.eyeKeyFor and T.tracking) then return end
  local now = GetTime()
  for _, unit in ipairs(OMA.eyesUnits()) do
    local okKey, key = pcall(T.tracking.unitKey, unit)
    local seen = okKey and key and OMA.eyes(unit)
    local state = seen and 'seeing' or (okKey and key and 'blind') or nil
    if state and state ~= eyeState then eyeState = state; T.tracking.trace('EYES ' .. state .. (state == 'blind' and ': the game hides aura buttons from us' or ': aura buttons readable in ' .. (InCombatLockdown() and 'combat' or 'peace'))) end
    if seen then
      if seen.isb and not isbSeen[key] then isbUntil[key] = now + ISB_SECONDS end
      isbSeen[key] = seen.isb or nil
      local dots = T.tracking.dotsByTarget[key]
      for name, dot in pairs(dots or {}) do
        local eye = OMA.eyeKeyFor(dot.spellID)
        if eye and seen[eye] == false and not dot.provisional and now - (dot.appliedAt or now) > EYE_GRACE then
          if not missing[dot] then missing[dot] = now
          elseif now - missing[dot] >= EYE_GONE then
            dots[name] = nil
            T.tracking.trace('DROP ' .. name .. ': its debuff is gone (seen on the plate)')
            T.refresh()
          end
        else
          missing[dot] = nil
        end
      end
    end
  end
end
OMA.eyesLook = look   -- tests call it directly
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(0.25, function() local ok, err = pcall(look); if not ok and OMA.err then OMA.err('eyes: ' .. tostring(err)) end end) end

-- ---------- claims: hits that are yours but not a DoT's ----------
-- Channel tick every N s from the start (Rain of Fire's 2 s is Classic's; Forever's isn't published). area = hits
-- every mob, so any mob's hit on the beat is the channel's.
local CHANNELS = {
  ['Drain Life'] = { every = 1, school = SHADOW }, ['Drain Soul'] = { every = 3, school = SHADOW },
  ['Wrack'] = { every = 1, school = SHADOW },
  ['Hellfire'] = { every = 1, school = FIRE, area = true }, ['Rain of Fire'] = { every = 2, school = FIRE, area = true },
}
local BEAT, SAME_HIT, TAIL = 0.3, 0.05, 0.3
local FIREBOLT_MIN, FIREBOLT_MAX = 0, 1.6        -- from the Imp's cast to the hit (travel)
local chan                                       -- { key, school, every, start, stoppedAt, area }
local claimed = {}                               -- key -> slot -> { at, units }
local petBolts = {}                              -- list of { key, at }

local function claimSlot(key, slot, unit, now)
  claimed[key] = claimed[key] or {}
  local c = claimed[key][slot]
  if c and now - c.at <= SAME_HIT then
    if c.units[unit] then return false end      -- a second hit on the same token at once: someone else's (a DoT)
    c.units[unit] = true; return true            -- the same hit seen through another token (target + nameplate)
  end
  if c then return false end                     -- this beat was already claimed earlier
  claimed[key][slot] = { at = now, units = { [unit] = true } }
  return true
end

function T.omaClaim(unit, key, school, now)
  if chan and school == chan.school and (chan.area or chan.key == key) and (not chan.stoppedAt or now - chan.stoppedAt <= TAIL) then
    local k = math.floor((now - chan.start) / chan.every + 0.5)
    if k >= 1 and math.abs(now - (chan.start + k * chan.every)) <= BEAT then
      if claimSlot(key, 'c' .. chan.start .. ':' .. k, unit, now) then return true end
    end
  end
  if school == FIRE then
    for i = #petBolts, 1, -1 do
      local b = petBolts[i]
      if now - b.at > FIREBOLT_MAX then table.remove(petBolts, i)
      elseif b.key == key and now - b.at >= FIREBOLT_MIN and not b.used then
        b.used = true; b.units = { [unit] = true }; b.hitAt = now; return true
      elseif b.key == key and b.used and b.hitAt and now - b.hitAt <= SAME_HIT and not b.units[unit] then
        b.units[unit] = true; return true
      end
    end
  end
  return false
end

local cf = CreateFrame('Frame')
cf:RegisterUnitEvent('UNIT_SPELLCAST_CHANNEL_START', 'player')
cf:RegisterUnitEvent('UNIT_SPELLCAST_CHANNEL_STOP', 'player')
cf:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'pet')
cf:SetScript('OnEvent', function(_, event, unit, castGUID, spellID)
  if not T.tracking then return end
  local name = spellName(spellID)
  if event == 'UNIT_SPELLCAST_CHANNEL_START' then
    local c = name and CHANNELS[name]
    if not c then return end
    local key = readable(castGUID) and T.tracking.castTargetKey(castGUID) or nil
    chan = { key = key, school = c.school, every = c.every, area = c.area, start = GetTime() }
  elseif event == 'UNIT_SPELLCAST_CHANNEL_STOP' then
    if chan then chan.stoppedAt = GetTime() end
  elseif unit == 'pet' and name == 'Firebolt' then
    local okKey, key = pcall(T.tracking.unitKey, 'pettarget')
    if okKey and key then petBolts[#petBolts + 1] = { key = key, at = GetTime() } end
  end
end)
