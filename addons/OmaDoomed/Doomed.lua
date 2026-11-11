-- Doomed (sheets omashu/wow/22 v5 and 23 v5, approved 2026-11-10/11): on your target's health bar, the health your DoTs
-- will still take shows in each DoT's colour, at the end of the green; a skull and bones on the portrait marks a mob
-- they will finish. Maths: DoesItDie's public API for now (MIT, Joe Greive), to be folded in later.
--
-- Forever hides health in combat, so nothing here reads a size: reverse-filling status bars pinned to the end of the
-- green, scaled by max health, let WoW place every piece. The skull rides the end of a very long bar inside a small
-- clipped window (DoesItDie's trick), so it shows only when the DoTs' damage reaches the mob's health. Because of
-- that it can't "pop" (no event says the moment it becomes true); it appears at once.
local ADDON, ns = ...
local P = {}; ns.parts.doomed = P

local COLOR = {   -- sheet 25 (approved 2026-11-11): one colour per DoT, shared with the nameplate rings, at the green's strength
  ['Corruption'] = { 40 / 255, 150 / 255, 168 / 255 }, ['Curse of Agony'] = { 120 / 255, 56 / 255, 192 / 255 },
  ['Bane of Agony'] = { 120 / 255, 56 / 255, 192 / 255 }, ['Immolate'] = { 206 / 255, 106 / 255, 36 / 255 },
  ['Siphon Life'] = { 160 / 255, 30 / 255, 50 / 255 },
}
local GOLD = { 206 / 255, 160 / 255, 44 / 255 }   -- gold means only 'ending soon' (last 3 s); at the green's strength like the other pieces
local LOW = 3
local function breath(x)              -- the rings' own breath (OmashuPlates): 1 at 3 s, 0.3 at 2.25 s, 1 at 1.5 s ...
  local ph = (LOW - x) / 1.5 % 1; return .3 + .7 * (math.cos(ph * 2 * math.pi) * .5 + .5)
end
local OTHER = { .55, .45, .65 }
local FILL = 'UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health'
local WHITE = 'Interface\\Buttons\\WHITE8X8'
local MARK = 'Interface\\AddOns\\OmaDoomed\\Art\\doomed-mark'
local MARK_W, MARK_H = 78, 54          -- screen pixels at 1080p (sheet 23: the skull's own size)
local MAX = 6

local hb, fill, portrait, built
local clip, holder, shine
local segs = {}
local win, longBar, mark
local last = {}                      -- damage per DoT name last time (a drop = a tick: flash)
local test
local JOIN = { crease = 4, fade = 6, thin = 2, none = 0 }   -- sheet 25: 'crease' = hard join + soft dark crease (Blizzard's way)

local function atlasOK(n) return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(n) ~= nil end
-- the bar's own grain: a thin middle slice of Blizzard's health texture (the whole texture stretched into a short piece
-- carried its left-to-right shading, so each colour went dark-to-bright and duller than the green)
local function barTex(t)
  local a = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(FILL)
  if a and a.file then
    t:SetTexture(a.file); local l, r = a.leftTexCoord, a.rightTexCoord
    t:SetTexCoord(l + (r - l) * .45, l + (r - l) * .55, a.topTexCoord, a.bottomTexCoord)
  else t:SetTexture('Interface\\TargetingFrame\\UI-StatusBar') end
  t:SetDesaturated(true)
end
local function px(n, frame)           -- screen pixels -> UI units of that frame (the target frame has its own scale)
  local _, h = GetPhysicalScreenSize(); return n * 768 / h / (frame or UIParent):GetEffectiveScale()
end

local function find()
  local tf = TargetFrame
  local main = tf and tf.TargetFrameContent and tf.TargetFrameContent.TargetFrameContentMain
  hb = main and main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
  portrait = tf and tf.TargetFrameContainer and tf.TargetFrameContainer.Portrait
  fill = hb and hb:GetStatusBarTexture()
  return hb and fill and portrait
end

local function build()
  if built then return true end
  if not find() then return false end
  -- clipped to the bar, minus the see-through margin Blizzard's texture has at its left end (measured: 5 screen px)
  clip = CreateFrame('Frame', nil, hb); clip:SetPoint('TOPLEFT', hb, 'TOPLEFT', px(5, hb), 0); clip:SetPoint('BOTTOMRIGHT', hb, 'BOTTOMRIGHT')
  clip:SetClipsChildren(true); clip:SetFrameLevel(hb:GetFrameLevel() + 1)
  holder = CreateFrame('Frame', nil, clip)
  holder:SetPoint('TOPRIGHT', fill, 'TOPRIGHT'); holder:SetPoint('BOTTOMRIGHT', fill, 'BOTTOMRIGHT'); holder:SetWidth(hb:GetWidth())
  local art = CreateFrame('Frame', nil, clip); art:SetAllPoints(clip); art:SetFrameLevel(clip:GetFrameLevel() + 2)
  P.lost = art:CreateTexture(nil, 'ARTWORK', nil, 0); barTex(P.lost); P.lost:SetVertexColor(.14, .09, .05); P.lost:Hide()   -- test only: the empty bar
  for i = 1, MAX do
    local bar = CreateFrame('StatusBar', nil, holder); bar:SetAllPoints(holder); bar:SetReverseFill(true)
    bar:SetStatusBarTexture(WHITE); bar:SetStatusBarColor(0, 0, 0, 0); bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    local s = { bar = bar, edge = bar:GetStatusBarTexture(), shown = 0, target = 0 }
    s.base = art:CreateTexture(nil, 'ARTWORK', nil, 1); barTex(s.base)
    s.lift = art:CreateTexture(nil, 'ARTWORK', nil, 2); barTex(s.lift); s.lift:SetBlendMode('ADD')
    -- the flash and the shine use the bar's own texture: a plain white one also lit the bar's see-through top edge
    s.flash = art:CreateTexture(nil, 'OVERLAY', nil, 1); barTex(s.flash); s.flash:SetVertexColor(1, 1, 1); s.flash:SetBlendMode('ADD'); s.flash:SetAlpha(0)
    s.join = art:CreateTexture(nil, 'ARTWORK', nil, 3); barTex(s.join)      -- the fade into the next piece
    s.joinLift = art:CreateTexture(nil, 'ARTWORK', nil, 4); barTex(s.joinLift); s.joinLift:SetBlendMode('ADD')   -- same brightening as the pieces, or the fade reads as a dark seam
    -- the crease uses the bar's own texture tinted black, so it has the bar's exact shape and never runs onto the brass
    -- borders into the name banner or the mana bar (a plain square did, Joshua 2026-11-11)
    s.creaseL = art:CreateTexture(nil, 'OVERLAY', nil, 0); barTex(s.creaseL)
    s.creaseR = art:CreateTexture(nil, 'OVERLAY', nil, 0); barTex(s.creaseR)
    local g = s.flash:CreateAnimationGroup()
    local a1 = g:CreateAnimation('Alpha'); a1:SetFromAlpha(0); a1:SetToAlpha(.42); a1:SetDuration(.08); a1:SetOrder(1)
    local a2 = g:CreateAnimation('Alpha'); a2:SetFromAlpha(.42); a2:SetToAlpha(0); a2:SetDuration(.45); a2:SetOrder(2); a2:SetSmoothing('OUT')
    s.flashAnim = g
    -- sheet 27 (approved "Looks right"): the bite. A second bar holds where this piece's edge WAS; the chunk between it and
    -- the new edge glows bright in the DoT's colour, holds 120 ms, then drains over 380 ms.
    s.gbar = CreateFrame('StatusBar', nil, holder); s.gbar:SetAllPoints(holder); s.gbar:SetReverseFill(true)
    s.gbar:SetStatusBarTexture(WHITE); s.gbar:SetStatusBarColor(0, 0, 0, 0); s.gbar:SetMinMaxValues(0, 1); s.gbar:SetValue(0)
    s.gedge = s.gbar:GetStatusBarTexture()
    s.ghost = art:CreateTexture(nil, 'OVERLAY', nil, 3); barTex(s.ghost); s.ghost:SetBlendMode('ADD'); s.ghost:Hide()
    s.ghost:SetPoint('TOPLEFT', s.gedge, 'TOPLEFT'); s.ghost:SetPoint('BOTTOMRIGHT', s.edge, 'BOTTOMLEFT')
    -- the glint: one soft light crossing the piece in 450 ms (a 0..1 bar inside the piece carries it, so no size is read)
    s.gclip = CreateFrame('Frame', nil, art); s.gclip:SetClipsChildren(true); s.gclip:SetFrameLevel(art:GetFrameLevel() + 1)
    s.sweep = CreateFrame('StatusBar', nil, s.gclip); s.sweep:SetAllPoints(s.gclip)
    s.sweep:SetStatusBarTexture(WHITE); s.sweep:SetStatusBarColor(0, 0, 0, 0); s.sweep:SetMinMaxValues(0, 1); s.sweep:SetValue(0)
    s.glint = s.gclip:CreateTexture(nil, 'OVERLAY'); barTex(s.glint); s.glint:SetBlendMode('ADD'); s.glint:SetWidth(px(14, hb))
    s.glint:SetPoint('TOP', s.sweep:GetStatusBarTexture(), 'TOPRIGHT'); s.glint:SetPoint('BOTTOM', s.sweep:GetStatusBarTexture(), 'BOTTOMRIGHT')
    if CreateColor then s.glint:SetGradient('HORIZONTAL', CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, .55)) end
    s.gclip:Hide()
    segs[i] = s
  end
  for i, s in ipairs(segs) do
    local right, rp = (i == 1) and holder or segs[i - 1].edge, (i == 1) and 'BOTTOMRIGHT' or 'BOTTOMLEFT'
    for _, t in ipairs({ s.base, s.lift, s.flash }) do
      t:SetPoint('TOPLEFT', s.edge, 'TOPLEFT'); t:SetPoint('BOTTOMRIGHT', right, rp)
    end
    s.gclip:SetPoint('TOPLEFT', s.edge, 'TOPLEFT'); s.gclip:SetPoint('BOTTOMRIGHT', right, rp)
    -- the join sits on this piece's right edge, fading from this colour into the previous (nearer the green) one
    if i > 1 then
      for _, t in ipairs({ s.join, s.joinLift }) do t:SetPoint('TOP', segs[i - 1].edge, 'TOPLEFT'); t:SetPoint('BOTTOM', segs[i - 1].edge, 'BOTTOMLEFT'); t:SetWidth(px(6, hb)) end
      -- the crease: 2 screen px of soft dark either side of the join, darkest (45%) on it
      s.creaseL:SetPoint('TOPRIGHT', segs[i - 1].edge, 'TOPLEFT'); s.creaseL:SetPoint('BOTTOMRIGHT', segs[i - 1].edge, 'BOTTOMLEFT'); s.creaseL:SetWidth(px(2, hb))
      s.creaseR:SetPoint('TOPLEFT', segs[i - 1].edge, 'TOPLEFT'); s.creaseR:SetPoint('BOTTOMLEFT', segs[i - 1].edge, 'BOTTOMLEFT'); s.creaseR:SetWidth(px(2, hb))
      if CreateColor then
        s.creaseL:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, .45))
        s.creaseR:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, .45), CreateColor(0, 0, 0, 0))
      end   -- 6 screen px: what the 2-game-pixel fade looked like on sheet 22 (seen ~3x); 2 px read as a hard cut on the TV
    end
  end
  -- one shine along the top of all the pieces (sheet 22: "fade and shine")
  shine = art:CreateTexture(nil, 'OVERLAY', nil, 2); barTex(shine); shine:SetBlendMode('ADD')
  shine:SetPoint('TOPRIGHT', holder, 'TOPRIGHT'); shine:SetPoint('BOTTOMRIGHT', holder, 'BOTTOMRIGHT')
  if CreateColor then shine:SetGradient('VERTICAL', CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, .30)) end

  -- the skull and bones, on the ring's top edge like a raid mark (sheet 23 v5)
  win = CreateFrame('Frame', nil, portrait:GetParent() or UIParent); win:SetClipsChildren(true); win:SetFrameStrata('HIGH')
  local W, H = px(MARK_W, win), px(MARK_H, win)
  -- sheet 23 v5: centred over the ring (measured on the sheet: 0.5 px off; a -6 px offset put it 6.8 px left in game)
  -- and 65.5 px above the ring's centre, on its top edge
  win:SetSize(W, H); win:SetPoint('CENTER', portrait, 'CENTER', px(.8, win), px(65.5, win))
  longBar = CreateFrame('StatusBar', nil, win); longBar:SetSize(W * 400, H); longBar:SetPoint('RIGHT', win, 'RIGHT')
  longBar:SetStatusBarTexture(WHITE); longBar:SetStatusBarColor(0, 0, 0, 0); longBar:SetMinMaxValues(0, 1); longBar:SetValue(0)
  mark = longBar:CreateTexture(nil, 'OVERLAY'); mark:SetTexture(MARK); mark:SetTexCoord(0, MARK_W / 128, 0, MARK_H / 64)
  mark:SetSize(W, H); mark:SetPoint('RIGHT', longBar:GetStatusBarTexture(), 'RIGHT')
  built = true
  return true
