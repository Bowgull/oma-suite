-- Omashu Pad: Bujuju's warlock controller layout (WoW Forever gamepad UI), Affliction levelling.
--
-- The gamepad bars have 3 sets (LB+RB + D-pad left/right), 28 slots each, read from the game 2026-11-09:
--   set 1 = 181-208, set 2 = 209-236, set 3 = 237-264. In each set: no trigger 4 (D-pad), then LT, RT and
--   LT+RT 8 each, in the order D-pad left, up, right, down, then X, Y, B, A.
--
-- Rules (Joshua, 2026-11-09):
--   1. Fill: a spell or item gets its button as soon as it is learned or in the bags.
--   2. Upgrade in place: a button with a list (curse, healthstone, water, food, armor, summons) moves to the best one.
--   3. Respect his changes: the add-on remembers what it put on each button. A button he changed or cleared himself
--      is his for good; the add-on never touches it again.
--   4. A new layout version moves only the add-on's own buttons.
--   New spell ranks: WoW swaps them on the bars itself (buttons are compared by spell name, so that's not "his change").
local V = 5                                    -- layout version: bump when LAYOUT changes
local L, U, R, D, X, Y, B, A = 0, 1, 2, 3, 4, 5, 6, 7
local BAR = { none = 0, LT = 4, RT = 12, LTRT = 20 }
local function slotOf(set, bar, btn) return 181 + (set - 1) * 28 + BAR[bar] + btn end

local MACROS = {                               -- Joshua's two demon buttons (his old "Good Boi", split for the pad)
  { 'PetFight', '/click PetActionButton9\n/petattack', 'Ability_Warrior_Charge' },   -- defensive + attack my target
  { 'PetHome',  '/petpassive\n/petfollow', 'Ability_Tracking' },                     -- passive + come back
  { 'Meters',   '/ommeters', 'INV_Misc_PocketWatch_01' },                            -- damage + threat meters, show/hide
}
local OLD_MACROS = { 'Bolt', 'PetGo', 'PetBack', 'PetMove', 'PetOne', 'PetTwo', 'Stone', 'Drink' }
local STONES = { 9421, 5510, 5509, 5511, 5512 }                    -- Major .. Minor Healthstone, best first
local WATERS = { 8766, 1645, 1708, 1205, 1179, 159 }                -- vendor water, best first
local FOODS  = { 8948, 4608, 4607, 4606, 4605, 4604 }               -- vendor mushrooms (Undercity), best first

-- { set, bar, button, kind, name or list (best first) }    kind: spell | macro | item
local LAYOUT = {
  -- SET 1 (v5, Joshua 2026-11-09): the face buttons (with a trigger) hold the most-used actions; the bare D-pad is the demon.
  -- No trigger, D-pad: the demon
  { 1, 'none', U, 'macro', 'PetFight' },                                 -- defensive + attack my target
  { 1, 'none', D, 'macro', 'PetHome' },                                  -- passive + follow
  { 1, 'none', L, 'spell', 'Health Funnel' },                            -- your health -> the demon
  { 1, 'none', R, 'spell', { 'Summon Sayaad', 'Summon Succubus', 'Summon Incubus', 'Summon Voidwalker', 'Summon Imp' } }, -- main demon by level
  -- LT + face: the pull
  { 1, 'LT', X, 'spell', 'Bane of Agony' },
  { 1, 'LT', Y, 'spell', 'Corruption' },
  { 1, 'LT', B, 'spell', 'Immolate' },
  { 1, 'LT', A, 'spell', 'Shoot' },                                      -- wand
  -- RT + face: keeping going
  { 1, 'RT', X, 'spell', 'Life Tap' },
  { 1, 'RT', Y, 'spell', 'Drain Life' },
  { 1, 'RT', B, 'spell', 'Fear' },
  { 1, 'RT', A, 'item', STONES },
  -- LT + D-pad, RT + D-pad: rare
  { 1, 'LT', U, 'spell', 'Shadow Bolt' },
  { 1, 'LT', R, 'spell', { 'Siphon Life', 'Drain Soul' } },              -- Drain Soul until 41, then Siphon Life (Drain Soul -> set 2)
  { 1, 'LT', L, 'spell', { 'Curse of the Elements', 'Curse of Weakness' } },
  { 1, 'LT', D, 'spell', 'Will of the Forsaken' },
  { 1, 'RT', U, 'spell', 'Summon Imp' },
  { 1, 'RT', R, 'spell', 'Summon Voidwalker' },
  { 1, 'RT', D, 'spell', 'Summon Felhunter' },
  { 1, 'RT', L, 'macro', 'Meters' },
  -- LT+RT: rare, out of fights
  { 1, 'LTRT', U, 'item', 6948 },                                        -- Hearthstone
  { 1, 'LTRT', R, 'spell', 'Find Minerals' },
  { 1, 'LTRT', L, 'spell', 'Tailoring' },
  { 1, 'LTRT', D, 'drink', WATERS },                                     -- smart: best drink in the bags (fallback list)
  { 1, 'LTRT', X, 'food', FOODS },                                       -- smart: best food in the bags (fallback list)
  { 1, 'LTRT', Y, 'spell', { 'Demon Armor', 'Demon Skin' } },
  { 1, 'LTRT', B, 'spell', 'Cannibalize' },
  { 1, 'LTRT', A, 'spell', 'Create Healthstone' },
  -- SET 2 (LB+RB, D-pad right): travel and utility. Fills in as you level.
  { 2, 'none', U, 'spell', { 'Summon Dreadsteed', 'Summon Felsteed' } }, -- mount (40)
  { 2, 'none', R, 'spell', 'Create Soulstone' },                         -- 18
  { 2, 'none', L, 'spell', 'Ritual of Summoning' },                      -- 20
  { 2, 'none', D, 'spell', 'Unending Breath' },
  { 2, 'LT', U, 'spell', 'Drain Soul' },                                 -- soul shards (shares LT+down on set 1 until 41)
  { 2, 'LT', R, 'spell', 'Death Coil' },
  { 2, 'LT', L, 'spell', 'Howl of Terror' },
  { 2, 'LT', D, 'spell', 'Banish' },
  { 2, 'LT', X, 'spell', 'Shadow Ward' },
  { 2, 'LT', Y, 'spell', 'Curse of Tongues' },
  { 2, 'LT', B, 'spell', 'Curse of Recklessness' },
  { 2, 'LT', A, 'spell', 'Curse of Exhaustion' },
  { 2, 'RT', U, 'spell', 'Eye of Kilrogg' },
  { 2, 'RT', R, 'spell', 'Enslave Demon' },
  { 2, 'RT', L, 'spell', 'Detect Invisibility' },
  { 2, 'RT', D, 'spell', 'Sense Demons' },
  { 2, 'RT', X, 'spell', 'Rain of Fire' },
  { 2, 'RT', Y, 'spell', 'Hellfire' },
  { 2, 'RT', B, 'spell', 'Searing Pain' },
  { 2, 'RT', A, 'spell', 'Soul Fire' },
  { 2, 'LTRT', U, 'spell', 'Create Firestone' },
  { 2, 'LTRT', R, 'spell', 'Create Spellstone' },
  { 2, 'LTRT', L, 'spell', 'Inferno' },
  { 2, 'LTRT', D, 'spell', 'Ritual of Doom' },
  -- SET 3 stays free for talents and anything later.
}

OmashuPadDB = OmashuPadDB or {}
local function say(m) print('|cffe8c860Omashu:|r ' .. m) end
local spellName = function(id) return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id)) end
local function knownId(name)
  if type(name) == 'table' then for _, n in ipairs(name) do local id = knownId(n); if id then return id end end; return nil end
  local id
  if C_Spell and C_Spell.GetSpellInfo then local i = C_Spell.GetSpellInfo(name); id = i and i.spellID else id = select(7, GetSpellInfo(name)) end
  return id and IsPlayerSpell and IsPlayerSpell(id) and id or nil
