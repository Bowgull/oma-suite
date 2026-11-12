-- The claims: your own channel ticks and your Imp's Firebolts aren't DoT ticks. OmaDoomed's own; no side-by-side.
-- (The eyes, an invisible aura container per plate, were dropped in phase 3: Blizzard locks aura buttons in combat.)
local A = 'Creature-0-1-0-1-100-AAAA'
local function setup(W)
  local F = require('fight'); F.start({ compare = false })
  F.mob('nameplate1', A, 'Kobold'); F.target(A); W.combat = true
  return F
end
return {
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
