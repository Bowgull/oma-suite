-- OmaDemon's settings: OmaDemonDB = { glow = {...}, shards = {...} }, one table for every setting (OmaCore Settings),
-- shown in Options > AddOns > Oma > OmaDemon (sheet 31 v3, approved 2026-11-12 "yes to both").
-- WoW fills OmaDemonDB in after the files run, so everything reads it through ns.glowDB() / ns.shardsDB().
-- A change calls every function in ns.onSetting (key, store), so it shows at once.
local ADDON, ns = ...
local Core = LibStub('OmaCore-1.0')
ns.core = Core

local function db()
  OmaDemonDB = OmaDemonDB or {}
  OmaDemonDB.glow = OmaDemonDB.glow or {}
  OmaDemonDB.shards = OmaDemonDB.shards or {}
  OmaDemonDB.group = OmaDemonDB.group or {}
  return OmaDemonDB
end
function ns.glowDB() return db().glow end
function ns.shardsDB() return db().shards end
function ns.groupDB() return db().group end
function ns.say(m) print('|cffc08cffOmaDemon:|r ' .. m) end

ns.onSetting = {}
local function changed(key, store) for _, fn in ipairs(ns.onSetting) do fn(key, store) end end

local pct = function(v) return ('%d%%'):format(v) end
local G, S, R = 'glow', 'shards', 'group'

