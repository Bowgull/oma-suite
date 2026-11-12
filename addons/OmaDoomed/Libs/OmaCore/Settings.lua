-- Settings: one table describes every setting of an add-on. From it come the defaults, the Options page (built only
-- from Blizzard's own Settings API controls, so controller, search and Defaults work), the bug-report dump, and the
-- saved-data version with numbered upgrade steps.
--
--   s = Core.NewSettings{ prefix = 'OMADOOMED_', onChange = function(key, store) end, onError = function(msg) end,
--                         items = { ... } }
-- An item is one of:
--   { header = 'Text' }                                    a section header
--   { element = function() return initializer end }         any initializer (nil = skipped)
--   { button = 'Text', name = '', click = fn, tip = '' }    a button
--   { key = 'k', default = v, store = 'sub' }               a setting with no control (default only)
--   { key = 'k', default = v, control = 'check'|'slider'|'dropdown', label = '', tip = '', parent = 'otherKey',
--     store = 'sub', min =, max =, step =, format = fn, choices = { { value, 'Label' }, ... },
--     frame = fn(rowFrame) }   frame: called each time Blizzard sets up the row, to add our own bits beside it
-- store: the sub-table of the saved table the value lives in (nil = the saved table itself).
-- Sliders get a small gold notch at their default. It is added with hooksecurefunc after Blizzard's own setup and
-- kept in OmaCore's own table, never written onto Blizzard's frame.
local _, ns = ...
local Core = ns.omaCoreBuild
if not Core then return end

local S = {}
S.__index = S
Core.SettingsMethods = S
Core.notches = Core.notches or setmetatable({}, { __mode = 'k' })   -- slider frame -> its notch (shared by all copies)

function Core.NewSettings(def)
  local s = setmetatable({ def = def, items = def.items, byKey = {}, prefix = def.prefix or 'OMA_' }, S)
  for _, it in ipairs(def.items) do
    if it.key then
      if s.byKey[it.key] then error('Settings: key ' .. it.key .. ' twice', 2) end
      if it.default == nil then error('Settings: ' .. it.key .. ' has no default', 2) end
      s.byKey[it.key] = it
    end
  end
  return s
end

function S:Default(key) local it = self.byKey[key]; return it and it.default end
function S:Store(key) local it = self.byKey[key]; return it and it.store end
function S:Item(key) return self.byKey[key] end
local function tableFor(db, it)
  if not it.store then return db end
  local t = db[it.store]; if type(t) ~= 'table' then t = {}; db[it.store] = t end
  return t
end

-- every missing value gets its default (saved values are kept)
function S:Fill(db)
  for _, it in ipairs(self.items) do
    if it.key then local t = tableFor(db, it); if t[it.key] == nil then t[it.key] = it.default end end
  end
end

-- db.v is the saved-data version; steps[i] upgrades version i-1 to i. Each step runs once, in order. A step that
-- fails stops the run (the version stays at the last good step) and is reported to onError.
function S:Migrate(db, steps, onError)
  local v = tonumber(db.v) or 0
  for i = v + 1, #steps do
    local ok, err = pcall(steps[i], db)
    if not ok then if onError then onError('saved data upgrade ' .. i .. ': ' .. tostring(err)) end; return false end
    db.v = i
  end
  return true
end

-- for bug reports: every plain value of the saved table and of each store, with every setting present
function S:Dump(db)
  local out = { main = {} }
  local function copy(t, o) for k, v in pairs(t or {}) do local tv = type(v); if tv == 'boolean' or tv == 'number' or tv == 'string' then o[k] = v end end end
  copy(db, out.main)
  for _, it in ipairs(self.items) do
    if it.key then
      local name = it.store or 'main'
      if not out[name] then out[name] = {}; copy(db[it.store], out[name]) end
      if out[name][it.key] == nil then
        local t = it.store and db[it.store] or db
        local v = type(t) == 'table' and t[it.key]; if v == nil then v = it.default end
        out[name][it.key] = v
      end
    end
  end
  return out
end

-- one shared "Oma" parent category for every Oma add-on; whoever loads first makes it (kept in _G.OmaSuite)
function Core.OmaParent()
  local O = _G.OmaSuite or {}; _G.OmaSuite = O
  if not O.parent then
    O.parent = Settings.RegisterVerticalLayoutCategory('Oma')
    local f = CreateFrame('Frame'); f:RegisterEvent('PLAYER_LOGIN')
    f:SetScript('OnEvent', function() if not O.registered then O.registered = true; Settings.RegisterAddOnCategory(O.parent) end end)
  end
  return O.parent
end

local function hookSliders()
  if Core.sliderHooked or not (SettingsSliderControlMixin and SettingsSliderControlMixin.Init) then return end
  Core.sliderHooked = true
  -- a recycled slider frame may carry a notch from another setting: hide it; ours shows it again after
  hooksecurefunc(SettingsSliderControlMixin, 'Init', function(frame) local n = Core.notches[frame]; if n then n:Hide() end end)
end

local function notch(init, def, lo, hi)
  hooksecurefunc(init, 'InitFrame', function(_, frame)
    local sl = frame and frame.SliderWithSteppers and frame.SliderWithSteppers.Slider
    if not sl then return end
    local n = Core.notches[frame]
    if not n then n = sl:CreateTexture(nil, 'OVERLAY'); n:SetColorTexture(1, .82, .25, .9); Core.notches[frame] = n end
    n:SetParent(sl); n:SetSize(2, 10); n:Show()
    local function placeIt()
      local w = sl:GetWidth(); if not w or w <= 0 then return end
      n:ClearAllPoints(); n:SetPoint('CENTER', sl, 'LEFT', w * (def - lo) / (hi - lo), 0)
    end
    placeIt(); C_Timer.After(0, placeIt)
  end)
end
function S:NotchOf(frame) return Core.notches[frame] end

local VARTYPE = { boolean = 'Boolean', number = 'Number', string = 'String' }

-- Builds the page as a subcategory `name` of `parent` (default: the shared Oma parent). Returns the category.
function S:Build(db, name, parent)
  local cat, layout = Settings.RegisterVerticalLayoutSubcategory(parent or Core.OmaParent(), name)
  self.category = cat
  hookSliders()
  local made = {}   -- key -> { init, setting }
  for _, it in ipairs(self.items) do
    if it.header then
      if CreateSettingsListSectionHeaderInitializer then layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(it.header)) end
    elseif it.element then
      local init = it.element(); if init then layout:AddInitializer(init) end
    elseif it.button then
      if CreateSettingsButtonInitializer then layout:AddInitializer(CreateSettingsButtonInitializer(it.name or '', it.button, it.click, it.tip, true)) end
    elseif it.key and it.control then
      local tbl, key, variable = tableFor(db, it), it.key, self.prefix .. it.key
      if tbl[key] == nil then tbl[key] = it.default end
      local setting = Settings.RegisterAddOnSetting(cat, variable, key, tbl, Settings.VarType[VARTYPE[type(it.default)]], it.label, it.default)
      local onChange, onError, store = self.def.onChange, self.def.onError, it.store
      Settings.SetOnValueChangedCallback(variable, function()
        if not onChange then return end
        local ok, err = pcall(onChange, key, store)
        if not ok and onError then onError('setting ' .. key .. ': ' .. tostring(err)) end
      end)
      local init
      if it.control == 'check' then
        init = Settings.CreateCheckbox(cat, setting, it.tip)
      elseif it.control == 'slider' then
        local opts = Settings.CreateSliderOptions(it.min, it.max, it.step)
        opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, it.format)
        init = Settings.CreateSlider(cat, setting, opts, it.tip)
        notch(init, it.default, it.min, it.max)
      elseif it.control == 'dropdown' then
        local choices = it.choices
        local function options()
          local c = Settings.CreateControlTextContainer()
          for _, ch in ipairs(choices) do c:Add(ch[1], ch[2]) end
          return c:GetData()
        end
        local make = Settings.CreateDropdown or Settings.CreateDropDown
        init = make(cat, setting, options, it.tip)
      else
        error('Settings: unknown control ' .. tostring(it.control) .. ' for ' .. key)
      end
      local p = it.parent and made[it.parent]
      if p and init.SetParentInitializer then init:SetParentInitializer(p.init, function() return p.setting:GetValue() end) end
      if it.frame and init.InitFrame then   -- it.frame(frame): add something to this row (kept on our side, never on Blizzard's frame)
        local fn, onError = it.frame, self.def.onError
        hooksecurefunc(init, 'InitFrame', function(_, frame)
          local ok, err = pcall(fn, frame); if not ok and onError then onError('row ' .. key .. ': ' .. tostring(err)) end
        end)
      end
      made[key] = { init = init, setting = setting }
    end
  end
  return cat
end

function S:Open() if self.category and Settings.OpenToCategory then Settings.OpenToCategory(self.category:GetID()) end end
