-- OmaDoomed, the mob list (sheet 83, approved 2026-11-16 "build engines"; one frame, rows like your nameplates).
-- Every enemy in your fight, one row each: its portrait (threat rim, your demon's mark, its raid mark, OmaDoomed's
-- skull when your DoTs will finish it), its name and health in Blizzard's own nameplate bar, your DoTs in their seats,
-- and a shield or anti-magic buff while it has one. One soft dark backing behind the whole list, no boxes.
-- Built on the engines: Roster (who and what), Scheduler (when), Motion (how things move), Layout (sizes), Skin (art).
--
-- Clicking (research, 2026-11-16): the game refuses targeting a nameplate token from an add-on button, but hovering a
-- secure UNIT button for nameplateN makes that mob your mouseover. So each row has an invisible button that runs
-- '/target [@mouseover]', and mouseover DoT keys / Mouseover Cast work from the list. Those buttons are locked in
-- place in a fight, so in a fight each mob keeps its row (no re-sorting under your mouse); between fights and at the
-- pull the list sorts: missing a DoT first, then the soonest ending.
--
-- Shown in fights. Moving and sizing: /omadoomed list unlock (Blizzard's Edit Mode look; drag it, size it with the
-- corner grip), /omadoomed list lock.
local ADDON, ns = ...
local L = {}; ns.moblist = L
local R, RO, M, K = ns.rings, ns.roster, ns.motion, ns.skin
local G = ns.layout and ns.layout.LIST
local TOKENS = 16

local u = G and G.u or 2
local ROW, PORT, GAPP, BAR, BARH, NAME = G.row * u, G.portrait * u, G.gapPortrait * u, G.bar * u, G.barH * u, G.name * u
local GAPR, RING, RINGGAP, PADX, PADY = G.gapRings * u, G.ring * u, G.ringGap * u, G.padX * u, G.padY * u
local BUFF = 22
L.RH = ROW

local db
local header, holder, geo, back, sel, grip
local rows, slotOf = {}, {}
local fighting = false
local function say(m) print('|cffb48cffOmaDoomed:|r ' .. m) end
local function tok(k) return 'nameplate' .. k end

local function seatWidth()
  local _, n = R.seatSpots()
  return n * RING + (n - 1) * RINGGAP
end
local function width() return PADX + PORT + GAPP + BAR + GAPR + seatWidth() + 6 + 2 * BUFF + PADX end
L.width = width

-- ---------- a row ----------
local function texCoord(t, c) t:SetTexCoord(c[1], c[2], c[3], c[4]) end

