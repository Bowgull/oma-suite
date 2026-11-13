-- Crowd-control timers (CrowdControl.lua, sheet 48): the teal ring on the held mob's plate, and the ring beside the
-- target frame whenever the held mob isn't your target or its plate is off screen.
local A, B = 'Creature-0-1-0-1-100-AAAA', 'Creature-0-1-0-1-101-BBBB'
local FEAR, FEAR3, BANISH, SEDUCE = 5782, 6215, 710, 6358

local function setup(W, rings)
  local ns, F, UI = require('load').addon({ rings = true, before = function()
    if rings then OmaDoomedDB = { rings = rings } end
  end })
  W.advance(3)
  return ns, F, UI
end
local function noErrors(T) T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1])) end
local function cast(W, id, caster) W.fire('UNIT_SPELLCAST_SUCCEEDED', caster or 'player', 'Cast-cc', id) end
local function ring(ns, kind) local f = ns.cc.rings[kind or 'fear']; return f and f:IsShown() and f or nil end
-- two slaves: A on a plate and on 'target', B on a plate
local function twoMobs(W, F)
  F.mob('nameplate1', A, 'Ravenclaw Slave', 300); F.mob('nameplate2', B, 'Ravenclaw Slave', 300)
  W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate2')
  F.alias('focus', 'nameplate1'); F.alias('boss1', 'nameplate2')   -- the mobs stay in the world when their plates go
  F.target(A)
end
local function offScreen(W, token) W.fire('NAME_PLATE_UNIT_REMOVED', token); W.units[token] = nil end

