-- Roster engine: one answer, for every view, to "which enemies are in my fight and what's going on with each".
-- One entry per nameplate token (nameplate1..16), refreshed by the scheduler a few times a second and on the events
-- that matter; each change fires 'ROSTER' (k) on the bus. Everything here is read the way Forever allows in combat:
-- hidden answers count as "no" and are never compared.
--   e.unit, e.k          the token and its number
--   e.on                 in your fight: you, your pet or a party/raid member is on its threat list, or it carries your DoTs
--   e.threat             your threat level 0..3 (nil: none / hidden)
--   e.target             it's your target (nameplate frames compared, never units)
--   e.petOn              your demon is attacking it (the pet's target's plate is this plate)
--   e.far                out of your spell range (only when the game says so plainly)
--   e.mark               its raid mark 1..8, or nil
--   e.missing            how many of your seats are empty on it (for "missing a DoT first")
--   e.soonest            seconds until your first DoT on it runs out (999: none)
local ADDON, ns = ...
local RO = {}; ns.roster = RO
local Secret = ns.core.Secret
local PM = ns.plates

RO.TOKENS = 16
local entries = {}
RO.entries = entries
local function plain(v) return v ~= nil and not Secret.is(v) end
local function tok(k) return 'nameplate' .. k end

local GROUP = { 'player', 'pet' }
for i = 1, 4 do GROUP[#GROUP + 1] = 'party' .. i; GROUP[#GROUP + 1] = 'partypet' .. i end
local dl, ds = {}, {}

local function alive(u)
  local ok, dead = pcall(UnitIsDead, u)
  return not (ok and plain(dead) and dead == true)
end
local function inFight(u, dots)
  for _, m in ipairs(GROUP) do
    local ok, st = pcall(UnitThreatSituation, m, u)
    if ok and plain(st) then return true end
  end
  if IsInRaid and IsInRaid() then
    for i = 1, 40 do local ok, st = pcall(UnitThreatSituation, 'raid' .. i, u); if ok and plain(st) then return true end end
  end
  return dots > 0
end
local function plateOf(u)
  local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, u, false)
  return ok and p or nil
end

-- the spell names that fill your seats (any rank), for counting what's missing
local seatNames
local function seatsKnown()
  if seatNames then return seatNames end
  seatNames = {}
  local R = ns.rings
  local spots = R and R.seatSpots and R.seatSpots() or {}
  for key in pairs(spots) do
    if key ~= 'curse' then   -- a curse is a choice, not a must: a mob without one isn't "missing" anything
      local sp = ns.spells.byKey[key]
      if sp then seatNames[key] = sp end
    end
  end
  return seatNames
end

local function refresh(k, now)
  local u = tok(k)
  local e = entries[k]; if not e then e = { k = k, unit = u }; entries[k] = e end
  local was = e.on
  local plate = PM.live[u]
  local okL = pcall(ns.model.listInto, u, true, dl, ds)
  local n = okL and #dl or 0
  e.on = plate ~= nil and alive(u) and inFight(u, n)
  if not e.on then
    e.threat, e.target, e.petOn, e.far, e.mark, e.missing, e.soonest = nil, false, false, false, nil, 0, 999
    return was ~= e.on
  end
  local ok, st = pcall(UnitThreatSituation, 'player', u)
  e.threat = ok and plain(st) and st > 0 and st or nil
  local tp = plateOf('target'); e.target = tp ~= nil and tp == plate
  local pp = plateOf('pettarget'); e.petOn = pp ~= nil and pp == plate
  local okR, inr = pcall(function() local f = C_Spell and C_Spell.IsSpellInRange; return f and f('Corruption', u) end)
  e.far = okR and plain(inr) and inr == false or false
  local okM, mk = pcall(GetRaidTargetIndex, u)
  e.mark = okM and plain(mk) and mk or nil
  -- which of your seat DoTs it carries, and the soonest one to end
  local have, soon = {}, 999
  for _, d in ipairs(okL and dl or {}) do
    local sp = ns.spells.ofName(d.name); if sp then have[sp.key] = true end
    if d.expiresAt then soon = math.min(soon, math.max(0, d.expiresAt - now)) end
  end
  local miss = 0; for key in pairs(seatsKnown()) do if not have[key] then miss = miss + 1 end end
  e.missing, e.soonest = miss, soon
  return true
end

function RO.refresh(k) local ok, ch = pcall(refresh, k, GetTime()); if ok and ch then ns.bus:Fire('ROSTER', k) end end
function RO.refreshAll()
  local now = GetTime()
  for k = 1, RO.TOKENS do local ok, ch = pcall(refresh, k, now); if ok and ch then ns.bus:Fire('ROSTER', k) end end
  ns.bus:Fire('ROSTER_DONE')
end

-- the order a list shows the mobs in: missing a DoT first (the DPS order), then the soonest ending, then by token so
-- equal mobs keep their places
function RO.order(missingFirst)
  local out = {}
  for k = 1, RO.TOKENS do local e = entries[k]; if e and e.on then out[#out + 1] = e end end
  table.sort(out, function(a, b)
    if missingFirst and a.missing ~= b.missing then return a.missing > b.missing end
    if a.soonest ~= b.soonest then return a.soonest < b.soonest end
    return a.k < b.k
  end)
  return out
end

local function start()
  if not (ns.sched and ns.model) then return end
  for k = 1, RO.TOKENS do entries[k] = { k = k, unit = tok(k), on = false, missing = 0, soonest = 999 } end
  ns.sched.add('roster', .2, RO.refreshAll)
  local ev = CreateFrame('Frame')
  for _, e in ipairs({ 'PLAYER_TARGET_CHANGED', 'UNIT_THREAT_LIST_UPDATE', 'RAID_TARGET_UPDATE', 'UNIT_PET', 'SPELLS_CHANGED' }) do pcall(ev.RegisterEvent, ev, e) end
  ev:SetScript('OnEvent', function(_, e) if e == 'SPELLS_CHANGED' then seatNames = nil end; ns.sched.mark('roster') end)
  for _, b in ipairs({ 'PLATE_ADDED', 'PLATE_REMOVED', 'PLATE_CHANGED', 'DOTS' }) do ns.bus:On(b, function() ns.sched.mark('roster') end) end
end
ns.starts[#ns.starts + 1] = start
