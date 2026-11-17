-- Known-wrong behaviours, each written as a test of the RIGHT behaviour. Those on tests/run.lua's KNOWN list fail
-- on purpose until the plan phase named there; the rest (fixed ones and the English twins) pass. The non-warlock test
-- moved to tests/test_foundations.lua when phase 2 fixed it.
-- Tests here that are not on that list (the English twins) pass today and show the scenario itself is sound.
local A = 'Creature-0-1-0-1-100-AAAA'
local COLOR = { Corruption = { 41 / 255 * 1.4, 40 / 255 * 1.4, 136 / 255 * 1.4 } }   -- lightened x1.4 (KillBarStyle S.LIGHTEN)

-- A German client: spell names and descriptions come back in German (Classic Era deDE wording, as in
-- Track/Locale_deDE.lua). GetLocale may still say enUS on Forever; here it says deDE.
local function german()
  local F = require('fight')
  local s = {}; for id, v in pairs(F.SPELLS) do s[id] = v end
  s[172] = { name = 'Verderbnis', desc = 'Verdirbt das Ziel und verursacht 12 Sek. lang 47 Punkt(e) Schattenschaden.' }
  s[348] = { name = 'Feuerbrand', desc = 'Verbrennt den Feind und fügt ihm 11 Feuerschaden sowie im Verlauf von 15 Sek. insgesamt 20 zusätzlichen Feuerschaden zu.' }
  s[980] = { name = 'Bann der Pein', desc = 'Verflucht das Ziel mit Pein und verursacht 24 Sek. lang 84 Punkt(e) Schattenschaden.' }
  s[18265] = { name = 'Lebensentzug', desc = 'Überträgt alle 3 Sek. 15 Punkt(e) Gesundheit vom Ziel auf den Zaubernden. Hält 30 Sek. lang an.' }
  return s
end
-- Corruption and Immolate on a target, each past its first tick; returns the add-on and its DoTs by spell ID
local function fight(W, spells, locale)
  local ns, F, UI = require('load').addon({ spells = spells, before = function() W.locale = locale end })
  F.mob('nameplate1', A, 'Kobold', 500); F.target(A); W.combat = true
  F.cast(348, { castTime = 2 }); F.hit('nameplate1', 4)
  F.cast(172); F.wait(3); F.hit('nameplate1', 32); F.hit('nameplate1', 4); F.wait(.3)
  local by = {}; for _, e in ipairs(ns.dotsFor('target')) do by[e.spellID] = e end
  return ns, by
end
local function immolateTracked(W, T, spells, locale)
  local ns, by = fight(W, spells, locale)
  T.ok(by[348], 'Immolate tracked on the target')
end
local function corruptionColoured(W, T, spells, locale)
  local ns, by = fight(W, spells, locale)
  local e = by[172]; T.ok(e, 'Corruption tracked')
  local s = (ns.model.peek(e.name) or {}).slot; T.ok(s, 'a piece on the kill bar')
  T.near(s.base._r, math.min(1, COLOR.Corruption[1] * 1.15), 1e-6, "Corruption's colour, not the grey for unknown DoTs (" .. e.name .. ')')
  T.near(s.base._b, math.min(1, COLOR.Corruption[3] * 1.15), 1e-6, "Corruption's colour (blue)")
end

local function countEntries(t) local n = 0; for _, v in pairs(t or {}) do if type(v) == 'table' then for _ in pairs(v) do n = n + 1 end else n = n + 1 end end; return n end
local function upvalue(fn, name) for i = 1, 200 do local k, v = debug.getupvalue(fn, i); if not k then return end; if k == name then return v end end end

local function rings(W)
  local ns, F, UI = require('load').addon({ rings = true }); W.advance(3)
  return ns, F, UI
end

