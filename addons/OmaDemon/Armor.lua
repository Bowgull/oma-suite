-- OmaDemon: armor missing (sheet 48 v2 A, approved 2026-11-13 "For armor missing A with a breathing to it").
-- A soft warm glow just inside your Demon Skin / Demon Armor / Fel Armor button, breathing slowly (2.4 s in and
-- out), while the armor is off. Out of combat and while alive only (the reminder rule, 2026-11-10). Gold, never
-- purple. No popup, no text. Found by spell on whatever bar holds it; the glow is our own small frame over the icon.
local _, ns = ...

local ARMORS = { ['Demon Skin'] = true, ['Demon Armor'] = true, ['Fel Armor'] = true }
local ART = 'Interface\\AddOns\\OmaDemon\\art\\armorglow'
local glows = {}          -- button -> our glow frame
local testUntil = 0

local function spellName(id)
  local ok, n = pcall(function() return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id)) end)
  if ok and type(n) == 'string' then return n end
end
local function armorOn()
  for n in pairs(ARMORS) do
    local ok, a = pcall(function()
      if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then return C_UnitAuras.GetAuraDataBySpellName('player', n, 'HELPFUL') end
      if AuraUtil and AuraUtil.FindAuraByName then return AuraUtil.FindAuraByName(n, 'player', 'HELPFUL') end
    end)
    if not ok then return true end      -- can't read it (secret): never nag on a guess
    if a then return true end
  end
  return false
end

-- every action button Blizzard knows about (its own list), plus the standard bar names as a fallback
local PREFIXES = { 'ActionButton', 'MultiBarBottomLeftButton', 'MultiBarBottomRightButton', 'MultiBarRightButton',
  'MultiBarLeftButton', 'MultiBar5Button', 'MultiBar6Button', 'MultiBar7Button' }
local function buttons()
  local seen, out = {}, {}
  local function add(b) if b and not seen[b] then seen[b] = true; out[#out + 1] = b end end
  local list = _G.ActionBarButtonEventsFrame and _G.ActionBarButtonEventsFrame.frames
  if type(list) == 'table' then for _, b in pairs(list) do add(b) end end
  for _, p in ipairs(PREFIXES) do for i = 1, 12 do add(_G[p .. i]) end end
  return out
end
local function armorButtons()
  local out = {}
  for _, b in ipairs(buttons()) do
    local ok, yes = pcall(function()
      local slot = b.action or (b.GetAttribute and b:GetAttribute('action'))
      if not slot or not GetActionInfo then return false end
      local kind, id = GetActionInfo(slot)
      return kind == 'spell' and ARMORS[spellName(id) or ''] or false
    end)
    if ok and yes then out[#out + 1] = b end
  end
  return out
end

local function glowFor(b)
  local g = glows[b]; if g then return g end
  g = CreateFrame('Frame', nil, UIParent); g:SetFrameStrata(b:GetFrameStrata() or 'MEDIUM'); g:SetFrameLevel((b:GetFrameLevel() or 1) + 5)
  local icon = b.icon or b.Icon or _G[(b:GetName() or '') .. 'Icon']
  g:SetAllPoints(icon or b)
  local t = g:CreateTexture(nil, 'OVERLAY'); t:SetTexture(ART); t:SetAllPoints(); t:SetBlendMode('ADD')
  local ag = t:CreateAnimationGroup(); ag:SetLooping('BOUNCE')
  local a = ag:CreateAnimation('Alpha'); a:SetFromAlpha(.25); a:SetToAlpha(.85); a:SetDuration(1.2); a:SetSmoothing('IN_OUT')
  g.tex, g.anim = t, ag; g:Hide()
  glows[b] = g; return g
end

local function refresh()
  local want = ns.groupDB().armor ~= false and not InCombatLockdown() and not UnitIsDeadOrGhost('player')
  local test = GetTime() < testUntil
  local missing = test or (want and not armorOn())
  for _, g in pairs(glows) do g:Hide(); g.anim:Stop() end
  if not (missing and (want or test)) then return end
  local reduced = ns.reduced and ns.reduced()
  for _, b in ipairs(armorButtons()) do
    local ok, vis = pcall(b.IsVisible, b)
    if ok and vis then
      local g = glowFor(b); g:Show()
      if reduced then g.tex:SetAlpha(.6) else g.tex:SetAlpha(1); g.anim:Play() end
    end
  end
end
ns.armorRefresh, ns.armorGlows = refresh, glows

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'PLAYER_REGEN_ENABLED', 'PLAYER_REGEN_DISABLED', 'UNIT_AURA',
  'ACTIONBAR_SLOT_CHANGED', 'ACTIONBAR_PAGE_CHANGED', 'UPDATE_BONUS_ACTIONBAR', 'SPELLS_CHANGED', 'PLAYER_DEAD',
  'PLAYER_ALIVE', 'PLAYER_UNGHOST' }) do pcall(ev.RegisterEvent, ev, e) end
local pending = false
local function soon() if pending then return end; pending = true; C_Timer.After(.2, function() pending = false; refresh() end) end
ev:SetScript('OnEvent', function(_, e, unit)
  if e == 'PLAYER_LOGIN' then
    if select(2, UnitClass('player')) ~= 'WARLOCK' then ev:UnregisterAllEvents(); return end
    soon()
  elseif e == 'UNIT_AURA' then
    if unit == 'player' and not InCombatLockdown() then soon() end
  elseif e == 'PLAYER_REGEN_DISABLED' then
    for _, g in pairs(glows) do g:Hide(); g.anim:Stop() end
  else soon() end
end)

table.insert(ns.onSetting, function(key, store) if store == 'group' and key == 'armor' then refresh() end end)

-- /omademon armor: show the glow for 8 s even with the armor on, to see where it sits
function ns.armorTest()
  testUntil = GetTime() + 8; refresh()
  local n = #armorButtons()
  ns.say(n > 0 and ('armor glow on ' .. n .. ' button' .. (n > 1 and 's' or '') .. ' for 8 s') or 'no Demon Skin or Demon Armor button found on your bars')
  C_Timer.After(8.1, refresh)
end
