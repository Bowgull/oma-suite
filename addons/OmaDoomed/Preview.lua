-- The preview window (sheet 60, 2026-11-13, Joshua: "I agree this is right this is the right way"): its own window docked
-- beside the Options window while OmaDoomed's page is open. A target frame built from Blizzard's own art (atlases; nothing
-- is read off the live TargetFrame, whose sizes are hidden on Forever), an enemy nameplate, the rings and Blizzard's
-- squares, running a looping test fight. It reads the settings every frame, so every change and every combination shows
-- at once. Pointing at a group of settings (mouse, or the pad's cursor) lights the part of the scene that group controls.
-- Nothing here touches your real target, and nothing is hooked or written onto Blizzard's settings rows.
local ADDON, ns = ...

local ART = 'Interface\\AddOns\\OmaDoomed\\Art\\'
local BAR_ATLAS = 'UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health'
local WHITE = 'Interface\\Buttons\\WHITE8X8'
local GREEN = { .21, .59, .16 }
local SP, Anim = ns.spells.byKey, ns.core.Anim
local KEY = { c = 'corruption', a = 'agony', i = 'immolate' }
local K = ns.killStyle             -- the kill bar's colours and looks (KillBarStyle.lua)
local look, ask = K.new(), {}
local RING = { c = SP.corruption.color, a = SP.agony.color, i = SP.immolate.color }    -- rings and tick light
local NAME = { c = 'Corruption', a = 'Bane of Agony', i = 'Immolate' }
local MAXHP, START = 198, 124      -- your DoTs finish this one, so the skull shows
local H = 420                      -- the scene's height inside the window (stacked: the enemy above, your target frame below)
local PLATE_K, FRAME_K = 1.5, 1.6  -- how much bigger than life the enemy and the target frame are drawn
local WIN_W, WIN_H = 470, H + 52    -- the window: narrow enough to sit beside Options on a 1080p screen

local ss, sst = Anim.smoothstep, Anim.smootherstep
local function barTex(t)
  local a = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BAR_ATLAS)
  if a and a.file then t:SetTexture(a.file); local l, r = a.leftTexCoord, a.rightTexCoord; t:SetTexCoord(l + (r - l) * .45, l + (r - l) * .55, a.topTexCoord, a.bottomTexCoord)
  else t:SetTexture('Interface\\TargetingFrame\\UI-StatusBar') end
  t:SetDesaturated(true)
end
local function icon(name) local ok, t = pcall(function() return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(name) end); return ok and t or 136197 end

-- the fight: Corruption cast 0-2 s, Bane of Agony at 2.4 s, Immolate cast 2.4-4.4 s; ticks from DoesItDie's log
local function plan()
  local ag = {}; for k = 1, 12 do ag[k] = 6.1 * (k <= 4 and .5 or (k <= 8 and 1 or 1.5)) end
  return {   -- nearest the green first: lasts longest .. ends first
    { k = 'a', ticks = ag, every = 2, cast = { 2.4, 2.4 }, dur = 24 },
    { k = 'i', ticks = { 3, 3, 3, 3, 3 }, every = 3, cast = { 2.4, 4.4 }, dur = 15 },
    { k = 'c', ticks = { 10.25, 10.25, 10.25, 10.25 }, every = 3, cast = { 0, 2 }, dur = 12 } }
end

local P, built, t0
local frame                         -- the copy of the target frame
local bar = {}                      -- bar geometry inside the copy
local pieces, rings, squares = {}, {}, {}

