-- Offline tests for OmaPad:  luajit tests/run.lua [pattern]   (from the OmaPad folder; texlua works too)
-- A small fake WoW: spells by name, action slots, macros, bags. Every test loads OmaPad.lua fresh, the way the game
-- does: the file runs first, then the saved variables arrive, then the slash command is used.
local pattern = arg and arg[1]

local SPELL_IDS, nextId = {}, 1000
local function spellId(name) if not SPELL_IDS[name] then nextId = nextId + 1; SPELL_IDS[name] = nextId end; return SPELL_IDS[name] end
local RANKS = {}                                     -- higher-rank ids: id -> name (a rank upgrade keeps the name)
local SPELL_NAMES = setmetatable({}, { __index = function(_, id) if RANKS[id] then return RANKS[id] end
  for n, i in pairs(SPELL_IDS) do if i == id then return n end end end })
-- a widget that takes any call (the drawing code's textures and animations); Create* hand back more of them
local function tolerant()
  return setmetatable({}, { __index = function(_, k)
    if type(k) == 'string' and k:match('^Create') then return function() return tolerant() end end
    if k == 'IsShown' or k == 'IsVisible' then return function() return false end end
    return function() return nil end
  end })
end

local W -- the current fake world
local function newWorld(class, name)
  W = { class = class, name = name, known = {}, slots = {}, macros = {}, bags = {}, cursor = nil, said = {}, rank = {}, sounds = {} }
  _G.GetActionTexture = function(s) if W.slots[s] then return 'icon' .. s end end
  _G.PlaySound = function(k, ch) W.sounds[#W.sounds + 1] = tostring(k) .. '/' .. tostring(ch) end
  _G.SOUNDKIT = { IG_QUEST_LIST_COMPLETE = 618 }
  _G.EnumerateFrames = nil; _G.UIParent = nil; _G.UnitAffectingCombat = nil
  W.frames = {}
  local function frame()
    local f = setmetatable({ ev = {} }, getmetatable(tolerant()))
    function f:RegisterEvent(e) self.ev[e] = true end
    function f:SetScript(k, fn) self[k] = fn end
    function f:HookScript() end
    W.frames[#W.frames + 1] = f
    return f
  end
  -- fire an event at every add-on frame that asked for it
  W.fire = function(e, ...) for _, f in ipairs(W.frames) do if f.ev[e] and f.OnEvent then f:OnEvent(e, ...) end end end
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
    GetSpellInfo = function(n) return { spellID = W.rank[n] or spellId(n) } end,
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

-- a movable window for the layout tests: where it is, its scale, shown or not
local function win(name, l, t, w, h)
  local f = { pts = { { 'CENTER', nil, 'CENTER', 0, 0 } }, scale = 1, shown = true, l = l, t = t, w = w, h = h }
  function f:GetNumPoints() return #self.pts end
  function f:GetPoint(i) return unpack(self.pts[i]) end
  function f:ClearAllPoints() self.pts = {} end
  function f:SetPoint(...) self.pts[#self.pts + 1] = { ... } end
  function f:SetScale(s) self.scale = s end
  function f:GetScale() return self.scale end
  function f:GetEffectiveScale() return self.scale end
  function f:IsShown() return self.shown end
  function f:IsVisible() return self.shown end
  function f:GetEffectiveAlpha() return self.alpha or 1 end
  function f:GetLeft() return self.l end
  function f:GetTop() return self.t end
  function f:GetRight() return self.l and self.l + self.w end
  function f:GetBottom() return self.t and self.t - self.h end
  function f:GetWidth() return self.w end
  function f:HookScript() end
  function f:SetAnchorType(a) self.anchor = a end
  _G[name] = f
  return f
end
local function layoutWorld()
  local w = load('PALADIN', 'Bunji')
  _G.C_Timer = { After = function(_, fn) fn() end }
  _G.hooksecurefunc = function() end
  _G.UIParent = { GetEffectiveScale = function() return 1 end }
  _G.wipe = function(t) for k in pairs(t) do t[k] = nil end end
  _G.unpack = unpack
  _G.NotGameTooltipKroGamepadBags = nil; _G.KroGamepadBagsDoll = nil     -- left over from another test
  _G.ShoppingTooltip1 = nil; _G.ShoppingTooltip2 = nil
  w.merchant = win('MerchantFrame', 20, 700, 340, 440)
  w.bags = win('KroGamepadBagsFrame', 900, 500, 300, 400)
  w.tip = win('GameTooltip', 500, 400, 250, 120)
  w.ah = win('ImprovedForeverAuctionBuy', 100, 700, 800, 500)
  return w
end

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
  -- v4 (2026-11-27): RT is the whole attack, seal beside Judgement; Crusader on set 2
  eq(spellOn(1, 'RT', X), 'Judgement'); eq(spellOn(1, 'RT', Y), 'Seal of Righteousness', 'main seal beside Judgement')
  eq(spellOn(1, 'RT', B), 'Holy Strike'); eq(spellOn(1, 'RT', R), nil, 'no second Righteousness yet')
  eq(spellOn(2, 'LTRT', B), 'Seal of the Crusader', 'Crusader off the attack section')
  eq(spellOn(1, 'LT', X), 'Holy Light'); eq(spellOn(1, 'LT', Y), nil, 'no second Holy Light yet')
  eq(spellOn(1, 'LT', A), 'Divine Protection')
  eq(spellOn(1, 'LT', D), 'Will to Survive', 'racial on LT (getting out of trouble)')
  eq(spellOn(1, 'LT', U), 'Perception')
  eq(spellOn(1, 'LTRT', B), 'Devotion Aura'); eq(spellOn(1, 'none', U), 'Blessing of Might', 'blessing on the bare D-pad')
  ok(GetMacroIndexByName('Meters') > 0, 'Meters macro made')
  eq(GetMacroIndexByName('PetFight'), 0, 'no demon macros on a paladin'); eq(GetMacroIndexByName('PetHome'), 0)
end

tests['paladin v2: First Aid, Cooking, Fishing and the best bandage on set 2 LT+RT'] = function()
  load('PALADIN', 'Pally', {}, nil)
  W.bags[3530] = 5; W.bags[6450] = 3                                -- wool, silk bandages
  learn({ 'First Aid', 'Cooking', 'Fishing', 'Holy Light' }); pad()
  eq(spellOn(2, 'LTRT', D), 'First Aid'); eq(spellOn(2, 'LTRT', R), 'Cooking'); eq(spellOn(2, 'LTRT', L), 'Fishing')
  local a = W.slots[slotOf(1, 'none', L)]
  ok(a and a[1] == 'item' and a[2] == 6450, 'silk bandage (the best) on the bare D-pad left (v4)')
  eq(OmaPadCharDB.layoutV, 4, 'paladin layout v4')
end

tests['paladin v3: Mastercraft and Polestar on/off on set 1 LT+RT left and right'] = function()
  load('PALADIN', 'Pally', {}, nil)
  learn({ 'Holy Light', 'Find Minerals', 'Blacksmithing' }); pad()
  local function macroOn(set, mod, b) local a = W.slots[slotOf(set, mod, b)]; return a and a[1] == 'macro' and W.macros[a[2]] and W.macros[a[2]].name end
  eq(macroOn(1, 'LTRT', L), 'Mastercraft'); eq(macroOn(1, 'LTRT', R), 'Polestar')
  local body; for _, m in pairs(W.macros) do if m.name == 'Polestar' then body = m.body end end
  ok(body == '/run if Polestar and Polestar.ToggleHidden then Polestar.ToggleHidden() end', 'hides and shows all of Polestar')
  local mc; for _, m in pairs(W.macros) do if m.name == 'Mastercraft' then mc = m.body end end
  ok(mc == '/mc', 'Mastercraft opens its window')
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

tests['new character: the game\'s own starting buttons are laid out by the add-on, nothing doubled'] = function()
  load('PALADIN', 'Bunji', {}, nil)
  _G.UnitLevel = function() return 1 end
  learn({ 'Seal of Righteousness', 'Will to Survive', 'Perception', 'Holy Light' })
  W.slots[slotOf(1, 'none', U)] = { 'spell', spellId('Will to Survive') }   -- the game put these here at creation
  W.slots[slotOf(1, 'none', D)] = { 'spell', spellId('Perception') }
  pad()
  eq(spellOn(1, 'RT', Y), 'Seal of Righteousness', 'main seal beside Judgement')
  eq(spellOn(1, 'LT', D), 'Will to Survive', 'racial on its own button')
  eq(spellOn(1, 'none', U), nil, 'starting extra cleared (no blessing known yet)')
  eq(spellOn(1, 'none', D), nil, 'starting extra cleared (no bombs in the bags)')
  eq(#(OmaPadCharDB.check.dups), 0, 'no duplicates')
  eq(OmaPadCharDB.fresh, nil, 'one time only')
end

tests['paladin: level 20 upgrades in place and the old spell drops to its second button'] = function()
  load('PALADIN', 'Pally', {}, nil)
  learn({ 'Seal of Righteousness', 'Holy Light', 'Devotion Aura', 'Judgement', 'Divine Protection' })
  pad()
  learn({ 'Seal of Command', 'Flash of Light', 'Retribution Aura', 'Consecration', 'Exorcism', 'Blessing of Kings' })
  pad()
  eq(spellOn(1, 'RT', Y), 'Seal of Command', 'main seal upgraded'); eq(spellOn(1, 'RT', R), 'Seal of Righteousness', 'swap seal')
  eq(spellOn(1, 'LT', X), 'Flash of Light'); eq(spellOn(1, 'LT', Y), 'Holy Light')
  eq(spellOn(1, 'LTRT', B), 'Retribution Aura', 'aura upgraded')
  eq(spellOn(1, 'RT', L), 'Consecration'); eq(spellOn(1, 'RT', A), 'Exorcism'); eq(spellOn(1, 'none', U), 'Blessing of Kings', 'Might -> Kings')
  learn({ 'Divine Shield' }); pad()
  eq(spellOn(1, 'LT', A), 'Divine Shield', 'Divine Protection -> Divine Shield')
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

tests['layouts: a vendor closed in combat is put back when combat ends; tooltips go free at once'] = function()
  local w = layoutWorld()
  w.fire('MERCHANT_SHOW')
  ok(w.bags.scale == 0.9, 'bags at 90% beside the vendor')
  local combat = true; _G.InCombatLockdown = function() return combat end
  w.merchant.shown = false; w.fire('MERCHANT_CLOSED')
  ok(w.bags.scale == 0.9, 'in combat nothing moves')
  combat = false; w.fire('PLAYER_REGEN_ENABLED')
  ok(w.bags.scale == 1 and w.bags.pts[1][1] == 'CENTER', 'combat over: bags back where they were')
end
tests['layouts: the auction house closing hands back to a vendor window still open, and ends cleanly'] = function()
  local w = layoutWorld()
  w.merchant.shown = false
  w.fire('AUCTION_HOUSE_SHOW')
  ok(w.ah.scale == 1.05 and w.bags.scale == 0.79, 'auction house layout')
  w.merchant.shown = true                       -- the auctioneer's own window is still up
  w.fire('AUCTION_HOUSE_CLOSED')
  ok(w.ah.scale == 1 and w.ah.pts[1][1] == 'CENTER', 'auction house put back')
  ok(w.bags.scale == 0.9, 'the open NPC window gets its layout')
  w.merchant.shown = false; w.fire('MERCHANT_CLOSED')
  ok(w.bags.scale == 1 and w.bags.pts[1][1] == 'CENTER', 'all back to normal')
end
tests['bags alone: their tooltip goes left of the bag window, the world tooltip is not touched'] = function()
  local w = layoutWorld()
  w.merchant.shown = false
  local kt = win('NotGameTooltipKroGamepadBags', 1100, 600, 250, 120)
  w.fire('PLAYER_ENTERING_WORLD')
  OmaPadPutTipsForTest()
  local p = kt.pts[1]
  ok(p and p[1] == 'TOPRIGHT' and p[3] == 'TOPLEFT', 'anchored by its right edge')
  ok(math.abs(p[4] - (900 * (1080 / 768) - 12) / (1080 / 768)) < 0.01, 'right edge 12 px left of the bags')
  ok(w.tip.pts[1][1] == 'CENTER', 'GameTooltip left alone')
end
tests['bags alone: the game tooltip moves when the bag window owns it, not otherwise'] = function()
  local w = layoutWorld()
  w.merchant.shown = false
  local back
  w.tip.NineSlice = { SetCenterColor = function(_, r, g, b, a) back = a end }
  w.tip.GetOwner = function() return w.owner end
  w.fire('PLAYER_ENTERING_WORLD')
  w.owner = UIParent; OmaPadPutTipsForTest()
  ok(w.tip.pts[1][1] == 'CENTER', 'a world tooltip stays put')
  w.owner = w.bags; OmaPadPutTipsForTest()
  local p = w.tip.pts[1]
  ok(p and p[1] == 'TOPRIGHT' and p[3] == 'TOPLEFT', 'the bag item tooltip goes left of the bags')
  ok(back == 1, 'solid backing (Joshua 2026-11-27: opaque, chat showed through at 90%)')
end
tests['bags alone: a vendor layout left on with no vendor window open lets go, the bag tooltip goes left of the bags'] = function()
  local w = layoutWorld()
  w.tip.GetOwner = function() return w.bags end
  w.fire('MERCHANT_SHOW')                       -- vendor layout on
  ok(w.bags.scale == 0.9, 'vendor layout')
  w.merchant.shown = false                      -- the window went without a closing event
  OmaPadPutTipsForTest()
  local p = w.tip.pts[1]
  ok(p and p[1] == 'TOPRIGHT' and p[3] == 'TOPLEFT', 'bag tooltip left of the bags, not the auction spot')
  ok(w.bags.scale == 1, 'the bags put back')
end
tests['layouts: an NPC window kept shown but faded out does not count as open'] = function()
  local w = layoutWorld()
  w.tip.GetOwner = function() return w.bags end
  w.merchant.alpha = 0
  w.fire('MERCHANT_SHOW')
  ok(w.bags.scale == 1, 'no vendor layout for an invisible window')
  OmaPadPutTipsForTest()
  ok(w.tip.pts[1][1] == 'TOPRIGHT', 'bag tooltip left of the bags')
end
tests['bags alone: with the character panel open, the tooltip goes left of it, not onto it'] = function()
  local w = layoutWorld()
  w.merchant.shown = false
  w.tip.GetOwner = function() return w.bags end
  win('KroGamepadBagsDoll', 600, 500, 290, 400)
  w.fire('PLAYER_ENTERING_WORLD')
  OmaPadPutTipsForTest()
  local p = w.tip.pts[1]
  ok(p and math.abs(p[4] - (600 * (1080 / 768) - 12) / (1080 / 768)) < 0.01, 'right edge 12 px left of the character panel')
end
local PXT = 1080 / 768
local function ahTips(header)
  local w = layoutWorld()
  w.merchant.shown = false
  w.fire('AUCTION_HOUSE_SHOW')
  local c1 = win('ShoppingTooltip1', 600, 600, 250, 100); local c2 = win('ShoppingTooltip2', 600, 480, 250, 100)
  if header then c1.CompareHeader = header end
  return w, c1, c2
end
-- the bag window's right edge and bottom in TV px (the AH stack lines up under it, right-aligned, 8 px down)
local function bagEdge(w)
  local b = w.bags; local e = (b.GetEffectiveScale and b:GetEffectiveScale() or 1) * PXT
  return b:GetLeft() * e, 1080 - b:GetBottom() * e
end
tests['auction house: the Equipped boxes go on top under the bags, right-aligned, the item under the last one'] = function()
  local w, c1, c2 = ahTips()
  OmaPadPutTipsForTest()
  local r, btm = bagEdge(w)
  local p = c1.pts[1]
  ok(p[1] == 'TOPLEFT' and p[3] == 'TOPLEFT', 'first compare box left-aligned')
  ok(math.abs(p[4] - r / PXT / 0.9) < 0.01, 'left edge on the bag window\'s left edge')
  ok(math.abs(p[5] + (btm + 34 + 28) / PXT / 0.9) < 0.01, '8 px under the bags, pushed down by the 28 px tab (no header)')
  ok(c2.pts[1][1] == 'TOPLEFT' and c2.pts[1][3] == 'BOTTOMLEFT', 'second box under the first, left-aligned')
  local m = w.tip.pts[1]
  ok(m[1] == 'TOPLEFT' and m[3] == 'BOTTOMLEFT', 'item tooltip under the last compare box')
  ok(math.abs(m[4] - c2.l) < 0.01 and math.abs(m[5] - (c2.t - c2.h - 12 / PXT / 0.9)) < 0.01, 'left-aligned, 12 px under it')
end
tests['auction house: no compare box, the item tooltip sits under the bags, right-aligned'] = function()
  local w, c1, c2 = ahTips(); c1.shown = false; c2.shown = false
  OmaPadPutTipsForTest()
  local r, btm = bagEdge(w)
  local m = w.tip.pts[1]
  ok(m[1] == 'TOPLEFT' and math.abs(m[4] - r / PXT / 0.9) < 0.01 and math.abs(m[5] + (btm + 34) / PXT / 0.9) < 0.01, 'under the bags, left edges level')
  ok(c1.pts[1][1] == 'CENTER', 'compare boxes untouched')
end
tests['auction house: a two-hander shows one Equipped box (the first sums both hands)'] = function()
  local w, c1, c2 = ahTips()
  local hidden = false; c2.Hide = function() hidden = true; c2.shown = false end
  w.tip.GetItem = function() return 'Fishing Pole', 'item:6256' end
  local was = _G.GetItemInfoInstant; _G.GetItemInfoInstant = function() return 6256, 'Weapon', 'Fishing Poles', 'INVTYPE_2HWEAPON' end
  OmaPadPutTipsForTest()
  _G.GetItemInfoInstant = was
  ok(hidden, 'second Equipped box hidden')
  local m = w.tip.pts[1]
  ok(m[3] == 'BOTTOMLEFT' and math.abs(m[4] - c1.l) < 0.01, 'item tooltip straight under the first box')
end
tests['compare tab: measured from the box header when it has one'] = function()
  local h = { GetTop = function() return nil end, GetHeight = function() return 30 end, GetEffectiveScale = function() return 0.9 end,
              IsShown = function() return true end }
  local w, c1 = ahTips(h)
  OmaPadPutTipsForTest()
  local tab = 30 * 0.9 * PXT
  local _, btm = bagEdge(w)
  ok(math.abs(c1.pts[1][5] + (btm + 34 + tab) / PXT / 0.9) < 0.01, 'pushed down by the header height: ' .. tostring(c1.pts[1][5]))
  -- the bags use the same math
  local w2 = layoutWorld(); w2.merchant.shown = false; w2.tip.GetOwner = function() return w2.bags end
  local b1 = win('ShoppingTooltip1', 600, 600, 250, 100); b1.CompareHeader = h; win('ShoppingTooltip2', 0, 0, 1, 1).shown = false
  w2.fire('PLAYER_ENTERING_WORLD'); OmaPadPutTipsForTest()
  ok(math.abs(b1.pts[1][5] + (1080 - 500 * PXT + tab) / PXT) < 0.01, 'bags: first box pushed down by the same tab')
end
tests['apply waits while he drags something'] = function()
  local w = load('PALADIN', 'Bunji'); w.cursor = { 'item', 6948 }
  local later = 0; _G.C_Timer = { After = function() later = later + 1 end }
  pad(''); ok(w.cursor and w.cursor[2] == 6948, 'what he holds stays on the cursor')
end

-- ---------- a spell lands on the pad (sheet 26) ----------
-- a clock for C_Timer: run(ms) moves time on and runs what came due, in order
local function clockWorld(class)
  local w = load(class or 'PALADIN', 'Bunji', {}, nil)
  local q, now = {}, 0
  _G.C_Timer = { After = function(d, fn) q[#q + 1] = { t = now + d * 1000, fn = fn, n = #q } end }
  w.run = function(ms)
    local stop = now + (ms or 60000)
    while true do
      table.sort(q, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.n < b.n end)
      local nx = q[1]; if not nx or nx.t > stop then break end
      table.remove(q, 1); now = nx.t; nx.fn()
    end
    now = stop
  end
  local combat = false
  w.combat = function(v) combat = v end
  _G.InCombatLockdown = function() return combat end
  w.log = function() return table.concat(OmaPadLand.log, ' ') end
  return w
end
local function lvl6(w) learn({ 'Seal of Righteousness', 'Holy Light', 'Judgement', 'Devotion Aura', 'Divine Protection' }); pad(); w.run() end

tests['landing: spells learned at a trainer wait until the trainer window closes'] = function()
  local w = clockWorld(); lvl6(w)
  eq(w.log(), '', 'the first look only takes notes')
  w.fire('TRAINER_SHOW')
  learn({ 'Hammer of Justice' }); pad(); w.run(10000)
  eq(w.log(), '', 'nothing while the trainer is open')
  learn({ 'Lay on Hands' })                                  -- learned just before closing: not looked at yet
  w.fire('TRAINER_CLOSED'); w.run()
  local s1, s2 = slotOf(1, 'RT', U), slotOf(1, 'LT', R)
  eq(w.log(), 'start layer:11 new:' .. s1 .. ' layer:12 new:' .. s2 .. ' end', 'both play once the window closes, RT before LT')
end

tests['landing: a spell from a quest or tome plays right away'] = function()
  local w = clockWorld(); lvl6(w)
  learn({ 'Hammer of Justice' }); pad(); w.run(1000)
  ok(w.log():find('new:' .. slotOf(1, 'RT', U), 1, true), 'played within a second: ' .. w.log())
  w.run(); ok(w.log():find('end', 1, true), 'and ends')
  eq(#w.sounds, 1, 'one chime'); eq(w.sounds[1], '618/SFX', 'default kit on the SFX channel')
end

tests['landing: order bare pad, RT, LT, LT+RT, set 2; upgrades of a layer together, left to right'] = function()
  local w = clockWorld()
  local S = function(set, bar, b) return slotOf(set, bar, b) end
  local steps = OmaPadLand.plan({ { kind = 'new', slot = S(2, 'none', U) }, { kind = 'up', slot = S(1, 'RT', B) },
    { kind = 'new', slot = S(1, 'LTRT', X) }, { kind = 'new', slot = S(1, 'LT', A) }, { kind = 'up', slot = S(1, 'RT', X) },
    { kind = 'new', slot = S(1, 'RT', Y) }, { kind = 'new', slot = S(1, 'none', D) } })
  local out = {}
  for _, st in ipairs(steps) do out[#out + 1] = st.kind == 'new' and ('n' .. st.slot) or ('u' .. table.concat(st.slots, ',')) end
  eq(table.concat(out, ' '), table.concat({ 'n' .. S(1, 'none', D), 'n' .. S(1, 'RT', Y), 'u' .. S(1, 'RT', X) .. ',' .. S(1, 'RT', B),
    'n' .. S(1, 'LT', A), 'n' .. S(1, 'LTRT', X), 'n' .. S(2, 'none', U) }, ' '))
end

tests['landing: new spell vs rank upgrade; a spell only moving buttons does not play'] = function()
  local w = clockWorld(); lvl6(w)
  W.rank['Holy Light'] = 5001; RANKS[5001] = 'Holy Light'      -- Holy Light rank 2
  learn({ 'Seal of Command' }); pad(); w.run()                 -- Command takes RT Y; Righteousness moves to RT R
  local cmd, hl = slotOf(1, 'RT', Y), slotOf(1, 'LT', X)
  eq(spellOn(1, 'RT', R), 'Seal of Righteousness')
  eq(w.log(), 'start layer:11 new:' .. cmd .. ' layer:12 up:' .. hl .. ' end')
  eq(#w.sounds, 1, 'chime for the new spell only')
  w.fire('LEARNED_SPELL_IN_TAB', spellId('Judgement')); pad(); w.run()   -- the game says a known spell got a rank
  ok(w.log():find('up:' .. slotOf(1, 'RT', X), 1, true), 'learned event counts as an upgrade: ' .. w.log())
end

tests['landing: never in a fight; it waits for the fight to end, and a fight or a button ends one playing'] = function()
  local w = clockWorld(); lvl6(w)
  learn({ 'Hammer of Justice' }); pad(); w.combat(true); w.run()
  eq(w.log(), '', 'waits in combat')
  w.combat(false); w.fire('PLAYER_REGEN_ENABLED'); w.run()
  ok(w.log():find('new:', 1, true), 'played after the fight: ' .. w.log())
  OmaPadLand.log = {}
  learn({ 'Lay on Hands', 'Blessing of Protection' }); pad(); w.run(800)
  w.fire('PLAYER_STARTED_MOVING')
  eq(OmaPadLand.running, false); ok(w.log():find('stop:button', 1, true), 'moving ends it: ' .. w.log())
  w.run(); ok(not w.log():find('end', 1, true), 'nothing left playing')
end

tests['landing: /omapad landtest plays a sample landing and upgrade, /omapad sound sets the chime'] = function()
  local w = clockWorld(); lvl6(w)
  eq(SLASH_OMASHUPAD2, '/omapad')
  -- a pad the drawing can find: the game's buttons show their action and place
  _G.UIParent = tolerant(); getmetatable(UIParent).__index = function(_, k) if k == 'GetEffectiveScale' then return function() return 1 end end return function() end end
  local btns = {}
  for b = 0, 7 do
    local f = tolerant(); local mt = getmetatable(f)
    local fx, fy = 300 + b * 60, 200
    rawset(f, 'action', b < 4 and 181 + b or 193 + b)
    rawset(f, 'GetCenter', function() return fx, fy end); rawset(f, 'GetEffectiveScale', function() return 1 end)
    rawset(f, 'GetWidth', function() return 50 end); rawset(f, 'IsVisible', function() return true end)
    btns[#btns + 1] = f
  end
  _G.EnumerateFrames = function(prev) if not prev then return btns[1] end; for i, f in ipairs(btns) do if f == prev then return btns[i + 1] end end end
  pad('landtest'); w.run()
  local L = w.log()
  ok(L:find('new:', 1, true) and L:find('up:', 1, true) and L:find('end', 1, true), 'sample played: ' .. L)
  eq(OmaPadDB.landCheck.found, 8, 'found the pad buttons'); eq(OmaPadDB.landCheck.err, nil, 'drawing ran clean')
  pad('sound 3337'); eq(OmaPadDB.landSound, 3337); eq(w.sounds[#w.sounds], '3337/SFX', 'played to hear it')
  pad('sound default'); eq(OmaPadDB.landSound, nil)
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
