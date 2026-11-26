-- Offline tests for OmaPad:  luajit tests/run.lua [pattern]   (from the OmaPad folder; texlua works too)
-- A small fake WoW: spells by name, action slots, macros, bags. Every test loads OmaPad.lua fresh, the way the game
-- does: the file runs first, then the saved variables arrive, then the slash command is used.
local pattern = arg and arg[1]

local SPELL_IDS, nextId = {}, 1000
local function spellId(name) if not SPELL_IDS[name] then nextId = nextId + 1; SPELL_IDS[name] = nextId end; return SPELL_IDS[name] end
local SPELL_NAMES = setmetatable({}, { __index = function(_, id) for n, i in pairs(SPELL_IDS) do if i == id then return n end end end })

local W -- the current fake world
local function newWorld(class, name)
  W = { class = class, name = name, known = {}, slots = {}, macros = {}, bags = {}, cursor = nil, said = {} }
  local function frame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    function f:HookScript() end
    return f
  end
  _G.CreateFrame = frame
  _G.UnitClass = function() return class:sub(1, 1) .. class:sub(2):lower(), class end
  _G.UnitName = function() return W.name end
  _G.UnitLevel = function() return 20 end
  _G.InCombatLockdown = function() return false end
  _G.GetTime = function() return 0 end
  _G.date = os.date
  _G.print = function(m) W.said[#W.said + 1] = m end
  _G.SlashCmdList = {}
  _G.C_Timer = { After = function() end }
  _G.C_Spell = {
    GetSpellInfo = function(n) return { spellID = spellId(n) } end,
    GetSpellName = function(id) return SPELL_NAMES[id] end,
    PickupSpell = function(id) W.cursor = { 'spell', id } end,
  }
  _G.IsPlayerSpell = function(id) return W.known[SPELL_NAMES[id]] == true end
  _G.C_Item = {
    GetItemCount = function(id) return W.bags[id] or 0 end,
    PickupItem = function(id) W.cursor = { 'item', id } end,
    GetItemInfoInstant = function() return nil end,
    GetItemInfo = function() return nil end,
  }
  _G.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemID = function() return nil end }
  _G.HasAction = function(s) return W.slots[s] ~= nil end
  _G.GetActionInfo = function(s) local a = W.slots[s]; if a then return a[1], a[2] end end
  _G.ClearCursor = function() W.cursor = nil end
  _G.GetCursorInfo = function() return W.cursor and W.cursor[1] end
  _G.PlaceAction = function(s) W.slots[s] = W.cursor; W.cursor = nil end
  _G.PickupAction = function(s) W.cursor = W.slots[s]; W.slots[s] = nil end
  _G.GetMacroIndexByName = function(n) for i, m in ipairs(W.macros) do if m.name == n then return i end end; return 0 end
  _G.GetMacroInfo = function(i) local m = W.macros[i]; if m then return m.name, m.icon, m.body end end
  _G.CreateMacro = function(n, icon, body) W.macros[#W.macros + 1] = { name = n, icon = icon, body = body }; return #W.macros end
  _G.EditMacro = function(i, n, icon, body) W.macros[i] = { name = n, icon = icon, body = body } end
  _G.DeleteMacro = function(i) table.remove(W.macros, i) end
  _G.PickupMacro = function(n) W.cursor = { 'macro', GetMacroIndexByName(n) } end
  _G.GetPetActionInfo = function() return nil end
  return W
end

-- load the add-on the way the game does, then hand it its saved variables
local function load(class, name, acct, char)
  newWorld(class, name)
  OmaPadDB, OmaPadCharDB = nil, nil
  dofile('OmaPad.lua')
  OmaPadDB, OmaPadCharDB = acct or {}, char
  return W
end
local function pad(m) SlashCmdList.OMASHUPAD(m or '') end

-- slot numbers, as in OmaPad.lua
local L, U, R, D, X, Y, B, A = 0, 1, 2, 3, 4, 5, 6, 7
local BAR = { none = 0, LT = 4, RT = 12, LTRT = 20 }
local function slotOf(set, bar, btn) return 181 + (set - 1) * 28 + BAR[bar] + btn end
local function spellOn(set, bar, btn) local a = W.slots[slotOf(set, bar, btn)]; return a and a[1] == 'spell' and SPELL_NAMES[a[2]] or nil end
local function learn(list) for _, n in ipairs(list) do W.known[n] = true end end

local function eq(a, b, msg) if a ~= b then error((msg or 'eq') .. ': expected ' .. tostring(b) .. ', got ' .. tostring(a), 2) end end
local function ok(v, msg) if not v then error(msg or 'expected true', 2) end end

local tests = {}

tests['warlock: old account-wide memory moves onto the warlock; his buttons stay'] = function()
  -- what the old version left in OmaPadDB: Corruption on RT X (placed by the add-on), his own thing on RT Y
  local cor, own = slotOf(1, 'RT', X), slotOf(1, 'RT', Y)
  local acct = { mine = { [cor] = 'spell:Corruption' }, his = { [own] = 'spell:Fireball' }, rulesV = 1, layoutV = 10,
                 vendorV = 1, settingsV = 4 }
  load('WARLOCK', 'Bujuju', acct, nil)
  learn({ 'Corruption', 'Fireball' })
  W.slots[cor] = { 'spell', spellId('Corruption') }
  W.slots[own] = { 'spell', spellId('Fireball') }
  pad()
  eq(OmaPadCharDB.mine[cor], 'spell:Corruption', 'mine moved to the character')
  eq(OmaPadCharDB.his[own], 'spell:Fireball', 'his moved to the character')
  eq(OmaPadCharDB.layoutV, 16, 'moved, then updated to v16')
  eq(OmaPadDB.mine, nil, 'account copy removed'); eq(OmaPadDB.his, nil)
  eq(OmaPadDB.padMovedTo, 'Bujuju')
  eq(OmaPadDB.vendorV, 1, 'account settings untouched'); eq(OmaPadDB.settingsV, 4)
  eq(spellOn(1, 'RT', X), 'Corruption', 'Corruption still there'); eq(spellOn(1, 'RT', Y), 'Fireball', 'his button kept')
end

tests['paladin: never takes the warlock memory, even logging in first'] = function()
  local acct = { mine = { [slotOf(1, 'RT', X)] = 'spell:Corruption' }, his = {}, rulesV = 1, layoutV = 10 }
  load('PALADIN', 'Pally', acct, nil)
  learn({ 'Judgement' })
  pad()
  ok(OmaPadDB.mine and OmaPadDB.mine[slotOf(1, 'RT', X)], 'warlock memory still waiting for the warlock')
  eq(OmaPadDB.padMovedTo, nil)
  eq(OmaPadCharDB.his[slotOf(1, 'RT', X)], nil, 'the warlock slot is not read as his')
  eq(spellOn(1, 'RT', X), 'Judgement', 'paladin pull button filled')
end

tests['paladin: level 6 fills the pull, the seal and Holy Light once'] = function()
  load('PALADIN', 'Pally', {}, nil)
  learn({ 'Seal of Righteousness', 'Holy Light', 'Devotion Aura', 'Judgement', 'Blessing of Might', 'Holy Strike',
          'Seal of the Crusader', 'Divine Protection', 'Will to Survive', 'Perception' })
  pad()
  eq(spellOn(1, 'RT', X), 'Judgement'); eq(spellOn(1, 'RT', Y), 'Holy Strike')
  eq(spellOn(1, 'none', U), 'Seal of Righteousness', 'main seal'); eq(spellOn(1, 'none', D), nil, 'no second Righteousness yet')
  eq(spellOn(1, 'none', L), 'Seal of the Crusader')
  eq(spellOn(1, 'LT', X), 'Holy Light'); eq(spellOn(1, 'LT', Y), nil, 'no second Holy Light yet')
  eq(spellOn(1, 'LT', D), 'Divine Protection')
  eq(spellOn(1, 'RT', D), 'Will to Survive', 'stun break racial on the warlock racial button')
  eq(spellOn(1, 'LT', U), 'Perception')
  eq(spellOn(1, 'LTRT', D), 'Devotion Aura'); eq(spellOn(1, 'LTRT', B), 'Blessing of Might')
  ok(GetMacroIndexByName('Meters') > 0, 'Meters macro made')
  eq(GetMacroIndexByName('PetFight'), 0, 'no demon macros on a paladin'); eq(GetMacroIndexByName('PetHome'), 0)
end

tests['paladin v2: First Aid, Cooking, Fishing and the best bandage on set 2 LT+RT'] = function()
  load('PALADIN', 'Pally', {}, nil)
  W.bags[3530] = 5; W.bags[6450] = 3                                -- wool, silk bandages
  learn({ 'First Aid', 'Cooking', 'Fishing', 'Holy Light' }); pad()
  eq(spellOn(2, 'LTRT', D), 'First Aid'); eq(spellOn(2, 'LTRT', R), 'Cooking'); eq(spellOn(2, 'LTRT', L), 'Fishing')
  local a = W.slots[slotOf(2, 'LTRT', B)]
  ok(a and a[1] == 'item' and a[2] == 6450, 'silk bandage (the best) on set 2 LT+RT B')
  eq(OmaPadCharDB.layoutV, 2, 'paladin layout v2')
end

tests['warlock: Well Fed food with an unreadable number still goes on the food button; Pointer macro retired'] = function()
  load('WARLOCK', 'Bujuju', {}, nil)
  W.macros[1] = { name = 'Pointer', icon = 1, body = '/click OmaPointerToggle' }
  W.bags[21072] = 3                                                 -- Smoked Sagefish
  C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end
  C_Container.GetContainerItemID = function(bag, slot) if bag == 0 and slot == 1 then return 21072 end end
  C_Item.GetItemInfoInstant = function(id) if id == 21072 then return id, nil, nil, nil, nil, 0, 5 end end
  C_Item.GetItemInfo = function(id) if id == 21072 then return 'Smoked Sagefish', nil, nil, nil, 10 end end
  _G.C_TooltipInfo = { GetBagItem = function() return { lines = { { leftText = 'Smoked Sagefish' },
    { leftText = 'Use: Eat to recover over 21 sec. If you spend at least 10 seconds eating you will become well fed.' } } } end }
  pad()
  _G.C_TooltipInfo = nil
  local a = W.slots[slotOf(2, 'LTRT', B)]
  ok(a and a[1] == 'item' and a[2] == 21072, 'Sagefish on the food button')
  eq(GetMacroIndexByName('Pointer'), 0, 'dead Pointer macro deleted')
  ok(OmaPadCharDB.foodScan[1]:find('Eat to recover'), 'tooltip line kept in foodScan')
end

tests['paladin: level 20 upgrades in place and the old spell drops to its second button'] = function()
  load('PALADIN', 'Pally', {}, nil)
  learn({ 'Seal of Righteousness', 'Holy Light', 'Devotion Aura', 'Judgement', 'Divine Protection' })
  pad()
  learn({ 'Seal of Command', 'Flash of Light', 'Retribution Aura', 'Consecration', 'Exorcism', 'Blessing of Kings' })
  pad()
  eq(spellOn(1, 'none', U), 'Seal of Command', 'main seal upgraded'); eq(spellOn(1, 'none', D), 'Seal of Righteousness', 'swap seal')
  eq(spellOn(1, 'LT', X), 'Flash of Light'); eq(spellOn(1, 'LT', Y), 'Holy Light')
  eq(spellOn(1, 'LTRT', D), 'Retribution Aura', 'aura upgraded')
  eq(spellOn(1, 'RT', B), 'Consecration'); eq(spellOn(1, 'RT', A), 'Exorcism'); eq(spellOn(1, 'LTRT', A), 'Blessing of Kings')
  learn({ 'Divine Shield' }); pad()
  eq(spellOn(1, 'LT', D), 'Divine Shield', 'Divine Protection -> Divine Shield')
end

tests['paladin: a button he changes is his for good'] = function()
  load('PALADIN', 'Pally', {}, nil)
  learn({ 'Seal of Righteousness', 'Judgement' })
  pad()
  W.slots[slotOf(1, 'none', U)] = { 'spell', spellId('Seal of the Crusader') }   -- he puts Crusader on D-pad up
  pad()
  learn({ 'Seal of Command' }); pad()
  eq(spellOn(1, 'none', U), 'Seal of the Crusader', 'his choice kept, no upgrade over it')
end

tests['paladin: buttons he placed before the add-on are left alone'] = function()
  load('PALADIN', 'Pally', {}, nil)
  W.slots[slotOf(1, 'RT', X)] = { 'spell', spellId('Holy Strike') }
  learn({ 'Judgement', 'Holy Strike' })
  pad()
  eq(spellOn(1, 'RT', X), 'Holy Strike', 'his pre-existing button kept')
  eq(OmaPadCharDB.mine[slotOf(1, 'RT', X)], nil, 'not adopted as the add-on\'s')
end

tests['sim: both classes pass'] = function()
  load('PALADIN', 'Pally', {}, nil); pad('sim')
  ok(OmaPadCharDB.sim and OmaPadCharDB.sim.pass, 'paladin sim: ' .. table.concat(OmaPadCharDB.sim and OmaPadCharDB.sim.steps or {}, '\n'))
  load('WARLOCK', 'Bujuju', {}, nil); pad('sim')
  ok(OmaPadCharDB.sim and OmaPadCharDB.sim.pass, 'warlock sim: ' .. table.concat(OmaPadCharDB.sim and OmaPadCharDB.sim.steps or {}, '\n'))
end

tests['warlock v11: Succubus stays the main demon, Felhunter never gets a button'] = function()
  load('WARLOCK', 'Bujuju', {}, nil)
  learn({ 'Summon Imp', 'Summon Voidwalker', 'Summon Succubus', 'Summon Felhunter' }); pad()
  eq(spellOn(1, 'LTRT', D), 'Summon Succubus', 'main demon button')
  eq(spellOn(2, 'LTRT', U), 'Summon Imp', 'Imp kept for the odd swap')
  for s = 181, 264 do local a = W.slots[s]; ok(not (a and SPELL_NAMES[a[2]] == 'Summon Felhunter'), 'Felhunter placed on ' .. s) end
end

tests['warlock v11: Wrack, Amplify Curse, curses and Subjugate get their buttons; no Shadow Ward'] = function()
  load('WARLOCK', 'Bujuju', {}, nil)
  learn({ 'Curse of Weakness', 'Curse of Recklessness', 'Curse of the Elements', 'Curse of Tongues', 'Wrack', 'Amplify Curse', 'Subjugate Demon',
          'Drain Mana', 'Health Funnel', 'Shadow Ward' }); pad()
  eq(spellOn(1, 'none', L), 'Wrack'); eq(spellOn(1, 'LT', D), 'Amplify Curse')
  eq(spellOn(1, 'RT', L), 'Curse of the Elements'); eq(spellOn(1, 'LTRT', X), 'Curse of Recklessness', 'v16: Recklessness on set 1'); eq(spellOn(2, 'RT', B), 'Curse of Weakness', 'v16: Weakness on set 2'); eq(spellOn(1, 'LTRT', R), 'Curse of Tongues', 'Tongues on set 1')
  eq(spellOn(2, 'LT', R), 'Subjugate Demon', 'renamed spell fills'); eq(spellOn(2, 'LTRT', R), 'Health Funnel'); eq(spellOn(2, 'LTRT', L), 'Drain Mana')
  for s = 181, 264 do local a = W.slots[s]; ok(not (a and SPELL_NAMES[a[2]] == 'Shadow Ward'), 'Shadow Ward placed on ' .. s) end
end

tests['warlock v10 -> v11: only the add-on\'s buttons move, his stay'] = function()
  local hf, mine, his = slotOf(1, 'none', L), slotOf(1, 'RT', X), slotOf(1, 'RT', Y)
  local acct = { mine = { [hf] = 'spell:Health Funnel', [mine] = 'spell:Corruption' }, his = { [his] = 'spell:Fireball' }, rulesV = 1, layoutV = 10 }
  load('WARLOCK', 'Bujuju', acct, nil)
  learn({ 'Health Funnel', 'Corruption', 'Fireball', 'Wrack' })
  W.slots[hf] = { 'spell', spellId('Health Funnel') }; W.slots[mine] = { 'spell', spellId('Corruption') }; W.slots[his] = { 'spell', spellId('Fireball') }
  pad()
  eq(OmaPadCharDB.layoutV, 16)
  eq(spellOn(1, 'none', L), 'Wrack', 'Health Funnel slot now Wrack'); eq(spellOn(2, 'LTRT', R), 'Health Funnel', 'Funnel moved to set 2')
  eq(spellOn(1, 'RT', X), 'Corruption', 'Corruption re-placed'); eq(spellOn(1, 'RT', Y), 'Fireball', 'his button kept')
end

tests['warlock v14: best bandage on set 1, First Aid on set 2, no drink'] = function()
  load('WARLOCK', 'Bujuju', {}, nil)
  W.bags[3530] = 5; W.bags[6450] = 3; W.bags[1645] = 10            -- wool, silk bandages, water
  learn({ 'First Aid', 'Tailoring', 'Find Minerals' }); pad()
  local a = W.slots[slotOf(1, 'LTRT', Y)]
  ok(a and a[1] == 'item' and a[2] == 6450, 'silk bandage (the best) on LT+RT Y')
  eq(spellOn(2, 'LTRT', D), 'First Aid')
  W.bags[16893] = 1; pad()
  local st = W.slots[slotOf(1, 'LTRT', L)]; ok(st and st[1] == 'item' and st[2] == 16893, 'Soulstone on LT+RT left')
  for s = 181, 264 do local b = W.slots[s]; ok(not (b and b[1] == 'item' and b[2] == 1645), 'water placed on ' .. s)
    ok(not (b and b[1] == 'spell' and (SPELL_NAMES[b[2]] == 'Tailoring' or SPELL_NAMES[b[2]] == 'Find Minerals')), 'dropped spell on ' .. s) end
end

tests['other classes: only the Meters macro, no buttons'] = function()
  load('MAGE', 'Someone', {}, nil)
  learn({ 'Fireball' }); pad()
  local any = false; for s in pairs(W.slots) do any = true end
  ok(not any, 'no buttons placed'); ok(GetMacroIndexByName('Meters') > 0)
end

local names = {}; for n in pairs(tests) do names[#names + 1] = n end; table.sort(names)
local pass, fail = 0, 0
for _, n in ipairs(names) do
  if not pattern or n:find(pattern, 1, true) then
    local good, err = pcall(tests[n])
    if good then pass = pass + 1; io.write('ok   ', n, '\n') else fail = fail + 1; io.write('FAIL ', n, '\n  ', tostring(err), '\n') end
  end
end
io.write(('%d passed, %d failed\n'):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
