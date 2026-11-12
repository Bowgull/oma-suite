-- The kill bar on the target frame (Doomed.lua): what it draws for a list of DoTs. These lock in today's behaviour
-- before the rebuild: piece order, precast (Charging), landing, the instant-cast "landed" piece, ending gold,
-- the skull, a tick's bite, and a target switch wiping everything. The DoT list is fed straight in (P.source), so
-- only the bar's own logic is tested here.
local A, B = 'Creature-0-1-0-1-100-AAAA', 'Creature-0-1-0-1-101-BBBB'
local FRAME = 1 / 30
local COLOR = {   -- Doomed.lua's piece colours (sheet 34 B)
  Corruption = { 78 / 255, 40 / 255, 136 / 255 }, Immolate = { 160 / 255, 66 / 255, 22 / 255 },
  ['Bane of Agony'] = { 128 / 255, 30 / 255, 74 / 255 },
}
local GOLD = { 206 / 255, 160 / 255, 44 / 255 }
local function full(c) return { math.min(1, c[1] * 1.15), math.min(1, c[2] * 1.15), math.min(1, c[3] * 1.15) } end

local function setup(W)
  local ns, F, UI = require('load').addon()
  local P = ns.parts.doomed
  F.mob('nameplate1', A, 'Kobold', 100); F.mob('nameplate2', B, 'Gnoll', 100)
  local DOTS = { [A] = {}, [B] = {} }
  P.source = function(u) local t = W.units[u]; return t and DOTS[t.guid] or {} end
  F.target(A)
  return ns, F, UI, P, DOTS
end
local function dot(W, name, damage, lasts, o)
  o = o or {}
  return { name = name, damage = damage, expiresAt = W.now + lasts, appliedAt = o.appliedAt or (W.now - 1), provisional = o.provisional or false }
end
local function colorIs(T, tex, want, msg)
  T.near(tex._r, want[1], 1e-6, msg .. ' (red)'); T.near(tex._g, want[2], 1e-6, msg .. ' (green)'); T.near(tex._b, want[3], 1e-6, msg .. ' (blue)')
end
local function noErrors(T) T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1])) end
-- the skull's window and its long bar (Doomed.lua build(): a HIGH-strata frame on the portrait's parent)
local function skull(UI)
  for _, k in ipairs(UI.kids(TargetFrame.TargetFrameContainer)) do
    if rawget(k, '_strata') == 'HIGH' then return k, UI.kids(k)[1] end
  end
end

