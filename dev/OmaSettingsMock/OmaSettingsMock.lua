-- Throwaway mockup (2026-11-11): OmaDemon's proposed settings page, under an "Oma" parent the way BigWigs nests its
-- pages, built only from Blizzard's own settings controls. The switches change nothing in OmaDemon.
-- Two live previews so the look can be judged in the game:
--   Edge strength: while the slider moves, the real purple edge art breathes on Blizzard's low-health clock at that strength.
--   Gem size: the real OmaDemon gem row scales while the slider moves (put back when the slider settles).
-- /omamock opens it.
OmaSettingsMockDB = {}   -- mock: always start from the proposed defaults
local db = OmaSettingsMockDB
local parentCat, cat, layout

local function header(text)
  if CreateSettingsListSectionHeaderInitializer then layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text)) end
end
local n = 0
local function reg(key, default, vartype, label)
  n = n + 1
  if db[key] == nil then db[key] = default end
  return Settings.RegisterAddOnSetting(cat, 'OMA_MOCK_' .. key, key, db, vartype, label, default)
end
local function child(init, parent)
  if parent and init.SetParentInitializer then init:SetParentInitializer(parent.init, function() return parent.setting:GetValue() end) end
end
local function check(key, label, default, tip, parent)
  local setting = reg(key, default, Settings.VarType.Boolean, label)
  local init = Settings.CreateCheckbox(cat, setting, tip); child(init, parent)
  return { init = init, setting = setting }
end
local function slider(key, label, default, lo, hi, step, tip, fmt, parent)
  local setting = reg(key, default, Settings.VarType.Number, label)
  local opts = Settings.CreateSliderOptions(lo, hi, step)
  opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
  local init = Settings.CreateSlider(cat, setting, opts, tip); child(init, parent)
  return { init = init, setting = setting }
end
local pct = function(v) return ('%d%%'):format(v) end

-- ---------- live preview: the real edge art on Blizzard's clock (0.5236 s linear bounce, 15% low) ----------
local edge = CreateFrame('Frame', nil, UIParent); edge:SetFrameStrata('BACKGROUND'); edge:SetAllPoints(UIParent); edge:Hide()
local edgeTex = edge:CreateTexture(nil, 'BACKGROUND'); edgeTex:SetTexture('Interface\\AddOns\\OmaDemon\\art\\edge'); edgeTex:SetAllPoints()
local previewUntil, strength = 0, 1
edge:SetScript('OnUpdate', function(self)
  local now = GetTime()
  if now > previewUntil then self:Hide(); return end
  local p = (now % 1.0472) / .5236; if p > 1 then p = 2 - p end           -- linear bounce, 0.5236 s each way
  local a = .15 + (1 - .15) * p
  local fade = math.min(1, (previewUntil - now) / .3)                      -- leave quick
  edgeTex:SetAlpha(a * strength * fade)
end)
local function previewEdge(v) strength = v / 100; previewUntil = GetTime() + 4; edge:Show() end

local baseScale
local function previewGems(v)
  local row = _G.OmaDemonShards; if not row then return end
  baseScale = baseScale or row:GetScale()
  row:SetScale(baseScale * v / 100)
  C_Timer.After(4, function() if baseScale and row then row:SetScale(baseScale); baseScale = nil end end)
end

-- One shared "Oma" parent for every Oma add-on (contract agreed with OmaDoomed, 2026-11-11): whoever loads first
-- makes it, it is registered once at PLAYER_LOGIN, everyone else hangs a subcategory under it.
local function omaParent()
  local O = _G.OmaSuite or {}; _G.OmaSuite = O
  if not O.parent then
    O.parent = Settings.RegisterVerticalLayoutCategory('Oma')
    local f = CreateFrame('Frame'); f:RegisterEvent('PLAYER_LOGIN')
    f:SetScript('OnEvent', function() if not O.registered then O.registered = true; Settings.RegisterAddOnCategory(O.parent) end end)
  end
  return O.parent
end

local function build()
  parentCat = omaParent()
  cat, layout = Settings.RegisterVerticalLayoutSubcategory(parentCat, 'OmaDemon')

  header('Demon Warning')
  check('ring', 'Portrait glow', true, "Your demon's portrait ring glows soul purple when its health drops below the warning level.")
  local edgeOn = check('edge', 'Screen edge', true, 'The edge of the screen breathes soul purple, like the red edge WoW shows when you are low.')
  slider('edgeStrength', 'Edge strength', 100, 20, 100, 5, 'How strong the purple edge is at its brightest. Move it to see the edge on screen.', pct, edgeOn)
  Settings.SetOnValueChangedCallback('OMA_MOCK_edgeStrength', function(...) previewEdge(select(select('#', ...), ...)) end)
  slider('level', 'Warning level', 30, 10, 50, 5, "The demon's health where the warning starts.", pct)
  check('sound', 'Warning sound', false, 'A soft sound when your demon drops below the warning level.')

  header('Soul Shard Gems')
  local gems = check('gems', 'Shard gems', true, 'Your soul shards as five cut gems. Past five, the count shows beside them.')
  slider('size', 'Size', 100, 75, 150, 5, 'Move it to see the gems change size.', pct, gems)
  Settings.SetOnValueChangedCallback('OMA_MOCK_size', function(...) previewGems(select(select('#', ...), ...)) end)
  check('pin', 'Pin to pet', true, "The gems follow your demon's frame. With no demon out, they slide up under yours. Turn it off to place them in Edit Mode.", gems)
  check('hideOOC', 'Hide out of combat', false, 'The gems fade away when you are not fighting.', gems)
  check('breathe', 'Breathe when full', true, 'In combat with five shards, the gems glow and breathe.', gems)
  check('chime', 'Chime at five', true, 'A soft chime when you reach five shards.', gems)
  check('pulse', 'Pulse when empty', false, 'The first gem pulses amber when you have no shards.', gems)

  header('Extra Shards')
  slider('keep', 'Shards to keep', 6, 0, 32, 1, 'When you open your bags, shards past this number are deleted. 0 keeps them all.', function(v) return v == 0 and 'All' or tostring(v) end)
  check('keepLine', 'Line in chat', true, 'Says in your chat how many shards were deleted.')

  if CreateSettingsButtonInitializer then
    layout:AddInitializer(CreateSettingsButtonInitializer('', 'Preview', function() previewEdge(db.edgeStrength or 100) end, 'Shows the demon warning for a few seconds.', true))
  end
end

-- Build at our own ADDON_LOADED, so the subcategory exists before the parent is registered at PLAYER_LOGIN.
local f = CreateFrame('Frame')
f:RegisterEvent('ADDON_LOADED')
f:SetScript('OnEvent', function(self, _, name)
  if name ~= 'OmaSettingsMock' then return end
  self:UnregisterEvent('ADDON_LOADED')
  local ok, err = pcall(build)
  if not ok then print('|cffc08cffOma mock:|r ' .. tostring(err)) end
end)
SLASH_OMAMOCK1 = '/omamock'
SlashCmdList.OMAMOCK = function(msg)
  if msg == 'edge' then previewEdge(db.edgeStrength or 100); return end
  if cat then Settings.OpenToCategory(cat:GetID()) end
end
