-- Wrack (WoW: Forever warlock channel, spell 1316697). OmaDoomed's own addition to the tracking; DoesItDie doesn't
-- know it.
--
-- Blizzard, Nov 10 2026 hotfix: while you channel Wrack, your Corruption, Siphon Life and Bane of Agony on that
-- target deal their periodic damage 100% faster: "advances 2 seconds instead of 1", and the time gained is kept
-- when the channel stops. Immolate is not affected.
--
-- Model: those DoTs run on a clock going twice as fast while Wrack is channelled at their mob. Each frame of the
-- channel moves every time stamp of theirs (applied, next tick, expiry, tick anchors) one frame earlier, so the
-- engine's tick schedule, matching windows and Agony's tick shape all see the faster clock without knowing it.
-- Ticks come sooner and the DoT ends sooner; the damage left is the same, it just arrives faster.
-- Which DoTs: the Shadow ones (school 32). Immolate is Fire. That holds in every client language.
-- Not known yet (needs a real fight): how the last part-tick works out when Wrack has shifted the schedule.
local _, OMA = ...
local T = OMA.track
local WRACK_ID = 1316697
local SHADOW = 32
local STAMPS = { 'appliedAt', 'nextTickAt', 'expiresAt', 'firstTickAt', 'lastTickAt' }

local active   -- { key = mob key, guid = cast GUID, last = GetTime() of the last shift }

local function isWrack(spellID)
  if spellID == WRACK_ID then return true end
  local ok, name = pcall(C_Spell and C_Spell.GetSpellName or GetSpellInfo, spellID)
  return ok and type(name) == 'string' and not (issecretvalue and issecretvalue(name)) and name == 'Wrack'
end

local function shift(now)
  if not active or not T.tracking then return end
  local dt = now - active.last
  active.last = now
  if dt <= 0 then return end
  local dots = T.tracking.dotsByTarget[active.key]
  if not dots then return end
  for _, dot in pairs(dots) do
    if dot.school == SHADOW and not dot.provisional then
      for _, k in ipairs(STAMPS) do if type(dot[k]) == 'number' then dot[k] = dot[k] - dt end end
    end
  end
end
OMA.wrackShift = shift   -- tests call it directly

local f = CreateFrame('Frame')
f:RegisterUnitEvent('UNIT_SPELLCAST_CHANNEL_START', 'player')
f:RegisterUnitEvent('UNIT_SPELLCAST_CHANNEL_STOP', 'player')
f:SetScript('OnEvent', function(_, event, _, castGUID, spellID)
  if issecretvalue and (issecretvalue(spellID) or issecretvalue(castGUID)) then return end
  if event == 'UNIT_SPELLCAST_CHANNEL_START' then
    if not isWrack(spellID) or not T.tracking then return end
    local key = T.tracking.castTargetKey(castGUID)
    if not key then return end
    active = { key = key, guid = castGUID, last = GetTime() }
    T.tracking.trace('WRACK on ' .. tostring(key) .. ': its Shadow DoTs run twice as fast')
  elseif active and (castGUID == nil or castGUID == active.guid or isWrack(spellID)) then
    shift(GetTime())
    T.tracking.trace('WRACK ended')
    active = nil
  end
end)
f:SetScript('OnUpdate', function() if active then shift(GetTime()) end end)
OMA.trackOffWith(function() f:UnregisterAllEvents(); f:SetScript('OnUpdate', nil); active = nil end)
