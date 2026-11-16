-- OmaDoomed, crowd-control timers (sheet 48, approved 2026-11-13; DECISIONS.md).
-- Your Fear, Banish, Howl of Terror and your Sayaad's Seduction, so you always see the timer:
--   * on the held mob's plate, and on your target's frame while it's your target: the teal 'cc' ring group
--     (Spells.lua, RingsLook.lua). Blizzard's AuraContainer reads the aura, so that one is exact.
--   * when the held mob isn't your target, or its plate is off screen: one teal ring standing apart beside the target
--     frame, no text. It stays in that spot with no target. That's this file.
-- Forever forbids the combat log and enemy aura reads in combat, so the ring beside the frame counts from your own
-- cast (spell ID -> length by rank). It corrects itself from the plate: while the held mob's plate is on screen this
-- ring hides (the plate's exact ring shows), and if the plate's ring goes away there, the hold is over.
local ADDON, ns = ...
local R, Spells, Secret, Anim = ns.rings, ns.spells, ns.core.Secret, ns.core.Anim
local PM = ns.plates
local CC = {}
ns.cc = CC

-- what each spell ID is and how long it holds (Forever: research_notes/Forever warlock full catalog/spells_part1/2.md)
local KIND = { [5782] = 'fear', [6213] = 'fear', [6215] = 'fear', [710] = 'banish', [18647] = 'banish',
  [5484] = 'howl', [17928] = 'howl', [6358] = 'seduce' }
local LENGTH = { [5782] = 10, [6213] = 15, [6215] = 20, [710] = 20, [18647] = 30, [5484] = 10, [17928] = 15, [6358] = 15 }
local BY_NAME = { ['Fear'] = 'fear', ['Banish'] = 'banish', ['Howl of Terror'] = 'howl', ['Seduction'] = 'seduce' }
local DEFAULT = { fear = 10, banish = 20, howl = 10, seduce = 15 }   -- a rank we don't know: its lowest length
local I = 'Interface\\Icons\\'                                     -- fallback icons, if the client won't say
local ICON = { fear = I .. 'Spell_Shadow_Possession', banish = I .. 'Spell_Shadow_Cripple', howl = I .. 'Spell_Shadow_DeathScream',
  seduce = I .. 'Spell_Shadow_MindSteal' }
CC.KIND, CC.LENGTH = KIND, LENGTH

local ART = R.ART
local GOLD, WHITE = R.GOLD, R.WHITE
local TEAL = Spells.byKey.cc.color
local SIZE = R.S * R.FRAME_SCALE * 1.5    -- sheet 48: one and a half times the target frame's DoT rings
local GAP = 10                            -- standing apart from the frame (sheet 48: 'not this mob')
local SPACE = 4                           -- two holds at once sit side by side
local FADE = 0.3                          -- ends like a DoT ends
CC.SIZE = SIZE

local db
local holds = {}                          -- kind -> { id, start, dur, guid, token, kind }
CC.holds = holds
local rings = {}                          -- kind -> ring frame
CC.rings = rings
local shownHold, endingAt = {}, {}       -- kind -> the hold its ring shows; kind -> when its fade-out began
local running = false
local holder
local secret = Secret.is

-- ---------- which mob ----------
local function guidOf(unit)
  local ok, g = pcall(UnitGUID, unit)
  if ok and g ~= nil and not secret(g) then return g end
end
local function plateOf(unit)
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
  local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, unit, false)
  if ok and p and not secret(p) then return p end
end
local function tokenOf(unit)
  local p = plateOf(unit); if not p then return nil end
  local t = (PM and PM.unitOf and PM.unitOf[p]) or p.namePlateUnitToken
  if type(t) == 'string' and not secret(t) then return t end
end
-- the held mob's plate token while its plate is on screen, or nil
local function liveToken(h)
  if h.token and PM.live[h.token] then
    if not h.guid then return h.token end
    local g = guidOf(h.token); if g == nil or g == h.guid then return h.token end
  end
  if h.guid then
    for t in pairs(PM.live) do if guidOf(t) == h.guid then h.token = t; return t end end
  end