local function ringWidget(parent)
  local w = CreateFrame('Frame', nil, parent); w:SetSize(40, 40)
  local shadow = w:CreateTexture(nil, 'BACKGROUND', nil, -8); shadow:SetTexture(ART .. 'rings\\ring_shadow'); shadow:SetAllPoints()
  local back = w:CreateTexture(nil, 'BACKGROUND'); back:SetTexture(ART .. 'rings\\backing'); back:SetAllPoints()
  local ic = w:CreateTexture(nil, 'ARTWORK', nil, 0); ic:SetPoint('CENTER'); ic:SetTexCoord(.06, .94, .06, .94)
  local m = w:CreateMaskTexture(); m:SetTexture(ART .. 'rings\\mask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE'); m:SetAllPoints(w); ic:AddMaskTexture(m)
  local ring = w:CreateTexture(nil, 'ARTWORK', nil, 2); ring:SetTexture(ART .. 'rings\\ring_bold'); ring:SetAllPoints()
  local light = w:CreateTexture(nil, 'ARTWORK', nil, 3); light:SetTexture(ART .. 'rings\\ring_light'); light:SetAllPoints()
  local spot = w:CreateTexture(nil, 'ARTWORK', nil, 1); spot:SetTexture(ART .. 'rings\\numspot'); spot:SetAllPoints()
  local glow = w:CreateTexture(nil, 'ARTWORK', nil, 4); glow:SetTexture(ART .. 'rings\\ring_bold'); glow:SetAllPoints(); glow:SetBlendMode('ADD'); glow:SetAlpha(0)
  local cd = CreateFrame('Cooldown', nil, w); cd:SetAllPoints(); pcall(cd.SetSwipeTexture, cd, ART .. 'rings\\swipe_track_bold'); pcall(cd.SetDrawEdge, cd, false); pcall(cd.SetReverse, cd, true); pcall(cd.SetHideCountdownNumbers, cd, true)
  local top = CreateFrame('Frame', nil, cd); top:SetAllPoints(w)
  local bez = top:CreateTexture(nil, 'ARTWORK'); bez:SetTexture(ART .. 'rings\\bezel'); bez:SetAllPoints()
  -- sheet 55: Modern's colour band sits in a black channel (outside line, and the inside line over the bezel)
  local edge = top:CreateTexture(nil, 'ARTWORK', nil, 1); edge:SetTexture(ART .. 'rings\\ring_edge', nil, nil, 'TRILINEAR'); edge:SetAllPoints()
  local edgeIn = top:CreateTexture(nil, 'ARTWORK', nil, 2); edgeIn:SetTexture(ART .. 'rings\\ring_edge_in', nil, nil, 'TRILINEAR'); edgeIn:SetAllPoints()
  local num = top:CreateFontString(nil, 'OVERLAY'); num:SetFont(STANDARD_TEXT_FONT, 16, 'OUTLINE'); num:SetPoint('CENTER')
  w.ic, w.ring, w.glow, w.cd, w.num, w.light, w.spot, w.shadow, w.bez, w.back = ic, ring, glow, cd, num, light, spot, shadow, bez, back
  w.edge, w.edgeIn = edge, edgeIn
  return w
end

