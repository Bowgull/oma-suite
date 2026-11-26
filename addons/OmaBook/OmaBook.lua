-- OmaBook: what the Paladin Book on the phone remote needs, saved with the character (Joshua 2026-11-26, sheet 18).
-- Read-only: it never changes a setting, a bar or a bag. It gathers the character's state into OmaBookDB.json, one
-- JSON string, kept fresh in memory and written to disk by the game itself on /reload and logout. Couch Mode reads that
-- file (GET /book) and Aang turns it into the book. Nothing here is live: the book says "as of your last reload".
--
--   json = { v, at, name, realm, faction, class, zone, level, money (copper), xp, xpMax, unspent, talents = { [name] = rank },
--            spells = { name, ... }, train = { { name, lvl } }, skills = { [name] = rank }, weapon = { id, name, dps }, bags = { [itemID] = count },
--            done = { [questID] = true }, log = { questID, ... }, cu = { rich, max, list = { { id, name, slot, price, pct } } } }

local V = 1
-- the class quests whose completion the book checks (from Polestar's own Forever paladin guides)
local QUESTS = { 1806, 78093, 1661, 8418, 7647 }   -- Verigan's Fist, Cloak of the Divine Storm, Tome of Nobility, Holy Mightstone, Charger

local function try(f) local ok, r = pcall(f); if ok then return r end end

-- a small JSON writer: tables with string keys become objects, sequences become arrays
local function esc(s) return (s:gsub('[%c"\\]', function(c)
  if c == '"' then return '\\"' elseif c == '\\' then return '\\\\' elseif c == '\n' then return '\\n' end
  return string.format('\\u%04x', c:byte()) end)) end
local function enc(v)
  local t = type(v)
  if t == 'string' then return '"' .. esc(v) .. '"' end
  if t == 'number' then if v ~= v or v == math.huge or v == -math.huge then return 'null' end; return (v % 1 == 0) and string.format('%d', v) or string.format('%.4g', v) end
  if t == 'boolean' then return tostring(v) end
  if t ~= 'table' then return 'null' end
  local n = #v
  if n > 0 or next(v) == nil then
    local out = {}; for i = 1, n do out[i] = enc(v[i]) end; return '[' .. table.concat(out, ',') .. ']'
  end
  local keys = {}; for k in pairs(v) do keys[#keys + 1] = tostring(k) end; table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do local x = v[k]; if x == nil then x = v[tonumber(k)] end; out[#out + 1] = '"' .. esc(k) .. '":' .. enc(x) end
  return '{' .. table.concat(out, ',') .. '}'
end

local function spellName(id) return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and (GetSpellInfo(id))) end

local function talents()
  local ranks, unspent = {}, 0
  local cfg = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
  local info = cfg and C_Traits.GetConfigInfo(cfg)
  for _, tree in ipairs(info and info.treeIDs or {}) do
    for _, c in ipairs(C_Traits.GetTreeCurrencyInfo and C_Traits.GetTreeCurrencyInfo(cfg, tree, false) or {}) do unspent = unspent + (c.quantity or 0) end
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(tree) or {}) do
      local n = C_Traits.GetNodeInfo(cfg, nodeID)
      local rank = n and (n.activeRank or n.ranksPurchased or 0) or 0
      if rank > 0 then
        local entry = n.activeEntry and n.activeEntry.entryID or (n.entryIDs and n.entryIDs[1])
        local e = entry and C_Traits.GetEntryInfo(cfg, entry)
        local def = e and e.definitionID and C_Traits.GetDefinitionInfo(e.definitionID)
        local sid = def and (def.spellID or def.overriddenSpellID)
        local name = sid and spellName(sid)
        if name then ranks[name] = rank end
      end
    end
  end
  return ranks, unspent
end

