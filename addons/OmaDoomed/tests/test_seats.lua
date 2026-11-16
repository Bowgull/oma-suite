-- Seats (sheets 69/70 A, 73; approved 2026-11-16): over a mob each DoT has its own fixed spot, a missing one leaves
-- its spot blank, the row stays centred on the seats you know, and rings sit 20% of a ring apart.
local A = 'Creature-0-1-0-1-100-A'

local function setup(W, known)
  local ns, F, UI = require('load').addon({ rings = true, before = function()
    if known then IsPlayerSpell = function(id) return known[id] == true end end
  end })
  W.advance(3)
  return ns, F, UI
end
local function noErrors(T) T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1])) end
local function seatOf(c, key) return c.groupByKey[key] end
local function xOf(b) local p = b._pts and b._pts.BOTTOM; return p and p[3] end

-- every rank of every seat spell known, except what 'without' names
local function knownAll(ns, without)
  local k = {}
  for _, sp in ipairs(ns.spells.list) do if sp.key ~= without then for _, id in ipairs(sp.ids) do k[id] = true end end end
  return k
end

return {
  ['seats: each DoT is one aura slot (1 button), the rest still flow; a pair costs half what it did'] = function(W, T)
    local ns, F, UI = setup(W)
    local ring = UI.ringContainers()[1]
    for _, k in ipairs({ 'corruption', 'agony', 'curse', 'immolate', 'siphon' }) do
      local g = seatOf(ring, k); T.ok(g and g.slot, k .. ' is a slot'); T.eq(#g.buttons, 1, k .. ': one button')
      T.ok(seatOf(UI.mainOf(ring), k).slot, k .. ': a slot in main too')
    end
    for _, k in ipairs({ 'cc', 'channel', 'mine', 'others' }) do T.ok(not seatOf(ring, k).slot, k .. ' still flows') end
    T.eq(ring.built + UI.mainOf(ring).built, 90, '90 aura buttons a pair (was 180)')
    noErrors(T)
  end,
  ['seats: fixed spots, centred, 20% of a ring apart; a missing DoT leaves its spot blank'] = function(W, T)
    local R
    local ns, F, UI = setup(W, nil)
    R = ns.rings
    local S = R.S
    local ring = UI.ringContainers()[1]
    -- no IsPlayerSpell in this world: all five seats count
    local want = { corruption = -2, agony = -1, curse = 0, immolate = 1, siphon = 2 }
    for k, i in pairs(want) do
      local b = seatOf(ring, k).buttons[1]
      T.near(xOf(b), i * S * 1.2, 1e-6, k .. ' sits in its spot')
      T.near(xOf(seatOf(UI.mainOf(ring), k).buttons[1]), i * S * 1.2, 1e-6, k .. ': main lines up with ring')
    end
    -- a mob with only Agony: Agony shows in ITS spot, the others draw nothing
    F.mob('nameplate1', A, 'Kobold', 300).auras = { 980 }
    W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); W.advance(.5)
    local row = UI.rowOn('nameplate1'); local seen = UI.showing(UI.mainOf(row))
    T.eq(#seen.agony, 1, 'Agony shows'); T.eq(#seen.corruption, 0, 'Corruption spot blank'); T.eq(#seen.immolate, 0, 'Immolate spot blank')
    T.near(xOf(seatOf(row, 'agony').buttons[1]), -S * 1.2, 1e-6, 'still in the second spot')
    noErrors(T)
  end,
  ['seats: without Siphon Life the four you know are centred; learning it re-centres five'] = function(W, T)
    local known = {}
    local ns, F, UI = setup(W, known)
    -- learn every spell but Siphon Life, then tell the rings (SPELLS_CHANGED, out of combat)
    for id in pairs(knownAll(ns, 'siphon')) do known[id] = true end
    W.fire('SPELLS_CHANGED'); W.advance(.1)
    local S = ns.rings.S
    local ring = UI.ringContainers()[1]
    T.near(xOf(seatOf(ring, 'corruption').buttons[1]), -1.5 * S * 1.2, 1e-6, 'four seats: Corruption first')
    T.near(xOf(seatOf(ring, 'immolate').buttons[1]), 1.5 * S * 1.2, 1e-6, 'Immolate last')
    for id in pairs(knownAll(ns)) do known[id] = true end
    W.fire('SPELLS_CHANGED'); W.advance(.1)
    T.near(xOf(seatOf(ring, 'corruption').buttons[1]), -2 * S * 1.2, 1e-6, 'five seats: Corruption moves out')
    T.near(xOf(seatOf(ring, 'siphon').buttons[1]), 2 * S * 1.2, 1e-6, 'Siphon Life takes the fifth')
    noErrors(T)
  end,
  ['seats: the flowing rings sit one ring and a gap above the seats; target-frame rows have no seats'] = function(W, T)
    local ns, F, UI = require('load').addon({ rings = true, before = function() OmaDoomedDB = { rings = { where = 'split' } } end })
    W.advance(3)
    local R = ns.rings
    local plateRing
    for _, c in ipairs(UI.ringContainers()) do
      if c.unit == 'target' then T.ok(not c.groupByKey.corruption.slot, 'a row following your target keeps the flow')
      elseif not plateRing then plateRing = c end
    end
    local p = plateRing._pts.BOTTOM
    T.near(p[4], R.S + 0.2 * R.S, 1e-6, 'flow row above the seats')
    noErrors(T)
  end,
}
