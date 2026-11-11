-- OmaDoomed's settings page (sheet 37, Joshua 2026-11-11: "Yes, build it"): Options > AddOns > Oma > OmaDoomed, built
-- only from Blizzard's own settings controls so the controller, search and Defaults work. Values live in OmaDoomedDB
-- (kill bar) and OmaDoomedDB.rings (rings). Every change calls ns.applySetting(key) so it shows at once.
local ADDON, ns = ...

ns.DEFAULTS = {
  doomed = true, skull = true, cast = 'charging', tick = 'ember', low = 3, lowlook = 'breathe',
}
ns.RING_DEFAULTS = {
  where = 'enemy', squares = 'notmine', which = 'all', size = 40, alpha = 100, othersAlpha = 55,
}

-- one shared "Oma" parent for every Oma add-on (agreed with the OmaDemon session): whoever loads first makes it
local function omaParent()
  local O = _G.OmaSuite or {}; _G.OmaSuite = O
  if not O.parent then
    O.parent = Settings.RegisterVerticalLayoutCategory('Oma')
    local f = CreateFrame('Frame'); f:RegisterEvent('PLAYER_LOGIN')
    f:SetScript('OnEvent', function() if not O.registered then O.registered = true; Settings.RegisterAddOnCategory(O.parent) end end)
  end
  return O.parent
end

local cat, layout
-- notches belong to OmaDoomed's sliders only: hide one left on a recycled slider frame
if SettingsSliderControlMixin and SettingsSliderControlMixin.Init then
  hooksecurefunc(SettingsSliderControlMixin, 'Init', function(frame) if frame.omaNotch then frame.omaNotch:Hide() end end)
end
local function header(text)
  if CreateSettingsListSectionHeaderInitializer then layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text)) end
end
local function reg(tbl, key, default, vartype, label)
  if tbl[key] == nil then tbl[key] = default end
  local s = Settings.RegisterAddOnSetting(cat, 'OMADOOMED_' .. key, key, tbl, vartype, label, default)
  Settings.SetOnValueChangedCallback('OMADOOMED_' .. key, function() if ns.applySetting then local ok, e = pcall(ns.applySetting, key); if not ok then ns.err('setting ' .. key .. ': ' .. tostring(e)) end end end)
  return s
end
local function child(init, parent)
  if parent and init.SetParentInitializer then init:SetParentInitializer(parent.init, function() return parent.setting:GetValue() end) end
end
local function check(tbl, key, label, tip, parent)
  local setting = reg(tbl, key, (tbl == ns.db and ns.DEFAULTS or ns.RING_DEFAULTS)[key], Settings.VarType.Boolean, label)
  local init = Settings.CreateCheckbox(cat, setting, tip); child(init, parent)
  return { init = init, setting = setting }
end
local function slider(tbl, key, label, lo, hi, step, tip, fmt, parent)
  local setting = reg(tbl, key, (tbl == ns.db and ns.DEFAULTS or ns.RING_DEFAULTS)[key], Settings.VarType.Number, label)
  local opts = Settings.CreateSliderOptions(lo, hi, step)
  opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
  local init = Settings.CreateSlider(cat, setting, opts, tip); child(init, parent)
  -- a small gold notch on the track marks the default (Joshua 2026-11-11: "a default spot for sliders")
  local def = (tbl == ns.db and ns.DEFAULTS or ns.RING_DEFAULTS)[key]
  local orig = init.InitFrame
  init.InitFrame = function(self, frame)
    orig(self, frame)
    local sl = frame.SliderWithSteppers and frame.SliderWithSteppers.Slider
    if not sl then return end
    local n = frame.omaNotch
    if not n then n = sl:CreateTexture(nil, 'OVERLAY'); n:SetColorTexture(1, .82, .25, .9); frame.omaNotch = n end
    n:SetParent(sl); n:SetSize(2, 10); n:Show()
    local function placeIt()
      local w = sl:GetWidth(); if not w or w <= 0 then return end
      n:ClearAllPoints(); n:SetPoint('CENTER', sl, 'LEFT', w * (def - lo) / (hi - lo), 0)
    end
    placeIt(); C_Timer.After(0, placeIt)
  end
  return { init = init, setting = setting }
end
local function drop(tbl, key, label, choices, tip, parent)
  local setting = reg(tbl, key, (tbl == ns.db and ns.DEFAULTS or ns.RING_DEFAULTS)[key], Settings.VarType.String, label)
  local function options()
    local c = Settings.CreateControlTextContainer()
    for _, ch in ipairs(choices) do c:Add(ch[1], ch[2]) end
    return c:GetData()
  end
  local make = Settings.CreateDropdown or Settings.CreateDropDown
  local init = make(cat, setting, options, tip); child(init, parent)
  return { init = init, setting = setting }
