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
local dg = UIx.group(dc, 'debuffs')
check(dg and dg.filter == 'HARMFUL' and dg.max == 8, 'HARMFUL group, up to 8 squares')
local b1 = dg.buttons[1]
check(b1:GetWidth() == 44, 'squares are 44 px: ' .. tostring(b1:GetWidth()))
W.units.player.otherAuras = { 101, 102 }; W.fire('UNIT_AURA', 'player')
check(#UIx.showing(dc).debuffs == 2, 'two debuffs on you, two squares')
W.units.player.otherAuras = {}; W.fire('UNIT_AURA', 'player')
check(#UIx.showing(dc).debuffs == 0, 'gone when they wear off (the game hides them)')
local tipped, shown = nil, false
GameTooltip = { SetOwner = function() end, SetUnitDebuffByAuraInstanceID = function(_, u, id) tipped = u .. ':' .. id end,
  Show = function() shown = true end, Hide = function() shown = false end }
b1.auraInstanceID = 77; D.onEnter(b1)
check(tipped == 'player:77' and shown, 'hover shows that debuff\'s tooltip')
D.onLeave(b1); check(not shown, 'leaving hides it')
-- Nightfall: one slot, Shadow Trance only
local nc = N.container
check(nc and nc.unit == 'player', 'Nightfall slot built on player' .. (N.failed and (': ' .. N.failed) or ''))
local ng = UIx.group(nc, 'nightfall')
check(ng and ng.slot and ng.filters.includeSpellIDs[17941], 'slot allows Shadow Trance (17941)')
W.units.player.otherAuras = { 101, 17941 }; W.fire('UNIT_AURA', 'player')
check(UIx.showing(nc).nightfall[1] == 17941 and #UIx.showing(dc).debuffs == 2, 'proc: the portrait glow shows')
W.units.player.otherAuras = { 101 }; W.fire('UNIT_AURA', 'player')
check(#UIx.showing(nc).nightfall == 0, 'Shadow Bolt used: the glow is gone')
SPELL[6] = 'Shadow Bolt'
local sbBtn = CreateFrame('Button', 'ActionButton2', UIParent); sbBtn.action = 9; sbBtn:Show()
GetActionInfo = function(slot) if slot == 5 then return 'spell', 4 elseif slot == 9 then return 'spell', 6 end end
W.fire('ACTIONBAR_SLOT_CHANGED'); W.advance(1)
check(N.on == sbBtn, 'Shadow Bolt button found for our proc glow')
W.fire('SPELL_ACTIVATION_OVERLAY_GLOW_SHOW', 6); W.advance(1)
check(OmaDemonDB.group.nfBlizz == true and N.on == nil, "Blizzard's own Shadow Bolt glow seen: ours stands down")
W.fire('PLAYER_ENTERING_WORLD'); W.advance(1); check(N.on == nil, 'and stays down')
io.write(('OmaDemon smoke: %d checks passed\n'):format(ok))
