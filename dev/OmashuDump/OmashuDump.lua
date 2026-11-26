-- Read-only: writes what's in the game into OmashuDumpDB (saved on /reload or logout).
local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function try(f, ...) local ok, r = pcall(f, ...); if ok then return r end; return 'ERR ' .. tostring(r) end

local function dump()
  local d = { at = date('%Y-%m-%d %H:%M:%S'), who = UnitName('player'), realm = GetRealmName(), level = UnitLevel('player'),
              class = select(2, UnitClass('player')), build = select(4, GetBuildInfo()) }
  -- spellbook
  d.spells = try(function()
    local out = {}
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
      for t = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(t)
        for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
          local s = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
          out[#out + 1] = info.name .. ' | ' .. tostring(s.name) .. ' | ' .. tostring(s.spellID or s.actionID) .. ' | ' .. tostring(s.itemType) .. (s.isPassive and ' passive' or '')
        end
      end
    else
      for t = 1, GetNumSpellTabs() do
        local tn, _, off, n = GetSpellTabInfo(t)
        for i = off + 1, off + n do
          local name, rank = GetSpellBookItemName(i, BOOKTYPE_SPELL)
          local _, id = GetSpellBookItemInfo(i, BOOKTYPE_SPELL)
          out[#out + 1] = tn .. ' | ' .. tostring(name) .. ' | ' .. tostring(rank) .. ' | ' .. tostring(id)
        end
      end
    end
    return out
  end)
  -- pet spells
  d.pet = try(function()
    local out = {}
    for i = 1, 10 do local n, tex, isToken, isActive, acAllowed, acOn, sid = GetPetActionInfo(i)
      out[#out + 1] = i .. ' | ' .. tostring(n) .. ' | token ' .. tostring(isToken) .. ' | lit ' .. tostring(isActive) .. ' | spell ' .. tostring(sid) end
    return out
  end)
  -- which pet commands this client has (2026-11-11: does /petdefensive exist here?)
  d.petCmds = try(function()
    local out = {}
    for _, f in ipairs({ 'PetDefensiveMode', 'PetDefensiveAssistMode', 'PetAssistMode', 'PetAggressiveMode', 'PetPassiveMode', 'PetAttack', 'PetFollow' }) do
      out[#out + 1] = f .. ' = ' .. type(_G[f]) end
    for _, c in ipairs({ '/petdefensive', '/petdefensiveassist', '/petassist', '/petaggressive', '/petpassive', '/petattack' }) do
      out[#out + 1] = c .. ' -> ' .. tostring(hash_SlashCmdList and hash_SlashCmdList[c:upper()] and 'yes' or 'no') end
    out[#out + 1] = 'ActionButtonUseKeyDown = ' .. tostring(C_CVar and C_CVar.GetCVar('ActionButtonUseKeyDown'))
    local names = {}
    for k, v in pairs(_G) do if type(k) == 'string' and k:find('^SLASH_PET') then names[#names + 1] = k .. ' = ' .. tostring(v) end end
    table.sort(names); for _, n in ipairs(names) do out[#out + 1] = n end
    return out
  end)
  -- macros
  d.macros = try(function()
    local out = {}
    for i = 1, 150 do local n, icon, body = GetMacroInfo(i); if n then out[#out + 1] = i .. ' | ' .. n .. ' | ' .. (body or ''):gsub('\n', ' \\n ') end end
    return out
  end)
  -- action slots
  d.slots = try(function()
    local out = {}
    for s = 1, 264 do -- 2026-11-26: was 200, missed OmaPad sets 2 and 3 (209-264)
      if HasAction(s) then
        local ty, id, sub = GetActionInfo(s)
        local nm = (ty == 'spell' and spellName(id)) or (ty == 'macro' and GetMacroInfo(id)) or (ty == 'item' and (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or GetItemInfo(id))) or GetActionText(s)
        out[#out + 1] = s .. ' | ' .. tostring(ty) .. ' | ' .. tostring(id) .. ' | ' .. tostring(nm)
      end
    end
    return out
  end)
  -- every key binding that involves a pad button
  d.padBinds = try(function()
    local out = {}
    for i = 1, GetNumBindings() do
      local cmd, cat, k1, k2 = GetBinding(i)
      for _, k in ipairs({ k1 or '', k2 or '' }) do if k:find('PAD') then out[#out + 1] = k .. ' = ' .. cmd end end
    end
    return out
  end)
  -- buttons on screen that hold an action slot
  d.buttons = try(function()
    local out, f = {}, EnumerateFrames()
    while f do
      local ok, slot = pcall(function() return f.action or (f.GetAttribute and f:GetAttribute('action')) end)
      if ok and type(slot) == 'number' and f.GetName then
        local x, y = f:GetCenter()
        out[#out + 1] = tostring(f:GetName()) .. ' | parent ' .. tostring(f:GetParent() and f:GetParent():GetName()) .. ' | slot ' .. slot ..
          ' | shown ' .. tostring(f:IsVisible()) .. ' | at ' .. tostring(x and math.floor(x)) .. ',' .. tostring(y and math.floor(y))
      end
      f = EnumerateFrames(f)
    end
    return out
  end)
  -- settings that matter here
  d.cvars = try(function()
    local out = {}
    if C_Console and C_Console.GetAllCommands then
      for _, c in ipairs(C_Console.GetAllCommands()) do
        local n = c.command
        if n and (n:find('[Pp]ad') or n:find('Invert') or n:find('QuestWatch') or n:find('Tracker')) then
          out[#out + 1] = n .. ' = ' .. tostring(C_CVar.GetCVar(n))
        end
      end
    end
    return out
  end)
  d.professions = try(function()
    local out = {}
    if GetProfessions then for _, ix in pairs({ GetProfessions() }) do if ix then local n, _, r = GetProfessionInfo(ix); out[#out + 1] = n .. ' ' .. r end end end
    for i = 1, (GetNumSkillLines and GetNumSkillLines() or 0) do local n, hdr, _, r = GetSkillLineInfo(i); if not hdr then out[#out + 1] = 'skill: ' .. n .. ' ' .. tostring(r) end end
    return out
  end)
  -- talents (2026-11-26): every tab's raw info and every talent's rank, plus unspent points
  d.talents = try(function()
    local out = {}
    local pack = function(...) local t = { ... }; for i = 1, select('#', ...) do t[i] = tostring(t[i]) end; return table.concat(t, ' | ') end
    for tab = 1, (GetNumTalentTabs and GetNumTalentTabs() or 0) do
      out[#out + 1] = 'TAB ' .. tab .. ' :: ' .. pack(GetTalentTabInfo(tab))
      for i = 1, (GetNumTalents and GetNumTalents(tab) or 0) do out[#out + 1] = '  ' .. tab .. '.' .. i .. ' :: ' .. pack(GetTalentInfo(tab, i)) end
    end
    return out
  end)
  -- Forever keeps talents in C_Traits (same reading as TalentsForeverBook's Game.lua): every tree of the active config,
  -- each node with a rank above 0 by spell name, and each tree's points (currency)
  d.traits = try(function()
    local out = {}
    if not (C_Traits and C_ClassTalents and C_ClassTalents.GetActiveConfigID) then return { 'no C_Traits' } end
    local cfg = C_ClassTalents.GetActiveConfigID()
    local info = cfg and C_Traits.GetConfigInfo(cfg)
    out[#out + 1] = 'config ' .. tostring(cfg) .. ' trees ' .. (info and table.concat(info.treeIDs or {}, ',') or 'none')
    for _, tree in ipairs(info and info.treeIDs or {}) do
      if C_Traits.GetTreeCurrencyInfo then
        for _, c in ipairs(C_Traits.GetTreeCurrencyInfo(cfg, tree, false) or {}) do
          out[#out + 1] = 'tree ' .. tree .. ' points: have ' .. tostring(c.quantity) .. ' spent ' .. tostring(c.spent) .. ' max ' .. tostring(c.maxQuantity)
        end
      end
      for _, nodeID in ipairs(C_Traits.GetTreeNodes(tree) or {}) do
        local n = C_Traits.GetNodeInfo(cfg, nodeID)
        local rank = n and (n.activeRank or n.ranksPurchased or n.currentRank or 0) or 0
        if rank > 0 then
          local entry = n.activeEntry and n.activeEntry.entryID or (n.entryIDs and n.entryIDs[1])
          local e = entry and C_Traits.GetEntryInfo(cfg, entry)
          local def = e and e.definitionID and C_Traits.GetDefinitionInfo(e.definitionID)
          local sid = def and (def.spellID or def.overriddenSpellID)
          out[#out + 1] = 'tree ' .. tree .. ' node ' .. nodeID .. ' ' .. tostring(sid and spellName(sid) or ('spell ' .. tostring(sid))) .. ' ' .. rank .. '/' .. tostring(n.maxRanks)
        end
      end
    end
    return out
  end)
  -- the whole talent tree (2026-11-26, the Paladin Book): every node, its spell, place in the tree and ranks
  d.tree = try(function()
    local out = {}
    local cfg = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    local info = cfg and C_Traits.GetConfigInfo(cfg)
    for _, tree in ipairs(info and info.treeIDs or {}) do
      for _, nodeID in ipairs(C_Traits.GetTreeNodes(tree) or {}) do
        local n = C_Traits.GetNodeInfo(cfg, nodeID)
        if n and n.ID and n.ID ~= 0 then
          for _, entry in ipairs(n.entryIDs or {}) do
            local e = C_Traits.GetEntryInfo(cfg, entry)
            local def = e and e.definitionID and C_Traits.GetDefinitionInfo(e.definitionID)
            local sid = def and (def.spellID or def.overriddenSpellID)
            local cond = {}
            for _, c in ipairs(n.conditionIDs or {}) do cond[#cond + 1] = c end
            out[#out + 1] = table.concat({ tree, nodeID, tostring(sid), tostring(sid and spellName(sid)), tostring(n.posX), tostring(n.posY),
              tostring(n.maxRanks), tostring(n.activeRank or n.ranksPurchased or 0), tostring(e and e.maxRanks), table.concat(cond, ',') }, ' | ')
          end
        end
      end
    end
    return out
  end)
  d.unspent = try(function()
    if UnitCharacterPoints then return tostring((UnitCharacterPoints('player'))) end
    if GetUnspentTalentPoints then return tostring(GetUnspentTalentPoints()) end
    return 'no api'
  end)
  -- worn gear and the stats a caster cares about
  d.gear = try(function()
    local out = {}
    for s = 1, 19 do local l = GetInventoryItemLink('player', s); if l then out[#out + 1] = s .. ' :: ' .. l end end
    return out
  end)
  d.stats = try(function()
    local st = { 'Str', 'Agi', 'Sta', 'Int', 'Spi' }
    local out = {}
    for i = 1, 5 do local _, eff = UnitStat('player', i); out[#out + 1] = st[i] .. ' ' .. tostring(eff) end
    if GetSpellBonusDamage then out[#out + 1] = 'shadow ' .. tostring(GetSpellBonusDamage(6)) .. ' fire ' .. tostring(GetSpellBonusDamage(3)) end
    out[#out + 1] = 'hp ' .. UnitHealthMax('player') .. ' mana ' .. UnitPowerMax('player', 0)
    return out
  end)
  d.money = GetMoney and GetMoney() or nil
  -- quest log and where he stands (2026-11-26, for the dungeon plan)
  d.where = try(function()
    local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit('player')
    local p = m and C_Map.GetPlayerMapPosition(m, 'player')
    return tostring(GetZoneText()) .. ' / ' .. tostring(GetSubZoneText()) .. (p and string.format(' (%.1f, %.1f)', p.x * 100, p.y * 100) or '')
  end)
  d.quests = try(function()
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
      for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local q = C_QuestLog.GetInfo(i)
        if q then
          if q.isHeader then out[#out + 1] = '## ' .. tostring(q.title)
          else
            local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(q.questID)
            out[#out + 1] = tostring(q.questID) .. ' | ' .. tostring(q.title) .. ' | lvl ' .. tostring(q.level) .. (done and ' | DONE' or '')
          end
        end
      end
    elseif GetNumQuestLogEntries then
      for i = 1, GetNumQuestLogEntries() do
        local t, lvl, _, hdr, _, done, _, id = GetQuestLogTitle(i)
        out[#out + 1] = (hdr and '## ' or '') .. tostring(id) .. ' | ' .. tostring(t) .. ' | lvl ' .. tostring(lvl) .. (done == 1 and ' | DONE' or '')
      end
    end
    return out
  end)
  -- memory per loaded add-on in KB, biggest first (2026-11-26, speed audit)
  d.addonMem = try(function()
    local out, rows, total = {}, {}, 0
    UpdateAddOnMemoryUsage()
    local num = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
    for i = 1, num do
      local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)(i)
      if loaded then
        local name = (C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo)(i)
        local kb = GetAddOnMemoryUsage(i); total = total + kb
        rows[#rows + 1] = { name, kb }
      end
    end
    table.sort(rows, function(a, b) return a[2] > b[2] end)
    out[1] = 'total ' .. math.floor(total) .. ' KB across ' .. #rows .. ' loaded; Lua heap ' .. math.floor(collectgarbage('count')) .. ' KB'
    for _, r in ipairs(rows) do out[#out + 1] = math.floor(r[2]) .. ' KB  ' .. r[1] end
    return out
  end)
  d.petLog = (OmashuDumpDB and OmashuDumpDB.petLog) or {}
  table.insert(d.petLog, d.at .. '  ' .. (type(d.pet) == 'table' and table.concat(d.pet, ' ;; ') or tostring(d.pet)))
  OmashuDumpDB = d
  print('|cffe8c860Omashu:|r read ' .. (type(d.spells) == 'table' and #d.spells or 0) .. ' spells, ' .. (type(d.slots) == 'table' and #d.slots or 0) .. ' slots')
end

local ev = CreateFrame('Frame')
ev:RegisterEvent('PLAYER_ENTERING_WORLD')
-- NodeSight's interact settings (2026-11-26): at login, with the controller UI starting, the game refuses them for a
-- moment and NodeSight warns; a few seconds later they take. Set them again 3 s after every loading screen.
local function interactAgain()
  if InCombatLockdown() then return end
  for k, v in pairs({ softTargetInteract = '3', SoftTargetInteractArc = '2', SoftTargetIconGameObject = '1' }) do
    if C_CVar.GetCVar(k) ~= v then C_CVar.SetCVar(k, v) end
  end
  local r = tonumber(C_CVar.GetCVar('SoftTargetInteractRange') or 0) or 0
  if r < 30 then C_CVar.SetCVar('SoftTargetInteractRange', '30') end
end
ev:SetScript('OnEvent', function() C_Timer.After(3, interactAgain); C_Timer.After(6, dump) end)
SLASH_OMASHUDUMP1 = '/omdump'
SlashCmdList.OMASHUDUMP = dump
