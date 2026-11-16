-- OmaDoomed, the mob list (sheets 69, 72, 73, 75; approved 2026-11-16 "build it"): every enemy in the fight in one
-- TV-sized window, one row each: its portrait (with Blizzard's aggro glow when your threat climbs), its name, its
-- health with your kill bar and its number, your DoTs in their seats, and the skull on a mob your DoTs will finish.
-- Click a row to target that mob, in combat too.
--
-- Built the way the Forever add-ons that work do it (Warlock HUD's rows, Warlock All-in-One's clicks; 2026-11-16,
-- after the first build showed nothing in a real fight: everything sat behind one secure script that handed mobs to
-- rows, and when that script didn't run, nothing showed at all):
--   * Every nameplate token has its own row for good (nameplate3's row always shows nameplate3), so a row's rings and
--     bar are bound once and never re-pointed.
--   * Plain add-on code shows and hides the rows (they aren't secure, so that's allowed in combat).
--   * Out of combat, and in the moment a fight starts, the rows are packed top-down: enemies first, then the free
--     tokens in order. In combat nothing moves: a mob keeps its row, a newcomer appears in the place its token already
--     has, and you never click the wrong row because the list re-sorted.
--   * Clicking: an invisible secure button over each row, for that row's token, never changed; Blizzard's own state
--     driver shows it while that unit is a living enemy ("[@nameplateN,exists,harm,nodead]"; Warlock All-in-One
--     uses the same driver with "exists" on Forever).
--     If the click part ever failed, the list would still show.
--
-- Shown in combat only. '/omadoomed list unlock' shows it out of combat to drag it (and its corner to size it).
local ADDON, ns = ...
local L = {}; ns.moblist = L
local R, Secret = ns.rings, ns.core.Secret
local PM = ns.plates
local ART = 'Interface\\AddOns\\OmaDoomed\\Art\\rings\\'
local MARK = 'Interface\\AddOns\\OmaDoomed\\Art\\doomed-mark'

-- sheet 75: one grid, u = a quarter ring. Every distance is a whole number of u (in the list's own units).
local U = 10
local D = 4 * U                       -- ring = portrait
local PADX, PADY = 2 * U, 1.5 * U
local GP = 1.5 * U                    -- portrait -> name
local BW = 18 * U                     -- health / kill bar
local GB = 3 * U                      -- bar -> rings: wider than between rings, so the two groups read apart
local RH = 6 * U                      -- a row is 1.5 rings tall
local NAME, BAR_H, NB = 16, 12, 6     -- name size, bar height, name -> bar gap
L.U, L.D, L.RH = U, D, RH
local TCOL = { [1] = { 1, .82, 0 }, [2] = { 1, .48, 0 }, [3] = { 1, .1, .1 } }   -- Blizzard's threat colours
local TOKENS = 16                     -- nameplate1..16 (Warlock HUD's number)

local db                              -- OmaDoomedDB.list
local header, holder                  -- the window (plain), the click buttons' secure parent
local rows, slotOf = {}, {}           -- token index -> row; token index -> place in the list (1 = top)
local fighting = false
local function say(m) print('|cffb48cffOmaDoomed:|r ' .. m) end
local function plain(v) return v ~= nil and not Secret.is(v) end
local function tok(k) return 'nameplate' .. k end

local function seatWidth()
  local _, n = R.seatSpots()
  return n * D + (n - 1) * R.SEAT_GAP
end
local function width() return PADX + D + GP + BW + GB + seatWidth() + PADX end

-- ---------- who a row shows ----------
local function alive(u)
  local ok, dead = pcall(UnitIsDead, u)
  return not (ok and plain(dead) and dead == true)
end
-- In YOUR fight (2026-11-16, his screenshots: the list showed a Kodo he never touched and missed hyenas he was
-- fighting, and kept a dead one at 0). 'Can I attack it' is hidden in combat, so a plate that appeared mid-fight
-- counted as friendly; and 'is it dead' is hidden too. Warlock HUD's rule instead, which Forever answers: you, your
-- pet or a party/raid member is on the mob's threat list (a hidden answer counts as no), or it carries your DoTs.
-- A dead mob drops off every threat list, so its row goes.
local GROUP = { 'player', 'pet' }
for i = 1, 4 do GROUP[#GROUP + 1] = 'party' .. i; GROUP[#GROUP + 1] = 'partypet' .. i end
local dlist, dseen2 = {}, {}
local function inFight(u)
  for _, m in ipairs(GROUP) do
    local ok, st = pcall(UnitThreatSituation, m, u)
    if ok and plain(st) then return true end
  end
  if IsInRaid and IsInRaid() then
    for i = 1, 40 do local ok, st = pcall(UnitThreatSituation, 'raid' .. i, u); if ok and plain(st) then return true end end
  end
  local ok = pcall(ns.model.listInto, u, true, dlist, dseen2)
  return ok and #dlist > 0
end
local function wanted(k)
  local u = tok(k)
  return PM.live[u] ~= nil and alive(u) and inFight(u)
end

local function isTarget(u)
  local ok, tp = pcall(C_NamePlate.GetNamePlateForUnit, 'target', false)
  local ok2, up = pcall(C_NamePlate.GetNamePlateForUnit, u, false)
  return ok and ok2 and tp ~= nil and tp == up
end

local function threat(r)
  local ok, s = pcall(UnitThreatSituation, 'player', r.unit)
  local c = ok and plain(s) and TCOL[s]
  if c then
    r.glow:SetVertexColor(c[1], c[2], c[3])
    if not r.glow:IsShown() then r.glow:Show(); r.breath:Play() end
  elseif r.glow:IsShown() then r.breath:Stop(); r.glow:Hide() end
end

local function health(r)
  local u = r.unit
  local okM, m = pcall(UnitHealthMax, u)
  local okH, h = pcall(UnitHealth, u)
  if okM then pcall(r.bar.SetMinMaxValues, r.bar, 0, m) end
  if okH then pcall(r.bar.SetValue, r.bar, h); pcall(r.hp.SetText, r.hp, h) end   -- a hidden number may be handed over
end

local function killbar(r)
  local K = ns.parts.platebar
  if K and K.paintRow then pcall(K.paintRow, r.shown and r.unit or nil, r.bar) end
end

-- the skull: your DoTs will finish this mob. Health is hidden in combat, so it's the target frame's own trick
-- (Doomed.lua): a bar 400 skulls long, 0 to the mob's health, filled with your DoTs' damage left; the skull rides the
-- fill's end and only reaches the little window over the portrait once the damage covers the health.
local dl, dseen = {}, {}
local function doomed(r)
  if ns.db.skull == false then r.skullWin:Hide(); return end
  r.skullWin:Show()
  local ok = pcall(ns.model.listInto, r.unit, true, dl, dseen)
  local total = 0
  if ok then for _, d in ipairs(dl) do total = total + (d.damage or 0) end end
  local okH, h = pcall(UnitHealth, r.unit)
  if okH then pcall(r.skullBar.SetMinMaxValues, r.skullBar, 0, h) end
  r.skullBar:SetValue(total)
end

local function fill(r)
  local u = r.unit
  pcall(r.name.SetText, r.name, UnitName(u))
  pcall(SetPortraitTexture, r.face, u)
  health(r); threat(r); killbar(r); doomed(r)
  r.tgt:SetShown(isTarget(u))
end

local function refreshRow(k)
  local r = rows[k]; if not r then return end
  local on = wanted(k)
  r.shown = on
  r:SetShown(on)
  if on then fill(r) else killbar(r) end
end

-- ---------- places ----------
local function place(r)
  r:ClearAllPoints()
  r:SetPoint('TOPLEFT', header, 'TOPLEFT', 0, -PADY - ((slotOf[r.k] or r.k) - 1) * RH)
end
-- packs the rows top-down: enemies up now first, then every other token in order. Out of combat only (and in the
-- moment a fight starts, before Blizzard locks the secure buttons).
local function pack()
  if InCombatLockdown() and fighting then return end
  local n = 0
  for k = 1, TOKENS do if wanted(k) then n = n + 1; slotOf[k] = n end end
  for k = 1, TOKENS do if not wanted(k) then n = n + 1; slotOf[k] = n end end
  for k = 1, TOKENS do if rows[k] then place(rows[k]) end end
end

-- ---------- building ----------
local function newRow(k)
  local r = CreateFrame('Frame', nil, header)
  r.k, r.unit, r.shown, r.pair = k, tok(k), false, false
  r:SetSize(width(), RH)
  r:Hide()
  -- the row's panel: sheet 73/75's plain dark panel, no dividers
  local bg = r:CreateTexture(nil, 'BACKGROUND'); bg:SetAllPoints(r); bg:SetColorTexture(.043, .035, .035, .9)
  r.tgt = r:CreateTexture(nil, 'BACKGROUND', nil, 1); r.tgt:SetPoint('TOPLEFT', 6, -3); r.tgt:SetPoint('BOTTOMRIGHT', -6, 3)
  r.tgt:SetColorTexture(1, .9, 0, .08); r.tgt:Hide()
  -- portrait; Blizzard's aggro colour breathes around it when your threat climbs; the skull on its top edge
  local cx = PADX + D / 2
  -- a soft glow, not a hard ring (2026-11-16: the ring_bold circle read as a thick red hoop)
  r.glow = r:CreateTexture(nil, 'ARTWORK', nil, 0); r.glow:SetTexture(ART .. 'softring_glow'); r.glow:SetBlendMode('ADD')
  r.glow:SetSize(D * 1.7, D * 1.7); r.glow:SetPoint('CENTER', r, 'LEFT', cx, 0); r.glow:Hide()
  r.breath = r.glow:CreateAnimationGroup(); r.breath:SetLooping('BOUNCE')
  local a = r.breath:CreateAnimation('Alpha'); a:SetFromAlpha(1); a:SetToAlpha(.35); a:SetDuration(.8); a:SetSmoothing('IN_OUT')
  r.face = r:CreateTexture(nil, 'ARTWORK', nil, 1); r.face:SetSize(D * .9, D * .9); r.face:SetPoint('CENTER', r, 'LEFT', cx, 0)
  local m = r:CreateMaskTexture(); m:SetTexture(ART .. 'mask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE'); m:SetAllPoints(r.face)
  r.face:AddMaskTexture(m)
  local rim = r:CreateTexture(nil, 'ARTWORK', nil, 2); rim:SetTexture(ART .. 'portrait_rim'); rim:SetSize(D * .94, D * .94)
  rim:SetPoint('CENTER', r.face, 'CENTER')
  local SW, SH = D * .95, D * .95 * 54 / 78
  r.skullWin = CreateFrame('Frame', nil, r); r.skullWin:SetClipsChildren(true)
  r.skullWin:SetSize(SW, SH); r.skullWin:SetPoint('BOTTOM', r.face, 'TOP', 0, -D * .18); r.skullWin:SetFrameLevel(r:GetFrameLevel() + 6)
  r.skullBar = CreateFrame('StatusBar', nil, r.skullWin); r.skullBar:SetSize(SW * 400, SH); r.skullBar:SetPoint('RIGHT', r.skullWin, 'RIGHT')
  r.skullBar:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8'); r.skullBar:SetStatusBarColor(0, 0, 0, 0)
  r.skullBar:SetMinMaxValues(0, 1); r.skullBar:SetValue(0)
  r.skull = r.skullBar:CreateTexture(nil, 'OVERLAY'); r.skull:SetTexture(MARK); r.skull:SetTexCoord(0, 78 / 128, 0, 54 / 64)
  r.skull:SetSize(SW, SH); r.skull:SetPoint('RIGHT', r.skullBar:GetStatusBarTexture(), 'RIGHT')
  -- name over the bar; the two as one block on the row's centre line
  local tx = PADX + D + GP
  local blk = NAME * .72 + NB + BAR_H
  r.bar = CreateFrame('StatusBar', nil, r)
  r.bar:SetSize(BW, BAR_H); r.bar:SetPoint('TOPLEFT', r, 'TOPLEFT', tx, -(RH / 2 - blk / 2 + NAME * .72 + NB))
  r.bar:SetStatusBarTexture('Interface\\TargetingFrame\\UI-StatusBar'); r.bar:SetStatusBarColor(.78, .08, .08)
  r.bar:SetMinMaxValues(0, 1); r.bar:SetValue(1)
  local bbg = r.bar:CreateTexture(nil, 'BACKGROUND'); bbg:SetPoint('TOPLEFT', -1, 1); bbg:SetPoint('BOTTOMRIGHT', 1, -1); bbg:SetColorTexture(0, 0, 0, 1)
  local bin = r.bar:CreateTexture(nil, 'BACKGROUND', nil, 1); bin:SetAllPoints(r.bar); bin:SetColorTexture(.16, .03, .03, 1)
  r.hp = r.bar:CreateFontString(nil, 'OVERLAY')
  r.hp:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF', BAR_H - 1, 'OUTLINE'); r.hp:SetPoint('CENTER', r.bar, 'CENTER', 0, 0)
  r.name = r:CreateFontString(nil, 'OVERLAY')
  r.name:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF', NAME, 'OUTLINE')
  r.name:SetTextColor(1, .82, 0); r.name:SetShadowColor(0, 0, 0, 1); r.name:SetShadowOffset(1, -1)
  r.name:SetPoint('BOTTOMLEFT', r.bar, 'TOPLEFT', 0, NB); r.name:SetWidth(BW); r.name:SetJustifyH('LEFT'); pcall(r.name.SetWordWrap, r.name, false)
  -- the click: an invisible secure button over the row, for this row's token, never changed
  local b = CreateFrame('Button', 'OmaDoomedListClick' .. k, holder, 'SecureUnitButtonTemplate')
  b:SetAttribute('type1', 'target'); b:SetAttribute('unit', tok(k))
  b:RegisterForClicks('AnyUp')
  b:SetAllPoints(r)
  local hl = b:CreateTexture(nil, 'HIGHLIGHT'); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, .06)
  RegisterStateDriver(b, 'visibility', ('[@%s,exists,harm,nodead] show; hide'):format(tok(k)))   -- enemies only
  r.click = b
  return r
end

-- seats: one row of rings per token, bound once, built one per frame out of combat (no hitch)
local function placeSeats(r)
  local p = r.pair; if not p then return end
  local sw = seatWidth()
  p.anchor:ClearAllPoints(); p.anchor:SetSize(sw, 1)
  p.anchor:SetPoint('BOTTOM', r, 'BOTTOMLEFT', PADX + D + GP + BW + GB + sw / 2, (RH - D) / 2)
end
local builder
local function buildPairs()
  builder = builder or CreateFrame('Frame')
  builder:SetScript('OnUpdate', function(self)
    if InCombatLockdown() then self:SetScript('OnUpdate', nil); return end
    for k = 1, TOKENS do
      local r = rows[k]
      if r and not r.pair then
        r.pair = R.newListPair(r) or false
        if r.pair then placeSeats(r); r.pair.bar:SetAllPoints(r.bar); r.pair.ring:SetUnit(r.unit); r.pair.main:SetUnit(r.unit) end   -- a CC on it: the row's bar becomes its timer too
        return
      end
    end
    self:SetScript('OnUpdate', nil)
  end)
end

-- the window's size follows the seats you know (Siphon Life at 30 adds one) and the rows; out of combat
local function layout()
  if InCombatLockdown() or not header then return end
  local w = width()
  header:SetSize(w, PADY * 2 + RH * (db.rows or 8))
  for k = 1, TOKENS do local r = rows[k]; if r then r:SetWidth(w); placeSeats(r) end end
  pack()
end

-- the window shows in a fight, or unlocked to move; plain code (the window isn't secure)
local function visible()
  if not header then return end
  header:SetShown(fighting or db.unlocked == true)
end

-- ---------- moving and sizing (out of combat) ----------
local mover
local function savePos()
  local p, _, rp, x, y = header:GetPoint(1)
  db.point, db.rel, db.x, db.y = p, rp, x, y
end
local function makeMover()
  mover = CreateFrame('Frame', nil, header)
  mover:SetAllPoints(header); mover:SetFrameLevel(header:GetFrameLevel() + 40); mover:EnableMouse(true)
  local t = mover:CreateTexture(nil, 'BACKGROUND'); t:SetAllPoints(); t:SetColorTexture(.043, .035, .035, .6)
  for _, e in ipairs({ { 'TOPLEFT', 'TOPRIGHT', 'h' }, { 'BOTTOMLEFT', 'BOTTOMRIGHT', 'h' }, { 'TOPLEFT', 'BOTTOMLEFT', 'w' }, { 'TOPRIGHT', 'BOTTOMRIGHT', 'w' } }) do
    local l = mover:CreateTexture(nil, 'BORDER'); l:SetColorTexture(.42, .32, .15, 1)
    l:SetPoint(e[1]); l:SetPoint(e[2]); if e[3] == 'w' then l:SetWidth(2) else l:SetHeight(2) end
  end
  mover:SetScript('OnMouseDown', function(_, b) if b == 'LeftButton' and not InCombatLockdown() then header:StartMoving() end end)
  mover:SetScript('OnMouseUp', function() header:StopMovingOrSizing(); savePos() end)
  -- the corner sizes the whole window (its scale), so every distance keeps its grid
  local grip = CreateFrame('Frame', nil, mover); grip:SetSize(22, 22); grip:SetPoint('BOTTOMRIGHT'); grip:EnableMouse(true)
  local gt = grip:CreateTexture(nil, 'OVERLAY'); gt:SetAllPoints(); gt:SetTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
  local from, start = 0, 1
  grip:SetScript('OnMouseDown', function()
    from, start = GetCursorPosition(), header:GetScale()
    grip:SetScript('OnUpdate', function()
      local w = header:GetWidth() * header:GetEffectiveScale()
      header:SetScale(math.max(.6, math.min(2, start * (1 + (GetCursorPosition() - from) / w))))
    end)
  end)
  grip:SetScript('OnMouseUp', function() grip:SetScript('OnUpdate', nil); db.scale = header:GetScale(); savePos() end)
  mover:Hide()
end

local function unlock(on)
  if InCombatLockdown() then say('the list can be moved after this fight.'); return end
  db.unlocked = on
  if on and not mover then makeMover() end
  if mover then mover:SetShown(on) end
  visible()
end

-- ---------- the ticker: threat, your target, health, the skull ----------
local since = 0
local function tick(_, el)
  since = since + el
  if since < .2 then return end
  since = 0
  for k = 1, TOKENS do
    local r = rows[k]
    if r then
      local on = wanted(k)
      if on ~= r.shown then refreshRow(k)
      elseif on then pcall(threat, r); pcall(health, r); pcall(doomed, r); r.tgt:SetShown(isTarget(r.unit)) end
    end
  end
end

local function start()
  if not R.db or not CreateFrame or not RegisterStateDriver then return end
  ns.db.list = ns.db.list or {}
  db = ns.db.list
  if db.enabled == false then return end
  db.rows = math.max(4, math.min(TOKENS, tonumber(db.rows) or 8))
  header = CreateFrame('Frame', 'OmaDoomedList', UIParent)
  header:SetClampedToScreen(true); header:SetMovable(true)
  header:SetScale(db.scale or 1)
  -- first place: down the right side under the minimap, clear of the target frame (2026-11-16)
  header:SetPoint(db.point or 'TOPRIGHT', UIParent, db.rel or 'TOPRIGHT', db.x or -40, db.y or -330)
  -- the click buttons' parent: secure, shown in a fight (Blizzard's driver); the buttons sit over the rows
  holder = CreateFrame('Frame', 'OmaDoomedListClicks', UIParent, 'SecureHandlerStateTemplate')
  holder:SetAllPoints(UIParent)
  RegisterStateDriver(holder, 'visibility', '[combat] show; hide')
  for k = 1, TOKENS do rows[k] = newRow(k) end
  layout()
  unlock(db.unlocked == true)
  buildPairs()
  ns.bus:On('DOTS', function() for k = 1, TOKENS do local r = rows[k]; if r and r.shown then killbar(r) end end end)
  local function plateEvent(u)
    local k = type(u) == 'string' and tonumber(u:match('^nameplate(%d+)$'))
    if k and rows[k] then
      if not InCombatLockdown() then pack() end
      refreshRow(k)
    end
  end
  ns.bus:On('PLATE_ADDED', plateEvent)
  ns.bus:On('PLATE_REMOVED', plateEvent)
  ns.bus:On('PLATE_CHANGED', plateEvent)
  local ev = CreateFrame('Frame')
  for _, e in ipairs({ 'PLAYER_REGEN_DISABLED', 'PLAYER_REGEN_ENABLED', 'SPELLS_CHANGED', 'PLAYER_TARGET_CHANGED', 'UNIT_HEALTH', 'UNIT_THREAT_LIST_UPDATE' }) do pcall(ev.RegisterEvent, ev, e) end
  ev:SetScript('OnEvent', function(_, e, u)
    if e == 'PLAYER_REGEN_DISABLED' then
      pack()                      -- the last packing before Blizzard locks the buttons: the places for this fight
      fighting = true; visible()
      for k = 1, TOKENS do refreshRow(k) end
    elseif e == 'PLAYER_REGEN_ENABLED' then
      fighting = false; visible(); layout(); buildPairs()
      for k = 1, TOKENS do refreshRow(k) end
    elseif e == 'SPELLS_CHANGED' then layout()
    elseif e == 'PLAYER_TARGET_CHANGED' then for k = 1, TOKENS do local r = rows[k]; if r and r.shown then r.tgt:SetShown(isTarget(r.unit)) end end
    elseif e == 'UNIT_THREAT_LIST_UPDATE' then
      local k = type(u) == 'string' and tonumber(u:match('^nameplate(%d+)$'))
      if k and rows[k] then refreshRow(k) end
    elseif e == 'UNIT_HEALTH' then
      local k = type(u) == 'string' and tonumber(u:match('^nameplate(%d+)$'))
      if k and rows[k] and rows[k].shown then
        pcall(health, rows[k])
        if not alive(u) then refreshRow(k) end     -- it died: its row goes (its place stays empty this fight)
      end
    end
  end)
  local ticker = CreateFrame('Frame', nil, header); ticker:SetScript('OnUpdate', tick)
  L.header = header
  fighting = InCombatLockdown() and true or false; visible()
  for k = 1, TOKENS do refreshRow(k) end
end
ns.starts[#ns.starts + 1] = start

function L.slash(msg)
  local cmd, arg = (msg or ''):match('^(%S*)%s*(.-)$'); cmd = (cmd or ''):lower()
  if not header then say('the mob list is off (it needs the rings on).'); return end
  if cmd == 'unlock' then unlock(true); say('drag the list where you want it, and its corner to size it. /omadoomed list lock when done.')
  elseif cmd == 'lock' then unlock(false); say('list locked: it shows in fights.')
  elseif cmd == 'rows' then
    local n = tonumber(arg); if n then db.rows = math.max(4, math.min(TOKENS, n)); layout(); say(('the list shows up to %d mobs.'):format(db.rows)) end
  elseif cmd == 'reset' then
    if InCombatLockdown() then return end
    db.point, db.rel, db.x, db.y, db.scale = nil, nil, nil, nil, nil
    header:ClearAllPoints(); header:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -40, -330); header:SetScale(1); say('list back in its first place.')
  else
    local n = 0; for k = 1, TOKENS do if rows[k] and rows[k].shown then n = n + 1 end end
    say(('mob list: %d shown of up to %d. /omadoomed list unlock | lock | rows 4-16 | reset'):format(n, db.rows))
  end
end
L.rows = rows
L.slotOf = slotOf