end
CC.liveToken = liveToken
local function isTarget(h)
  if not UnitExists('target') then return false end
  if h.guid then local g = guidOf('target'); if g then return g == h.guid end end
  local t = h.token and PM.live[h.token] and plateOf(h.token)
  local tp = plateOf('target')
  return t ~= nil and tp ~= nil and t == tp
end

-- ---------- the ring beside the target frame (our own frames: no aura reads, so it works in combat) ----------
local function newRing()
  local f = CreateFrame('Frame', nil, holder); f:SetSize(SIZE, SIZE); f:Hide()
  local flat = R.flat()   -- the 'Ring look' setting: Rich (shadow, lit ring, bezel, number spot) or Flat (sheet 52 F)
  if not flat then local shadow = f:CreateTexture(nil, 'BACKGROUND', nil, -8); shadow:SetTexture(ART .. 'ring_shadow', nil, nil, 'TRILINEAR'); shadow:SetAllPoints(f) end
  local back = f:CreateTexture(nil, 'BACKGROUND'); back:SetTexture(ART .. (flat and 'backing_flat' or 'backing'), nil, nil, 'TRILINEAR'); back:SetAllPoints(f)
  local ring = f:CreateTexture(nil, 'ARTWORK'); ring:SetTexture(ART .. (flat and 'ring_bold' or 'ring_bold_hard'), nil, nil, 'TRILINEAR'); ring:SetAllPoints(f)
  if not flat then local light = f:CreateTexture(nil, 'ARTWORK', nil, 3); light:SetTexture(ART .. 'ring_light', nil, nil, 'TRILINEAR'); light:SetAllPoints(f) end
  local track = CreateFrame('Cooldown', nil, f)
  -- the same cooldown look as the plate rings: the dark track covers the spent part, so the ring drains
  track:SetAllPoints(f)
  pcall(track.SetSwipeTexture, track, ART .. 'swipe_track_bold', 1, 1, 1, 1); pcall(track.SetSwipeColor, track, 1, 1, 1, 1)
  pcall(track.SetDrawEdge, track, false); pcall(track.SetDrawBling, track, false); pcall(track.SetReverse, track, true)
  pcall(track.SetHideCountdownNumbers, track, true)
  local top = CreateFrame('Frame', nil, track); top:SetAllPoints(f)
  if not flat then local edge = top:CreateTexture(nil, 'BACKGROUND'); edge:SetTexture(ART .. 'ring_edge', nil, nil, 'TRILINEAR'); edge:SetAllPoints(f) end   -- sheet 55: the band encased
  local icon = top:CreateTexture(nil, 'ARTWORK', nil, 0)
  icon:SetSize(SIZE * 0.756, SIZE * 0.756); icon:SetPoint('CENTER', f, 'CENTER'); icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
  local m = top:CreateMaskTexture(); m:SetTexture(ART .. 'mask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE', 'TRILINEAR'); m:SetAllPoints(f)
  icon:AddMaskTexture(m)
  if not flat then
    icon:SetAlpha(.8)
    local spot = top:CreateTexture(nil, 'ARTWORK', nil, 1); spot:SetTexture(ART .. 'numspot', nil, nil, 'TRILINEAR'); spot:SetAllPoints(f)
    local bezel = top:CreateTexture(nil, 'ARTWORK', nil, 2); bezel:SetTexture(ART .. 'bezel', nil, nil, 'TRILINEAR'); bezel:SetAllPoints(f)
    local edgeIn = top:CreateTexture(nil, 'ARTWORK', nil, 3); edgeIn:SetTexture(ART .. 'ring_edge_in', nil, nil, 'TRILINEAR'); edgeIn:SetAllPoints(f)
  end
  local inner = CreateFrame('Cooldown', nil, top)
  inner:SetAllPoints(f)
  pcall(inner.SetSwipeTexture, inner, ART .. 'swipe_inner', 1, 1, 1, 1); pcall(inner.SetDrawEdge, inner, false)
  pcall(inner.SetDrawBling, inner, false); pcall(inner.SetReverse, inner, true); pcall(inner.SetHideCountdownNumbers, inner, true)
  if flat then pcall(inner.SetDrawSwipe, inner, false) end   -- Classic: no dark sweep over the icon
  local nf = CreateFrame('Frame', nil, inner); nf:SetAllPoints(f)
  local num = nf:CreateFontString(nil, 'OVERLAY')
  num:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF', math.floor(SIZE * R.numK() + 0.5), flat and 'OUTLINE' or 'THICKOUTLINE')
  num:SetPoint('CENTER', f, 'CENTER', 0, -SIZE * 0.02)
  if flat then num:SetShadowColor(0, 0, 0, 0); num:SetShadowOffset(0, 0) else num:SetShadowColor(0, 0, 0, 1); num:SetShadowOffset(1, -1) end
  f.ring, f.icon, f.num, f.track, f.inner = ring, icon, num, track, inner
  return f
