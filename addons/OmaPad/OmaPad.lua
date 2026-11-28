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
local VERSIONS = { WARLOCK = 16, PALADIN = 4 } -- layout version per class: bump a class's number when its LAYOUT changes
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
-- Paladin v3 (Joshua 2026-11-26): Mastercraft's window and Polestar's guide on/off (for hanging out in town) on the two
-- set 1 buttons Blacksmithing and Find Minerals had (Find Minerals stays on once switched on; Mastercraft runs professions)
-- Mastercraft's window is mouse-only: the phone's trackpad (remote sheet 19) works it. (The game's own controller
-- pointer, SetGamePadCursorControl, did nothing in Forever: tried 2026-11-26.)
local MASTERCRAFT_MACRO = { 'Mastercraft', '/mc', 'Trade_BlackSmithing' }
-- all of Polestar (guide window, arrow, map pins) off and back on: its own hide switch (Joshua: the arrow stayed)
local POLESTAR_MACRO = { 'Polestar', '/run if Polestar and Polestar.ToggleHidden then Polestar.ToggleHidden() end', 'INV_Misc_Map_01' }
MACROS_BY_CLASS.PALADIN = { METERS_MACRO, MASTERCRAFT_MACRO, POLESTAR_MACRO }
local function classMacros() return MACROS_BY_CLASS[playerClass()] or { METERS_MACRO } end
-- the warlock's retired macros (character macros, so only ever on the warlock)
local OLD_MACROS = { WARLOCK = { 'Bolt', 'PetGo', 'PetBack', 'PetMove', 'PetOne', 'PetTwo', 'Stone', 'Drink',
  'Pointer' } } -- Pointer (2026-11-26): OmaPointer's toggle; that add-on is removed, so its button is dead
local BANDAGES = { 14530, 14529, 8545, 8544, 6451, 6450, 3531, 3530, 2581, 1251 } -- Heavy Runecloth .. Linen, best first
local SOULSTONES = { 16896, 16895, 16893, 16892, 5232 }             -- Major .. Minor Soulstone, best first
local POTIONS = { 13446, 3928, 1710, 929, 858, 118 }               -- Major .. Minor Healing Potion, best first
-- Throwables, best first (paladin v4, 2026-11-27): Engineering's bombs and grenades, and Forever's SAF-T ones anyone can
-- throw (their ids not known yet: add them when seen in game). Icy Veins: grenades are "incredibly potent" for paladins.
local BOMBS = { 10646, 15993, 16005, 10562, 18641, 10507, 4394, 4390, 4380, 6714, 4374, 4370, 4365, 4360, 4358 }
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
  { 1, 'LTRT', X, 'spell', 'Curse of Recklessness' },                    -- v16 (Joshua 2026-11-26): "I want recklessness not weakness"
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
  { 2, 'RT', B, 'spell', 'Curse of Weakness' },                          -- v16: swapped with set 1's Recklessness
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
  -- v4 (Joshua 2026-11-27, Undead Horde paladin, mockup omashu/pad/23): each trigger is one job. RT is the whole attack:
  -- seal and Judgement side by side ("I hate having to press up for the seal I'm using to judge off a right trigger"),
  -- the strikes, and Hammer of Justice, which starts the double-damage Judgement of Command. LT gets you out of trouble.
  -- The D-pad alone is upkeep. No seal he doesn't use on the attack section: Crusader (bosses only) goes to set 2.
  -- RT + face: the attack
  { 1, 'RT', X, 'spell', 'Judgement' },                                    -- 4: on cooldown, off the global cooldown
  { 1, 'RT', Y, 'spell', { 'Seal of Command', 'Seal of Righteousness' } }, -- main seal: Command from 22
  { 1, 'RT', B, 'spell', 'Holy Strike' },                                  -- 6
  { 1, 'RT', A, 'spell', 'Exorcism' },                                     -- 20: undead and demons, a 30 yd pull
  -- RT + D-pad: the rest of the attack
  { 1, 'RT', U, 'spell', 'Hammer of Justice' },                            -- 8: stun, then Judge Command for double
  { 1, 'RT', R, 'spell', 'Seal of Righteousness' },                        -- the second seal for Unsealed Wrath's swap (40); fills once Command is known
  { 1, 'RT', L, 'spell', 'Consecration' },                                 -- 20: 3+ mobs
  { 1, 'RT', D, 'spell', 'Hammer of Wrath' },                              -- 44: under 20% health
  -- LT + face: heal and protect
  { 1, 'LT', X, 'spell', { 'Flash of Light', 'Holy Light' } },             -- Holy Light until 20
  { 1, 'LT', Y, 'spell', 'Holy Light' },                                   -- fills at 20
  { 1, 'LT', B, 'spell', 'Repentance' },                                   -- talent, 33
  { 1, 'LT', A, 'spell', { 'Divine Shield', 'Divine Protection' } },       -- Protection from 6 (6 s immunity), Shield from 34
  -- LT + D-pad: escape
  { 1, 'LT', U, 'spell', { 'Cannibalize', 'Perception' } },                -- racial: 35% health and mana
  { 1, 'LT', R, 'spell', 'Lay on Hands' },                                 -- 10
  { 1, 'LT', L, 'spell', 'Blessing of Freedom' },                          -- 18
  { 1, 'LT', D, 'spell', { 'Will of the Forsaken', 'Will to Survive' } },  -- racial: after the fear lands
  -- bare D-pad: upkeep
  { 1, 'none', U, 'spell', { 'Blessing of Kings', 'Blessing of Might' } }, -- Kings from 20
  { 1, 'none', R, 'item', POTIONS },                                       -- best healing potion in the bags
  { 1, 'none', L, 'item', BANDAGES },                                      -- best bandage in the bags
  { 1, 'none', D, 'item', BOMBS },                                         -- best throwable in the bags
  -- LT + RT: out of the fight
  { 1, 'LTRT', U, 'item', 6948 },                                          -- Hearthstone
  { 1, 'LTRT', R, 'macro', 'Polestar' },                                   -- guide on/off
  { 1, 'LTRT', L, 'macro', 'Mastercraft' },                                -- professions window
  { 1, 'LTRT', X, 'food', FOODS },                                         -- +5% kill XP (Well Fed)
  { 1, 'LTRT', Y, 'drink', WATERS },
  { 1, 'LTRT', B, 'spell', { 'Retribution Aura', 'Devotion Aura' } },      -- the aura
  -- SET 2 (LB+RB, D-pad right): travel and utility, same places as before.
  { 2, 'none', U, 'spell', { 'Summon Charger', 'Summon Warhorse' } },     -- mount (40)
  { 2, 'none', R, 'spell', 'Redemption' },                                 -- 12
  { 2, 'none', L, 'spell', 'Divine Intervention' },                        -- 30
  { 2, 'none', D, 'spell', 'Sense Undead' },
  { 2, 'LT', X, 'spell', 'Blessing of Wisdom' },                           -- 14
  { 2, 'LT', Y, 'spell', 'Blessing of Protection' },                       -- 10
  { 2, 'LT', B, 'spell', { 'Cleanse', 'Purify' } },                        -- Cleanse from 42
  { 2, 'LT', A, 'spell', 'Turn Undead' },                                  -- 24
  { 2, 'RT', L, 'spell', 'Concentration Aura' },                           -- 22
  { 2, 'RT', U, 'spell', 'Shadow Resistance Aura' },                       -- 28
  { 2, 'RT', R, 'spell', 'Frost Resistance Aura' },                        -- 32
  { 2, 'RT', D, 'spell', 'Fire Resistance Aura' },                         -- 36
  { 2, 'LTRT', X, 'spell', 'Righteous Fury' },                             -- tanking only
  { 2, 'LTRT', Y, 'spell', 'Seal of Fury' },                               -- tanking only
  { 2, 'LTRT', B, 'spell', 'Seal of the Crusader' },                       -- bosses and elites only (sources disagree on normal mobs)
  { 2, 'LTRT', A, 'spell', 'Find Herbs' },                                 -- Herbalism (was Smelting: Bujuju mines)
  { 2, 'LTRT', D, 'spell', 'First Aid' },
  { 2, 'LTRT', R, 'spell', 'Cooking' },
  { 2, 'LTRT', L, 'spell', 'Fishing' },
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
    -- 2026-11-26 (Bunji, level 1): a brand-new character comes with buttons the game put on the pad bars itself
    -- (Will to Survive, the starting food). Taken as "his", they blocked the main seal button and doubled two spells.
    -- A new character (level 1 or 2) hands them to the add-on once, so the next pass lays the bars out clean.
    if not c.layoutV and (UnitLevel('player') or 99) <= 2 then c.fresh = true end
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

