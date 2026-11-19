-- OmaDoomed, the mob list (sheet 83, approved 2026-11-16 "build engines"; one frame, rows like your nameplates).
-- Every enemy in your fight, one row each: its portrait (threat rim, your demon's mark, its raid mark, OmaDoomed's
-- skull when your DoTs will finish it), its name and health in Blizzard's own nameplate bar, your DoTs in their seats,
-- and a shield or anti-magic buff while it has one. One soft dark backing behind the whole list, no boxes.
-- Built on the engines: Roster (who and what), Scheduler (when), Motion (how things move), Layout (sizes), Skin (art).
--
-- Clicking (measured 2026-11-16, rechecked on 1.60.1.70959 on 2026-11-17): Forever's engine refuses every add-on route
-- that names a nameplateN token (target, spell, '/target [@mouseover]', and hovering such a button sets no mouseover).
-- So the rows are display only. Hover-cast happens on the real nameplate (Mouseover Cast). Full write-up:
-- reports/OmaDoomed click and hover casting, deep dive 2026-11-17.md. Rows sort: missing a DoT first, then the
-- soonest ending.
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
local CASTH, CASTGAP = 3, 2   -- the mob's cast line under its bar: 3 px, 2 px under the bar's frame
local BUFF = 18        -- sheet 108 v2: the shield/anti-magic badge sits on the portrait's top-right corner
local FEATHER = 18     -- how far the backing reaches past the rows, above and below
L.RH = ROW
local function plainV(v) return v ~= nil and not (ns.core and ns.core.Secret and ns.core.Secret.is(v)) end

local db
local testOff    -- the test list (below)
local header, holder, geo, back, backF, sel, grip
local rows, slotOf, parked = {}, {}, {}
local fighting = false
local function say(m) print('|cffb48cffOmaDoomed:|r ' .. m) end
local function tok(k) return 'nameplate' .. k end

local function seatWidth()
  local _, n = R.seatSpots()
  return n * RING + (n - 1) * RINGGAP
