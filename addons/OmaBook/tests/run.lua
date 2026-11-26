-- Offline tests for OmaBook:  luajit tests/run.lua   (from the OmaBook folder)
local W
local function world()
  W = { events = nil, timers = {} }
  _G.OmaBookDB = nil
  _G.time = function() return 1800000000 end
  _G.UnitName = function() return 'Bunji' end
  _G.GetRealmName = function() return 'Realm' end
  _G.UnitFactionGroup = function() return 'Alliance', 'Alliance' end
  _G.UnitClass = function() return 'Paladin', 'PALADIN' end
  _G.UnitLevel = function() return 23 end
  _G.GetRealZoneText = function() return 'Duskwood' end
  _G.UnitXP = function() return 410 end
  _G.UnitXPMax = function() return 1000 end
  _G.C_Timer = { After = function(_, fn) W.timers[#W.timers + 1] = fn end }
  _G.CreateFrame = function() local fr = {}; function fr:RegisterEvent() end; function fr:SetScript(_, fn) W.events = fn end; return fr end
  _G.C_Spell = { GetSpellName = function(id) return ({ [1311074] = 'Sanctified Judgement', [20060] = 'Deflection' })[id] end }
  _G.C_ClassTalents = { GetActiveConfigID = function() return 7 end }
  _G.C_Traits = {
    GetConfigInfo = function() return { treeIDs = { 1100 } } end,
    GetTreeCurrencyInfo = function() return { { quantity = 1 } } end,
    GetTreeNodes = function() return { 1, 2, 3 } end,
    GetNodeInfo = function(_, n) return ({ { activeRank = 5, entryIDs = { 10 } }, { activeRank = 1, entryIDs = { 20 } }, { activeRank = 0, entryIDs = { 30 } } })[n] end,
    GetEntryInfo = function(_, e) return { definitionID = e } end,
    GetDefinitionInfo = function(d) return { spellID = ({ [10] = 20060, [20] = 1311074, [30] = 9 })[d] } end }
  _G.Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2 } }
  _G.C_Spell.GetSpellLevelLearned = function(id) return ({ [26573] = 20, [879] = 20, [24275] = 44 })[id] end
  _G.C_SpellBook = { GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 6 } end,
    GetSpellBookItemInfo = function(i) return ({ { name = 'Judgement' }, { name = 'Holy Strike' }, { name = 'Two-Handed Weapon Spec', isPassive = true },
      { name = 'Consecration', spellID = 26573, itemType = 2 }, { name = 'Exorcism', spellID = 879, itemType = 2 }, { name = 'Hammer of Wrath', spellID = 24275, itemType = 2 } })[i] end }
  _G.GetNumSkillLines = function() return 3 end
  _G.GetSkillLineInfo = function(i) return ({ { 'Weapon Skills', true }, { 'Two-Handed Maces', false, nil, 110 }, { 'First Aid', false, nil, 60 } })[i][1],
    ({ true, false, false })[i], nil, ({ nil, 110, 60 })[i] end
  _G.GetInventoryItemID = function() return 6953 end
  _G.GetInventoryItemLink = function() return '|cff0070dd|Hitem:6953::::|h[Verigan\'s Fist]|h|r' end
  _G.C_Item = { GetItemStats = function() return { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 25.63 } end, GetItemNameByID = function() return "Verigan's Fist" end,
    GetItemInfoInstant = function() return 6953, 'Weapon', 'Two-Handed Maces', 'INVTYPE_2HWEAPON', 0, 2, 5 end }
  _G.C_Container = { GetContainerNumSlots = function(b) return b == 0 and 3 or 0 end,
    GetContainerItemInfo = function(b, s) return ({ { itemID = 5480, stackCount = 3 }, { itemID = 5480, stackCount = 5 }, nil })[s] end }
  _G.C_QuestLog = { IsQuestFlaggedCompleted = function(q) return q == 1806 end, GetNumQuestLogEntries = function() return 2 end,
    GetInfo = function(i) return ({ { isHeader = true }, { questID = 78088 } })[i] end }
  _G.CheapUpgrades = { db = { richMode = false, maxPrice = 50000 }, results = { { link = '|Hitem:2264::|h[x]|h', name = 'Ringed Chestguard', slot = 'Chest', price = 11000, pct = 64 } } }
  dofile('OmaBook.lua')
