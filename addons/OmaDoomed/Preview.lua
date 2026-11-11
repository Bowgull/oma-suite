-- The live preview at the top of OmaDoomed's Options page (sheet 37): a copy of the target frame built from the game's
-- own frame art (read off the real TargetFrame), an enemy nameplate, the rings and Blizzard's squares, running the
-- test fight. It reads the settings every frame, so any change shows at once. Nothing here touches your real target.
local ADDON, ns = ...

local ART = 'Interface\\AddOns\\OmaDoomed\\Art\\'
local BAR_ATLAS = 'UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health'
local WHITE = 'Interface\\Buttons\\WHITE8X8'
local GREEN = { .21, .59, .16 }
local GOLD = { 206 / 255, 160 / 255, 44 / 255 }
local COLOR = { c = { 78 / 255, 40 / 255, 136 / 255 }, a = { 128 / 255, 30 / 255, 74 / 255 }, i = { 160 / 255, 66 / 255, 22 / 255 } }
local RING = { c = { 176 / 255, 120 / 255, 1 }, a = { 240 / 255, 84 / 255, 150 / 255 }, i = { 1, 138 / 255, 61 / 255 } }
local NAME = { c = 'Corruption', a = 'Bane of Agony', i = 'Immolate' }
local MAXHP, START = 198, 124      -- your DoTs finish this one, so the skull shows
local H = 150                      -- the preview's height in the list

local function mix(a, b, k) return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k } end
local function ss(v) v = math.max(0, math.min(1, v)); return v * v * (3 - 2 * v) end
local function sst(v) v = math.max(0, math.min(1, v)); return v * v * v * (v * (v * 6 - 15) + 10) end
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
  local back = w:CreateTexture(nil, 'BACKGROUND'); back:SetTexture(ART .. 'rings\\backing'); back:SetAllPoints()
  local ic = w:CreateTexture(nil, 'ARTWORK', nil, 0); ic:SetPoint('CENTER'); ic:SetTexCoord(.06, .94, .06, .94)
  local m = w:CreateMaskTexture(); m:SetTexture(ART .. 'rings\\mask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE'); m:SetAllPoints(w); ic:AddMaskTexture(m)
  local ring = w:CreateTexture(nil, 'ARTWORK', nil, 2); ring:SetTexture(ART .. 'rings\\ring'); ring:SetAllPoints()
  local glow = w:CreateTexture(nil, 'ARTWORK', nil, 3); glow:SetTexture(ART .. 'rings\\ring'); glow:SetAllPoints(); glow:SetBlendMode('ADD'); glow:SetAlpha(0)
  local cd = CreateFrame('Cooldown', nil, w); cd:SetAllPoints(); pcall(cd.SetSwipeTexture, cd, ART .. 'rings\\swipe_track'); pcall(cd.SetDrawEdge, cd, false); pcall(cd.SetReverse, cd, true); pcall(cd.SetHideCountdownNumbers, cd, true)
  local top = CreateFrame('Frame', nil, cd); top:SetAllPoints(w)
  local bez = top:CreateTexture(nil, 'ARTWORK'); bez:SetTexture(ART .. 'rings\\bezel'); bez:SetAllPoints()
  local num = top:CreateFontString(nil, 'OVERLAY'); num:SetFont(STANDARD_TEXT_FONT, 16, 'THICKOUTLINE'); num:SetPoint('CENTER')
  w.ic, w.ring, w.glow, w.cd, w.num = ic, ring, glow, cd, num
  return w
end

