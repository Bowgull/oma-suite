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
  W.frames = {}
  local function frame()
    local f = { ev = {} }
    function f:RegisterEvent(e) self.ev[e] = true end
    function f:SetScript(k, fn) self[k] = fn end
    function f:HookScript() end
    W.frames[#W.frames + 1] = f
    return f
  end
  -- fire an event at every add-on frame that asked for it
  W.fire = function(e) for _, f in ipairs(W.frames) do if f.ev[e] and f.OnEvent then f:OnEvent(e) end end end
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
  ok(w.ah.scale == 1.05 and w.bags.scale == 0.65, 'auction house layout')
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
  ok(back and back > 0.8 and back < 1, 'darker backing, not solid')
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
tests['apply waits while he drags something'] = function()
  local w = load('PALADIN', 'Bunji'); w.cursor = { 'item', 6948 }
  local later = 0; _G.C_Timer = { After = function() later = later + 1 end }
  pad(''); ok(w.cursor and w.cursor[2] == 6948, 'what he holds stays on the cursor')
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
