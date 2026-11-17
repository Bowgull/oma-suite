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
      choices = { { 'default', 'Default' }, { 'fel', 'Fel' }, { 'smoke', 'Smoke' }, { 'drain', 'Soul drain' } },
      tip = "Default: Blizzard's breath. Fel: the edge shaped into still flame tongues. Smoke: soft smoke rising slowly through it. Soul drain: thin strands of light flowing along the edge toward your demon. All in your warning colour." },
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
      tip = '"healthstones ready, grab one" when you cast Ritual of Souls. Your own Create Healthstone stays quiet.' },
    { key = 'askHelp', store = R, default = true, control = 'check', label = 'Click a debuff to ask for help',
      tip = 'Click one of your debuffs above your bars and one line goes to group chat, naming whoever in your group can remove it ("cursed, Eiria decurse pls <3"), or a cheeky line when nobody can.' },
    { key = 'chatStyle', store = R, default = 'plain', control = 'dropdown', label = 'Chat style',
      choices = { { 'plain', 'Plain' }, { 'funny', 'Funny' } },
      tip = "Plain: the lines above. Funny: a different joke line each time, never the same one twice in a row (some swear; the game's profanity filter stars those out for anyone who has it on). Also the extra-shards line." },

    { header = 'Reminders' },
    { key = 'armor', store = R, default = true, control = 'check', label = 'Armor missing',
      tip = 'Your Demon Skin or Demon Armor button glows softly when the armor is off. Out of combat only.' },

    { header = 'Nightfall' },
    { key = 'nfOn', store = R, default = true, control = 'check', label = 'Nightfall overlay',
      tip = "When Nightfall procs (Shadow Trance: your next Shadow Bolt is instant), Blizzard's thorned crescents show either side of you until the Shadow Bolt goes." },
    { key = 'nfColour', store = R, default = 'violet', control = 'dropdown', label = 'Colour', parent = 'nfOn',
      choices = { { 'violet', "Blizzard's violet" }, { 'fel', 'Fel green' }, { 'ember', 'Hellfire ember' }, { 'blood', 'Blood red' } },
      tip = "Blizzard's violet is the art as Blizzard made it. The others recolour it, the same way Blizzard tints its own proc art." },
    { key = 'nfSound', store = R, default = true, control = 'check', label = 'Proc chime', parent = 'nfOn',
      tip = "Blizzard's proc chime, once, when it lights." },
    { button = 'Preview', name = '', click = function() if ns.nightfall and ns.nightfall.preview then ns.nightfall.preview(4) end end,
      tip = 'Shows it for 4 seconds, with its chime, so you can see it before you have the talent (level 25).' },

    { header = 'Extra Shards' },
    { key = 'keep', store = S, default = 6, control = 'slider', label = 'Shards to keep', min = 1, max = 20, step = 1, format = tostring,
      tip = 'How many Soul Shards you want to carry.' },
    { key = 'trim', store = S, default = true, control = 'check', label = 'Delete extras on bag open',
      tip = 'Each time you open your bags with more shards than you keep, one extra shard is deleted. Never in a fight. Off: you get a line in chat instead, and clear them yourself.' },
    { key = 'chat', store = S, default = true, control = 'check', label = 'Line in chat',
      tip = 'One line in chat when a shard is deleted, or when you go over (with deleting off).' },
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
  -- 2026-11-13: Heartbeat, Wisps, Essence and Soul fire are gone; an old saved look would show as "Custom"
  local looks = { default = true, fel = true, smoke = true, drain = true }
  if d.glow.look ~= nil and not looks[d.glow.look] then d.glow.look = 'default' end
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
  if cmd == 'nightfall' then
    if rest == 'probe' then return ns.nfProbe and ns.nfProbe.toggle() end
    if rest == 'sound off' or rest == 'sound on' then ns.groupDB().nfSound = (rest == 'sound on'); print('|cff9b6bffOmaDemon|r: Nightfall chime ' .. rest:sub(7)); return end
    if ns.nightfall and ns.nightfall.preview then ns.nightfall.preview(4) end
    print('|cff9b6bffOmaDemon|r: Nightfall for 4 s (art from the ' .. tostring(ns.nightfall and ns.nightfall.artFrom) .. '). /omademon nightfall sound off|on')
    return
  end
  if cmd == 'motion' then
    local off = rest:lower() == 'off'
    ns.glowDB().reduced = off; ns.shardsDB().reduced = off
    if ns.glowMotion then ns.glowMotion() end
    return ns.say('motion ' .. (off and 'reduced (steady glow)' or 'full'))
  end
  if ns.glowSlash then return ns.glowSlash(msg) end
end