local function build(host)
  P = CreateFrame('Frame', nil, host); P:SetHeight(H)
  local bg = P:CreateTexture(nil, 'BACKGROUND'); bg:SetAllPoints(); bg:SetColorTexture(.05, .04, .035, .92)
  -- 2026-11-13 (Joshua: "can we get something behind the black screen"): Blizzard's own warlock artwork behind the
  -- scene (the talent screen's backdrop), darkened so the pieces still read. The first atlas the client has wins.
  local art = P:CreateTexture(nil, 'BACKGROUND', nil, 1); art:SetAllPoints()
  local found = false
  for _, name in ipairs({ 'talents-background-warlock', 'talents-background-warlock-affliction', 'spec-background-warlock' }) do
    local ok = pcall(art.SetAtlas, art, name, false)
    if ok and art.GetAtlas and art:GetAtlas() == name then found = true; break end
  end
  if found then art:SetVertexColor(.72, .66, .72)
    local wash = P:CreateTexture(nil, 'BACKGROUND', nil, 2); wash:SetAllPoints(); wash:SetColorTexture(0, 0, 0, .25)
  else art:Hide() end
  local tag = P:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall'); tag:SetPoint('TOPLEFT', 8, -6); tag:SetText('Over the enemy'); P.leftTag = tag
  local tag2 = P:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall'); tag2:SetPoint('TOPLEFT', 8, -190); tag2:SetText('Your target frame')

  -- the enemy in the world: Forever's own nameplate, built the way Blizzard builds it (wow-ui-source, forever branch:
  -- Blizzard_NamePlates.xml, Blizzard_NamePlateUnitFrame.lua, Camelot/Blizzard_NamePlateLevelFrame.xml and
  -- Camelot/Blizzard_NamePlateConstants.lua): a 20 px bar filled with UI-HUD-CoolDownManager-Bar, its frame
  -- UI-HUD-CoolDownManager-Bar-BG set (-2, 3) / (6, -6) around it, the 28 px level box ui-hud-nameplates-levelindicator
  -- 5 px to its right, the nameplate font above, and UI-HUD-CoolDownManager-Selected-yellow round it when it's your
  -- target. Each atlas falls back to a plain stand-in if the client doesn't have it.
  local function atlasOK(tex, name) local ok = pcall(tex.SetAtlas, tex, name, false); return ok and tex.GetAtlas and tex:GetAtlas() == name end
  P.plate = CreateFrame('Frame', nil, P); P.plate:SetSize(170, 62); P.plate:SetScale(PLATE_K); P.plate:SetPoint('TOP', P, 'TOP', 0, -84 / PLATE_K)
  local hb = CreateFrame('StatusBar', nil, P.plate); hb:SetSize(126, 16); hb:SetPoint('BOTTOMLEFT', P.plate, 'BOTTOMLEFT', 4, 8)
  local fillTex = hb:CreateTexture(nil, 'ARTWORK')
  if not atlasOK(fillTex, 'UI-HUD-CoolDownManager-Bar') then fillTex:SetTexture('Interface\\TargetingFrame\\UI-StatusBar') end
  hb:SetStatusBarTexture(fillTex); hb:SetStatusBarColor(1, 0, 0); hb:SetMinMaxValues(0, MAXHP); hb:SetValue(START)
  local bgT = hb:CreateTexture(nil, 'BACKGROUND')
  if atlasOK(bgT, 'UI-HUD-CoolDownManager-Bar-BG') then bgT:SetPoint('TOPLEFT', hb, 'TOPLEFT', -2, 3); bgT:SetPoint('BOTTOMRIGHT', hb, 'BOTTOMRIGHT', 6, -6)
  else bgT:SetColorTexture(0, 0, 0, .8); bgT:SetPoint('TOPLEFT', hb, 'TOPLEFT', -1, 1); bgT:SetPoint('BOTTOMRIGHT', hb, 'BOTTOMRIGHT', 1, -1) end
  local sel = hb:CreateTexture(nil, 'OVERLAY')
  if atlasOK(sel, 'UI-HUD-CoolDownManager-Selected-yellow') then sel:SetPoint('TOPLEFT', bgT, 'TOPLEFT', -3, 2); sel:SetPoint('BOTTOMRIGHT', bgT, 'BOTTOMRIGHT', 0, 2) else sel:Hide() end
  local lvl = CreateFrame('Frame', nil, P.plate); lvl:SetWidth(28)
  lvl:SetPoint('TOPLEFT', hb, 'TOPRIGHT', 5, 3); lvl:SetPoint('BOTTOMLEFT', hb, 'BOTTOMRIGHT', 5, -2)
  local lvlArt = lvl:CreateTexture(nil, 'ARTWORK'); lvlArt:SetAllPoints()
  if not atlasOK(lvlArt, 'ui-hud-nameplates-levelindicator') then lvlArt:SetColorTexture(0, 0, 0, .7) end
  local lvlText = lvl:CreateFontString(nil, 'OVERLAY', _G.SystemFont_NamePlateLevel and 'SystemFont_NamePlateLevel' or 'GameFontNormalSmall')
  lvlText:SetPoint('CENTER', lvl, 'CENTER', 0, 0); lvlText:SetText('13'); lvlText:SetTextColor(1, .82, 0)
  local nm = P.plate:CreateFontString(nil, 'OVERLAY', _G.SystemFont_NamePlate and 'SystemFont_NamePlate' or 'GameFontNormal')
  nm:SetPoint('BOTTOM', hb, 'TOP', 0, 2); nm:SetText('Cursed Darkhound'); nm:SetTextColor(1, .1, .1)
  P.plateBar, P.plateSel, P.nameText = hb, sel, nm

  -- the target frame stand-in: fixed sizes of our own. Nothing is read off the live TargetFrame (2026-11-13 BugSack:
  -- its sizes come back as hidden values on Forever, and SetSize refuses them). The redesigned preview replaces this.
  frame = CreateFrame('Frame', nil, P); frame:SetSize(232, 100); frame:SetScale(FRAME_K); frame:SetPoint('TOP', P, 'TOP', 0, -196 / FRAME_K)
  local pt = frame:CreateTexture(nil, 'BACKGROUND'); pt:SetSize(58, 58); pt:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -26, -19)
  pt:SetTexture('Interface\\Icons\\Ability_Hunter_Pet_Wolf')
  local pm = frame:CreateMaskTexture(); pm:SetTexture('Interface\\CharacterFrame\\TempPortraitAlphaMask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE'); pm:SetAllPoints(pt); pt:AddMaskTexture(pm)
  P.portrait = pt
  local fs = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall'); fs:SetPoint('BOTTOMLEFT', frame, 'TOPLEFT', 24, -40); fs:SetText('Cursed Darkhound')
  bar.x, bar.y, bar.w, bar.h = 24, -42, 124, 18
  -- Blizzard's own target frame art (the same atlases the real frame uses), drawn over our bars; skipped if missing
  local function atlas(tex, name) local ok = pcall(tex.SetAtlas, tex, name, false); return ok and tex.GetAtlas and tex:GetAtlas() == name end
  local art = frame:CreateTexture(nil, 'OVERLAY', nil, -1); art:SetSize(192, 67); art:SetPoint('TOPLEFT', frame, 'TOPLEFT', 20, -19)
  if not atlas(art, 'UI-HUD-UnitFrame-Target-PortraitOn') then art:Hide() end
  local mana = frame:CreateTexture(nil, 'ARTWORK', nil, 0); mana:SetSize(bar.w, 9); mana:SetPoint('TOPLEFT', frame, 'TOPLEFT', bar.x, bar.y - bar.h - 1)
  if not atlas(mana, 'UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana') then mana:SetColorTexture(.1, .2, .7) end

  -- the bar: empty, green, a piece per DoT (base + lift), its bite wash, particles, creases, cast looks
  local empty = frame:CreateTexture(nil, 'ARTWORK', nil, 0); barTex(empty); empty:SetVertexColor(.14, .09, .05)
  empty:SetPoint('TOPLEFT', frame, 'TOPLEFT', bar.x, bar.y); empty:SetSize(bar.w, bar.h)
  P.green = frame:CreateTexture(nil, 'ARTWORK', nil, 1); barTex(P.green); P.green:SetVertexColor(GREEN[1] * 1.6, GREEN[2] * 1.6, GREEN[3] * 1.6)
  for i = 1, 3 do
    local s = {}
    s.base = frame:CreateTexture(nil, 'ARTWORK', nil, 2); barTex(s.base)
    s.lift = frame:CreateTexture(nil, 'ARTWORK', nil, 3); barTex(s.lift); s.lift:SetBlendMode('ADD')
    s.bite = frame:CreateTexture(nil, 'ARTWORK', nil, 4); barTex(s.bite)
    s.wash = frame:CreateTexture(nil, 'OVERLAY', nil, 1); barTex(s.wash); s.wash:SetBlendMode('ADD')
    s.fill = frame:CreateTexture(nil, 'ARTWORK', nil, 5); barTex(s.fill)
    s.spark = frame:CreateTexture(nil, 'OVERLAY', nil, 2); barTex(s.spark); s.spark:SetBlendMode('ADD')
    s.stripes = frame:CreateTexture(nil, 'ARTWORK', nil, 6); s.stripes:SetTexture('Interface/RaidFrame/Shield-Overlay', 'REPEAT', 'REPEAT'); s.stripes:SetDesaturated(true); s.stripes:SetBlendMode('ADD')
    s.motes = frame:CreateTexture(nil, 'ARTWORK', nil, 6); s.motes:SetTexture(ART .. 'motes', 'REPEAT', 'REPEAT'); s.motes:SetBlendMode('ADD')
    s.crease = frame:CreateTexture(nil, 'OVERLAY', nil, 0); barTex(s.crease)
    s.parts = {}; for k = 1, 5 do local t = frame:CreateTexture(nil, 'OVERLAY', nil, 3); t:SetBlendMode('ADD'); s.parts[k] = t end
    pieces[i] = s
  end
  P.skull = frame:CreateTexture(nil, 'OVERLAY', nil, 7); P.skull:SetTexture(ART .. 'doomed-mark'); P.skull:SetTexCoord(0, 78 / 128, 0, 54 / 64); P.skull:SetSize(60, 42)
  if P.portrait then P.skull:SetPoint('BOTTOM', P.portrait, 'TOP', 0, -6) else P.skull:SetPoint('BOTTOMRIGHT', frame, 'TOPRIGHT', -10, -6) end

  -- rings: three of yours and one from another player, in two homes (above the enemy, above the frame)
  for home = 1, 2 do
    rings[home] = {}
    for i = 1, 4 do rings[home][i] = ringWidget(home == 1 and P.plate or frame) end
  end
  -- Blizzard's squares under the frame: your three DoTs, another player's Corruption, a stun
  local sqIcons = { icon('Bane of Agony'), icon('Immolate'), icon('Corruption'), icon('Corruption'), 'Interface\\Icons\\Spell_Frost_Stun' }
  for i = 1, 5 do
    local q = CreateFrame('Frame', nil, frame); q:SetSize(20, 20)
    -- Blizzard's own debuff square: the icon with UI-Debuff-Overlays' border (the same file and corner TargetFrame uses)
    local ic = q:CreateTexture(nil, 'ARTWORK'); ic:SetAllPoints(); ic:SetTexture(sqIcons[i])
    local bd = q:CreateTexture(nil, 'OVERLAY'); bd:SetPoint('TOPLEFT', -1, 1); bd:SetPoint('BOTTOMRIGHT', 1, -1)
    bd:SetTexture('Interface/Buffs/UI-Debuff-Overlays'); bd:SetTexCoord(.296875, .5703125, 0, .515625); bd:SetVertexColor(.8, 0, 0)
    squares[i] = q
  end
  P.plan = plan(); t0 = GetTime()
  P:SetScript('OnUpdate', function() local ok, err = pcall(ns.previewDraw); if not ok then P:SetScript('OnUpdate', nil); ns.fail('preview: ' .. tostring(err), 'the preview') end end)
  built = true