end

local function iconFor(h)
  local tex
  local ok, t = pcall(function()
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(h.id) end
    return GetSpellTexture and GetSpellTexture(h.id)
  end)
  if ok and t and not secret(t) then tex = t end
  return tex or ICON[h.kind]
end

local function ringFor(h)
  local f = rings[h.kind]
  if not f then f = newRing(); rings[h.kind] = f end
  if shownHold[h.kind] ~= h then
    shownHold[h.kind] = h; endingAt[h.kind] = nil; f:SetAlpha(1)
    f.icon:SetTexture(iconFor(h))
    pcall(f.track.SetCooldown, f.track, h.start, h.dur); pcall(f.inner.SetCooldown, f.inner, h.start, h.dur)
  end
  return f
end

-- where the rings go: standing apart, left of the target frame's bars, level with them. Out of combat only for scale.
local function anchorHolder()
  if not holder then return end
  holder:ClearAllPoints()
  local main = TargetFrame and TargetFrame.TargetFrameContent and TargetFrame.TargetFrameContent.TargetFrameContentMain
  local bars = main and main.HealthBarsContainer
  if bars then holder:SetPoint('RIGHT', bars, 'LEFT', -GAP, 0)
  elseif TargetFrame then holder:SetPoint('RIGHT', TargetFrame, 'LEFT', -GAP, 0)
  else holder:SetPoint('CENTER', UIParent, 'CENTER', 0, 200) end
  if not InCombatLockdown() and TargetFrame and TargetFrame.GetEffectiveScale and UIParent.GetEffectiveScale then
    local ok, s = pcall(function() return TargetFrame:GetEffectiveScale() / UIParent:GetEffectiveScale() end)
    local size = (R.db and R.db.size or 40) / 40
    if ok and type(s) == 'number' and s > 0 then holder:SetScale(s * size) end
  end
end
CC.anchorHolder = anchorHolder

-- ---------- holds ----------
local function now() return GetTime() end
local function ended(h) return now() >= h.start + h.dur end

-- shown beside the frame: a live hold whose plate is off screen, and which isn't the target showing on its frame
function CC.wantsRing(h)
  if not h or ended(h) or h.over then return false end
  if liveToken(h) then return false end                       -- the plate's exact ring shows instead
  -- Target frame: it's in the frame's own row. Haunt keeps it over the mob instead (Rings.lua OVERHEAD), so with the
  -- mob off screen there the ring beside the frame is the only one
  if isTarget(h) and R.db and R.db.where == 'frame' and R.db.enabled ~= false then
    return false
  end
  return true
end

local order = { 'fear', 'banish', 'seduce', 'howl' }
local function layout()
  local x = 0
  for _, k in ipairs(order) do
    local f = rings[k]
    if f and f:IsShown() then
      f:ClearAllPoints(); f:SetPoint('RIGHT', holder, 'RIGHT', -x, 0); x = x + SIZE + SPACE
    end
  end
end

local LOW_ALPHA, BREATH = 0.3, 1.5
local function lowSecs() return (ns.db and ns.db.low) or 3 end
local function breathes() return not (ns.db and ns.db.lowlook == 'steady') end

