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
    for s = 1, 200 do
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
  d.petLog = (OmashuDumpDB and OmashuDumpDB.petLog) or {}
  table.insert(d.petLog, d.at .. '  ' .. (type(d.pet) == 'table' and table.concat(d.pet, ' ;; ') or tostring(d.pet)))
  OmashuDumpDB = d
  print('|cffe8c860Omashu:|r read ' .. (type(d.spells) == 'table' and #d.spells or 0) .. ' spells, ' .. (type(d.slots) == 'table' and #d.slots or 0) .. ' slots')
end

local ev = CreateFrame('Frame')
ev:RegisterEvent('PLAYER_ENTERING_WORLD')
ev:SetScript('OnEvent', function() C_Timer.After(6, dump) end)
SLASH_OMASHUDUMP1 = '/omdump'
SlashCmdList.OMASHUDUMP = dump
