-- The eyes (Blizzard's aura container says if your debuff is still on a plated mob) and the claims (your own channel
-- ticks and your Imp's Firebolts aren't DoT ticks). OmaDoomed's own; no side-by-side.
local A = 'Creature-0-1-0-1-100-AAAA'
local function setup(W)
  local F = require('fight'); F.start({ compare = false })
  F.mob('nameplate1', A, 'Kobold'); F.target(A); W.combat = true
  return F
end
local function eyes(F, seen)   -- what the plate's eyes report from now on
  F.oma.eyesUnits = function() return { 'nameplate1' } end
  F.oma.eyeKeyFor = function(id) return ({ [172] = 'corruption', [348] = 'immolate', [980] = 'agony' })[id] end
  F.oma.eyes = function() return seen end
end
return {
  ['eyes: a DoT whose debuff is gone is dropped, even while hits keep landing on its beat'] = function(W, T)
    local F = setup(W); local seen = { corruption = true, isb = false }; eyes(F, seen)
    F.cast(172); F.wait(3); F.hit('nameplate1', 32)
    seen.corruption = false                       -- dispelled
    F.wait(0.3); F.oma.eyesLook(); T.ok(F.dots().Corruption, 'not at once')
    F.wait(0.6); F.oma.eyesLook(); T.eq(F.dots().Corruption, nil, 'gone after half a second')
  end,
  ['eyes: a fresh DoT is given time for its debuff to show'] = function(W, T)
    local F = setup(W); eyes(F, { corruption = false, isb = false })
    F.cast(172); F.wait(0.5); F.oma.eyesLook(); F.wait(0.6); F.oma.eyesLook(); T.ok(F.dots().Corruption)
  end,
  ['eyes that can\'t see (secret) change nothing'] = function(W, T)
    local F = setup(W); eyes(F, nil); F.cast(172); F.wait(2); F.oma.eyesLook(); F.wait(1); F.oma.eyesLook(); T.ok(F.dots().Corruption)
  end,
  ['eyes: Improved Shadow Bolt\'s debuff makes Shadow DoTs +20% for 12 s'] = function(W, T)
    local F = setup(W); F.talents({ ['Improved Shadow Bolt'] = 5 }); local seen = { corruption = true, isb = false }; eyes(F, seen)
    F.cast(172); F.wait(0.1); T.eq(F.dots().Corruption.damage, 47)
    seen.isb = true; F.oma.eyesLook(); F.wait(0.1)
    -- ticks at +3, +6, +9, +12 from the cast; the debuff covers 12 s from now (+0.1): all four, 47 x 1.2
    T.eq(F.dots().Corruption.damage, 56)
  end,
  ['claims: Drain Life on the beat can\'t keep a dispelled Corruption alive'] = function(W, T)
    local F = setup(W); F.cast(172); F.wait(3); F.hit('nameplate1', 32)   -- tick 1 at +3, then it's dispelled
    F.wait(1)                                                             -- +4: Drain Life for 5 s, ticks +5..+9
    local g = 'Chan-dl'
    W.fire('UNIT_SPELLCAST_SENT', 'player', 'Kobold', g, 689); W.fire('UNIT_SPELLCAST_CHANNEL_START', 'player', g, 689)
    for i = 1, 5 do F.wait(1); F.hit('nameplate1', 32) end              -- its hits land on Corruption's beats at +6, +9
    W.fire('UNIT_SPELLCAST_CHANNEL_STOP', 'player', g, 689); F.wait(0.6)
    T.eq(F.dots().Corruption, nil, 'Drain Life\'s hits were not taken for its ticks')
  end,
  ['claims: Corruption still ticks fine during Drain Life'] = function(W, T)
    local F = setup(W); F.cast(172); F.wait(1)
    local g = 'Chan-dl2'
    W.fire('UNIT_SPELLCAST_SENT', 'player', 'Kobold', g, 689); W.fire('UNIT_SPELLCAST_CHANNEL_START', 'player', g, 689)
    F.wait(2); F.hit('nameplate1', 32); F.hit('nameplate1', 32)           -- +3: Drain Life tick AND Corruption tick
    F.wait(3); F.hit('nameplate1', 32); F.hit('nameplate1', 32)           -- +6: both again
    W.fire('UNIT_SPELLCAST_CHANNEL_STOP', 'player', g, 689); F.wait(0.2)
    T.near(F.dots().Corruption.damage, 24, 1, 'two of four ticks counted')
  end,
  ['claims: the Imp\'s Firebolt can\'t keep an eaten Immolate alive'] = function(W, T)
    local F = setup(W); W.units.pettarget = W.units.nameplate1
    F.cast(348); F.hit('nameplate1', 4); F.wait(3); F.hit('nameplate1', 4)   -- Immolate tick 1 at +3, then it's gone
    for i = 1, 3 do                                                         -- Firebolts land on its beats +6, +9, +12
      F.wait(2.4); W.fire('UNIT_SPELLCAST_SUCCEEDED', 'pet', 'pb' .. i, 3110); F.wait(0.6); F.hit('nameplate1', 4)
    end
    F.wait(0.6); T.eq(F.dots().Immolate, nil)
  end,
}