end
-- sheet 108 v2: exactly the Details meter's width (Layout.LIST.width). The health bar takes what the seats leave, so
-- a new seat (Siphon Life at 30) narrows the bar instead of widening the list. Floor 96 px (2026-11-18, was 110: the
-- elite dragon's room, +16 px, leaves 348 - (12 + 40 + 22 + 6 + 5 x 30 + 4 x 4) = 102 px with five seats).
local BAR_MIN = 96
local function barW() return math.max(BAR_MIN, (G.width or 0) * u - (2 * PADX + PORT + GAPP + GAPR + seatWidth())) end
local function width() return 2 * PADX + PORT + GAPP + barW() + GAPR + seatWidth() end
L.barW = barW
L.width = width

-- ---------- a row ----------
local function texCoord(t, c) t:SetTexCoord(c[1], c[2], c[3], c[4]) end

local function newRow(k)
  local r = CreateFrame('Frame', nil, header)
  r.k, r.unit, r.shown, r.pair = k, tok(k), false, false
  r.y, r.lv, r.wantA, r.fk, r.lastBite, r.quiet, r.veilWin, r.markOn, r.isTgt = false, false, false, false, false, false, false, false, false   -- set, never nil (a frame answers unknown keys)
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
  -- sheet 86 ("portraits are great"): the game's own portrait, clean (the additive lift over it washed it out)
  r.lift = r:CreateTexture(nil, 'ARTWORK', nil, 1); r.lift:SetAllPoints(r.face); r.lift:SetBlendMode('ADD'); r.lift:SetAlpha(.18); r.lift:AddMaskTexture(m)   -- a light touch (0.4 washed it out)
  r.ring = r:CreateTexture(nil, 'ARTWORK', nil, 3); r.ring:SetTexture(K.portraitRing, nil, nil, 'TRILINEAR')
  r.ring:SetSize(PORT + 6, PORT + 6); r.ring:SetPoint('CENTER', r.face, 'CENTER'); r.ring:SetVertexColor(K.rim[1], K.rim[2], K.rim[3], K.rim[4])
  -- sheet 118 v6 (Joshua 2026-11-18: "i like the elite frame"): elite and rare get the game's own small nameplate
  -- dragon (gold, silver) at the left end of the health bar, unmirrored, exactly where the nameplate puts it. Placed
  -- with the bar (below); the numbers are there.
  -- and the mob's level in a small bronze-rimmed disc on the portrait's lower left, like the target frame's
  r.lvlBg = r:CreateTexture(nil, 'OVERLAY', nil, 4); r.lvlBg:SetTexture(K.ART .. 'rings\\mask_disc', nil, nil, 'TRILINEAR')
  r.lvlBg:SetVertexColor(.07, .05, .02, 1); r.lvlBg:SetSize(16, 16); r.lvlBg:SetPoint('CENTER', r.face, 'BOTTOMLEFT', 3, 3)
  r.lvlRim = r:CreateTexture(nil, 'OVERLAY', nil, 5); r.lvlRim:SetTexture(K.portraitRing, nil, nil, 'TRILINEAR')
  r.lvlRim:SetVertexColor(K.rim[1], K.rim[2], K.rim[3], 1); r.lvlRim:SetSize(19, 19); r.lvlRim:SetPoint('CENTER', r.lvlBg, 'CENTER')
  r.lvl = r:CreateFontString(nil, 'OVERLAY'); r.lvl:SetFont(K.font, 9, 'OUTLINE'); r.lvl:SetPoint('CENTER', r.lvlBg, 'CENTER', 0, 0)
  r.lvl:SetTextColor(K.nameGold[1], K.nameGold[2], K.nameGold[3])
  -- sheet 119 A + B (Joshua 2026-11-19: "A + B"): your target's row gets a gold frame round the whole row with a
  -- breathing glow, and a gold arrow left of its face nudging in and out. Art and numbers: Art\make_target_art.py.
  -- Frame and glow textures cover row-local x -11 .. 359, y -10 .. 54 (370 x 64 of a 512 x 64 texture) for a 348 x 44
  -- row, so they sit at TOPLEFT (-11, +10) / BOTTOMRIGHT (+11, -10) and are 1:1 at the meter's width (a wider list
  -- stretches only the straight edges' share). Line: rounded 1,1 .. 347,43, radius 8, 2 px. Below the level disc and
  -- the demon mark (OVERLAY 4/5 and 2/3), as on the sheet.
  r.tgtGlow = r:CreateTexture(nil, 'OVERLAY', nil, 0); r.tgtGlow:SetTexture(K.tgtGlow, nil, nil, 'TRILINEAR')
  r.tgtFrame = r:CreateTexture(nil, 'OVERLAY', nil, 1); r.tgtFrame:SetTexture(K.tgtFrame, nil, nil, 'TRILINEAR')
  for _, t in ipairs({ r.tgtGlow, r.tgtFrame }) do
    t:SetTexCoord(0, 370 / 512, 0, 1); t:SetPoint('TOPLEFT', r, 'TOPLEFT', -11, 10); t:SetPoint('BOTTOMRIGHT', r, 'BOTTOMRIGHT', 11, -10)
    t:SetVertexColor(K.nameGold[1], K.nameGold[2], K.nameGold[3]); t:Hide()
  end
  -- the arrow: 32 x 32 covering x -23 .. 9, y 6 .. 38; its tip at (2, 22), the row's middle, 2.6 px short of the
  -- portrait ring (26 - 21.4). It nudges 6 px left and back every 1.1 s (the sheet's 1.6% of 372 px).
  r.tgtArrow = r:CreateTexture(nil, 'OVERLAY', nil, 6); r.tgtArrow:SetTexture(K.tgtArrow, nil, nil, 'TRILINEAR')
  r.tgtArrow:SetSize(32, 32); r.tgtArrow:SetPoint('TOPLEFT', r, 'TOPLEFT', -23, -6); r.tgtArrow:Hide()
  -- your demon's mark (its own icon) on the portrait's lower right; the mob's raid mark at the end of its name line
  r.pet = r:CreateTexture(nil, 'OVERLAY', nil, 2); r.pet:SetSize(20, 20); r.pet:SetPoint('CENTER', r.face, 'BOTTOMRIGHT', -1, 1); r.pet:Hide()
  local pm = r:CreateMaskTexture(); pm:SetTexture(K.ART .. 'rings\\mask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE', 'TRILINEAR'); pm:SetAllPoints(r.pet); r.pet:AddMaskTexture(pm)
  r.petRim = r:CreateTexture(nil, 'OVERLAY', nil, 3); r.petRim:SetTexture(K.portraitRing, nil, nil, 'TRILINEAR'); r.petRim:SetSize(25, 25)
  r.petRim:SetPoint('CENTER', r.pet, 'CENTER'); r.petRim:SetVertexColor(.89, .82, 1); r.petRim:Hide()   -- a bright rim so it reads on the dark row
  r.mark = r:CreateTexture(nil, 'OVERLAY', nil, 2); r.mark:SetSize(13, 13)
  r.mark:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcons'); r.mark:Hide()   -- placed with the bar (below)
  -- OmaDoomed's skull on the portrait's top edge (the target frame's trick: a long bar 0..health filled with your
  -- DoTs' damage; the skull rides its end and reaches the little window only when the damage covers the health)
  local SW, SH = PORT * .78, PORT * .78 * 54 / 78
  r.skullWin = CreateFrame('Frame', nil, r); r.skullWin:SetClipsChildren(true)
  -- on the portrait's top rim, as the big skull sits on the target frame (2026-11-16: "On the portrait")
  -- 2026-11-17 (09:58 screenshot): it covered half the portrait; now it only sits on the rim (12% overlap)
  r.skullWin:SetSize(SW, SH); r.skullWin:SetPoint('BOTTOM', r.face, 'TOP', 0, -PORT * .12); r.skullWin:SetFrameLevel(r:GetFrameLevel() + 6)
  r.skullBar = CreateFrame('StatusBar', nil, r.skullWin); r.skullBar:SetSize(SW * 400, SH); r.skullBar:SetPoint('RIGHT', r.skullWin, 'RIGHT')
  r.skullBar:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8'); r.skullBar:SetStatusBarColor(0, 0, 0, 0)
  r.skullBar:SetMinMaxValues(0, 1); r.skullBar:SetValue(0)
  r.skull = r.skullBar:CreateTexture(nil, 'OVERLAY'); r.skull:SetTexture(K.mark, nil, nil, 'TRILINEAR'); r.skull:SetTexCoord(0, 78 / 128, 0, 54 / 64)
  r.skull:SetSize(SW, SH); r.skull:SetPoint('RIGHT', r.skullBar:GetStatusBarTexture(), 'RIGHT')
  -- 'Fade mobs your DoTs will finish' (sheet 90 A, 2026-11-17 "yes build it as a setting"): the same trick as the
  -- skull. A mob's health is hidden in a fight, so the add-on can't ask "doomed?". A soft dark veil rides the end of a
  -- long bar filled with your DoTs' damage over the health; only when the damage covers the health does it reach the
  -- row's window and lie over the bar and rings. The game eases the bar (interpolated value), so it sweeps in softly.
  -- The portrait (threat rim, threat glow) and the name stay outside it: they never fade.
  local vx = PADX + PORT + GAPP - 4
  r.veilWin = CreateFrame('Frame', nil, r); r.veilWin:SetClipsChildren(true)
  r.veilWin:SetPoint('TOPLEFT', r, 'TOPLEFT', vx, -(ROW / 2 - (NAME + 3 + BARH) / 2 + NAME + 1))
  r.veilWin:SetPoint('BOTTOMRIGHT', r, 'BOTTOMRIGHT', 0, 2)
  r.veilWin:SetFrameLevel(r:GetFrameLevel() + 8); r.veilWin:Hide()
  local VW = width() - vx
  r.veilBar = CreateFrame('StatusBar', nil, r.veilWin); r.veilBar:SetSize(VW * 400, ROW); r.veilBar:SetPoint('RIGHT', r.veilWin, 'RIGHT')
  r.veilBar:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8'); r.veilBar:SetStatusBarColor(0, 0, 0, 0)
  r.veilBar:SetMinMaxValues(0, 1); r.veilBar:SetValue(0)
  r.veil = r.veilBar:CreateTexture(nil, 'OVERLAY'); r.veil:SetTexture(K.rowGlow, nil, nil, 'TRILINEAR'); r.veil:SetVertexColor(0, 0, 0, .62)
  r.veil:SetSize(VW + 20, ROW); r.veil:SetPoint('RIGHT', r.veilBar:GetStatusBarTexture(), 'RIGHT', 10, 0)
  -- name and health, built like the nameplate: Blizzard's bar frame, status bar art, white name
  local tx = PADX + PORT + GAPP
  -- 2026-11-19: the block centred on the row (and on the portrait's middle) is name + 3 + framed bar + 2 + the 3 px cast
  -- line, 34 px: name from y 5, frame 20..34, your target's rim 19..35, cast line 36..39, then 2 px to the gold target
  -- frame's line (41..43). Before, the block left the cast line out (29 px): frame 22.5..36.5 and the line 36.5..39.5
  -- lay on the frame's edge and 1 px under the target rim.
  local blk = NAME + 3 + BARH + CASTGAP + CASTH
  r.bar = CreateFrame('StatusBar', nil, r)
  r.bar:SetSize(barW() - 4, BARH - 6); r.bar:SetPoint('TOPLEFT', r, 'TOPLEFT', tx + 2, -(ROW / 2 - blk / 2 + NAME + 3 + 3))
  r.bar:SetStatusBarTexture(K.statusbar); r.bar:SetStatusBarColor(K.healthRed[1], K.healthRed[2], K.healthRed[3])
  r.bar:SetMinMaxValues(0, 1); r.bar:SetValue(1)
  -- sheet 108 v2 ("warm glow per each threat level ON THE BAR it belongs to"): the threat swell sits around the bar
  r.glow:ClearAllPoints(); r.glow:SetPoint('TOPLEFT', r.bar, 'TOPLEFT', -26, 16); r.glow:SetPoint('BOTTOMRIGHT', r.bar, 'BOTTOMRIGHT', 26, -16)
  r.mark:SetPoint('BOTTOMRIGHT', r.bar, 'TOPRIGHT', 1, 4)
  local empty = r.bar:CreateTexture(nil, 'BACKGROUND', nil, -1); empty:SetPoint('TOPLEFT', -1, 1); empty:SetPoint('BOTTOMRIGHT', 1, -1); empty:SetColorTexture(K.empty[1], K.empty[2], K.empty[3], 1)
  r.frameArt = r.bar:CreateTexture(nil, 'OVERLAY', nil, 2); r.frameArt:SetTexture(K.plateTex, nil, nil, 'TRILINEAR'); texCoord(r.frameArt, K.plateFrame)
  r.frameArt:SetPoint('TOPLEFT', r.bar, 'TOPLEFT', -2, 3); r.frameArt:SetPoint('BOTTOMRIGHT', r.bar, 'BOTTOMRIGHT', 2, -3)
  r.tgt = r.bar:CreateTexture(nil, 'OVERLAY', nil, 3); r.tgt:SetTexture(K.plateTex, nil, nil, 'TRILINEAR'); texCoord(r.tgt, K.plateTarget)
  r.tgt:SetPoint('TOPLEFT', r.bar, 'TOPLEFT', -4, 4); r.tgt:SetPoint('BOTTOMRIGHT', r.bar, 'BOTTOMRIGHT', 4, -4); r.tgt:Hide()
  -- the elite dragon, by measurement (2026-11-19, his 10:5x screenshot of Blackfathom Myrmidon, 1:1). Art: the
  -- nameplate's own 'nameplates-icon-elite-gold' (silver for rares). Drawn in a 16 x 14 box the atlas's art showed only
  -- ~11 x 10 px (x 99.5..>110, y 72.5..82.5 of the box's 98..114 x 70.5..84.5): the atlas has clear margins, 1.5 of
  -- 16 left, 2 of 14 top and bottom, so the dragon was 71% of the framed bar's 14 px, where sheet 118 v6 (and the
  -- nameplate) has it as tall as the frame. And it lay on the row, under the bar's frame, so your target's 4 px rim
  -- hid its tail. Now: box x 1.4 = 22.4 x 19.6, so the art is 14 px tall (the frame's height), its middle on the
  -- bar's middle; drawn on the bar above the rim (OVERLAY 4). Its art is ~15.8 px wide (sheet 118's 1.125 : 1), its
  -- tail ~1 px over the frame's left end: box right at frame left + 5. Art spans x ~53.7..69.5 local, y 20..34.
  -- Clearance (ring and mark as before, now the block sits 2.5 px higher): portrait ring (26,22, r 21.4) reaches
  -- x 47.4 at the dragon's top (y 20..24), 6 px clear; your demon's mark (45,41, r 11.6) reaches x 51 where the
  -- dragon's lowest left claw is (y ~31, x ~55.9), 5 px clear.
  r.drag = r.bar:CreateTexture(nil, 'OVERLAY', nil, 4); r.drag:Hide()
  r.drag:SetSize(22.4, 19.6); r.drag:SetPoint('RIGHT', r.frameArt, 'LEFT', 5, 0)
  r.hp = r.bar:CreateFontString(nil, 'OVERLAY', nil, 7); r.hp:SetFont(K.font, 12, 'OUTLINE'); r.hp:SetPoint('CENTER', r.bar, 'CENTER', 0, 0)
  -- a tick: the DoT pieces flash (a soft white light over the bar) as they shrink (sheet 83, row 1)
  r.bite = r.bar:CreateTexture(nil, 'OVERLAY', nil, 1); r.bite:SetTexture(K.statusbar); r.bite:SetAllPoints(r.bar)
  r.bite:SetVertexColor(1, .93, .8); r.bite:SetBlendMode('ADD'); r.bite:SetAlpha(0)
  r.dmg, r.nd = false, false
  -- the mob's cast: a thin line under its bar, red when you can interrupt it (Spell Lock), grey when you can't.
  -- 2026-11-19: as wide as the bar's frame (x 68 .. 68 + barW, it was the inner bar's barW - 4 from x 70, so it
  -- started 2 px in and stopped 2 px short), 2 px under the frame (1 px clear of your target's rim), drawn above the bar
  r.cast = CreateFrame('StatusBar', nil, r); r.cast:SetHeight(CASTH)
  r.cast:SetPoint('TOPLEFT', r.frameArt, 'BOTTOMLEFT', 0, -CASTGAP); r.cast:SetPoint('TOPRIGHT', r.frameArt, 'BOTTOMRIGHT', 0, -CASTGAP)
  r.cast:SetFrameLevel(r.bar:GetFrameLevel() + 1)
  r.cast:SetStatusBarTexture(K.statusbar); r.cast:SetMinMaxValues(0, 1); r.cast:SetValue(0); r.cast:Hide()
  local cb = r.cast:CreateTexture(nil, 'BACKGROUND'); cb:SetAllPoints(); cb:SetColorTexture(0, 0, 0, .7)
  r.name = r:CreateFontString(nil, 'OVERLAY'); r.name:SetFont(K.font, NAME, 'OUTLINE')
  r.name:SetTextColor(K.nameGold[1], K.nameGold[2], K.nameGold[3]); r.name:SetShadowColor(0, 0, 0, 1); r.name:SetShadowOffset(1, -1)
  r.name:SetPoint('BOTTOMLEFT', r.bar, 'TOPLEFT', -1, 5); r.name:SetWidth(barW() + 2); r.name:SetJustifyH('LEFT'); pcall(r.name.SetWordWrap, r.name, false)
  -- shields and anti-magic: only while the mob has one (HELPFUL|IMPORTANT, what the game itself flags)
  local ok, buffs = pcall(CreateFrame, 'AuraContainer', nil, r, 'CustomAuraContainerTemplate')
  if ok and buffs then
    pcall(buffs.SetEditModePreviewEnabled, buffs, false)
    buffs:SetFlowLayoutAnchorPoint('LEFT'); buffs:SetFlowLayoutGrowthDirection(1, 1); buffs:SetFlowLayoutMaximumLineSize(BUFF * 2.5)
    local okG = pcall(buffs.AddAuraGroup, buffs, 'buffs', 'HELPFUL|IMPORTANT|INCLUDE_NAME_PLATE_ONLY', { initializeFrame = R.buffButton(BUFF), maxFrameCount = 2, layout = { groupSpacing = 4 } })
    if okG then r.buffs = buffs; buffs:SetPoint('LEFT', r.face, 'TOPRIGHT', -BUFF * .6, -2); buffs:SetFrameLevel(r:GetFrameLevel() + 7); buffs:SetUnit(r.unit) end
  end
  -- Display only (2026-11-16, measured: Forever refuses every add-on route to a mob through its nameplate token:
  -- click to target, cast at it, mouseover macro, hover-as-mouseover; DECISIONS.md). The row itself takes the mouse
  -- just for its hover light and the mob's tooltip. Hover-cast on the mob or its real nameplate (Mouseover Cast).
  r:EnableMouse(true)
  r:SetScript('OnEnter', function(self)
    M.tween('hov' .. k, r.hover:GetAlpha(), .22, .12, function(v) r.hover:SetAlpha(v) end)
    if GameTooltip then pcall(GameTooltip_SetDefaultAnchor, GameTooltip, self); pcall(GameTooltip.SetUnit, GameTooltip, tok(k)); pcall(GameTooltip.Show, GameTooltip) end
  end)
  r:SetScript('OnLeave', function()
    M.tween('hov' .. k, r.hover:GetAlpha(), 0, .25, function(v) r.hover:SetAlpha(v) end)
    if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
  end)
  r.click = false
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
  if r.dmg and r.nd == n and sum < r.dmg - .5 and ns.db.tick ~= 'plain' and not r.quiet then
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
  if db.casts == false then r.cast:SetScript('OnUpdate', nil); r.cast:Hide(); return end   -- 'Cast lines' off
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
-- the skull (2026-11-16): your DoTs will finish this mob AND it still has an empty seat, i.e. "don't spend a GCD
-- filling it". A mob with every seat full needs nothing from you, so it gets no skull (at level 19 nearly every
-- DoTed mob would carry one, which told him nothing).
local EASE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local function setEased(bar, v) if not (EASE and pcall(bar.SetValue, bar, v, EASE)) then bar:SetValue(v) end end
local function skull(r, e)
  local ok = pcall(ns.model.listInto, r.unit, true, dl, ds)
  local total = 0
  if ok then for _, d in ipairs(dl) do total = total + (d.damage or 0) end end
  local okH, h = pcall(UnitHealth, r.unit)
  -- the fade: never on your target (Tab always lands on a bright row), never while the setting is off
  if db.fadeDone ~= false and not (e and e.target) and total > 0 then
    r.veilWin:Show()
    if okH then pcall(r.veilBar.SetMinMaxValues, r.veilBar, 0, h) end
    setEased(r.veilBar, total)
  else r.veilWin:Hide() end
  if ns.db.skull == false or not (e and (e.missing or 0) > 0) then r.skullWin:Hide(); return end
  r.skullWin:Show()
  if okH then pcall(r.skullBar.SetMinMaxValues, r.skullBar, 0, h) end
  r.skullBar:SetValue(total)
end
local function threatLook(r, e)
  local lv = db.threat ~= false and not r.quiet and e.threat or nil
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
    r.ring:SetVertexColor(K.rim[1], K.rim[2], K.rim[3], K.rim[4])
  end
end
-- sheet 108 v2 (dragon moved by sheet 118 v6): elite gold dragon and gold bar trim, rare silver, rare elite silver with a gold trim; level on the disc
local CLASS_LOOK = {
  elite = { tex = 'elite', trim = { 1, .84, .38 }, name = { 1, .86, .3 } },
  worldboss = { tex = 'elite', trim = { 1, .84, .38 }, name = { 1, .86, .3 } },
  rareelite = { tex = 'rareElite', trim = { 1, .9, .55 }, name = { .92, .95, 1 } },
  rare = { tex = 'rareElite', trim = { .82, .88, 1 }, name = { .92, .95, 1 } },
}
local function classLook(r, cls)   -- cls: the test list's pretend classification
  local c = cls
  if not c then local ok, v = pcall(UnitClassification, r.unit); c = ok and plainV(v) and v or nil end
  local look = c and CLASS_LOOK[c] or nil
  if look then
    if r.drag.tex ~= look.tex then
      r.drag.tex = look.tex
      local at = K[look.tex .. 'Atlas']
      local ok = at and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(at) ~= nil
      if ok then r.drag:SetTexCoord(0, 1, 0, 1); r.drag:SetAtlas(at, false)
      else r.drag:SetTexture(K[look.tex]); r.drag:SetTexCoord(0, 37 / 64, 0, 28 / 32) end   -- the tooltip icon: 37 x 28 of 64 x 32
    end
    r.drag:Show(); r.frameArt:SetVertexColor(look.trim[1], look.trim[2], look.trim[3]); r.name:SetTextColor(look.name[1], look.name[2], look.name[3])
  else
    r.drag:Hide(); r.frameArt:SetVertexColor(1, 1, 1); r.name:SetTextColor(K.nameGold[1], K.nameGold[2], K.nameGold[3])
  end
end
local function levelLook(r)
  local ok, lv = pcall(UnitLevel, r.unit)
  if ok and plainV(lv) and type(lv) == 'number' then r.lvl:SetText(lv < 0 and '??' or tostring(lv)) else r.lvl:SetText('') end
end
-- your demon's own spell icon (sheet 86, "demon mark is great"): crisp game art, not a 20 px face
local DEMON_ICON = {
  Imp = 'Interface\\Icons\\Spell_Shadow_SummonImp', Voidwalker = 'Interface\\Icons\\Spell_Shadow_SummonVoidWalker',
  Succubus = 'Interface\\Icons\\Spell_Shadow_SummonSuccubus', Sayaad = 'Interface\\Icons\\Spell_Shadow_SummonSuccubus',
  Felhunter = 'Interface\\Icons\\Spell_Shadow_SummonFelHunter', Felguard = 'Interface\\Icons\\Spell_Shadow_SummonFelGuard',
}
local function petLook(r, e)
  if e.petOn then
    local ok, fam = pcall(UnitCreatureFamily, 'pet')
    local icon = ok and type(fam) == 'string' and DEMON_ICON[fam]
    if icon then r.pet:SetTexture(icon); r.pet:SetTexCoord(.08, .92, .08, .92)
    else r.pet:SetTexCoord(0, 1, 0, 1); pcall(SetPortraitTexture, r.pet, 'pet') end   -- a demon not in the table: its face
    r.pet:Show(); r.petRim:Show()
  else r.pet:Hide(); r.petRim:Hide() end
end
-- the name runs to 3 px before the first ring (left at bar - 1 = 73, rings at 72 + barW + 6), so barW + 2; with a
-- raid mark at the line's end (13 px, on the bar's top-right) it stops short of it, barW - 16 (2026-11-18: the elite
-- dragon's room took 16 px from the bar, and "Evolving Ectoplasm" is 121 px)
local function nameW(r) return (r.markOn and barW() - 16) or barW() + 2 end
local function markLook(r, e)
  local on = e.mark and true or false
  if on ~= r.markOn then r.markOn = on; r.name:SetWidth(nameW(r)) end
  if e.mark then
    local i = e.mark - 1
    r.mark:SetTexCoord((i % 4) / 4, (i % 4 + 1) / 4, math.floor(i / 4) / 4, (math.floor(i / 4) + 1) / 4); r.mark:Show()
  else r.mark:Hide() end
end

-- sheet 119 A + B: frame, glow and arrow on your target's row. Glow breathes 1 -> .35 -> 1 over 1.6 s; arrow nudges
-- 0 -> -6 px -> 0 over 1.1 s. 'Calm motion' holds both still (glow full, arrow at rest), as the Motion engine does.
local function targetLook(r, on)
  on = on == true
  if r.isTgt == on then return end
  r.isTgt = on
  r.tgtGlow:SetShown(on); r.tgtFrame:SetShown(on); r.tgtArrow:SetShown(on)
  if on then
    M.breathe('tgtG' .. r.k, 1.6, .35, 1, function(v) r.tgtGlow:SetAlpha(v) end)
    M.breathe('tgtB' .. r.k, 1.1, -6, 0, function(v) r.tgtArrow:SetPoint('TOPLEFT', r, 'TOPLEFT', -23 + v, -6) end)
  else
    M.stop('tgtG' .. r.k); M.stop('tgtB' .. r.k)
    r.tgtGlow:SetAlpha(1); r.tgtArrow:SetPoint('TOPLEFT', r, 'TOPLEFT', -23, -6)
  end
end
L.targetLook = targetLook
local function fill(r, e)
  pcall(r.name.SetText, r.name, UnitName(r.unit))
  pcall(SetPortraitTexture, r.face, r.unit); pcall(SetPortraitTexture, r.lift, r.unit)
  health(r); skull(r, e)   -- the kill bar paints on DOTS and when the row appears (not five times a second)
  r.tgt:SetShown(e.target == true); targetLook(r, e.target)
  threatLook(r, e); petLook(r, e); markLook(r, e); classLook(r); levelLook(r)
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
-- the backing covers only the rows showing (top to bottom), never empty places above them (19:07 shot: one mob in
-- place 3 under two empty places of black)
local function fitBack()
  local low, top = 0, TOKENS + 1
  for k = 1, TOKENS do local r = rows[k]; if r and r.shown then local s2 = slotOf[k] or k; if s2 > low then low = s2 end; if s2 < top then top = s2 end end end
  if db.unlocked and not L.testing then low = math.max(low, 3); top = 1 end
  if top > low then top = 1 end
  local h = PADY * 2 + ROW * math.max(low - top + 1, 1)
  local want = (low > 0 or L.testing) and 1 or 0
  back:ClearAllPoints(); back:SetPoint('TOPLEFT', header, 'TOPLEFT', -24, slotY(top) + PADY + FEATHER)
  -- the backing reaches FEATHER past the rows above and below; its soft ends are never more than half its height,
  -- so a list of one row stays soft (16:51 shots: margins 48 on a 72 px backing squashed into hard lines)
  local function setH(v)
    local bh = v + 2 * FEATHER
    back:SetHeight(bh)
    if back.SetTextureSliceMargins then local m = math.min(48, math.floor(bh / 2) - 1); pcall(back.SetTextureSliceMargins, back, 48, m, 48, m) end
    if sel then sel:SetHeight(v) end
  end
  M.tween('backH', back.h or h, h, .22, function(v) back.h = v; setH(v) end, M.ease.out)
  if back.want ~= want then back.want = want; M.tween('backA', backF:GetAlpha(), want, .25, function(v) backF:SetAlpha(v) end) end
end

local function placeClicks()
  do return end   -- display only: no click areas any more
  pcall(function()
    local sc = header:GetScale()
    geo:SetScale(sc); holder:SetScale(sc)
    -- geo's top-left IS the list's top-left, whatever corner the list is saved by (2026-11-16 "its only targeting
    -- top mob": geo was anchored by the list's own point but is 16 rows tall to the list's 8, so with any point but a
    -- top corner, e.g. RIGHT after a drag, every click area sat rows away from its row)
    geo:ClearAllPoints()
    local l, t = header:GetLeft(), header:GetTop()
    if l and t then geo:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', l, t)
    else local p, _, rp, x, y = header:GetPoint(1); geo:SetPoint(p or 'TOPRIGHT', UIParent, rp or 'TOPRIGHT', x or 0, y or 0) end
    geo:SetSize(width(), PADY * 2 + ROW * TOKENS)
    for k = 1, TOKENS do
      local r = rows[k]
      if r and r.click then
        r.click:ClearAllPoints(); r.click:SetSize(width(), ROW)
        -- only places inside the list (its Rows setting) are live; a place past it would hang down the screen as an
        -- invisible area (20:43 shots: all 16 stacked down the right side), where a resting mouse could send a DoT to
        -- whatever mob that token holds
        if parked[k] or (slotOf[k] or k) > (db.rows or 8) then r.click:SetPoint('TOPLEFT', UIParent, 'BOTTOMRIGHT', 4000, -4000)   -- off screen: no click area
        else r.click:SetPoint('TOPLEFT', geo, 'TOPLEFT', 0, slotY(slotOf[k] or k)) end
      end
    end
  end)
end

-- places: between fights and at the pull, the DPS order (missing a DoT first, then the soonest ending). Then the
-- places for newcomers (tokens with no plate yet: a mob that joins takes one). A plate that is up but not in your
-- fight (an idle Kodo, a friendly guard) is parked: its click area goes off screen, so the list's empty places are
-- never a live mouseover for a mob you can't see in it. In a fight nothing moves (the buttons are locked).
local function pack(instant)
  -- display only now (no secure click areas): the list re-packs in fights too, so a dead mob never leaves a hole
  -- (2026-11-17 shots: rows in places 1 and 4 with empty places between)
  local n, done = 0, {}
  wipe(parked)
  for _, e in ipairs(RO.order(db.sort ~= 'soonest')) do n = n + 1; slotOf[e.k] = n; done[e.k] = true end
  -- then the mobs likely to be in it: your target and your demon's (at the pull the one you hit is often not on the
  -- threat list yet: 19:07, it got parked and could not be clicked), then every other enemy, then empty tokens
  local function plateTok(unit) local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, unit, false); local u = ok and p and ns.plates.unitOf[p]; return u and tonumber(u:match('(%d+)$')) end
  for _, unit in ipairs({ 'target', 'pettarget' }) do local k = plateTok(unit); if k and not done[k] and ns.plates.enemy[tok(k)] then n = n + 1; slotOf[k] = n; done[k] = true end end
  for k = 1, TOKENS do if not done[k] and ns.plates.enemy[tok(k)] then n = n + 1; slotOf[k] = n; done[k] = true end end
  for k = 1, TOKENS do if not done[k] and not ns.plates.live[tok(k)] then n = n + 1; slotOf[k] = n; done[k] = true end end
  -- the rest (friendly plates now). Never parked off screen: the [harm,nodead] driver already hides their click areas,
  -- and the game hands a token to a new mob mid-fight, which a parked token could then never be clicked for
  -- (2026-11-16 19:48, "its only targeting top mob": no click area showed anywhere with /omadoomed list boxes)
  for k = 1, TOKENS do if not done[k] then n = n + 1; slotOf[k] = n end end
  for k = 1, TOKENS do if rows[k] then moveTo(rows[k], slotOf[k], instant) end end
  placeClicks(); fitBack()
end
-- a parked mob joins mid-fight: its row takes the first place no row is using and no plate owns (it can't be
-- clicked until the fight ends: its click area is locked off screen)
local function placeJoiner(k)
  local used = {}
  for j = 1, TOKENS do local r = rows[j]; if j ~= k and r and (r.shown or ns.plates.live[tok(j)]) then used[slotOf[j] or j] = true end end
  for s2 = 1, TOKENS do if not used[s2] then slotOf[k] = s2; moveTo(rows[k], s2, true); return end end
end

local function setShown(r, on)
  if r.shown == on then return end
  r.shown = on
  if on then
    r:Show(); r.wantA = false; r.dmg, r.nd = false, false; killbar(r); pcall(castLook, r)
    M.tween('in' .. r.k, 12, 0, .22, function(v) r:SetPoint('TOPLEFT', header, 'TOPLEFT', v, r.y or slotY(slotOf[r.k] or r.k)) end, M.ease.out)
  else
    M.stop('thr' .. r.k); r.lv = false; targetLook(r, false)
    M.tween('a' .. r.k, r:GetAlpha(), 0, .2, function(v) r:SetAlpha(v) end, nil, function() if not r.shown then r:Hide() end end)
    r.wantA = 0
    killbar(r); pcall(castLook, r)
  end
end

local function update()
  if not header or L.testing then return end
  for k = 1, TOKENS do
    local r, e = rows[k], RO.entries[k]
    if r and e then
      if e.on and not r.shown and fighting and parked[k] then placeJoiner(k) end
      setShown(r, e.on == true)
      if e.on then local ok, err = pcall(fill, r, e); if not ok then ns.error('list row: ' .. tostring(err)) end end
    end
  end
  pack()
end
L.update = update

-- ---------- moving and sizing: Blizzard's Edit Mode look ----------
local function savePos() local p, _, rp, x, y = header:GetPoint(1); db.point, db.rel, db.x, db.y = p, rp, x, y end
-- Size the list about its top-left corner. A frame's anchor offsets are in its own scale, so a plain SetScale slides the
-- whole list across the screen while you drag (2026-11-17: the corner grip "glitched it the fuck out"). Measure the
-- corner on screen first, scale, then pin the corner back to the same screen spot.
local function scaleKeep(s)
  local okL, l = pcall(header.GetLeft, header); local okT, t = pcall(header.GetTop, header)
  local e0 = header:GetEffectiveScale()
  header:SetScale(s)
  if okL and okT and type(l) == 'number' and type(t) == 'number' then
    local e1 = header:GetEffectiveScale()
    header:ClearAllPoints(); header:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', l * e0 / e1, t * e0 / e1)
  end
end
L.scaleKeep = scaleKeep
local function wheel(d)
  if InCombatLockdown() then return end
  db.scale = math.max(60, math.min(180, (db.scale or 100) + d * 5)); scaleKeep(db.scale / 100); savePos(); placeClicks()
end
-- back to where it started: top right, full size
local function resetPlace()
  if InCombatLockdown() or not header then return end
  db.point, db.rel, db.x, db.y, db.scale = nil, nil, nil, nil, nil
  header:ClearAllPoints(); header:SetScale(1); header:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -40, -330); placeClicks()