-- ---------- A spell lands on the pad (sheet omashu/pad/26 v2, Joshua 2026-11-27) ----------
-- A NEW spell the add-on puts on a button: on that button the old face drops away (140 ms), the icon springs in
-- (420 ms, overshoot), a gold ring opens and fades (600 ms), six gold sparks fly out and a warm glow breathes, then
-- stops. A RANK UPGRADE: the icon stays; one gold light sweeps across it (520 ms) and a soft glow comes and goes
-- (900 ms), no sound. Several at once play one at a time: bare pad, RT, LT, LT+RT, then set 2 (and 3). A layer behind
-- a trigger is shown by lighting that trigger and laying that layer's icons over the pad buttons for the moment.
-- WHEN (Joshua: "This is paramount"): spells learned at a trainer play only once the trainer window closes; spells
-- gained any other way (quest reward, tome) right after he gets them; never in combat (they wait for it to end).
-- Any button press, moving or a fight starting ends it at once. Only plain frames of our own: no Blizzard frame is
-- touched (their places are only read), nothing secure, nothing in combat.
local Land = { queue = {}, log = {}, gen = 0, running = false, trainer = false }
_G.OmaPadLand = Land                                       -- for /run checks and the offline tests
local GOLD, EMPTY = { 1, 0.83, 0.42 }, { 0.03, 0.03, 0.03 }   -- #ffd36b, the dark empty face
local TEX = {                                             -- first one that loads wins (check in game: see landCheck)
  ring  = { 'Interface\\Cooldown\\ping4', 'Interface\\Buttons\\UI-ActionButton-Border' },
  spark = { 'Interface\\Cooldown\\star4', 'Interface\\Buttons\\UI-ActionButton-Border' },
  glow  = { 'Interface\\SpellActivationOverlay\\IconAlert', 'Interface\\Buttons\\UI-ActionButton-Border' },
  white = { 'Interface\\Buttons\\WHITE8X8' },
}
local ROUND_MASK = 'Interface\\CharacterFrame\\TempPortraitAlphaMask'
local BAR_ORDER = { none = 0, RT = 1, LT = 2, LTRT = 3 }  -- Joshua's order: bare pad, RT, LT, LT+RT (then the next set)
local SCREEN_X = { [0] = 0, [1] = 1, [3] = 1, [2] = 2, [4] = 3, [5] = 4, [7] = 4, [6] = 5 }   -- left to right on the TV
local function layerOf(slot)                              -- slot -> set, bar, button (0-7: D-pad L U R D, then X Y B A)
  local off = (slot - PAD_FIRST) % 28
  local bar = off < 4 and 'none' or off < 12 and 'LT' or off < 20 and 'RT' or 'LTRT'
  return math.floor((slot - PAD_FIRST) / 28) + 1, bar, off < 4 and off or (off - 4) % 8
end
local function layerKey(slot) local set, bar = layerOf(slot); return set * 10 + BAR_ORDER[bar] end
local function inCombat() return InCombatLockdown() or (UnitAffectingCombat and UnitAffectingCombat('player')) or false end
local function note(k, v) if type(OmaPadDB) == 'table' then OmaPadDB.landCheck = OmaPadDB.landCheck or {}; OmaPadDB.landCheck[k] = v end end

-- the chime: new spells only, once each, on the SFX channel so it sits under the music. One setting, picked by ear on
-- the TV (/omapad sound <id>); the default is the new-recipe chime if this client has it, else quest complete.
local function landSound()
  local k = type(OmaPadDB) == 'table' and tonumber(OmaPadDB.landSound)
  if k then return k end
  local S = rawget(_G, 'SOUNDKIT') or {}
  return S.UI_PROFESSIONS_NEW_RECIPE_LEARNED_TOAST or S.IG_QUEST_LIST_COMPLETE
end
local function chime() local k = landSound(); if k and PlaySound then pcall(PlaySound, k, 'SFX') end end

