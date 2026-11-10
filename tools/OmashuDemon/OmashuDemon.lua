-- Omashu Demon: your demon's portrait ring glows soul-purple when it is in trouble (below 30% health).
-- Approved design: mockups omashu/wow/15-glows-and-nameplates.html, section B ("Yes, build it", 2026-11-09).
-- Three layers on the pet portrait, sized from the portrait itself so it fits any demon and any frame size:
--   bloom (breathes every 1.6 s), rim lit from above (steady), sheen (sweeps once around every 3.5 s).
-- Health is a hidden ("secret") value in combat on Forever, so we never read it. Blizzard's own
-- UnitHealthPercent(unit, usePredicted, curve) evaluates a curve on it and hands back an alpha, and SetAlpha
-- accepts hidden values. So: alpha = curve(health%) = 1 below 28%, 0 above 32%, a short ramp between.
-- We only anchor our own frame to PetPortrait; nothing on Blizzard's frames is ever changed.
local ART = 'Interface\\AddOns\\OmashuDemon\\art\\'
local LOW, HIGH = .28, .32                  -- fully lit under 28%, gone over 32% (the line is 30%)

local root = CreateFrame('Frame', 'OmashuDemonFrame', UIParent)
root:SetFrameStrata('MEDIUM'); root:Hide()
local gate = CreateFrame('Frame', nil, root); gate:SetAllPoints(); gate:SetAlpha(0)   -- the health switch
local glow = CreateFrame('Frame', nil, gate); glow:SetAllPoints()                    -- the motion lives here

local function layer(name, drawLayer, sub)
  local t = glow:CreateTexture(nil, drawLayer, nil, sub); t:SetTexture(ART .. name); t:SetAllPoints()
  t:SetBlendMode('BLEND'); return t
end
local bloom = layer('bloom', 'BACKGROUND', 0)
local rim = layer('rim', 'ARTWORK', 1)
local sheen = layer('sheen', 'OVERLAY', 2); sheen:SetBlendMode('ADD')

-- Bloom breathes .62 -> 1 -> .62 over 1.6 s (mockup: .62 + .38 * sine)
local breathe = bloom:CreateAnimationGroup(); breathe:SetLooping('BOUNCE')
local b = breathe:CreateAnimation('Alpha'); b:SetFromAlpha(.62); b:SetToAlpha(1); b:SetDuration(.8); b:SetSmoothing('IN_OUT')
-- Sheen sweeps clockwise once every 3.5 s
local sweep = sheen:CreateAnimationGroup(); sweep:SetLooping('REPEAT')
local s = sweep:CreateAnimation('Rotation'); s:SetDegrees(-360); s:SetDuration(3.5)