end
local pct = function(v) return ('%d%%'):format(v) end

function ns.buildSettings()
  local db, rdb = ns.db, OmaDoomedDB.rings
  for k, v in pairs(ns.DEFAULTS) do if db[k] == nil then db[k] = v end end
  for k, v in pairs(ns.RING_DEFAULTS) do if rdb[k] == nil then rdb[k] = v end end
  cat, layout = Settings.RegisterVerticalLayoutSubcategory(omaParent(), 'OmaDoomed')
  ns.settingsCategory = cat

  local pv = ns.previewInitializer and ns.previewInitializer(); if pv then layout:AddInitializer(pv) end
  header('Kill bar')
  local bar = check(db, 'doomed', 'Kill bar', "Your DoTs' coming damage, in their own colours, inside the enemy's health bar.")
  check(db, 'skull', 'Skull', 'A skull and bones on the portrait ring when your DoTs alone will finish the enemy.', bar)
  drop(db, 'cast', 'While you cast', {
    { 'charging', 'Charging' }, { 'smoulder', 'Smoulder' }, { 'stripes', 'Drifting stripes' }, { 'motes', 'Motes' }, { 'plain', 'Plain' } },
    "Charging: the piece fills with your cast bar, an ember at its front. Smoulder: its colour rises out of the dark. Drifting stripes: stripes sliding toward the green. Motes: small pixels drifting through it. Plain: a dim piece that turns solid when the spell lands.", bar)
  drop(db, 'tick', 'Tick light', { { 'ember', 'Ember' }, { 'cinders', 'Cinders' }, { 'essence', 'Essence' }, { 'plain', 'Plain' } },
    "Ember: the bitten part glows in its own colour and settles. Cinders: the same glow, and small embers lift off it. Essence: a soft curl of shadow haze rises from it. Plain: it just slides shut.", bar)
  slider(db, 'low', 'Ending soon', 2, 5, 1, "A DoT's piece and ring number turn gold for its last seconds.", function(v) return ('%d s'):format(v) end, bar)
  drop(db, 'lowlook', 'Ending soon look', { { 'breathe', 'Breathing gold' }, { 'steady', 'Steady gold' } },
    "How the gold looks in a DoT's last seconds: breathing on the rings' beat, or steady.", bar)

  header('Rings')
  drop(rdb, 'where', 'Where the rings show', { { 'enemy', 'Above the enemy' }, { 'split', 'Target on its frame, others overhead' }, { 'frame', 'Above the target frame' }, { 'both', 'Both' } },
    'Above the enemy in the world, above its target frame, or both. Target on its frame, others overhead: your target\'s rings sit on its frame next to the kill bar, every other enemy keeps its rings over its head.')
  drop(rdb, 'squares', "Blizzard's squares", { { 'notmine', 'All but my DoTs' }, { 'all', 'All' }, { 'hide', 'Hide' } },
    "Blizzard's own buff and debuff squares on the target frame. All but my DoTs keeps everyone else's debuffs, stuns and the enemy's buffs, and leaves out yours (the rings already show them).")
  drop(rdb, 'which', 'Which enemies', { { 'all', 'Every enemy' }, { 'target', 'Only your target' }, { 'combat', 'Only in combat' } },
    "Rings on every enemy, only your target, or only while you're fighting.")
  slider(rdb, 'size', 'Ring size', 28, 60, 2, "How big your rings are. 40 is Blizzard's own size.", tostring)
  slider(rdb, 'alpha', 'Ring opacity', 20, 100, 5, 'How solid your own rings are.', pct)
  slider(rdb, 'othersAlpha', "Other players' DoTs", 0, 100, 5, "How solid other players' rings are. 0 hides them.",
    function(v) return v == 0 and 'Hidden' or ('%d%%'):format(v) end)
end

local f = CreateFrame('Frame'); f:RegisterEvent('ADDON_LOADED')
f:SetScript('OnEvent', function(self, _, name)
  if name ~= ADDON then return end
  self:UnregisterAllEvents()
  OmaDoomedDB = OmaDoomedDB or {}; OmaDoomedDB.rings = OmaDoomedDB.rings or {}
  ns.db = ns.db or OmaDoomedDB
  local ok, err = pcall(ns.buildSettings)
  if not ok then print('|cffb48cffOmaDoomed:|r settings page failed: ' .. tostring(err)) end
end)

-- /omadoomed options
function ns.openSettings() if ns.settingsCategory and Settings.OpenToCategory then Settings.OpenToCategory(ns.settingsCategory:GetID()) end end
