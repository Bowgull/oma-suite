-- OmaPad: Joshua's controller layouts (WoW Forever gamepad UI), one per class: Bujuju's warlock (Affliction
-- levelling) and the paladin alt (Retribution levelling). Both follow the same design, so the hands don't have to
-- relearn anything between characters: RT + face = the pull, LT + face = keeping it going, bare D-pad = support,
-- LT + D-pad = emergencies, LT + RT = out of the fight, set 2 = travel and utility, set 3 free.
--
-- Class-aware (2026-11-26, Joshua: "class aware is best"): every class has its own LAYOUT and layout version, and the
-- add-on's memory of which buttons it placed and which are his lives PER CHARACTER (OmaPadCharDB). It used to live
-- in the account-wide OmaPadDB, where a second character's bars would have read as "he changed all of these".
-- The warlock's old account-wide memory is moved onto the warlock the first time it logs in, unchanged, so not one
-- of its buttons moves. A class without a layout gets only the Meters macro.
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
local VERSIONS = { WARLOCK = 15, PALADIN = 2 } -- layout version per class: bump a class's number when its LAYOUT changes
local function playerClass() return select(2, UnitClass('player')) end
local L, U, R, D, X, Y, B, A = 0, 1, 2, 3, 4, 5, 6, 7
local BAR = { none = 0, LT = 4, RT = 12, LTRT = 20 }
local function slotOf(set, bar, btn) return 181 + (set - 1) * 28 + BAR[bar] + btn end

-- the pet bar slot holding Defensive Assist for the demon that's out, or nil (no demon)
local function petFightBody()
  for i = 1, 10 do
    local n = GetPetActionInfo(i)
    if n == 'PET_MODE_DEFENSIVEASSIST' then return '/click PetActionButton' .. i .. ' LeftButton 1\n/petattack' end
  end
end
local METERS_MACRO = { 'Meters', '/ommeters', 'INV_Misc_PocketWatch_01' }         -- damage + threat meters, show/hide
local MACROS_BY_CLASS = {}
MACROS_BY_CLASS.WARLOCK = {                    -- Joshua's two demon buttons (his old "Good Boi", split for the pad)
  -- Defensive Assist + attack (Joshua 2026-11-11, "fighting for weeks"). Measured in game: Forever's pet bar has Assist,
  -- Defensive Assist and Passive (no plain Defensive, so /petdefensive does nothing) and no slash command for Defensive
  -- Assist. So the macro presses that pet-bar button, with "LeftButton 1" = key down (this engine's buttons ignore the
  -- key-up a bare /click sends). Its slot depends on the demon, so the body is rebuilt whenever the pet changes.
  { 'PetFight', function() return petFightBody() end, 'Ability_Warrior_Charge' },     -- defensive assist + attack my target
  { 'PetHome',  '/petpassive\n/petfollow', 'Ability_Tracking' },                     -- passive + come back
  METERS_MACRO,
}
MACROS_BY_CLASS.PALADIN = { METERS_MACRO }
local function classMacros() return MACROS_BY_CLASS[playerClass()] or { METERS_MACRO } end
-- the warlock's retired macros (character macros, so only ever on the warlock)
local OLD_MACROS = { WARLOCK = { 'Bolt', 'PetGo', 'PetBack', 'PetMove', 'PetOne', 'PetTwo', 'Stone', 'Drink',
  'Pointer' } } -- Pointer (2026-11-26): OmaPointer's toggle; that add-on is removed, so its button is dead
local BANDAGES = { 14530, 14529, 8545, 8544, 6451, 6450, 3531, 3530, 2581, 1251 } -- Heavy Runecloth .. Linen, best first
local SOULSTONES = { 16896, 16895, 16893, 16892, 5232 }             -- Major .. Minor Soulstone, best first
local POTIONS = { 13446, 3928, 1710, 929, 858, 118 }               -- Major .. Minor Healing Potion, best first
local STONES = { 9421, 5510, 5509, 5511, 5512 }                    -- Major .. Minor Healthstone, best first
local WATERS = { 8766, 1645, 1708, 1205, 1179, 159 }                -- vendor water, best first
local FOODS  = { 8948, 4608, 4607, 4606, 4605, 4604 }               -- vendor mushrooms (Undercity), best first

