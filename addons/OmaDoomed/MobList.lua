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

local RD = 44                         -- the list's rings (2026-11-16: 40 read thin at real size)
local function seatWidth()
  local _, n = R.seatSpots()
  return n * RD + (n - 1) * R.SEAT_GAP * RD / R.S
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
  -- the glow says something only in a group: solo you hold every mob, so it lit every row red (2026-11-16)
  if not (IsInGroup and IsInGroup()) then if r.glow:IsShown() then r.breath:Stop(); r.glow:Hide() end; return end
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
  pcall(SetPortraitTexture, r.face, u); pcall(SetPortraitTexture, r.lift, u)
  health(r); threat(r); killbar(r); doomed(r)
  r.tgt:SetShown(isTarget(u))
end

-- sheet 75's panel: ONE dark panel with a thin warm border and rounded corners behind the rows that show (2026-11-16:
-- a black block per row read as a slab). Blizzard's own soft tooltip border, tinted. It reaches down to the lowest row
-- showing; plain frame, so it can grow and shrink in combat.
local panel
local function fitPanel()
  if not panel then return end
  local low = 0
  for k = 1, TOKENS do local r = rows[k]; if r and r.shown and (slotOf[k] or k) > low then low = slotOf[k] or k end end
  if low == 0 and not db.unlocked then panel:Hide(); return end
  panel:SetHeight(PADY * 2 + RH * math.max(low, 1)); panel:Show()
end

local function refreshRow(k)
  local r = rows[k]; if not r then return end
  local on = wanted(k)
  r.shown = on
  r:SetShown(on)
  if on then fill(r) else killbar(r) end
  fitPanel()
end

-- ---------- places ----------
local function place(r)
  r:ClearAllPoints()
  r:SetPoint('TOPLEFT', header, 'TOPLEFT', 0, -PADY - ((slotOf[r.k] or r.k) - 1) * RH)
end
-- the click buttons over the rows, by screen position (UIParent units); out of combat only, and in the moment a
-- fight starts. Each button follows its row's rectangle; the rows themselves stay plain frames.
-- 2026-11-16: reading the rows' screen positions failed (the list is hidden until a fight, and a frame that has
-- never shown has no position), so clicking stopped working. Now the buttons hang off 'geo': a plain, always-shown,
-- empty frame placed exactly like the list (same point, size and scale), never shown, hidden or moved in combat.
-- Each button sits at its row's place by arithmetic, in the list's own units.
local geo
local function placeClicks()
  if not (geo and holder and header) or (InCombatLockdown() and fighting) then return end
  pcall(function()
    local p, _, rp, x, y = header:GetPoint(1)
    local sc = header:GetScale()
    geo:SetScale(sc); holder:SetScale(sc)
    geo:ClearAllPoints(); geo:SetPoint(p or 'TOPRIGHT', UIParent, rp or 'TOPRIGHT', x or 0, y or 0)
    geo:SetSize(width(), PADY * 2 + RH * TOKENS)
    for k = 1, TOKENS do
      local r = rows[k]
      if r and r.click then
        r.click:ClearAllPoints()
        r.click:SetPoint('TOPLEFT', geo, 'TOPLEFT', 0, -PADY - ((slotOf[k] or k) - 1) * RH)
        r.click:SetSize(width(), RH)
      end
    end
  end)
end

-- packs the rows top-down: enemies up now first, then every other token in order. Out of combat only (and in the
-- moment a fight starts, before Blizzard locks the secure buttons).
local function pack()
  if InCombatLockdown() and fighting then return end
  -- places: mobs in the fight first, then hostile mobs nearby (the likely joiners), then neutral ones and the rest
  local n, done = 0, {}
  local function hostileIdle(k)
    local u = tok(k)
    if not PM.live[u] then return false end
    local ok, re = pcall(UnitReaction, u, 'player')
    return ok and plain(re) and re <= 3          -- red: likely to join; yellow animals (reaction 4) wait their turn
  end
  for _, pass in ipairs({ wanted, hostileIdle, function() return true end }) do
    for k = 1, TOKENS do if not done[k] and pass(k) then n = n + 1; slotOf[k] = n; done[k] = true end end
  end
  for k = 1, TOKENS do if rows[k] then place(rows[k]) end end
  fitPanel(); placeClicks()