-- The order to play a batch in: layer by layer; in each, the new spells one at a time left to right, then all of the
-- layer's upgrades together.
function Land.plan(items)
  local layers, keys = {}, {}
  for _, it in ipairs(items) do
    local k = layerKey(it.slot)
    if not layers[k] then layers[k] = { new = {}, up = {} }; keys[#keys + 1] = k end
    table.insert(layers[k][it.kind], it.slot)
  end
  table.sort(keys)
  local function lr(a, b)
    local _, _, ba = layerOf(a); local _, _, bb = layerOf(b)
    if SCREEN_X[ba] ~= SCREEN_X[bb] then return SCREEN_X[ba] < SCREEN_X[bb] end
    return ba < bb
  end
  local steps = {}
  for _, k in ipairs(keys) do
    table.sort(layers[k].new, lr); table.sort(layers[k].up, lr)
    for _, s in ipairs(layers[k].new) do steps[#steps + 1] = { layer = k, kind = 'new', slot = s } end
    if #layers[k].up > 0 then steps[#steps + 1] = { layer = k, kind = 'up', slots = layers[k].up } end
  end
  return steps
end

-- ----- drawing (plain frames on UIParent, placed over the game's pad buttons by reading where those are) -----
local R
local function setTex(t, list) for _, p in ipairs(list) do local ok, r = pcall(t.SetTexture, t, p); if ok and r ~= false then return p end end end
local function anim(g, kind, order, ms, smooth)
  local a = g:CreateAnimation(kind); a:SetOrder(order); a:SetDuration(ms / 1000); if smooth then a:SetSmoothing(smooth) end; return a
end
local function fade(g, from, to, ms, order, smooth)
  local a = anim(g, 'Alpha', order or 1, ms, smooth); a:SetFromAlpha(from); a:SetToAlpha(to); return a
end
local function grow(g, from, to, ms, order, smooth)
  local a = anim(g, 'Scale', order or 1, ms, smooth)
  if a.SetScaleFrom then a:SetScaleFrom(from, from); a:SetScaleTo(to, to)
  elseif a.SetFromScale then a:SetFromScale(from, from); a:SetToScale(to, to)
  else a:SetScale(to / from, to / from) end
  return a
end
local function group(obj, final)
  local g = obj:CreateAnimationGroup()
  if g.SetToFinalAlpha then g:SetToFinalAlpha(true) end
  if final then g:SetScript('OnFinished', function() obj:SetAlpha(final) end) end
  return g
end
local function newFace(round)
  local f = CreateFrame('Frame', nil, UIParent)
  f:SetFrameStrata('DIALOG'); f:EnableMouse(false); f:Hide()
  local function tex(layer, sub, list, blend)
    local t = f:CreateTexture(nil, layer, nil, sub); setTex(t, list); if blend then t:SetBlendMode(blend) end; t:SetAlpha(0); return t
  end
  f.halo = tex('BACKGROUND', 0, TEX.glow, 'ADD'); f.halo:SetVertexColor(unpack(GOLD))
  f.back = tex('ARTWORK', 0, TEX.white)                    -- the layer's icon, or an empty face
  f.old = tex('ARTWORK', 1, TEX.white); f.old:SetVertexColor(unpack(EMPTY))
  f.icon = tex('ARTWORK', 2, TEX.white)
  f.ring = tex('OVERLAY', 1, TEX.ring, 'ADD'); f.ring:SetVertexColor(unpack(GOLD))
  f.glow = tex('OVERLAY', 2, TEX.glow, 'ADD'); f.glow:SetVertexColor(unpack(GOLD))
  if round and f.CreateMaskTexture then
    pcall(function()
      local m = f:CreateMaskTexture(); m:SetTexture(ROUND_MASK, 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE'); m:SetAllPoints(f)
      for _, t in ipairs({ f.back, f.old, f.icon }) do t:AddMaskTexture(m) end
    end)
  end
  f.sparks = {}
  for i = 1, 6 do local s = tex('OVERLAY', 3, TEX.spark, 'ADD'); s:SetVertexColor(unpack(GOLD)); f.sparks[i] = { t = s } end
  -- the upgrade's sweep: a soft gold band moved across the icon, clipped to the button
  local clip = CreateFrame('Frame', nil, f); clip:SetAllPoints(f); if clip.SetClipsChildren then pcall(clip.SetClipsChildren, clip, true) end
  f.band = clip:CreateTexture(nil, 'OVERLAY'); setTex(f.band, TEX.white); f.band:SetBlendMode('ADD'); f.band:SetAlpha(0)
  f.band:SetVertexColor(1, 0.95, 0.75)
  if f.band.SetRotation then pcall(f.band.SetRotation, f.band, math.rad(-18)) end
  -- the animations (numbers from the sheet's CSS; cubic-bezier(.32,.72,0,1) = OUT)
  f.aOld = group(f.old, 0); fade(f.aOld, 1, 0, 140, 1, 'IN'); grow(f.aOld, 1, 0.8, 140, 1, 'IN')
  f.aPop = group(f.icon, 1); fade(f.aPop, 0, 1, 200, 1, 'OUT'); grow(f.aPop, 0.6, 1.1, 260, 1, 'OUT'); grow(f.aPop, 1.1, 1, 160, 2, 'IN_OUT')
  f.aRing = group(f.ring, 0); fade(f.aRing, 0.95, 0, 600, 1, 'OUT'); grow(f.aRing, 0.9, 1.5, 600, 1, 'OUT')
  f.aHaloLong = group(f.halo, 0)                           -- breathes twice (2.8 s each) and stops
  for i = 0, 1 do fade(f.aHaloLong, 0, 1, 1400, i * 2 + 1, 'IN_OUT'); fade(f.aHaloLong, 1, 0, 1400, i * 2 + 2, 'IN_OUT') end
  f.aHaloShort = group(f.halo, 0); fade(f.aHaloShort, 0, 1, 700, 1, 'IN_OUT'); fade(f.aHaloShort, 1, 0, 700, 2, 'IN_OUT')
  for _, s in ipairs(f.sparks) do
    s.g = group(s.t, 0); fade(s.g, 1, 0, 520, 1, 'OUT'); grow(s.g, 1.4, 0.6, 520, 1, 'OUT')
    s.move = anim(s.g, 'Translation', 1, 520, 'OUT')
  end
  f.aBand = group(f.band, 0); f.bandMove = anim(f.aBand, 'Translation', 1, 520, 'OUT')
  f.aGlow = group(f.glow, 0); fade(f.aGlow, 0, 1, 315, 1, 'IN_OUT'); fade(f.aGlow, 1, 0, 585, 2, 'IN_OUT')
  f.aIn = f:CreateAnimationGroup(); fade(f.aIn, 0, 1, 220, 1, 'OUT')
  return f
end
local function placeFace(f, p)
  local s = p.size
  f:SetSize(s, s); f:ClearAllPoints(); f:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', p.x, p.y)
  for _, t in ipairs({ f.back, f.old, f.icon }) do t:ClearAllPoints(); t:SetAllPoints(f) end
  f.ring:ClearAllPoints(); f.ring:SetPoint('CENTER', f); f.ring:SetSize(s + 8, s + 8)
  f.halo:ClearAllPoints(); f.halo:SetPoint('CENTER', f); f.halo:SetSize(s * 1.7, s * 1.7)
  f.glow:ClearAllPoints(); f.glow:SetPoint('CENTER', f); f.glow:SetSize(s * 1.35, s * 1.35)
  for i, sp in ipairs(f.sparks) do
    local a, d = (i - 1) / 6 * math.pi * 2 + 0.3, s * (0.6 + (i % 2) * 0.13)
    sp.t:ClearAllPoints(); sp.t:SetPoint('CENTER', f); sp.t:SetSize(s * 0.22, s * 0.22)
    sp.move:SetOffset(math.cos(a) * d, math.sin(a) * d)
  end
  f.band:ClearAllPoints(); f.band:SetSize(s * 0.45, s * 1.4); f.band:SetPoint('CENTER', f, 'LEFT', -s * 0.3, 0)
  f.bandMove:SetOffset(s * 1.6, 0)
end
local function actionOf(b)
  local a = b.action
  if type(a) ~= 'number' and b.GetAttribute then local ok, v = pcall(b.GetAttribute, b, 'action'); a = ok and tonumber(v) or nil end
  if type(a) ~= 'number' and b.CalculateAction then local ok, v = pcall(b.CalculateAction, b); a = ok and tonumber(v) or nil end
  return type(a) == 'number' and a or nil
end
-- where the game's pad buttons are: every action button whose action is a pad slot, by button (shown ones first)
local function locate()
  local found, ui = {}, (UIParent and UIParent:GetEffectiveScale() or 1)
  if not EnumerateFrames then return found end
  local f, n = EnumerateFrames(), 0
  while f and n < 30000 do
    n = n + 1
    local ok, a = pcall(actionOf, f)
    if ok and a and a >= PAD_FIRST and a <= PAD_LAST then
      local okc, x, y = pcall(f.GetCenter, f)
      if okc and x and y then
        local _, _, btn = layerOf(a)
        local vis = (f.IsVisible and f:IsVisible()) and 1 or 0
        if not found[btn] or vis > found[btn].vis then
          local e = f:GetEffectiveScale() or 1
          found[btn] = { x = x * e / ui, y = y * e / ui, size = (f:GetWidth() or 40) * e / ui, vis = vis, name = f.GetName and f:GetName() or '?' }
        end
      end
    end
    f = EnumerateFrames(f)
  end
  return found
end
local function makeR()
  local r = { faces = {}, dots = {} }
  for b = 0, 7 do r.faces[b] = newFace(b >= 4) end        -- D-pad buttons are square, face buttons round
  local function lamp()
    local f = CreateFrame('Frame', nil, UIParent); f:SetFrameStrata('DIALOG'); f:EnableMouse(false); f:Hide()
    f.t = f:CreateTexture(nil, 'OVERLAY'); setTex(f.t, TEX.glow); f.t:SetBlendMode('ADD'); f.t:SetVertexColor(unpack(GOLD)); f.t:SetAllPoints(f)
    f.g = f:CreateAnimationGroup(); if f.g.SetLooping then f.g:SetLooping('BOUNCE') end; fade(f.g, 0.55, 1, 700, 1, 'IN_OUT')
    return f
  end
  r.lamps = { LT = lamp(), RT = lamp(), set = lamp() }
  return r
end
local function dot(i)
  local d = R.dots[i]
  if not d then
    d = CreateFrame('Frame', nil, UIParent); d:SetFrameStrata('DIALOG'); d:EnableMouse(false)
    d.t = d:CreateTexture(nil, 'OVERLAY'); setTex(d.t, TEX.white); d.t:SetAllPoints(d)
    if d.CreateMaskTexture then pcall(function() local m = d:CreateMaskTexture(); m:SetTexture(ROUND_MASK, 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE'); m:SetAllPoints(d); d.t:AddMaskTexture(m) end) end
    R.dots[i] = d
  end
  return d
end
local Draw = {}
function Draw.start(nSteps)
  if not R then R = makeR() end
  R.at = locate()
  local minX, maxX, top, bottom, size, n = nil, nil, nil, nil, 40, 0
  for _, p in pairs(R.at) do
    n = n + 1; size = p.size
    minX = math.min(minX or p.x, p.x); maxX = math.max(maxX or p.x, p.x)
    top = math.max(top or p.y, p.y); bottom = math.min(bottom or p.y, p.y)
  end
  local names = {}; for b, p in pairs(R.at) do names[#names + 1] = b .. '=' .. tostring(p.name) end; table.sort(names)
  note('buttons', table.concat(names, ' ')); note('found', n)
  R.box = n > 0 and { minX = minX, maxX = maxX, top = top, bottom = bottom, size = size } or nil
  if not R.box then return end
  local s, B = size, R.box
  local function put(f, x, y, w, h) f:SetSize(w, h); f:ClearAllPoints(); f:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', x, y) end
  put(R.lamps.LT, B.minX - s * 1.1, B.top + s * 0.7, s * 1.15, s * 0.85)   -- first guesses from the sheet: tune on the TV
  put(R.lamps.RT, B.maxX + s * 1.1, B.top + s * 0.7, s * 1.15, s * 0.85)
  put(R.lamps.set, (B.minX + B.maxX) / 2, B.top + s * 0.9, s * 1.15, s * 0.85)
  for i = 1, nSteps do local d = dot(i); put(d, (B.minX + B.maxX) / 2 + (i - (nSteps + 1) / 2) * s * 0.2, B.bottom - s * 0.95, s * 0.12, s * 0.12) end
  for i = nSteps + 1, #R.dots do R.dots[i]:Hide() end
end
function Draw.dots(n, cur)
  if not R or not R.box then return end
  for i = 1, n do
    local d = R.dots[i]; d:Show()
    if i < cur then d.t:SetVertexColor(0.54, 0.42, 0.16) elseif i == cur then d.t:SetVertexColor(unpack(GOLD)) else d.t:SetVertexColor(0.23, 0.16, 0.08) end
  end
end
local function faceIcon(f, slot)
  local icon = GetActionTexture and GetActionTexture(slot)
  if icon then f.back:SetTexture(icon); f.back:SetVertexColor(1, 1, 1) else setTex(f.back, TEX.white); f.back:SetVertexColor(unpack(EMPTY)) end
end
-- show a layer: the bare pad needs nothing; any other layer lights its trigger (or set switch) and lays its icons on
-- the pad buttons. New spells not yet landed show an empty face until their turn.
function Draw.layer(key, pending)
  if not R or not R.box then return end
  for _, l in pairs(R.lamps) do l.g:Stop(); l:Hide() end
  for b, f in pairs(R.faces) do f.aIn:Stop(); f:Hide(); f.back:SetAlpha(0); f.icon:SetAlpha(0) end
  if not key or key == 10 then return end
  local set, bar = math.floor(key / 10), nil
  for name, o in pairs(BAR_ORDER) do if o == key % 10 then bar = name end end
  local lamps = bar == 'LT' and { 'LT' } or bar == 'RT' and { 'RT' } or bar == 'LTRT' and { 'LT', 'RT' } or {}
  if set ~= 1 then lamps[#lamps + 1] = 'set' end
  for _, n in ipairs(lamps) do R.lamps[n]:Show(); R.lamps[n].g:Play() end
  for b = 0, bar == 'none' and 3 or 7 do
    local f, p = R.faces[b], R.at[b]
    if p then
      local slot = 181 + (set - 1) * 28 + ({ none = 0, LT = 4, RT = 12, LTRT = 20 })[bar] + b
      placeFace(f, p)
      if pending[slot] then setTex(f.back, TEX.white); f.back:SetVertexColor(unpack(EMPTY)) else faceIcon(f, slot) end
      f.back:SetAlpha(1); f:Show(); f.aIn:Play()
    end
  end
end
local function faceFor(slot)
  if not R or not R.box then return nil end
  local _, _, b = layerOf(slot); local f, p = R.faces[b], R.at[b]
  if not p then return nil end
  if not f:IsShown() then placeFace(f, p); f.back:SetAlpha(0); f:SetAlpha(1); f:Show() end
  return f
end
function Draw.pop(slot, alone, at)
  local f = faceFor(slot); if not f then return end
  f.icon:SetTexture((GetActionTexture and GetActionTexture(slot)) or 'Interface\\Icons\\INV_Misc_QuestionMark')
  f.icon:SetAlpha(0); f.old:SetAlpha(1); f.aOld:Play()                       -- 0: the old face drops away
  at(120, function() f.aPop:Play() end)                                     -- 120: the icon springs in
  at(160, function() f.aRing:Play() end)                                    -- 160: the gold ring
  at(220, function() for _, s in ipairs(f.sparks) do s.g:Play() end end)    -- 220: the sparks
  if alone then at(600, function() f.aHaloLong:Play() end) else at(300, function() f.aHaloShort:Play() end) end
end
function Draw.glint(slot)
  local f = faceFor(slot); if not f then return end
  f.aBand:Stop(); f.aGlow:Stop(); f.aBand:Play(); f.aGlow:Play()
end
function Draw.clear()
  if not R then return end
  for _, f in pairs(R.faces) do
    for _, g in ipairs({ f.aOld, f.aPop, f.aRing, f.aHaloLong, f.aHaloShort, f.aBand, f.aGlow, f.aIn }) do g:Stop() end
    for _, s in ipairs(f.sparks) do s.g:Stop(); s.t:SetAlpha(0) end
    for _, t in ipairs({ f.back, f.old, f.icon, f.ring, f.halo, f.glow, f.band }) do t:SetAlpha(0) end
    f:Hide()
  end
  for _, l in pairs(R.lamps) do l.g:Stop(); l:Hide() end
  for _, d in ipairs(R.dots) do d:Hide() end
end
local function draw(name, ...)                              -- drawing never stops the add-on; the first error is kept
  local ok, err = pcall(Draw[name], ...)
  if not ok then note('err', name .. ': ' .. tostring(err)) end
end

-- ----- playing a batch -----
function Land.stop(why)
  if not Land.running then return end
  Land.gen = Land.gen + 1; Land.running = false; Land.queue = {}
  Land.log[#Land.log + 1] = 'stop:' .. tostring(why)
  draw('clear')
end
function Land.run(items)
  local steps = Land.plan(items)
  if #steps == 0 then return end
  Land.gen = Land.gen + 1; Land.running = true
  local gen = Land.gen
  local function at(ms, fn) C_Timer.After(ms / 1000, function() if Land.gen == gen then fn() end end) end
  local alone = #steps == 1 and steps[1].kind == 'new'
  local pending = {}; for _, s in ipairs(steps) do if s.kind == 'new' then pending[s.slot] = true end end
  Land.log[#Land.log + 1] = 'start'
  draw('start', #steps)
  local t, cur = 0, nil
  for i, s in ipairs(steps) do
    if s.layer ~= cur then
      local k = s.layer
      at(t, function() Land.log[#Land.log + 1] = 'layer:' .. k; draw('layer', k, pending) end)
      t = t + (k == 10 and 250 or 450); cur = k
    end
    at(t, function() draw('dots', #steps, i) end)
    if s.kind == 'new' then
      at(t, function() pending[s.slot] = nil; Land.log[#Land.log + 1] = 'new:' .. s.slot; chime(); draw('pop', s.slot, alone, at) end)
      t = t + (alone and 6200 or 1200)
    else
      for j, slot in ipairs(s.slots) do
        at(t + (j - 1) * 80, function() Land.log[#Land.log + 1] = 'up:' .. slot; draw('glint', slot) end)
      end
      t = t + 900 + (#s.slots - 1) * 80
    end
  end
  at(t, function() draw('layer', nil, pending); draw('dots', #steps, #steps + 1) end)
  at(t + 300, function()
    draw('clear'); Land.running = false; Land.log[#Land.log + 1] = 'end'
    Land.kick()
  end)
end
-- play what's waiting, if now is allowed: not while a trainer is open, not in combat, not on top of another batch
function Land.kick()
  if Land.running or #Land.queue == 0 or Land.trainer then return end
  if inCombat() then Land.afterCombat = true; return end
  local items = Land.queue; Land.queue = {}
  Land.run(items)
end
function Land.add(items)
  if #items == 0 then return end
  local at = {}; for i, it in ipairs(Land.queue) do at[it.slot] = i end
  for _, it in ipairs(items) do
    local i = at[it.slot]
    if not i then Land.queue[#Land.queue + 1] = it; at[it.slot] = #Land.queue
    elseif it.kind == 'new' then Land.queue[i] = it end                          -- a new spell beats an upgrade
  end
  C_Timer.After(0.2, Land.kick)                                                  -- "right after I acquire them"
end

-- What changed: a pad button the add-on just filled with a spell he didn't know at the last look = new; a spell on a
-- pad button whose rank went up (its spell id changed, or the game said it was learned) = upgrade. The first look of
-- a session only takes notes, so logging in, a layout change or a fresh character never set anything off.
local landSeen, landLearned = nil, {}
local function rankOf(n) return knownId(n) or false end
function Land.learned(id) local n = id and spellName(id); if n then landLearned[n] = true end end
function Land.detect(before, mine)
  local now, names = {}, {}
  for s = PAD_FIRST, PAD_LAST do now[s] = sigOf(s) end
  for _, e in ipairs(classLayout()) do
    if e[4] == 'spell' then for _, n in ipairs(type(e[5]) == 'table' and e[5] or { e[5] }) do names[n] = true end end
  end
  for _, sig in pairs(now) do local n = sig:match('^spell:(.*)$'); if n then names[n] = true end end
  if landSeen then
    local found = {}
    for s = PAD_FIRST, PAD_LAST do
      local sig = now[s]; local n = sig and sig:match('^spell:(.*)$')
      if n then
        if sig ~= before[s] and mine[s] == sig and not landSeen[n] then
          found[#found + 1] = { kind = 'new', slot = s }
        elseif sig == before[s] and landSeen[n] and (landSeen[n] ~= rankOf(n) or landLearned[n]) then
          found[#found + 1] = { kind = 'up', slot = s }
        end
      end
    end
    Land.add(found)
  end
  landSeen = {}; for n in pairs(names) do landSeen[n] = rankOf(n) end
  landLearned = {}
end
-- /omapad landtest: one sample new spell (the first filled bare D-pad button) and one upgrade (the first filled RT
-- button) on the pad as it is now, to look at it and pick the sound on the TV
function Land.test()
  if inCombat() then say('landtest: not in a fight'); return end
  local new, up = 182, nil
  for s = 181, 184 do if HasAction(s) then new = s; break end end
  for s = 193, 200 do if HasAction(s) then up = s; break end end
  if not up then for s = 185, 192 do if HasAction(s) then up = s; break end end end
  Land.stop('test'); Land.queue = {}
  local items = { { kind = 'new', slot = new } }
  if up then items[2] = { kind = 'up', slot = up } end
  Land.run(items)
end

local function apply()
  if InCombatLockdown() then return end
  if GetCursorInfo and GetCursorInfo() then C_Timer.After(2, apply); return end   -- he is dragging something: not now
  pcall(makeMacros)                                                               -- a full macro list never stops the pad
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
  -- A brand-new character (charDB's `fresh`): everything on the pad bars is the game's own start, so it is the add-on's
  -- to lay out: adopt it and force the version step below to clear and re-place.
  if db.fresh then
    for s = PAD_FIRST, PAD_LAST do local sig = sigOf(s); if sig then db.mine[s] = sig; db.his[s] = nil end end
    db.layoutV = nil
    db.fresh = nil
  end
  -- New layout version: take the add-on's own buttons off; his stay where they are.
  local moved = 0
  if db.layoutV ~= V then
    for s in pairs(db.mine) do if HasAction(s) then PickupAction(s); ClearCursor(); moved = moved + 1 end; db.mine[s] = nil end
    db.layoutV = V
  end
  local before = {}; for s = PAD_FIRST, PAD_LAST do before[s] = sigOf(s) end      -- for the landing (sheet 26)
  local placed, upgraded, cleared, waiting, blocked = runRules(realBoard, db)
  do local okL, errL = pcall(Land.detect, before, db.mine); if not okL then note('err', 'detect: ' .. tostring(errL)) end end
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
-- The breath / fatigue bar sat on Polestar's arrow text at the top (Joshua 2026-11-26, swimming): moved under it.
-- Polestar's arrow, distance and step line end about 190 px down (135 units at 1080p); the bar now starts at 150.
local function moveBreathBar()
  local f = rawget(_G, 'MirrorTimerContainer') or rawget(_G, 'MirrorTimer1')
  if not f or InCombatLockdown() then return end
  f:ClearAllPoints(); f:SetPoint('TOP', UIParent, 'TOP', 0, -150)
  -- quest progress ("Half-Eaten Fish: 6/7") and the game's red errors: under the breath bar too (was TOP -122)
  local e = rawget(_G, 'UIErrorsFrame')
  if e then e:ClearAllPoints(); e:SetPoint('TOP', UIParent, 'TOP', 0, -190) end
end
-- The auction house layout (Joshua 2026-11-26, sheet omashu/remote/20): while the auction house is open, the bags
-- (KroGamepadBags) and ImprovedForever's auction house are one row at 85%, same top, just under the player frame,
-- bags left; the item tooltip and its "Equipped" compare stack at 70% in the column under the minimap, growing up from
-- just above the XP bar. Everything goes back the way it was when the auction house closes. TV pixels / 1.40625 =
-- UI units (1080p, UI scale 1); an offset is in the frame's own scaled units, so it is divided by the scale.
local PX = 1080 / 768
-- measured on the TV 2026-11-26: the bag window draws 77 px above its anchor and is 503 px wide at 85%; the auction
-- house draws 11 px right of and 10 px above its anchor and is 1085 px wide. Both now show from y 230, bags 54-557,
-- 12 px gap, auction house 569-1654. The minimap doesn't matter at the auction house (Joshua): tooltips go bottom-right.
-- tooltips in the free space under the bags (bottom-left), growing up (Joshua: they hid the Sell panel's profit)
-- Full screen (Joshua: "use the FULL screen at the AH, it's a TV"): the auction house at 115% fills the left 3/4 (TV px
-- 20-1487 across, 54-1026 down, text about 18-20 px tall); bags at 70% top-right (1496-1910, 54-504); tooltips at 85%
-- under the bags, growing down. Anchors allow for where each window really draws (measured): bags 90 units above
-- their anchor, the auction house 13 right / 12 up (both before scale).
-- v3 (looked at on the TV): the auction house's own tab icons stick out 65 px past its right edge (they covered the
-- bags), so the auction house is 105% (15-1423 across), bags 65% at the top of the right column (1433-1818, 54-472),
-- tooltips 90% under them; the "Equipped" compare gets 28 px so its tab doesn't sit on the item tooltip.
-- 2026-11-27 (Joshua: the bags look small with space to spare): bags 79%, filling the column from just right of the
-- auction window's tab icons (they end at ~1430 px) to 10 px from the screen's right edge (1440-1910 = 470 px; the bag
-- window is ~595 px wide unscaled). The item tooltip goes under them, right edges level (placeTips).
local AHL = { ah = { 2, 67, 1.05 }, bags = { 1440, 113, 0.79 }, tip = 0.90, tipAt = { 1433, 480 } }
local ahLayoutOn, saved = false, {}
local TIPS = {}   -- the tooltip frames we move (filled as they're hooked)
-- TV pixels -> a frame's own SetPoint units at scale s (also right when the game's UI scale is not 1)
local function U(p, s) return p / PX / s / UIParent:GetEffectiveScale() end
local function keep(f)
  if not f or saved[f] then return end
  local pts = {}
  for i = 1, f:GetNumPoints() do pts[i] = { f:GetPoint(i) } end
  saved[f] = { scale = f:GetScale(), pts = pts }
end
local function putTopLeft(f, x, y, s)
  if not f or InCombatLockdown() then return end
  keep(f); f:SetScale(s); f:ClearAllPoints()
  f:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', U(x, s), -U(y, s))
end
-- Every NPC window (vendor, trainer, bank, mailbox, quest, gossip, crafting; Joshua 2026-11-26: "at a vendor nothing
-- else matters, use the entire screen"): the NPC window stays where WoW opens it (left; Blizzard's own frames are never
-- moved), the bags go to the right edge at 90%, tops level, and the item tooltip plus its "Equipped" compare fill the
-- gap between the two at up to 100%, never on either window. Back to normal when the window closes.
local PANELS = { 'MerchantFrame', 'ClassTrainerFrame', 'BankFrame', 'MailFrame', 'QuestFrame', 'GossipFrame',
  'TradeSkillFrame', 'ProfessionsFrame', 'CraftFrame' }
local panelOn = false
local function openPanel()
  -- really on screen: shown inside a shown parent and not faded out (2026-11-27: some add-ons keep NPC windows shown
  -- but invisible, and the vendor layout then stayed on in the open world)
  for _, n in ipairs(PANELS) do
    local f = rawget(_G, n)
    if f and f.IsVisible and f:IsVisible() and (not f.GetEffectiveAlpha or f:GetEffectiveAlpha() > 0.05) then return f end
  end
end
local function px(f)   -- a frame's left, top, right, bottom in TV pixels (nil until it has a place)
  if not f:GetLeft() then return nil end
  local e = f:GetEffectiveScale() * PX
  return f:GetLeft() * e, 1080 - f:GetTop() * e, f:GetRight() * e, 1080 - f:GetBottom() * e
end
local placing = false
-- One compare box under another, placed by screen position rather than tied to it: the game's own anchoring ties
-- ShoppingTooltip1 to ShoppingTooltip2, and a tie the other way made a loop (2026-11-27). side: 'LEFT' or 'RIGHT' edge.
local function under(c, prev, gap, side)
  local e, ce = prev:GetEffectiveScale(), c:GetEffectiveScale()
  local x, b = side == 'RIGHT' and prev:GetRight() or prev:GetLeft(), prev:GetBottom()
  if not x or not b then return false end
  c:ClearAllPoints()
  c:SetPoint(side == 'RIGHT' and 'TOPRIGHT' or 'TOPLEFT', UIParent, 'BOTTOMLEFT', x * e / ce, b * e / ce - gap)
  return true
end
-- How far a compare box's "Equipped" tab sticks out above its top, in TV px: measured from the box's own header
-- (CompareHeader: its top against the box's top, or failing that its height), else 28 px (measured 2026-11-27).
local TAB_PX = 28
local function tabPx(c)
  local h = c and rawget(c, 'CompareHeader')
  if h and (not h.IsShown or h:IsShown()) then
    local ok, v = pcall(function()
      local ht, ct = h:GetTop(), c:GetTop()
      if ht and ct and ht * h:GetEffectiveScale() > ct * c:GetEffectiveScale() then return (ht * h:GetEffectiveScale() - ct * c:GetEffectiveScale()) * PX end
      local hh = h:GetHeight(); if hh and hh > 0 then return hh * h:GetEffectiveScale() * PX end
    end)
    if ok and v and v > 0 and v < 200 then return v end
  end
  return TAB_PX
end
-- a solid backing so the words read over the world and the chat behind (Joshua 2026-11-27, later the same day:
-- "an opaque background. Chat is cutting it off"; it was 90% before)
local TIP_BACK = { 0.03, 0.03, 0.05, 1 }
local function solidTip(t) if t and t.NineSlice and t.NineSlice.SetCenterColor then pcall(t.NineSlice.SetCenterColor, t.NineSlice, unpack(TIP_BACK)) end end
-- A two-hander compared with a main hand and an off hand shows two "Equipped" boxes; the first one's "if you replace
-- these items" already sums both (Joshua 2026-11-27: three boxes ran off the screen), so the second is hidden.
-- The auction house stack's spot, one per tooltip (an item's link, else its first line, e.g. a price). The AH hides and
-- re-shows its tooltip ~5 times a second while the lines fill in, so the spot only ever moves one way per tooltip:
-- further left, from under the bags to left of them, item beside the Equipped box. It never flips back (Joshua
-- 2026-11-27: "still kind of buggy"; a spot wiped on every hide and a bottom check that read a stale position blinked).
local spot = {}
local function spotFor()
  local link = GameTooltip and GameTooltip.GetItem and select(2, GameTooltip:GetItem())
  local l1 = rawget(_G, 'GameTooltipTextLeft1')
  local key = link or ('t:' .. tostring(l1 and l1.GetText and l1:GetText() or '?'))
  if spot.key ~= key then spot = { key = key } end
  return spot
end
local function twoHander(t)
  local link = t and t.GetItem and select(2, t:GetItem())
  if not link and GameTooltip and GameTooltip.GetItem and GameTooltip:IsShown() then link = select(2, GameTooltip:GetItem()) end
  local loc = link and GetItemInfoInstant and select(4, GetItemInfoInstant(link))
  return loc == 'INVTYPE_2HWEAPON'
end
local function placeTips()
  local x, y, limit, s = AHL.tipAt[1], AHL.tipAt[2], 1910, AHL.tip
  local panel = panelOn and openPanel()
  if panel and not ahLayoutOn then
    local _, top, right = px(panel)
    if not right then return end
    x, y = right + 12, top
    local bags = rawget(_G, 'KroGamepadBagsFrame')
    if bags and bags:IsShown() and bags:GetLeft() then limit = (px(bags)) - 12 end
  end
  -- At the auction house (Joshua 2026-11-27: a wide tooltip ran into the screen's edge and the game shoved it left):
  -- the stack's right edge lines up with the bag window's right edge, just under it, so a wide one grows left.
  -- 2026-11-27, later ("too far to the right"): left edges level with the bag window instead; a tooltip too wide to fit
  -- from there moves left only as far as it must to stay 10 px inside the screen.
  local side, bags = 'LEFT', rawget(_G, 'KroGamepadBagsFrame')
  if ahLayoutOn and bags and bags:IsShown() and bags:GetLeft() then
    local bLeft, _, _, bBottom = px(bags)
    if bLeft then
      local widest = 0
      for _, n in ipairs({ 'NotGameTooltipKroGamepadBags', 'GameTooltip', 'ShoppingTooltip1', 'ShoppingTooltip2' }) do
        local t = rawget(_G, n)
        if t and t:IsShown() and t.GetWidth then widest = math.max(widest, (t:GetWidth() or 0) * s * PX * UIParent:GetEffectiveScale()) end
      end
      local sp = spotFor()
      sp.x = math.min(sp.x or bLeft, bLeft, 1910 - widest)
      x, y = sp.x, bBottom + 34   -- (the bag window's footer hangs ~26 px below its edge)
      -- No room under the bags for the whole stack (tall bags, a two-hander's Equipped boxes; Joshua 2026-11-27 at the
      -- game's own auction window): the stack goes left of the bag window instead, tops level, growing left.
      local tall, ue = 0, UIParent:GetEffectiveScale()
      for _, n in ipairs({ 'NotGameTooltipKroGamepadBags', 'GameTooltip', 'ShoppingTooltip1', 'ShoppingTooltip2' }) do
        local t = rawget(_G, n)
        if t and t:IsShown() and t.GetHeight then tall = tall + (t:GetHeight() or 0) * s * PX * ue + 40 end
      end
      if y + tall > 1070 then sp.left = true end
      if sp.left then
        local _, bTop = px(bags)
        side, x, y = 'RIGHT', bLeft - 8, bTop
      end
    end
  end
  local anchor = side == 'RIGHT' and 'TOPRIGHT' or 'TOPLEFT'
  local main
  for _, n in ipairs({ 'NotGameTooltipKroGamepadBags', 'GameTooltip' }) do
    local t = rawget(_G, n)
    if t and t:IsShown() then
      if panel and not ahLayoutOn then s = math.max(0.6, math.min(1.0, (limit - x) / (math.max(1, t:GetWidth()) * PX))) end
      keep(t); t:SetScale(s); t:ClearAllPoints()
      t:SetPoint(anchor, UIParent, 'TOPLEFT', U(x, s), -U(y, s))
      if ahLayoutOn then solidTip(t) end
      main = main or t
    end
  end
  -- What you're wearing on top, the item under it (Joshua 2026-11-27, as in the bags): the "Equipped" boxes take the
  -- spot, pushed down by their tab so it sits flush at the stack's top-left; the item goes under the last one.
  -- No compare box: the item stays at the spot.
  if not main then return end
  local prev
  local only1 = twoHander(main)
  for _, n in ipairs({ 'ShoppingTooltip1', 'ShoppingTooltip2' }) do
    local t = rawget(_G, n)
    if t and t:IsShown() and only1 and n == 'ShoppingTooltip2' then t:Hide(); t = nil end
    if t and t:IsShown() then
      keep(t); t:SetScale(main:GetScale())
      local ms = main:GetScale()
      if ahLayoutOn then solidTip(t) end
      if not prev then t:ClearAllPoints(); t:SetPoint(anchor, UIParent, 'TOPLEFT', U(x, ms), -U(y + tabPx(t), ms)); prev = t
      elseif under(t, prev, U(tabPx(t), ms), side) then prev = t end
    end
  end
  if prev then
    under(main, prev, U(12, main:GetScale()), side)
    -- still runs off the bottom: the item goes left of the Equipped box, tops level (Joshua: "options 2 and 3").
    -- Worked out from the heights, not read back from the screen: a frame just moved still reports its old spot.
    local sp, ue = ahLayoutOn and spotFor(), UIParent:GetEffectiveScale()
    if sp and not sp.left and not sp.beside then
      local h = function(t) return (t:GetHeight() or 0) * t:GetScale() * ue * PX end
      local bottom = y + h(main) + 12
      for _, n in ipairs({ 'ShoppingTooltip1', 'ShoppingTooltip2' }) do
        local t = rawget(_G, n); if t and t:IsShown() then bottom = bottom + tabPx(t) + h(t) end
      end
      if bottom > 1070 then sp.beside = true end
    end
    if sp and sp.beside and not sp.left then
      local first = rawget(_G, 'ShoppingTooltip1')
      local fl, ft = first and px(first)
      if fl then local ms = main:GetScale(); main:ClearAllPoints(); main:SetPoint('TOPRIGHT', UIParent, 'TOPLEFT', U(fl - 12, ms), -U(ft, ms)) end
    end
  end
end
-- Bags open on their own (Joshua 2026-11-26: "when I'm in my bags the tooltip is in a terrible spot", it sat on the bag
-- window's items): the bag add-on's item tooltip goes just left of the bag window, tops level, the "Equipped" compare under
-- it. Only the bags' own tooltip moves; the world's tooltip (GameTooltip) is left alone.
-- 2026-11-27: KroGamepadBags 2.1 shows items in the game's own tooltip (GameTooltip, owned by the bag window) unless its
-- "Tooltip type" is set to its own; that one is moved too, but only while the bag window owns it.
local function bagsAlone()
  local b = rawget(_G, 'KroGamepadBagsFrame')
  if ahLayoutOn or panelOn or not (b and b:IsShown() and b:GetLeft()) then return nil end
  local t = rawget(_G, 'NotGameTooltipKroGamepadBags')
  if t and t:IsShown() then return b, t end
  local g = rawget(_G, 'GameTooltip')
  if g and g:IsShown() and g.GetOwner and g:GetOwner() == b then return b, g end
  return nil
end
local function placeBagTip()
  local b, t = bagsAlone()
  if not b then return end
  local left, top = px(b)
  if not left then return end
  -- KroGamepadBags 2.1 puts its character, bank and other-character panels to the left of the bag window as their
  -- own frames: go left of whichever is leftmost, so the tooltip never sits on the character picture
  for _, n in ipairs({ 'KroGamepadBagsDoll', 'KroGamepadBagsBank', 'KroGamepadBagsViewDoll' }) do
    local f = rawget(_G, n)
    if f and f.IsVisible and f:IsVisible() and f:GetLeft() then local l = px(f); if l and l < left then left = l end end
  end
  local s = t:GetScale()
  if t.NineSlice and t.NineSlice.SetCenterColor then pcall(t.NineSlice.SetCenterColor, t.NineSlice, unpack(TIP_BACK)) end
  -- What you're wearing on top, the item you're on under it (Joshua 2026-11-27: "flip it so that equipped sat on the
  -- top"; the "Equipped" tab sits at the top-left corner of its box, tabPx above it, so the stack starts that much lower).
  local prev
  for _, n in ipairs({ 'ShoppingTooltip1', 'ShoppingTooltip2' }) do
    local c = rawget(_G, n)
    if c and c:IsShown() then
      c:SetScale(s)
      if c.NineSlice and c.NineSlice.SetCenterColor then pcall(c.NineSlice.SetCenterColor, c.NineSlice, unpack(TIP_BACK)) end
      if not prev then c:ClearAllPoints(); c:SetPoint('TOPRIGHT', UIParent, 'TOPLEFT', U(left - 12, s), -U(top + tabPx(c), s)); prev = c
      elseif under(c, prev, U(tabPx(c), s), 'RIGHT') then prev = c end
    end
  end
  if not (prev and under(t, prev, U(12, s), 'RIGHT')) then
    t:ClearAllPoints(); t:SetPoint('TOPRIGHT', UIParent, 'TOPLEFT', U(left - 12, s), -U(top, s))
  end
end
local restoreLater = false
local restore
local function putTips()
  if placing then return end
  -- 2026-11-27: the vendor layout stayed on with no NPC window open (seen after a reload in Goldshire), so every
  -- tooltip, the bags' too, went to the auction-house spot over the bag window. Check the window is really there.
  if panelOn and not ahLayoutOn and not openPanel() then
    panelOn = false
    if InCombatLockdown() then restoreLater = true else placing = true; pcall(restore); placing = false end
  end
  if ahLayoutOn or panelOn then placing = true; pcall(placeTips); placing = false
  elseif bagsAlone() then placing = true; pcall(placeBagTip); placing = false end
end
function restore()   -- everything the layouts moved goes back, and tooltips are free again
  if InCombatLockdown() then restoreLater = true; return end
  restoreLater = false; panelOn = false; ahLayoutOn = false
  for f, v in pairs(saved) do
    f:SetScale(v.scale); f:ClearAllPoints()
    -- tooltips get no old points back: the game anchors them fresh on every show, and a leftover point plus the game's
    -- own made the tooltip stretch across the top of the screen after closing a vendor (Joshua 2026-11-27)
    if TIPS[f] then if f.Hide and f:IsShown() then f:Hide() end
    else for _, p in ipairs(v.pts) do f:SetPoint(unpack(p)) end end
  end
  wipe(saved)
end
local function panelLayout()
  if ahLayoutOn then return end
  if InCombatLockdown() then if panelOn and not openPanel() then panelOn = false; restoreLater = true end return end
  local panel = openPanel()
  if panel and panel:GetTop() then
    panelOn = true
    local bags = rawget(_G, 'KroGamepadBagsFrame')
    if bags and bags:IsShown() then
      local _, top = px(panel)
      keep(bags); bags:SetScale(0.9); bags:ClearAllPoints()
      bags:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -U(10, 0.9), -U(top + 80, 0.9))   -- its title bar draws 80 px above
    end
    putTips()
  elseif panelOn then restore() end
end
local function ahLayout(on)
  if not on then ahLayoutOn = false; restore(); if not restoreLater then panelLayout() end return end   -- an NPC window still open gets its own layout
  if InCombatLockdown() then return end
  panelOn = false; ahLayoutOn = true; spot = {}
  putTopLeft(rawget(_G, 'ImprovedForeverAuctionBuy'), AHL.ah[1], AHL.ah[2], AHL.ah[3])
  putTopLeft(rawget(_G, 'KroGamepadBagsFrame'), AHL.bags[1], AHL.bags[2], AHL.bags[3])
end
do
  local hooked = {}
  local function hookTip(n)
    local t = rawget(_G, n)
    if t and not hooked[n] then hooked[n] = true; TIPS[t] = true; t:HookScript('OnShow', function() C_Timer.After(0, putTips) end)
      -- the "Equipped" compare boxes: our spot ties ShoppingTooltip2 under ShoppingTooltip1; left on, the game's own
      -- side-by-side anchoring next time ties 1 to 2 and fails ("Cannot anchor to a region dependent on it", 54 times
      -- in one session, 2026-11-27). The game anchors them fresh on every show, so ours go when they close.
      if n:match('^ShoppingTooltip') then t:HookScript('OnHide', function(self) if not placing then self:ClearAllPoints() end end) end
      -- the auction house anchors the tooltip itself on every item change, after it shows: follow every SetPoint
      hooksecurefunc(t, 'SetPoint', function() if not placing then putTips() end end)
      -- the controller UI anchors item tooltips to the highlighted button (SetOwner with ANCHOR_RIGHT), which the game
      -- keeps moving there on its own: while a layout is on, take the anchor off so our spot sticks
      if t.SetAnchorType then hooksecurefunc(t, 'SetOwner', function(self)
        if ahLayoutOn or panelOn or bagsAlone() then self:SetAnchorType('ANCHOR_NONE'); putTips() end end) end
    end
  end
  local hookAll
  function hookAll()
    for _, n in ipairs({ 'NotGameTooltipKroGamepadBags', 'GameTooltip', 'ShoppingTooltip1', 'ShoppingTooltip2' }) do hookTip(n) end
    for _, n in ipairs({ 'ImprovedForeverAuctionBuy', 'KroGamepadBagsFrame' }) do
      local f = rawget(_G, n)
      if f and not hooked[n] then hooked[n] = true; f:HookScript('OnShow', function() if ahLayoutOn then C_Timer.After(0, function() ahLayout(true) end) elseif openPanel() then C_Timer.After(0, panelLayout) else C_Timer.After(0, hookAll) end end) end
    end
  end
  local pev = CreateFrame('Frame')
  for _, e in ipairs({ 'MERCHANT_SHOW', 'MERCHANT_CLOSED', 'TRAINER_SHOW', 'TRAINER_CLOSED', 'BANKFRAME_OPENED', 'BANKFRAME_CLOSED',
    'MAIL_SHOW', 'MAIL_CLOSED', 'QUEST_DETAIL', 'QUEST_PROGRESS', 'QUEST_COMPLETE', 'QUEST_FINISHED', 'GOSSIP_SHOW', 'GOSSIP_CLOSED',
    'TRADE_SKILL_SHOW', 'TRADE_SKILL_CLOSE', 'PLAYER_ENTERING_WORLD' }) do pcall(pev.RegisterEvent, pev, e) end
  pev:SetScript('OnEvent', function() C_Timer.After(0.3, function() hookAll(); panelLayout() end) end)
  local ev = CreateFrame('Frame')
  ev:RegisterEvent('AUCTION_HOUSE_SHOW'); ev:RegisterEvent('AUCTION_HOUSE_CLOSED')
  ev:SetScript('OnEvent', function(_, e)
    if e == 'AUCTION_HOUSE_SHOW' then C_Timer.After(0.3, function() hookAll(); ahLayout(true) end)
    else ahLayout(false) end
  end)
  -- the game's default anchor only adds its corner, it never clears: if one of our spots is still on the tooltip (the
  -- vendor or bag spot), it stretches between the two. With no layout on, a tooltip with more than one point is reset.
  local fixing = false
  -- the game puts each tooltip's own (see-through) background back whenever it fills it; in the bags ours goes back on
  -- (Joshua 2026-11-27: chat still showed through the item tooltip)
  local function solid(t)
    if t and (bagsAlone() or ahLayoutOn) and t.NineSlice and t.NineSlice.SetCenterColor then pcall(t.NineSlice.SetCenterColor, t.NineSlice, unpack(TIP_BACK)) end
  end
  for _, fn in ipairs({ 'SharedTooltip_SetBackdropStyle', 'GameTooltip_SetBackdropStyle' }) do
    if hooksecurefunc and rawget(_G, fn) then hooksecurefunc(fn, function(t) solid(t) end) end
  end
  if hooksecurefunc then hooksecurefunc('GameTooltip_SetDefaultAnchor', function(t, parent)
    if ahLayoutOn or panelOn then C_Timer.After(0, putTips); return end
    -- The world's tooltip (people, mobs) opens just above Polestar's target list, right edges level, instead of on it
    -- (Joshua 2026-11-27: "the tooltip is covering everything" in the bottom-right corner where the list sits).
    if not fixing and t == GameTooltip and not bagsAlone() then
      local top, right, ue = nil, nil, UIParent:GetEffectiveScale()
      for i = 1, 8 do
        local r = rawget(_G, 'PolestarTargetRow' .. i)
        if r and r.IsVisible and r:IsVisible() and r:GetTop() then
          local e = r:GetEffectiveScale() / ue
          top = math.max(top or 0, r:GetTop() * e); right = math.max(right or 0, r:GetRight() * e)
        end
      end
      if top then
        fixing = true; t:ClearAllPoints(); t:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMLEFT', right, top + 8); fixing = false
        return
      end
    end
    if fixing or not t or not t.GetNumPoints or t:GetNumPoints() <= 1 or bagsAlone() then return end
    fixing = true; t:ClearAllPoints(); pcall(GameTooltip_SetDefaultAnchor, t, parent); fixing = false
  end) end
  -- a window that closed in combat is put back when combat ends; a logout or reload while one is open puts it back first
  local rev = CreateFrame('Frame'); rev:RegisterEvent('PLAYER_REGEN_ENABLED'); rev:RegisterEvent('PLAYER_LOGOUT')
  rev:SetScript('OnEvent', function(_, e) if restoreLater or e == 'PLAYER_LOGOUT' then restore(); if e ~= 'PLAYER_LOGOUT' then panelLayout() end end end)
end
_G.OmaPadAhLayout = ahLayout   -- for a /run to try it again
_G.OmaPadPutTipsForTest = putTips

local busy
local function later() if busy then return end; busy = true; C_Timer.After(2, function() busy = false; apply() end) end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_ENTERING_WORLD', 'SPELLS_CHANGED', 'LEARNED_SPELL_IN_SKILL_LINE', 'LEARNED_SPELL_IN_TAB', 'BAG_UPDATE_DELAYED', 'PLAYER_REGEN_ENABLED', 'UNIT_PET', 'PET_BAR_UPDATE' }) do
  pcall(ev.RegisterEvent, ev, e)                -- event names differ between WoW versions
end
ev:SetScript('OnEvent', function(_, e, a1)
  if e == 'LEARNED_SPELL_IN_TAB' or e == 'LEARNED_SPELL_IN_SKILL_LINE' then pcall(Land.learned, tonumber(a1)) end
  if e == 'PLAYER_ENTERING_WORLD' then
    C_Timer.After(3, function()
      pcall(keepRxpProfile); pcall(settings); pcall(moveBreathBar); pcall(hideTracker); pcall(meterButtonOnly); pcall(setMeters, false)
      C_Timer.After(30, function() pcall(memory) end)
      apply()
    end)
  else later() end
end)
-- The landing's moments (sheet 26): a trainer holds everything until its window closes; a fight holds it until the
-- fight ends; any button, moving, or a fight starting ends one that is playing.
local landEv = CreateFrame('Frame')
for _, e in ipairs({ 'TRAINER_SHOW', 'TRAINER_CLOSED', 'PLAYER_REGEN_ENABLED', 'PLAYER_REGEN_DISABLED', 'PLAYER_STARTED_MOVING',
  'MODIFIER_STATE_CHANGED', 'UNIT_SPELLCAST_SENT', 'PLAYER_TARGET_CHANGED', 'PLAYER_ENTERING_WORLD' }) do pcall(landEv.RegisterEvent, landEv, e) end
landEv:SetScript('OnEvent', function(_, e, a1, a2)
  if e == 'TRAINER_SHOW' then Land.trainer = true; Land.stop('trainer')
  elseif e == 'TRAINER_CLOSED' then
    if not Land.trainer then return end                       -- the game can send it twice
    Land.trainer = false
    C_Timer.After(0.3, function() apply(); Land.kick() end)   -- the last spell learned may not be looked at yet
  elseif e == 'PLAYER_REGEN_ENABLED' then if Land.afterCombat then Land.afterCombat = false; C_Timer.After(0.5, Land.kick) end
  elseif e == 'PLAYER_ENTERING_WORLD' then Land.trainer = false; Land.stop('loading')
  elseif e == 'PLAYER_REGEN_DISABLED' then Land.stop('combat')
  elseif e == 'MODIFIER_STATE_CHANGED' then if a2 == 1 then Land.stop('button') end   -- a trigger pressed, not released
  elseif e == 'UNIT_SPELLCAST_SENT' then if a1 == 'player' then Land.stop('button') end
  else Land.stop('button') end
end)
if hooksecurefunc then                                        -- after-hooks only: nothing of the game's is changed
  for _, fn in ipairs({ 'UseAction', 'JumpOrAscendStart', 'ToggleGameMenu', 'CastSpellByName' }) do
    if rawget(_G, fn) then hooksecurefunc(fn, function() Land.stop('button') end) end
  end
end

-- /ompad: re-check now.  /ompad sim: replay levelling on a copy and check the rules.  /ompad mine: hand every pad button back to the add-on (forgets which were his).
-- /omapad landtest: one sample landing and one upgrade on the pad.  /omapad sound <id>: the chime (a sound kit id),
-- played once to hear it; /omapad sound default: back to the default; /omapad sound: says which one is set.
SLASH_OMASHUPAD1 = '/ompad'
SLASH_OMASHUPAD2 = '/omapad'
SlashCmdList.OMASHUPAD = function(m)
  m = m or ''
  if m == 'sim' then simulate(); return end
  if m == 'landtest' then Land.test(); return end
  if m:match('^sound') then
    local arg = m:match('^sound%s+(%S+)')
    if arg == 'default' then OmaPadDB.landSound = nil elseif tonumber(arg) then OmaPadDB.landSound = tonumber(arg) end
    say('landing sound: ' .. tostring(landSound()) .. (OmaPadDB.landSound and '' or ' (default)')); chime(); return
  end
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

