-- Wrack (OmaDoomed's own; DoesItDie doesn't know it, so no side-by-side here).
local A = 'Creature-0-1-0-1-100-AAAA'
local function setup(W)
  local F = require('fight'); F.start({ compare = false })
  F.mob('nameplate1', A, 'Kobold'); F.target(A); W.combat = true
  return F
end
return {
  ['Wrack is not a DoT and adds no damage'] = function(W, T)
    local F = setup(W); F.channel(1316697, 6); T.eq(#F.oma.dotsFor('target'), 0)
  end,
  ['Corruption runs twice as fast while Wrack is channelled, and keeps the time gained'] = function(W, T)
    local F = setup(W); local t0 = W.now
    F.cast(172)                                   -- 47 over 12 s, a tick every 3 s
    F.wait(1)                                     -- progress 1
    local d0 = F.dots().Corruption; T.near(d0.expiresAt, t0 + 12, 0.06)
    -- Wrack for 3 s: progress 1 -> 7. Ticks due at progress 3 and 6 = real t0+2 and t0+3.5.
    local g = 'Chan-x'
    W.fire('UNIT_SPELLCAST_SENT', 'player', 'Kobold', g, 1316697); W.fire('UNIT_SPELLCAST_CHANNEL_START', 'player', g, 1316697)
    F.wait(1); F.hit('nameplate1', 32)            -- t0+2: tick 1
    F.wait(1.5); F.hit('nameplate1', 32)          -- t0+3.5: tick 2
    F.wait(0.5); W.fire('UNIT_SPELLCAST_CHANNEL_STOP', 'player', g, 1316697)   -- t0+4, progress 7
    local d = F.dots().Corruption
    T.ok(d, 'still tracked after the channel')
    T.near(d.expiresAt, t0 + 9, 0.1, 'ends 3 s sooner (12 - 3 gained)')
    T.near(d.damage, 24, 1, 'two of four ticks left (47 / 4 * 2)')
    F.wait(2); F.hit('nameplate1', 32)            -- t0+6: tick 3 at progress 9
    F.wait(0.1); T.near(F.dots().Corruption.damage, 12, 1, 'one tick left')
    F.wait(2.9); F.hit('nameplate1', 32)          -- t0+9: last tick
    F.wait(0.6); T.eq(#F.oma.dotsFor('target'), 0, 'gone after its last tick')
  end,
  ['Immolate is not sped up'] = function(W, T)
    local F = setup(W); local t0 = W.now
    F.cast(348); F.hit('nameplate1', 4); F.wait(0.5)
    F.channel(1316697, 3)
    T.near(F.dots().Immolate.expiresAt, t0 + 15, 0.1)
  end,
  ["Wrack at another mob leaves the target's DoTs alone"] = function(W, T)
    local F = setup(W); local t0 = W.now
    F.mob('nameplate2', 'Creature-B', 'Gnoll')
    F.cast(172); F.wait(0.5)
    W.units.focus = W.units.nameplate2
    local g = 'Chan-y'
    W.fire('UNIT_SPELLCAST_SENT', 'player', 'Gnoll', g, 1316697); W.fire('UNIT_SPELLCAST_CHANNEL_START', 'player', g, 1316697)
    F.wait(2); W.fire('UNIT_SPELLCAST_CHANNEL_STOP', 'player', g, 1316697)
    T.near(F.dots().Corruption.expiresAt, t0 + 12, 0.1)
  end,
}