local function newRow(k)
  local r = CreateFrame('Frame', nil, header)
  r.k, r.unit, r.shown, r.pair = k, tok(k), false, false
  r.y, r.lv, r.wantA = false, false, false   -- set, never nil (a frame answers unknown keys)
  r:SetSize(width(), ROW); r:Hide(); r:SetAlpha(0)
  -- threat: a soft swell of light behind the row, in Blizzard's threat colour, breathing (Motion)
  r.glow = r:CreateTexture(nil, 'BACKGROUND', nil, 2); r.glow:SetTexture(K.rowGlow, nil, nil, 'TRILINEAR')
  r.glow:SetPoint('TOPLEFT', r, 'TOPLEFT', -14, -2); r.glow:SetPoint('BOTTOMRIGHT', r, 'BOTTOMRIGHT', -(width() * .3), 2)
  r.glow:SetBlendMode('ADD'); r.glow:SetAlpha(0)
  -- hover: the same soft swell, white and faint
  r.hover = r:CreateTexture(nil, 'BACKGROUND', nil, 3); r.hover:SetTexture(K.rowGlow, nil, nil, 'TRILINEAR')
  r.hover:SetAllPoints(r.glow); r.hover:SetVertexColor(1, 1, 1); r.hover:SetBlendMode('ADD'); r.hover:SetAlpha(0)
  -- portrait in a thin ring (black, or the threat colour)
  local cx = PADX + PORT / 2
  r.face = r:CreateTexture(nil, 'ARTWORK', nil, 1); r.face:SetSize(PORT, PORT); r.face:SetPoint('CENTER', r, 'LEFT', cx, 0)
  local m = r:CreateMaskTexture(); m:SetTexture(K.ART .. 'rings\\mask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE', 'TRILINEAR'); m:SetAllPoints(r.face)
  r.face:AddMaskTexture(m)
  r.lift = r:CreateTexture(nil, 'ARTWORK', nil, 1); r.lift:SetAllPoints(r.face); r.lift:SetBlendMode('ADD'); r.lift:SetAlpha(.4); r.lift:AddMaskTexture(m)
  r.ring = r:CreateTexture(nil, 'ARTWORK', nil, 3); r.ring:SetTexture(K.portraitRing, nil, nil, 'TRILINEAR')
  r.ring:SetSize(PORT + 6, PORT + 6); r.ring:SetPoint('CENTER', r.face, 'CENTER'); r.ring:SetVertexColor(0, 0, 0, .9)
  -- your demon's mark (its own icon) and the mob's raid mark, on the portrait's lower corners
  r.pet = r:CreateTexture(nil, 'OVERLAY', nil, 2); r.pet:SetSize(15, 15); r.pet:SetPoint('CENTER', r.face, 'BOTTOMRIGHT', -2, 2); r.pet:Hide()
  local pm = r:CreateMaskTexture(); pm:SetTexture(K.ART .. 'rings\\mask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE', 'TRILINEAR'); pm:SetAllPoints(r.pet); r.pet:AddMaskTexture(pm)
  r.petRim = r:CreateTexture(nil, 'OVERLAY', nil, 3); r.petRim:SetTexture(K.portraitRing, nil, nil, 'TRILINEAR'); r.petRim:SetSize(19, 19)
  r.petRim:SetPoint('CENTER', r.pet, 'CENTER'); r.petRim:SetVertexColor(K.petRim[1], K.petRim[2], K.petRim[3]); r.petRim:Hide()
  r.mark = r:CreateTexture(nil, 'OVERLAY', nil, 2); r.mark:SetSize(13, 13); r.mark:SetPoint('CENTER', r.face, 'BOTTOMLEFT', 2, 2)
  r.mark:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcons'); r.mark:Hide()
  -- OmaDoomed's skull on the portrait's top edge (the target frame's trick: a long bar 0..health filled with your
  -- DoTs' damage; the skull rides its end and reaches the little window only when the damage covers the health)
  local SW, SH = PORT * .78, PORT * .78 * 54 / 78
  r.skullWin = CreateFrame('Frame', nil, r); r.skullWin:SetClipsChildren(true)
  r.skullWin:SetSize(SW, SH); r.skullWin:SetPoint('BOTTOM', r.face, 'TOP', 0, -PORT * .3); r.skullWin:SetFrameLevel(r:GetFrameLevel() + 6)
  r.skullBar = CreateFrame('StatusBar', nil, r.skullWin); r.skullBar:SetSize(SW * 400, SH); r.skullBar:SetPoint('RIGHT', r.skullWin, 'RIGHT')
  r.skullBar:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8'); r.skullBar:SetStatusBarColor(0, 0, 0, 0)
  r.skullBar:SetMinMaxValues(0, 1); r.skullBar:SetValue(0)
  r.skull = r.skullBar:CreateTexture(nil, 'OVERLAY'); r.skull:SetTexture(K.mark, nil, nil, 'TRILINEAR'); r.skull:SetTexCoord(0, 78 / 128, 0, 54 / 64)
  r.skull:SetSize(SW, SH); r.skull:SetPoint('RIGHT', r.skullBar:GetStatusBarTexture(), 'RIGHT')
  -- name and health, built like the nameplate: Blizzard's bar frame, status bar art, white name
  local tx = PADX + PORT + GAPP
  local blk = NAME + 3 + BARH
  r.bar = CreateFrame('StatusBar', nil, r)
  r.bar:SetSize(BAR - 4, BARH - 6); r.bar:SetPoint('TOPLEFT', r, 'TOPLEFT', tx + 2, -(ROW / 2 - blk / 2 + NAME + 3 + 3))
  r.bar:SetStatusBarTexture(K.statusbar); r.bar:SetStatusBarColor(K.healthRed[1], K.healthRed[2], K.healthRed[3])
  r.bar:SetMinMaxValues(0, 1); r.bar:SetValue(1)
  local empty = r.bar:CreateTexture(nil, 'BACKGROUND', nil, -1); empty:SetPoint('TOPLEFT', -1, 1); empty:SetPoint('BOTTOMRIGHT', 1, -1); empty:SetColorTexture(K.empty[1], K.empty[2], K.empty[3], 1)
  r.frameArt = r.bar:CreateTexture(nil, 'OVERLAY', nil, 2); r.frameArt:SetTexture(K.plateTex, nil, nil, 'TRILINEAR'); texCoord(r.frameArt, K.plateFrame)
  r.frameArt:SetPoint('TOPLEFT', r.bar, 'TOPLEFT', -2, 3); r.frameArt:SetPoint('BOTTOMRIGHT', r.bar, 'BOTTOMRIGHT', 2, -3)
  r.tgt = r.bar:CreateTexture(nil, 'OVERLAY', nil, 3); r.tgt:SetTexture(K.plateTex, nil, nil, 'TRILINEAR'); texCoord(r.tgt, K.plateTarget)
  r.tgt:SetPoint('TOPLEFT', r.bar, 'TOPLEFT', -4, 4); r.tgt:SetPoint('BOTTOMRIGHT', r.bar, 'BOTTOMRIGHT', 4, -4); r.tgt:Hide()
  r.hp = r.bar:CreateFontString(nil, 'OVERLAY', nil, 7); r.hp:SetFont(K.font, 10, 'OUTLINE'); r.hp:SetPoint('CENTER', r.bar, 'CENTER', 0, 0)
  -- a tick: the DoT pieces flash (a soft white light over the bar) as they shrink (sheet 83, row 1)
  r.bite = r.bar:CreateTexture(nil, 'OVERLAY', nil, 1); r.bite:SetTexture(K.statusbar); r.bite:SetAllPoints(r.bar)
  r.bite:SetVertexColor(1, .93, .8); r.bite:SetBlendMode('ADD'); r.bite:SetAlpha(0)
  r.dmg, r.nd = false, false
  -- the mob's cast: a thin line under its bar, red when you can interrupt it (Spell Lock), grey when you can't
  r.cast = CreateFrame('StatusBar', nil, r); r.cast:SetSize(BAR - 4, 3); r.cast:SetPoint('TOPLEFT', r.bar, 'BOTTOMLEFT', 0, -3)
  r.cast:SetStatusBarTexture(K.statusbar); r.cast:SetMinMaxValues(0, 1); r.cast:SetValue(0); r.cast:Hide()
  local cb = r.cast:CreateTexture(nil, 'BACKGROUND'); cb:SetAllPoints(); cb:SetColorTexture(0, 0, 0, .7)
  r.name = r:CreateFontString(nil, 'OVERLAY'); r.name:SetFont(K.font, NAME, 'OUTLINE')
  r.name:SetTextColor(1, 1, 1); r.name:SetShadowColor(0, 0, 0, 1); r.name:SetShadowOffset(1, -1)
  r.name:SetPoint('BOTTOMLEFT', r.bar, 'TOPLEFT', -1, 6); r.name:SetWidth(BAR); r.name:SetJustifyH('LEFT'); pcall(r.name.SetWordWrap, r.name, false)
  -- shields and anti-magic: only while the mob has one (HELPFUL|IMPORTANT, what the game itself flags)
  local ok, buffs = pcall(CreateFrame, 'AuraContainer', nil, r, 'CustomAuraContainerTemplate')
  if ok and buffs then
    pcall(buffs.SetEditModePreviewEnabled, buffs, false)
    buffs:SetFlowLayoutAnchorPoint('LEFT'); buffs:SetFlowLayoutGrowthDirection(1, 1); buffs:SetFlowLayoutMaximumLineSize(BUFF * 2.5)
    local okG = pcall(buffs.AddAuraGroup, buffs, 'buffs', 'HELPFUL|IMPORTANT|INCLUDE_NAME_PLATE_ONLY', { initializeFrame = R.buffButton(BUFF), maxFrameCount = 2, layout = { groupSpacing = 4 } })
    if okG then r.buffs = buffs; buffs:SetPoint('LEFT', r, 'LEFT', tx + BAR + GAPR + seatWidth() + 6, 0); buffs:SetUnit(r.unit) end
  end
  -- the click: an invisible secure unit button for this token, never changed (see the top of the file)
  local b = CreateFrame('Button', 'OmaDoomedListClick' .. k, holder, 'SecureUnitButtonTemplate')
  b:SetAttribute('unit', tok(k))
  b:SetAttribute('*type1', 'macro'); b:SetAttribute('*macrotext1', '/target [@mouseover,harm,nodead]')
  b:SetAttribute('useOnKeyDown', false)
  b:RegisterForClicks('AnyUp', 'AnyDown')
  b:HookScript('OnEnter', function() M.tween('hov' .. k, r.hover:GetAlpha(), .22, .12, function(v) r.hover:SetAlpha(v) end) end)
  b:HookScript('OnLeave', function() M.tween('hov' .. k, r.hover:GetAlpha(), 0, .25, function(v) r.hover:SetAlpha(v) end) end)
  RegisterStateDriver(b, 'visibility', ('[@%s,exists] show; hide'):format(tok(k)))
  r.click = b
  return r
end

-- ---------- what a row shows ----------
local function health(r)
  local okM, mx = pcall(UnitHealthMax, r.unit)
  local okH, h = pcall(UnitHealth, r.unit)
  if okM then pcall(r.bar.SetMinMaxValues, r.bar, 0, mx) end
  if okH then pcall(r.bar.SetValue, r.bar, h); if db.hp ~= false then pcall(r.hp.SetText, r.hp, h) else r.hp:SetText('') end end
end
local dl, ds = {}, {}
-- a tick: the same DoTs, less damage left. A DoT ending or a new one landing is not a tick.
local function tickLook(r)
  if not r.shown then r.dmg, r.nd = false, false; return end
  local ok = pcall(ns.model.listInto, r.unit, true, dl, ds)
  if not ok then return end
  local sum, n = 0, #dl
  for _, d in ipairs(dl) do if type(d.damage) == 'number' then sum = sum + d.damage end end
  if r.dmg and r.nd == n and sum < r.dmg - .5 and ns.db.tick ~= 'plain' then
    M.flash('bite' .. r.k, .45, function(v) r.bite:SetAlpha(v * .55) end)
  end
  r.dmg, r.nd = sum, n
end
local function killbar(r)
  local KP = ns.parts.platebar
  if KP and KP.paintRow then pcall(KP.paintRow, r.shown and r.unit or nil, r.bar) end
  pcall(tickLook, r)
end
-- the mob's cast line (UNIT_SPELLCAST_* on its token)
local plain = function(v) return v ~= nil and not ns.core.Secret.is(v) end
local function castStep(self)
  local now = GetTime() * 1000
  if self.e and plain(self.e) and now >= self.e then self:SetScript('OnUpdate', nil); self:Hide(); return end
  pcall(self.SetValue, self, self.chan and (self.e and plain(self.e) and self.e - now + self.s or now) or now)
end
local function castLook(r)
  if not r.shown then r.cast:SetScript('OnUpdate', nil); r.cast:Hide(); return end
  local chan = false
  local ok, name, _, _, s, e, _, _, noInt = pcall(UnitCastingInfo, r.unit)
  if not (ok and name) then chan = true; ok, name, _, _, s, e, _, noInt = pcall(UnitChannelInfo, r.unit) end
  if not (ok and name and s and e) then r.cast:SetScript('OnUpdate', nil); r.cast:Hide(); return end
  local stoppable = plain(noInt) and noInt == false
  local c = stoppable and K.castRed or K.castGrey
  r.cast:SetStatusBarColor(c[1], c[2], c[3])
  pcall(r.cast.SetMinMaxValues, r.cast, s, e)
  r.cast.s, r.cast.e, r.cast.chan = s, e, chan
  r.cast:Show(); r.cast:SetScript('OnUpdate', castStep); castStep(r.cast)
end
local function skull(r)
  if ns.db.skull == false then r.skullWin:Hide(); return end
  r.skullWin:Show()
  local ok = pcall(ns.model.listInto, r.unit, true, dl, ds)
  local total = 0
  if ok then for _, d in ipairs(dl) do total = total + (d.damage or 0) end end
  local okH, h = pcall(UnitHealth, r.unit)
  if okH then pcall(r.skullBar.SetMinMaxValues, r.skullBar, 0, h) end
  r.skullBar:SetValue(total)
end
local function threatLook(r, e)
  local lv = db.threat ~= false and e.threat or nil
  if (lv or false) == r.lv then return end
  local rose = (lv or 0) > (r.lv or 0) and lv == 3
  r.lv = lv or false
  if lv then
    local c, top = K.threat[lv], K.threatGlow[lv]
    r.glow:SetVertexColor(c[1], c[2], c[3]); r.ring:SetVertexColor(c[1], c[2], c[3], 1)
    M.breathe('thr' .. r.k, 2.6, top / 3, top, function(v) r.glow:SetAlpha(v) end)
    if rose then M.flash('thrF' .. r.k, 1.1, function(v) r.glow:SetAlpha(math.max(r.glow:GetAlpha(), v)) end) end
  else
    M.stop('thr' .. r.k)
    M.tween('thr' .. r.k, r.glow:GetAlpha(), 0, .4, function(v) r.glow:SetAlpha(v) end)
    r.ring:SetVertexColor(0, 0, 0, .9)
  end
end
local function petLook(r, e)
  if e.petOn then
    pcall(SetPortraitTexture, r.pet, 'pet')   -- your demon's own face
    r.pet:Show(); r.petRim:Show()
  else r.pet:Hide(); r.petRim:Hide() end
end
local function markLook(r, e)
  if e.mark then
    local i = e.mark - 1
    r.mark:SetTexCoord((i % 4) / 4, (i % 4 + 1) / 4, math.floor(i / 4) / 4, (math.floor(i / 4) + 1) / 4); r.mark:Show()
  else r.mark:Hide() end
end

local function fill(r, e)
  pcall(r.name.SetText, r.name, UnitName(r.unit))
  pcall(SetPortraitTexture, r.face, r.unit); pcall(SetPortraitTexture, r.lift, r.unit)
  health(r); skull(r)   -- the kill bar paints on DOTS and when the row appears (not five times a second)
  r.tgt:SetShown(e.target == true)
  threatLook(r, e); petLook(r, e); markLook(r, e)
  local a = (db.range ~= false and e.far) and .5 or 1
  if r.wantA ~= a then r.wantA = a; M.tween('a' .. r.k, r:GetAlpha(), a, .25, function(v) r:SetAlpha(v) end) end
end

-- ---------- places, the backing, the click buttons ----------
local function slotY(s) return -PADY - (s - 1) * ROW end
local function moveTo(r, s, now)
  local y = slotY(s)
  if r.y == y then return end
  local from = r.y or y
  r.y = y
  r:ClearAllPoints(); r:SetPoint('TOPLEFT', header, 'TOPLEFT', 0, from)
  if now then r:ClearAllPoints(); r:SetPoint('TOPLEFT', header, 'TOPLEFT', 0, y); return end
  M.tween('y' .. r.k, from, y, .22, function(v) r:ClearAllPoints(); r:SetPoint('TOPLEFT', header, 'TOPLEFT', 0, v) end, M.ease.out)
end

local shownCount = 0
local function fitBack()
  local low = 0
  for k = 1, TOKENS do local r = rows[k]; if r and r.shown and (slotOf[k] or k) > low then low = slotOf[k] or k end end
  if db.unlocked then low = math.max(low, 3) end
  local h = PADY * 2 + ROW * math.max(low, 1)
  local want = low > 0 and 1 or 0
  M.tween('backH', back:GetHeight(), h, .22, function(v) back:SetHeight(v); if sel then sel:SetHeight(v) end end, M.ease.out)
  if back.want ~= want then back.want = want; M.tween('backA', back:GetAlpha(), want, .25, function(v) back:SetAlpha(v) end) end
end

local function placeClicks()
  if not (geo and holder and header) or InCombatLockdown() then return end
  pcall(function()
    local p, _, rp, x, y = header:GetPoint(1)
    local sc = header:GetScale()
    geo:SetScale(sc); holder:SetScale(sc)
    geo:ClearAllPoints(); geo:SetPoint(p or 'TOPRIGHT', UIParent, rp or 'TOPRIGHT', x or 0, y or 0)
    geo:SetSize(width(), PADY * 2 + ROW * TOKENS)
    for k = 1, TOKENS do
      local r = rows[k]
      if r and r.click then
        r.click:ClearAllPoints(); r.click:SetPoint('TOPLEFT', geo, 'TOPLEFT', 0, slotY(slotOf[k] or k)); r.click:SetSize(width(), ROW)
      end
    end
  end)
end

-- places: between fights and at the pull, the DPS order (missing a DoT first, then the soonest ending); the rest of
-- the tokens after, likely joiners (hostile) before idle neutral mobs. In a fight nothing moves (the buttons are locked).
local function pack(instant)
  if InCombatLockdown() and fighting then return end
  local n, done = 0, {}
  for _, e in ipairs(RO.order(db.sort ~= 'soonest')) do n = n + 1; slotOf[e.k] = n; done[e.k] = true end
  local function hostile(k)
    local ok, re = pcall(UnitReaction, tok(k), 'player')
    return ns.plates.live[tok(k)] and ok and type(re) == 'number' and re <= 3
  end
  for _, pass in ipairs({ hostile, function() return true end }) do
    for k = 1, TOKENS do if not done[k] and pass(k) then n = n + 1; slotOf[k] = n; done[k] = true end end
  end
  for k = 1, TOKENS do if rows[k] then moveTo(rows[k], slotOf[k], instant) end end
  placeClicks(); fitBack()
end

local function setShown(r, on)
  if r.shown == on then return end
  r.shown = on
  if on then
    r:Show(); r.wantA = false; r.dmg, r.nd = false, false; killbar(r); pcall(castLook, r)
    M.tween('in' .. r.k, 12, 0, .22, function(v) r:SetPoint('TOPLEFT', header, 'TOPLEFT', v, r.y or slotY(slotOf[r.k] or r.k)) end, M.ease.out)
  else
    M.stop('thr' .. r.k); r.lv = false
    M.tween('a' .. r.k, r:GetAlpha(), 0, .2, function(v) r:SetAlpha(v) end, nil, function() if not r.shown then r:Hide() end end)
    r.wantA = 0
    killbar(r); pcall(castLook, r)
  end
end

local function update()
  if not header then return end
  for k = 1, TOKENS do
    local r, e = rows[k], RO.entries[k]
    if r and e then
      setShown(r, e.on == true)
      if e.on then local ok, err = pcall(fill, r, e); if not ok then ns.error('list row: ' .. tostring(err)) end end
    end
  end
  if not fighting then pack() else fitBack() end
end
L.update = update

-- ---------- moving and sizing: Blizzard's Edit Mode look ----------
local function savePos() local p, _, rp, x, y = header:GetPoint(1); db.point, db.rel, db.x, db.y = p, rp, x, y end
local function buildEditMode()
  sel = CreateFrame('Frame', nil, header)
  sel:SetPoint('TOPLEFT', header, 'TOPLEFT', -6, 2); sel:SetWidth(width() + 12); sel:SetHeight(PADY * 2 + ROW * 3)
  sel:SetFrameLevel(header:GetFrameLevel() + 30); sel:EnableMouse(true); sel:Hide()
  local f = sel:CreateTexture(nil, 'BACKGROUND'); f:SetAllPoints(); f:SetColorTexture(.12, .43, .86, .16)
  local edges = { { 'TOPLEFT', 'TOPRIGHT', 0, 2 }, { 'BOTTOMLEFT', 'BOTTOMRIGHT', 0, 2 }, { 'TOPLEFT', 'BOTTOMLEFT', 2, 0 }, { 'TOPRIGHT', 'BOTTOMRIGHT', 2, 0 } }
  for _, e in ipairs(edges) do
    local l = sel:CreateTexture(nil, 'BORDER'); l:SetColorTexture(.43, .71, 1, .95); l:SetPoint(e[1]); l:SetPoint(e[2])
    if e[3] > 0 then l:SetWidth(e[3]) else l:SetHeight(e[4]) end
  end
  local tag = sel:CreateFontString(nil, 'OVERLAY'); tag:SetFont(K.font, 12, ''); tag:SetText('Mob List'); tag:SetPoint('BOTTOM', sel, 'TOP', 0, 2)
  sel:SetScript('OnMouseDown', function(_, b) if b == 'LeftButton' and not InCombatLockdown() then header:StartMoving() end end)
  sel:SetScript('OnMouseUp', function() header:StopMovingOrSizing(); savePos(); placeClicks() end)
  grip = CreateFrame('Button', nil, sel); grip:SetSize(16, 16); grip:SetPoint('BOTTOMRIGHT', sel, 'BOTTOMRIGHT', -2, 2)
  grip:SetNormalTexture(K.sizeGrip); grip:SetHighlightTexture(K.sizeGripHi); grip:SetPushedTexture(K.sizeGripDown)
  local from, start = 0, 1
  grip:SetScript('OnMouseDown', function()
    from, start = GetCursorPosition(), header:GetScale()
    grip:SetScript('OnUpdate', function()
      local w = width() * header:GetEffectiveScale()
      header:SetScale(math.max(.6, math.min(1.8, start * (1 + (GetCursorPosition() - from) / w))))
    end)
  end)
  grip:SetScript('OnMouseUp', function() grip:SetScript('OnUpdate', nil); db.scale = math.floor(header:GetScale() * 100 + .5); savePos(); placeClicks() end)
end

local function visible() if header then header:SetShown(fighting or db.unlocked == true) end end
local function unlock(on)
  if InCombatLockdown() then say('the list can be moved after this fight.'); return end
  db.unlocked = on
  if on and not sel then buildEditMode() end
  if sel then sel:SetShown(on) end
  visible(); fitBack()
end

-- ---------- seats: one row of your rings per token, built one per frame out of combat ----------
local function placeSeats(r)
  local p = r.pair; if not p then return end
  local sw = seatWidth(); local k = RING / R.S
  p.anchor:SetScale(k); p.anchor:ClearAllPoints(); p.anchor:SetSize(sw / k, 1)
  p.anchor:SetPoint('BOTTOM', r, 'BOTTOMLEFT', (PADX + PORT + GAPP + BAR + GAPR + sw / 2) / k, ((ROW - RING) / 2) / k)
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
        if r.pair then placeSeats(r); r.pair.bar:SetAllPoints(r.bar); r.pair.ring:SetUnit(r.unit); r.pair.main:SetUnit(r.unit); if r.pair.halo then r.pair.halo:SetUnit(r.unit) end end
        return
      end
    end
    self:SetScript('OnUpdate', nil)
  end)