-- known spells, plus the spellbook's "future" spells you're already high enough to learn (train) or will be soon
local function spells()
  local out, seen, train = {}, {}, {}
  local future = Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
  local level = UnitLevel('player') or 0
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    for t = 1, C_SpellBook.GetNumSpellBookSkillLines() do
      local line = C_SpellBook.GetSpellBookSkillLineInfo(t)
      for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
        local s = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
        if s and s.name and future and s.itemType == future then
          local lvl = s.spellID and C_Spell.GetSpellLevelLearned and C_Spell.GetSpellLevelLearned(s.spellID)
          if lvl and lvl > 0 and lvl <= level + 2 then train[#train + 1] = { name = s.name, lvl = lvl } end
        elseif s and s.name and not seen[s.name] and not s.isPassive then seen[s.name] = true; out[#out + 1] = s.name end
      end
    end
  end
  table.sort(out)
  table.sort(train, function(a, b) if a.lvl ~= b.lvl then return a.lvl < b.lvl end return a.name < b.name end)
  return out, train
end

local function skills()
  local out = {}
  for i = 1, (GetNumSkillLines and GetNumSkillLines() or 0) do
    local name, header, _, rank = GetSkillLineInfo(i)
    if name and not header then out[name] = rank end
  end
  return out
end

local function weapon()
  local id = GetInventoryItemID and GetInventoryItemID('player', 16)
  if not id then return nil end
  local link = GetInventoryItemLink('player', 16)
  local stats = link and ((C_Item and C_Item.GetItemStats and C_Item.GetItemStats(link)) or (GetItemStats and GetItemStats(link))) or {}
  local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (link and link:match('%[(.-)%]'))
  -- weapon subclass (4 one-hand mace, 5 two-hand mace, 6 polearm, 1 two-hand axe, 8 two-hand sword...): picks the stone
  local sub = C_Item and C_Item.GetItemInfoInstant and select(7, C_Item.GetItemInfoInstant(id))
  return { id = id, name = name, dps = stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT, sub = sub }
end

local function bags()
  local out = {}
  local slots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  for bag = 0, 4 do
    for slot = 1, (slots(bag) or 0) do
      local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then out[tostring(info.itemID)] = (out[tostring(info.itemID)] or 0) + (info.stackCount or 1) end
    end
  end
  return out
end

local function quests()
  local done, log = {}, {}
  local isDone = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
  for _, q in ipairs(QUESTS) do if isDone and isDone(q) then done[tostring(q)] = true end end
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local q = C_QuestLog.GetInfo(i)
      if q and not q.isHeader and q.questID then log[#log + 1] = q.questID end
    end
  end
  return done, log
end

-- Cheap Upgrades' own list (CheapUpgrades.results: link, name, slot, price, pct), the ten best, and its mode
local function cheapUpgrades()
  local cu = rawget(_G, 'CheapUpgrades')
  if type(cu) ~= 'table' then return nil end
  local list = {}
  for i, r in ipairs(type(cu.results) == 'table' and cu.results or {}) do
    if i > 10 then break end
    local id = type(r.link) == 'string' and tonumber(r.link:match('item:(%d+)'))
    list[#list + 1] = { id = id, name = r.name, slot = r.slot, price = r.price, pct = r.pct }
  end
  local db = type(cu.db) == 'table' and cu.db or {}
  return { rich = db.richMode and true or false, max = db.maxPrice, list = list }
end

local function gather()
  local d = { v = V, at = time(), name = UnitName('player'), realm = GetRealmName(), faction = (UnitFactionGroup('player')),
    class = select(2, UnitClass('player')), zone = GetRealZoneText and GetRealZoneText() or nil, level = UnitLevel('player'), money = GetMoney and GetMoney() or nil, xp = UnitXP('player'), xpMax = UnitXPMax('player') }
  d.talents, d.unspent = {}, 0
  local ok, t, u = pcall(talents); if ok then d.talents, d.unspent = t, u end
  d.spells, d.train = {}, {}
  local ok3, sp, tr = pcall(spells); if ok3 then d.spells, d.train = sp, tr end
  d.skills = try(skills) or {}
  d.weapon = try(weapon)
  d.bags = try(bags) or {}
  local ok2, done, log = pcall(quests); if ok2 then d.done, d.log = done, log end
  d.cu = try(cheapUpgrades)
  return d
end

local function save()
  local ok, d = pcall(gather)
  if not ok then return end
  OmaBookDB = OmaBookDB or {}
  OmaBookDB.json = enc(d)
  OmaBookDB.at = d.at
end
_G.OmaBook = { save = save, enc = enc }   -- for the offline tests

-- saved at login (once the game has settled), level-ups, bag and spell changes (gently), and just before logout
local f = CreateFrame('Frame')
local queued = false
local function soon() if queued then return end; queued = true; C_Timer.After(3, function() queued = false; save() end) end
for _, e in ipairs({ 'PLAYER_ENTERING_WORLD', 'PLAYER_LEVEL_UP', 'BAG_UPDATE_DELAYED', 'SPELLS_CHANGED', 'TRAIT_CONFIG_UPDATED', 'QUEST_TURNED_IN', 'PLAYER_EQUIPMENT_CHANGED', 'PLAYER_MONEY', 'PLAYER_LOGOUT' }) do
  f:RegisterEvent(e)
end
f:SetScript('OnEvent', function(_, e) if e == 'PLAYER_LOGOUT' then save() else soon() end end)