return {
  ['pieces: the DoT that ends first sits nearest the green, each stacked on the last'] = function(W, T)
    local ns, F, UI, P, DOTS = setup(W)
    DOTS[A] = { dot(W, 'Bane of Agony', 84, 24), dot(W, 'Corruption', 47, 12), dot(W, 'Immolate', 20, 15) }
    W.advance(2, FRAME)
    T.eq(table.concat(P.order, ','), 'Corruption,Immolate,Bane of Agony', 'order by expiry')
    local c, i, a = P.slotOf.Corruption, P.slotOf.Immolate, P.slotOf['Bane of Agony']
    T.ok(c and i and a and c ~= i and i ~= a, 'each DoT owns its own slot')
    T.ok(c.right == P.E[0].f and i.right == c.edge and a.right == i.edge, 'each piece hangs on the one before it')
    T.near(P.shownBy.Corruption, 47, 1, 'grown to full size')
    T.near(c.mark.L:GetValue(), 47, 1, 'Corruption ends 47 into the green')
    T.near(i.mark.L:GetValue(), 67, 1, 'Immolate stacked after it')
    T.near(a.mark.L:GetValue(), 151, 1, 'Agony last')
    T.ok(c.base:IsShown() and i.base:IsShown() and a.base:IsShown(), 'all three drawn')
    colorIs(T, c.base, full(COLOR.Corruption), "Corruption's colour")
    colorIs(T, i.base, full(COLOR.Immolate), "Immolate's colour")
    noErrors(T)
  end,
  ['precast (Charging): the piece sits dim and fills with the cast bar, then lands at full colour'] = function(W, T)
    local ns, F, UI, P, DOTS = setup(W)
    T.eq(ns.db.cast, 'charging', 'the default look')
    local t0 = W.now
    UnitCastingInfo = function() return 'Corruption', nil, nil, t0 * 1000, (t0 + 2) * 1000 end
    DOTS[A] = { dot(W, 'Corruption', 47, 14, { provisional = true }) }
    W.advance(1, FRAME)
    local s = P.slotOf.Corruption
    T.eq(P.wasPre.Corruption, 'charging')
    T.near(s.cpr, .5, .05, 'filled as far as the cast')
    T.ok(s.cbase:IsShown(), 'the fill is drawn')
    colorIs(T, s.base, { COLOR.Corruption[1] * .45, COLOR.Corruption[2] * .45, COLOR.Corruption[3] * .45 }, 'the piece under it is dim')
    colorIs(T, s.cbase, full(COLOR.Corruption), 'the fill is the landed colour')
    UnitCastingInfo = function() return nil end
    DOTS[A][1].provisional = false
    W.advance(.1, FRAME)
    T.eq(P.wasPre.Corruption, nil); T.ok(P.landAt.Corruption, 'landing noted')
    T.ok(not s.cbase:IsShown(), 'fill gone')
    colorIs(T, s.base, full(COLOR.Corruption), 'full colour at once')
    T.ok(s.spark:IsShown(), 'the ember fades out after landing')
    W.advance(.5, FRAME)
    T.ok(not s.spark:IsShown(), 'and is gone after 0.35 s')
    noErrors(T)
  end,
  ['an instant cast it has seen before shows a solid "landed" piece until the engine lists it, never in the skull'] = function(W, T)
    local ns, F, UI, P, DOTS = setup(W)
    DOTS[A] = { dot(W, 'Corruption', 47, 12, { appliedAt = W.now }) }
    W.advance(.3, FRAME)
    T.eq(P.fullBy.Corruption, 47, 'its fresh size is remembered')
    DOTS[A] = {}
    W.advance(1.5, FRAME)
    T.eq(next(P.slotOf), nil, 'gone from the bar')
    W.fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-1', 172)
    W.advance(.2, FRAME)
    T.ok(P.landed and P.landed.name == 'Corruption', 'landed piece held')
    T.eq(table.concat(P.order, ','), 'Corruption')
    local _, long = skull(UI)
    T.eq(long:GetValue(), 0, 'not counted toward the skull')
    W.advance(5, FRAME)
    T.eq(P.landed, nil, 'dropped after 4.5 s unlisted'); T.eq(next(P.slotOf), nil)
    noErrors(T)
  end,
  ['ending: the last 3 seconds turn gold (steady look), before that its own colour'] = function(W, T)
    local ns, F, UI, P, DOTS = setup(W)
    ns.db.lowlook = 'steady'
    DOTS[A] = { dot(W, 'Corruption', 20, 10) }
    W.advance(.5, FRAME)
    local s = P.slotOf.Corruption
    colorIs(T, s.base, full(COLOR.Corruption), 'own colour with 9.5 s left')
    DOTS[A][1].expiresAt = W.now + 2
    W.advance(.2, FRAME)
    colorIs(T, s.base, full(GOLD), 'gold in the last 3 s')
    ns.db.lowlook = 'breathe'
    W.advance(.4, FRAME)
    T.near(s.base._r / s.base._g, full(GOLD)[1] / full(GOLD)[2], 1e-3, 'breathing gold: same hue')
    T.ok(s.base._r <= full(GOLD)[1] + 1e-9, 'never brighter than steady gold')
    noErrors(T)
  end,
  ['skull: shows when confirmed DoTs reach the health; off with the setting or a raid mark'] = function(W, T)
    local ns, F, UI, P, DOTS = setup(W)
    local win, long = skull(UI)
    T.ok(win and long, 'the skull window exists')
    DOTS[A] = { dot(W, 'Corruption', 60, 12), dot(W, 'Immolate', 50, 15), dot(W, 'Bane of Agony', 500, 24, { provisional = true }) }
    W.advance(.3, FRAME)
    T.ok(win:IsShown(), 'window shown')
    T.eq(select(2, long:GetMinMaxValues()), 100, 'scaled to the health')
    T.eq(long:GetValue(), 110, 'only confirmed DoTs count (the precast Agony does not)')
    DOTS[A] = { dot(W, 'Corruption', 30, 12) }
    W.advance(.3, FRAME)
    T.eq(long:GetValue(), 30, 'short of the health: the skull sits outside its window')
    ns.db.skull = false; W.advance(.2, FRAME)
    T.ok(not win:IsShown(), 'setting off: hidden')
    ns.db.skull = true; W.raidMarks.target = 8; W.advance(.2, FRAME)
    T.ok(not win:IsShown(), 'a real raid mark wins')
    W.raidMarks.target = nil; W.advance(.2, FRAME)
    T.ok(win:IsShown(), 'back')
    noErrors(T)
  end,
  ['a tick: the drop becomes a bite that glows and closes over 0.7 s'] = function(W, T)
    local ns, F, UI, P, DOTS = setup(W)
    DOTS[A] = { dot(W, 'Corruption', 47, 12) }
    W.advance(1, FRAME)
    DOTS[A][1].damage = 35
    W.advance(4 * FRAME, FRAME)
    T.ok(P.bites.Corruption, 'a bite'); T.near(P.bites.Corruption.amt, 12, 1e-6, 'the size of the drop')
    T.ok(P.slotOf.Corruption.ghost:IsShown(), 'the bitten part is drawn')
    W.advance(1, FRAME)
    T.eq(P.bites.Corruption, nil, 'closed'); T.ok(not P.slotOf.Corruption.ghost:IsShown())
    noErrors(T)
  end,
  ['a target switch wipes every bit of state from the last mob'] = function(W, T)
    local ns, F, UI, P, DOTS = setup(W)
    DOTS[A] = { dot(W, 'Corruption', 47, 12, { appliedAt = W.now }), dot(W, 'Immolate', 20, 15) }
    W.advance(1, FRAME)
    DOTS[A][1].damage = 35; W.advance(4 * FRAME, FRAME)
    W.fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-1', 172)
    T.ok(next(P.bites) and P.landed, 'state to wipe: a bite and a landed piece')
    DOTS[B] = { dot(W, 'Bane of Agony', 84, 24) }
    F.target(B)
    T.eq(next(P.bites), nil, 'bites'); T.eq(next(P.pred), nil, 'predictions'); T.eq(P.landed, nil, 'landed piece')
    T.eq(next(P.shownBy), nil, 'sizes'); T.eq(next(P.wasPre), nil, 'precast looks'); T.eq(next(P.slotOf), nil, 'slots')
    T.eq(table.concat(P.order, ','), 'Bane of Agony', 'only the new mob')
    W.advance(FRAME, FRAME)
    T.ok(P.shownBy['Bane of Agony'] < 84 * .5, 'the new piece grows in from nothing')
    T.eq(P.slotOf.Corruption, nil); T.eq(P.slotOf.Immolate, nil)
    noErrors(T)
  end,
}