local function build(host)
  P = CreateFrame('Frame', nil, host); P:SetHeight(H)
  local bg = P:CreateTexture(nil, 'BACKGROUND'); bg:SetAllPoints(); bg:SetColorTexture(.05, .04, .035, .92)
  local tag = P:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall'); tag:SetPoint('TOPLEFT', 8, -6); tag:SetText('Preview: the test fight')

  -- the enemy in the world: its name, a thin nameplate bar, the rings above it
  P.plate = CreateFrame('Frame', nil, P); P.plate:SetSize(150, 60); P.plate:SetPoint('TOPLEFT', P, 'TOPLEFT', 20, -40)
  local nm = P.plate:CreateFontString(nil, 'OVERLAY', 'GameFontNormal'); nm:SetPoint('BOTTOM', P.plate, 'BOTTOM', 0, 14); nm:SetText('Cursed Darkhound'); nm:SetTextColor(1, .25, .2)
  local pb = P.plate:CreateTexture(nil, 'ARTWORK'); pb:SetColorTexture(.08, .02, .02); pb:SetSize(120, 8); pb:SetPoint('BOTTOM', P.plate, 'BOTTOM', 0, 2)
  P.plateFill = P.plate:CreateTexture(nil, 'ARTWORK', nil, 1); P.plateFill:SetColorTexture(.78, .12, .06); P.plateFill:SetPoint('TOPLEFT', pb); P.plateFill:SetPoint('BOTTOMLEFT', pb); P.plateFill:SetWidth(120)
  P.nameText = nm

  -- the copy of the target frame, from the real one's own art and measurements
  frame = CreateFrame('Frame', nil, P); frame:SetSize(232, 100); frame:SetPoint('TOPRIGHT', P, 'TOPRIGHT', -10, -34)
  local tf = TargetFrame
  local cont = tf and tf.TargetFrameContainer
  local hb = tf and ((tf.TargetFrameContent and tf.TargetFrameContent.TargetFrameContentMain and tf.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer and tf.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar) or tf.healthbar)
  local fx, fy, fw, fh
  if tf and tf:GetLeft() then fx, fy, fw, fh = tf:GetLeft(), tf:GetTop(), tf:GetWidth(), tf:GetHeight() end
  local function copyRegion(src, layer)
    if not (src and fx and src.GetLeft and src:GetLeft()) then return end
    local t = frame:CreateTexture(nil, layer or 'ARTWORK')
    local at = src.GetAtlas and src:GetAtlas()
    if at then t:SetAtlas(at) else local tx = src.GetTexture and src:GetTexture(); if tx then t:SetTexture(tx) end; if src.GetTexCoord then t:SetTexCoord(src:GetTexCoord()) end end
    t:SetSize(src:GetWidth(), src:GetHeight()); t:SetPoint('TOPLEFT', frame, 'TOPLEFT', src:GetLeft() - fx, src:GetTop() - fy)
    return t
  end
  if fx then
    frame:SetSize(fw, fh)
    copyRegion(cont and cont.FrameTexture, 'BORDER')
    local mb = tf.TargetFrameContent and tf.TargetFrameContent.TargetFrameContentMain and tf.TargetFrameContent.TargetFrameContentMain.ManaBar
    if mb and mb.GetStatusBarTexture then copyRegion(mb:GetStatusBarTexture(), 'ARTWORK') end
    local por = cont and cont.Portrait
    if por and por:GetLeft() then
      local pt = frame:CreateTexture(nil, 'BACKGROUND'); pt:SetSize(por:GetWidth(), por:GetHeight()); pt:SetPoint('TOPLEFT', frame, 'TOPLEFT', por:GetLeft() - fx, por:GetTop() - fy)
      pt:SetTexture('Interface\\Icons\\Ability_Hunter_Pet_Wolf'); local pm = frame:CreateMaskTexture(); pm:SetTexture('Interface\\CharacterFrame\\TempPortraitAlphaMask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE'); pm:SetAllPoints(pt); pt:AddMaskTexture(pm)
      P.portrait = pt
    end
    local nmSrc = tf.TargetFrameContent and tf.TargetFrameContent.TargetFrameContentMain and tf.TargetFrameContent.TargetFrameContentMain.Name
    if nmSrc and nmSrc:GetLeft() then
      local fs = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall'); fs:SetPoint('TOPLEFT', frame, 'TOPLEFT', nmSrc:GetLeft() - fx, nmSrc:GetTop() - fy); fs:SetSize(nmSrc:GetWidth(), nmSrc:GetHeight()); fs:SetText('Cursed Darkhound')
    end
    if hb and hb:GetLeft() then bar.x, bar.y, bar.w, bar.h = hb:GetLeft() - fx, hb:GetTop() - fy, hb:GetWidth(), hb:GetHeight() end
    frame:SetScale(math.min(1.3, 100 / fh))
  end
  if not bar.w then bar.x, bar.y, bar.w, bar.h = 20, -40, 124, 18 end   -- no target frame to copy: a plain bar

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
  if P.portrait then P.skull:SetPoint('CENTER', P.portrait, 'TOP', 0, 2) else P.skull:SetPoint('BOTTOMRIGHT', frame, 'TOPRIGHT', -10, -6) end

  -- rings: three of yours and one from another player, in two homes (above the enemy, above the frame)
  for home = 1, 2 do
    rings[home] = {}
    for i = 1, 4 do rings[home][i] = ringWidget(home == 1 and P.plate or frame) end
  end
  -- Blizzard's squares under the frame: your three DoTs, another player's Corruption, a stun
  local sqIcons = { icon('Bane of Agony'), icon('Immolate'), icon('Corruption'), icon('Corruption'), 'Interface\\Icons\\Spell_Frost_Stun' }
  for i = 1, 5 do
    local q = CreateFrame('Frame', nil, frame); q:SetSize(20, 20)
    local b = q:CreateTexture(nil, 'BACKGROUND'); b:SetAllPoints(); b:SetColorTexture(.7, 0, 0)
    local ic = q:CreateTexture(nil, 'ARTWORK'); ic:SetPoint('TOPLEFT', 1, -1); ic:SetPoint('BOTTOMRIGHT', -1, 1); ic:SetTexCoord(.07, .93, .07, .93); ic:SetTexture(sqIcons[i])
    squares[i] = q
  end
  P.plan = plan(); t0 = GetTime()
  P:SetScript('OnUpdate', function() local ok, err = pcall(ns.previewDraw); if not ok then P:SetScript('OnUpdate', nil); ns.err('preview: ' .. tostring(err)); print('|cffb48cffOmaDoomed:|r preview stopped: ' .. tostring(err)) end end)
  built = true