end
local function eq(a, b, m) if a ~= b then error((m or 'eq') .. ': expected ' .. tostring(b) .. ', got ' .. tostring(a), 2) end end
local function ok(v, m) if not v then error(m or 'expected true', 2) end end
local tests = {}
tests['save writes one JSON string with everything the book needs'] = function()
  world(); OmaBook.save()
  local j = OmaBookDB.json
  ok(j:find('"name":"Bunji"', 1, true), 'name'); ok(j:find('"zone":"Duskwood"', 1, true), 'zone'); ok(j:find('"level":23', 1, true), 'level'); ok(j:find('"unspent":1', 1, true), 'unspent')
  ok(j:find('"Deflection":5', 1, true) and j:find('"Sanctified Judgement":1', 1, true), 'talent ranks'); ok(not j:find('"9"', 1, true), 'no unbought talents')
  ok(j:find('"spells":["Holy Strike","Judgement"]', 1, true), 'active spells, sorted, no passives')
  ok(j:find('"Two-Handed Maces":110', 1, true) and j:find('"First Aid":60', 1, true), 'skills'); ok(not j:find('Weapon Skills', 1, true), 'no headers')
  ok(j:find('"train":[{"lvl":20,"name":"Consecration"},{"lvl":20,"name":"Exorcism"}]', 1, true), 'trainable spells, not the far-off ones')
  ok(not j:find('"spells":[^]]*Consecration'), 'future spells are not known spells')
  ok(j:find('"sub":5', 1, true), 'weapon subclass')
  ok(j:find('"dps":25.63', 1, true) and j:find('"id":6953', 1, true), 'weapon')
  ok(j:find('"5480":8', 1, true), 'bag counts summed across stacks')
  ok(j:find('"1806":true', 1, true) and not j:find('"78093":true', 1, true), 'class quests done')
  ok(j:find('"log":[78088]', 1, true), 'quest log ids, no headers')
  ok(j:find('"pct":64', 1, true) and j:find('"rich":false', 1, true) and j:find('"max":50000', 1, true), 'cheap upgrades')
end
tests['events save a few seconds later, logout saves at once'] = function()
  world(); W.events(nil, 'BAG_UPDATE_DELAYED'); eq(OmaBookDB, nil, 'not yet'); W.timers[1](); ok(OmaBookDB and OmaBookDB.json, 'saved after the delay')
  world(); W.events(nil, 'PLAYER_LOGOUT'); ok(OmaBookDB and OmaBookDB.json, 'logout saves now')
end
tests['a broken game API never breaks the save'] = function()
  world(); _G.C_Traits = nil; _G.CheapUpgrades = nil; _G.C_SpellBook = nil; OmaBook.save()
  ok(OmaBookDB.json:find('"level":23', 1, true), 'still saved'); ok(OmaBookDB.json:find('"talents":[]', 1, true), 'empty talents')
end
tests['JSON escapes quotes and control characters'] = function()
  world(); eq(OmaBook.enc({ a = 'x"y\n' }), '{"a":"x\\"y\\n"}')
end
local pass, fail = 0, 0
local names = {}; for n in pairs(tests) do names[#names + 1] = n end; table.sort(names)
for _, n in ipairs(names) do local good, err = pcall(tests[n]); if good then pass = pass + 1; io.write('ok   ' .. n .. '\n') else fail = fail + 1; io.write('FAIL ' .. n .. '\n     ' .. tostring(err) .. '\n') end end
io.write(pass .. ' passed, ' .. fail .. ' failed\n'); os.exit(fail == 0 and 0 or 1)