end

-- ---------- building ----------
local function newRow(k)
  local r = CreateFrame('Frame', nil, header)
  r.k, r.unit, r.shown, r.pair = k, tok(k), false, false
  r:SetSize(width(), RH)
  r:Hide()
  r.tgt = r:CreateTexture(nil, 'BACKGROUND', nil, 1); r.tgt:SetPoint('TOPLEFT', 6, -3); r.tgt:SetPoint('BOTTOMRIGHT', -6, 3)
  r.tgt:SetColorTexture(1, .9, 0, .08); r.tgt:Hide()
  -- portrait; Blizzard's aggro colour breathes around it when your threat climbs; the skull on its top edge
  local cx = PADX + D / 2
  -- a soft glow, not a hard ring (2026-11-16: the ring_bold circle read as a thick red hoop)
  r.glow = r:CreateTexture(nil, 'ARTWORK', nil, 0); r.glow:SetTexture(ART .. 'softring_glow', nil, nil, 'TRILINEAR'); r.glow:SetBlendMode('ADD')
  r.glow:SetSize(D * 1.6, D * 1.6); r.glow:SetAlpha(.6); r.glow:SetPoint('CENTER', r, 'LEFT', cx, 0); r.glow:Hide()
  r.breath = r.glow:CreateAnimationGroup(); r.breath:SetLooping('BOUNCE')
  local a = r.breath:CreateAnimation('Alpha'); a:SetFromAlpha(1); a:SetToAlpha(.35); a:SetDuration(.8); a:SetSmoothing('IN_OUT')
  r.face = r:CreateTexture(nil, 'ARTWORK', nil, 1); r.face:SetSize(D, D); r.face:SetPoint('CENTER', r, 'LEFT', cx, 0)
  local m = r:CreateMaskTexture(); m:SetTexture(ART .. 'mask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE', 'TRILINEAR'); m:SetAllPoints(r.face)
  r.face:AddMaskTexture(m)
  -- the 3D portrait is dark at this size: a faint added copy lifts it
  r.lift = r:CreateTexture(nil, 'ARTWORK', nil, 1); r.lift:SetAllPoints(r.face); r.lift:SetBlendMode('ADD'); r.lift:SetAlpha(.45)
  r.lift:AddMaskTexture(m)
  local rim = r:CreateTexture(nil, 'ARTWORK', nil, 2); rim:SetTexture(ART .. 'portrait_rim', nil, nil, 'TRILINEAR'); rim:SetSize(D, D)
  rim:SetPoint('CENTER', r.face, 'CENTER')
  local SW, SH = D * .72, D * .72 * 54 / 78    -- smaller, on the portrait's top edge (it spilled into the row above)
  r.skullWin = CreateFrame('Frame', nil, r); r.skullWin:SetClipsChildren(true)
  r.skullWin:SetSize(SW, SH); r.skullWin:SetPoint('BOTTOM', r.face, 'TOP', 0, -D * .26); r.skullWin:SetFrameLevel(r:GetFrameLevel() + 6)
  r.skullBar = CreateFrame('StatusBar', nil, r.skullWin); r.skullBar:SetSize(SW * 400, SH); r.skullBar:SetPoint('RIGHT', r.skullWin, 'RIGHT')
  r.skullBar:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8'); r.skullBar:SetStatusBarColor(0, 0, 0, 0)
  r.skullBar:SetMinMaxValues(0, 1); r.skullBar:SetValue(0)
  r.skull = r.skullBar:CreateTexture(nil, 'OVERLAY'); r.skull:SetTexture(MARK, nil, nil, 'TRILINEAR'); r.skull:SetTexCoord(0, 78 / 128, 0, 54 / 64)
  r.skull:SetSize(SW, SH); r.skull:SetPoint('RIGHT', r.skullBar:GetStatusBarTexture(), 'RIGHT')
  -- name over the bar; the two as one block on the row's centre line
  local tx = PADX + D + GP
  local blk = NAME * .72 + NB + BAR_H
  r.bar = CreateFrame('StatusBar', nil, r)
  r.bar:SetSize(BW, BAR_H); r.bar:SetPoint('TOPLEFT', r, 'TOPLEFT', tx, -(RH / 2 - blk / 2 + NAME * .72 + NB))
  r.bar:SetStatusBarTexture('Interface\\TargetingFrame\\UI-StatusBar'); r.bar:SetStatusBarColor(.93, .1, .1)   -- Blizzard's bright red, as on sheet 78
  r.bar:SetMinMaxValues(0, 1); r.bar:SetValue(1)
  -- the plates' frame colour round a black line, and a sheen on the fill (sheet 78's bar)
  local bfr = r.bar:CreateTexture(nil, 'BACKGROUND', nil, -2); bfr:SetPoint('TOPLEFT', -2, 2); bfr:SetPoint('BOTTOMRIGHT', 2, -2); bfr:SetColorTexture(.35, .29, .21, 1)
  local bbg = r.bar:CreateTexture(nil, 'BACKGROUND', nil, -1); bbg:SetPoint('TOPLEFT', -1, 1); bbg:SetPoint('BOTTOMRIGHT', 1, -1); bbg:SetColorTexture(0, 0, 0, 1)
  local sheen = r.bar:CreateTexture(nil, 'OVERLAY', nil, 1); sheen:SetPoint('TOPLEFT'); sheen:SetPoint('RIGHT'); sheen:SetHeight(BAR_H * .42); sheen:SetColorTexture(1, 1, 1, .12)
  local bin = r.bar:CreateTexture(nil, 'BACKGROUND', nil, 1); bin:SetAllPoints(r.bar); bin:SetColorTexture(.07, .02, .02, 1)   -- the empty part darker, so the health reads
  r.hp = r.bar:CreateFontString(nil, 'OVERLAY')
  r.hp:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF', BAR_H - 1, 'OUTLINE'); r.hp:SetPoint('CENTER', r.bar, 'CENTER', 0, 0)
  r.name = r:CreateFontString(nil, 'OVERLAY')
  r.name:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF', NAME, 'OUTLINE')   -- names must fit (THICKOUTLINE cut them off)
  r.name:SetTextColor(1, .82, 0); r.name:SetShadowColor(0, 0, 0, 1); r.name:SetShadowOffset(1, -1)
  r.name:SetPoint('BOTTOMLEFT', r.bar, 'TOPLEFT', 0, NB); r.name:SetWidth(BW + GB - 6); r.name:SetJustifyH('LEFT'); pcall(r.name.SetWordWrap, r.name, false)
  -- the click: an invisible secure button over the row, for this row's token, never changed
  -- 2026-11-16 (clicks never targeted): secure buttons fire on the PRESS by default (CVar ActionButtonUseKeyDown), and
  -- this one only listened for the release. Now both, acting on the release (BetterBlizzFrames' working setup), the
  -- template every working Forever example uses, and '*type1' so modifier clicks target too.
  -- 2026-11-16 research: the game refuses targeting a nameplate token directly (since 7.1, in the engine), but a
  -- secure UNIT button for nameplateN becomes your 'mouseover' when hovered (MPlusKick, confirmed on a Midnight
  -- client), and '/target [@mouseover]' is allowed. So the click runs that macro, and mouseover DoT macros and
  -- Blizzard's Mouseover Cast work straight from the list too.
  local b = CreateFrame('Button', 'OmaDoomedListClick' .. k, holder, 'SecureUnitButtonTemplate')
  b:SetAttribute('unit', tok(k))
  b:SetAttribute('*type1', 'macro'); b:SetAttribute('*macrotext1', '/target [@mouseover,harm,nodead]')
  b:SetAttribute('useOnKeyDown', false)
  b:RegisterForClicks('AnyUp', 'AnyDown')
  -- NOT anchored to the row: a secure button anchored to a frame makes that frame secure too, and then showing or
  -- hiding the row in combat is blocked (seen 2026-11-16: ADDON_ACTION_BLOCKED Frame:SetShown). Warlock All-in-One's
  -- way: placed by screen position on its own secure holder, out of combat (placeClicks).
  local hl = b:CreateTexture(nil, 'HIGHLIGHT'); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, .06)
  -- 'exists' only: 'harm' and 'nodead' may test false in combat on Forever and keep the button hidden (Warlock
  -- All-in-One's driver uses exists alone)
  RegisterStateDriver(b, 'visibility', ('[@%s,exists] show; hide'):format(tok(k)))
  r.click = b
  return r
end

-- seats: one row of rings per token, bound once, built one per frame out of combat (no hitch)
local function placeSeats(r)
  local p = r.pair; if not p then return end
  local sw = seatWidth()
  local k = RD / R.S
  p.anchor:SetScale(k)
  p.anchor:ClearAllPoints(); p.anchor:SetSize(sw / k, 1)
  p.anchor:SetPoint('BOTTOM', r, 'BOTTOMLEFT', (PADX + D + GP + BW + GB + sw / 2) / k, ((RH - RD) / 2) / k)
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
        if r.pair then placeSeats(r); r.pair.bar:SetAllPoints(r.bar); r.pair.ring:SetUnit(r.unit); r.pair.main:SetUnit(r.unit); if r.pair.halo then r.pair.halo:SetUnit(r.unit) end end   -- a CC on it: the row's bar becomes its timer too
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
  mover:SetScript('OnMouseUp', function() header:StopMovingOrSizing(); savePos(); placeClicks() end)
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
  grip:SetScript('OnMouseUp', function() grip:SetScript('OnUpdate', nil); db.scale = header:GetScale(); savePos(); placeClicks() end)
  mover:Hide()
end

local function unlock(on)
  if InCombatLockdown() then say('the list can be moved after this fight.'); return end
  db.unlocked = on
  if on and not mover then makeMover() end
  if mover then mover:SetShown(on) end
  visible(); fitPanel()
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
  geo = CreateFrame('Frame', nil, UIParent); geo:SetSize(1, 1)
  holder = CreateFrame('Frame', 'OmaDoomedListClicks', UIParent, 'SecureHandlerStateTemplate')
  holder:SetAllPoints(UIParent)
  holder:SetFrameStrata('HIGH')   -- above the list's own art, which sat over the buttons
  RegisterStateDriver(holder, 'visibility', '[combat] show; hide')
  -- sheet 78's panel: one rounded rectangle with a thin crisp warm line (our own art), stretched by slice margins so
  -- the corners keep their shape (2026-11-16: Blizzard's tooltip border read generic and beveled)
  panel = CreateFrame('Frame', nil, header)
  panel:SetPoint('TOPLEFT', header, 'TOPLEFT'); panel:SetPoint('TOPRIGHT', header, 'TOPRIGHT')
  local pt = panel:CreateTexture(nil, 'BACKGROUND'); pt:SetAllPoints(panel); pt:SetTexture(ART .. 'list_panel', nil, nil, 'TRILINEAR')
  if not (pt.SetTextureSliceMargins and pcall(pt.SetTextureSliceMargins, pt, 12, 12, 12, 12)) then
    pt:SetTexture(nil); pt:SetColorTexture(.043, .035, .035, .9)
  else pcall(pt.SetTextureSliceMode, pt, Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0) end
  panel:SetFrameLevel(header:GetFrameLevel()); panel:Hide()
  for k = 1, TOKENS do rows[k] = newRow(k); rows[k]:SetFrameLevel(header:GetFrameLevel() + 2) end
  layout()
  unlock(db.unlocked == true)
  R.whenGlyph(buildPairs)   -- the list's rings wait for the ring font too
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
    header:ClearAllPoints(); header:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -40, -330); header:SetScale(1); placeClicks(); say('list back in its first place.')
  else
    local n = 0; for k = 1, TOKENS do if rows[k] and rows[k].shown then n = n + 1 end end
    say(('mob list: %d shown of up to %d. /omadoomed list unlock | lock | rows 4-16 | reset'):format(n, db.rows))
  end
end
L.rows = rows
L.slotOf = slotOf