end
L.resetPlace = resetPlace
-- /omadoomed list snap (sheet 108 v2, 2026-11-17: "pushing it right to the edge and its still not fully in line with
-- my damage meter"): once, the list's top-right goes 3 px under the bottom-right of Details' first window. Its size is
-- left alone. A saved place like any drag: no live link to Details (which hides when solo).
function L.snap()
  if InCombatLockdown() or not header then say('the list can be lined up after this fight.'); return false end
  local d = _G.DetailsBaseFrame1
  local okR, right = pcall(function() return d and d:GetRight() end)
  local okB, bottom = pcall(function() return d and d:GetBottom() end)
  local okW, dw = pcall(function() return d and d:GetWidth() end)
  if not (okR and okB and okW and type(right) == 'number' and type(bottom) == 'number' and type(dw) == 'number') then
    say("Details' window isn't up. Open it (/details show), then /omadoomed list snap again."); return false
  end
  -- position only (2026-11-17: sizing is the corner grip's job alone); at its full size the list is the meter's width
  local ds, e = d:GetEffectiveScale(), header:GetEffectiveScale()
  header:ClearAllPoints(); header:SetPoint('TOPRIGHT', UIParent, 'BOTTOMLEFT', right * ds / e, (bottom * ds - 3) / e)
  savePos(); placeClicks()
  local same = math.abs(width() * e - dw * ds) < 2
  say(same and 'lined up under your damage meter, edge to edge.' or "lined up under your damage meter's right edge. Its width matches at full size: the //// grip sizes it.")
  return true
end
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
  sel:SetScript('OnMouseUp', function(_, b)
    header:StopMovingOrSizing(); savePos(); placeClicks()
    if b == 'RightButton' and L.menu then L.menu(sel) end   -- right-click: lock or reset
  end)
  -- 2026-11-17 (Joshua: "it should only ever resize with a //// bottom right"): the corner grip is the only way to size
  -- it; the mouse wheel no longer does (the old wheel() stays for /omadoomed list size)
  grip = CreateFrame('Button', nil, sel); grip:SetSize(24, 24); grip:SetPoint('BOTTOMRIGHT', sel, 'BOTTOMRIGHT', -2, 2)
  grip:SetNormalTexture(K.sizeGrip); grip:SetHighlightTexture(K.sizeGripHi); grip:SetPushedTexture(K.sizeGripDown)
  -- the drag is measured once, at the press (the list's width on screen then), so the grip moving with the list
  -- can't feed back into its own size
  local from, start, wpx = 0, 1, 1
  grip:SetScript('OnMouseDown', function()
    if InCombatLockdown() then return end
    from, start, wpx = GetCursorPosition(), header:GetScale(), math.max(1, width() * header:GetEffectiveScale())
    grip:SetScript('OnUpdate', function()
      scaleKeep(math.max(.6, math.min(1.8, start * (1 + (GetCursorPosition() - from) / wpx))))
    end)
  end)
  grip:SetScript('OnMouseUp', function() grip:SetScript('OnUpdate', nil); db.scale = math.floor(header:GetScale() * 100 + .5); savePos(); placeClicks() end)
end

-- db.hidden: switched off from the minimap button or its key (2026-11-17, "easily turn off and on ... like Details");
-- moving it or the test list still shows it
local function visible() if header then header:SetShown((fighting and db.hidden ~= true) or db.unlocked == true or L.testing == true) end end
function L.isShown() return db and db.hidden ~= true end
function L.setShown(on)
  if not db then return end
  db.hidden = not on
  if header then visible() end
  if L.tabShown then L.tabShown() end
end
local function unlock(on)
  if InCombatLockdown() then say('the list can be moved after this fight.'); return end
  db.unlocked = on
  if on then db.tabLocked = false; if L.tab and L.tab() then L.tab():Show() end end
  if on and not sel then buildEditMode() end
  if sel then sel:SetShown(on) end
  -- unlocked, it shows the five test rows, so you place and size the list you will really see
  if L.test and (on and not L.testing or (not on and L.testing and L.testForMove)) then L.testForMove = on or nil; L.test(on, true) end
  -- your crowd-control ring moves with the same unlock (sheet 83: everything can be moved)
  if ns.cc and ns.cc.unlock then pcall(ns.cc.unlock, on) end
  visible(); fitBack()
end
L.toggleMove = function() unlock(not db.unlocked) end
L.isUnlocked = function() return db and db.unlocked == true end
-- right-click menu (2026-11-17: "right click and either lock unlock or reset to default"), Blizzard's own menu
function L.menu(owner)
  local function lock() if db.unlocked then unlock(false) end; db.tabLocked = true; if L.peekOff then L.peekOff() end; if L.tabShown then L.tabShown() end end
  local function free() unlock(true) end
  local function reset() resetPlace(); say('list back in its first place, full size.') end
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(owner, function(_, root)
      root:CreateTitle('Mob list')
      if db.unlocked or (sel and sel:IsShown()) then root:CreateButton('Lock in place', lock) else root:CreateButton('Unlock to move', free) end
      root:CreateButton('Line up under the damage meter', function() L.snap() end)
      root:CreateButton('Reset to default', reset)
    end)
  else lock() end   -- no menu in this client: right-click locks, as before
end

-- ---------- seats: one row of your rings per token, built one per frame out of combat ----------
local function placeSeats(r)
  local p = r.pair; if not p then return end
  local sw = seatWidth(); local k = RING / R.S
  p.anchor:SetScale(k); p.anchor:ClearAllPoints(); p.anchor:SetSize(sw / k, 1)
  -- sheet 108 v2: the seats end at the list's right edge, so the rings line up with the meter above
  p.anchor:SetPoint('BOTTOM', r, 'BOTTOMLEFT', (width() - PADX - sw / 2) / k, ((ROW - RING) / 2) / k)
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
        if r.pair then placeSeats(r); r.pair.bar:SetAllPoints(r.bar); r.pair.ring:SetUnit(r.unit); r.pair.main:SetUnit(r.unit); if r.pair.halo then r.pair.halo:SetUnit(r.unit) end; if r.pair.sring then r.pair.sring:SetUnit(r.unit); r.pair.smain:SetUnit(r.unit) end end
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
  for k = 1, TOKENS do local r = rows[k]; if r then r:SetWidth(width()); r.bar:SetWidth(barW() - 4); r.name:SetWidth(nameW(r)); placeSeats(r) end end
  if sel then sel:SetWidth(width() + 12) end
  pack(true)
end

-- ---------- the anchor tab (sheet 84 A, approved 2026-11-16 "A, hover tab") ----------
-- Between fights a small tab sits faintly at the list's top-left corner (the list itself hides out of combat, so
-- unlike Details and Threat there's nothing else to grab). Point at it: it lights gold, the list's outline and its
-- corner grip show. Drag the tab to move, the //// corner grip to size; click the padlock and the tab goes
-- away until you unlock again (options' Move button, the key binding, /omadoomed list move). In a fight it's gone.
local tab
local TAB_W, TAB_H = 52, 22
local function peeking() return tab and (tab:IsMouseOver() or (sel and sel:IsShown() and sel:IsMouseOver()) or tab.dragging) end
local function tabLook(lit)
  if not tab then return end
  tab:SetAlpha(lit and 1 or .4)
  tab.bg:SetVertexColor(.05, .035, .02, lit and .8 or .6)
  tab.edge:SetVertexColor(.91, .77, .42, lit and .9 or .3)
end
local function peek(on)
  if not header or fighting then return end
  if on then
    if not sel then buildEditMode() end
    sel:Show(); header:Show(); tabLook(true)
  elseif not db.unlocked then
    sel:Hide(); visible(); tabLook(false)
  else tabLook(false) end
end
L.peekOff = function() peek(false) end
local function tabShown()
  if not tab then return end
  tab:SetShown(not fighting and db.tabLocked ~= true and db.on ~= false and db.hidden ~= true)
  if not tab:IsShown() then tab.peek = false end
end
local function buildTab()
  tab = CreateFrame('Button', 'OmaDoomedListTab', UIParent)
  tab:SetSize(TAB_W, TAB_H); tab:SetFrameStrata('MEDIUM'); tab:SetClampedToScreen(true)
  tab:SetPoint('BOTTOMLEFT', header, 'TOPLEFT', -6, 2)
  tab.bg = tab:CreateTexture(nil, 'BACKGROUND'); tab.bg:SetTexture(K.ART .. 'rings\\softsq_mask', nil, nil, 'TRILINEAR'); tab.bg:SetAllPoints()
  tab.edge = tab:CreateTexture(nil, 'BORDER'); tab.edge:SetTexture(K.ART .. 'rings\\softsq_edge', nil, nil, 'TRILINEAR'); tab.edge:SetAllPoints()
  -- Blizzard's own size grabber (the diagonal lines) as the grip, and its padlock
  local g = tab:CreateTexture(nil, 'ARTWORK'); g:SetTexture(K.sizeGrip); g:SetSize(16, 16); g:SetPoint('LEFT', tab, 'LEFT', 5, 0)
  g:SetTexCoord(1, 0, 0, 1)   -- mirrored: the lines lean like ////
  local lock = CreateFrame('Button', nil, tab); lock:SetSize(18, 18); lock:SetPoint('RIGHT', tab, 'RIGHT', -4, 0)
  lock:SetNormalTexture('Interface\\Buttons\\LockButton-Unlocked-Up'); lock:SetPushedTexture('Interface\\Buttons\\LockButton-Unlocked-Down')
  lock:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square', 'ADD')
  lock:SetScript('OnClick', function()
    db.tabLocked = true; peek(false); tabShown()
    say('mob list locked in place. To move it again: Move the list in options, or the key binding.')
  end)
  lock:SetScript('OnEnter', function() peek(true) end)
  tab:RegisterForDrag('LeftButton')
  tab:SetScript('OnEnter', function() peek(true) end)
  tab:SetScript('OnDragStart', function(self) if InCombatLockdown() then return end; self.dragging = true; peek(true); header:StartMoving() end)
  tab:SetScript('OnDragStop', function(self) self.dragging = false; header:StopMovingOrSizing(); savePos(); placeClicks() end)
  tab:RegisterForClicks('RightButtonUp')
  tab:SetScript('OnClick', function(self, b) if b == 'RightButton' then L.menu(self) end end)
  -- leaving: the outline goes once the mouse is off both the tab and the outline (and nothing is being dragged)
  tab:SetScript('OnUpdate', function(self, el)
    if not (sel and sel:IsShown()) or db.unlocked then return end
    self.off = peeking() and 0 or (self.off or 0) + el
    if self.off > .35 then self.off = 0; peek(false) end
  end)
  tabLook(false); tabShown()
end
L.tab = function() return tab end
L.tabShown = function() tabShown() end

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
  holder = false   -- display only: no secure click holder
  -- the one soft backing (no box, no edges): wide feathered shape, 9-slice so its soft ends keep their shape
  -- the backing's strength is its colour's alpha (setting 'Backing', like the Threat and Details windows: see-through);
  -- fading it in and out is its own frame's alpha, so the two never overwrite each other
  backF = CreateFrame('Frame', nil, header); backF:SetAllPoints(header); backF:SetFrameLevel(math.max(0, header:GetFrameLevel() - 1)); backF:SetAlpha(0)
  back = backF:CreateTexture(nil, 'BACKGROUND', nil, -8); back:SetTexture(K.listBack, nil, nil, 'TRILINEAR')
  back:SetVertexColor(0, 0, 0, (db.back or 35) / 100); back:SetPoint('TOPLEFT', header, 'TOPLEFT', -24, FEATHER)
  back:SetWidth(width() + 48); back:SetHeight(1); back.h = false; back.want = false
  for k = 1, TOKENS do rows[k] = newRow(k); rows[k]:SetFrameLevel(header:GetFrameLevel() + 2) end
  relayout()
  unlock(db.unlocked == true)
  buildPairs()
  -- the scheduler drives the list: refreshed with the roster, and frozen while your mouse is over it
  local function mouseOver() return header:IsMouseOver() or (holder and holder:IsShown() and MouseIsOver and MouseIsOver(geo)) end
  ns.sched.add('moblist', .2, update, function() return mouseOver() end)   -- frozen while your mouse is on it (rows never move under it)
  ns.bus:On('ROSTER_DONE', function() ns.sched.mark('moblist') end)
  ns.bus:On('SETTING', function(key, store)
    if store ~= 'list' then return end
    if key == 'back' then back:SetVertexColor(0, 0, 0, (db.back or 35) / 100)
    elseif key == 'scale' and not InCombatLockdown() then header:SetScale((db.scale or 100) / 100); placeClicks()
    else relayout(); update() end
  end)
  ns.bus:On('DOTS', function() for k = 1, TOKENS do local r = rows[k]; if r and r.shown then killbar(r) end end end)
  -- sheet 78: someone else's crowd control on a mob: its row goes quiet (rings and threat glow at 35%, no tick
  -- flash); the bar is already that crowd control's teal timer. On Forever nothing fires this any more: whether the
  -- game shows that button is secret, so it can't be watched (Rings.lua, 2026-11-17). Kept for a safe signal later.
  ns.bus:On('OCC', function(owner, on)
    for k = 1, TOKENS do
      local r = rows[k]
      if r and r.pair and r.pair.main == owner then
        r.quiet = on and true or false
        local a = on and .35 or 1
        for _, c in ipairs({ r.pair.sring, r.pair.halo }) do if c then c:SetAlpha(a) end end
        r.glow:SetAlpha(on and 0 or r.glow:GetAlpha()); if on then M.stop('thr' .. k); M.stop('bite' .. k); r.bite:SetAlpha(0); r.lv = false end
      end
    end
  end)
  local ev = CreateFrame('Frame')
  local CASTS = { UNIT_SPELLCAST_START = 1, UNIT_SPELLCAST_STOP = 1, UNIT_SPELLCAST_FAILED = 1, UNIT_SPELLCAST_INTERRUPTED = 1,
    UNIT_SPELLCAST_DELAYED = 1, UNIT_SPELLCAST_CHANNEL_START = 1, UNIT_SPELLCAST_CHANNEL_STOP = 1, UNIT_SPELLCAST_CHANNEL_UPDATE = 1,
    UNIT_SPELLCAST_INTERRUPTIBLE = 1, UNIT_SPELLCAST_NOT_INTERRUPTIBLE = 1 }
  for _, e in ipairs({ 'PLAYER_REGEN_DISABLED', 'PLAYER_REGEN_ENABLED', 'SPELLS_CHANGED', 'UNIT_HEALTH' }) do pcall(ev.RegisterEvent, ev, e) end
  for e in pairs(CASTS) do pcall(ev.RegisterEvent, ev, e) end
  ev:SetScript('OnEvent', function(_, e, unit)
    if e == 'PLAYER_REGEN_DISABLED' then
      if db.unlocked and sel then db.unlocked = false; sel:Hide(); L.testForMove = nil end
      if L.testing then testOff() end
      RO.refreshAll(); pack(true)        -- the places for this fight, set before Blizzard locks the buttons
      fighting = true; visible(); tabShown(); update()
    elseif e == 'PLAYER_REGEN_ENABLED' then
      fighting = false; visible(); tabShown(); relayout(); buildPairs(); update()
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
  buildTab()
  fighting = InCombatLockdown() and true or false; visible()
  RO.refreshAll(); update()
end
ns.starts[#ns.starts + 1] = start


-- ---------- the test list: /omadoomed list test ----------
-- Five pretend rows, out of combat, so the real list can be compared with sheet 83 without a fight (2026-11-16: "it
-- looks nothing like mockups"; the sheets were drawn in a browser, this is the game's own drawing). Every part is the
-- list's own (rows, backing, glow, skull, bar art, cast line, tick flash); only the DoT rings and the kill pieces are
-- stand-ins in the rings' own art (the real ones need real auras). /omadoomed list boxes tints the click areas.
local ART = K.ART
local SPB = ns.spells.byKey
local BEAST, HAWK, RAPTOR = 'Interface\\Icons\\Ability_Mount_WhiteDireWolf', 'Interface\\Icons\\Ability_Hunter_Pet_WindSerpent', 'Interface\\Icons\\Ability_Hunter_Pet_Raptor'
local FAKE = {
  { name = 'Zhevra Runner', hp = 244, max = 300, icon = BEAST, seats = { corruption = 7, agony = 19 }, threat = 1, tick = true },
  { name = 'Sunscale Screecher', hp = 312, max = 400, icon = HAWK, seats = { corruption = 12, agony = 16, immolate = 9 }, cast = true, cls = 'elite' },
  { name = 'Zhevra Runner', hp = 96, max = 300, icon = BEAST, seats = { corruption = 2, agony = 12 }, threat = 3, skull = true, pet = true },
  { name = 'Zhevra Runner', hp = 186, max = 300, icon = BEAST, seats = { corruption = 10, agony = 16, curse = 240 }, target = true, mark = 8 },
  { name = 'Sunscale Lashtail', hp = 330, max = 350, icon = RAPTOR, seats = {}, far = true, cls = 'rare' },
}
local function fakeRing(parent, key)
  local w = CreateFrame('Frame', nil, parent); w:SetSize(RING, RING); w:SetFrameLevel(parent:GetFrameLevel() + 5)
  local bk = w:CreateTexture(nil, 'BACKGROUND'); bk:SetTexture(ART .. 'rings\\backing_flat', nil, nil, 'TRILINEAR'); bk:SetAllPoints()
  local ic = w:CreateTexture(nil, 'ARTWORK'); ic:SetPoint('CENTER'); ic:SetSize(RING * .72, RING * .72); ic:SetTexCoord(.08, .92, .08, .92)
  local sp = SPB[key]
  local okI, tex = pcall(function() return C_Spell.GetSpellTexture(sp and sp.names[1] or 'Corruption') end)
  ic:SetTexture(okI and tex or 136197)
  local m = w:CreateMaskTexture(); m:SetTexture(ART .. 'rings\\mask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE', 'TRILINEAR'); m:SetAllPoints(ic); ic:AddMaskTexture(m)
  local band = w:CreateTexture(nil, 'ARTWORK', nil, 2); band:SetTexture(ART .. 'rings\\ring_plain', nil, nil, 'TRILINEAR'); band:SetAllPoints()
  local c = sp and sp.color or { 1, 1, 1 }; band:SetVertexColor(c[1], c[2], c[3])
  local bez = w:CreateTexture(nil, 'ARTWORK', nil, 3); bez:SetTexture(ART .. 'rings\\bezel', nil, nil, 'TRILINEAR'); bez:SetAllPoints()
  -- the ending light, as the real ring draws it: the whole band in its own lit colour, breathing (the real curve)
  local light = w:CreateTexture(nil, 'ARTWORK', nil, 4); light:SetTexture(ART .. 'rings\\ring_bold', nil, nil, 'TRILINEAR'); light:SetAllPoints(); light:SetBlendMode('ADD'); light:SetAlpha(0)
  local num = w:CreateFontString(nil, 'OVERLAY'); num:SetFont(K.font, math.floor(RING * .42), 'OUTLINE'); num:SetPoint('CENTER')
  w.num, w.light, w.key = num, light, key
  return w
end
local function fakeParts(r)
  if r.fk then return r.fk end
  local fk = { rings = {}, pieces = {} }
  local spots = R.seatSpots()
  for key, i in pairs(spots) do
    local w = fakeRing(r, key)
    w:SetPoint('CENTER', r, 'LEFT', PADX + PORT + GAPP + barW() + GAPR + (i - .5) * RING + (i - 1) * RINGGAP, 0)
    fk.rings[key] = w
  end
  for i = 1, 3 do local t = r.bar:CreateTexture(nil, 'ARTWORK', nil, 2); t:SetTexture(K.statusbar); fk.pieces[i] = t end
  r.fk = fk
  return fk
end
local boxes = {}
local function showBoxes(on)
  for k = 1, TOKENS do local r = rows[k]; if r and r.click and r.click.box then r.click.box:SetShown(on and not L.testing) end end
  for s2 = 1, #FAKE do
    local b = boxes[s2]
    if on and L.testing then
      if not b then b = geo:CreateTexture(nil, 'OVERLAY'); b:SetColorTexture(.2, .8, 1, .25); boxes[s2] = b end
      b:ClearAllPoints(); b:SetPoint('TOPLEFT', geo, 'TOPLEFT', 0, slotY(s2) - 1); b:SetSize(width(), ROW - 2); b:Show()
    elseif b then b:Hide() end
  end
end
-- the kill pieces: your DoTs' damage left, laid back from the health's end (the one ending first nearest the green)
local ORDER = { 'corruption', 'agony', 'immolate' }
local function fakePieces(r, d, dmg)
  local bw = barW() - 4
  local x = d.hp / d.max * bw
  for i, key in ipairs(ORDER) do
    local t, amt = r.fk.pieces[i], dmg[key] or 0
    local w = math.min(x, amt / d.max * bw)
    if w > 0 then
      local c = SPB[key].deep or SPB[key].color
      t:SetVertexColor(c[1], c[2], c[3]); t:ClearAllPoints(); t:SetPoint('TOPLEFT', r.bar, 'TOPLEFT', x - w, 0); t:SetSize(w, BARH - 6); t:Show()
      x = x - w
    else t:Hide() end
  end
end
local function testStep()
  local t = GetTime() - (L.t0 or 0)
  for i, d in ipairs(FAKE) do
    local r = rows[i]
    for key, w in pairs(r.fk.rings) do
      local left = d.seats[key]
      if left then
        local v = left - (t % math.max(3, left)); if v < .5 then v = left end
        w.num:SetText(v >= 60 and (math.floor(v / 60 + .5) .. 'm') or tostring(math.floor(v + .5)))
        -- the real ending curves, evaluated on the seconds left (what Blizzard does for the real rings)
        local nc = R.numCurves and R.numCurves[key]; local lc = R.lightCurves and R.lightCurves[key]
        local okN, cn = pcall(function() return nc and nc:Evaluate(v) end)
        local okL, cl = pcall(function() return lc and lc:Evaluate(v) end)
        if okN and cn and cn.r then w.num:SetTextColor(cn.r, cn.g, cn.b) else w.num:SetTextColor(1, 1, 1) end
        if okL and cl and cl.r then w.light:SetVertexColor(cl.r, cl.g, cl.b); w.light:SetAlpha(cl.a or 0) else w.light:SetAlpha(0) end
        w:Show()
      else w:Hide() end
    end
    local bite = 0
    if d.tick then
      local n = math.floor(t / 3)
      if r.lastBite ~= n then r.lastBite = n; M.flash('bite' .. i, .45, function(v) r.bite:SetAlpha(v * .55) end) end
      bite = (n % 4) * 8
    end
    fakePieces(r, d, { corruption = d.seats.corruption and math.max(0, 50 - bite) or 0, agony = d.seats.agony and 70 or 0, immolate = d.seats.immolate and 60 or 0 })
    if d.cast then
      local ph = t % 3
      if ph < 2 then r.cast:SetStatusBarColor(K.castRed[1], K.castRed[2], K.castRed[3]); r.cast:SetMinMaxValues(0, 2); r.cast:SetValue(ph); r.cast:Show() else r.cast:Hide() end
    end
  end
end
local function clearFake(r)
  if r.fk then for _, w in pairs(r.fk.rings) do w:Hide() end; for _, p2 in ipairs(r.fk.pieces) do p2:Hide() end end
  if r.pair then r.pair.anchor:Show() end
  if r.buffs then r.buffs:Show() end
  r.cast:Hide(); r.tgt:Hide(); targetLook(r, false); r.pet:Hide(); r.petRim:Hide(); r.mark:Hide(); r.skullWin:Hide()
  M.stop('thr' .. r.k); r.lv = false; r.glow:SetAlpha(0); r.ring:SetVertexColor(0, 0, 0, .9)
  r.shown = false; r:Hide(); r:SetAlpha(0); r.wantA = false
end
testOff = function()
  L.testing = nil
  ns.sched.remove('listtest')
  for i = 1, #FAKE do clearFake(rows[i]) end
  showBoxes(db.boxes == true)
end
local function testOn(on, quiet)
  if InCombatLockdown() then say('the test list is for out of combat.'); return end
  if not on then testOff(); visible(); update(); if not quiet then say('test list off.') end; return end
  L.testing = true
  L.t0 = GetTime()
  for i, d in ipairs(FAKE) do
    local r = rows[i]
    local fk = fakeParts(r)
    if r.pair then r.pair.anchor:Hide() end
    if r.buffs then r.buffs:Hide() end
    r.name:SetText(d.name); r.face:SetTexture(d.icon); r.lift:SetTexture(d.icon)
    r.bar:SetMinMaxValues(0, d.max); r.bar:SetValue(d.hp); r.hp:SetText(db.hp ~= false and tostring(d.hp) or '')
    r.tgt:SetShown(d.target == true); targetLook(r, d.target)
    r.lv = false; threatLook(r, { threat = d.threat })
    if d.pet then
      if not (UnitExists('pet') and pcall(SetPortraitTexture, r.pet, 'pet')) then r.pet:SetTexture('Interface\\Icons\\Spell_Shadow_SummonImp') end
      r.pet:Show(); r.petRim:Show()
    else r.pet:Hide(); r.petRim:Hide() end
    markLook(r, { mark = d.mark })
    classLook(r, d.cls or 'normal')   -- row 2 shows the elite dragon, row 5 the rare's silver one
    r.skullWin:SetShown(d.skull == true and ns.db.skull ~= false); r.skullBar:SetMinMaxValues(0, 1); r.skullBar:SetValue(d.skull and 1 or 0)
    r.cast:Hide(); r.cast:SetScript('OnUpdate', nil)
    for _, w in pairs(fk.rings) do w:Show() end
    slotOf[i] = i; r.shown = true; r:Show(); r:SetAlpha(d.far and .5 or 1); r.wantA = d.far and .5 or 1
    r.y = false; moveTo(r, i, true)
  end
  for k = #FAKE + 1, TOKENS do local r = rows[k]; if r then r.shown = false; r:Hide() end end
  placeClicks(); visible(); fitBack()
  ns.sched.add('listtest', .05, testStep)
  showBoxes(db.boxes == true)
  if not quiet then say('test list on: five pretend rows. /omadoomed list boxes shows the click areas. /omadoomed list test again to stop.') end
end
L.test = testOn
L.showBoxes = showBoxes


function L.slash(msg)
  local cmd, arg = (msg or ''):match('^(%S*)%s*(.-)$'); cmd = (cmd or ''):lower()
  if not header then say('the mob list is off (it needs the rings on).'); return end
  if cmd == 'test' then testOn(not L.testing)
  elseif cmd == 'boxes' then db.boxes = not db.boxes; showBoxes(db.boxes); say(db.boxes and 'click areas shown (tinted blue).' or 'click areas hidden.')
  elseif cmd == 'where' then
    local log = {}; ns.db.where = log
    local say0 = say
    local function say(m) log[#log + 1] = date('%H:%M:%S ') .. m; say0(m) end   -- also kept in OmaDoomedDB.where
    -- where every row's click area really is (2026-11-16: clicks only reached the top row). In a fight the click
    -- areas show; out of one they're hidden by design, but their places are still worked out.
    local function top(f) local ok, t = pcall(f.GetTop, f); return ok and t or nil end
    local ok, mo = pcall(function() return ns.model and ns.model.mouseoverCastOn and ns.model.mouseoverCastOn() end)
    say(('click areas: holder %s, combat %s, Mouseover Cast %s'):format(tostring(holder and holder:IsVisible()), tostring(InCombatLockdown()), tostring(ok and mo)))
    -- does the game's secure condition language accept nameplate tokens? (the old show/hide rule depended on it)
    if SecureCmdOptionParse then
      for k = 1, TOKENS do
        if ns.plates.live[tok(k)] then
          local okP, v = pcall(SecureCmdOptionParse, ('[@%s,exists] yes; no'):format(tok(k)))
          say(('  rule test %s: [@%s,exists] -> %s'):format(tok(k), tok(k), tostring(okP and v)))
        end
      end
    end
    for k = 1, TOKENS do
      local r = rows[k]
      if r and (r.shown or (r.click and r.click:IsVisible())) then
        local rt, ct = top(r), top(r.click)
        say(('  %s place %s: row %s, click %s (shown %s, visible %s, top %s vs row %s)'):format(tok(k), tostring(slotOf[k]),
          r.shown and 'shown' or 'hidden', r.click and 'yes' or 'none', tostring(r.click and r.click:IsShown()), tostring(r.click and r.click:IsVisible()),
          ct and ('%.0f'):format(ct * r.click:GetEffectiveScale()) or '?', rt and ('%.0f'):format(rt * r:GetEffectiveScale()) or '?'))
      end
    end
  elseif cmd == 'unlock' or cmd == 'move' then unlock(true); say('drag the list anywhere; the //// corner grip sizes it; right-click it when done.')
  elseif cmd == 'lock' then unlock(false); say('list locked: it shows in fights.')
  elseif cmd == 'snap' then L.snap()
  elseif cmd == 'rows' then
    local n = tonumber(arg); if n then db.rows = math.max(4, math.min(TOKENS, n)); relayout(); say(('the list shows up to %d mobs.'):format(db.rows)) end
  elseif cmd == 'reset' then
    if InCombatLockdown() then return end
    resetPlace(); say('list back in its first place.')
  else
    local n = 0; for k = 1, TOKENS do if rows[k] and rows[k].shown then n = n + 1 end end
    say(('mob list: %d shown of up to %d. /omadoomed list test | boxes | unlock | lock | rows 4-16 | reset'):format(n, db.rows))
  end
end
function L.unlock(on) unlock(on) end
function L.relayout() relayout(); update() end
L.rows = rows
L.slotOf = slotOf
L.parked = parked
-- the key binding (Bindings.xml): Key Bindings > AddOns > OmaDoomed > Move the mob list
_G.OmaDoomed_ListMove = function() if L.toggleMove then L.toggleMove() end end
_G['BINDING_NAME_OMADOOMED_LISTMOVE'] = 'Move the mob list'

-- the key binding (Bindings.xml): Key Bindings > AddOns > OmaDoomed > Show / hide the mob list
_G.OmaDoomed_ListToggle = function() if L.setShown then L.setShown(not L.isShown()) end end
_G['BINDING_NAME_OMADOOMED_LISTTOGGLE'] = 'Show / hide the mob list'
