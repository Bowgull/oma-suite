-- OmaDemon: debuffs on you (sheet 104 v7 + sheet 103 Plasma, approved 2026-11-17 "Yes, build it").
-- Centred above your action bars, one fixed spot per type: magic, curse, poison, disease, then anything else. Each is
-- Blizzard's own action-button frame (the game's atlas, nothing shipped) with the Plasma you picked flowing round it in
-- the type's colour. The spot says the type, so a click knows what it was without reading anything hidden: click one
-- and OmaDemon asks the groupmate who can remove it, in your voice (Lines.lua ns.helpLine). The click is your own
-- press, so the game lets the line go out even in a dungeon fight.
-- Blizzard's own AuraContainer reads the auras and shows and hides each spot (AddAuraSlot, one per type, filtered by
-- dispel type inside the game's code). This file only builds each spot's look once, in initializeFrame (aura buttons
-- are locked after it), and our own click buttons sit on top.
local _, ns = ...

local ART = 'Interface\\AddOns\\OmaDemon\\art\\'
local AB = 'Interface\\HUD\\UIActionBar2x'          -- Blizzard's action-button frame and hover (the game's own file)
local FRAME_TC = { 358 / 512, 456 / 512, 432 / 2048, 539 / 2048 }
local HOVER_TC = { 358 / 512, 456 / 512, 546 / 2048, 640 / 2048 }
local SIZE, GAP = 44, 6
local PLASMA = SIZE * 78.6 / 44                      -- the loop's canvas (sheet 103), centred on the square
local TYPES = {
  { key = 'magic', dispel = 'Magic' }, { key = 'curse', dispel = 'Curse' }, { key = 'poison', dispel = 'Poison' },
  { key = 'disease', dispel = 'Disease' }, { key = 'other' },
}
local D = { size = SIZE, types = TYPES }
ns.debuffs = D