end

local function place(tex, x, w)
  if w <= .05 then tex:Hide(); return end
  tex:ClearAllPoints(); tex:SetPoint('TOPLEFT', frame, 'TOPLEFT', bar.x + x, bar.y); tex:SetSize(w, bar.h); tex:Show()
end

function ns.previewDraw()
  local db, rdb = ns.db, OmaDoomedDB.rings
  local t = GetTime() - t0
  if t > 26 then t0 = GetTime(); t = 0; P.plan = plan() end
  local low, steady = db.low or 5, db.lowlook == 'steady'
  local function lowFor(k) local R = ns.rings; return (R and R.windowFor and k and R.windowFor(KEY[k])) or low end   -- each DoT's own window, as in game
  local castLook, tickLook = db.cast or 'charging', db.tick or 'ember'
  local function breath(x) return K.breath(x, low, steady) end
  -- the numbers
  local hp, pending = START, 0
  local live = {}
  for _, d in ipairs(P.plan) do
    local land = d.cast[2]
    local done, left, lastTick = 0, 0, nil
    for k, v in ipairs(d.ticks) do local at = land + k * d.every; if t >= at then done = done + v; lastTick = { at = at, amt = v } else left = left + v end end
    if t >= d.cast[1] then hp = hp - done; pending = pending + left end
    d.left, d.done, d.lastTick, d.timeLeft = left, done, lastTick, land + d.dur - t
    d.casting = t >= d.cast[1] and t < land
    d.cpr = d.casting and ((t - d.cast[1]) / math.max(.01, land - d.cast[1])) or 1
    if t >= d.cast[1] then live[#live + 1] = d end
  end
  local pxPer = bar.w / MAXHP
  local greenHp = math.max(0, hp - (db.doomed ~= false and pending or 0))
  place(P.green, 0, greenHp * pxPer)
  if P.plateBar then P.plateBar:SetValue(math.max(0, hp)) end
  -- the pieces
  local x = greenHp * pxPer
  for i, s in ipairs(pieces) do
    local d = live[i]
    for _, tx in ipairs({ s.base, s.lift, s.bite, s.wash, s.fill, s.spark, s.stripes, s.motes, s.crease }) do tx:Hide() end
    for k = 1, 5 do s.parts[k]:Hide() end
    if d and db.doomed ~= false and d.left > 0 then
      local bl, a = 0, 9
      if d.lastTick then a = t - d.lastTick.at; if a < .5 then bl = d.lastTick.amt * (1 - sst(a / .5)) end end
      local w, bw = d.left * pxPer, bl * pxPer
      -- the look: KillBarStyle.lua, the same as the target bar's
      ask.left, ask.low, ask.steady = d.timeLeft, low, steady
      ask.provisional, ask.look, ask.pr = d.casting, castLook, d.cpr
      ask.landAge, ask.landLook = t - d.cast[2], castLook
      ask.light, ask.quiet, ask.rawTone = bw > 0 and tickLook or nil, nil, true
      local o = K.piece(look, SP[KEY[d.k]], ask)
      local tn = o.tn
      if d.casting then
        place(s.base, x, w); s.base:SetVertexColor(o.base[1], o.base[2], o.base[3])
        if o.cpr then
          place(s.fill, x, w * o.cpr); s.fill:SetVertexColor(o.fill[1], o.fill[2], o.fill[3])
          local f = o.spark; place(s.spark, x + w * o.cpr - 6, 8); s.spark:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 1), CreateColor(tn[1] * f, tn[2] * f, tn[3] * f, 1))
        elseif o.stripes then local at = K.stripesAt(t); place(s.stripes, x, w); s.stripes:SetTexCoord(at, at + w / 24, 0, bar.h / 24); s.stripes:SetVertexColor(tn[1], tn[2], tn[3], K.STRIPES_A)
        elseif o.motes then local at = K.motesAt(t); place(s.motes, x, w); s.motes:SetTexCoord(at, at + w / 64, 0, 1); s.motes:SetVertexColor(tn[1] * K.MOTES_K, tn[2] * K.MOTES_K, tn[3] * K.MOTES_K)
        end
      else
        place(s.base, x, w); s.base:SetVertexColor(o.base[1], o.base[2], o.base[3])
        place(s.lift, x, w); s.lift:SetVertexColor(o.lift[1], o.lift[2], o.lift[3])
        if o.spark then local f = o.spark; place(s.spark, x + w - 6, 8); s.spark:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 1), CreateColor(tn[1] * f, tn[2] * f, tn[3] * f, 1)) end
        if bw > 0 then
          place(s.bite, x + w, bw); s.bite:SetVertexColor(o.ghost[1], o.ghost[2], o.ghost[3])
          if tickLook ~= 'plain' then
            local flare = a < .16 and ss(a / .16) or 1 - ss((a - .16) / .5); local fa = K.lightA(flare)
            local tone = o.tone
            place(s.wash, x + w - 16, 16 + bw); s.wash:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 1), CreateColor(tone[1] * fa, tone[2] * fa, tone[3] * fa, 1))
            if tickLook == 'cinders' or tickLook == 'essence' then
              for k = 1, 5 do
                local l, fade, e = K.particle(k, a)
                if l then
                  local p = s.parts[k]
                  p:ClearAllPoints(); p:SetPoint('CENTER', frame, 'TOPLEFT', bar.x + x + w + bw - 2 - (k - 1) * 3 + math.sin(a * 4 + k * 1.7) * 2, bar.y - bar.h * .8 + e * bar.h * .6)
                  if tickLook == 'cinders' then p:SetTexture(ART .. 'mote'); p:SetSize(5 - 2 * l, 5 - 2 * l); p:SetVertexColor(tone[1], tone[2], tone[3], .7 * fade)
                  else p:SetTexture(ART .. 'haze'); p:SetSize(10 + 14 * l, 10 + 14 * l); p:SetVertexColor(o.haze[1], o.haze[2], o.haze[3], .45 * fade) end
                  p:Show()
                end
              end
            end
          end
        end
        w = w + bw
      end
      if i > 1 then place(s.crease, x - 2, 4); s.crease:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, .45)) end
      x = x + w
    end
  end
  -- the skull
  P.skull:SetShown(db.doomed ~= false and db.skull ~= false and greenHp <= 0)
  -- rings
  local where, size, alpha = rdb.where or 'enemy', (rdb.size or 40), (rdb.alpha or 100) / 100
  local oa = rdb.othersMode == 'blizzard' and 0 or (rdb.othersAlpha or 55) / 100   -- Blizzard default: OmaDoomed draws only yours
  if P.leftTag then P.leftTag:SetText(where == 'split' and 'Another enemy you DoT' or 'Over the enemy') end
  if P.plateSel and P.plateSel.GetAtlas and P.plateSel:GetAtlas() then P.plateSel:SetShown(where ~= 'split') end
  for home = 1, 2 do
    -- Above enemies: the enemy on the left is your target, rings over it. Target frame: rings only on the frame.
    -- Haunt: the left one is ANOTHER enemy you DoT (rings over its head); your target's rings sit on its frame.
    local on = (home == 1 and (where == 'enemy' or where == 'both' or where == 'split')) or (home == 2 and where ~= 'enemy')
    local n = 0
    for i = 1, 4 do
      local w = rings[home][i]
      local d = i <= 3 and live[i] or nil
      local other = i == 4
      if on and ((d and not d.casting and d.timeLeft > 0) or (other and oa > 0)) then
        local z = other and size * .6 or size
        w:SetSize(z, z); w.ic:SetSize(z * .756, z * .756); local flat = ns.rings.flat(); local ol = flat and 'OUTLINE' or 'THICKOUTLINE'   -- the 'Ring look' setting, live here
        w.num:SetFont(STANDARD_TEXT_FONT, math.floor(z * ns.rings.numK() + .5), ol); w.ic:SetAlpha((other or flat) and 1 or .8)
        w.light:SetShown(not other and not flat); w.spot:SetShown(not other and not flat); w.shadow:SetShown(not other and not flat); w.bez:SetShown(not flat)
        w.back:SetTexture(ART .. (flat and 'rings\\backing_flat' or 'rings\\backing'))
        local modern = not flat and not other
        w.edge:SetShown(modern); w.edgeIn:SetShown(modern); w.ring:SetTexture(ART .. (modern and 'rings\\ring_bold_hard' or 'rings\\ring_bold'))
        local k = other and 'c' or d.k
        w.ic:SetTexture(icon(NAME[k]))
        local col = other and { .54, .42, .16 } or RING[k]
        local lowR = d and d.timeLeft <= lowFor(d.k)
        if lowR then local b = breath(d.timeLeft); local lc = ns.rings.lit(col, ns.rings.LIT_RING); w.ring:SetVertexColor(lc[1] * b, lc[2] * b, lc[3] * b) else w.ring:SetVertexColor(col[1], col[2], col[3]) end
        w.glow:SetVertexColor(col[1], col[2], col[3])
        local pa = (d and d.lastTick and tickLook ~= 'plain') and (t - d.lastTick.at) or 9
        w.glow:SetAlpha(pa < .12 and pa / .12 * .4 or (pa < .57 and .4 * (1 - (pa - .12) / .45) or 0))
        w.num:SetText(other and '9' or tostring(math.max(0, math.ceil(d.timeLeft))))
        if d then w.cd:SetCooldown(GetTime() - (d.dur - d.timeLeft), d.dur) else w.cd:SetCooldown(GetTime() - 6, 15) end
        w:SetAlpha(other and oa or alpha)
        w:ClearAllPoints()
        -- every ring is centred on its row's line (the smaller one too), and the row starts on the bar's left edge
        if home == 1 then w:SetPoint('CENTER', P.plate, 'TOP', -60 + n + z / 2, 6 + size / 2)
        else local fz = z * ns.rings.FRAME_SCALE; w:SetSize(fz, fz); w.ic:SetSize(fz * .756, fz * .756); w.num:SetFont(STANDARD_TEXT_FONT, math.floor(fz * ns.rings.numK(true) + .5), ol)   -- sheets 51 B, 52 F
          -- under the frame: Blizzard's squares first, the rings in a row beneath them (sheet 42 B)
          local sqH = 0
          local rowH = size * ns.rings.FRAME_SCALE
          w:SetPoint('CENTER', frame, 'BOTTOMLEFT', (bar.x or 20) + n + fz / 2, -(4 + sqH + rowH / 2)) end
        n = n + (home == 2 and z * ns.rings.FRAME_SCALE + 4 or z + 3)
        w:Show()
      else w:Hide() end
    end
  end
  -- Blizzard's squares
  local mode = rdb.squares or 'notmine'
  local n = 0
  for i = 1, 5 do
    local q = squares[i]
    local mine = i <= 3
    local d = mine and live[i]
    local on = false   -- 2026-11-13: Blizzard's squares are left out of the preview
    if on then q:ClearAllPoints(); q:SetPoint('TOPLEFT', frame, 'BOTTOMLEFT', (bar.x or 20) + n, -4); n = n + 22; q:Show() else q:Hide() end
  end
