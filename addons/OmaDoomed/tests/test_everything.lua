-- Sheet 78, everything else on a mob: someone else's crowd control laid over the health bar as its own timer, other
-- players' debuffs as soft squares right of the level box, and Blizzard's own crowd-control icon switched off.
local A = 'Creature-0-1-0-1-100-A'
local function setup(W, rings)
  local ns, F, UI = require('load').addon({ rings = true, before = function() if rings then OmaDoomedDB = { rings = rings } end end })
  W.advance(3)
  return ns, F, UI
end
local function noErrors(T) T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1])) end
local function sideOf(UI, ring)
  for _, c in ipairs(UI.aura.containers) do if c.groupByKey.odeb and UI.under(c, ring:GetParent()) then return c end end
end

return {
  ["crowd control: one slot on main, CC that isn't yours, laid over the plate's health bar"] = function(W, T)
    local ns, F, UI = setup(W)
    local ring = UI.ringContainers()[1]
    local g = UI.group(UI.mainOf(ring), 'occ')
    T.ok(g and g.slot, 'a single slot'); T.eq(g.filter, 'HARMFUL|!PLAYER|CROWD_CONTROL|INCLUDE_NAME_PLATE_ONLY', "only other people's crowd control")
    F.mob('nameplate1', A, 'Kobold', 300); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); W.advance(.2)
    local row = UI.rowOn('nameplate1')
    local p; for _, x in ipairs(ns.rings.pairsAll) do if x.ring == row then p = x end end
    local b = UI.group(UI.mainOf(row), 'occ').buttons[1]
    T.eq(b._anchor, p.bar, "it covers the pair's bar frame")
    T.ok(p.bar._anchor ~= nil, "and that frame sits on the plate's health bar")
    noErrors(T)
  end,
  ["other players' debuffs: a side container, three at most; with no rings of theirs, other warlocks' DoTs are squares too"] = function(W, T)
    local ns, F, UI = setup(W)
    local ring = UI.ringContainers()[1]
    local side = sideOf(UI, ring)
    T.ok(side, 'each plate row has its side container')
    local g = UI.group(side, 'odeb')
    T.eq(g.filter, 'HARMFUL|!PLAYER|!CROWD_CONTROL|INCLUDE_NAME_PLATE_ONLY', 'everything not yours that is not crowd control')
    T.eq(g.max, 3, 'three at most'); T.ok(not (g.filters.excludeSpellIDs or {})[172], "Team row only: another warlock's Corruption is a square")
    F.mob('nameplate1', A, 'Kobold', 300).otherAuras = { 7386, 172 }   -- a warrior's Sunder, another lock's Corruption
    W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); W.advance(.2)
    local row = UI.rowOn('nameplate1')
    local s2 = sideOf(UI, row)
    T.eq(s2.unit, 'nameplate1', 'the side follows the plate')
    local seen = UI.showing(s2)
    T.eq(#seen.odeb, 2, 'the Sunder and the Corruption both show')
    noErrors(T)
  end,
  ["other players' debuffs, As rings: other warlocks' DoTs are left to their faint rings"] = function(W, T)
    local ns, F, UI = require('load').addon({ rings = true, before = function() OmaDoomedDB = { v = 5, rings = { othersMode = 'rings' } } end })
    W.advance(3)
    local side = sideOf(UI, UI.ringContainers()[1])
    local g = UI.group(side, 'odeb')
    T.ok(g.filters.excludeSpellIDs[172], "Corruption from another warlock stays a faint ring, not a square")
    T.eq(OmaDoomedDB.rings.others, true, 'their rings are on')
    noErrors(T)
  end,
  ["Blizzard's own crowd-control icon goes off with its debuff row; settings can keep either part off"] = function(W, T)
    local ns, F, UI = setup(W, { occ = false, odeb = false })
    local ring = UI.ringContainers()[1]
    T.eq(UI.group(UI.mainOf(ring), 'occ'), nil, 'crowd control off: no slot')
    T.eq(sideOf(UI, ring), nil, "other players' debuffs off: no side container")
    noErrors(T)
  end,
}