local function paint(f, h)
  local left = h.start + h.dur - now()
  if left < 0 then left = 0 end
  local LOW = lowSecs()
  local n = math.ceil(left - 1e-6); if n < 1 then n = 1 end
  f.num:SetText(n >= 60 and (math.ceil(n / 60) .. 'm') or tostring(n))
  if left <= LOW then
    local a = breathes() and Anim.breath(left, LOW, BREATH, LOW_ALPHA) or 1
    -- sheet 58 C: ending in its own colour, lit (teal), like every other ring
    local rc, nc = R.lit(TEAL, R.LIT_RING), R.lit(TEAL, R.LIT_NUM)
    f.ring:SetVertexColor(rc[1], rc[2], rc[3], a); f.num:SetTextColor(nc[1], nc[2], nc[3], a)
  else
    f.ring:SetVertexColor(TEAL[1], TEAL[2], TEAL[3], 1); f.num:SetTextColor(1, 1, 1, 1)
  end
end

local function update()
  if not holder then return end
  local any, moved = false, false
  for _, k in ipairs(order) do
    local h, f = holds[k], rings[k]
    if h and (ended(h) or h.over) and not endingAt[k] then
      -- over: fade out (0.3 s) if it's showing, then forget it
      if f and f:IsShown() then endingAt[k] = now() else holds[k] = nil; h = nil end
    end
    if f and endingAt[k] then
      local a = 1 - (now() - endingAt[k]) / FADE
      if a <= 0 then f:Hide(); endingAt[k] = nil; shownHold[k] = nil; holds[k] = nil; moved = true else f:SetAlpha(a); any = true end
    elseif h and db.cc ~= false and CC.wantsRing(h) then
      f = ringFor(h)
      if not f:IsShown() then f:SetAlpha(1); f:Show(); moved = true end
      paint(f, h); any = true
    elseif f and f:IsShown() then
      f:Hide(); moved = true
    end
    if holds[k] then any = true end
  end
  if moved then layout() end
  if not any then holder:SetScript('OnUpdate', nil); running = false end
end
CC.update = update

local acc = 0
local function run()
  if not holder or running then return end
  running = true; acc = 0
  holder:SetScript('OnUpdate', function(_, dt) acc = acc + (dt or 0); if acc >= 0.05 then acc = 0; update() end end)
end

-- a hold begins: your cast landed (player) or your Sayaad's (pet). One mob at a time per spell, so a new one replaces.
function CC.cast(caster, spellID)
  if spellID == nil or secret(spellID) then return end
  local kind = KIND[spellID]
  if not kind then
    local ok, name = pcall(function() return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or (GetSpellInfo and GetSpellInfo(spellID)) end)
    kind = ok and type(name) == 'string' and not secret(name) and BY_NAME[name] or nil
  end
  if not kind then return end
  if (kind == 'seduce') ~= (caster == 'pet') then return end
  local h = { id = spellID, kind = kind, start = now(), dur = LENGTH[spellID] or DEFAULT[kind] }
  if kind ~= 'howl' then
    local unit = caster == 'pet' and 'pettarget' or 'target'
    h.guid, h.token = guidOf(unit), tokenOf(unit)
  end
  shownHold[kind] = nil; endingAt[kind] = nil
  holds[kind] = h
  run(); update()
  return h
end

-- the plate's own ring (exact) went away while its row was showing: that mob's hold is over (broken or ended)
local function plateRingGone(b)
  local p = b
  for _ = 1, 8 do
    p = p and p.GetParent and p:GetParent()
    if not p then return end
    for unit, pair in pairs(R.active) do
      if pair.anchor == p or pair.ring == p or pair.main == p then
        local okV, vis = pcall(p.IsVisible, p)
        if not okV or not vis or secret(vis) then return end    -- the whole row hid (fade, release): not the aura
        -- a ring can blink while Blizzard re-lays the row: only a ring still gone a moment later counts
        C_Timer.After(0.25, function()
          local okS, shown = pcall(b.IsShown, b)
          if okS and shown == true then return end
          local okP, still = pcall(p.IsVisible, p)
          if not okP or still ~= true then return end
          for _, h in pairs(holds) do
            if h.kind ~= 'howl' and not h.over and liveToken(h) == unit then h.over = true end
          end
          update()
        end)
        return
      end
    end
  end