end

-- ---------- the window: docked beside Options while OmaDoomed's page is open ----------
local win, tucked, hl, watch
local GROUP = {   -- which part of the scene each setting lights (keys from Settings.lua)
  doomed = 'tf', skull = 'tf', cast = 'tf', tick = 'tf', low = 'tf', lowlook = 'tf', targetPath = 'tf',
  platebar = 'np', enabled = 'np', which = 'np', othersAlpha = 'np', cc = 'np',
  where = 'where', look = 'rings', size = 'rings', alpha = 'rings', othersMode = 'np',
}
local HEADER = { ['Your target frame'] = 'tf', ['Over enemies'] = 'np', ['Where the rings go'] = 'where', ['Ring look'] = 'rings' }

local function makeHighlight()
  -- 2026-11-13 (Joshua: "it defeats the purpose of LOOKING at it if it obscures it"): nothing is drawn over the part you
  -- point at. Everything else dims (on a layer above the whole scene), and a thin quiet line marks the edge.
  local shade = CreateFrame('Frame', nil, P); shade:SetAllPoints(P); shade:SetFrameLevel(P:GetFrameLevel() + 40)
  hl = CreateFrame('Frame', nil, P); hl:SetFrameLevel(P:GetFrameLevel() + 41); hl:Hide()
  hl.edges = {}
  for i = 1, 4 do local t = hl:CreateTexture(nil, 'OVERLAY'); t:SetColorTexture(1, .9, .7, .35); hl.edges[i] = t end
  local e = hl.edges
  e[1]:SetPoint('TOPLEFT'); e[1]:SetPoint('TOPRIGHT'); e[1]:SetHeight(1)
  e[2]:SetPoint('BOTTOMLEFT'); e[2]:SetPoint('BOTTOMRIGHT'); e[2]:SetHeight(1)
  e[3]:SetPoint('TOPLEFT'); e[3]:SetPoint('BOTTOMLEFT'); e[3]:SetWidth(1)
  e[4]:SetPoint('TOPRIGHT'); e[4]:SetPoint('BOTTOMRIGHT'); e[4]:SetWidth(1)
  hl.dim = {}   -- the rest of the scene dims; the focus itself is left exactly as it is
  for i = 1, 4 do local t = shade:CreateTexture(nil, 'OVERLAY'); t:SetColorTexture(0, 0, 0, .55); t:Hide(); hl.dim[i] = t end