-- { set, bar, button, kind, name or list (best first) }    kind: spell | macro | item | food | drink
local LAYOUTS = {}
LAYOUTS.WARLOCK = {
  -- SET 1 (v6, Joshua 2026-11-09: "the buttons I want to press most are the face buttons"). Eight most-pressed actions on
  -- trigger + face buttons (bare face buttons are Blizzard's: jump, back, interact, inspect). A whole pull = hold RT, X Y B A.
  -- v7 (Joshua 2026-11-10): "my right trigger is the main pull, the left trigger the other stuff": LT and RT swapped in every set.
  -- RT + face: the pull
  { 1, 'RT', X, 'spell', 'Corruption' },                                 -- v10 (Joshua 2026-11-12): Corruption X, Bane Y, wand B
  { 1, 'RT', Y, 'spell', 'Bane of Agony' },
  { 1, 'RT', B, 'spell', 'Shoot' },                                      -- wand
  { 1, 'RT', A, 'macro', 'PetFight' },                                   -- demon: defensive + attack my target (v9: was X)
  -- LT + face: keeping it going
  { 1, 'LT', X, 'spell', 'Life Tap' },
  { 1, 'LT', Y, 'spell', 'Drain Life' },
  { 1, 'LT', B, 'spell', 'Immolate' },
  { 1, 'LT', A, 'spell', 'Fear' },
  -- bare D-pad: support
  { 1, 'none', U, 'macro', 'PetHome' },                                  -- demon: passive + follow
  { 1, 'none', R, 'item', STONES },                                      -- Healthstone
  { 1, 'none', L, 'spell', 'Wrack' },                                    -- v11: capstone channel (was Health Funnel -> set 2)
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
  { 1, 'LT', D, 'spell', 'Amplify Curse' },                              -- v11: before Bane every few pulls (Shadow Ward dropped)
  -- LT + RT: out of the fight. v8 (Joshua 2026-11-10, "Is there a way to get them on page one?" / "Sounds good"):
  -- Hearthstone and the professions here; ONE demon button that follows your newest demon; every demon has its own
  -- button on set 2 for when you want a different one (rule 5 skips the set-2 copy of the one this button shows).
  { 1, 'LTRT', U, 'item', 6948 },                                          -- Hearthstone
  { 1, 'LTRT', R, 'spell', 'Curse of Tongues' },                         -- v12 (Joshua 2026-11-26, PvP ruleset): Tongues on set 1
  { 1, 'LTRT', L, 'item', SOULSTONES },                                   -- v15 (Joshua 2026-11-26): use the Soulstone (Create stays on set 2)
  -- v11 (Joshua 2026-11-26: "I'm just using succubus", Felhunter "pretty bad for leveling and dungeons rn"): the main
  -- demon button prefers the Succubus/Incubus and never jumps to the Felhunter.
  { 1, 'LTRT', D, 'spell', { 'Summon Succubus', 'Summon Incubus', 'Summon Sayaad', 'Summon Voidwalker', 'Summon Imp' } },
  { 1, 'LTRT', X, 'spell', 'Curse of Weakness' },                        -- v13 (Joshua 2026-11-26): for melee elites in dungeons
  { 1, 'LTRT', Y, 'item', BANDAGES },                                     -- v14 (Joshua 2026-11-26): bandages; no drink (Life Tap)
  { 1, 'LTRT', B, 'spell', { 'Demon Armor', 'Demon Skin' } },
  { 1, 'LTRT', A, 'spell', 'Create Healthstone' },
  -- SET 2 (LB+RB, D-pad right): travel and utility. Fills in as you level.
  { 2, 'LTRT', U, 'spell', 'Summon Imp' },                               -- the odd swap (v11: the only spare demon left)
  { 2, 'LTRT', R, 'spell', 'Health Funnel' },                            -- v11: was Voidwalker
  { 2, 'LTRT', L, 'spell', 'Drain Mana' },                               -- v11: was Felhunter
  { 2, 'LTRT', B, 'food', FOODS },                                        -- v13: food off set 1 (eaten between fights)
  { 2, 'none', U, 'spell', { 'Summon Dreadsteed', 'Summon Felsteed' } }, -- mount (40)
  { 2, 'none', R, 'spell', 'Create Soulstone' },                         -- 18
  { 2, 'none', L, 'spell', 'Ritual of Summoning' },                      -- 20
  { 2, 'none', D, 'spell', 'Unending Breath' },
  { 2, 'RT', U, 'spell', 'Drain Soul' },                                 -- soul shards (shares RT+up on set 1 until 41)
  { 2, 'RT', D, 'spell', 'Banish' },
  { 2, 'LTRT', D, 'spell', 'First Aid' },                                -- v14: Find Minerals dropped (Node Sight tracks)
  { 2, 'RT', B, 'spell', 'Curse of Recklessness' },
  { 2, 'RT', A, 'spell', 'Curse of Exhaustion' },
  { 2, 'LT', R, 'spell', { 'Subjugate Demon', 'Enslave Demon' } },       -- v11: Forever renamed it Subjugate Demon
  { 2, 'RT', R, 'spell', 'Eye of Kilrogg' },
  { 2, 'LT', L, 'spell', 'Detect Invisibility' },
  { 2, 'LT', D, 'spell', 'Sense Demons' },
  { 2, 'LT', X, 'spell', 'Rain of Fire' },
  { 2, 'LT', Y, 'spell', 'Hellfire' },
  { 2, 'LT', B, 'spell', 'Searing Pain' },
  { 2, 'LT', A, 'spell', 'Soul Fire' },
  { 2, 'LTRT', X, 'spell', 'Create Firestone' },                        -- 28
  { 2, 'LTRT', Y, 'spell', 'Create Spellstone' },                        -- 36
  { 2, 'LT', U, 'spell', 'Inferno' },                                    -- 50
  { 3, 'LTRT', U, 'spell', 'Ritual of Doom' },                           -- 60
  -- SET 3 otherwise free for talents and anything later.
}

-- Paladin (Human, Retribution levelling, 2026-11-26). Mirrors the warlock button for button by JOB, not by spell
-- (Joshua: "It should follow the warlocks design"): what the warlock pulls with, the paladin pulls with, and so on.
-- Lists upgrade in place (rule 2) and rule 5 keeps the lower spell off a second button until the upgrade arrives:
-- before 20, Seal of Righteousness sits on D-pad up and D-pad down stays empty; at 20 up becomes Seal of Command and
-- Righteousness drops to down (the Unsealed Wrath swap at 40). The same for Holy Light (LT X -> LT Y at 20).
-- Racials are listed for both paladin races, so the button is right whichever one he plays.
LAYOUTS.PALADIN = {
  -- RT + face: the pull                                                    (warlock: Corruption, Bane, wand, PetFight)
  { 1, 'RT', X, 'spell', 'Judgement' },                                    -- 4
  { 1, 'RT', Y, 'spell', 'Holy Strike' },                                  -- 6
  { 1, 'RT', B, 'spell', 'Consecration' },                                 -- 20
  { 1, 'RT', A, 'spell', 'Exorcism' },                                     -- 20
  -- LT + face: keeping it going                                            (warlock: Life Tap, Drain Life, Immolate, Fear)
  { 1, 'LT', X, 'spell', { 'Flash of Light', 'Holy Light' } },             -- Holy Light until 20
  { 1, 'LT', Y, 'spell', 'Holy Light' },                                   -- fills at 20
  { 1, 'LT', B, 'spell', 'Repentance' },                                   -- talent, 33
  { 1, 'LT', A, 'spell', 'Hammer of Justice' },                            -- 8: the paladin's Fear
  -- bare D-pad: support = the Seals                                        (warlock: PetHome, Healthstone, Funnel, Bolt)
  { 1, 'none', U, 'spell', { 'Seal of Command', 'Seal of Righteousness' } }, -- main seal: Command from 20
  { 1, 'none', R, 'item', POTIONS },                                       -- Healing Potion (the Healthstone button)
  { 1, 'none', L, 'spell', 'Seal of the Crusader' },                       -- 6
  { 1, 'none', D, 'spell', 'Seal of Righteousness' },                      -- fills at 20 (Unsealed Wrath swap)
  -- RT + D-pad                                                             (warlock: Siphon, curses, racial, Meters)
  { 1, 'RT', U, 'spell', 'Hammer of Wrath' },                              -- 44
  { 1, 'RT', L, 'spell', 'Holy Wrath' },                                   -- 50
  { 1, 'RT', D, 'spell', { 'Will to Survive', 'Will of the Forsaken' } },  -- stun break racial, Human or Undead
  { 1, 'RT', R, 'macro', 'Meters' },
  -- LT + D-pad: emergencies                                                (warlock: Cannibalize, Coil, Howl, Ward)
  { 1, 'LT', U, 'spell', { 'Cannibalize', 'Perception' } },                -- the other racial
  { 1, 'LT', R, 'spell', 'Lay on Hands' },                                 -- 10
  { 1, 'LT', L, 'spell', 'Blessing of Freedom' },                          -- 18
  { 1, 'LT', D, 'spell', { 'Divine Shield', 'Divine Protection' } },       -- Shield from 34
  -- LT + RT: out of the fight                                              (same slots as the warlock's)
  { 1, 'LTRT', U, 'item', 6948 },                                          -- Hearthstone
  { 1, 'LTRT', R, 'spell', 'Find Minerals' },
  { 1, 'LTRT', L, 'spell', 'Blacksmithing' },
  { 1, 'LTRT', D, 'spell', { 'Retribution Aura', 'Devotion Aura' } },      -- the "always out" button (warlock: demon)
  { 1, 'LTRT', X, 'food', FOODS },
  { 1, 'LTRT', Y, 'drink', WATERS },
  { 1, 'LTRT', B, 'spell', 'Blessing of Might' },                          -- self-buff (warlock: Demon Armor)
  { 1, 'LTRT', A, 'spell', 'Blessing of Kings' },                          -- 20 (warlock: Create Healthstone)
  -- SET 2 (LB+RB, D-pad right): travel and utility, same places as the warlock's.
  { 2, 'none', U, 'spell', { 'Summon Charger', 'Summon Warhorse' } },     -- mount (40), the Felsteed slot
  { 2, 'none', R, 'spell', 'Redemption' },                                 -- 12, the Soulstone slot
  { 2, 'none', L, 'spell', 'Divine Intervention' },                        -- 30, the Ritual of Summoning slot
  { 2, 'none', D, 'spell', 'Sense Undead' },
  { 2, 'LT', X, 'spell', 'Blessing of Wisdom' },                           -- 14
  { 2, 'LT', Y, 'spell', 'Blessing of Protection' },                       -- 10
  { 2, 'LT', B, 'spell', { 'Cleanse', 'Purify' } },                        -- Cleanse from 42
  { 2, 'LT', A, 'spell', 'Turn Undead' },                                  -- 24
  { 2, 'RT', L, 'spell', 'Concentration Aura' },                           -- 22
  { 2, 'RT', U, 'spell', 'Shadow Resistance Aura' },                       -- 28
  { 2, 'RT', R, 'spell', 'Frost Resistance Aura' },                        -- 32
  { 2, 'RT', D, 'spell', 'Fire Resistance Aura' },                         -- 36
  { 2, 'LTRT', X, 'spell', 'Righteous Fury' },                             -- 10, tanking only
  { 2, 'LTRT', Y, 'spell', 'Seal of Fury' },                               -- 10, tanking only
  { 2, 'LTRT', A, 'spell', 'Smelting' },                                   -- Mining
  { 2, 'LTRT', D, 'spell', 'First Aid' },                                  -- paladin v2 (Joshua 2026-11-26): the secondary
  { 2, 'LTRT', R, 'spell', 'Cooking' },                                    -- professions, First Aid in the warlock's spot
  { 2, 'LTRT', L, 'spell', 'Fishing' },
  { 2, 'LTRT', B, 'item', BANDAGES },                                      -- best bandage in the bags
  -- SET 3 free (a Holy or Protection dual spec at 40).
}
local function classLayout() return LAYOUTS[playerClass()] or {} end

OmaPadDB = OmaPadDB or {}
-- Per-character memory (rules 3 and 4): which buttons the add-on placed (mine), which are his (his), and the layout
-- and rules versions they were made under, plus this character's checks (waiting, blocked, check, sim, foodScan).
-- One-time move: the warlock's memory used to sit in the account-wide OmaPadDB. The first warlock to log in after
-- this change takes it over exactly as it was (same version numbers, so nothing is re-placed); it is then removed
-- from OmaPadDB so no other character can ever read it as its own. A fresh character starts with rulesV = 1, so the
-- old "adopt everything on set 1" step never runs on it: buttons he placed before the add-on stay untouched.
local PER_CHAR = { 'mine', 'his', 'rulesV', 'layoutV', 'waiting', 'blocked', 'check', 'sim', 'foodScan' }
local function charDB()
  OmaPadCharDB = OmaPadCharDB or {}
  local c = OmaPadCharDB
  if not c.started then
    local acct = OmaPadDB or {}
    if playerClass() == 'WARLOCK' and acct.mine and not acct.padMovedTo then
      for _, k in ipairs(PER_CHAR) do c[k] = acct[k]; acct[k] = nil end
      acct.padMovedTo = UnitName('player') or 'warlock'
    end
    c.mine = c.mine or {}; c.his = c.his or {}
    c.rulesV = c.rulesV or 1
    c.started = true
  end
  return c
end
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
-- the fixed vendor lists above still work. Every scan is written to OmaPadCharDB.foodScan for checking.
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
          local lines, hp, mana, fed, use = tipLines(bag, slot), 0, 0, false, nil
          for _, l in ipairs(lines or {}) do
            local low = l:lower()
            local a = low:match('restores ([%d,]+) health') or low:match('([%d,]+) health'); if a then hp = math.max(hp, tonumber((a:gsub(',', ''))) or 0) end
            local m = low:match('restores ([%d,]+) mana') or low:match('and ([%d,]+) mana'); if m then mana = math.max(mana, tonumber((m:gsub(',', ''))) or 0) end
            if low:find('well fed') then fed = true end
            if not use and (low:find('^use') or low:find('restore')) then use = l end
          end
          found[#found + 1] = { id = id, name = name or ('item ' .. id), minLevel = minLevel or 0, hp = hp, mana = mana, fed = fed,
                                usable = (minLevel or 0) <= lvl, tip = lines ~= nil, use = use }
        end
      end
    end
  end
  scan, scanAt = found, GetTime()
  local fs = {}; charDB().foodScan = fs
  for _, f in ipairs(found) do
    fs[#fs + 1] = ('%s (%d): health %d, mana %d%s, level %d%s%s'):format(f.name, f.id, f.hp, f.mana,
      f.fed and ', Well Fed' or '', f.minLevel, f.usable and '' or ' TOO HIGH', f.tip and '' or ', no tooltip')
      .. (f.use and (' | ' .. f.use:sub(1, 90)) or '')
  end
  return found
end
local function bestConsumable(kind)
  local best, bestScore
  for _, f in ipairs(scanBags()) do
    if f.usable then
      local amount = kind == 'food' and f.hp or f.mana
      -- 2026-11-26: Smoked Sagefish read as "health 0" on Forever. Well Fed food whose number can't be read still counts.
      if kind == 'food' and amount == 0 and f.fed and f.mana == 0 then amount = 1 end
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
  for _, n in ipairs(OLD_MACROS[playerClass()] or {}) do local i = GetMacroIndexByName(n); if i > 0 then DeleteMacro(i) end end
  for _, m in ipairs(classMacros()) do
    local i = GetMacroIndexByName(m[1])
    local body = m[2]; if type(body) == 'function' then body = body() end
    if body then
      if i == 0 then CreateMacro(m[1], m[3] or 'INV_MISC_QUESTIONMARK', body, true)
      elseif select(3, GetMacroInfo(i)) ~= body then EditMacro(i, m[1], m[3] or 'INV_MISC_QUESTIONMARK', body) end
    elseif i == 0 then CreateMacro(m[1], m[3] or 'INV_MISC_QUESTIONMARK', '/petattack', true) end   -- no demon yet: fixed on summon
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
  for _, e in ipairs(classLayout()) do
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
  local db, V = charDB(), VERSIONS[playerClass()] or 0
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

-- /ompad sim: replays levelling on a COPY of the bars (nothing on screen changes) and checks each step: no
-- duplicates, every spell in the class's "once" list on exactly one button, Joshua's own buttons untouched.
-- Results in OmaPadCharDB.sim. Warlock: 7-41, Imp, Succubus and the v11 additions once, Felhunter and Shadow Ward never. Paladin: 6-44, the seals and heals that move
-- between buttons (Righteousness, Command, Holy Light, Flash of Light) once each at every level.
local SIMS = {
  WARLOCK = {
    steps = {
      { 7,  { 'Shadow Bolt', 'Immolate', 'Corruption', 'Life Tap', 'Summon Imp', 'Demon Skin', 'Shoot', 'Will of the Forsaken', 'Cannibalize', 'Tailoring', 'Find Minerals' } },
      { 10, { 'Bane of Agony', 'Fear', 'Curse of Weakness', 'Drain Soul', 'Summon Voidwalker', 'Create Healthstone' } },
      { 12, { 'Health Funnel' }, 'his' },                                   -- here Joshua puts his own thing on LT+RT up
      { 20, { 'Drain Life', 'Summon Succubus', 'Ritual of Summoning', 'Create Soulstone', 'Unending Breath', 'Demon Armor', 'Amplify Curse' } },
      { 30, { 'Summon Felhunter', 'Banish', 'Subjugate Demon', 'Drain Mana', 'Curse of Tongues', 'Shadow Ward' } },
      { 41, { 'Siphon Life', 'Curse of the Elements', 'Summon Felsteed', 'Wrack' } },
    },
    -- Imp and Succubus are reachable exactly once; the Felhunter never gets a button (see mainDemon below)
    once = { 'Summon Imp', 'Summon Succubus', 'Curse of Weakness', 'Health Funnel', 'Wrack', 'Amplify Curse', 'Subjugate Demon' },
    never = { 'Summon Felhunter', 'Shadow Ward' },
    ownSlot = { ['Summon Imp'] = slotOf(2, 'LTRT', U) },
  },
  PALADIN = {
    steps = {
      { 6,  { 'Seal of Righteousness', 'Holy Light', 'Devotion Aura', 'Judgement', 'Blessing of Might', 'Holy Strike',
              'Seal of the Crusader', 'Divine Protection', 'Will to Survive', 'Perception', 'Blacksmithing', 'Find Minerals', 'Sense Undead' } },
      { 10, { 'Hammer of Justice', 'Purify', 'Lay on Hands', 'Blessing of Protection', 'Righteous Fury', 'Seal of Fury' } },
      { 12, { 'Redemption' }, 'his' },                                      -- here Joshua puts his own thing on LT+RT up
      { 20, { 'Blessing of Wisdom', 'Retribution Aura', 'Blessing of Freedom', 'Consecration', 'Exorcism', 'Flash of Light',
              'Blessing of Kings', 'Seal of Command' } },
      { 34, { 'Repentance', 'Divine Shield', 'Turn Undead', 'Divine Intervention', 'Concentration Aura' } },
      { 44, { 'Summon Warhorse', 'Cleanse', 'Hammer of Wrath' } },
    },
    once = { 'Seal of Righteousness', 'Seal of Command', 'Holy Light', 'Flash of Light' },
    never = {},
    ownSlot = {},
  },
}
local function simulate()
  local class = playerClass()
  local sim = SIMS[class]
  if not sim then say('no simulation for ' .. tostring(class)); return end
  local db, V = charDB(), VERSIONS[class] or 0
  local bars, st = {}, { mine = {}, his = {} }
  for s = PAD_FIRST, PAD_LAST do bars[s] = sigOf(s) end
  for s, v in pairs(db.mine or {}) do st.mine[s] = v end
  for s, v in pairs(db.his or {}) do st.his[s] = v end
  local board = { get = function(s) return bars[s] end, put = function(s, sig) bars[s] = sig; return true end, clear = function(s) bars[s] = nil end }
  if (db.layoutV or 0) ~= V then for s in pairs(st.mine) do bars[s] = nil; st.mine[s] = nil end end
  local known, report, ok = {}, {}, true
  for _, step in ipairs(sim.steps) do
    for _, n in ipairs(step[2]) do known[n] = true end
    if step[3] == 'his' then local s = slotOf(1, 'LTRT', U); bars[s] = 'spell:Joshua own choice'; st.mine[s] = nil; st.his[s] = bars[s] end
    fakeKnown = known
    local okRun, err = pcall(runRules, board, st)
    fakeKnown = nil
    if not okRun then ok = false; report[#report + 1] = ('lvl %d: ERROR %s'):format(step[1], tostring(err)); break end
    local dups = duplicates(board, st.mine)
    local once = {}
    for _, d in ipairs(sim.once) do if known[d] then local n = 0; for s = PAD_FIRST, PAD_LAST do if bars[s] == 'spell:' .. d then n = n + 1 end end
      local own = sim.ownSlot[d]
      local excused = n == 0 and own and st.his[own]
      once[#once + 1] = d:gsub('Summon ', '') .. '=' .. n .. (excused and ' (his button)' or ''); if n > 1 or (n == 0 and not excused) then ok = false end end end
    for _, d in ipairs(sim.never) do for s = PAD_FIRST, PAD_LAST do if bars[s] == 'spell:' .. d then
      ok = false; once[#once + 1] = d .. ' ON ' .. s end end end
    local hisOk = not st.his[slotOf(1, 'LTRT', U)] or bars[slotOf(1, 'LTRT', U)] == 'spell:Joshua own choice'
    if #dups > 0 or not hisOk then ok = false end
    report[#report + 1] = ('lvl %d: RT face %s/%s/%s/%s | LT face %s/%s/%s/%s | D-pad up=%s down=%s | RT up=%s | set2 RT up=%s | once %s | dups %s | his %s'):format(step[1],
      tostring(bars[slotOf(1, 'RT', X)]), tostring(bars[slotOf(1, 'RT', Y)]), tostring(bars[slotOf(1, 'RT', B)]), tostring(bars[slotOf(1, 'RT', A)]),
      tostring(bars[slotOf(1, 'LT', X)]), tostring(bars[slotOf(1, 'LT', Y)]), tostring(bars[slotOf(1, 'LT', B)]), tostring(bars[slotOf(1, 'LT', A)]),
      tostring(bars[slotOf(1, 'none', U)]), tostring(bars[slotOf(1, 'none', D)]),
      tostring(bars[slotOf(1, 'RT', U)]), tostring(bars[slotOf(2, 'RT', U)]), table.concat(once, ' '), #dups == 0 and 'none' or table.concat(dups, '; '),
      hisOk and 'kept' or 'TOUCHED')
  end
  db.sim = { at = date('%Y-%m-%d %H:%M:%S'), pass = ok, steps = report }
  say('simulation ' .. (ok and '|cff60ff60passed|r' or '|cffff6060FAILED|r') .. ' (' .. #report .. ' steps, details saved)')
end

-- RestedXP: this realm keeps changing its name, which gives RestedXP a blank profile. Keep Bujuju's own.
local function keepRxpProfile()
  if playerClass() ~= 'WARLOCK' then return end                -- Bujuju's profile only; never put it on another character
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
  local db = OmaPadDB
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
  if C_QuestLog and C_QuestLog.GetNumQuestWatches then OmaPadDB.tracked = C_QuestLog.GetNumQuestWatches() end   -- for checking
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
  m.TOTAL = math.floor(total); OmaPadDB.memory = m
end


-- one-off probe of RestedXP's window (its own frames only)
local function rxpProbe()
  local f = _G.RXPFrame; if not f then OmaPadDB.rxpProbe = 'no frame'; return end
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
  OmaPadDB.rxpProbe = out
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
  -- its full size: 1.2 (Joshua's pick, 2026-11-09) unless he makes it bigger. Not "whatever it was at login": RestedXP
  -- saves its scale on reload, so a shrunk size would otherwise become the new normal (2026-11-11).
  local s = f:GetScale(); fit.base = fit.base or math.max(s, OmaPadDB.rxpBase or 1.2)
  if s > fit.base * 1.001 then fit.base = s; OmaPadDB.rxpBase = s end            -- Joshua made it bigger: follow it
  local top = rxpTopPx(f); local bottom = f:GetBottom() and (1080 - f:GetBottom() * f:GetEffectiveScale() * 1080 / 768)
  if not top or not bottom or bottom - top < 10 then return end
  -- the bottom bar's place (2026-11-11, Joshua: "a reload broke it"): it had drifted ~275 px up from where it was put
  -- on 2026-11-09 (18 px above the chat tabs), so the steps had no room and climbed into the frames. Now it is pinned
  -- there every time: 18 screen px above the General chat tab's top, left edge kept.
  local u, e = UIParent:GetEffectiveScale(), f:GetEffectiveScale()
  local tab = _G.ChatFrame1Tab
  local wantB = tab and tab:GetTop() and (tab:GetTop() * tab:GetEffectiveScale() / u + 18 * 768 / 1080 / u)
  if wantB then
    local curB = f:GetBottom() * e / u
    if math.abs(curB - wantB) > 1 then
      local l = f:GetLeft() * e / u
      f:ClearAllPoints(); f:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', l / s, wantB / s)
      bottom = 1080 - wantB * u * 1080 / 768; top = rxpTopPx(f)
      if not top then return end
    end
  end
  local want = s
  if top < LIMIT then want = s * (bottom - LIMIT) / (bottom - top)
  elseif top > LIMIT + ROOM and s < fit.base then want = math.min(fit.base, s * (bottom - LIMIT - ROOM / 2) / (bottom - top)) end
  want = math.max(fit.base * MINF, math.min(fit.base, want))
  if math.abs(want - s) < .01 then return end
  -- keep the bottom-left corner where it is on screen while the scale changes
  e = f:GetEffectiveScale()
  local l, b = f:GetLeft() * e / u, f:GetBottom() * e / u
  f:SetScale(want); f:ClearAllPoints(); f:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', l / want, b / want)
  OmaPadDB.rxpFit = ('%s top %dpx -> scale %.2f (base %.2f)'):format(date('%H:%M:%S'), top, want, fit.base)
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
for _, e in ipairs({ 'PLAYER_ENTERING_WORLD', 'SPELLS_CHANGED', 'LEARNED_SPELL_IN_SKILL_LINE', 'LEARNED_SPELL_IN_TAB', 'BAG_UPDATE_DELAYED', 'PLAYER_REGEN_ENABLED', 'UNIT_PET', 'PET_BAR_UPDATE' }) do
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
    OmaPadDB.keys, OmaPadDB.keyCVars = out, cv
    say('pad keys saved; /reload to write them to the file (an add-on can\'t reload by itself).'); return
  end
  if m == 'mine' then local c = charDB(); c.his = {}; c.rulesV = 0 end
  apply()
end

-- Bags and map on LT/LB + View (sheet 16) removed 2026-11-10: Forever keeps View and Menu for itself in every
-- combination, so those bindings never fire. Bags and map stay in the Menu wheel.

-- ---------- Auction house: aux on top, bags out of the way (Joshua 2026-11-10: "Yes for everything else") ----------
-- WoW opens all bags with the auction house, and KroGamepadBags' window then covers aux. When aux opens, close the bag
-- window once (its own OnHide does all its cleanup; ns.Close is the same frame:Hide()). LB + RB + B still opens the bags
-- on purpose afterwards: we only close it in the first second after aux appears.
local ahWatch = CreateFrame('Frame')
local function bagsOffForAux()
  local aux, bags = _G.aux_frame, _G.KroGamepadBagsFrame
  if InCombatLockdown() or not (aux and aux:IsShown() and bags and bags:IsShown()) then return end
  bags:Hide()
end
ahWatch:RegisterEvent('AUCTION_HOUSE_SHOW')
ahWatch:SetScript('OnEvent', function()
  for _, t in ipairs({ 0.1, 0.4, 0.9 }) do C_Timer.After(t, bagsOffForAux) end
end)

-- ---------- Selling junk and repairing: Leatrix does both (Joshua 2026-11-10: "Yes for everything else") ----------
-- One seller only: Leatrix's "sell junk" on, RestedXP's off, so nothing sells twice; Leatrix "repair" on.
-- Done once (OmaPadDB.vendorV); RestedXP reads its setting at each vendor visit, Leatrix after the next reload.
-- After this the switches are his: changing them in Leatrix or RestedXP is never undone.
local VENDOR_V = 1
local vendorEv = CreateFrame('Frame'); vendorEv:RegisterEvent('PLAYER_LOGIN')
vendorEv:SetScript('OnEvent', function()
  OmaPadDB = OmaPadDB or {}
  if (OmaPadDB.vendorV or 0) >= VENDOR_V then return end
  local done = {}
  if type(LeaPlusDB) == 'table' then LeaPlusDB.AutoSellJunk = 'On'; LeaPlusDB.AutoRepairGear = 'On'; done[#done + 1] = 'Leatrix sells junk and repairs' end
  if type(RXPSettings) == 'table' and type(RXPSettings.profiles) == 'table' then
    for _, prof in pairs(RXPSettings.profiles) do if type(prof) == 'table' then prof.autoSellJunk = false end end
    done[#done + 1] = "RestedXP's junk selling off"
  end
  OmaPadDB.vendorV = VENDOR_V
  if #done > 0 then say(table.concat(done, '; ') .. ' (Leatrix needs one /reload)') end
end)