end
local count = C_Item and C_Item.GetItemCount or GetItemCount
local function bestItem(ids)
  if type(ids) ~= 'table' then ids = { ids } end
  for _, i in ipairs(ids) do if count(i) > 0 then return i end end
end
local function inList(list, v) if type(list) ~= 'table' then return list == v end; for _, x in ipairs(list) do if x == v then return true end end end

-- Smart food and water (Joshua, 2026-11-09). Scan the bags for anything that is Food & Drink, read what it restores
-- from its tooltip, and pick: food = cooked Well Fed food first (+5% kill XP on Forever), then the most health;
-- drink = Well Fed smoothies first, then the most mana. Only things usable at your level. If no tooltip can be read,
-- the fixed vendor lists above still work. Every scan is written to OmashuPadDB.foodScan for checking.
local FOOD_CLASS, FOOD_SUB = 0, 5                                        -- Consumable, Food & Drink
local scan, scanAt = nil, 0
local function tipLines(bag, slot)
  if C_TooltipInfo and C_TooltipInfo.GetBagItem then
    local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if ok and data and data.lines then local out = {}; for _, l in ipairs(data.lines) do out[#out + 1] = l.leftText or '' end; return out end
  end
end
local function scanBags()
  if scan and GetTime() - scanAt < 1 then return scan end
  local found, seen, lvl = {}, {}, UnitLevel('player')
  local getID = C_Container and C_Container.GetContainerItemID or GetContainerItemID
  local slots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  for bag = 0, 5 do
    for slot = 1, (slots(bag) or 0) do
      local id = getID(bag, slot)
      if id and not seen[id] then
        seen[id] = true
        local _, _, _, _, _, cls, sub = C_Item.GetItemInfoInstant(id)
        if cls == FOOD_CLASS and sub == FOOD_SUB then
          local name, _, _, _, minLevel = C_Item.GetItemInfo(id)
          local lines, hp, mana, fed = tipLines(bag, slot), 0, 0, false
          for _, l in ipairs(lines or {}) do
            local low = l:lower()
            local a = low:match('restores ([%d,]+) health'); if a then hp = math.max(hp, tonumber((a:gsub(',', ''))) or 0) end
            local m = low:match('restores ([%d,]+) mana') or low:match('and ([%d,]+) mana'); if m then mana = math.max(mana, tonumber((m:gsub(',', ''))) or 0) end
            if low:find('well fed') then fed = true end
          end
          found[#found + 1] = { id = id, name = name or ('item ' .. id), minLevel = minLevel or 0, hp = hp, mana = mana, fed = fed,
                                usable = (minLevel or 0) <= lvl, tip = lines ~= nil }
        end
      end
    end
  end
  scan, scanAt = found, GetTime()
  OmashuPadDB.foodScan = {}
  for _, f in ipairs(found) do
    OmashuPadDB.foodScan[#OmashuPadDB.foodScan + 1] = ('%s (%d): health %d, mana %d%s, level %d%s%s'):format(f.name, f.id, f.hp, f.mana,
      f.fed and ', Well Fed' or '', f.minLevel, f.usable and '' or ' TOO HIGH', f.tip and '' or ', no tooltip')
  end
  return found
end
local function bestConsumable(kind)
  local best, bestScore
  for _, f in ipairs(scanBags()) do
    if f.usable then
      local amount = kind == 'food' and f.hp or f.mana
      if amount > 0 then
        local score = (f.fed and 1e6 or 0) + amount
        if not bestScore or score > bestScore then best, bestScore = f.id, score end
      end
    end
  end
  return best
end
local function isFoodDrink(id)
  local _, _, _, _, _, cls, sub = C_Item.GetItemInfoInstant(id); return cls == FOOD_CLASS and sub == FOOD_SUB
end

-- What a slot holds, as 'spell:<name>', 'macro:<name>' or 'item:<id>' (spell by NAME so new ranks match).
local function sigOf(slot)
  if not HasAction(slot) then return nil end
  local ty, id = GetActionInfo(slot)
  if ty == 'spell' then return 'spell:' .. tostring(spellName(id)) end
  if ty == 'macro' then return 'macro:' .. tostring((GetMacroInfo(id))) end
  if ty == 'item' then return 'item:' .. tostring(id) end
  return tostring(ty) .. ':' .. tostring(id)
end
-- What a layout entry wants right now: its sig and how to pick it up, or nil if nothing is available yet.
local function want(e)
  if e[4] == 'spell' then local id = knownId(e[5]); if id then return 'spell:' .. tostring(spellName(id)), function() (C_Spell and C_Spell.PickupSpell or PickupSpell)(id) end end
  elseif e[4] == 'macro' then if GetMacroIndexByName(e[5]) > 0 then return 'macro:' .. e[5], function() PickupMacro(e[5]) end end
  elseif e[4] == 'item' then local i = bestItem(e[5]); if i then return 'item:' .. i, function() (C_Item and C_Item.PickupItem or PickupItem)(i) end end
  elseif e[4] == 'food' or e[4] == 'drink' then
    local ok, i = pcall(bestConsumable, e[4]); if not ok or not i then i = bestItem(e[5]) end
    if i then return 'item:' .. i, function() (C_Item and C_Item.PickupItem or PickupItem)(i) end end
  end
end
-- Is this sig one of the entry's own options (so the add-on may upgrade it)?
local function ownsOption(e, sig)
  if not sig then return false end
  local k, v = sig:match('^(%a+):(.*)$')
  if (e[4] == 'food' or e[4] == 'drink') and k == 'item' then return isFoodDrink(tonumber(v)) end
  if k ~= e[4] then return false end
  if k == 'item' then return inList(e[5], tonumber(v)) end
  return inList(e[5], v)
end

local function makeMacros()
  for _, n in ipairs(OLD_MACROS) do local i = GetMacroIndexByName(n); if i > 0 then DeleteMacro(i) end end
  for _, m in ipairs(MACROS) do
    local i = GetMacroIndexByName(m[1])
    if i == 0 then CreateMacro(m[1], m[3] or 'INV_MISC_QUESTIONMARK', m[2], true) else EditMacro(i, m[1], m[3] or 'INV_MISC_QUESTIONMARK', m[2]) end
  end
end

local function place(slot, pickup)
  ClearCursor(); pickup()
  if not GetCursorInfo() then return false end
  PlaceAction(slot); ClearCursor(); return true
end

local function apply()
  if InCombatLockdown() then return end
  makeMacros()
  local db = OmashuPadDB
  db.mine = db.mine or {}; db.his = db.his or {}
  -- One-time: older versions stored names, and everything on 181-208 was the add-on's. Adopt it.
  if (db.rulesV or 0) < 1 then
    db.mine, db.his = {}, {}
    for s = 181, 208 do db.mine[s] = sigOf(s) end
    db.rulesV = 1
  end
  -- Notice his own changes: a slot that no longer holds what the add-on put there is his for good.
  for s, sig in pairs(db.mine) do
    if sigOf(s) ~= sig then db.his[s] = sigOf(s) or 'cleared'; db.mine[s] = nil end
  end
  -- New layout version: take the add-on's own buttons off; his stay where they are.
  local moved = 0
  if db.layoutV ~= V then
    for s in pairs(db.mine) do if HasAction(s) then PickupAction(s); ClearCursor(); moved = moved + 1 end; db.mine[s] = nil end
    db.layoutV = V
  end
  local placed, upgraded, waiting, blocked = 0, 0, {}, {}
  for _, e in ipairs(LAYOUT) do
    local slot = slotOf(e[1], e[2], e[3])
    if db.his[slot] then
      blocked[#blocked + 1] = slot
    else
      local sig, pickup = want(e)
      local cur = sigOf(slot)
      if not sig then
        if not cur then waiting[#waiting + 1] = type(e[5]) == 'table' and tostring(e[5][1]) or tostring(e[5]) end
      elseif not cur then
        if place(slot, pickup) then placed = placed + 1; db.mine[slot] = sigOf(slot) end
      elseif cur ~= sig and db.mine[slot] == cur and ownsOption(e, cur) then
        if place(slot, pickup) then upgraded = upgraded + 1; db.mine[slot] = sigOf(slot) end
      end
    end
  end
  db.waiting, db.blocked = waiting, blocked
  if placed + upgraded + moved > 0 then
    say(('pad: %d set, %d upgraded%s'):format(placed, upgraded, #waiting > 0 and (', ' .. #waiting .. ' waiting for later levels') or ''))
  end
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
local function later() if busy then return end; busy = true; C_Timer.After(2, function() busy = false; apply() end) end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_ENTERING_WORLD', 'SPELLS_CHANGED', 'LEARNED_SPELL_IN_SKILL_LINE', 'LEARNED_SPELL_IN_TAB', 'BAG_UPDATE_DELAYED', 'PLAYER_REGEN_ENABLED' }) do
  pcall(ev.RegisterEvent, ev, e)                -- event names differ between WoW versions
end
ev:SetScript('OnEvent', function(_, e)
  if e == 'PLAYER_ENTERING_WORLD' then
    C_Timer.After(3, function()
      pcall(keepRxpProfile); pcall(settings); pcall(hideTracker); pcall(setMeters, false)
      C_Timer.After(30, function() pcall(memory) end)
      apply()
    end)
  else later() end
end)
-- /ompad: re-check now.  /ompad mine: hand every pad button back to the add-on (forgets which were his).
SLASH_OMASHUPAD1 = '/ompad'
SlashCmdList.OMASHUPAD = function(m)
  if m == 'mine' then OmashuPadDB.his = {}; OmashuPadDB.rulesV = 0 end
  apply()
end