end
local function lightUp(g)
  if not hl then return end
  if not g then hl:Hide(); for _, t in ipairs(hl.dim) do t:Hide() end; return end
  hl:ClearAllPoints()
  if g == 'tf' then hl:SetPoint('TOPLEFT', frame, 'TOPLEFT', 16, -14); hl:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -6, 8)
  elseif g == 'np' then hl:SetPoint('TOPLEFT', P.plate, 'TOPLEFT', -2, 44); hl:SetPoint('BOTTOMRIGHT', P.plate, 'BOTTOMRIGHT', 10, -10)
  elseif g == 'where' then hl:SetPoint('TOPLEFT', P, 'TOPLEFT', 6, -6); hl:SetPoint('BOTTOMRIGHT', P, 'BOTTOMRIGHT', -6, 22)
  elseif g == 'rings' then hl:SetPoint('TOPLEFT', P, 'TOPLEFT', 6, -6); hl:SetPoint('BOTTOMRIGHT', P, 'BOTTOMRIGHT', -6, 6) end
  hl:Show()
  local L, T, R, B = hl:GetLeft(), hl:GetTop(), hl:GetRight(), hl:GetBottom()
  local pl, pt, pr, pb = P:GetLeft(), P:GetTop(), P:GetRight(), P:GetBottom()
  local d = hl.dim
  if L and pl then
    d[1]:ClearAllPoints(); d[1]:SetPoint('TOPLEFT', P); d[1]:SetPoint('BOTTOMRIGHT', P, 'TOPRIGHT', 0, -(pt - T))
    d[2]:ClearAllPoints(); d[2]:SetPoint('BOTTOMLEFT', P); d[2]:SetPoint('TOPRIGHT', P, 'BOTTOMRIGHT', 0, B - pb)
    d[3]:ClearAllPoints(); d[3]:SetPoint('TOPLEFT', P, 'TOPLEFT', 0, -(pt - T)); d[3]:SetPoint('BOTTOMRIGHT', P, 'BOTTOMLEFT', L - pl, B - pb)
    d[4]:ClearAllPoints(); d[4]:SetPoint('TOPRIGHT', P, 'TOPRIGHT', 0, -(pt - T)); d[4]:SetPoint('BOTTOMLEFT', P, 'BOTTOMRIGHT', -(pr - R), B - pb)
    for _, t in ipairs(d) do t:Show() end
  end
