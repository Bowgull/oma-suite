-- OmaDemon: debuffs on you (sheet 78, approved 2026-11-16; plan phase 7).
-- "Debuffs on you: soft squares just above your bars, glowing in their type's colour; the magic one breathes because
-- your Felhunter can take it off."
-- Blizzard's own AuraContainer (CustomAuraContainerTemplate) on 'player', HARMFUL, reads the auras and shows and hides
-- the squares; this file only builds each square's look once, in initializeFrame (aura buttons are locked after it).
-- Nothing hidden is ever read here: the GAME tints each glow by the debuff's type (AddDispelTypeTexture with a colour
-- map, the same route as OmaDoomed's soft squares, RingsLook.lua glowBehind). The breathing light is a second
-- type-tinted texture whose map is clear for every type except Magic, so only magic debuffs breathe.
-- The container is made out of combat (containers can't be made in combat) and placed just above your action bars.
local _, ns = ...

local ART = 'Interface\\AddOns\\OmaDemon\\art\\'
local SIZE = 44
local GAP = 6
local MAX = 8
local DISPEL_RGB = { Magic = { .24, .61, 1 }, Curse = { .64, .21, .93 }, Disease = { .6, .4, 0 }, Poison = { .12, .75, .12 },
  Bleed = { .82, .1, .1 }, None = { .82, .1, .1 } }
local D = { size = SIZE, max = MAX }
ns.debuffs = D

local maps = {}
local function colorMap(which)
  if maps[which] or not CreateColor then return maps[which] end
  local m = {}
  for k, c in pairs(DISPEL_RGB) do
    -- 'breath': only Magic has any light; every other type is fully clear
    local a = (which == 'breath' and k ~= 'Magic') and 0 or 1
    m[k] = CreateColor(c[1], c[2], c[3], a)
  end
  maps[which] = m; return m
end
-- Blizzard's style that keeps our own glow art and only tints it ('PreserveAsset'); found by name, any enum spelling
local function preserveStyle()
  for _, t in pairs(Enum or {}) do if type(t) == 'table' and t.PreserveAsset ~= nil then return t.PreserveAsset end end
end
local function tintByType(b, tex, which)
  if not b.AddDispelTypeTexture then return false end
  if which == 'breath' and not colorMap(which) then return false end   -- without our map every type would breathe
  return (pcall(b.AddDispelTypeTexture, b, tex, { style = preserveStyle(), showWhenHarmful = true,
    showWithoutDispelType = true, customDispelColorMap = colorMap(which) }))
end

-- hover: Blizzard's own tooltip if the button has one, otherwise the aura by its instance on 'player'
local function onEnter(self)
  if not GameTooltip then return end
  pcall(GameTooltip.SetOwner, GameTooltip, self, 'ANCHOR_TOP')
  local ok = pcall(function()
    local id = self.auraInstanceID or (self.GetAuraInstanceID and self:GetAuraInstanceID())
    if id and GameTooltip.SetUnitDebuffByAuraInstanceID then GameTooltip:SetUnitDebuffByAuraInstanceID('player', id)
    elseif id and GameTooltip.SetUnitAuraByAuraInstanceID then GameTooltip:SetUnitAuraByAuraInstanceID('player', id)
    else error('no aura id') end
  end)
  if ok then pcall(GameTooltip.Show, GameTooltip) else pcall(GameTooltip.Hide, GameTooltip) end
end
local function onLeave() if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end end
D.onEnter, D.onLeave = onEnter, onLeave

function D.button(b)
  b:SetSize(SIZE, SIZE)
  -- the icon in a soft square (Blizzard's square, corners 20% of the side, no frame)
  local icon = b:CreateTexture(nil, 'ARTWORK', nil, 0)
  icon:SetSize(SIZE, SIZE); icon:SetPoint('CENTER', b, 'CENTER'); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local m = b:CreateMaskTexture(); m:SetTexture(ART .. 'softsq_mask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE', 'TRILINEAR'); m:SetAllPoints(icon)
  icon:AddMaskTexture(m)
  local edge = b:CreateTexture(nil, 'ARTWORK', nil, 2); edge:SetTexture(ART .. 'softsq_edge', nil, nil, 'TRILINEAR'); edge:SetAllPoints(icon)
  -- the soft glow behind it, in the debuff's type colour (a quiet red if this client refuses the tint)
  local glow = b:CreateTexture(nil, 'BACKGROUND', nil, -6); glow:SetTexture(ART .. 'softsq_glow', nil, nil, 'TRILINEAR')
  glow:SetSize(SIZE * 1.5, SIZE * 1.5); glow:SetPoint('CENTER', b, 'CENTER'); glow:SetBlendMode('ADD')
  glow:SetVertexColor(.82, .1, .1, .6)
  tintByType(b, glow, 'glow')
  -- the breath: a wider glow, clear unless the debuff is Magic, swelling in and out (2.4 s round, like the armor glow)
  local breath = b:CreateTexture(nil, 'BACKGROUND', nil, -7); breath:SetTexture(ART .. 'softsq_glow', nil, nil, 'TRILINEAR')
  breath:SetSize(SIZE * 1.9, SIZE * 1.9); breath:SetPoint('CENTER', b, 'CENTER'); breath:SetBlendMode('ADD')
  breath:SetVertexColor(0, 0, 0, 0)
  if tintByType(b, breath, 'breath') then
    local ag = breath:CreateAnimationGroup(); ag:SetLooping('BOUNCE')
    local a = ag:CreateAnimation('Alpha'); a:SetFromAlpha(.15); a:SetToAlpha(1); a:SetDuration(1.2); a:SetSmoothing('IN_OUT')
    if not (ns.reduced and ns.reduced()) then ag:Play() else breath:SetAlpha(.6) end   -- a looping group keeps going; no OnShow hook (Forever blocks it on aura buttons)
    b.omBreath = ag
  end
  -- time left: the game's own countdown on a clear cooldown (no swipe, no edge)
  local cd = CreateFrame('Cooldown', nil, b); cd:SetAllPoints(b)
  pcall(cd.SetDrawSwipe, cd, false); pcall(cd.SetDrawEdge, cd, false); pcall(cd.SetUseAuraDisplayTime, cd, true)
  pcall(b.SetIcon, b, icon); pcall(b.SetDurationCooldown, b, cd)
  -- stacks, bottom right, when the client offers them
  if b.SetApplicationsText then
    local top = CreateFrame('Frame', nil, b); top:SetAllPoints(b); top:SetFrameLevel(b:GetFrameLevel() + 3)
    local n = top:CreateFontString(nil, 'OVERLAY'); n:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF', 14, 'OUTLINE')
    n:SetPoint('BOTTOMRIGHT', b, 'BOTTOMRIGHT', -2, 2)
    pcall(b.SetApplicationsText, b, n)
  end
  -- hover shows the game's own tooltip: the game sets the button's OnEnter after this, and ours would block it
  -- ("cannot replace a forbidden script handler", BugSack 2026-11-17). Mouse motion only, so clicks pass through.
  if b.EnableMouseMotion then pcall(b.EnableMouseMotion, b, true) else pcall(b.EnableMouse, b, true) end
end

-- just above the action bars: the highest bottom bar that is showing, else the screen's bottom centre
local BARS = { 'MultiBarBottomRight', 'MultiBarBottomLeft', 'MainActionBar', 'MainMenuBar' }
local function barTop()
  local best, top
  for _, n in ipairs(BARS) do
    local f = _G[n]
    local ok, vis, t = pcall(function() return f:IsVisible(), f:GetTop() end)
    if ok and vis and type(t) == 'number' and (not top or t > top) then best, top = f, t end
  end
  return best
end
function D.place()
  local c = D.container; if not c or InCombatLockdown() then return end
  c:ClearAllPoints()
  local bar = barTop()
  if bar then c:SetPoint('BOTTOMLEFT', bar, 'TOPLEFT', 0, 12) else c:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOM', -(SIZE + GAP) * MAX / 2, 150) end
  D.bar = bar
end

function D.build()
  if D.container or InCombatLockdown() then return D.container end
  local ok, c = pcall(CreateFrame, 'AuraContainer', 'OmaDemonDebuffs', UIParent, 'CustomAuraContainerTemplate')
  if not ok or not c then D.failed = tostring(c); return nil end
  pcall(c.SetEditModePreviewEnabled, c, false)
  c:SetFlowLayoutAnchorPoint('BOTTOMLEFT'); c:SetFlowLayoutGrowthDirection(1, 1)
  c:SetFlowLayoutMaximumLineSize((SIZE + GAP) * MAX)
  local okG, err = pcall(c.AddAuraGroup, c, 'debuffs', 'HARMFUL', { initializeFrame = D.button, maxFrameCount = MAX,
    layout = { groupSpacing = GAP } })
  if not okG then D.failed = tostring(err); c:Hide(); return nil end
  pcall(c.SetFrameStrata, c, 'MEDIUM')
  D.container = c
  D.place()
  c:SetUnit('player')
  return c
end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'PLAYER_REGEN_ENABLED', 'EDIT_MODE_LAYOUTS_UPDATED',
  'ACTIONBAR_SHOWGRID', 'ACTIONBAR_HIDEGRID' }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript('OnEvent', function(_, e)
  if e == 'PLAYER_LOGIN' and select(2, UnitClass('player')) ~= 'WARLOCK' then ev:UnregisterAllEvents(); return end
  if not D.container then D.build() else D.place() end
end)
