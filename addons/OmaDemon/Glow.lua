-- OmaDemon glow: your demon's portrait ring glows soul-purple when it is in trouble (below the warning level, 30% by default).
-- Approved design: mockups omashu/wow/15-glows-and-nameplates.html, section B ("Yes, build it", 2026-11-09).
-- Three layers on the pet portrait, sized from the portrait itself so it fits any demon and any frame size:
--   bloom (breathes with the screen edge, Blizzard's clock), rim lit from above (steady), sheen (sweeps once around every 3.5 s).
-- Health is a hidden ("secret") value in combat on Forever, so we never read it. Blizzard's own
-- UnitHealthPercent(unit, usePredicted, curve) evaluates a curve on it and hands back an alpha, and SetAlpha
-- accepts hidden values. So: alpha = curve(health%) = 1 below level - 2%, 0 above level + 2%, a short ramp between.
-- Because of that, nothing here can *know* the demon is low in combat: every look just runs, and the health gate's
-- alpha decides whether you see it. That is also why there is no warning sound (a sound can't be gated by alpha).
-- We only anchor our own frames to PetPortrait / UIParent; nothing on Blizzard's frames is ever changed.
local _, ns = ...
local ART = 'Interface\\AddOns\\OmaDemon\\art\\'
local HALF = .5236                          -- Blizzard's LowHealthFrame bounce, each way

local root = CreateFrame('Frame', 'OmaDemonGlow', UIParent)
root:SetFrameStrata('MEDIUM'); root:Hide()
local gate = CreateFrame('Frame', nil, root); gate:SetAllPoints(); gate:SetAlpha(0)   -- the health switch
local glow = CreateFrame('Frame', nil, gate); glow:SetAllPoints()                    -- the ring; the motion lives here

local function layer(parent, name, drawLayer, sub)
  local t = parent:CreateTexture(nil, drawLayer, nil, sub); t:SetTexture(ART .. name); t:SetAllPoints()
  t:SetBlendMode('BLEND'); return t
end
local bloom = layer(glow, 'bloom', 'BACKGROUND', 0)
local rim = layer(glow, 'rim', 'ARTWORK', 1)
local sheen = layer(glow, 'sheen', 'OVERLAY', 2); sheen:SetBlendMode('ADD')

local function alpha(group, from, to, dur, order, smooth)
  local a = group:CreateAnimation('Alpha'); a:SetFromAlpha(from); a:SetToAlpha(to); a:SetDuration(dur)
  a:SetSmoothing(smooth or 'NONE'); a:SetOrder(order or 1); return a
end

-- Bloom breathes on Blizzard's low-health clock, in step with the screen edge: same 0.5236 s linear bounce, started
-- on the same frame, settling at the same moment. Its own range keeps the ring readable: .62 <-> 1, easing to .62 <-> .81.
local breathe = bloom:CreateAnimationGroup(); breathe:SetLooping('BOUNCE')
local b = alpha(breathe, .62, 1, HALF)
local RING_MIN, RING_ALARM, RING_CALM = .62, 1.0, .81
-- Sheen sweeps clockwise once every 3.5 s
local sweep = sheen:CreateAnimationGroup(); sweep:SetLooping('REPEAT')
local s = sweep:CreateAnimation('Rotation'); s:SetDegrees(-360); s:SetDuration(3.5)

-- ---------- the screen edge (sheet 17; five looks from sheet 45, approved 2026-11-12) ----------
-- The whole screen edge breathes soul purple while the demon is low, the size and strength of Blizzard's red
-- low-health edge. It hangs off the same health gate as the ring. Drawn under everything else, like Blizzard's.
-- Default copies Blizzard's LowHealthFrame: bounce 15% <-> 100%, 0.5236 s each way, linear; 2 s after it lights it
-- eases over 1 s to 15% <-> 50%. The other looks keep that beat and settle the same way.
local edge = CreateFrame('Frame', nil, gate); edge:SetFrameStrata('BACKGROUND'); edge:SetFrameLevel(0)
edge:SetPoint('TOPLEFT', UIParent, 'TOPLEFT'); edge:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT')
local edgeTex = edge:CreateTexture(nil, 'BACKGROUND'); edgeTex:SetTexture(ART .. 'edge'); edgeTex:SetAllPoints(); edgeTex:SetBlendMode('BLEND')
local edgeBreathe = edgeTex:CreateAnimationGroup(); edgeBreathe:SetLooping('BOUNCE')
local eb = alpha(edgeBreathe, .15, 1, HALF)
local ALARM_MIN, ALARM_MAX, CALM_MIN, CALM_MAX = .15, 1.0, .15, .5

-- The looks (sheet 50 v6, 2026-11-13): Default is the band alone. The others are the same band with a few white
-- textures tinted in the Warning colour's ramp (deep / colour / hot), all breathing with it; nothing flashes.
--   fel    the band's inner edge shaped into still, uneven flame tongues (three ramp steps)
--   smoke  soft billows with gaps rising slowly through the band (a tile scrolled up under the band mask)
--   drain  thin strands of light flowing along each side toward the demon's frame, top-left (a tile per side)
-- mat holds them and breathes in step with the band (its own copy of the band's alpha animation).
local LOOKS = { default = true, fel = true, smoke = true, drain = true }
local mat = CreateFrame('Frame', nil, edge); mat:SetAllPoints()
local matBreathe = mat:CreateAnimationGroup(); matBreathe:SetLooping('BOUNCE')
local mb = alpha(matBreathe, .15, 1, HALF)
local function matTex(name, mask, sub)
  local t = mat:CreateTexture(nil, 'BACKGROUND', nil, sub or 1); t:SetTexture(ART .. name); t:SetAllPoints(); t:Hide()
  if mask and mat.CreateMaskTexture then
    local m = mat:CreateMaskTexture(); m:SetTexture(ART .. mask); m:SetAllPoints(); t:AddMaskTexture(m)
  end
  return t
end
local function tile(t) pcall(t.SetHorizTile, t, true); pcall(t.SetVertTile, t, true); return t end
local fel = { inner = matTex('fel_inner'), mid = matTex('fel_mid', nil, 2), hot = matTex('fel_hot', nil, 3) }
fel.hot:SetBlendMode('ADD')
local smoke = { body = tile(matTex('smoke', 'mask_band')), hot = tile(matTex('smoke', 'edgerim', 2)) }
smoke.hot:SetBlendMode('ADD')
local drain = {}
for _, side in ipairs({ 't', 'b', 'l', 'r' }) do
  local h = tile(matTex('strands', 'mask_' .. side, 2)); h:SetBlendMode('ADD')
  drain[side] = { tile(matTex('strands', 'mask_' .. side)), h }
end
local allLookTex = { fel.inner, fel.mid, fel.hot, smoke.body, smoke.hot }
for _, p in pairs(drain) do allLookTex[#allLookTex + 1] = p[1]; allLookTex[#allLookTex + 1] = p[2] end
local scroll = 0
-- the tiles move: smoke rises (its texcoords slide down), strands run along each side toward the top-left
local function scrollLooks(dt, L)
  scroll = scroll + dt
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  if L == 'smoke' then
    local u0, v0 = math.sin(scroll * .25) * .02, scroll * .012
    local uw, vh = W / 512 / 1.4, H / 512 / 1.4
    smoke.body:SetTexCoord(u0, u0 + uw, v0, v0 + vh); smoke.hot:SetTexCoord(u0, u0 + uw, v0, v0 + vh)
  elseif L == 'drain' then
    local d = scroll * .028
    for _, side in ipairs({ 't', 'b' }) do        -- along x, leftward
      local off = side == 'b' and .37 or 0
      for _, t in ipairs(drain[side]) do t:SetTexCoord(d + off, d + off + W / 1024, 0, H / 256) end
    end
    for _, side in ipairs({ 'l', 'r' }) do        -- rotated: the texture's x runs up the screen
      local off = side == 'r' and .61 or 0
      local u0, u1, v1 = d + off, d + off + H / 1024, W / 256
      for _, t in ipairs(drain[side]) do t:SetTexCoord(u1, 0, u0, 0, u1, v1, u0, v1) end
    end
  end
end
-- the ramp per Warning colour: deep inside, the colour, hot at the rim
local RAMP = {
  default = { { .24, .07, .44 }, { .65, .36, 1 }, { .93, .82, 1 } },
  fel = { { .06, .33, .04 }, { .38, .91, .25 }, { .89, 1, .66 } },
  ember = { { .46, .09, .02 }, { 1, .48, .12 }, { 1, .89, .58 } },
}
local function styleLook(L)
  for _, t in ipairs(allLookTex) do t:Hide() end
  local ramp = RAMP[ns.glowDB().colour or 'default'] or RAMP.default
  local deep, main, hot = ramp[1], ramp[2], ramp[3]
  if L == 'fel' then
    fel.inner:SetVertexColor(deep[1], deep[2], deep[3], .85); fel.mid:SetVertexColor(main[1], main[2], main[3], .9)
    fel.hot:SetVertexColor(hot[1], hot[2], hot[3], .6); fel.inner:Show(); fel.mid:Show(); fel.hot:Show()
  elseif L == 'smoke' then
    smoke.body:SetVertexColor(main[1], main[2], main[3], .85); smoke.hot:SetVertexColor(hot[1], hot[2], hot[3], .5)
    smoke.body:Show(); smoke.hot:Show()
  elseif L == 'drain' then
    for _, p in pairs(drain) do
      p[1]:SetVertexColor(main[1], main[2], main[3], .9); p[2]:SetVertexColor(hot[1], hot[2], hot[3], .4); p[1]:Show(); p[2]:Show()
    end
  end
  -- under a look the plain band is quieter, so the look's own shape reads
  edgeTex:SetAlpha(L == 'default' and 1 or .45)
end

local litAt          -- when the edge last lit (only known while the gate's alpha is readable)
local function look() local d = ns.glowDB(); if d.edge == false then return 'off' end; return LOOKS[d.look] and d.look or 'default' end
-- Ring and edge always start together so they breathe as one. Reduced motion: both hold steady at their calm top.
local function edgeMotion()
  local L, reduced = look(), ns.reduced()
  edgeBreathe:Stop(); matBreathe:Stop(); breathe:Stop(); sweep:Stop()
  edge:SetShown(L ~= 'off'); glow:SetShown(ns.glowDB().ring ~= false)
  styleLook(L); mat:SetShown(L ~= 'off' and L ~= 'default')
  if reduced then
    edgeTex:SetAlpha(CALM_MAX * (L == 'default' and 1 or .45)); mat:SetAlpha(CALM_MAX); bloom:SetAlpha(RING_CALM)
  else
    mat:SetAlpha(1); bloom:SetAlpha(1)
    edgeBreathe:Play(); matBreathe:Play(); breathe:Play(); sweep:Play()
  end
end
ns.glowMotion = edgeMotion
-- Blizzard's settle: full alarm for 2 s after lighting, then ease to the calm range over 1 s.
local function settleK()
  if not litAt then return 0 end
  local t = GetTime() - litAt; return t <= 2 and 0 or (t >= 3 and 1 or (t - 2))
end
local function edgeSettle()
  local k, L = settleK(), look()
  eb:SetFromAlpha(ALARM_MIN + (CALM_MIN - ALARM_MIN) * k); eb:SetToAlpha(ALARM_MAX + (CALM_MAX - ALARM_MAX) * k)
  mb:SetFromAlpha(ALARM_MIN + (CALM_MIN - ALARM_MIN) * k); mb:SetToAlpha(ALARM_MAX + (CALM_MAX - ALARM_MAX) * k)
  b:SetToAlpha(RING_ALARM + (RING_CALM - RING_ALARM) * k)
  local strength = (ns.glowDB().strength or 100) / 100
  edge:SetAlpha(strength)
end
-- Health % may come back as 0..1 or 0..100 (the docs only say "percentage"), and in combat we can't look.
-- One curve that is right for both: 0..1 -> lit under low, dark from high up to 1 (full health);
-- above 1 it can only be the 0..100 scale (anything under 1% there is a dead demon anyway): lit to low, dark from high.
local curve
local function buildCurve()
  if not (C_CurveUtil and C_CurveUtil.CreateCurve and UnitHealthPercent) then return end
  local lv = (ns.glowDB().level or 30) / 100
  local LOW, HIGH = lv - .02, lv + .02
  curve = C_CurveUtil.CreateCurve(); curve:SetType(Enum.LuaCurveType.Linear)
  -- 0% is a dead demon: dark (the glow must not stay on a corpse).
  for _, p in ipairs({ { 0, 0 }, { .004, 1 }, { LOW, 1 }, { HIGH, 0 }, { 1, 0 }, { 1.001, 1 }, { LOW * 100, 1 }, { HIGH * 100, 0 }, { 100, 0 } }) do
    curve:AddPoint(p[1], p[2])
  end
end

local testAt, testUntil = 0, 0   -- /omademon test and Preview: lights at testAt for a few seconds
local function update()
  local portrait = PetPortrait
  local okd, dead = pcall(UnitIsDeadOrGhost, 'pet')
  if not okd or (issecretvalue and issecretvalue(dead)) then dead = false end
  local now = GetTime()
  local testing = now >= testAt and now < testUntil
  local shown = (UnitExists('pet') and not dead and portrait and PetFrame and PetFrame:IsVisible()) or (testing and portrait)
  if not shown then root:Hide(); edgeBreathe:Stop(); matBreathe:Stop(); breathe:Stop(); sweep:Stop(); litAt = nil; return end
  if not root:IsShown() then
    -- r = the gold ring's centre radius, which is what the art is drawn around (mockup: band 34-38 px, r 36).
    -- PetPortrait is only the picture inside the ring: measured in game 2026-11-10, its half-width lands at
    -- 23.7 px on the TV while the gold band runs 34-38 px, so r = half-width x 36/23.7 = x1.52.
    local r = (portrait:GetWidth() or 0) / 2 * 1.52
    if r <= 0 then return end
    root:ClearAllPoints(); root:SetPoint('CENTER', portrait, 'CENTER'); root:SetSize(4.4 * r, 4.4 * r)
    root:Show(); edgeMotion()
  end
  if testing then gate:SetAlpha(1); litAt = litAt or now; edgeSettle(); return end
  if not curve then buildCurve() end
  if curve then
    local ok, a = pcall(UnitHealthPercent, 'pet', false, curve)
    if ok and a ~= nil then
      gate:SetAlpha(a)
      -- track when it lit, for the settle; in combat the value may be hidden, then it stays at full alarm
      if not (issecretvalue and issecretvalue(a)) then
        if a > 0 then litAt = litAt or GetTime() else litAt = nil end
      end
      edgeSettle(); return
    end
  end
  -- Fallback (no curve API): only works while health is readable, i.e. out of combat.
  local ok, h, m = pcall(function() return UnitHealth('pet'), UnitHealthMax('pet') end)
  if ok and h and m and not (issecretvalue and (issecretvalue(h) or issecretvalue(m))) and m > 0 then
    gate:SetAlpha(h / m < (ns.glowDB().level or 30) / 100 and 1 or 0)
  end
end

-- Preview (settings button, /omademon preview): the whole warning for 6 s, ring and edge together, from now
function ns.previewWarning()
  if InCombatLockdown() then ns.say('not in combat'); return end
  testAt = GetTime(); testUntil = testAt + 6; litAt = nil; root:Hide(); update()
  if ns.shardsPreview then ns.shardsPreview(6) end
end

-- Warning colour (2026-11-13, sheet 46: Default soul purple, Fel green, Hellfire ember). The ring and edge have their
-- own art per colour (make_art.py); the looks are white art tinted with the colour's ramp (styleLook).
local COLOUR = { default = '', fel = '-fel', ember = '-ember' }
local function applyColour()
  local sfx = COLOUR[ns.glowDB().colour or 'default'] or ''
  bloom:SetTexture(ART .. 'bloom' .. sfx); rim:SetTexture(ART .. 'rim' .. sfx); sheen:SetTexture(ART .. 'sheen' .. sfx)
  edgeTex:SetTexture(ART .. 'edge' .. sfx)
  styleLook(look())
end
ns.applyWarningColour = applyColour

table.insert(ns.onSetting, function(key, store)
  if store ~= 'glow' then return end
  if key == 'colour' then applyColour() end
  if key == 'level' then curve = nil; buildCurve(); update() end
  if key == 'look' or key == 'edge' or key == 'ring' then if root:IsShown() then edgeMotion() end end
  if key == 'strength' then edgeSettle() end
  -- show a change right away for a few seconds (out of combat), like the mockup's live preview
  if (key == 'look' or key == 'strength' or key == 'level' or key == 'colour') and not InCombatLockdown() then
    testAt = GetTime(); testUntil = testAt + 4; litAt = nil; root:Hide(); update()
  end
end)

local ev = CreateFrame('Frame')
ev:SetScript('OnEvent', function(_, e, unit)
  if e == 'PLAYER_LOGIN' then
    if select(2, UnitClass('player')) ~= 'WARLOCK' then ev:UnregisterAllEvents(); ev:SetScript('OnUpdate', nil); return end
    applyColour()
    buildCurve()
  end
  if e == 'CVAR_UPDATE' then if root:IsShown() then edgeMotion() end; return end
  if e == 'UNIT_PET' or e == 'PLAYER_ENTERING_WORLD' then root:Hide() end   -- re-measure the portrait
  update()
end)
for _, e in ipairs({ 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'UNIT_PET', 'PET_UI_UPDATE', 'UNIT_HEALTH',
  'UNIT_MAXHEALTH', 'PLAYER_REGEN_ENABLED', 'PLAYER_REGEN_DISABLED', 'UI_SCALE_CHANGED', 'EDIT_MODE_LAYOUTS_UPDATED', 'CVAR_UPDATE' }) do
  pcall(ev.RegisterEvent, ev, e)
end
-- A slow safety tick: health events cover changes, this catches frames moving or showing late. Particles ride it too.
local acc = 0
ev:SetScript('OnUpdate', function(_, dt)
  acc = acc + dt
  if root:IsShown() and not ns.reduced() then local L = look(); if L == 'smoke' or L == 'drain' then scrollLooks(dt, L) end end
  if acc >= .1 then acc = 0; update() end
end)

local function raw()   -- the pet's health % as the game reports it, when readable (out of combat)
  local ok, v = pcall(UnitHealthPercent, 'pet', false)
  if not ok or v == nil then return 'n/a' end
  if issecretvalue and issecretvalue(v) then return 'hidden' end
  local a = curve and select(2, pcall(UnitHealthPercent, 'pet', false, curve))
  return ('%s -> alpha %s'):format(tostring(v), (a ~= nil and not (issecretvalue and issecretvalue(a))) and tostring(a) or '?')
end

ns.glowSlash = function(msg)
  msg = (msg or ''):lower()
  if msg == 'test' then
    if InCombatLockdown() then ns.say('not in combat'); return end
    testAt = GetTime() + 6; testUntil = testAt + 8; litAt = nil; root:Hide(); update(); ns.say('the glow lights in 6 s, for 8 s')
  elseif msg == 'status' then
    local p = PetPortrait
    ns.say(('pet %s, frame %s, portrait %s, curve %s, health %s, look %s'):format(
      tostring(UnitExists('pet')), tostring(PetFrame and PetFrame:IsVisible()),
      p and ('%.1f x %.1f'):format(p:GetWidth(), p:GetHeight()) or 'none', tostring(curve ~= nil), raw(), look()))
  else
    ns.say('/omademon (settings) | preview | test | status | motion on|off | shards ...')
  end
end
