-- Throwaway mockup (2026-11-10): the proposed Omashu settings page, made only of Blizzard's own settings controls,
-- so the look, fonts and controller behaviour are the game's. Nothing here changes anything. /ommock opens it.
OmashuSettingsMockDB = {}   -- mock: always start from the proposed defaults
local db = OmashuSettingsMockDB
local category, layout

local function header(text)
  if CreateSettingsListSectionHeaderInitializer then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
  end
end
local n = 0
local function check(label, default, tip, parent)
  n = n + 1
  local key = 'c' .. n
  if db[key] == nil then db[key] = default end
  local setting = Settings.RegisterAddOnSetting(category, 'OMASHU_MOCK_' .. n, key, db, Settings.VarType.Boolean, label, default)
  local init = Settings.CreateCheckbox(category, setting, tip)
  if parent and init.SetParentInitializer then
    init:SetParentInitializer(parent.init, function() return parent.setting:GetValue() end)
  end
  return { init = init, setting = setting }
end
local function slider(label, default, lo, hi, tip, fmt)
  n = n + 1
  local key = 's' .. n
  if db[key] == nil then db[key] = default end
  local setting = Settings.RegisterAddOnSetting(category, 'OMASHU_MOCK_' .. n, key, db, Settings.VarType.Number, label, default)
  local opts = Settings.CreateSliderOptions(lo, hi, 1)
  opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
  Settings.CreateSlider(category, setting, opts, tip)
end

local function build()
  category, layout = Settings.RegisterVerticalLayoutCategory('Omashu')

  header('Combat')
  local doomed = check('Doomed', true, "On your target's health bar, the health your DoTs will still take shows in their colours. When they'll finish it, a skull and bones lands on its portrait.")
  check('Skull on nameplates', true, 'The skull and bones also shows on the nameplates of other mobs your DoTs will finish.', doomed)
  local rings = check('DoT rings on nameplates', true, "Your DoTs as rings over each enemy's nameplate, draining as they run out.")
  check("Other warlocks' DoTs", true, 'Shown smaller and dimmer than yours.', rings)
  check('Demon low-health warning', true, "Your demon's portrait ring and the screen edge breathe purple when it drops below 30% health.")

  header('Soul Shards')
  check('Shard gems', true, "Your soul shards as gems under your demon's portrait.")
  check('Drain Soul shard hint', true, 'Shows when Drain Soul will give you a shard from this mob.')
  slider('Shards to keep', 6, 0, 32, 'When you open your bags, shards above this number are deleted, with a line in chat. 0 keeps them all.',
    function(v) v = math.floor(v + .5); return v == 0 and 'All' or tostring(v) end)

  header('Reminders')
  check('Demon missing or passive', true, 'When your demon is dismissed, dead, or set to passive.')
  check('Armor missing', true, 'When Demon Skin or Demon Armor has run out.')
  check('Healthstone missing', true, 'When you have no Healthstone in your bags.')
  check('Soulstone not placed', true, 'When no one in your group has your Soulstone.')
  check('Shards low', true, 'When you are down to your last soul shard.')
  check('New spells at the trainer', true, 'When you reach a level with new warlock spells to learn.')

  header('Group')
  check('Soulstone tracker', true, 'Who has your Soulstone and how long it has left, next to the party frames.')
  check('Summon queue', true, 'Who in your group still needs a summon.')
  check('Crowd-control timers', true, 'Your Banish, Fear and Seduction timers on the mobs they hold.')

  header('Say in Group Chat')
  check('Soulstone placed', false, 'Says in party or raid chat who has your Soulstone.')
  check('Summoning', false, 'Says in party or raid chat who you are summoning, so they click the portal.')
  check('Healthstones ready', false, 'Says in party or raid chat that your Healthstones are ready.')

  header('Controller')
  check('Warlock button layout', true, 'Your warlock spells on the gamepad trigger sets.')
  check('View opens the guide', true, 'Press View to move the controller into the RestedXP guide box.')

  header('Accessibility')
  check('Calm motion', false, 'Glows hold steady instead of breathing.')

  Settings.RegisterAddOnCategory(category)
end

local f = CreateFrame('Frame')
f:RegisterEvent('PLAYER_LOGIN')
f:SetScript('OnEvent', function()
  local ok, err = pcall(build)
  if not ok then print('|cffe8c860Omashu mock:|r ' .. tostring(err)) end
end)
SLASH_OMASHUMOCK1 = '/ommock'
SlashCmdList.OMASHUMOCK = function()
  if category then Settings.OpenToCategory(category:GetID()) end
end
