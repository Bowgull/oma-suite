-- The QA list (Side notes: doesitdie-engine-map.md section 8), as tests. Unless a test says otherwise, both engines
-- run and must agree at every 0.05 s step (F.diffs empty), and the test also checks the behaviour itself.
local A = 'Creature-0-1-0-1-100-AAAA'
local B = 'Creature-0-1-0-1-101-BBBB'
local function setup(W, opts)
  local F = require('fight')
  F.start(opts)
  F.mob('nameplate1', A, 'Kobold'); F.target(A)
  W.combat = not (opts and opts.readable)
  return F
end
local function same(T, F) T.eq(#F.diffs, 0, #F.diffs .. ' differences, first: ' .. tostring(F.diffs[1])) end

return {
  -- Parsing
  ['01 Immolate counts its 20 over time, not the 11 upfront'] = function(W, T)
    local F = setup(W); F.cast(348, { castTime = 2 }); F.hit('nameplate1', 4); F.wait(0.1)
    T.eq(F.dots().Immolate.damage, 20); same(T, F)
  end,
  ['02 Immolate upfront hit is not a tick'] = function(W, T)
    local F = setup(W); F.cast(348, { castTime = 2 }); F.hit('nameplate1', 4); F.wait(1)
    T.eq(F.dots().Immolate.damage, 20); same(T, F)
  end,
  ['03 Siphon Life reads every 3 sec for 30 sec, Shadow'] = function(W, T)
    local F = setup(W); F.cast(18265); F.wait(0.1)
    local d = F.dots()['Siphon Life']; T.eq(d.damage, 150); T.eq(d.school, 32); same(T, F)
  end,
  ['04 Bane of Agony ticks small first (shape)'] = function(W, T)
    local F = setup(W); F.cast(980); F.wait(2); F.hit('nameplate1', 32); F.wait(0.1)
    local d = F.dots()['Bane of Agony'].damage
    T.ok(d >= 80 and d <= 81, 'first tick is half the average (3.5 of 84), got ' .. d); same(T, F)
  end,
  ['06 a secret description makes no DoT and no error'] = function(W, T)
    local F = setup(W); F.SPELLS[172] = { name = 'Corruption', desc = W.secret('x') }
    F.cast(172); F.wait(0.5); T.eq(#F.oma.dotsFor('target'), 0); same(T, F)
  end,
  ['07 channels, direct spells and other curses are never DoTs'] = function(W, T)
    local F = setup(W); F.cast(689); F.cast(686, { castTime = 2.5 }); F.cast(11719); F.wait(1)
    T.eq(#F.oma.dotsFor('target'), 0); same(T, F)
  end,
  ['07b other classes\' DoTs are ignored (warlock only)'] = function(W, T)
    local F = setup(W, { compare = false }); F.cast(1978); F.wait(0.5)
    T.eq(#F.oma.dotsFor('target'), 0, 'Serpent Sting must not be tracked')
  end,

  -- Targeting
  ['09 tab right after an instant DoT: it stays on the first mob'] = function(W, T)
    local F = setup(W); F.mob('nameplate2', B, 'Gnoll')
    F.cast(172); F.target(B); F.wait(0.2)
    T.eq(#F.oma.dotsFor('target'), 0, 'nothing on the new target')
    T.ok(F.dots('nameplate1').Corruption, 'Corruption on the first mob'); same(T, F)
  end,
  ['10 a [@focus] cast goes on the focus'] = function(W, T)
    local F = setup(W); F.mob('nameplate2', B, 'Gnoll'); F.alias('focus', 'nameplate2')
    F.cast(172, { on = 'focus' }); F.wait(0.2)
    T.eq(#F.oma.dotsFor('target'), 0); T.ok(F.dots('focus').Corruption); same(T, F)
  end,
  ['11 Blizzard mouseover cast on a same-named mob goes to the hovered one'] = function(W, T)
    local F = setup(W); F.mouseoverCast = true
    F.mob('nameplate2', B, 'Kobold'); F.alias('mouseover', 'nameplate2')
    F.cast(172, { on = 'mouseover' }); F.wait(0.2)
    T.eq(#F.oma.dotsFor('target'), 0); T.ok(F.dots('nameplate2').Corruption); same(T, F)
  end,
  ['12 a friendly hard target: the cast goes to the soft enemy'] = function(W, T)
    local F = setup(W); F.mob('party1', 'Player-2', 'Friend', 100, { friendly = true }); W.units.target = W.units.party1
    F.alias('softenemy', 'nameplate1')
    F.cast(172, { on = 'softenemy' }); F.wait(0.2)
    T.ok(F.dots('nameplate1').Corruption); same(T, F)
  end,
  ['13 a corpse still targeted: the cast goes to the next mob (soft enemy)'] = function(W, T)
    local F = setup(W); F.mob('nameplate2', B, 'Kobold'); W.units.nameplate1.dead = true
    F.alias('softenemy', 'nameplate2')
    F.cast(172, { on = 'softenemy' }); F.wait(0.2)
    T.ok(F.dots('nameplate2').Corruption, 'on the living mob'); same(T, F)
  end,
  ['15 dungeon (secret IDs): each mob tracked by its plate, a reused plate forgets'] = function(W, T)
    local F = require('fight'); F.start()
    F.mob('nameplate1', A, 'Cultist', 200, { secretGuid = true }); F.mob('nameplate2', B, 'Cultist', 200, { secretGuid = true })
    W.combat = true; W.units.target = W.units.nameplate1; W.fire('PLAYER_TARGET_CHANGED')
    F.cast(172); W.units.target = W.units.nameplate2; W.fire('PLAYER_TARGET_CHANGED'); F.cast(172); F.wait(0.2)
    T.ok(F.dots('nameplate1').Corruption and F.dots('nameplate2').Corruption, 'both mobs')
    W.fire('NAME_PLATE_UNIT_REMOVED', 'nameplate1'); F.wait(0.1)
    T.eq(#F.oma.dotsFor('nameplate1'), 0, 'plate 1 forgotten'); same(T, F)
  end,
  ['16 secret ID and no plate: only the target, wiped on target change'] = function(W, T)
    local F = require('fight'); F.start()
    F.mob('x1', A, 'Boss', 900, { secretGuid = true }); W.units.target = W.units.x1; W.combat = true
    W.fire('PLAYER_TARGET_CHANGED'); F.cast(172); F.wait(0.2)
    T.ok(F.dots().Corruption); W.units.target = nil; W.fire('PLAYER_TARGET_CHANGED'); W.units.target = W.units.x1
    W.fire('PLAYER_TARGET_CHANGED'); F.wait(0.1)
    T.eq(#F.oma.dotsFor('target'), 0); same(T, F)
  end,

  -- Outcomes
  ['17 a resist right after the cast drops the DoT'] = function(W, T)
    local F = setup(W); F.cast(172); F.wait(0.1); F.hit('nameplate1', 32, 0, 'RESIST'); F.wait(0.2)
    T.eq(#F.oma.dotsFor('target'), 0); same(T, F)
  end,
  ['18 a resisted recast keeps the earlier one ticking'] = function(W, T)
    local F = setup(W); F.cast(172); F.wait(3); F.hit('nameplate1', 32); F.wait(2)
    local before = F.dots().Corruption.expiresAt
    F.cast(172); F.wait(0.1); F.hit('nameplate1', 32, 0, 'RESIST'); F.wait(0.2)
    T.ok(F.dots().Corruption, 'still there'); T.near(F.dots().Corruption.expiresAt, before, 0.01, 'old schedule'); same(T, F)
  end,
  ['19 a resist just before the cast event still counts'] = function(W, T)
    local F = setup(W); F.hit('nameplate1', 32, 0, 'RESIST'); F.wait(0.1); F.cast(172); F.wait(0.2)
    T.eq(#F.oma.dotsFor('target'), 0); same(T, F)
  end,
  ['20 the pet\'s dodge right after Corruption is ignored'] = function(W, T)
    local F = setup(W); F.cast(172); F.wait(0.1); F.hit('nameplate1', 1, 0, 'DODGE'); F.wait(0.2)
    T.ok(F.dots().Corruption); same(T, F)
  end,
  ['21 a non-Shadow miss after a fresh Corruption: waits for its first tick'] = function(W, T)
    local F = setup(W); F.cast(172); F.wait(0.1); F.hit('nameplate1', 1, 0, 'MISS'); F.wait(0.2)
    T.eq(#F.oma.dotsFor('target'), 0, 'hidden while doubtful')
    F.wait(2.7); F.hit('nameplate1', 32); F.wait(0.1)
    T.ok(F.dots().Corruption, 'back after its tick'); same(T, F)
  end,
  ['22 Immolate\'s upfront hit landed: a later miss is someone else\'s'] = function(W, T)
    local F = setup(W); F.cast(348, { castTime = 2 }); F.hit('nameplate1', 4); F.wait(0.1)
    F.hit('nameplate1', 4, 0, 'MISS'); F.wait(0.2); T.ok(F.dots().Immolate); same(T, F)
  end,
  ['22b ... but an IMMUNE still removes it'] = function(W, T)
    local F = setup(W); F.cast(348, { castTime = 2 }); F.hit('nameplate1', 4); F.wait(0.1)
    F.hit('nameplate1', 4, 0, 'IMMUNE'); F.wait(0.2); T.eq(#F.oma.dotsFor('target'), 0); same(T, F)
  end,
  ['23 a DoT that never ticks is dropped after two missed ticks'] = function(W, T)
    local F = setup(W); F.cast(172); F.wait(5.5); T.ok(F.dots().Corruption, 'one missed: kept')
    F.wait(1.5); T.eq(#F.oma.dotsFor('target'), 0, 'two missed: dropped'); same(T, F)
  end,
  ['24 a mob you tabbed off (no plate) keeps its DoT until it runs out'] = function(W, T)
    local F = require('fight'); F.start(); W.combat = true
    F.mob('x1', A, 'Far'); W.units.target = W.units.x1; W.fire('PLAYER_TARGET_CHANGED'); F.cast(172)
    F.mob('nameplate2', B, 'Near'); F.target(B); F.wait(9)
    W.units.target = W.units.x1; W.fire('PLAYER_TARGET_CHANGED'); F.wait(0.1)
    T.ok(F.dots().Corruption, 'still counted'); F.wait(3.5); T.eq(#F.oma.dotsFor('target'), 0, 'expired on time'); same(T, F)
  end,
  ['25 a fully absorbed tick keeps the DoT alive'] = function(W, T)
    local F = setup(W, { readable = true }); F.cast(172); F.wait(3); F.hit('nameplate1', 32, 0, 'ABSORB')
    F.wait(3); F.hit('nameplate1', 32, 0, 'ABSORB'); F.wait(0.2); T.ok(F.dots().Corruption); same(T, F)
  end,

  -- Ticks
  ['26 in combat: ticks by school and timing, no size learned'] = function(W, T)
    local F = setup(W); F.cast(172); F.wait(3); F.hit('nameplate1', 32); F.wait(0.1)
    T.ok(F.dots().Corruption.damage < 47); T.eq(OmaDoomedDB.track.ticks[172], nil); same(T, F)
  end,
  ['27 out of combat: tick sizes are learned per rank'] = function(W, T)
    local F = setup(W, { readable = true }); F.cast(172); F.wait(3); F.hit('nameplate1', 32, 15); F.wait(0.1)
    T.eq(OmaDoomedDB.track.ticks[172], 15); T.eq(F.dots().Corruption.damage, 45, '3 ticks of 15 left'); same(T, F)
  end,
  ['27b a crit tick doesn\'t raise the average'] = function(W, T)
    local F = setup(W, { readable = true }); F.cast(172); F.wait(3); F.hit('nameplate1', 32, 15); F.wait(3)
    W.fire('UNIT_COMBAT', 'nameplate1', 'WOUND', 'CRITICAL', 28, 32); F.wait(0.1)
    T.eq(OmaDoomedDB.track.ticks[172], 15); same(T, F)
  end,
  ['28 Corruption and Siphon Life ticking at once both count'] = function(W, T)
    local F = setup(W, { readable = true }); F.cast(172); F.cast(18265); F.wait(3)
    F.hit('nameplate1', 32, 15); F.hit('nameplate1', 32, 15); F.wait(0.1)
    T.eq(F.dots().Corruption.damage, 45); T.eq(F.dots()['Siphon Life'].damage, 135); same(T, F)
  end,
  ['29 one tick seen on target and nameplate counts once'] = function(W, T)
    local F = setup(W, { readable = true }); F.cast(172); F.cast(18265); F.wait(3)
    F.hit('nameplate1', 32, 15); F.hit('target', 32, 15); F.wait(0.1)
    local n = 0; for _, d in pairs(F.dots()) do if d.damage < 47 and d.name == 'Corruption' or (d.name == 'Siphon Life' and d.damage < 150) then n = n + 1 end end
    T.eq(n, 1, 'only one DoT took that tick'); same(T, F)
  end,
  ['34 the last tick is not cut off (expiry follows the ticks)'] = function(W, T)
    local F = setup(W); F.cast(172)
    for i = 1, 4 do F.wait(3.1); F.hit('nameplate1', 32) end
    F.wait(0.1); same(T, F)
  end,
  ['37 a recast replaces the old one with a new schedule'] = function(W, T)
    local F = setup(W); F.cast(172); F.wait(3); F.hit('nameplate1', 32); F.wait(1)
    F.cast(172); F.wait(0.1); T.eq(F.dots().Corruption.damage, 47); T.eq(#F.oma.dotsFor('target'), 1); same(T, F)
  end,

  -- Casting estimate
  ['38 Immolate shows while casting'] = function(W, T)
    local F = setup(W); W.fire('UNIT_SPELLCAST_SENT', 'player', 'Kobold', 'g1', 348); W.fire('UNIT_SPELLCAST_START', 'player', 'g1', 348)
    F.wait(0.5); T.ok(F.dots().Immolate and F.dots().Immolate.provisional); same(T, F)
  end,
  ['39 recasting shows one Immolate, not two'] = function(W, T)
    local F = setup(W); F.cast(348, { castTime = 2 }); F.wait(3)
    W.fire('UNIT_SPELLCAST_SENT', 'player', 'Kobold', 'g2', 348); W.fire('UNIT_SPELLCAST_START', 'player', 'g2', 348); F.wait(0.5)
    T.eq(#F.oma.dotsFor('target'), 1); same(T, F)
  end,
  ['40 an interrupted cast removes the estimate; the old DoT stays'] = function(W, T)
    local F = setup(W); F.cast(348, { castTime = 2 }); F.wait(1)
    F.cast(348, { castTime = 1, interrupted = true }); F.wait(0.1)
    T.ok(F.dots().Immolate and not F.dots().Immolate.provisional); same(T, F)
  end,
  ['42 changing target mid-cast drops the estimate'] = function(W, T)
    local F = setup(W); F.mob('nameplate2', B, 'Gnoll')
    W.fire('UNIT_SPELLCAST_SENT', 'player', 'Kobold', 'g3', 348); W.fire('UNIT_SPELLCAST_START', 'player', 'g3', 348); F.wait(0.5)
    F.target(B); F.target(A); F.wait(0.1); T.eq(#F.oma.dotsFor('target'), 0); same(T, F)
  end,

  -- Rules
  ['53 never listens to the combat log (Forever blocks it)'] = function(W, T)
    setup(W); local f = CreateFrame('Frame')
    for k, v in pairs(_G) do if type(v) == 'table' and v.events and v.events.COMBAT_LOG_EVENT_UNFILTERED then error('registered by ' .. k) end end
    T.ok(true)
  end,
  ['54 a secret school or action is never compared'] = function(W, T)
    local F = setup(W); F.cast(172); F.wait(0.1)
    W.fire('UNIT_COMBAT', 'nameplate1', 'WOUND', '', W.secret(3), W.secret(32))
    W.fire('UNIT_COMBAT', 'nameplate1', W.secret('WOUND'), '', 3, 32)
    F.wait(0.2); T.ok(F.dots().Corruption); same(T, F)
  end,
}