ns.settings = Core.NewSettings({
  prefix = 'OMADEMON_',
  onChange = changed,
  onError = function(m) ns.say('settings problem: ' .. m) end,
  items = {
    { header = 'Demon Warning' },
    { key = 'ring', store = G, default = true, control = 'check', label = 'Portrait glow',
      tip = "Your demon's portrait ring glows in your warning colour when its health drops below the warning level." },
    { key = 'edge', store = G, default = true, control = 'check', label = 'Screen edge',
      tip = "The edge of the screen breathes in your warning colour, like Blizzard's red edge when you're the one low." },
    { key = 'look', store = G, default = 'default', control = 'dropdown', label = 'Edge look', parent = 'edge',
      choices = { { 'default', 'Default' }, { 'heart', 'Heartbeat' }, { 'wisps', 'Wisps' }, { 'essence', 'Essence' }, { 'fire', 'Soul fire' } },
      tip = "Default: Blizzard's breath. Heartbeat: two beats and a rest. Wisps: soul sparks drift off the edge. Essence: haze curls up. Soul fire: thin flames along the bottom and sides." },
    { key = 'strength', store = G, default = 100, control = 'slider', label = 'Edge strength', parent = 'edge', min = 20, max = 100, step = 5, format = pct,
      tip = 'How strong the edge is.' },
    { key = 'colour', store = G, default = 'default', control = 'dropdown', label = 'Warning colour',
      choices = { { 'default', 'Default' }, { 'fel', 'Fel green' }, { 'ember', 'Hellfire ember' } },
      tip = "Default: soul purple. Fel green: fel fire. Hellfire ember: Immolate's orange. The ring and the edge always match." },
    { key = 'level', store = G, default = 30, control = 'slider', label = 'Warning level', min = 10, max = 50, step = 5, format = pct,
      tip = "The glow starts when your demon's health drops below this." },
    { button = 'Preview', name = '', click = function() if ns.previewWarning then ns.previewWarning() end end,
      tip = 'Runs the full warning for 6 seconds: ring and edge together.' },

    { header = 'Soul Shard Gems' },
    { key = 'gems', store = S, default = true, control = 'check', label = 'Shard gems',
      tip = "A gem for each soul shard you carry, under your demon's frame." },
    { key = 'gemLook', store = S, default = 'default', control = 'dropdown', label = 'Gem look', parent = 'gems',
      choices = { { 'default', 'Default' }, { 'crystal', 'Soul crystal' }, { 'pixel', 'Oma pixel' } },
      tip = "Default: OmaDemon's own cut soul gems. Soul crystal: a long crystal with a smaller one glowing inside, in an iron claw. Oma pixel: crisp pixel art in the Oma family's iron and brass." },
    { key = 'size', store = S, default = 100, control = 'slider', label = 'Size', parent = 'gems', min = 60, max = 160, step = 10, format = pct,
      tip = 'How big the gems are. 100% matches the pet frame.', frame = function(f) if ns.sizeRow then ns.sizeRow(f) end end },
    { key = 'pin', store = S, default = true, control = 'check', label = 'Pin to pet', parent = 'gems',
      tip = "The gems sit centred under your demon's frame and follow it. Turn off to place them yourself with Move gems." },
    { button = 'Move', name = 'Move gems', click = function() if ns.moveGems then ns.moveGems() end end,
      tip = 'Drag the gem row with the mouse, or nudge it with the arrow keys or D-pad. Enter or A when it is where you want it. Turn off Pin to pet first.' },
    { key = 'hideOOC', store = S, default = false, control = 'check', label = 'Hide out of combat', parent = 'gems',
      tip = "The gems only show while you're fighting." },
    { key = 'breathe', store = S, default = true, control = 'check', label = 'Breathe when full', parent = 'gems',
      tip = "All five gems breathe softly in a fight when you're full." },
    { key = 'sound', store = S, default = true, control = 'check', label = 'Chime at five', parent = 'gems',
      tip = 'A soft chime when the fifth gem lights.' },
    { key = 'zeroHint', store = S, default = false, control = 'check', label = 'Pulse when empty', parent = 'gems',
      tip = 'The first gem pulses amber when you have no shards and Drain Soul is known.' },

    { header = 'Group' },
    { key = 'soulstone', store = R, default = true, control = 'check', label = 'Soulstone tracker',
      tip = "Your soul crystal and the time left, on the party frame of whoever has your Soulstone. On yourself, at the end of your gems." },
    { key = 'sayStone', store = R, default = false, control = 'check', label = 'Say Soulstone in chat',
      tip = [["Soulstone on <name>." in party or raid chat when you place it. Never when you're alone.]] },
    { key = 'saySummon', store = R, default = false, control = 'check', label = 'Say summons in chat',
      tip = '"summoning <name>, click the portal pls" when you start Ritual of Summoning.' },
    { key = 'sayStones', store = R, default = false, control = 'check', label = 'Say Healthstones in chat',
      tip = '"healthstones ready, grab one" when you make them.' },

    { header = 'Reminders' },
    { key = 'armor', store = R, default = true, control = 'check', label = 'Armor missing',
      tip = 'Your Demon Skin or Demon Armor button glows softly when the armor is off. Out of combat only.' },

    { header = 'Extra Shards' },
    { key = 'keep', store = S, default = 6, control = 'slider', label = 'Shards to keep', min = 1, max = 20, step = 1, format = tostring,
      tip = 'Above this many, you get one line in chat so you can clear bag space.' },
    { key = 'chat', store = S, default = true, control = 'check', label = 'Line in chat',
      tip = 'One line in chat when you go over.' },
  },
})

-- WoW's own "Do Not Flash Screen at Low Health" (Accessibility) also calms OmaDemon: glows hold steady instead of moving.
function ns.reduced()
  local ok, v = pcall(GetCVarBool, 'doNotFlashLowHealthWarning')
  return (ok and v) or ns.glowDB().reduced or false
end

local boot = CreateFrame('Frame')
boot:RegisterEvent('ADDON_LOADED')
boot:SetScript('OnEvent', function(_, _, name)
  if name ~= ADDON then return end
  boot:UnregisterAllEvents()
  local d = db()
  ns.settings:Fill(d)
  if select(2, UnitClass('player')) == 'WARLOCK' then ns.category = ns.settings:Build(d, 'OmaDemon') end
end)

-- One slash command for both halves: /omademon (opens settings) | test | preview | motion on|off | shards ...
SLASH_OMADEMON1 = '/omademon'
SlashCmdList.OMADEMON = function(msg)
  msg = msg or ''
  local cmd, rest = msg:match('^(%S*)%s*(.-)$'); cmd = cmd:lower()
  if cmd == '' or cmd == 'options' then return ns.settings:Open() end
  if cmd == 'shards' then return ns.shardsSlash and ns.shardsSlash(rest) end
  if cmd == 'preview' then return ns.previewWarning and ns.previewWarning() end
  if cmd == 'stone' then return ns.stoneTest and ns.stoneTest(rest ~= '' and rest or nil) end
  if cmd == 'armor' then return ns.armorTest and ns.armorTest() end
  if cmd == 'motion' then
    local off = rest:lower() == 'off'
    ns.glowDB().reduced = off; ns.shardsDB().reduced = off
    if ns.glowMotion then ns.glowMotion() end
    return ns.say('motion ' .. (off and 'reduced (steady glow)' or 'full'))
  end
  if ns.glowSlash then return ns.glowSlash(msg) end
end
