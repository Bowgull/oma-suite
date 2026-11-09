-- Omashu Pad: the warlock controller layout for Bujuju (WoW Forever gamepad UI).
-- Pad slots (read from the game 2026-11-09): no trigger = 181-184 (D-pad left, up, right, down);
-- LT = 185-192, RT = 193-200, LT+RT = 201-208, each: D-pad left, up, right, down, then X, Y, B, A.
local V = 3                                   -- bump to re-apply the whole layout once
local L, U, R, D, X, Y, B, A = 0, 1, 2, 3, 4, 5, 6, 7
local BASE = { none = 181, LT = 185, RT = 193, LTRT = 201 }

local MACROS = {                               -- Joshua's two demon buttons (his old "Good Boi", split for the pad)
  { 'PetFight', '/click PetActionButton9\n/petattack', 'Ability_Warrior_Charge' },   -- defensive + attack my target
  { 'PetHome',  '/petpassive\n/petfollow', 'Ability_Tracking' },                     -- passive + come back
  { 'Meters',   '/ommeters', 'INV_Misc_PocketWatch_01' },                               -- damage + threat meters, show/hide
}
local OLD_MACROS = { 'Bolt', 'PetGo', 'PetBack', 'PetMove', 'PetOne', 'PetTwo', 'Stone', 'Drink' }
local STONES = { 9421, 5510, 5509, 5511, 5512 }                                       -- Major .. Minor Healthstone
local WATERS = { 8766, 1645, 1708, 1205, 1179, 159 }                                   -- best vendor water first

-- { bar, button, kind, name or list }   kind: spell | macro | item (id or list of ids)
-- Build: Affliction (WoW Forever levelling guide). Empty buttons fill in as spells are learned.
local LAYOUT = {
  -- no trigger: the fight
  { 'none', U, 'spell', 'Shadow Bolt' },
  { 'none', R, 'spell', 'Corruption' },
  { 'none', L, 'spell', 'Immolate' },
  { 'none', D, 'spell', 'Shoot' },              -- wand
  -- LT: banes, curses, drains, staying alive
  { 'LT', U, 'spell', 'Bane of Agony' },
  { 'LT', R, 'spell', 'Drain Life' },
  { 'LT', L, 'spell', { 'Curse of the Elements', 'Curse of Weakness' } },
  { 'LT', D, 'spell', 'Drain Soul' },
  { 'LT', X, 'spell', 'Life Tap' },
  { 'LT', Y, 'spell', 'Fear' },
  { 'LT', B, 'spell', 'Will of the Forsaken' },
  { 'LT', A, 'item', STONES },
  -- RT: the demon
  { 'RT', U, 'macro', 'PetFight' },
  { 'RT', D, 'macro', 'PetHome' },
  { 'RT', L, 'spell', 'Summon Imp' },
  { 'RT', R, 'spell', 'Summon Voidwalker' },
  { 'RT', X, 'spell', { 'Summon Sayaad', 'Summon Succubus', 'Summon Incubus' } },
  { 'RT', Y, 'spell', 'Summon Felhunter' },
  { 'RT', B, 'spell', 'Health Funnel' },
  { 'RT', A, 'macro', 'Meters' },               -- damage + threat meters (Create Soulstone goes elsewhere at 18)
  -- LT+RT: out of fights
  { 'LTRT', U, 'item', 6948 },                  -- Hearthstone
  { 'LTRT', R, 'spell', 'Find Minerals' },
  { 'LTRT', L, 'spell', 'Tailoring' },
  { 'LTRT', D, 'item', WATERS },
  { 'LTRT', X, 'item', 4604 },                  -- Forest Mushroom Cap (food)
  { 'LTRT', Y, 'spell', 'Demon Skin' },
  { 'LTRT', B, 'spell', 'Cannibalize' },
  { 'LTRT', A, 'spell', 'Create Healthstone' },
}

OmashuPadDB = OmashuPadDB or {}
local function say(m) print('|cffe8c860Omashu:|r ' .. m) end
local function known(name)
  if type(name) == 'table' then for _, n in ipairs(name) do local id = known(n); if id then return id end end; return nil end
  if C_Spell and C_Spell.GetSpellInfo then local i = C_Spell.GetSpellInfo(name); return i and IsPlayerSpell and IsPlayerSpell(i.spellID) and i.spellID end
  local id = select(7, GetSpellInfo(name)); return id and IsPlayerSpell(id) and id
