-- OmaDoomed's own Forever rules (not in DoesItDie: no side-by-side here).
local A = 'Creature-0-1-0-1-100-AAAA'
local function setup(W, readable)
  local F = require('fight'); F.start({ compare = false })
  F.mob('nameplate1', A, 'Kobold'); F.target(A); W.combat = not readable
  return F
end
return {
  ['Bane of Doom replaces your Bane of Agony on that mob'] = function(W, T)
    local F = setup(W); F.cast(980); F.cast(172); F.wait(1); T.ok(F.dots()['Bane of Agony'])
    F.cast(603); F.wait(0.1)
    T.eq(F.dots()['Bane of Agony'], nil, 'Agony gone'); T.ok(F.dots().Corruption, 'Corruption stays')
  end,
  ['Bane of Havoc replaces it too'] = function(W, T)
    local F = setup(W); F.cast(980); F.wait(1); F.cast(80240); F.wait(0.1); T.eq(F.dots()['Bane of Agony'], nil)
  end,
  ['Doom on another mob leaves this one alone'] = function(W, T)
    local F = setup(W); F.mob('nameplate2', 'Creature-B', 'Gnoll'); F.cast(980); F.target('Creature-B'); F.cast(603)
    F.target(A); F.wait(0.1); T.ok(F.dots()['Bane of Agony'])
  end,
  ['an evading mob loses its DoTs'] = function(W, T)
    local F = setup(W); F.cast(172); F.cast(348); F.wait(1)
    W.fire('UNIT_COMBAT', 'nameplate1', 'EVADE', '', 0, 1); F.wait(0.1); T.eq(#F.oma.dotsFor('target'), 0)
  end,
  ['a DoT that ticked then stops ticking is dropped after two missed ticks'] = function(W, T)
    local F = setup(W); F.cast(172); F.wait(3); F.hit('nameplate1', 32); F.wait(3.6)
    T.ok(F.dots().Corruption, 'one missed: kept'); F.wait(3); T.eq(F.dots().Corruption, nil, 'two missed: dropped')
  end,
  ['ticking on time keeps it to the end'] = function(W, T)
    local F = setup(W); F.cast(172)
    for i = 1, 3 do F.wait(3); F.hit('nameplate1', 32) end
    F.wait(0.2); T.ok(F.dots().Corruption)
  end,
  ['a mob out of sight (no plate) is not dropped for unseen ticks'] = function(W, T)
    local F = require('fight'); F.start({ compare = false }); W.combat = true
    F.mob('x1', A, 'Far'); W.units.target = W.units.x1; W.fire('PLAYER_TARGET_CHANGED'); F.cast(172); F.wait(3); F.hit('target', 32)
    F.mob('nameplate2', 'Creature-B', 'Near'); F.target('Creature-B'); F.wait(6.5)
    W.units.target = W.units.x1; W.fire('PLAYER_TARGET_CHANGED'); F.wait(0.1); T.ok(F.dots().Corruption)
  end,
  ['Amplify Curse makes the next Agony 50% bigger, once'] = function(W, T)
    local F = setup(W); F.cast(18288); F.cast(980); F.wait(0.1)
    T.eq(F.dots()['Bane of Agony'].damage, 126, '84 x 1.5')
    F.mob('nameplate2', 'Creature-B', 'Gnoll'); F.target('Creature-B'); F.cast(980); F.wait(0.1)
    T.eq(F.dots()['Bane of Agony'].damage, 84, 'used up')
  end,
  ['Amplify Curse runs out after 30 s'] = function(W, T)
    local F = setup(W); F.cast(18288); F.wait(31); F.cast(980); F.wait(0.1); T.eq(F.dots()['Bane of Agony'].damage, 84)
  end,
  ['a new rank starts from how much harder the old rank really hit'] = function(W, T)
    local F = setup(W, true)
    F.cast(172); F.wait(3); F.hit('nameplate1', 32, 18); F.wait(0.1)   -- rank 1: tooltip 47/4 = 11.75, really 18
    T.near(OmaDoomedDB.track.omaRatio.Corruption, 18 / 11.75, 0.01)
    F.mob('nameplate2', 'Creature-B', 'Gnoll'); F.target('Creature-B')
    F.cast(6222); F.wait(0.1)                                          -- rank 2: tooltip 108 over 15 s = 5 x 21.6
    T.near(F.dots().Corruption.damage, 108 * 18 / 11.75, 1.5, 'not the bare 108')
  end,

  ['Curse of Weakness uses up Amplify Curse'] = function(W, T)
    local F = setup(W); F.cast(18288); F.cast(702); F.cast(980); F.wait(0.1)
    T.eq(F.dots()['Bane of Agony'].damage, 84)
  end,
  ['Conflagrate eats Immolate without Shadow and Flame'] = function(W, T)
    local F = setup(W); F.cast(348); F.hit('nameplate1', 4); F.wait(1); F.cast(17962); F.wait(0.1)
    T.eq(F.dots().Immolate, nil)
  end,
  ['Shadow and Flame 5/5 keeps Immolate, and Shadow DoTs +20% for 20 s'] = function(W, T)
    local F = setup(W); F.talents({ ['Shadow and Flame'] = 5 })
    F.cast(348); F.hit('nameplate1', 4); F.cast(172); F.wait(0.5)
    T.eq(F.dots().Corruption.damage, 47)
    F.cast(17962); F.wait(0.1)
    T.ok(F.dots().Immolate, 'Immolate kept')
    T.eq(F.dots().Corruption.damage, 56, 'all 4 ticks inside the 20 s: 47 x 1.2')
  end,
  ['Shadow and Flame 2/5: Immolate may stay, so it is kept (missed ticks decide)'] = function(W, T)
    local F = setup(W); F.talents({ ['Shadow and Flame'] = 2 })
    F.cast(348); F.hit('nameplate1', 4); F.wait(1); F.cast(17962); F.wait(0.1); T.ok(F.dots().Immolate)
  end,
  ['Curse of the Elements: +10% on that mob\'s DoTs, ended by your next Curse there'] = function(W, T)
    local F = setup(W); F.cast(172); F.cast(1490); F.wait(0.1)
    T.eq(F.dots().Corruption.damage, 52, '47 x 1.1')
    F.cast(702); F.wait(0.1); T.eq(F.dots().Corruption.damage, 47, 'Weakness replaced it')
  end,
  ['Curse of the Elements on one mob leaves another alone'] = function(W, T)
    local F = setup(W); F.mob('nameplate2', 'Creature-B', 'Gnoll')
    F.cast(1490); F.target('Creature-B'); F.cast(172); F.wait(0.1); T.eq(F.dots().Corruption.damage, 47)
  end,
}