end
local function relayout()
  if InCombatLockdown() or not header then return end
  header:SetSize(width(), PADY * 2 + ROW * (db.rows or 8))
  back:SetWidth(width() + 48)
  for k = 1, TOKENS do local r = rows[k]; if r then r:SetWidth(width()); placeSeats(r) end end
  if sel then sel:SetWidth(width() + 12) end
  pack(true)
end

local function start()
  if not (R.db and RO and M and K and G and RegisterStateDriver) then return end
  ns.db.list = ns.db.list or {}
  db = ns.db.list
  if db.on == false then return end
  db.rows = math.max(4, math.min(TOKENS, tonumber(db.rows) or 8))
  header = CreateFrame('Frame', 'OmaDoomedList', UIParent)
  header:SetClampedToScreen(true); header:SetMovable(true); header:SetScale((db.scale or 100) / 100)
  header:SetPoint(db.point or 'TOPRIGHT', UIParent, db.rel or 'TOPRIGHT', db.x or -40, db.y or -330)
  geo = CreateFrame('Frame', nil, UIParent); geo:SetSize(1, 1)
  holder = CreateFrame('Frame', 'OmaDoomedListClicks', UIParent, 'SecureHandlerStateTemplate')
  holder:SetAllPoints(UIParent); holder:SetFrameStrata('HIGH')
  RegisterStateDriver(holder, 'visibility', '[combat] show; hide')
  -- the one soft backing (no box, no edges): wide feathered shape, 9-slice so its soft ends keep their shape
  back = header:CreateTexture(nil, 'BACKGROUND', nil, -8); back:SetTexture(K.listBack, nil, nil, 'TRILINEAR')
  if back.SetTextureSliceMargins then pcall(back.SetTextureSliceMargins, back, 48, 48, 48, 48) end
  back:SetVertexColor(0, 0, 0, .62); back:SetPoint('TOPLEFT', header, 'TOPLEFT', -24, 10)
  back:SetWidth(width() + 48); back:SetHeight(1); back:SetAlpha(0)
  for k = 1, TOKENS do rows[k] = newRow(k); rows[k]:SetFrameLevel(header:GetFrameLevel() + 2) end
  relayout()
  unlock(db.unlocked == true)
  buildPairs()
  -- the scheduler drives the list: refreshed with the roster, and frozen while your mouse is over it
  local function mouseOver() return header:IsMouseOver() or (holder and holder:IsShown() and MouseIsOver and MouseIsOver(geo)) end
  ns.sched.add('moblist', .2, update, function() return fighting == false and mouseOver() end)
  ns.bus:On('ROSTER_DONE', function() ns.sched.mark('moblist') end)
  ns.bus:On('SETTING', function(key, store)
    if store ~= 'list' then return end
    if key == 'scale' and not InCombatLockdown() then header:SetScale((db.scale or 100) / 100); placeClicks()
    else relayout(); update() end
  end)
  ns.bus:On('DOTS', function() for k = 1, TOKENS do local r = rows[k]; if r and r.shown then killbar(r) end end end)
  local ev = CreateFrame('Frame')
  local CASTS = { UNIT_SPELLCAST_START = 1, UNIT_SPELLCAST_STOP = 1, UNIT_SPELLCAST_FAILED = 1, UNIT_SPELLCAST_INTERRUPTED = 1,
    UNIT_SPELLCAST_DELAYED = 1, UNIT_SPELLCAST_CHANNEL_START = 1, UNIT_SPELLCAST_CHANNEL_STOP = 1, UNIT_SPELLCAST_CHANNEL_UPDATE = 1,
    UNIT_SPELLCAST_INTERRUPTIBLE = 1, UNIT_SPELLCAST_NOT_INTERRUPTIBLE = 1 }
  for _, e in ipairs({ 'PLAYER_REGEN_DISABLED', 'PLAYER_REGEN_ENABLED', 'SPELLS_CHANGED', 'UNIT_HEALTH' }) do pcall(ev.RegisterEvent, ev, e) end
  for e in pairs(CASTS) do pcall(ev.RegisterEvent, ev, e) end
  ev:SetScript('OnEvent', function(_, e, unit)
    if e == 'PLAYER_REGEN_DISABLED' then
      RO.refreshAll(); pack(true)        -- the places for this fight, set before Blizzard locks the buttons
      fighting = true; visible(); update()
    elseif e == 'PLAYER_REGEN_ENABLED' then
      fighting = false; visible(); relayout(); buildPairs(); update()
    elseif e == 'SPELLS_CHANGED' then relayout()
    elseif e == 'UNIT_HEALTH' then
      local k = type(unit) == 'string' and tonumber(unit:match('^nameplate(%d+)$'))
      if k and rows[k] and rows[k].shown then pcall(health, rows[k]) end
    elseif CASTS[e] then
      local k = type(unit) == 'string' and tonumber(unit:match('^nameplate(%d+)$'))
      if k and rows[k] and rows[k].shown then pcall(castLook, rows[k]) end
    end
  end)
  L.header = header
  fighting = InCombatLockdown() and true or false; visible()
  RO.refreshAll(); update()