end

local function hide()
  if not built then return end
  clip:Hide(); win:Hide()
  for _, s in ipairs(segs) do s.shown, s.target = 0, 0; s.bite = nil; s.glintAt = nil; s.ghost:Hide(); s.gclip:Hide() end
end

local function colorOf(name) return COLOR[name] or OTHER end

-- dots: { {name, damage} } nearest-the-green first; maxv / hp may be hidden numbers (only handed to status bars)
local function draw(dots, maxv, hp)
  if not build() then return end
  if #dots == 0 then return hide() end
  clip:Show()
  local run = 0
  for i, s in ipairs(segs) do
    local d = dots[i]
    s.bar:SetMinMaxValues(0, maxv)
    if d then
      run = run + d.damage; s.target = run
      local c = colorOf(d.name)
      local left = d.expires and (d.expires - GetTime())
      local a = 1
      local lowNow = left and left > 0 and left <= LOW
      -- ending soon: gold, breathing in brightness on the rings' beat (fading it see-through let the green show: lime)
      if lowNow then local b = .6 + .4 * breath(left); c = { GOLD[1] * b, GOLD[2] * b, GOLD[3] * b } end
      s.base:SetVertexColor(c[1] * 1.15, c[2] * 1.15, c[3] * 1.15, a)
      s.lift:SetVertexColor(c[1] * .7, c[2] * .7, c[3] * .7, a)
      local n = segs[i - 1] and dots[i - 1] and colorOf(dots[i - 1].name)
      if n and CreateColor then
        s.join:SetGradient('HORIZONTAL', CreateColor(c[1] * 1.15, c[2] * 1.15, c[3] * 1.15, 1), CreateColor(n[1] * 1.15, n[2] * 1.15, n[3] * 1.15, 1))
        s.joinLift:SetGradient('HORIZONTAL', CreateColor(c[1] * .7, c[2] * .7, c[3] * .7, 1), CreateColor(n[1] * .7, n[2] * .7, n[3] * .7, 1))
      end
      if last[d.name] and d.damage < last[d.name] - .5 then
        local now = GetTime()
        s.bite = { from = s.shown, at = now }; s.ghost:SetVertexColor(math.min(1, c[1] * 1.6), math.min(1, c[2] * 1.6), math.min(1, c[3] * 1.6))
        s.gbar:SetMinMaxValues(0, maxv); s.gbar:SetValue(s.shown); s.ghost:Show()
        s.glintAt = now; s.gclip:Show()
        s.flashAnim:Stop(); s.flashAnim:Play()
        if _G.OmashuPlates_Pulse then pcall(_G.OmashuPlates_Pulse, 'target', d.name) end   -- its ring, same instant
      end
      last[d.name] = d.damage
    else
      s.target = run
    end
    local on = d and true or false
    local mode = ns.db.doomedJoin or 'crease'
    local jw = mode == 'crease' and 0 or (JOIN[mode] or 0)
    s.creaseL:SetShown(on and i > 1 and mode == 'crease'); s.creaseR:SetShown(on and i > 1 and mode == 'crease')
    if jw > 0 then s.join:SetWidth(px(jw, hb)); s.joinLift:SetWidth(px(jw, hb)) end
    s.base:SetShown(on); s.lift:SetShown(on); s.flash:SetShown(on); s.join:SetShown(on and i > 1 and jw > 0); s.joinLift:SetShown(on and i > 1 and jw > 0)
  end
  local far = segs[math.min(#dots, MAX)]
  shine:ClearAllPoints(); shine:SetPoint('TOPRIGHT', holder, 'TOPRIGHT'); shine:SetPoint('BOTTOMLEFT', far.edge, 'BOTTOMLEFT')
  -- the skull: hidden when the mob already carries a real raid mark (that one wins)
  if GetRaidTargetIndex('target') then win:Hide() else win:Show(); longBar:SetMinMaxValues(0, hp); longBar:SetValue(run) end
end

-- smooth: each piece glides to its new size (grows in, shrinks on ticks)
local function smooth(x) x = math.max(0, math.min(1, x)); return x * x * (3 - 2 * x) end
local function glide(dt)
  if not built or not clip:IsShown() then return end
  local now = GetTime()
  for _, s in ipairs(segs) do
    if s.bite then
      local a = now - s.bite.at
      if a >= .5 then s.bite = nil; s.ghost:Hide()
      else
        local k = a < .12 and 0 or smooth((a - .12) / .38)                -- holds 120 ms, drains over 380 ms
        s.gbar:SetValue(s.bite.from + (s.shown - s.bite.from) * k)
        s.ghost:SetAlpha(1 - .6 * k)
      end
    end
    if s.glintAt then
      local a = (now - s.glintAt) / .45
      if a >= 1 then s.glintAt = nil; s.gclip:Hide() else s.sweep:SetValue(smooth(a)) end
    end
    if s.shown ~= s.target then
      s.shown = s.shown + (s.target - s.shown) * math.min(1, dt * 8)
      if math.abs(s.target - s.shown) < .5 then s.shown = s.target end
      s.bar:SetValue(s.shown)
    end
  end
end

local function update()
  if not ns.db or not ns.db.doomed then return hide() end
  if test then
    if not UnitExists('target') then return hide() end
    local m = UnitHealthMax('target'); local frac = .62; local h = m * frac
    local now = GetTime()
    for _, d in ipairs(test.dots) do   -- fake ticks: Agony every 2 s, the rest every 3 s, each takes a bite; refills when it runs out
      local every = d[1] == 'Curse of Agony' and 2 or 3
      d.next = d.next or now + every
      if now >= d.next then d.next = now + every; d.left = (d.left or d[2]) - d[2] / 6; if d.left <= 0 then d.left = d[2] end end
    end
    -- test: Immolate stays in its last 3 s (gold, breathing like its ring's test); the others have time left
    local dots = {}; for _, d in ipairs(test.dots) do dots[#dots + 1] = { name = d[1], damage = m * (d.left or d[2]), expires = d[1] == 'Immolate' and (now + 3 - (now % 3) - .01) or now + 12 } end
    if build() then   -- pretend the mob is at 62% (or 20%): the pieces start there, the rest of the bar shows empty
      local W = hb:GetWidth()
      holder:ClearAllPoints(); holder:SetPoint('TOPRIGHT', hb, 'TOPLEFT', W * frac, 0); holder:SetPoint('BOTTOMRIGHT', hb, 'BOTTOMLEFT', W * frac, 0)
      P.lost:ClearAllPoints(); P.lost:SetPoint('TOPLEFT', hb, 'TOPLEFT', W * frac, 0); P.lost:SetPoint('BOTTOMRIGHT', hb, 'BOTTOMRIGHT'); P.lost:Show()
    end
    return draw(dots, m, h)
  end
  if not UnitExists('target') or UnitIsDead('target') or not (DoesItDie and DoesItDie.GetDoTs) then return hide() end
  local list = DoesItDie.GetDoTs('target')
  table.sort(list, function(a, b) return (a.expiresAt or 0) < (b.expiresAt or 0) end)   -- runs out first = nearest the green
  local dots = {}
  for _, e in ipairs(list) do if (e.damage or 0) > 0 then dots[#dots + 1] = { name = e.name, damage = e.damage, expires = e.expiresAt } end end
  local ok, err = pcall(draw, dots, UnitHealthMax('target'), UnitHealth('target'))
  if not ok then ns.say('Doomed stopped: ' .. tostring(err)); ns.db.doomed = false; hide() end
end

-- DoesItDie's own box and icon stay off while Doomed is on, and come back when it's off
local function quiet(on)
  if not DoesItDieDB then return end
  if on then
    if ns.db.didSaved == nil then ns.db.didSaved = { m = DoesItDieDB.showMarkers, s = DoesItDieDB.showSkull } end
    DoesItDieDB.showMarkers, DoesItDieDB.showSkull = false, false
  elseif ns.db.didSaved then
    DoesItDieDB.showMarkers, DoesItDieDB.showSkull = ns.db.didSaved.m, ns.db.didSaved.s; ns.db.didSaved = nil
  end
end

function P.start()
  if select(2, UnitClass('player')) ~= 'WARLOCK' then return end
  if not (DoesItDie and DoesItDie.GetDoTs) then ns.say('Doomed needs DoesItDie for now (its maths).'); return end
  quiet(ns.db.doomed)
  local ev = CreateFrame('Frame')
  ev:RegisterEvent('PLAYER_TARGET_CHANGED'); ev:RegisterUnitEvent('UNIT_HEALTH', 'target'); ev:RegisterUnitEvent('UNIT_AURA', 'target')
  ev:SetScript('OnEvent', function(_, e) if e == 'PLAYER_TARGET_CHANGED' then wipe(last); for _, s in ipairs(segs) do s.shown = 0 end end; update() end)
  local acc = 0
  ev:SetScript('OnUpdate', function(_, dt) glide(dt); acc = acc + dt; if acc >= .1 then acc = 0; update() end end)
  if DoesItDie.RegisterCallback then DoesItDie.RegisterCallback(ADDON, function() update() end) end
end

-- /omadoomed            on/off
-- /omadoomed test       fake DoTs on your current target (live)   /omadoomed test die   (doomed)   ... test off
function P.slash(m)
  local j = m:match('^join (%a+)'); if j and JOIN[j] then ns.db.doomedJoin = j; ns.say('Doomed join: ' .. j); return update() end
  if m == 'test off' then test = nil; if built then P.lost:Hide(); holder:ClearAllPoints(); holder:SetPoint('TOPRIGHT', fill, 'TOPRIGHT'); holder:SetPoint('BOTTOMRIGHT', fill, 'BOTTOMRIGHT') end; ns.say('Doomed test off'); return update() end
  if m:match('^test') then
    -- sheet 22's own numbers (health 62%; of the 224-px bar: lives 22/30/36 px, dies 40/60/80 px)
    test = { die = m:match('die') and true or false, dots = { { 'Immolate', 22 / 224 }, { 'Curse of Agony', 30 / 224 }, { 'Corruption', 36 / 224 } } }
    if test.die then test.dots = { { 'Immolate', 40 / 224 }, { 'Curse of Agony', 60 / 224 }, { 'Corruption', 80 / 224 } } end
    ns.say('Doomed test on your target' .. (test.die and ' (doomed)' or '') .. '. /omadoomed test off'); return update()
  end
  ns.db.doomed = not ns.db.doomed; quiet(ns.db.doomed); ns.say('Doomed ' .. (ns.db.doomed and 'on' or 'off (DoesItDie back after /reload)')); update()
end
