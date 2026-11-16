-- The engines (Engine/*.lua): one clock for jobs, one for motion, one roster of the fight.
local function setup(W) local ns, F, UI = require('load').addon({ rings = true }); W.advance(3); return ns, F, UI end

return {
  ['scheduler: a job runs at its rate, at once when marked, never while frozen'] = function(W, T)
    local ns = setup(W)
    local n, frozen = 0, false
    ns.sched.add('t', 1, function() n = n + 1 end, function() return frozen end)
    W.advance(.05); T.eq(n, 1, 'runs on the next frame')
    W.advance(.5); T.eq(n, 1, 'not again before its rate')
    ns.sched.mark('t'); W.advance(.05); T.eq(n, 2, 'marked: runs at once')
    frozen = true; ns.sched.mark('t'); W.advance(2); T.eq(n, 2, 'frozen: waits')
    frozen = false; W.advance(.05); T.eq(n, 3, 'then catches up')
  end,
  ['motion: a tween eases to its end; a new one starts where the old one is; calm jumps'] = function(W, T)
    local ns = setup(W)
    local v
    ns.motion.tween('k', 0, 10, .5, function(x) v = x end)
    W.advance(.25); T.ok(v > 5 and v < 10, 'eased past half by half time (ease out): ' .. v)
    local mid = v
    ns.motion.tween('k', 0, 0, .5, function(x) v = x end)
    W.advance(.02); T.ok(v <= mid and v > 0, 'took over from where it was: ' .. v)
    W.advance(1); T.eq(v, 0, 'and reached its end')
    ns.db.calm = true
    ns.motion.tween('k', 0, 7, .5, function(x) v = x end); T.eq(v, 7, 'calm motion: at once')
  end,
  ['motion: a breath stays between its bottom and top, and moves'] = function(W, T)
    local ns = setup(W)
    local lo, hi, seen = 9, -9, {}
    ns.motion.breathe('b', 2, .2, .8, function(x) lo = math.min(lo, x); hi = math.max(hi, x) end)
    for _ = 1, 60 do W.advance(.05) end
    T.ok(lo >= .2 - 1e-6 and hi <= .8 + 1e-6, 'within .2-.8')
    T.ok(hi - lo > .5, 'and it breathes: ' .. lo .. '-' .. hi)
  end,
  ['roster: mobs in your fight only; ordered missing-a-DoT first, then the soonest ending'] = function(W, T)
    local ns, F = setup(W)
    UnitThreatSituation = function(who, u) local x = W.units[u]; if who == 'player' and x and x.enemy and not x.dead and not x.idle then return 0 end end
    for k = 1, 3 do F.mob('nameplate' .. k, 'C-' .. k, 'Mob' .. k, 300); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate' .. k) end
    F.mob('nameplate4', 'C-4', 'Kodo', 300).idle = true; W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate4')
    W.advance(.3)
    local on = {}; for k = 1, 4 do on[k] = ns.roster.entries[k].on end
    T.ok(on[1] and on[2] and on[3], 'the three in the fight'); T.ok(not on[4], 'not the idle Kodo')
    ns.roster.entries[2].missing, ns.roster.entries[1].missing, ns.roster.entries[3].missing = 2, 0, 0
    ns.roster.entries[1].soonest, ns.roster.entries[3].soonest = 9, 3
    local o = ns.roster.order(true)
    T.eq(o[1].k, 2, 'missing the most first'); T.eq(o[2].k, 3, 'then the soonest ending'); T.eq(o[3].k, 1)
  end,
}