end

-- which group the pointer is on: read Blizzard's own row data under the cursor (no hooks, nothing written)
local function pointedGroup()
  local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
  local f = foci and foci[1]
  for _ = 1, 8 do
    if not f then return end
    local ok, g = pcall(function()
      if not f.GetElementData then return end
      local data = f:GetElementData(); if not data then return end
      local setting = data.GetSetting and data:GetSetting()
      local var = setting and setting.GetVariable and setting:GetVariable()
      if type(var) == 'string' then return GROUP[(var:gsub('^OMADOOMED_', ''))] end
      local name = data.data and data.data.name
      if type(name) == 'string' then return HEADER[name] end
    end)
    if ok and g then return g end
    f = f.GetParent and f:GetParent()
  end
end

local function onOurPage()
  local sp = _G.SettingsPanel
  if not (sp and sp:IsShown() and ns.settingsCategory) then return false end
  local ok, cur = pcall(sp.GetCurrentCategory, sp)
  return ok and cur == ns.settingsCategory
end

local function dock()
  local sp = _G.SettingsPanel; if not (win and sp) then return end
  win:ClearAllPoints()
  local db = ns.db
  if db and db.previewPos then win:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', db.previewPos[1], db.previewPos[2]); return end
  -- beside Options on the right, else on the left, else (small screens) over its lower part
  local s = win:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local left, right, uiRight = sp:GetLeft(), sp:GetRight(), UIParent:GetRight()
  local w = WIN_W * s
  if right and uiRight and right + w + 8 <= uiRight then win:SetPoint('TOPLEFT', sp, 'TOPRIGHT', 6, -40)
  elseif left and left - w - 8 >= 0 then win:SetPoint('TOPRIGHT', sp, 'TOPLEFT', -6, -40)
  else win:SetPoint('BOTTOM', sp, 'BOTTOM', 0, 40) end
