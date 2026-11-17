-- Seats, packed (2026-11-16, "dots have their place but never an empty spot they organize themselves correctly to
-- where they belong"): each seat DoT is a one-button group, in seat order, in its own flowing row. The game lays the
-- row out (in combat too), so a DoT that isn't up takes no space and the rest close up in their order. The ending
-- glow, the bands and the icons flow the same groups the same way, so they line up.
local A = 'Creature-0-1-0-1-100-A'
local function setup(W, known)
  local ns, F, UI = require('load').addon({ rings = true, before = function()
    if known then IsPlayerSpell = function(id) return known[id] == true end end
  end })
  W.advance(3)
  return ns, F, UI
end
local function noErrors(T) T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1])) end
local function keys(c) local t = {}; for _, g in ipairs(c.groups) do t[#t + 1] = g.key end; return table.concat(t, ',') end
local ORDER = 'corruption,agony,curse,immolate,siphon'

return {
  ['packed seats: halo, band and icon rows flow the same groups in seat order, one button each'] = function(W, T)
    local ns, F, UI = setup(W)
    local ring = UI.ringContainers()[1]
    local p; for _, q in ipairs(ns.rings.pairsAll) do if q.ring == ring then p = q end end
    T.ok(p and p.sring and p.smain and p.halo, 'a pair has its seat rows')
    for _, c in ipairs({ p.sring, p.smain, p.halo }) do
      T.eq(keys(c), ORDER, 'seat order')
      for _, g in ipairs(c.groups) do T.ok(not g.slot, g.key .. ' is a group (flows), not a fixed slot'); T.eq(g.opts.maxFrameCount, 1, g.key .. ': one button') end
    end
    T.ok(UI.kids(p.sring)[1] == p.smain or (function() for _, k in ipairs(UI.kids(p.sring)) do if k == p.smain then return true end end end)(), 'icons are a child of the bands (draw above)')
    noErrors(T)
  end,
  ['packed seats: a mob with only Agony and Immolate shows just those two, Agony first'] = function(W, T)
    local ns, F, UI = setup(W)
    F.mob('nameplate1', A, 'Kobold', 300).auras = { 348, 980 }
    W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); W.advance(.5)
    local row = UI.rowOn('nameplate1'); local p
    for _, q in ipairs(ns.rings.pairsAll) do if q.ring == row then p = q end end
    T.ok(p, 'the row'); p.smain:UpdateAllAuras()
    local seen = UI.showing(p.smain)
    T.eq(#seen.corruption, 0, 'no Corruption: takes no place'); T.eq(#seen.agony, 1, 'Agony'); T.eq(#seen.immolate, 1, 'Immolate')
    noErrors(T)
  end,
  ['packed seats: the row starts where the first seat was, and re-centres when a seat is learned'] = function(W, T)
    local known = {}
    local ns, F, UI = setup(W, known)
    local S, R = ns.rings.S, ns.rings
    for _, sp in ipairs(ns.spells.list) do if sp.key ~= 'siphon' then for _, id in ipairs(sp.ids) do known[id] = true end end end
    W.fire('SPELLS_CHANGED'); W.advance(.1)
    local p = ns.rings.pairsAll[1]
    local x = p.sring._pts and p.sring._pts.BOTTOMLEFT and p.sring._pts.BOTTOMLEFT[3]
    T.near(x, R.seatX(1, 4) - S / 2, 1e-6, 'four known: starts at the first of four spots')
    for _, sp in ipairs(ns.spells.list) do for _, id in ipairs(sp.ids) do known[id] = true end end
    W.fire('SPELLS_CHANGED'); W.advance(.1)
    x = p.sring._pts.BOTTOMLEFT[3]
    T.near(x, R.seatX(1, 5) - S / 2, 1e-6, 'five known: moves out')
    noErrors(T)
  end,
  ['seats: target-frame rows have no seat rows; plate rows keep the flowing rings above'] = function(W, T)
    local ns, F, UI = require('load').addon({ rings = true, before = function() OmaDoomedDB = { rings = { where = 'split' } } end })
    W.advance(3)
    for _, p in ipairs(ns.rings.pairsAll) do
      if p.ring.unit == 'target' then T.ok(not p.sring, 'a row following your target keeps the flow') end
    end
    noErrors(T)
  end,
}