return {
  -- spells by ID, not English names (phase 3 for the tracking; the kill bar colour passes since phase 2's Spells.lua)
  ['English client: Immolate is tracked'] = function(W, T) immolateTracked(W, T, nil, 'enUS') end,
  ['German client: Immolate (Feuerbrand) is tracked'] = function(W, T) immolateTracked(W, T, german(), 'deDE') end,
  ['English client: Corruption keeps its colour on the kill bar'] = function(W, T) corruptionColoured(W, T, nil, 'enUS') end,
  ['German client: Corruption (Verderbnis) keeps its colour on the kill bar'] = function(W, T) corruptionColoured(W, T, german(), 'deDE') end,

  -- phase 3: claims and curses pruned on the housekeeping beat (the eyes and their Shadow Vulnerability table are gone)
  ['memory: 200 drained mobs leave the claims and curse tables small'] = function(W, T)
    local F = require('fight'); F.start({ compare = false })
    local oma = F.oma; W.combat = true
    for m = 1, 200 do
      local guid = 'Creature-0-1-0-1-' .. (1000 + m) .. '-L'
      F.mob('nameplate1', guid, 'Mob' .. m, 300); F.target(guid)
      F.cast(1490)                                              -- Curse of the Elements on every mob
      local g = 'Chan-L' .. m
      W.fire('UNIT_SPELLCAST_SENT', 'player', 'Mob' .. m, g, 689); W.fire('UNIT_SPELLCAST_CHANNEL_START', 'player', g, 689)
      for _ = 1, 5 do W.advance(1, .1); F.hit('target', 32); F.hit('nameplate1', 32) end
      W.fire('UNIT_SPELLCAST_CHANNEL_STOP', 'player', g, 689); W.advance(1, .1)
    end
    W.advance(10, .1)
    local claimed = upvalue(upvalue(oma.track.omaClaim, 'claimSlot'), 'claimed')
    local coe = upvalue(oma.track.omaTickMult, 'coe')
    T.ok(claimed and coe, 'found the tables')
    T.ok(countEntries(claimed) <= 20, 'claims kept: ' .. countEntries(claimed))
    -- a curse lasts 5 min: only the mobs cursed in the last 5 min (6 s each) are kept
    local mobs = 0; for _ in pairs(coe) do mobs = mobs + 1 end
    T.ok(mobs > 0 and mobs <= 300 / 6 + 2, 'cursed mobs kept: ' .. mobs)
    T.eq(upvalue(oma.track.omaTickMult, 'isbUntil'), nil, 'no Shadow Vulnerability table any more')
  end,

  -- phase 4: rows follow hostility changes (UNIT_FACTION / UNIT_FLAGS)
  ['a duel: a plate that turns hostile gets its row'] = function(W, T)
    local ns, F, UI = rings(W)
    local u = F.mob('nameplate1', 'Player-2', 'Rival', 300, { friendly = true }); u.player = true
    W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1')
    T.eq(UI.rowOn('nameplate1'), nil, 'friendly when it appeared: no row')
    u.enemy = true; W.fire('UNIT_FACTION', 'nameplate1'); W.fire('UNIT_FLAGS', 'nameplate1'); W.advance(.2)
    T.ok(UI.rowOn('nameplate1'), 'the duel started: a row')
  end,
  ['a mob that turns friendly loses its row'] = function(W, T)
    local ns, F, UI = rings(W)
    local u = F.mob('nameplate1', A, 'Kobold', 300)
    W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); T.ok(UI.rowOn('nameplate1'), 'a row while hostile')
    u.enemy = false; W.fire('UNIT_FACTION', 'nameplate1'); W.fire('UNIT_FLAGS', 'nameplate1'); W.advance(.2)
    T.eq(UI.rowOn('nameplate1'), nil, 'charmed: no row')
  end,

  -- phase 4: attach takes a new pair off the free list too (Rings.lua attach + newPair), so past the 24 spares
  -- every second plate steals the row of the plate before it
  ['pool: every plate past the spares keeps its own pair'] = function(W, T)
    local ns, F, UI = rings(W)
    for i = 1, 40 do F.mob('nameplate' .. i, 'Creature-0-1-0-1-' .. i .. '-P', 'Mob' .. i, 300); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate' .. i) end
    W.advance(1)
    local n, lost = 0, {}
    for i = 1, 40 do if UI.rowOn('nameplate' .. i) then n = n + 1 else lost[#lost + 1] = i end end
    T.eq(n, 40, 'plates with a row (missing: ' .. table.concat(lost, ',') .. ')')
  end,
}
