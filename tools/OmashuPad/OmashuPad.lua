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
--   5. Nothing it places appears twice (LAYOUT order is priority). Checked after every pass; /ompad sim replays 7-41.
--   New spell ranks: WoW swaps them on the bars itself (buttons are compared by spell name, so that's not "his change").
local V = 7                                    -- layout version: bump when LAYOUT changes
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
  -- SET 1 (v6, Joshua 2026-11-09: "the buttons I want to press most are the face buttons"). Eight most-pressed actions on
  -- trigger + face buttons (bare face buttons are Blizzard's: jump, back, interact, inspect). A whole pull = hold RT, X Y B A.
  -- v7 (Joshua 2026-11-10): "my right trigger is the main pull, the left trigger the other stuff": LT and RT swapped in every set.
  -- RT + face: the pull
  { 1, 'RT', X, 'macro', 'PetFight' },                                   -- demon: defensive + attack my target
  { 1, 'RT', Y, 'spell', 'Corruption' },
  { 1, 'RT', B, 'spell', 'Bane of Agony' },
  { 1, 'RT', A, 'spell', 'Shoot' },                                      -- wand
  -- LT + face: keeping it going
  { 1, 'LT', X, 'spell', 'Life Tap' },
  { 1, 'LT', Y, 'spell', 'Drain Life' },
  { 1, 'LT', B, 'spell', 'Immolate' },
  { 1, 'LT', A, 'spell', 'Fear' },
  -- bare D-pad: support
  { 1, 'none', U, 'macro', 'PetHome' },                                  -- demon: passive + follow
  { 1, 'none', R, 'item', STONES },                                      -- Healthstone
  { 1, 'none', L, 'spell', 'Health Funnel' },
  { 1, 'none', D, 'spell', 'Shadow Bolt' },
  -- RT + D-pad
  { 1, 'RT', U, 'spell', { 'Siphon Life', 'Drain Soul' } },              -- Drain Soul until 41, then Siphon Life (Drain Soul -> set 2)
  { 1, 'RT', L, 'spell', { 'Curse of the Elements', 'Curse of Weakness' } },
  { 1, 'RT', D, 'spell', 'Will of the Forsaken' },
  { 1, 'RT', R, 'macro', 'Meters' },
  -- LT + D-pad: Cannibalize, and room for the emergency spells you learn later
  { 1, 'LT', U, 'spell', 'Cannibalize' },
  { 1, 'LT', R, 'spell', 'Death Coil' },
  { 1, 'LT', L, 'spell', 'Howl of Terror' },
  { 1, 'LT', D, 'spell', 'Shadow Ward' },
  -- LT + RT: out of the fight
  { 1, 'LTRT', U, 'spell', 'Summon Imp' },
  { 1, 'LTRT', R, 'spell', 'Summon Voidwalker' },
  { 1, 'LTRT', D, 'spell', { 'Summon Sayaad', 'Summon Succubus', 'Summon Incubus' } },
  { 1, 'LTRT', L, 'spell', 'Summon Felhunter' },
  { 1, 'LTRT', X, 'food', FOODS },
  { 1, 'LTRT', Y, 'drink', WATERS },
  { 1, 'LTRT', B, 'spell', { 'Demon Armor', 'Demon Skin' } },
  { 1, 'LTRT', A, 'spell', 'Create Healthstone' },
  -- SET 2 (LB+RB, D-pad right): travel and utility. Fills in as you level.
  { 2, 'LT', U, 'item', 6948 },                                          -- Hearthstone (moved from set 1 in v6)
  { 2, 'LTRT', X, 'spell', 'Find Minerals' },
  { 2, 'LTRT', Y, 'spell', 'Tailoring' },
  { 2, 'none', U, 'spell', { 'Summon Dreadsteed', 'Summon Felsteed' } }, -- mount (40)
  { 2, 'none', R, 'spell', 'Create Soulstone' },                         -- 18
  { 2, 'none', L, 'spell', 'Ritual of Summoning' },                      -- 20
  { 2, 'none', D, 'spell', 'Unending Breath' },
  { 2, 'RT', U, 'spell', 'Drain Soul' },                                 -- soul shards (shares RT+up on set 1 until 41)
  { 2, 'RT', D, 'spell', 'Banish' },
  { 2, 'RT', Y, 'spell', 'Curse of Tongues' },
  { 2, 'RT', B, 'spell', 'Curse of Recklessness' },
  { 2, 'RT', A, 'spell', 'Curse of Exhaustion' },
  { 2, 'LT', R, 'spell', 'Enslave Demon' },
  { 2, 'RT', R, 'spell', 'Eye of Kilrogg' },
  { 2, 'LT', L, 'spell', 'Detect Invisibility' },
  { 2, 'LT', D, 'spell', 'Sense Demons' },
  { 2, 'LT', X, 'spell', 'Rain of Fire' },
  { 2, 'LT', Y, 'spell', 'Hellfire' },
  { 2, 'LT', B, 'spell', 'Searing Pain' },
  { 2, 'LT', A, 'spell', 'Soul Fire' },
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
local fakeKnown = nil                                                    -- set only by /ompad sim
local function knownSpell(name)
  if fakeKnown then
    for _, n in ipairs(type(name) == 'table' and name or { name }) do if fakeKnown[n] then return n end end
    return nil
  end
  local id = knownId(name); if id then return spellName(id), id end
end
local function want(e)
  if e[4] == 'spell' then local n, id = knownSpell(e[5]); if n then return 'spell:' .. tostring(n), function() (C_Spell and C_Spell.PickupSpell or PickupSpell)(id) end end
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

-- The rules run on a "board": the real action bars, or a copy in the simulation.
local realBoard = {
  get = function(slot) return sigOf(slot) end,
  put = function(slot, sig, pickup) return place(slot, pickup) end,
  clear = function(slot) if HasAction(slot) then PickupAction(slot); ClearCursor() end end,
}
local PAD_FIRST, PAD_LAST = 181, 264

-- Rule 5 (2026-11-09, Joshua: "is summon demon on there twice?"): nothing the add-on places appears twice.
-- LAYOUT order is priority: if an earlier button already holds a spell or item, a later button for the same thing
-- stays empty (and the add-on takes its own copy off). So the main-demon button wins and the RT summons skip it;
-- set 1's Drain Soul wins until Siphon Life replaces it, then set 2's Drain Soul fills in.
local function runRules(board, st)
  local placed, upgraded, cleared, waiting, blocked, claimed = 0, 0, 0, {}, {}, {}
  for _, e in ipairs(LAYOUT) do
    local slot = slotOf(e[1], e[2], e[3])
    local cur = board.get(slot)
    if st.his[slot] then
      blocked[#blocked + 1] = slot
      if cur and not claimed[cur] then claimed[cur] = slot end
    else
      local sig, pickup = want(e)
      if sig and claimed[sig] then
        if cur and st.mine[slot] == cur then board.clear(slot); st.mine[slot] = nil; cleared = cleared + 1 end
      else
        if not sig then
          if not cur then waiting[#waiting + 1] = type(e[5]) == 'table' and tostring(e[5][1]) or tostring(e[5]) end
        elseif not cur then
          if board.put(slot, sig, pickup) then placed = placed + 1; st.mine[slot] = board.get(slot) end
        elseif cur ~= sig and st.mine[slot] == cur and ownsOption(e, cur) then
          if board.put(slot, sig, pickup) then upgraded = upgraded + 1; st.mine[slot] = board.get(slot) end
        end
        local now = board.get(slot)
        if now and not claimed[now] then claimed[now] = slot end
      end
    end
  end
  return placed, upgraded, cleared, waiting, blocked
end

-- Self-check after every pass: any spell or item on two pad buttons where at least one is the add-on's = a bug.
local function duplicates(board, mine)
  local where, dups = {}, {}
  for s = PAD_FIRST, PAD_LAST do local sig = board.get(s); if sig then where[sig] = where[sig] or {}; table.insert(where[sig], s) end end
  for sig, slots in pairs(where) do
    if #slots > 1 then local ours = false; for _, s in ipairs(slots) do if mine[s] then ours = true end end
      if ours then dups[#dups + 1] = sig .. ' on ' .. table.concat(slots, ',') end end
  end
  table.sort(dups); return dups
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
  local placed, upgraded, cleared, waiting, blocked = runRules(realBoard, db)
  db.waiting, db.blocked = waiting, blocked
  local dups = duplicates(realBoard, db.mine)
  db.check = { at = date('%Y-%m-%d %H:%M:%S'), dups = dups }
  if #dups > 0 then say('|cffff6060duplicate buttons:|r ' .. table.concat(dups, '; ')) end
  if placed + upgraded + moved + cleared > 0 then
    say(('pad: %d set, %d upgraded%s%s'):format(placed, upgraded, cleared > 0 and (', ' .. cleared .. ' doubled one taken off') or '',
      #waiting > 0 and (', ' .. #waiting .. ' waiting for later levels') or ''))
  end
end

-- /ompad sim: replays levelling from 7 to 41 on a COPY of the bars (nothing on screen changes) and checks each step:
-- no duplicates, every known demon reachable once, Joshua's own buttons untouched. Results in OmashuPadDB.sim.
local SIM_STEPS = {
  { 7,  { 'Shadow Bolt', 'Immolate', 'Corruption', 'Life Tap', 'Summon Imp', 'Demon Skin', 'Shoot', 'Will of the Forsaken', 'Cannibalize', 'Tailoring', 'Find Minerals' } },
  { 10, { 'Bane of Agony', 'Fear', 'Curse of Weakness', 'Drain Soul', 'Summon Voidwalker', 'Create Healthstone' } },
  { 12, { 'Health Funnel' }, 'his' },                                       -- here Joshua puts his own thing on RT up
  { 20, { 'Drain Life', 'Summon Sayaad', 'Ritual of Summoning', 'Create Soulstone', 'Unending Breath', 'Demon Armor' } },
  { 30, { 'Summon Felhunter', 'Banish' } },
  { 41, { 'Siphon Life', 'Curse of the Elements', 'Summon Felsteed' } },
}
local function simulate()
  local bars, st = {}, { mine = {}, his = {} }
  for s = PAD_FIRST, PAD_LAST do bars[s] = sigOf(s) end
  for s, v in pairs(OmashuPadDB.mine or {}) do st.mine[s] = v end
  for s, v in pairs(OmashuPadDB.his or {}) do st.his[s] = v end
  local board = { get = function(s) return bars[s] end, put = function(s, sig) bars[s] = sig; return true end, clear = function(s) bars[s] = nil end }
  if (OmashuPadDB.layoutV or 0) ~= V then for s in pairs(st.mine) do bars[s] = nil; st.mine[s] = nil end end
  local known, report, ok = {}, {}, true
  local DEMONS = { 'Summon Imp', 'Summon Voidwalker', 'Summon Sayaad', 'Summon Felhunter' }
  for _, step in ipairs(SIM_STEPS) do
    for _, n in ipairs(step[2]) do known[n] = true end
    if step[3] == 'his' then local s = slotOf(1, 'LTRT', U); bars[s] = 'spell:Joshua own choice'; st.mine[s] = nil; st.his[s] = bars[s] end
    fakeKnown = known
    local okRun, err = pcall(runRules, board, st)
    fakeKnown = nil
    if not okRun then ok = false; report[#report + 1] = ('lvl %d: ERROR %s'):format(step[1], tostring(err)); break end
    local dups = duplicates(board, st.mine)
    local demons = {}
    for _, d in ipairs(DEMONS) do if known[d] then local n = 0; for s = PAD_FIRST, PAD_LAST do if bars[s] == 'spell:' .. d then n = n + 1 end end
      -- exactly once, unless Joshua took that demon's own button for something else (then 0 is right)
      local own = ({ ['Summon Imp'] = slotOf(1, 'LTRT', U), ['Summon Voidwalker'] = slotOf(1, 'LTRT', R), ['Summon Sayaad'] = slotOf(1, 'LTRT', D), ['Summon Felhunter'] = slotOf(1, 'LTRT', L) })[d]
      local excused = n == 0 and own and st.his[own]
      demons[#demons + 1] = d:gsub('Summon ', '') .. '=' .. n .. (excused and ' (his button)' or ''); if n > 1 or (n == 0 and not excused) then ok = false end end end
    local hisOk = not st.his[slotOf(1, 'LTRT', U)] or bars[slotOf(1, 'LTRT', U)] == 'spell:Joshua own choice'
    if #dups > 0 or not hisOk then ok = false end
    report[#report + 1] = ('lvl %d: RT face %s/%s/%s/%s | LT face %s/%s/%s/%s | RT up=%s | set2 RT up=%s | demons %s | dups %s | his %s'):format(step[1],
      tostring(bars[slotOf(1, 'RT', X)]), tostring(bars[slotOf(1, 'RT', Y)]), tostring(bars[slotOf(1, 'RT', B)]), tostring(bars[slotOf(1, 'RT', A)]),
      tostring(bars[slotOf(1, 'LT', X)]), tostring(bars[slotOf(1, 'LT', Y)]), tostring(bars[slotOf(1, 'LT', B)]), tostring(bars[slotOf(1, 'LT', A)]),
      tostring(bars[slotOf(1, 'RT', U)]), tostring(bars[slotOf(2, 'RT', U)]), table.concat(demons, ' '), #dups == 0 and 'none' or table.concat(dups, '; '),
      hisOk and 'kept' or 'TOUCHED')
  end
  OmashuPadDB.sim = { at = date('%Y-%m-%d %H:%M:%S'), pass = ok, steps = report }
  say('simulation ' .. (ok and '|cff60ff60passed|r' or '|cffff6060FAILED|r') .. ' (' .. #report .. ' steps, details saved)')
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
-- ForeverThreat shows itself when a fight starts; Joshua wants the meters on his button only (2026-11-09).
local function meterButtonOnly()
  local ft = _G.ForeverThreat
  if ft and ft.db then ft.db.autoShowInCombat = false; ft.db.autoShowOnlyWithThreat = false end
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


-- one-off probe of RestedXP's window (its own frames only)
local function rxpProbe()
  local f = _G.RXPFrame; if not f then OmashuPadDB.rxpProbe = 'no frame'; return end
  local out, H = {}, UIParent:GetHeight()
  local function px(top, s) return math.floor(1080 - top * s * 1080 / 768 + .5) end
  local function row(name, fr)
    local ok, l, b, tp = pcall(function() return fr:GetLeft(), fr:GetBottom(), fr:GetTop() end)
    if ok and l and fr:IsVisible() then local s = fr:GetEffectiveScale()
      out[#out + 1] = ('%s top %dpx bottom %dpx left %d scale %.2f'):format(name, px(tp, s), px(b, s), math.floor(l * s * 1080 / 768), fr:GetScale()) end
  end
  row('RXPFrame', f)
  local np, rel, rp, x, y = f:GetPoint(1); out[#out + 1] = ('point %s %s %s %.1f %.1f'):format(tostring(np), tostring(rel and rel.GetName and rel:GetName()), tostring(rp), x or 0, y or 0)
  local function walk(fr, depth, path)
    if depth > 3 then return end
    for i, c in ipairs({ fr:GetChildren() }) do
      local n = (c.GetName and c:GetName()) or (path .. '.' .. i); row(n, c); walk(c, depth + 1, n)
    end
  end
  walk(f, 1, 'RXPFrame')
  OmashuPadDB.rxpProbe = out
end
-- RestedXP auto-fit (Joshua, 2026-11-09): its bottom bar is pinned and the steps stack upward, so a long step group
-- can climb into the shard gems. Twice a second: if the topmost step is above LIMIT px from the screen top, shrink the
-- whole window just enough (keeping the bottom bar where it is); grow back when there is room again. Never below 85%.
local LIMIT, ROOM, MINF = 300, 60, .85
local fit = { base = nil, last = 0 }
local function pxTop(fr) local tp = fr:GetTop(); if not tp then return nil end; return 1080 - tp * fr:GetEffectiveScale() * 1080 / 768 end
local function rxpTopPx(f)
  local best = pxTop(f)
  for _, c in ipairs({ f:GetChildren() }) do
    if c:IsVisible() then local p = pxTop(c); if p and (not best or p < best) then best = p end
      for _, g in ipairs({ c:GetChildren() }) do if g:IsVisible() then local q = pxTop(g); if q and q < best then best = q end end end end
  end
  return best
end
local function rxpFit()
  local f = _G.RXPFrame; if not f or not f:IsVisible() then return end
  local s = f:GetScale(); fit.base = fit.base or s
  if s > fit.base * 1.001 or s < fit.base * MINF * .999 then fit.base = s end            -- RestedXP (or Joshua) changed its size: follow it
  local top = rxpTopPx(f); local bottom = f:GetBottom() and (1080 - f:GetBottom() * f:GetEffectiveScale() * 1080 / 768)
  if not top or not bottom or bottom - top < 10 then return end
  local want = s
  if top < LIMIT then want = s * (bottom - LIMIT) / (bottom - top)
  elseif top > LIMIT + ROOM and s < fit.base then want = math.min(fit.base, s * (bottom - LIMIT - ROOM / 2) / (bottom - top)) end
  want = math.max(fit.base * MINF, math.min(fit.base, want))
  if math.abs(want - s) < .01 then return end
  -- keep the bottom-left corner where it is on screen while the scale changes
  local u = UIParent:GetEffectiveScale(); local e = f:GetEffectiveScale()
  local l, b = f:GetLeft() * e / u, f:GetBottom() * e / u
  f:SetScale(want); f:ClearAllPoints(); f:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', l / want, b / want)
  OmashuPadDB.rxpFit = ('%s top %dpx -> scale %.2f (base %.2f)'):format(date('%H:%M:%S'), top, want, fit.base)
end
local fitTicker = CreateFrame('Frame'); local acc = 0
fitTicker:SetScript('OnUpdate', function(_, el) acc = acc + el; if acc < .5 then return end; acc = 0; pcall(rxpFit) end)
-- Controller bar fade: REMOVED 2026-11-09. Setting the alpha of GamepadMainActionBarFrame (a protected Blizzard frame)
-- from add-on code tainted the gamepad UI: the game menu and chat Enter were then blocked ("Interface action failed
-- because of an AddOn"). The code is in git history (commit before this note). Do not touch that frame.
SLASH_OMASHURXP1 = '/omrxp'
SlashCmdList.OMASHURXP = function(m)
  local n = tonumber((m or ''):match('limit%s+(%d+)')); if n then LIMIT = n; say('RestedXP fit line ' .. n .. ' px'); return end
  rxpProbe()
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
      pcall(keepRxpProfile); pcall(settings); pcall(hideTracker); pcall(meterButtonOnly); pcall(setMeters, false)
      C_Timer.After(30, function() pcall(memory) end)
      apply()
    end)
  else later() end
end)
-- /ompad: re-check now.  /ompad sim: replay levelling on a copy and check the rules.  /ompad mine: hand every pad button back to the add-on (forgets which were his).
SLASH_OMASHUPAD1 = '/ompad'
SlashCmdList.OMASHUPAD = function(m)
  if m == 'sim' then simulate(); return end
  if m == 'keys' then   -- every gamepad button (and LB/RB/LT/RT/View combos) -> what it's bound to, saved for Claude to read
    local names = { 'PADA', 'PADB', 'PADX', 'PADY', 'PADLSHOULDER', 'PADRSHOULDER', 'PADLTRIGGER', 'PADRTRIGGER',
      'PADLSTICK', 'PADRSTICK', 'PADBACK', 'PADFORWARD', 'PADSYSTEM', 'PADSOCIAL', 'PADDUP', 'PADDDOWN', 'PADDLEFT', 'PADDRIGHT',
      'PADPADDLE1', 'PADPADDLE2', 'PADPADDLE3', 'PADPADDLE4' }
    local mods = { '', 'SHIFT-', 'CTRL-', 'ALT-', 'CTRL-SHIFT-', 'ALT-SHIFT-', 'ALT-CTRL-' }
    local out = {}
    for _, md in ipairs(mods) do for _, n in ipairs(names) do local a = GetBindingAction(md .. n); if a and a ~= '' then out[md .. n] = a end end end
    local cv = {}
    for _, c in ipairs({ 'GamePadEmulateShift', 'GamePadEmulateCtrl', 'GamePadEmulateAlt', 'GamePadEnable' }) do cv[c] = C_CVar.GetCVar(c) end
    OmashuPadDB.keys, OmashuPadDB.keyCVars = out, cv
    say('pad keys saved; /reload to write them to the file (an add-on can\'t reload by itself).'); return
  end
  if m == 'mine' then OmashuPadDB.his = {}; OmashuPadDB.rulesV = 0 end
  apply()
end