end
ns.starts[#ns.starts + 1] = start

function L.slash(msg)
  local cmd, arg = (msg or ''):match('^(%S*)%s*(.-)$'); cmd = (cmd or ''):lower()
  if not header then say('the mob list is off (it needs the rings on).'); return end
  if cmd == 'unlock' then unlock(true); say('drag the list, and size it with the corner grip. /omadoomed list lock when done.')
  elseif cmd == 'lock' then unlock(false); say('list locked: it shows in fights.')
  elseif cmd == 'rows' then
    local n = tonumber(arg); if n then db.rows = math.max(4, math.min(TOKENS, n)); relayout(); say(('the list shows up to %d mobs.'):format(db.rows)) end
  elseif cmd == 'reset' then
    if InCombatLockdown() then return end
    db.point, db.rel, db.x, db.y, db.scale = nil, nil, nil, nil, nil
    header:ClearAllPoints(); header:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -40, -330); header:SetScale(1); placeClicks(); say('list back in its first place.')
  else
    local n = 0; for k = 1, TOKENS do if rows[k] and rows[k].shown then n = n + 1 end end
    say(('mob list: %d shown of up to %d. /omadoomed list unlock | lock | rows 4-16 | reset'):format(n, db.rows))
  end
end
function L.unlock(on) unlock(on) end
function L.relayout() relayout(); update() end
L.rows = rows
L.slotOf = slotOf
