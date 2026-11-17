-- Recasting a DoT that's still running (2026-11-16, Joshua: "i can cast anything once but the second time bugs out
-- and i cant see refreshes"). Corruption cast, ticks every 3 s, recast at 6 s. Whatever the game does with the tick
-- clock on a refresh, the recast must stay tracked; a miss of another school right after must not undo it.
local function world(W)
  local ns, F = require('load').addon()
  local A = 'Creature-0-1-0-1-100-AAAA'
  F.mob('nameplate1', A, 'Kobold', 500); F.target(A)
  W.combat = true
  UnitCastingInfo = function() return nil end
  local function cast()
    local g = 'Cast-x' .. W.now
    W.fire('UNIT_SPELLCAST_SENT', 'player', 'Kobold', g, 172)
    W.fire('UNIT_SPELLCAST_SUCCEEDED', 'player', g, 172)
    return W.now
  end
  local function runTo(t, sched)
    while W.now < t - 1e-9 do
      W.advance(.05, 1 / 30)
      if sched[1] and W.now >= sched[1] - 1e-9 then table.remove(sched, 1); F.hit('target', 32, nil); F.hit('nameplate1', 32, nil) end
    end
  end
  local function dot()
    for _, e in ipairs(ns.dotsFor('target')) do if e.name == 'Corruption' then return e end end
  end
  local function firstCast()
    local c1 = cast(); W.advance(.05, 1 / 30)
    local sched = {}; for k = 1, 4 do sched[#sched + 1] = c1 + 3 * k end
    runTo(c1 + 6, sched)
  end
  return ns, F, cast, runTo, dot, firstCast
end

return {
  ['refresh: the game restarts the tick clock: the recast keeps ticking and showing'] = function(W, T)
    local ns, F, cast, runTo, dot, firstCast = world(W)
    firstCast()
    local c2 = cast(); W.advance(.05, 1 / 30)
    local fresh = dot(); T.ok(fresh, 'tracked after the recast')
    local full = fresh.damage
    local sched = {}; for k = 1, 4 do sched[#sched + 1] = c2 + 3 * k end
    runTo(c2 + 7, sched)
    local d = dot(); T.ok(d, 'still tracked 7 s on'); T.ok(d.damage < full, 'and its ticks counted down: ' .. d.damage .. ' < ' .. full)
  end,
  ['refresh: the game keeps the old tick rhythm: the recast is not dropped (it was, 7 s after the recast)'] = function(W, T)
    local ns, F, cast, runTo, dot, firstCast = world(W)
    firstCast()
    local c2 = cast(); W.advance(.05, 1 / 30)
    local full = dot().damage
    local sched = {}; for k = 1, 4 do sched[#sched + 1] = c2 + 1.5 + 3 * (k - 1) end
    for i = 1, 20 do runTo(c2 + i * .5, sched); T.ok(dot(), ('tracked at %.1f s after the recast'):format(i * .5)) end
    T.ok(dot().damage < full, 'its ticks counted down')
  end,
  ['refresh: a miss of another school right after the recast does not roll it back'] = function(W, T)
    local ns, F, cast, runTo, dot, firstCast = world(W)
    firstCast()
    local before = dot().damage
    local c2 = cast(); W.advance(.1, 1 / 30); F.hit('target', 1, nil, 'MISS'); W.advance(.05, 1 / 30)
    T.ok(dot().damage > before, ('the recast stands: %d, the old one had %d'):format(dot().damage, before))
  end,
}
