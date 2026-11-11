-- Real fights from DoesItDie's log of Bujuju's play (DoesItDieDB.log, 2026-11-11), replayed into both engines.
-- Pass = OmaDoomed's copy says exactly what DoesItDie says at every 0.05 s step.
local function diffsMsg(F) return #F.diffs .. ' differences, first: ' .. tostring(F.diffs[1]) end
return {
  ['log fight 2: Corruption, Immolate, Bane of Agony in combat (hidden amounts)'] = function(W, T)
    local F = require('fight')
    F.start({ at = 100939.3 })
    F.mob('nameplate1', 'Creature-0-6827-0-2-1548-E773449908', 'Mob')
    F.target('Creature-0-6827-0-2-1548-E773449908')
    W.combat = true
    F.wait(2.7)                                   -- 100942.0
    F.cast(172, { castTime = 1.7 })               -- Corruption lands 100943.7
    F.wait(0.2); F.cast(348, { castTime = 1.9 })  -- Immolate lands 100945.8
    F.hit('nameplate1', 4)                         -- its upfront Fire hit
    F.wait(0.4); F.cast(980)                       -- Bane of Agony 100946.2
    F.wait(0.5); F.hit('nameplate1', 32)           -- 100946.7 Corruption tick 1
    F.wait(1.4); F.hit('nameplate1', 64)           -- 100948.1 someone's Arcane
    F.wait(0.1); F.hit('nameplate1', 32)           -- 100948.2 Bane tick 1
    F.wait(0.7); F.hit('nameplate1', 4)            -- 100948.9 Immolate tick 1
    F.wait(0.6); F.hit('nameplate1', 64)           -- 100949.5
    F.wait(0.1); F.hit('nameplate1', 32)           -- 100949.6 Corruption tick 2
    F.wait(0.1); F.hit('nameplate1', 32)           -- 100949.7 an unmatched Shadow hit
    F.wait(0.4); F.hit('nameplate1', 32)           -- 100950.1 Bane tick 2
    F.wait(1.8); F.hit('nameplate1', 4)            -- 100951.9 Immolate tick 2
    F.wait(1.0)
    T.ok(F.left() > 0, 'DoTs still running')
    T.eq(#F.diffs, 0, diffsMsg(F))
  end,
}