end

local function buildWindow()
  local ok, w = pcall(CreateFrame, 'Frame', 'OmaDoomedPreviewWindow', UIParent, 'BasicFrameTemplateWithInset')
  if not ok or not w then w = CreateFrame('Frame', 'OmaDoomedPreviewWindow', UIParent) end
  win = w
  win:SetSize(WIN_W, WIN_H); win:SetFrameStrata('DIALOG'); win:SetToplevel(true); win:Hide()
  win:SetClampedToScreen(true); win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag('LeftButton')
  win:SetScript('OnDragStart', function(self) self:StartMoving() end)
  win:SetScript('OnDragStop', function(self)
    self:StopMovingOrSizing(); local x, y = self:GetCenter(); if x and ns.db then ns.db.previewPos = { x, y } end
  end)
  local hasTitle = type(win.TitleText) == 'table'
  local title = hasTitle and win.TitleText or win:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
  if not hasTitle then title:SetPoint('TOP', 0, -6) end
  title:SetText('OmaDoomed preview')
  if type(win.CloseButton) == 'table' then win.CloseButton:SetScript('OnClick', function() tucked = true; win:Hide() end) end
  build(win)
  P:ClearAllPoints(); P:SetPoint('TOPLEFT', win, 'TOPLEFT', 10, -30); P:SetPoint('RIGHT', win, 'RIGHT', -10, 0)
  makeHighlight()
end

-- shown while OmaDoomed's page is open (unless closed with X this session); lights what the pointer is on
local acc = 0
local function tick(_, dt)
  acc = acc + dt; if acc < .1 then return end; acc = 0
  local want = onOurPage() and not tucked
  if want and not win then buildWindow() end
  if not win then return end
  if want and not win:IsShown() then dock(); t0 = GetTime(); P.plan = plan(); win:Show() elseif not want and win:IsShown() then win:Hide() end
  if win:IsShown() then lightUp(pointedGroup()) end
end
local startWatching
function startWatching()
  local sp = _G.SettingsPanel
  if watch then return end
  if not sp then C_Timer.After(2, startWatching); return end   -- Blizzard's settings may load after us
  watch = CreateFrame('Frame'); watch:Hide(); watch:SetScript('OnUpdate', tick)
  sp:HookScript('OnShow', function() watch:Show() end)
  sp:HookScript('OnHide', function() watch:Hide(); if win then win:Hide() end; tucked = false end)
  if sp:IsShown() then watch:Show() end
end
ns.previewStart = startWatching

-- the Show button on the page, and /omadoomed preview
function ns.previewOpen(force)
  tucked = false
  if not win then buildWindow() end
  dock(); t0 = GetTime(); P.plan = plan(); win:Show()
  if force and ns.db then ns.db.previewPos = nil; dock() end
end
ns.previewWindow = function() return win end