end

local function place(tex, x, w)
  if w <= .05 then tex:Hide(); return end
  tex:ClearAllPoints(); tex:SetPoint('TOPLEFT', frame, 'TOPLEFT', bar.x + x, bar.y); tex:SetSize(w, bar.h); tex:Show()
end

function ns.previewDraw()
  -- Blizzard reuses list rows: if ours now holds another setting, the preview steps away
  if P.row and P.row.GetElementData and P.row:GetElementData() ~= P.init then P:Hide(); return end
  local db, rdb = ns.db, OmaDoomedDB.rings
  local t = GetTime() - t0
  if t > 26 then t0 = GetTime(); t = 0; P.plan = plan() end
  local low, steady = db.low or 3, db.lowlook == 'steady'
  local castLook, tickLook = db.cast or 'charging', db.tick or 'ember'
  local function breath(x) if steady then return 1 end; local ph = (low - x) / 1.5 % 1; return .3 + .7 * (math.cos(ph * 2 * math.pi) * .5 + .5) end
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
  P.plateFill:SetWidth(math.max(.01, 120 * hp / MAXHP))
  -- the pieces
  local x = greenHp * pxPer
  for i, s in ipairs(pieces) do
    local d = live[i]
    for _, tx in ipairs({ s.base, s.lift, s.bite, s.wash, s.fill, s.spark, s.stripes, s.motes, s.crease }) do tx:Hide() end
    for k = 1, 5 do s.parts[k]:Hide() end
    if d and db.doomed ~= false and d.left > 0 then
      local c = COLOR[d.k]; local tn = RING[d.k]
      local lowNow = d.timeLeft <= low
      if lowNow then local b = .6 + .4 * breath(d.timeLeft); c = { GOLD[1] * b, GOLD[2] * b, GOLD[3] * b } end
      local bl, a = 0, 9
      if d.lastTick then a = t - d.lastTick.at; if a < .5 then bl = d.lastTick.amt * (1 - sst(a / .5)) end end
      local w, bw = d.left * pxPer, bl * pxPer
      local full = { math.min(1, c[1] * 1.15), math.min(1, c[2] * 1.15), math.min(1, c[3] * 1.15) }
      if d.casting then
        place(s.base, x, w); s.base:SetVertexColor(c[1] * .45, c[2] * .45, c[3] * .45)
        if castLook == 'charging' then
          place(s.fill, x, w * d.cpr); s.fill:SetVertexColor(full[1], full[2], full[3])
          place(s.spark, x + w * d.cpr - 6, 8); s.spark:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 1), CreateColor(tn[1] * .45, tn[2] * .45, tn[3] * .45, 1))
        elseif castLook == 'smoulder' then local k = d.cpr ^ 1.6; s.base:SetVertexColor(c[1] * (.3 + .85 * k), c[2] * (.3 + .85 * k), c[3] * (.3 + .85 * k))
        elseif castLook == 'stripes' then local o = (t * .35) % 1; place(s.stripes, x, w); s.stripes:SetTexCoord(o, o + w / 24, 0, bar.h / 24); s.stripes:SetVertexColor(tn[1], tn[2], tn[3], .55)
        elseif castLook == 'motes' then local o = (t * .08) % 1; place(s.motes, x, w); s.motes:SetTexCoord(o, o + w / 64, 0, 1); s.motes:SetVertexColor(tn[1] * .8, tn[2] * .8, tn[3] * .8)
        end
      else
        local la = t - d.cast[2]; local k = 1
        if castLook ~= 'charging' and castLook ~= 'smoulder' and la < .3 then k = .4 + .6 * ss(la / .3) end
        place(s.base, x, w); s.base:SetVertexColor(full[1] * k, full[2] * k, full[3] * k)
        place(s.lift, x, w); s.lift:SetVertexColor(c[1] * .7 * k, c[2] * .7 * k, c[3] * .7 * k)
        if castLook == 'charging' and la < .35 then local f = .45 * (1 - la / .35) ^ 2; place(s.spark, x + w - 6, 8); s.spark:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 1), CreateColor(tn[1] * f, tn[2] * f, tn[3] * f, 1)) end
        if bw > 0 then
          place(s.bite, x + w, bw); s.bite:SetVertexColor(full[1] + c[1] * .7, full[2] + c[2] * .7, full[3] + c[3] * .7)
          if tickLook ~= 'plain' then
            local flare = a < .16 and ss(a / .16) or 1 - ss((a - .16) / .5); local fa = flare * .55
            local tone = lowNow and { c[1] * 1.3, c[2] * 1.3, c[3] * 1.3 } or tn
            place(s.wash, x + w - 16, 16 + bw); s.wash:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 1), CreateColor(tone[1] * fa, tone[2] * fa, tone[3] * fa, 1))
            if tickLook == 'cinders' or tickLook == 'essence' then
              local life = a / .7
              for k = 1, 5 do
                local l = math.max(0, math.min(1, (life - (k - 1) * .04) / .9))
                if l > 0 and l < 1 then
                  local p = s.parts[k]; local fade = math.sin(math.pi * math.min(1, l * 1.15)); local e = 1 - (1 - l) ^ 2
                  p:ClearAllPoints(); p:SetPoint('CENTER', frame, 'TOPLEFT', bar.x + x + w + bw - 2 - (k - 1) * 3 + math.sin(a * 4 + k * 1.7) * 2, bar.y - bar.h * .8 + e * bar.h * .6)
                  if tickLook == 'cinders' then p:SetTexture(ART .. 'mote'); p:SetSize(5 - 2 * l, 5 - 2 * l); p:SetVertexColor(tone[1], tone[2], tone[3], .7 * fade)
                  else p:SetTexture(ART .. 'haze'); p:SetSize(10 + 14 * l, 10 + 14 * l); local hz = mix(c, tone, .45); p:SetVertexColor(hz[1], hz[2], hz[3], .45 * fade) end
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
  local where, size, alpha, oa = rdb.where or 'enemy', (rdb.size or 40), (rdb.alpha or 100) / 100, (rdb.othersAlpha or 55) / 100
  for home = 1, 2 do
    local on = (home == 1 and where ~= 'frame') or (home == 2 and where ~= 'enemy')
    local n = 0
    for i = 1, 4 do
      local w = rings[home][i]
      local d = i <= 3 and live[i] or nil
      local other = i == 4
      if on and ((d and not d.casting and d.timeLeft > 0) or (other and oa > 0)) then
        local z = other and size * .6 or size
        w:SetSize(z, z); w.ic:SetSize(z * .756, z * .756); w.num:SetFont(STANDARD_TEXT_FONT, math.floor(z * .4 + .5), 'THICKOUTLINE')
        local k = other and 'c' or d.k
        w.ic:SetTexture(icon(NAME[k]))
        local col = other and { .54, .42, .16 } or RING[k]
        local lowR = d and d.timeLeft <= low
        if lowR then local b = breath(d.timeLeft); w.ring:SetVertexColor(1 * b, .94 * b, .69 * b) else w.ring:SetVertexColor(col[1], col[2], col[3]) end
        w.glow:SetVertexColor(col[1], col[2], col[3])
        local pa = (d and d.lastTick and tickLook ~= 'plain') and (t - d.lastTick.at) or 9
        w.glow:SetAlpha(pa < .12 and pa / .12 * .4 or (pa < .57 and .4 * (1 - (pa - .12) / .45) or 0))
        w.num:SetText(other and '9' or tostring(math.max(0, math.ceil(d.timeLeft))))
        if d then w.cd:SetCooldown(GetTime() - (d.dur - d.timeLeft), d.dur) else w.cd:SetCooldown(GetTime() - 6, 15) end
        w:SetAlpha(other and oa or alpha)
        w:ClearAllPoints()
        if home == 1 then w:SetPoint('BOTTOMLEFT', P.plate, 'TOP', -60 + n, other and 0 or -6)
        else w:SetPoint('BOTTOMLEFT', frame, 'TOPLEFT', (bar.x or 20) + n, 4) end
        n = n + z + 3
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
    local on = mode ~= 'hide' and (not mine or (mode == 'all' and d and not d.casting and d.timeLeft > 0))
    if on then q:ClearAllPoints(); q:SetPoint('TOPLEFT', frame, 'TOPLEFT', (bar.x or 20) + n, bar.y - bar.h - 30); n = n + 22; q:Show() else q:Hide() end
  end
end

-- the preview sits at the top of the OmaDoomed page, as a list row of its own
function ns.previewInitializer()
  if not Settings.CreateElementInitializer then return nil end
  local init = Settings.CreateElementInitializer('SettingsListElementTemplate', {})
  init.GetExtent = function() return H + 12 end
  init.InitFrame = function(self, row)
    if not built then build(row) end
    P:SetParent(row); P:ClearAllPoints(); P:SetPoint('TOPLEFT', row, 'TOPLEFT', 30, -6); P:SetPoint('RIGHT', row, 'RIGHT', -30, 0); P:Show()
    P.row, P.init = row, self
    if not row.omaPreviewHook then
      row.omaPreviewHook = true
      row:HookScript('OnHide', function() if P and P.row == row then P:Hide() end end)
    end
    t0 = GetTime(); P.plan = plan()
  end
  return init
end
