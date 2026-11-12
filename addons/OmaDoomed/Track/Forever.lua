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
--   * Claims: a hit on the beat of your own channel (Drain Life, Drain Soul, Wrack, Hellfire, Rain of Fire) or the
--     Firebolt your Imp just cast is that, not a DoT tick, so it can't keep a finished DoT alive.
-- Every rule knows its spells by ID first (any client language), then by English name, then by the name this client
-- gives those IDs. Talents are found by their place in the tree (any language). Old claims, curses and Firebolts are
-- pruned on the engine's housekeeping beat.
-- Sources: reports/Forever warlock full catalog.md (game client data, build 1.60.1.70888).
-- (A DoT that stops ticking is dropped by the engine itself after two missed ticks: Track/Engine.lua, "OMA".)
local _, OMA = ...
local T = OMA.track
local Spells = OMA.spells

local function readable(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

-- a rule's spells: { ids = { [id] = true }, names = { [name] = true } }; client names join at load and login
local rules = {}
local function rule(names, ids)
  local r = { ids = {}, names = {}, idList = ids }
  for _, id in ipairs(ids) do r.ids[id] = true end
  for _, n in ipairs(names) do r.names[n] = true end
  rules[#rules + 1] = r
  return r
end
local function is(r, spellID, name)
  return (readable(spellID) and r.ids[spellID]) or (name ~= nil and r.names[name]) or false
end

local COW = { 702, 1108, 6205, 7646, 11707, 11708, 27224, 30909 }
local COEX = { 18223 }
local COE_IDS = { 1490, 11721, 11722, 27228 }
local function join(...) local o = {}; for _, l in ipairs({ ... }) do for _, id in ipairs(l) do o[#o + 1] = id end end; return o end

local AMPLIFY = rule({ 'Amplify Curse' }, { 18288 })
local REPLACES_AGONY = rule({ 'Bane of Doom', 'Bane of Havoc' }, { 603, 80240 })
local AMPLIFY_EATERS = rule({ 'Curse of Weakness', 'Curse of Exhaustion' }, join(COW, COEX))
local CURSES = rule({ 'Curse of Weakness', 'Curse of Recklessness', 'Curse of Tongues', 'Curse of Exhaustion',
  'Curse of the Elements' }, join(COW, COEX, COE_IDS, { 704, 7658, 7659, 11717, 27226 }, { 1714, 11719 }))
local COE = rule({ 'Curse of the Elements' }, COE_IDS)
local CONFLAGRATE = rule({ 'Conflagrate' }, { 17962, 18930, 18931, 18932, 27266, 30912 })
local SHADOWBURN = rule({ 'Shadowburn' }, { 17877, 18867, 18868, 18869, 18870, 18871, 27263, 30546 })
local FIREBOLT = rule({ 'Firebolt' }, { 3110, 7799, 7800, 7801, 7802, 11762, 11763, 27267 })
local AMPLIFY_SECONDS, AMPLIFY_SCALE = 30, 1.5
local COE_SECONDS, COE_BY_RANK = 300, { 4, 6, 8, 10 }
local SF_SECONDS, SF_PER_RANK = 20, 4
local SHADOW, FIRE = 32, 4

local amplifyUntil = 0
local coe = {}                 -- mob key -> { pct, untilT }
local sfShadowUntil, sfFireUntil = 0, 0

local function spellName(id)
  if not readable(id) then return nil end
  local get = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
  if not get then return nil end
  local ok, name = pcall(get, id)
  if ok and readable(name) and type(name) == 'string' then return name end
end
-- this client's own names for every rule's IDs (another language)
local function learnNames()
  for _, r in ipairs(rules) do
    for _, id in ipairs(r.idList) do local n = spellName(id); if n then r.names[n] = true end end
  end
end

-- the registry key of a tracked DoT ('immolate', 'agony'...), by its spell ID, else its name
local function keyOf(name, dot)
  local sp = Spells and ((dot and Spells.ofID(dot.spellID)) or Spells.ofName(name))
  return sp and sp.key
end

-- Talents, read out of combat by their place in the tree (tab, tier, column), so any client language works; the
-- English name wins when it is found (a moved talent). Anything missing reads as 0.
local TALENTS = { sf = { tab = 3, tier = 6, column = 3, name = 'Shadow and Flame' } }
local talents = {}
local function readTalents()
  if InCombatLockdown and InCombatLockdown() then return end
  if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return end
  local ok = pcall(function()
    local byPlace, byName = {}, {}
    for tab = 1, GetNumTalentTabs() do
      for i = 1, GetNumTalents(tab) do
        local name, _, tier, column, rank = GetTalentInfo(tab, i)
        if type(rank) == 'number' then
          for k, t in pairs(TALENTS) do
            if tab == t.tab and tier == t.tier and column == t.column then byPlace[k] = rank end
            if name == t.name then byName[k] = rank end
          end
        end
      end
    end
    local found = {}
    for k in pairs(TALENTS) do found[k] = byName[k] or byPlace[k] end
    talents = found
  end)
  return ok
end
OMA.readTalents = readTalents
local function rank(k) return talents[k] or 0 end

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
  if dot.school == SHADOW and at <= sfShadowUntil then m = m * (1 + SF_PER_RANK * rank('sf') / 100) end
  if dot.school == FIRE and at <= sfFireUntil then m = m * (1 + SF_PER_RANK * rank('sf') / 100) end
  return m
end

local function dotsAt(key) return key and T.tracking and T.tracking.dotsByTarget[key] end
-- drop every DoT of this key (name order is the engine's table order; there is one per key at most anyway)
local function dropKey(dots, k, why)
  for name, dot in pairs(dots) do
    if keyOf(name, dot) == k then dots[name] = nil; T.tracking.trace('DROP ' .. name .. ': ' .. why) end
  end
end
local function firstOfKey(dots, k)
  for name, dot in pairs(dots) do if keyOf(name, dot) == k then return dot end end
end

local f = CreateFrame('Frame')
f:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
f:RegisterEvent('UNIT_COMBAT')
f:RegisterEvent('PLAYER_LOGIN'); f:RegisterEvent('PLAYER_REGEN_ENABLED'); f:RegisterEvent('CHARACTER_POINTS_CHANGED')
pcall(f.RegisterEvent, f, 'PLAYER_TALENT_UPDATE')
f:SetScript('OnEvent', function(_, event, unit, a2, a3)
  if event == 'PLAYER_LOGIN' or event == 'PLAYER_REGEN_ENABLED' or event == 'CHARACTER_POINTS_CHANGED' or event == 'PLAYER_TALENT_UPDATE' then
    if event == 'PLAYER_LOGIN' then learnNames() end
    readTalents(); return
  end
  if not T.tracking then return end
  if event == 'UNIT_SPELLCAST_SUCCEEDED' then
    local castGUID, spellID = a2, a3
    local name = spellName(spellID)
    if not name then return end
    local now = GetTime()
    if is(AMPLIFY, spellID, name) then amplifyUntil = now + AMPLIFY_SECONDS; return end
    local key = readable(castGUID) and T.tracking.castTargetKey(castGUID) or nil
    local dots = dotsAt(key)
    if is(CURSES, spellID, name) and key then
      if is(COE, spellID, name) then coe[key] = { pct = coePercent(spellID), untilT = now + COE_SECONDS }
      else coe[key] = nil end
      if is(AMPLIFY_EATERS, spellID, name) then amplifyUntil = 0 end
      T.refresh(); return
    end
    if is(CONFLAGRATE, spellID, name) then
      if rank('sf') > 0 then sfShadowUntil = now + SF_SECONDS end
      if dots and rank('sf') == 0 then dropKey(dots, 'immolate', 'eaten by Conflagrate') end
      T.refresh(); return
    end
    if is(SHADOWBURN, spellID, name) and rank('sf') > 0 then sfFireUntil = now + SF_SECONDS; T.refresh(); return end
    local sp = Spells and (Spells.ofID(spellID) or Spells.ofName(name))
    if is(REPLACES_AGONY, spellID, name) and dots then
      dropKey(dots, 'agony', 'replaced by ' .. name)
      T.refresh()
    elseif sp and sp.key == 'agony' and GetTime() < amplifyUntil then
      amplifyUntil = 0
      local dot = dots and firstOfKey(dots, 'agony')
      if dot then dot.omaScale = AMPLIFY_SCALE; T.tracking.trace(name .. ': Amplify Curse, +50%'); T.refresh() end
    end
  elseif event == 'UNIT_COMBAT' then
    if T.omaWatched and not T.omaWatched(unit) then return end
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

-- ---------- claims: hits that are yours but not a DoT's ----------
-- Channel tick every N s from the start (Rain of Fire's 2 s is Classic's; Forever's isn't published). area = hits
-- every mob, so any mob's hit on the beat is the channel's.
local CHANNELS = {
  { r = rule({ 'Drain Life' }, { 689, 699, 709, 7651, 11699, 11700, 27219, 27220 }), every = 1, school = SHADOW },
  { r = rule({ 'Drain Soul' }, { 1120, 8288, 8289, 11675, 27217 }), every = 3, school = SHADOW },
  { r = rule({ 'Wrack' }, { 1316697 }), every = 1, school = SHADOW },
  { r = rule({ 'Hellfire' }, { 1949, 11683, 11684, 27213 }), every = 1, school = FIRE, area = true },
  { r = rule({ 'Rain of Fire' }, { 5740, 6219, 11677, 11678, 27212 }), every = 2, school = FIRE, area = true },
}
local function channelOf(spellID, name) for _, c in ipairs(CHANNELS) do if is(c.r, spellID, name) then return c end end end
local BEAT, SAME_HIT, TAIL = 0.3, 0.05, 0.3
local FIREBOLT_MIN, FIREBOLT_MAX = 0, 1.6        -- from the Imp's cast to the hit (travel)
local CLAIM_KEEP, PRUNE_EVERY = 2, 1             -- a beat can't be hit again after 0.3 s: claims older than 2 s go
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

-- on the engine's housekeeping beat (Track/Shim.lua), once a second: old claims, ended curses, landed Firebolts
local nextPrune = 0
function T.omaHousekeep(now)
  if now < nextPrune then return end
  nextPrune = now + PRUNE_EVERY
  for key, slots in pairs(claimed) do
    for slot, c in pairs(slots) do if now - c.at > CLAIM_KEEP then slots[slot] = nil end end
    if next(slots) == nil then claimed[key] = nil end
  end
  for key, c in pairs(coe) do if now > c.untilT then coe[key] = nil end end
  for i = #petBolts, 1, -1 do if now - petBolts[i].at > FIREBOLT_MAX then table.remove(petBolts, i) end end
end

local cf = CreateFrame('Frame')
cf:RegisterUnitEvent('UNIT_SPELLCAST_CHANNEL_START', 'player')
cf:RegisterUnitEvent('UNIT_SPELLCAST_CHANNEL_STOP', 'player')
cf:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'pet')
cf:SetScript('OnEvent', function(_, event, unit, castGUID, spellID)
  if not T.tracking then return end
  local name = spellName(spellID)
  if event == 'UNIT_SPELLCAST_CHANNEL_START' then
    local c = (name or readable(spellID)) and channelOf(spellID, name)
    if not c then return end
    local key = readable(castGUID) and T.tracking.castTargetKey(castGUID) or nil
    chan = { key = key, school = c.school, every = c.every, area = c.area, start = GetTime() }
  elseif event == 'UNIT_SPELLCAST_CHANNEL_STOP' then
    if chan then chan.stoppedAt = GetTime() end
  elseif unit == 'pet' and is(FIREBOLT, spellID, name) then
    local okKey, key = pcall(T.tracking.unitKey, 'pettarget')
    if okKey and key then petBolts[#petBolts + 1] = { key = key, at = GetTime() } end
  end
end)

pcall(learnNames)
OMA.trackOffWith(function() f:UnregisterAllEvents(); cf:UnregisterAllEvents() end)
