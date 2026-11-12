-- Checks the UI fakes themselves (tests/ui.lua), so later failures are about the add-on, not the harness.
local function setup(W)
  local UI = require('ui'); UI.install(); UI.plates(); UI.auras(); UI.settings()
  return UI
end
local function noop() end
local function container(UI, parent)
  local c = CreateFrame('AuraContainer', nil, parent, 'CustomAuraContainerTemplate')
  c:AddAuraGroup('corruption', 'HARMFUL|PLAYER', { initializeFrame = noop, candidateFilters = { includeSpellIDs = { [172] = true } }, maxFrameCount = 2 })
  c:AddAuraGroup('others', 'HARMFUL|!PLAYER', { initializeFrame = noop, maxFrameCount = 3 })
  return c
end
return {
  ['aura container: 10 buttons per group up front, initializeFrame on each, whatever the max'] = function(W, T)
    local UI = setup(W); local n = 0
    local c = CreateFrame('AuraContainer', nil, UIParent, 'CustomAuraContainerTemplate')
    c:AddAuraGroup('a', 'HARMFUL|PLAYER', { initializeFrame = function() n = n + 1 end, maxFrameCount = 2 })
    T.eq(n, 10); T.eq(c.built, 10); T.eq(UI.aura.buttons, 10)
    T.ok(not pcall(c.AddAuraGroup, c, 'a', 'HARMFUL', { initializeFrame = noop }), 'a repeated key raises')
    T.ok(not pcall(c.AddAuraGroup, c, 'b', 'HARMFUL', {}), 'no initializeFrame raises')
    T.ok(not pcall(CreateFrame, 'AuraContainer', nil, UIParent, 'SomeOtherTemplate'), 'needs the template')
  end,
  ['aura container: same unit is a no-op, a new unit re-reads; UpdateAllAuras re-reads'] = function(W, T)
    local UI = setup(W); local c = container(UI, UIParent)
    W.units.nameplate1 = { guid = 'A', enemy = true, auras = { 172 }, otherAuras = { 980, 348 } }
    c:SetUnit('nameplate1'); T.eq(UI.reads(c), 1)
    c:SetUnit('nameplate1'); T.eq(UI.reads(c), 1, 'same token: nothing')
    T.eq(#UI.showing(c).corruption, 1); T.eq(#UI.showing(c).others, 2, "other players' auras in the !PLAYER group")
    W.units.nameplate1.auras = {}
    T.eq(#UI.showing(c).corruption, 1, 'stale until something re-reads')
    c:UpdateAllAuras(); T.eq(UI.reads(c), 2); T.eq(#UI.showing(c).corruption, 0)
  end,
  ['aura container: showing a parent re-reads it and its child containers; hidden ones do not'] = function(W, T)
    local UI = setup(W)
    local anchor = CreateFrame('Frame', nil, UIParent); anchor:Hide()
    local ring = container(UI, anchor); local main = container(UI, ring)
    T.eq(UI.reads(ring) + UI.reads(main), 0, 'made under a hidden frame: no reads')
    anchor:Show(); T.eq(UI.reads(ring), 1); T.eq(UI.reads(main), 1)
    ring:Hide(); ring:Show(); T.eq(UI.reads(ring), 2); T.eq(UI.reads(main), 2, 'hide/show cascades to the child')
    main:Hide(); ring:Hide(); ring:Show(); T.eq(UI.reads(main), 2, 'a hidden child stays quiet')
    T.ok(UI.mainOf(ring) == main and #UI.ringContainers() == 1, 'a pair is a ring with its main as a child')
  end,
  ['aura container: groups switch on and off, filters change, unknown groups raise'] = function(W, T)
    local UI = setup(W); local c = container(UI, UIParent)
    W.units.target = { guid = 'A', enemy = true, auras = { 172 } }; c:SetUnit('target')
    c:SetAuraGroupEnabled('corruption', false); T.eq(#UI.showing(c).corruption, 0)
    c:SetAuraGroupEnabled('corruption', true); T.eq(#UI.showing(c).corruption, 1)
    c:SetAuraGroupCandidateFilters('corruption', { includeSpellIDs = {} }); T.eq(#UI.showing(c).corruption, 0)
    T.ok(not pcall(c.SetAuraGroupEnabled, c, 'nope', true), 'unknown group raises')
  end,
  ['plates: one stable plate per nameplate token, found from any token on the same mob'] = function(W, T)
    local UI = setup(W)
    W.units.nameplate3 = { guid = 'A', enemy = true }; W.units.target = W.units.nameplate3
    local p = C_NamePlate.GetNamePlateForUnit('nameplate3')
    T.ok(p and p == C_NamePlate.GetNamePlateForUnit('target'), 'same frame both ways')
    T.ok(p.UnitFrame.HealthBarsContainer.healthBar:GetStatusBarTexture(), 'a health bar with a fill')
    T.eq(C_NamePlate.GetNamePlateForUnit('focus'), nil)
  end,
  ['settings: a missing default, a wrong type or an unknown setting raises'] = function(W, T)
    local UI = setup(W)
    local cat = Settings.RegisterVerticalLayoutCategory('X'); local db = {}
    T.ok(not pcall(Settings.RegisterAddOnSetting, cat, 'X_a', 'a', db, Settings.VarType.Boolean, 'A', nil), 'no default')
    T.ok(not pcall(Settings.RegisterAddOnSetting, cat, 'X_b', 'b', db, Settings.VarType.Number, 'B', 'x'), 'wrong type')
    T.ok(not pcall(Settings.SetOnValueChangedCallback, 'X_nope', noop), 'unknown setting')
    local s = Settings.RegisterAddOnSetting(cat, 'X_c', 'c', db, Settings.VarType.String, 'C', 'one')
    local function opts() local c = Settings.CreateControlTextContainer(); c:Add('two', 'Two'); return c:GetData() end
    T.ok(not pcall(Settings.CreateDropdown, cat, s, opts), 'default not among the options')
    T.ok(not pcall(Settings.CreateCheckbox, cat, s), 'a checkbox on a string setting')
    local n = Settings.RegisterAddOnSetting(cat, 'X_n', 'n', db, Settings.VarType.Number, 'N', 7)
    T.ok(not pcall(Settings.CreateSlider, cat, n, Settings.CreateSliderOptions(0, 5, 1)), 'default off the slider')
    local hit; Settings.SetOnValueChangedCallback('X_n', function(_, v) hit = v end); n:SetValue(3)
    T.eq(hit, 3); T.eq(db.n, 3, 'writes the saved table')
  end,
  ['widgets remember what they were told; calls are counted'] = function(W, T)
    local UI = setup(W)
    local f = CreateFrame('StatusBar', nil, UIParent); local t = f:CreateTexture()
    local c0 = UI.calls
    f:SetMinMaxValues(0, 50); f:SetValue(20); t:SetVertexColor(.1, .2, .3); f:Hide()
    T.eq(f:GetValue(), 20); T.eq(select(2, f:GetMinMaxValues()), 50); T.eq(t._r, .1)
    T.ok(not f:IsShown() and not t:IsVisible(), 'hidden, and its texture with it')
    T.eq(UI.calls - c0, 8, 'every widget call counted')
  end,
}