end
local function hasItem(id)
  if type(id) == 'table' then for _, i in ipairs(id) do if hasItem(i) then return i end end; return nil end
  return (C_Item and C_Item.GetItemCount or GetItemCount)(id) > 0 and id
end

local function makeMacros()
  for _, n in ipairs(OLD_MACROS) do local i = GetMacroIndexByName(n); if i > 0 then DeleteMacro(i) end end
  for _, m in ipairs(MACROS) do
    local i = GetMacroIndexByName(m[1])
    if i == 0 then CreateMacro(m[1], m[3] or 'INV_MISC_QUESTIONMARK', m[2], true) else EditMacro(i, m[1], m[3] or 'INV_MISC_QUESTIONMARK', m[2]) end
  end
end

local function put(slot, e)
  ClearCursor()
  if e[3] == 'spell' then local id = known(e[4]); if not id then return false end; (C_Spell and C_Spell.PickupSpell or PickupSpell)(id)
  elseif e[3] == 'macro' then PickupMacro(e[4])
  elseif e[3] == 'item' then local id = hasItem(e[4]); if not id then return false end; (C_Item and C_Item.PickupItem or PickupItem)(id) end
  if not GetCursorInfo() then return false end
  PlaceAction(slot); ClearCursor(); return true
end

local function apply(full)
  if InCombatLockdown() then return end
  makeMacros()
  local db = OmashuPadDB; db.mine = db.mine or {}
  if full then                                   -- first time: keep what was there, then lay out everything
    if not db.before then
      db.before = {}
      for s = 181, 208 do if HasAction(s) then local t, id = GetActionInfo(s); db.before[s] = t .. ':' .. tostring(id) end end
    end
    for s = 181, 208 do if HasAction(s) then PickupAction(s); ClearCursor() end end
    db.mine = {}
  end
  local placed, waiting = 0, {}
  for _, e in ipairs(LAYOUT) do
    local slot = BASE[e[1]] + e[2]
    if not HasAction(slot) then
      if put(slot, e) then placed = placed + 1; db.mine[slot] = e[4] else waiting[#waiting + 1] = e[4] end
    end
  end
  db.waiting = waiting
  if full or placed > 0 then say(('pad layout: %d buttons set%s'):format(placed, #waiting > 0 and (', ' .. #waiting .. ' saved for later') or '')) end
end

-- RestedXP: this realm keeps changing its name, which gives RestedXP a blank profile. Keep Bujuju's own.
local function keepRxpProfile()
  local adb = LibStub and LibStub('AceDB-3.0', true); if not adb or not adb.db_registry then return end
  for db in pairs(adb.db_registry) do
    if db.sv == RXPSettings and db.profiles and db.profiles['Bujuju Banton'] and db:GetCurrentProfile() ~= 'Bujuju Banton' then
      db:SetProfile('Bujuju Banton'); say('RestedXP settings restored')
    end
  end
end

-- Quests stay tracked (Joshua wants them, 2026-11-09); only the side panel is kept off the screen.
-- The quest log (LB+RB, D-pad up) still shows them. Undoes the earlier "tracking off" (settings v1-v2).
local function settings()
  local db = OmashuPadDB
  if (db.settingsV or 0) < 4 then
    C_CVar.SetCVar('autoQuestWatch', '1')
    local n, ok, notes = C_QuestLog.GetNumQuestLogEntries(), 0, {}
    for i = 1, n do
      local q = C_QuestLog.GetInfo(i)
      if q and not q.isHeader and q.questID then
        local a = pcall(C_QuestLog.AddQuestWatch, q.questID)
        if not C_QuestLog.GetQuestWatchType(q.questID) and AddQuestWatch then pcall(AddQuestWatch, i) end
        if C_QuestLog.GetQuestWatchType(q.questID) then ok = ok + 1 else notes[#notes + 1] = q.title .. (q.isHidden and ' (hidden)' or '') end
      end
    end
    db.retrack = { entries = n, watched = ok, missed = notes, cvar = C_CVar.GetCVar('autoQuestWatch') }
    if ok > 0 then db.settingsV = 4 end
  end
end
local function hideTracker()
  if C_QuestLog and C_QuestLog.GetNumQuestWatches then OmashuPadDB.tracked = C_QuestLog.GetNumQuestWatches() end   -- for checking
  local f = ObjectiveTrackerFrame or WatchFrame; if not f then return end
  f:SetAlpha(0)
  if not f.omashuHooked then f.omashuHooked = true; f:HookScript('OnShow', function(s) s:SetAlpha(0) end) end
end


-- Meters (Joshua, 2026-11-09): Details! (damage) on top, ForeverThreat under it, on the right edge below the
-- minimap where the quest panel was. Both hidden at every login; one pad button (/ommeters) shows or hides both.
local RIGHT, TOP, W, DH, GAP, TH = -16, -270, 300, 190, 30, 140   -- UI units (1080 px = 768 units): starts just under the minimap
local function detailsWin() local d = _G.Details; return d and d.GetInstance and d:GetInstance(1) end
local function placeMeters()
  local s = UIParent:GetEffectiveScale()
  local w = detailsWin()
  if w and w.baseframe then
    pcall(function()
      w.baseframe:ClearAllPoints(); w.baseframe:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', RIGHT, TOP - 20)
      w.baseframe:SetSize(W, DH); if w.SaveMainWindowPosition then w:SaveMainWindowPosition() end
    end)
  end
  local ft = _G.ForeverThreat
  if ft and ft.frame and ft.db then
    ft.frame:ClearAllPoints(); ft.frame:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', RIGHT, TOP - 20 - DH - GAP)
    ft.frame:SetSize(W, TH)
    ft.db.point, ft.db.x, ft.db.y, ft.db.frameWidth, ft.db.frameHeight = 'TOPRIGHT', RIGHT, TOP - 20 - DH - GAP, W, TH
    ft.db.locked = true; if ft.RefreshWindowLockState then ft:RefreshWindowLockState() end
  end
end
local function metersShown()
  local ft = _G.ForeverThreat
  if ft and ft.frame and ft.frame:IsShown() then return true end
  local w = detailsWin(); return w and w.IsEnabled and w:IsEnabled() or false
end
local function setMeters(on)
  if SlashCmdList.DETAILS then pcall(SlashCmdList.DETAILS, on and 'show' or 'hide') end
  if SlashCmdList.FOREVERTHREAT then pcall(SlashCmdList.FOREVERTHREAT, on and 'show' or 'hide') end
  if on then placeMeters() end
end
SLASH_OMASHUMETERS1 = '/ommeters'
SlashCmdList.OMASHUMETERS = function() setMeters(not metersShown()) end

-- What each addon costs in memory (KB), for checking the 8 GB laptop.
local function memory()
  if not UpdateAddOnMemoryUsage then return end
  UpdateAddOnMemoryUsage(); local m, total = {}, 0
  for i = 1, C_AddOns.GetNumAddOns() do
    local n = C_AddOns.GetAddOnInfo(i)
    if C_AddOns.IsAddOnLoaded(i) then local kb = GetAddOnMemoryUsage(i); m[n] = math.floor(kb); total = total + kb end
  end
  m.TOTAL = math.floor(total); OmashuPadDB.memory = m
end

local busy
local function later(full) if busy then return end; busy = true; C_Timer.After(2, function() busy = false; apply(full) end) end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_ENTERING_WORLD', 'SPELLS_CHANGED', 'LEARNED_SPELL_IN_SKILL_LINE', 'LEARNED_SPELL_IN_TAB', 'BAG_UPDATE_DELAYED', 'PLAYER_REGEN_ENABLED' }) do
  pcall(ev.RegisterEvent, ev, e)                -- event names differ between WoW versions
end
ev:SetScript('OnEvent', function(_, e)
  if e == 'PLAYER_ENTERING_WORLD' then
    C_Timer.After(3, function()
      pcall(keepRxpProfile); pcall(settings); pcall(hideTracker); pcall(setMeters, false); C_Timer.After(30, function() pcall(memory) end)
      local full = OmashuPadDB.layoutV ~= V
      apply(full); if full then OmashuPadDB.layoutV = V end
    end)
  else later(false) end
end)
SLASH_OMASHUPAD1 = '/ompad'
SlashCmdList.OMASHUPAD = function(m) if m == 'reset' then apply(true) else apply(false) end end