end
function ns.ccPlateHook(b)
  b:HookScript('OnHide', function(self) if db then pcall(plateRingGone, self) end end)
end
CC.plateRingGone = plateRingGone

function CC.clear()
  for k, h in pairs(holds) do h.over = true end
  update()
end

-- /omadoomed cc test: a pretend 15 s Fear on no mob, so you can see the ring beside your target frame
function CC.test()
  if not holder then return end
  local h = { id = 5782, kind = 'fear', start = now(), dur = 15 }
  holds.fear = h; shownHold.fear = nil; endingAt.fear = nil
  run(); update()
  return h
end

-- the plate ring group follows the setting (out of combat: groups can't change in a fight)
local function plateGroups()
  if InCombatLockdown() or not R.pairsAll then return end
  local on = db.cc ~= false
  for _, p in ipairs(R.pairsAll) do
    local k = on and not (p == R.framePair and db.where == 'split')   -- Haunt: over the mob, never in the frame row
    pcall(p.ring.SetAuraGroupEnabled, p.ring, 'cc', k); pcall(p.main.SetAuraGroupEnabled, p.main, 'cc', k)
  end
end

local function start()
  db = ns.db.rings
  if not db then return end
  holder = CreateFrame('Frame', nil, UIParent); holder:SetSize(1, SIZE)
  pcall(holder.SetFrameStrata, holder, 'MEDIUM')
  anchorHolder()
  local ev = CreateFrame('Frame')
  pcall(ev.RegisterUnitEvent, ev, 'UNIT_SPELLCAST_SUCCEEDED', 'player', 'pet')
  for _, e in ipairs({ 'PLAYER_REGEN_ENABLED', 'PLAYER_TARGET_CHANGED', 'PLAYER_DEAD', 'UI_SCALE_CHANGED' }) do pcall(ev.RegisterEvent, ev, e) end
  ev:SetScript('OnEvent', function(_, e, unit, _, spellID)
    local ok, err = pcall(function()
      if e == 'UNIT_SPELLCAST_SUCCEEDED' then CC.cast(unit, spellID)
      elseif e == 'PLAYER_REGEN_ENABLED' then
        -- out of combat: no mob is held any more
        CC.clear(); anchorHolder(); plateGroups()
      elseif e == 'PLAYER_DEAD' then CC.clear()
      elseif e == 'UI_SCALE_CHANGED' then anchorHolder()
      else update() end
    end)
    if not ok then ns.error('cc: ' .. tostring(err)) end
  end)
  ns.bus:On('PLATE_ADDED', function() if next(holds) then update() end end)
  ns.bus:On('PLATE_REMOVED', function(u)
    -- a held mob that died on screen: its plate goes and it never comes back, so the hold ends here (PlateManager has
    -- already dropped the token from PM.live, so match it by token or GUID directly)
    local okD, dead = pcall(UnitIsDead, u)
    dead = okD and dead == true
    for _, h in pairs(holds) do
      if dead and h.kind ~= 'howl' and (h.token == u or (h.guid and guidOf(u) == h.guid)) then h.over = true end
    end
    for _, h in pairs(holds) do if h.token == u then h.token = nil end end   -- the token goes to another mob next
    if next(holds) then update() end
  end)
  ns.bus:On('SETTING', function(key, store)
    if store == 'rings' and key == 'cc' then plateGroups(); update()
    elseif store == 'rings' and (key == 'size' or key == 'where' or key == 'enabled') then anchorHolder(); update() end
  end)
  plateGroups()
end
ns.starts[#ns.starts + 1] = start

-- /omadoomed cc [test]
function ns.ccSlash(msg)
  msg = (msg or ''):lower()
  if not db then return end
  if msg == 'test' then CC.test(); ns.say('a pretend 15 s Fear beside your target frame.')
  else
    local n = 0; for _ in pairs(holds) do n = n + 1 end
    ns.say(('crowd-control timers %s, %d held now. /omadoomed cc test shows one.'):format(db.cc ~= false and 'on' or 'off', n))
  end
end
