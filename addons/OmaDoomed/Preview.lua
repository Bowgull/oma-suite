-- The live preview at the top of OmaDoomed's Options page (sheet 37): a target frame stand-in of fixed sizes (nothing
-- read off the real TargetFrame), an enemy nameplate, the rings and Blizzard's squares, running the
-- test fight. It reads the settings every frame, so any change shows at once. Nothing here touches your real target.
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
local H = 150                      -- the preview's height in the list

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
  local num = top:CreateFontString(nil, 'OVERLAY'); num:SetFont(STANDARD_TEXT_FONT, 16, 'OUTLINE'); num:SetPoint('CENTER')
  w.ic, w.ring, w.glow, w.cd, w.num, w.light, w.spot, w.shadow, w.bez, w.back = ic, ring, glow, cd, num, light, spot, shadow, bez, back
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

  -- the target frame stand-in: fixed sizes of our own. Nothing is read off the live TargetFrame (2026-11-13 BugSack:
  -- its sizes come back as hidden values on Forever, and SetSize refuses them). The redesigned preview replaces this.
  frame = CreateFrame('Frame', nil, P); frame:SetSize(232, 100); frame:SetPoint('TOPRIGHT', P, 'TOPRIGHT', -10, -34)
  local pt = frame:CreateTexture(nil, 'BACKGROUND'); pt:SetSize(58, 58); pt:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -26, -19)
  pt:SetTexture('Interface\\Icons\\Ability_Hunter_Pet_Wolf')
  local pm = frame:CreateMaskTexture(); pm:SetTexture('Interface\\CharacterFrame\\TempPortraitAlphaMask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE'); pm:SetAllPoints(pt); pt:AddMaskTexture(pm)
  P.portrait = pt
  local fs = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall'); fs:SetPoint('BOTTOMLEFT', frame, 'TOPLEFT', 24, -40); fs:SetText('Cursed Darkhound')
  bar.x, bar.y, bar.w, bar.h = 24, -42, 124, 18

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
  P:SetScript('OnUpdate', function() local ok, err = pcall(ns.previewDraw); if not ok then P:SetScript('OnUpdate', nil); ns.fail('preview: ' .. tostring(err), 'the preview') end end)
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
  P.plateFill:SetWidth(math.max(.01, 120 * hp / MAXHP))
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
  local where, size, alpha, oa = rdb.where or 'enemy', (rdb.size or 40), (rdb.alpha or 100) / 100, (rdb.othersAlpha or 55) / 100
  for home = 1, 2 do
    local on = (home == 1 and (where == 'enemy' or where == 'both')) or (home == 2 and where ~= 'enemy')   -- the preview's enemy IS your target
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
        local k = other and 'c' or d.k
        w.ic:SetTexture(icon(NAME[k]))
        local col = other and { .54, .42, .16 } or RING[k]
        local lowR = d and d.timeLeft <= low
        if lowR then local b = breath(d.timeLeft); local lc = ns.rings.lit(col, ns.rings.LIT_RING); w.ring:SetVertexColor(lc[1] * b, lc[2] * b, lc[3] * b) else w.ring:SetVertexColor(col[1], col[2], col[3]) end
        w.glow:SetVertexColor(col[1], col[2], col[3])
        local pa = (d and d.lastTick and tickLook ~= 'plain') and (t - d.lastTick.at) or 9
        w.glow:SetAlpha(pa < .12 and pa / .12 * .4 or (pa < .57 and .4 * (1 - (pa - .12) / .45) or 0))
        w.num:SetText(other and '9' or tostring(math.max(0, math.ceil(d.timeLeft))))
        if d then w.cd:SetCooldown(GetTime() - (d.dur - d.timeLeft), d.dur) else w.cd:SetCooldown(GetTime() - 6, 15) end
        w:SetAlpha(other and oa or alpha)
        w:ClearAllPoints()
        if home == 1 then w:SetPoint('BOTTOMLEFT', P.plate, 'TOP', -60 + n, other and 0 or -6)
        else local fz = z * ns.rings.FRAME_SCALE; w:SetSize(fz, fz); w.ic:SetSize(fz * .756, fz * .756); w.num:SetFont(STANDARD_TEXT_FONT, math.floor(fz * ns.rings.numK(true) + .5), ol)   -- sheets 51 B, 52 F
          w:SetPoint('TOPLEFT', frame, 'BOTTOMLEFT', (bar.x or 20) + n, -5) end   -- sheet 42 B: under the frame, 40 px
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
    local on = mode ~= 'hide' and (not mine or (mode == 'all' and d and not d.casting and d.timeLeft > 0))
    if on then q:ClearAllPoints(); q:SetPoint('TOPLEFT', frame, 'TOPLEFT', (bar.x or 20) + n, bar.y - bar.h - 30); n = n + 22; q:Show() else q:Hide() end
  end
end

-- the preview sits at the top of the OmaDoomed page, as a list row of its own
function ns.previewInitializer()
  if not Settings.CreateElementInitializer then return nil end
  local init = Settings.CreateElementInitializer('SettingsListElementTemplate', {})
  init.GetExtent = function() return H + 12 end
  -- Blizzard pools these rows: we only parent our own frame to one, never hook or tag it, and never let the default
  -- Resetter run (it calls the row's Release, which needs cbrHandles that this plain template never makes: the
  -- 2026-11-13 BugSack error when switching Options categories)
  init.InitFrame = function(self, row)
    if not built then build(row) end
    P:SetParent(row); P:ClearAllPoints(); P:SetPoint('TOPLEFT', row, 'TOPLEFT', 30, -6); P:SetPoint('RIGHT', row, 'RIGHT', -30, 0); P:Show()
    P.row, P.init = row, self
    t0 = GetTime(); P.plan = plan()
  end
  init.Resetter = function(self, row)
    if P and P.row == row then P:Hide(); P:ClearAllPoints(); P:SetParent(UIParent); P.row = nil end
  end
  return init
end