return {
  ['Fear on slave 1, it runs off screen, you target slave 2: the ring stands beside the target frame and counts down'] = function(W, T)
    local ns, F, UI = setup(W)
    twoMobs(W, F); W.combat = true
    W.units.nameplate1.auras = { FEAR }; W.fire('UNIT_AURA', 'nameplate1'); cast(W, FEAR)
    W.advance(.2)
    T.eq(ring(ns), nil, "slave 1's plate is on screen: its own exact ring shows, not this one")
    T.eq(#UI.showing(UI.mainOf(UI.rowOn('nameplate1'))).cc, 1, 'the teal ring is on its plate')
    offScreen(W, 'nameplate1'); F.target(B); W.advance(.2)
    local f = ring(ns)
    T.ok(f, 'off screen and not your target: the ring beside the frame')
    T.eq(f.num:GetText(), '10', 'Fear rank 1: 10 s')
    T.ok(UI.under(f, UIParent) and not UI.under(f, TargetFrame), 'not a child of the target frame, so it stays with no target')
    local r, g, b = f.ring:GetVertexColor()
    T.near(r, 0x5f / 255, 1e-3, 'teal'); T.near(b, 0xc8 / 255, 1e-3)
    W.advance(5); T.eq(f.num:GetText(), '5', 'counts down')
    W.advance(3); r = f.ring:GetVertexColor(); T.near(r, 1, 1e-3, 'last 3 seconds: gold')
    W.advance(2.5); T.eq(ring(ns), nil, 'over: faded out')
    T.eq(ns.cc.holds.fear, nil, 'and forgotten')
    noErrors(T)
  end,
  ['no target at all: the ring stays in its spot'] = function(W, T)
    local ns, F, UI = setup(W)
    twoMobs(W, F); W.combat = true
    cast(W, FEAR3); offScreen(W, 'nameplate1'); F.target(nil); W.advance(.2)
    local f = ring(ns)
    T.ok(f, 'still shown'); T.eq(f.num:GetText(), '20', 'Fear rank 3: 20 s')
  end,
  ['Haunt: the ring stays over the mob, so with your held target off screen it shows beside the frame'] = function(W, T)
    local ns, F, UI = setup(W, { where = 'split' })
    twoMobs(W, F); W.combat = true
    cast(W, FEAR); offScreen(W, 'nameplate1'); W.advance(.2)
    T.ok(ring(ns), 'your target, off screen: beside the frame (the frame row has no crowd-control ring in Haunt)')
  end,
  ['Target frame: while the held mob is your target its ring is on the frame, so nothing beside it'] = function(W, T)
    local ns, F, UI = setup(W, { where = 'frame' })
    twoMobs(W, F); W.combat = true
    cast(W, FEAR); offScreen(W, 'nameplate1'); W.advance(.2)
    T.eq(ring(ns), nil, 'your target: shown in the frame row')
    F.target(B); W.advance(.2)
    T.ok(ring(ns), 'switch to slave 2: the ring steps out beside the frame')
    F.target(A); W.advance(.2)
    T.eq(ring(ns), nil, 'back on slave 1: back into the frame row')
  end,
  ['Above enemies: your target behind you has no plate, so the ring shows beside the frame'] = function(W, T)
    local ns, F, UI = setup(W)
    twoMobs(W, F); W.combat = true
    cast(W, FEAR); offScreen(W, 'nameplate1'); W.advance(.2)
    T.ok(ring(ns), 'shown')
  end,
  ['the plate comes back: the exact plate ring takes over; if the Fear is gone there, the hold is over'] = function(W, T)
    local ns, F, UI = setup(W)
    twoMobs(W, F); W.combat = true
    cast(W, FEAR); offScreen(W, 'nameplate1'); F.target(B); W.advance(.2)
    T.ok(ring(ns), 'off screen: beside the frame')
    F.mob('nameplate3', A, 'Ravenclaw Slave', 300); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate3'); W.advance(.2)
    T.eq(ring(ns), nil, 'back on screen (a new plate token): hidden, the plate ring shows')
    -- a DoT tick broke it: the plate's cc ring goes away
    local row = UI.mainOf(UI.rowOn('nameplate3'))
    local b = UI.group(row, 'cc').buttons[1]; b.shown = false
    ns.cc.plateRingGone(b); W.advance(.5)
    offScreen(W, 'nameplate3'); W.advance(.2)
    T.eq(ring(ns), nil, 'it broke while you could see it: no stale timer when it runs off again')
    noErrors(T)
  end,
  ['a ring that blinks while Blizzard re-lays the row is not a break'] = function(W, T)
    local ns, F, UI = setup(W)
    twoMobs(W, F); W.combat = true
    cast(W, FEAR); W.advance(.2)
    local b = UI.group(UI.mainOf(UI.rowOn('nameplate1')), 'cc').buttons[1]
    b.shown = false; ns.cc.plateRingGone(b); b.shown = true
    W.advance(.5); offScreen(W, 'nameplate1'); F.target(B); W.advance(.2)
    T.ok(ring(ns), 'still held')
  end,
  ['a new Fear replaces the old one (one mob at a time); Banish gets its own ring next to it'] = function(W, T)
    local ns, F, UI = setup(W)
    twoMobs(W, F); W.combat = true
    cast(W, FEAR); W.advance(4)
    F.target(B); cast(W, FEAR); F.target(A); offScreen(W, 'nameplate2'); W.advance(.2)
    T.eq(ring(ns).num:GetText(), '10', 'the new Fear, from its own cast')
    cast(W, BANISH); F.target(B); offScreen(W, 'nameplate1'); W.advance(.2)
    T.ok(ring(ns, 'banish') and ring(ns, 'fear'), 'two holds, two rings')
    T.eq(ring(ns, 'banish').num:GetText(), '20', 'Banish rank 1: 20 s')
  end,
  ["Seduction counts only from your Sayaad's cast, on the demon's target"] = function(W, T)
    local ns, F, UI = setup(W)
    twoMobs(W, F); W.combat = true
    cast(W, SEDUCE, 'player'); W.advance(.2)
    T.eq(ns.cc.holds.seduce, nil, 'not from you')
    F.alias('pettarget', 'nameplate2')
    cast(W, SEDUCE, 'pet'); offScreen(W, 'nameplate2'); W.advance(.2)
    T.eq(ns.cc.holds.seduce.guid, B, "the demon's target")
    T.ok(ring(ns, 'seduce'), 'shown beside the frame')
  end,
  ['the held mob dies on screen: no ring for it after its plate goes'] = function(W, T)
    local ns, F, UI = setup(W)
    twoMobs(W, F); W.combat = true
    cast(W, FEAR); F.target(B); W.advance(.2)
    W.units.nameplate1.dead = true; offScreen(W, 'nameplate1'); W.advance(.5)
    T.eq(ring(ns), nil, 'dead, not counting')
  end,
  ['the fight ends: every hold is over'] = function(W, T)
    local ns, F, UI = setup(W)
    twoMobs(W, F); W.combat = true
    cast(W, FEAR); offScreen(W, 'nameplate1'); F.target(B); W.advance(.2)
    W.combat = false; W.fire('PLAYER_REGEN_ENABLED'); W.advance(.5)
    T.eq(ring(ns), nil, 'gone: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,
  ['the setting: off hides the ring and turns the plate group off; /omadoomed cc test shows a pretend Fear'] = function(W, T)
    local ns, F, UI = setup(W)
    twoMobs(W, F)
    ns.ccSlash('test'); W.advance(.2)
    T.ok(ring(ns), 'test ring'); T.eq(ring(ns).num:GetText(), '15')
    OmaDoomedDB.rings.cc = false; ns.bus:Fire('SETTING', 'cc', 'rings'); W.advance(.2)
    T.eq(ring(ns), nil, 'off')
    T.eq(UI.group(UI.rowOn('nameplate1'), 'cc').enabled, false, 'plate group off too')
    noErrors(T)
  end,
}