-- Pet edge (sheet 17, "Yes the purple is perfect", 2026-11-10): the whole screen edge breathes soul purple while the
-- demon is under 30%, the size and strength of Blizzard's red low-health edge. It hangs off the same health gate as
-- the ring, so it shows and hides exactly with it (in combat too). Drawn under everything else, like Blizzard's.
-- Breathing copies Blizzard's own LowHealthFrame (FrameXML LowHealthFrame.xml/.lua, 2026-11-10, Joshua: "it needs to
-- breathe the way the WoW I'm dying breathes"): bounce 15% <-> 100%, 0.5236 s each way, linear; 2 s after it lights
-- it eases over 1 s to 15% <-> 50%. Reduced motion (/omdemon motion off) holds a steady 50%.
OmashuDemonDB = OmashuDemonDB or {}
local edge = CreateFrame('Frame', nil, gate); edge:SetFrameStrata('BACKGROUND'); edge:SetFrameLevel(0)
edge:SetPoint('TOPLEFT', UIParent, 'TOPLEFT'); edge:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT')
local edgeTex = edge:CreateTexture(nil, 'BACKGROUND'); edgeTex:SetTexture(ART .. 'edge'); edgeTex:SetAllPoints(); edgeTex:SetBlendMode('BLEND')
local edgeBreathe = edgeTex:CreateAnimationGroup(); edgeBreathe:SetLooping('BOUNCE')
local eb = edgeBreathe:CreateAnimation('Alpha'); eb:SetDuration(.5236); eb:SetSmoothing('NONE')
local ALARM_MIN, ALARM_MAX, CALM_MIN, CALM_MAX = .15, 1.0, .15, .5
eb:SetFromAlpha(ALARM_MIN); eb:SetToAlpha(ALARM_MAX)
local litAt          -- when the edge last lit (only known while the gate's alpha is readable)
local function edgeMotion()
  if OmashuDemonDB.reduced then edgeBreathe:Stop(); edgeTex:SetAlpha(CALM_MAX) else edgeTex:SetAlpha(1); if not edgeBreathe:IsPlaying() then edgeBreathe:Play() end end
end
-- Blizzard's settle: full alarm for 2 s after lighting, then ease to the calm range over 1 s.
local function edgeSettle()
  if not litAt then eb:SetFromAlpha(ALARM_MIN); eb:SetToAlpha(ALARM_MAX); return end
  local t = GetTime() - litAt
  local k = t <= 2 and 0 or (t >= 3 and 1 or (t - 2))
  eb:SetFromAlpha(ALARM_MIN + (CALM_MIN - ALARM_MIN) * k); eb:SetToAlpha(ALARM_MAX + (CALM_MAX - ALARM_MAX) * k)
end

-- Health % may come back as 0..1 or 0..100 (the docs only say "percentage"), and in combat we can't look.
-- One curve that is right for both: 0..1 -> lit under .28, dark from .32 up to 1 (full health);
-- above 1 it can only be the 0..100 scale (anything under 1% there is a dead demon anyway): lit to 28, dark from 32.
local curve
local function buildCurve()
  if not (C_CurveUtil and C_CurveUtil.CreateCurve and UnitHealthPercent) then return end
  curve = C_CurveUtil.CreateCurve(); curve:SetType(Enum.LuaCurveType.Linear)
  -- 0% is a dead demon: dark (the glow must not stay on a corpse).
  for _, p in ipairs({ { 0, 0 }, { .004, 1 }, { LOW, 1 }, { HIGH, 0 }, { 1, 0 }, { 1.001, 1 }, { LOW * 100, 1 }, { HIGH * 100, 0 }, { 100, 0 } }) do
    curve:AddPoint(p[1], p[2])
  end
end

local testAt, testUntil = 0, 0   -- /omdemon test: lights at testAt for 8 s (a 6 s countdown first)
local function update()
  local portrait = PetPortrait
  local okd, dead = pcall(UnitIsDeadOrGhost, 'pet')
  if not okd or (issecretvalue and issecretvalue(dead)) then dead = false end
  local shown = UnitExists('pet') and not dead and portrait and PetFrame and PetFrame:IsVisible()
  if not shown then root:Hide(); breathe:Stop(); sweep:Stop(); edgeBreathe:Stop(); litAt = nil; return end
  if not root:IsShown() then
    -- r = the gold ring's centre radius, which is what the art is drawn around (mockup: band 34-38 px, r 36).
    -- PetPortrait is only the picture inside the ring: measured in game 2026-11-10, its half-width lands at
    -- 23.7 px on the TV while the gold band runs 34-38 px, so r = half-width x 36/23.7 = x1.52.
    local r = (portrait:GetWidth() or 0) / 2 * 1.52
    if r <= 0 then return end
    root:ClearAllPoints(); root:SetPoint('CENTER', portrait, 'CENTER'); root:SetSize(4.4 * r, 4.4 * r)
    root:Show(); breathe:Play(); sweep:Play(); edgeMotion()
  end
  local now = GetTime()
  if now >= testAt and now < testUntil then gate:SetAlpha(1); litAt = litAt or now; edgeSettle(); return end
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
    gate:SetAlpha(h / m < .30 and 1 or 0)
  end
end

local ev = CreateFrame('Frame')
ev:SetScript('OnEvent', function(_, e, unit)
  if e == 'PLAYER_LOGIN' then
    if select(2, UnitClass('player')) ~= 'WARLOCK' then ev:UnregisterAllEvents(); return end
    buildCurve()
  end
  if e == 'UNIT_PET' or e == 'PLAYER_ENTERING_WORLD' then root:Hide() end   -- re-measure the portrait
  update()
end)
for _, e in ipairs({ 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'UNIT_PET', 'PET_UI_UPDATE', 'UNIT_HEALTH',
  'UNIT_MAXHEALTH', 'PLAYER_REGEN_ENABLED', 'PLAYER_REGEN_DISABLED', 'UI_SCALE_CHANGED', 'EDIT_MODE_LAYOUTS_UPDATED' }) do
  pcall(ev.RegisterEvent, ev, e)
end
-- A slow safety tick: health events cover changes, this catches frames moving or showing late.
local acc = 0
ev:SetScript('OnUpdate', function(_, dt) acc = acc + dt; if acc >= .1 then acc = 0; update() end end)

local function raw()   -- the pet's health % as the game reports it, when readable (out of combat)
  local ok, v = pcall(UnitHealthPercent, 'pet', false)
  if not ok or v == nil then return 'n/a' end
  if issecretvalue and issecretvalue(v) then return 'hidden' end
  local a = curve and select(2, pcall(UnitHealthPercent, 'pet', false, curve))
  return ('%s -> alpha %s'):format(tostring(v), (a ~= nil and not (issecretvalue and issecretvalue(a))) and tostring(a) or '?')
end

SLASH_OMASHUDEMON1 = '/omdemon'
SlashCmdList.OMASHUDEMON = function(msg)
  msg = (msg or ''):lower()
  if msg == 'test' then
    if InCombatLockdown() then print('|cffc08cffOmashu Demon|r: not in combat'); return end
    testAt = GetTime() + 6; testUntil = testAt + 8; litAt = nil; root:Hide(); update(); print('|cffc08cffOmashu Demon|r: the glow lights in 6 s, for 8 s')
  elseif msg == 'motion on' or msg == 'motion off' then
    OmashuDemonDB.reduced = (msg == 'motion off'); edgeMotion(); print('|cffc08cffOmashu Demon|r: motion ' .. (OmashuDemonDB.reduced and 'reduced (steady edge)' or 'full'))
  else
    local p = PetPortrait
    print(('|cffc08cffOmashu Demon|r: pet %s, frame %s, portrait %s, curve %s, health %s'):format(
      tostring(UnitExists('pet')), tostring(PetFrame and PetFrame:IsVisible()),
      p and ('%.1f x %.1f'):format(p:GetWidth(), p:GetHeight()) or 'none', tostring(curve ~= nil), raw()))
  end
end
