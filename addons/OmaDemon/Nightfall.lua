-- OmaDemon: Nightfall (sheet 78, approved 2026-11-16; plan phase 7).
-- When Nightfall procs, Shadow Trance (your next Shadow Bolt is instant) shows as a violet breathing glow round your
-- portrait, gone the moment the Shadow Bolt uses it.
-- Blizzard's own AuraContainer reads the buff: ONE aura slot on 'player', HELPFUL, allowed only Shadow Trance's spell
-- IDs. The game shows the slot's button while the buff is up and hides it when it goes; the glow is that button, so
-- nothing here ever reads an aura or watches a timer.
-- Shadow Bolt's button: Blizzard's own proc glow (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW) may already light it on
-- Forever. Until that event has been seen once for Shadow Bolt, the same slot button also carries a violet glow over
-- your Shadow Bolt action button (a child frame pinned to our own anchor, which we move over the button out of
-- combat). Once Blizzard's glow is seen, ours shrinks to nothing for good (saved), so there are never two.
-- To check in game: a proc lights the portrait; and whether Blizzard's own Shadow Bolt glow shows (see CHANGES.md).
local _, ns = ...

local ART = 'Interface\\AddOns\\OmaDemon\\art\\'
local VIOLET = { .66, .38, 1 }
-- Shadow Trance, the Nightfall proc (Classic 17941; Forever keeps Classic's IDs for Classic spells). The name is
-- looked up as well, in case Forever gave it a new ID.
local IDS = { 17941 }
local NAMES = { 'Shadow Trance' }       -- never 'Nightfall': that's the talent, a passive that would light it for good
local N = { ids = IDS }
ns.nightfall = N

local function idSet()
  local set = {}
  for _, id in ipairs(IDS) do set[id] = true end
  for _, n in ipairs(NAMES) do
    local ok, id = pcall(function()
      if C_Spell and C_Spell.GetSpellInfo then local i = C_Spell.GetSpellInfo(n); return i and i.spellID end
      return GetSpellInfo and select(7, GetSpellInfo(n))
    end)
    if ok and type(id) == 'number' then set[id] = true end
  end
  return set
end

local function portrait()
  local pf = _G.PlayerFrame
  local p = _G.PlayerPortrait
  if not p and pf then
    local ok, x = pcall(function() return pf.PlayerFrameContainer.PlayerPortrait end)
    if ok then p = x end
  end
  return p or pf
end

-- our own anchor for the Shadow Bolt glow: moved over the button out of combat, size 0 when there's nothing to light
local sb = CreateFrame('Frame', 'OmaDemonNightfallAnchor', UIParent); sb:SetSize(0.001, 0.001); sb:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', -50, -50)
N.anchor = sb

local function breathe(tex, from, to)
  local ag = tex:CreateAnimationGroup(); ag:SetLooping('BOUNCE')
  local a = ag:CreateAnimation('Alpha'); a:SetFromAlpha(from); a:SetToAlpha(to); a:SetDuration(.9); a:SetSmoothing('IN_OUT')
  return ag
end

function N.button(b)
  pcall(b.EnableMouse, b, false)
  local p = portrait()
  local w = 64
  if p then local ok, pw = pcall(p.GetWidth, p); if ok and type(pw) == 'number' and pw > 0 then w = pw end end
  -- the portrait's glow, sized like OmaDemon's demon ring (Glow.lua): bloom outside, a lit rim on the portrait's edge
  local r = w / 2 * 1.52
  b:SetSize(4.4 * r, 4.4 * r); b:ClearAllPoints()
  if p then b:SetPoint('CENTER', p, 'CENTER') else b:SetPoint('CENTER', UIParent, 'CENTER') end
  pcall(b.SetFrameStrata, b, 'MEDIUM')
  local bloom = b:CreateTexture(nil, 'BACKGROUND'); bloom:SetTexture(ART .. 'bloom'); bloom:SetAllPoints(b)
  bloom:SetVertexColor(VIOLET[1], VIOLET[2], VIOLET[3]); bloom:SetBlendMode('ADD')
  local rim = b:CreateTexture(nil, 'ARTWORK'); rim:SetTexture(ART .. 'rim'); rim:SetAllPoints(b)
  rim:SetVertexColor(VIOLET[1], VIOLET[2], VIOLET[3]); rim:SetBlendMode('ADD')
  local anims = { breathe(bloom, .35, 1), breathe(rim, .6, 1) }
  -- Shadow Bolt's button: a frame of this button (so the game shows and hides it), pinned to our anchor
  local hold = CreateFrame('Frame', nil, b); hold:SetAllPoints(sb)
  local g = hold:CreateTexture(nil, 'OVERLAY'); g:SetTexture(ART .. 'armorglow'); g:SetAllPoints(hold)
  g:SetVertexColor(VIOLET[1], VIOLET[2], VIOLET[3]); g:SetBlendMode('ADD')
  anims[#anims + 1] = breathe(g, .4, 1)
  N.hold = hold
  local function play() if ns.reduced and ns.reduced() then return end; for _, ag in ipairs(anims) do ag:Play() end end
  play(); b:HookScript('OnShow', play)
end

local function blizzGlowSeen() return ns.groupDB().nfBlizz == true end

-- out of combat: put the anchor over the first Shadow Bolt button showing (unless Blizzard's own glow does it)
function N.placeButton()
  if InCombatLockdown() then return end
  sb:ClearAllPoints(); sb:SetSize(0.001, 0.001); sb:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', -50, -50)
  N.on = nil
  if blizzGlowSeen() or not ns.actionButtons then return end
  for _, btn in ipairs(ns.actionButtons()) do
    local ok, yes = pcall(function()
      if not btn:IsVisible() then return false end
      local slot = btn.action or (btn.GetAttribute and btn:GetAttribute('action'))
      if not slot or not GetActionInfo then return false end
      local kind, id = GetActionInfo(slot)
      return kind == 'spell' and ns.spellName(id) == 'Shadow Bolt'
    end)
    if ok and yes then
      local icon = btn.icon or btn.Icon or _G[(btn:GetName() or '') .. 'Icon'] or btn
      sb:ClearAllPoints(); sb:SetPoint('TOPLEFT', icon, 'TOPLEFT'); sb:SetPoint('BOTTOMRIGHT', icon, 'BOTTOMRIGHT')
      N.on = btn; return
    end
  end
end

function N.build()
  if N.container or InCombatLockdown() then return N.container end
  local ok, c = pcall(CreateFrame, 'AuraContainer', 'OmaDemonNightfall', UIParent, 'CustomAuraContainerTemplate')
  if not ok or not c then N.failed = tostring(c); return nil end
  pcall(c.SetEditModePreviewEnabled, c, false)
  c:SetSize(1, 1); c:SetPoint('CENTER', UIParent, 'CENTER')
  local okS, err = pcall(c.AddAuraSlot, c, 'nightfall', 'HELPFUL', { initializeFrame = N.button, candidateFilters = { includeSpellIDs = idSet() } })
  if not okS then N.failed = tostring(err); c:Hide(); return nil end
  N.container = c
  c:SetUnit('player')
  N.placeButton()
  return c
end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'PLAYER_REGEN_ENABLED', 'ACTIONBAR_SLOT_CHANGED',
  'ACTIONBAR_PAGE_CHANGED', 'UPDATE_BONUS_ACTIONBAR', 'SPELLS_CHANGED', 'SPELL_ACTIVATION_OVERLAY_GLOW_SHOW' }) do pcall(ev.RegisterEvent, ev, e) end
local pending = false
local function soon() if pending then return end; pending = true; C_Timer.After(.2, function() pending = false; N.placeButton() end) end
ev:SetScript('OnEvent', function(_, e, id)
  if e == 'PLAYER_LOGIN' then
    if select(2, UnitClass('player')) ~= 'WARLOCK' then ev:UnregisterAllEvents(); return end
    N.build()
  elseif e == 'SPELL_ACTIVATION_OVERLAY_GLOW_SHOW' then
    -- Blizzard lights Shadow Bolt itself on Forever: ours stands down for good (shrinks out of combat)
    if ns.spellName and ns.spellName(id) == 'Shadow Bolt' and not blizzGlowSeen() then
      ns.groupDB().nfBlizz = true; N.blizzSeenAt = GetTime(); soon()
    end
  elseif not N.container then N.build()
  else soon() end
end)
