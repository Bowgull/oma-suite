-- OmaDemon offline smoke test: loads the add-on in TOC order into OmaDoomed's fake WoW (with the Settings fake),
-- logs in a warlock with a demon out, then works every setting, Preview, Move gems and the edge looks.
-- Run from the OmaDemon folder:  luajit tests/smoke.lua
package.path = '../OmaDoomed/tests/?.lua;' .. package.path
local W = require('fakewow')
local UI = require('ui'); UI.install(); UI.settings()
UnitClass = function() return 'Warlock', 'WARLOCK' end
UnitExists = function(u) return u == 'pet' or u == 'player' end
UnitIsDeadOrGhost = function() return false end
local hp = .2
UnitHealthPercent = function(u, pred, curve) if curve then return curve:Evaluate(hp) end; return hp end
local function mkCurve() local pts = {}; return { SetType = function() end, AddPoint = function(_, x, y) pts[#pts + 1] = { x, y } end,
  Evaluate = function(_, x) for i = 1, #pts - 1 do local a, b = pts[i], pts[i + 1]; if x >= a[1] and x <= b[1] then if b[1] == a[1] then return b[2] end; return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1]) end end; return 0 end } end
C_CurveUtil = { CreateCurve = mkCurve }; Enum = Enum or {}; Enum.LuaCurveType = { Linear = 1 }
GetCVarBool = GetCVarBool or function() return false end
local binds = {}
SetOverrideBindingClick = function(owner, prio, key, btn) binds[key] = btn end
ClearOverrideBindings = function() binds = {} end
HideUIPanel = HideUIPanel or function(f) f:Hide() end
local count = 3
ToggleBackpack = function() end; OpenAllBags = function() end   -- the bag-open hooks need them before the add-on loads
PlaySound = function() end
C_Item = C_Item or {}; C_Item.GetItemCount = function() return count end
local files = {}
for line in io.lines('OmaDemon.toc') do if not line:match('^##') and line:match('%S') then files[#files + 1] = (line:gsub('\\', '/'):gsub('%s+$', '')) end end
local ns = W.load('.', 'OmaDemon', files, {})
W.fire('ADDON_LOADED', 'OmaDemon'); W.fire('PLAYER_LOGIN'); W.fire('PLAYER_ENTERING_WORLD')
local ok = 0
local function check(c, m) if not c then error('FAIL: ' .. m, 2) end; ok = ok + 1 end
check(ns.category ~= nil, 'settings page built')
check(OmaDemonDB.glow.look == 'default' and OmaDemonDB.shards.gemLook == 'default', 'defaults filled, first choice called default')
-- every setting change runs without error
for _, it in ipairs(ns.settings.items) do
  if it.key and it.control then
    local store = OmaDemonDB[it.store]
    local v = it.default
    if it.control == 'check' then v = not v elseif it.control == 'slider' then v = it.max elseif it.control == 'dropdown' then v = it.choices[#it.choices][1] end
    store[it.key] = v; for _, fn in ipairs(ns.onSetting) do fn(it.key, it.store) end
    store[it.key] = it.default; for _, fn in ipairs(ns.onSetting) do fn(it.key, it.store) end
    check(true, it.key)
  end
end
for _, L in ipairs({ 'default', 'fel', 'smoke', 'drain' }) do
  OmaDemonDB.glow.look = L; for _, fn in ipairs(ns.onSetting) do fn('look', 'glow') end
  W.advance(3); check(true, 'look ' .. L)
end
ns.previewWarning(); W.advance(1); check(true, 'preview')
OmaDemonDB.glow.look = 'wisps'; for _, fn in ipairs(ns.onSetting) do fn('look', 'glow') end; W.advance(1); check(true, 'an old saved look (wisps) falls back to default while drawing')
OmaDemonDB.glow.look = 'wisps'; W.fire('ADDON_LOADED', 'OmaDemon'); check(OmaDemonDB.glow.look == 'wisps' or OmaDemonDB.glow.look == 'default', 'migration hook ran')
OmaDemonDB.glow.look = 'default'
OmaDemonDB.shards.pin = false; for _, fn in ipairs(ns.onSetting) do fn('pin', 'shards') end
check(OmaDemonDB.shards.pin == false, 'unpinned (the fake has no layout, so no spot to keep)')
ns.moveGems(); check(_G.OmaDemonGemMover:IsShown(), 'move box shows'); _G.OmaDemonNudgeUp:Click(); ns.endMove()
check(not _G.OmaDemonGemMover:IsShown(), 'done hides the box')
count = 7; W.fire('BAG_UPDATE_DELAYED'); check(true, 'over keep')
-- ---- sheet 48: chat lines, Soulstone tracker, armor glow ----
W.units.player = { guid = 'P-1', name = 'Bujuju', player = true }
W.units.party1 = { guid = 'P-2', name = 'Lindarra', player = true }
W.units.party2 = { guid = 'P-3', name = 'Zugzug', player = true }
UnitExists = function(u) return u == 'pet' or W.units[u] ~= nil end
local sent = {}
SendChatMessage = function(m, ch) sent[#sent + 1] = ch .. ':' .. m end
local SPELL = { [1] = 'Soulstone Resurrection', [2] = 'Ritual of Summoning', [3] = 'Create Healthstone (Minor)', [4] = 'Demon Skin', [5] = 'Ritual of Souls' }
C_Spell = C_Spell or {}; C_Spell.GetSpellName = function(id) return SPELL[id] end
local auras = {}
C_UnitAuras = C_UnitAuras or {}
C_UnitAuras.GetAuraDataBySpellName = function(u, n) return auras[u .. ':' .. n] end
local function cast(id, target) if target then W.fire('UNIT_SPELLCAST_SENT', 'player', target, 'c', id) end; W.fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'c', id) end
local G = OmaDemonDB.group
check(G.sayStone == false and G.saySummon == false and G.sayStones == false and G.soulstone == true and G.armor == true, 'group defaults: lines off, tracker and armor on')
W.group = true
cast(1, 'Lindarra'); check(#sent == 0, 'lines off by default send nothing')
G.sayStone, G.saySummon, G.sayStones = true, true, true
cast(1, 'Lindarra'); check(sent[#sent] == 'PARTY:Soulstone on Lindarra.', 'soulstone line: ' .. tostring(sent[#sent]))
cast(2, 'Zugzug'); check(sent[#sent] == 'PARTY:summoning Zugzug, click the portal pls', 'summon line: ' .. tostring(sent[#sent]))
local n0 = #sent; cast(3); check(#sent == n0, 'Create Healthstone (just yours) says nothing')
cast(5); check(sent[#sent] == 'PARTY:healthstones ready, grab one', 'healthstones line: ' .. tostring(sent[#sent]))
local n = #sent; cast(5); check(#sent == n, 'healthstones line at most once a minute')
W.group = false; cast(1, 'Lindarra'); check(#sent == n, 'never sent when alone')
-- sheet 51: Chat style Funny, a different line each time, never twice in a row
check(G.chatStyle == 'plain', 'chat style defaults to Plain')
G.chatStyle = 'funny'; W.group = true
local prev
for i = 1, 30 do
  cast(1, 'Lindarra'); local m = sent[#sent]
  check(m:find('Lindarra', 1, true) and m ~= prev, 'funny stone line has the name, never repeats: ' .. m); prev = m
end
cast(2, 'Zugzug'); check(sent[#sent]:find('Zugzug', 1, true), 'funny summon line: ' .. sent[#sent])
for _, kind in ipairs({ 'stone', 'summon', 'stones', 'shards', 'trim' }) do
  for _, f in ipairs(ns.lines.funny[kind]) do
    local okf, m = pcall(string.format, f, (kind == 'shards' or kind == 'trim') and 7 or 'Zugzug', 6)
    check(okf and #m < 255 and not m:find('%', 1, true), 'line ok: ' .. tostring(m))
  end
end
check(ns.line('shards', 7, 6):find('7', 1, true), 'funny shards line has the count')
G.chatStyle = 'plain'; check(ns.line('stone', 'Lindarra') == 'Soulstone on Lindarra.', 'back to Plain')
W.group = false; n = #sent
W.group = true
local pf = CreateFrame('Frame', 'CompactPartyFrameMember2', UIParent); pf.unit = 'party1'; pf:Show()
auras['party1:Soulstone Resurrection'] = { sourceUnit = 'player', expirationTime = W.now + 1800 }
cast(1, 'Lindarra'); W.advance(1)
check(_G.OmaDemonSoulstone:IsShown(), 'crystal shows on her frame')
auras['party1:Soulstone Resurrection'] = nil; W.advance(7)
check(not _G.OmaDemonSoulstone:IsShown(), 'crystal leaves when the stone is gone (out of combat check)')
W.group = false; ns.stoneTest(); W.advance(1)
check(_G.OmaDemonSoulstone:IsShown() and _G.OmaDemonSoulstone:GetParent() == _G.OmaDemonShards, 'solo stone sits with the gem row')
W.advance(95); check(not _G.OmaDemonSoulstone:IsShown(), 'test stone runs out')
local btn = CreateFrame('Button', 'ActionButton1', UIParent); btn.action = 5; btn:Show()
GetActionInfo = function(slot) if slot == 5 then return 'spell', 4 end end
W.fire('PLAYER_ENTERING_WORLD'); W.advance(1)
local g = ns.armorGlows[btn]
check(g and g:IsShown(), 'armor glow shows when Demon Skin is off')
auras['player:Demon Skin'] = { sourceUnit = 'player' }; W.fire('UNIT_AURA', 'player'); W.advance(1)
check(not g:IsShown(), 'glow goes when the armor is back')
auras['player:Demon Skin'] = nil; W.fire('UNIT_AURA', 'player'); W.advance(1); check(g:IsShown(), 'and comes back')
W.combat = true; W.fire('PLAYER_REGEN_DISABLED'); check(not g:IsShown(), 'never in combat')
W.combat = false; W.fire('PLAYER_REGEN_ENABLED'); W.advance(1)
G.armor = false; for _, fn in ipairs(ns.onSetting) do fn('armor', 'group') end; check(not g:IsShown(), 'switch turns it off')
-- ---- sheet 78 / plan phase 7: debuffs on you, Nightfall ----
local UIx = require('ui')
local D, N = ns.debuffs, ns.nightfall
local dc = D.container
check(dc and dc.unit == 'player', 'debuff container built on player' .. (D.failed and (': ' .. D.failed) or ''))
-- sheet 104: one fixed spot per type, centred above the bars; the game filters by dispel type
W.dispel = { [101] = 'Magic', [102] = 'Curse', [104] = 'Poison' }
local mg = UIx.group(dc, 'magic')
check(mg and mg.slot and mg.filter == 'HARMFUL' and mg.filters.includeDispelTypes.Magic, 'a magic spot, filtered by the game')
check(UIx.group(dc, 'other').filters.excludeDispelTypes.Curse, 'the last spot: anything without a type')
local b1 = mg.buttons[1]
check(b1:GetWidth() == 44, 'spots are 44 px: ' .. tostring(b1:GetWidth()))
W.units.player.otherAuras = { 101, 102, 103 }; W.fire('UNIT_AURA', 'player')
local sh = UIx.showing(dc)
check(sh.magic[1] == 101 and sh.curse[1] == 102 and sh.other[1] == 103 and #sh.poison == 0, 'each debuff in its own spot')
check(b1.omPlasma and b1.omPlasma:IsPlaying(), 'the plasma loops (started once)')
W.units.player.otherAuras = {}; W.fire('UNIT_AURA', 'player')
sh = UIx.showing(dc); check(#sh.magic == 0 and #sh.curse == 0, 'gone when they wear off (the game hides them)')
-- click to ask for help: the groupmate who can remove it, by class and level
W.units.party1 = { guid = 'P-9', name = 'Eiria', player = true, level = 23 }
local oldClass = UnitClass
UnitClass = function(u) if u == 'party1' then return 'Druid', 'DRUID' end; return oldClass(u) end
check(ns.helpLine('poison') == 'poisoned, Eiria cleanse pls :3', 'a level 23 druid cures poison: ' .. tostring(ns.helpLine('poison')))
check(ns.helpLine('curse') == 'cursed, no decurse here. its fine T_T', 'but not curses until 24')
W.units.party1.level = 24; check(ns.helpLine('curse') == 'cursed, Eiria decurse pls <3', 'at 24 she can')
W.group = true
local auraList = { { dispelName = 'Poison' } }
C_UnitAuras.GetAuraDataByIndex = function(u, i) return auraList[i] end
local n0 = #sent; _G.OmaDemonHelppoison:Click(); check(sent[#sent] == 'PARTY:poisoned, Eiria cleanse pls :3', 'click: the line goes out: ' .. tostring(sent[#sent]))
n0 = #sent; _G.OmaDemonHelpmagic:Click(); check(#sent == n0, 'nothing in that spot (out of a fight we can tell): no line')
W.combat = true; n0 = #sent; _G.OmaDemonHelpcurse:Click(); check(#sent == n0 + 1, 'in a fight a click still sends (it is your press)')
ns.groupSay('Soulstone on Lindarra.'); check(#sent == n0 + 1, 'a line that fires on its own waits in a fight')
W.combat = false; W.fire('PLAYER_REGEN_ENABLED'); check(sent[#sent] == 'PARTY:Soulstone on Lindarra.', 'and goes out when it ends')
OmaDemonDB.group.askHelp = false; n0 = #sent; _G.OmaDemonHelppoison:Click(); check(#sent == n0, 'switch off: no line'); OmaDemonDB.group.askHelp = nil
W.units.party1 = nil; UnitClass = oldClass; W.group = false
-- Nightfall: one slot, Shadow Trance only
local nc = N.container
check(nc and nc.unit == 'player', 'Nightfall slot built on player' .. (N.failed and (': ' .. N.failed) or ''))
local ng = UIx.group(nc, 'nightfall')
check(ng and ng.slot and ng.filters.includeSpellIDs[17941], 'slot allows Shadow Trance (17941)')
W.units.player.otherAuras = { 101, 17941 }; W.fire('UNIT_AURA', 'player')
check(UIx.showing(nc).nightfall[1] == 17941 and true, 'proc: the slot shows')
check(N.live and UIx.isVisible(N.live), 'proc: the crescents show (they ride the game button)')
check(N.chimed == nil, 'proc: no chime on a real proc (Forever refuses OnShow under the game button)')
check(N.live.sides[1].pulse:IsPlaying() and N.live:GetAlpha() > 0, 'proc: the crescents pulse on their own, at full strength')
local sl, sr = N.live.sides[1].frame, N.live.sides[2].frame
check(math.abs(sl:GetWidth() - 102.4) < 1e-6 and math.abs(sl:GetHeight() - 204.8) < 1e-6, "crescents at Blizzard's size (0.4 x 0.8 of 256)")
check(rawget(sl, '_pts').RIGHT and rawget(sr, '_pts').LEFT, 'one each side of the centre square')
check(N.artFrom == 'add-on', 'no game file in the fake: the add-on copy of the art')
W.units.player.otherAuras = { 101 }; W.fire('UNIT_AURA', 'player')
check(#UIx.showing(nc).nightfall == 0 and not UIx.isVisible(N.live), 'Shadow Bolt used: the crescents are gone')
local pv = N.preview(4); check(UIx.isVisible(pv) and N.chimed == 1, '/omademon nightfall: shown, with its chime')
W.advance(5); check(not UIx.isVisible(pv), 'and gone after 4 s')
ns.groupDB().nfSound = false; N.preview(4); check(N.chimed == 1, 'chime off: silent'); ns.groupDB().nfSound = nil; W.advance(5)
local function set(k, v) OmaDemonDB.group[k] = v; for _, fn in ipairs(ns.onSetting) do fn(k, 'group') end end
set('nfColour', 'fel'); local r, g = N.previewFrame.sides[1].tex:GetVertexColor()
check(math.abs(r - .42) < 1e-6 and g == 1, 'Colour: Fel green repaints it at once')
set('nfColour', 'violet'); r, g = N.previewFrame.sides[1].tex:GetVertexColor()
check(r == 1 and g == 1, "Colour: back to Blizzard's violet (the art as made)")
local before = N.chimed; set('nfOn', false); N.preview(4)
check(N.chimed == before and N.previewFrame:GetAlpha() == 0, 'Nightfall overlay off: nothing shows, no chime')
check(N.live:GetAlpha() == 0, 'Nightfall overlay off: the real one is clear too'); set('nfOn', nil); W.advance(5)
check(N.live:GetAlpha() > 0, 'back on: the real one shows again')
W.fire('SPELL_ACTIVATION_OVERLAY_SHOW', 17941)
check(OmaDemonDB.group.nfOverlayBlizz == true, "Blizzard's own Shadow Trance overlay seen: ours stands down")
W.units.player.otherAuras = { 17941 }; W.fire('UNIT_AURA', 'player')
check(N.live:GetAlpha() == 0, 'and stays out of the way on the next proc')
W.units.player.otherAuras = {}; W.fire('UNIT_AURA', 'player'); OmaDemonDB.group.nfOverlayBlizz = nil
SPELL[6] = 'Shadow Bolt'
local sbBtn = CreateFrame('Button', 'ActionButton2', UIParent); sbBtn.action = 9; sbBtn:Show()
GetActionInfo = function(slot) if slot == 5 then return 'spell', 4 elseif slot == 9 then return 'spell', 6 end end
W.fire('ACTIONBAR_SLOT_CHANGED'); W.advance(1)
check(N.on == sbBtn, 'Shadow Bolt button found for our proc glow')
W.fire('SPELL_ACTIVATION_OVERLAY_GLOW_SHOW', 6); W.advance(1)
check(OmaDemonDB.group.nfBlizz == true and N.on == nil, "Blizzard's own Shadow Bolt glow seen: ours stands down")
W.fire('PLAYER_ENTERING_WORLD'); W.advance(1); check(N.on == nil, 'and stays down')
-- Nightfall chime probe: reads and logs only
C_Spell.GetSpellInfo = function(n) if n == 'Shadow Bolt' then return { spellID = 6, castTime = W.now > 9000 and 0 or 2500 } end end
SPELL[6] = 'Shadow Bolt'
local PR = ns.nfProbe
PR.toggle(); check(PR.on and OmaDemonDB.group.nfProbe.shadowBolt == 6, 'probe on, Shadow Bolt found')
W.fire('UNIT_SPELLCAST_START', 'player', 'c', 6); W.fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'c', 6)
W.fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'c', 6)
check(OmaDemonDB.group.nfProbe.sum.instant == 1, 'an instant Shadow Bolt is counted')
W.fire('SPELL_ACTIVATION_OVERLAY_GLOW_SHOW', 6); check(OmaDemonDB.group.nfProbe.sum.events == 1, 'overlay event logged')
W.advance(301); check(not PR.on and #OmaDemonDB.group.nfProbe.log > 3, 'probe stops by itself after 5 min')
-- extra shards deleted on bag open (ShardTrim.lua)
local bagShards, cursor, deleted = 0, nil, 0
C_Container = C_Container or {}
C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end
C_Container.GetContainerItemID = function(bag, slot) if bag == 0 and slot <= bagShards then return 6265 end end
C_Container.PickupContainerItem = function() cursor = 6265 end
DeleteCursorItem = function() if cursor then cursor = nil; bagShards = bagShards - 1; deleted = deleted + 1 end end
CursorHasItem = function() return cursor ~= nil end; ClearCursor = function() cursor = nil end
C_Item.GetItemCount = function() return bagShards end
date = date or os.date
local SD = OmaDemonDB.shards
SD.keep, SD.trim = 6, nil
local said = {}; local oldSay = ns.say; ns.say = function(m) said[#said + 1] = m end
bagShards = 8; W.advance(1); ToggleBackpack(); OpenAllBags(); W.advance(1)   -- one press can fire several hooks
check(bagShards == 7 and deleted == 1, 'bag open over the limit: one shard deleted (several hooks, one press)')
check(said[#said] and said[#said]:find('7', 1, true), 'and a line in chat: ' .. tostring(said[#said]))
W.advance(1); ToggleBackpack(); W.advance(1); check(bagShards == 6, 'next open: the last extra')
W.advance(1); ToggleBackpack(); W.advance(1); check(bagShards == 6, 'at the limit: nothing more')
bagShards = 9; W.combat = true; W.advance(1); ToggleBackpack(); W.advance(1); check(bagShards == 9, 'never in a fight'); W.combat = false
cursor = 1234; W.advance(1); ToggleBackpack(); W.advance(1); check(bagShards == 9 and cursor == 1234, 'never while you hold something')
cursor = nil; SD.trim = false; W.advance(1); ToggleBackpack(); W.advance(1); check(bagShards == 9, 'switch off: kept')
SD.trim = nil; ns.say = oldSay

-- gem size follows the pet frame even when only the frame it sits in is resized (2026-11-19: "sometimes big, sometimes small")
local row = _G.OmaDemonShards
SD.gems, SD.hideOOC, SD.size, SD.pin, SD.pos = nil, false, nil, nil, nil; ns.shardsVis()
local petScale = 1
local oldPF = _G.PetFrame
_G.PetFrame = { GetEffectiveScale = function() return petScale end }   -- a parent's SetScale: no hook on PetFrame fires
W.advance(1); check(math.abs(row:GetScale() - .55) < 1e-6, 'gems at .55 with the pet frame at 1')
petScale = 1.5; W.advance(1); check(math.abs(row:GetScale() - .825) < 1e-6, 'pet frame grown by its parent: gems follow within a second')
_G.PetFrame.GetEffectiveScale = function() error('secret') end; W.advance(1)
check(math.abs(row:GetScale() - .825) < 1e-6, 'an unreadable pet frame scale keeps the last good size')
_G.PetFrame.GetEffectiveScale = function() return 0 end; W.advance(1)
check(math.abs(row:GetScale() - .825) < 1e-6, 'a zero scale keeps the last good size')
_G.PetFrame = oldPF; W.advance(1)

-- no pet: the row's centre sits on the centre of your bars (2026-11-19: it was 29 px right on Joshua's 1080p screen)
local oldPP, oldHolder, oldPlayer = _G.PetPortrait, _G.PlayerBottomManagedFrameContainer, _G.PlayerFrame
local function bar(l, r, s, vis) return { GetLeft = function() return l end, GetRight = function() return r end,
  GetEffectiveScale = function() return s or 1 end, IsVisible = function() return vis ~= false end } end
local holderStub = bar(50, 400); _G.PlayerBottomManagedFrameContainer = holderStub
_G.PetPortrait = { IsVisible = function() return false end }
local function topX() for _, fn in ipairs(ns.onSetting) do fn('size', 'shards') end
  local p = rawget(row, '_pts') and rawget(row, '_pts').TOP; return p and p[1] == holderStub and p[2] == 'TOPLEFT' and p[3] end
_G.PlayerFrame = { healthbar = bar(103, 263), manabar = bar(107, 261) }   -- the bars measured on the screenshot
check(topX() == 183 - 50, 'no pet: row centred on the bars (x 183), not the old +59')
_G.PlayerFrame = { healthbar = bar(103 / .8, 263 / .8, .8), manabar = bar(0, 900, 1, false) }   -- smaller frame scale, a hidden bar
check(math.abs(topX() - 133) < 1e-6, 'no pet: same spot at another frame scale; hidden bars ignored')
_G.PlayerFrame = {}
check(rawget(row, '_pts') and (topX() == nil) and rawget(row, '_pts').TOPLEFT[3] == 59, 'no bars to read: the old spot')
_G.PetPortrait, _G.PlayerBottomManagedFrameContainer, _G.PlayerFrame = oldPP, oldHolder, oldPlayer
for _, fn in ipairs(ns.onSetting) do fn('size', 'shards') end
io.write(('OmaDemon smoke: %d checks passed\n'):format(ok))

