-- OmaDemon: Nightfall chime PROBE (2026-11-17). Forever hides whether Shadow Trance is up from add-ons in a fight
-- (the aura, and the aura button's showing, are secret), so the chime needs a plain signal. This probe only READS and
-- writes down what the game says, to learn which of these is plain on Forever and moves when Nightfall procs:
--   1. Shadow Bolt's cast time (C_Spell.GetSpellInfo castTime): 0 while Shadow Trance makes it instant?
--   2. C_SpellActivationOverlay.IsSpellOverlayed(Shadow Bolt): the game's own "this button is lit" flag
--   3. SPELL_ACTIVATION_OVERLAY_* events
-- Ground truth: a Shadow Bolt that succeeds with no cast start before it was instant, so Shadow Trance was up.
-- /omademon nightfall probe   runs 5 minutes (or until /omademon nightfall probe again), then prints a summary.
-- Saved in OmaDemonDB.group.nfProbe; /reload writes it to disk. Nothing is cast, clicked or changed.
local _, ns = ...

local RUN = 300
local MAX = 300
local P = { on = false }
ns.nfProbe = P

local function secret(v) return issecretvalue and issecretvalue(v) or false end
local function show(v) if secret(v) then return 'SECRET' end; return tostring(v) end
local function auraSecret()
  local ok, v = pcall(function() return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() end)
  if not ok then return '?' end
  return show(v)
end

local db, t0, sbID
local function log(what)
  if not db then return end
  local n = #db.log
  if n >= MAX then return end
  db.log[n + 1] = ('%6.1f %s | fight %s auraSecret %s'):format(GetTime() - t0, what, tostring(InCombatLockdown() and true or false), auraSecret())
end

local function shadowBolt()
  local ok, info = pcall(function() return C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo('Shadow Bolt') end)
  if ok and type(info) == 'table' then return info end
end
local function castTime()
  local ok, v = pcall(function()
    local i = shadowBolt(); if i then return i.castTime end
    return GetSpellInfo and select(4, GetSpellInfo('Shadow Bolt'))
  end)
  if not ok then return 'error' end
  return v
end
local function overlayed()
  if not sbID then return 'no id' end
  local ok, v = pcall(function()
    if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then return C_SpellActivationOverlay.IsSpellOverlayed(sbID) end
    if IsSpellOverlayed then return IsSpellOverlayed(sbID) end
    return 'no api'
  end)
  if not ok then return 'error' end
  return v
end

local lastCT, lastOV, started, acc, endsAt = nil, nil, false, 0, 0
local ticker = CreateFrame('Frame'); ticker:Hide()
local ev = CreateFrame('Frame')

local function summary()
  local s = db.sum
  ns.say(('nightfall probe done: cast time changed %d times (%s), button-lit flag changed %d times (%s), overlay events %d, instant Shadow Bolts %d. /reload, then tell Claude.')
    :format(s.ct, s.ctSecret and 'some SECRET' or 'plain', s.ov, s.ovSecret and 'some SECRET' or 'plain', s.events, s.instant))
end

local function stop()
  if not P.on then return end
  P.on = false; ticker:Hide(); ev:UnregisterAllEvents()
  log('probe stop'); summary()
end

local function sample()
  local ct, ov = castTime(), overlayed()
  local ctS, ovS = show(ct), show(ov)
  if ctS ~= lastCT then
    if lastCT ~= nil then db.sum.ct = db.sum.ct + 1 end
    if secret(ct) then db.sum.ctSecret = true end
    log('castTime ' .. ctS); lastCT = ctS
  end
  if ovS ~= lastOV then
    if lastOV ~= nil then db.sum.ov = db.sum.ov + 1 end
    if secret(ov) then db.sum.ovSecret = true end
    log('lit ' .. ovS); lastOV = ovS
  end
end

ticker:SetScript('OnUpdate', function(_, dt)
  acc = acc + dt
  if acc < .1 then return end
  acc = 0
  if GetTime() >= endsAt then stop(); return end
  sample()
end)

local function isShadowBolt(id)
  if secret(id) then return 'SECRET' end
  local ok, name = pcall(function() return ns.spellName and ns.spellName(id) end)
  return ok and name == 'Shadow Bolt'
end

ev:SetScript('OnEvent', function(_, e, a1, a2, a3)
  if e == 'UNIT_SPELLCAST_START' then
    if a1 == 'player' and isShadowBolt(a3) == true then started = true; log('Shadow Bolt cast start') end
  elseif e == 'UNIT_SPELLCAST_SUCCEEDED' then
    if a1 == 'player' and isShadowBolt(a3) == true then
      if not started then db.sum.instant = db.sum.instant + 1 end
      log('Shadow Bolt went off ' .. (started and '(cast)' or '(INSTANT: Shadow Trance was up)')); started = false
      sample()
    end
  elseif e == 'UNIT_SPELLCAST_FAILED' or e == 'UNIT_SPELLCAST_INTERRUPTED' then
    if a1 == 'player' then started = false end
  else   -- SPELL_ACTIVATION_OVERLAY_*
    db.sum.events = db.sum.events + 1
    log(e .. ' ' .. show(a1) .. (isShadowBolt(a1) == true and ' (Shadow Bolt)' or ''))
  end
end)

function P.toggle()
  if P.on then stop(); return end
  local g = ns.groupDB()
  g.nfProbe = { at = date('%Y-%m-%d %H:%M'), log = {}, sum = { ct = 0, ov = 0, events = 0, instant = 0 } }
  db = g.nfProbe
  t0 = GetTime(); endsAt = t0 + RUN; lastCT, lastOV, started, acc = nil, nil, false, 0
  local info = shadowBolt(); sbID = info and not secret(info.spellID) and info.spellID or nil
  db.shadowBolt = sbID or 'not found'
  for _, e in ipairs({ 'UNIT_SPELLCAST_START', 'UNIT_SPELLCAST_SUCCEEDED', 'UNIT_SPELLCAST_FAILED', 'UNIT_SPELLCAST_INTERRUPTED',
    'SPELL_ACTIVATION_OVERLAY_GLOW_SHOW', 'SPELL_ACTIVATION_OVERLAY_GLOW_HIDE', 'SPELL_ACTIVATION_OVERLAY_SHOW', 'SPELL_ACTIVATION_OVERLAY_HIDE' }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  P.on = true; log('probe start, Shadow Bolt id ' .. tostring(db.shadowBolt)); sample(); ticker:Show()
  ns.say('nightfall probe on for 5 min: fight with Corruption or Drain Life up, and cast Shadow Bolt a few times, including right after a proc. /omademon nightfall probe again stops it early.')
end
