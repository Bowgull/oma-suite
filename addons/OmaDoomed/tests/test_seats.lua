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
  ["packed seats: the row starts at the row anchor's left edge (over a mob: the health bar's left edge)"] = function(W, T)
    local ns, F, UI = setup(W)
    local p = ns.rings.pairsAll[1]
    local pt = p.sring._pts and p.sring._pts.BOTTOMLEFT
    T.ok(pt, 'anchored by its bottom-left')
    T.eq(pt[1], p.anchor, 'to the row anchor'); T.eq(pt[2], 'BOTTOMLEFT', "at the anchor's left edge"); T.eq(pt[3], 0); T.eq(pt[4], 0)
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
  ["sheet 78: a plate's side row shows the mob's important buffs (by type colour) before other players' debuffs"] = function(W, T)
    local ns, F, UI = setup(W)
    local p; for _, q in ipairs(ns.rings.pairsAll) do if q.side then p = q; break end end
    T.ok(p, 'a plate pair with its side row')
    local keys = {}; for _, g in ipairs(p.side.groups) do keys[#keys + 1] = g.key end
    T.eq(table.concat(keys, ','), 'mbuff,odeb', 'buffs first, then their debuffs')
    T.eq(ns.rings.BUFF_RGB.Enrage, nil, 'Enrage not singled out'); T.eq(ns.rings.BUFF_RGB.Magic[1], 1, 'magic buffs orange'); T.ok(ns.rings.BUFF_RGB.Magic[3] < .2)
    noErrors(T)
  end,
}