local function spotX(i) return (i - (#TYPES + 1) / 2) * (SIZE + GAP) end

-- one spot's look: plasma behind, the icon, Blizzard's frame over it, the game's own countdown and stacks
function D.slotInit(t, i, holder)
  return function(b)
    b:SetSize(SIZE, SIZE); pcall(b.EnableMouse, b, false)
    b:ClearAllPoints(); b:SetPoint('CENTER', holder, 'CENTER', spotX(i), 0)
    if t.dispel then
      local p = b:CreateTexture(nil, 'BACKGROUND', nil, -6)
      p:SetTexture(ART .. 'plasma_' .. t.key, nil, nil, 'TRILINEAR'); p:SetSize(PLASMA, PLASMA); p:SetPoint('CENTER', b, 'CENTER')
      local ag = p:CreateAnimationGroup(); ag:SetLooping('REPEAT')
      local ok, fb = pcall(ag.CreateAnimation, ag, 'FlipBook')
      if ok and fb then
        pcall(fb.SetFlipBookRows, fb, 4); pcall(fb.SetFlipBookColumns, fb, 4); pcall(fb.SetFlipBookFrames, fb, 16)
        pcall(fb.SetDuration, fb, 2.2)
        if ns.reduced and ns.reduced() then p:SetTexCoord(0, .25, 0, .25) else ag:Play() end   -- started once: allowed
      else p:SetTexCoord(0, .25, 0, .25) end
      b.omPlasma = ag
    end
    local icon = b:CreateTexture(nil, 'ARTWORK', nil, 0)
    icon:SetSize(SIZE, SIZE); icon:SetPoint('CENTER', b, 'CENTER'); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local fr = b:CreateTexture(nil, 'OVERLAY', nil, 1)
    fr:SetTexture(AB); fr:SetTexCoord(FRAME_TC[1], FRAME_TC[2], FRAME_TC[3], FRAME_TC[4])
    fr:SetSize(SIZE * 98 / 77, SIZE * 107 / 77); fr:SetPoint('TOPLEFT', icon, 'TOPLEFT', -SIZE * 8 / 77, SIZE * 16 / 77)
    local cd = CreateFrame('Cooldown', nil, b); cd:SetAllPoints(b)
    pcall(cd.SetDrawSwipe, cd, false); pcall(cd.SetDrawEdge, cd, false); pcall(cd.SetUseAuraDisplayTime, cd, true)
    pcall(b.SetIcon, b, icon); pcall(b.SetDurationCooldown, b, cd)
    if b.SetApplicationCount then   -- the stack count (the game's name for it; SetApplicationsText never existed)
      local top = CreateFrame('Frame', nil, b); top:SetAllPoints(b); top:SetFrameLevel(b:GetFrameLevel() + 3)
      local n = top:CreateFontString(nil, 'OVERLAY'); n:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF', 14, 'OUTLINE')
      n:SetPoint('BOTTOMRIGHT', b, 'BOTTOMRIGHT', -2, 2)
      pcall(b.SetApplicationCount, b, n)
    end
  end
end

-- ---------- our click buttons, one over each spot you can ask help for ----------
-- out of combat the tooltip shows what is there (aura data is plain then); in a fight only the hint
local function firstOfType(dispel)
  if InCombatLockdown() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
  for i = 1, 40 do
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, 'player', i, 'HARMFUL')
    if not ok or not a then return end
    if a.dispelName == dispel then return a, i end
  end
end
D.firstOfType = firstOfType
local function makeClick(t, i, holder)
  local btn = CreateFrame('Button', 'OmaDemonHelp' .. t.key, holder)
  btn:SetSize(SIZE, SIZE); btn:SetPoint('CENTER', holder, 'CENTER', spotX(i), 0)
  btn:SetFrameLevel(holder:GetFrameLevel() + 30)
  btn:RegisterForClicks('LeftButtonUp')
  local hv = btn:CreateTexture(nil, 'HIGHLIGHT')
  hv:SetTexture(AB); hv:SetTexCoord(HOVER_TC[1], HOVER_TC[2], HOVER_TC[3], HOVER_TC[4])
  hv:SetSize(SIZE * 98 / 77, SIZE * 94 / 77); hv:SetPoint('CENTER', btn, 'CENTER'); hv:SetBlendMode('ADD')
  btn:SetScript('OnClick', function()
    if not InCombatLockdown() and not firstOfType(t.dispel) then return end   -- nothing there (we can tell out of a fight)
    if ns.askHelp then ns.askHelp(t.key) end
  end)
  btn:SetScript('OnEnter', function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, 'ANCHOR_TOP')
    local _, idx = firstOfType(t.dispel)
    if idx and GameTooltip.SetUnitDebuff then pcall(GameTooltip.SetUnitDebuff, GameTooltip, 'player', idx) end
    GameTooltip:AddLine('Click: ask for help in group chat', 1, .82, 0)
    GameTooltip:Show()
  end)
  btn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
  return btn
end

-- just above the action bars: the highest bottom bar that is showing, else the screen's bottom centre
local BARS = { 'MultiBarBottomRight', 'MultiBarBottomLeft', 'MainActionBar', 'MainMenuBar' }
local function barTop()
  local best, top
  for _, n in ipairs(BARS) do
    local f = _G[n]
    local ok, vis, t = pcall(function() return f:IsVisible(), f:GetTop() and f:GetTop() * f:GetEffectiveScale() end)
    if ok and vis and type(t) == 'number' and (not top or t > top) then best, top = f, t end
  end
  return best, top
end
function D.place()
  local h = D.holder; if not h or InCombatLockdown() then return end
  h:ClearAllPoints()
  local bar, top = barTop()
  local s = UIParent:GetEffectiveScale() or 1
  if bar and top then h:SetPoint('BOTTOM', UIParent, 'BOTTOM', 0, top / s + 12) else h:SetPoint('BOTTOM', UIParent, 'BOTTOM', 0, 150) end
  D.bar = bar
end

function D.build()
  if D.container or InCombatLockdown() then return D.container end
  local h = CreateFrame('Frame', 'OmaDemonDebuffRow', UIParent); h:SetSize(#TYPES * (SIZE + GAP), SIZE)
  pcall(h.SetFrameStrata, h, 'MEDIUM')
  D.holder = h
  local ok, c = pcall(CreateFrame, 'AuraContainer', 'OmaDemonDebuffs', h, 'CustomAuraContainerTemplate')
  if not ok or not c then D.failed = tostring(c); return nil end
  pcall(c.SetEditModePreviewEnabled, c, false)
  c:SetAllPoints(h)
  local others = {}
  for _, t in ipairs(TYPES) do if t.dispel then others[t.dispel] = true end end
  D.clicks = {}
  for i, t in ipairs(TYPES) do
    local filters = t.dispel and { includeDispelTypes = { [t.dispel] = true } } or { excludeDispelTypes = others }
    local okS, err = pcall(c.AddAuraSlot, c, t.key, 'HARMFUL', { initializeFrame = D.slotInit(t, i, h), candidateFilters = filters })
    if not okS then D.failed = tostring(err); c:Hide(); return nil end
    if t.dispel then D.clicks[t.key] = makeClick(t, i, h) end
  end
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
