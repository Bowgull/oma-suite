-- Phase 7: the plate bars only draw a plate again when something on it changed (its DoTs, your cast, a plate or a
-- setting), with the real tracking underneath. Counted in widget calls on the plate pieces.
local DOTS = { 172, 980, 348 }   -- Corruption, Bane of Agony, Immolate

local function setup(W, n)
  local ns, F, UI = require('load').addon({ rings = true })
  W.advance(3)
  for i = 1, n do
    local u = F.mob('nameplate' .. i, 'Creature-0-1-0-1-' .. i .. '-B', 'Mob' .. i, 30000); u.auras = DOTS
    W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate' .. i)
  end
  W.advance(1, 1 / 60); W.combat = true
  for i = 1, n do F.target(W.units['nameplate' .. i].guid); for _, id in ipairs(DOTS) do F.cast(id) end end
  F.target(W.units.nameplate1.guid)
  return ns, F, UI
end
-- SetValue calls on measuring bars of plate pieces during `secs`
local function valuesSet(W, UI, ns, secs, during)
  local hbs = {}
  for i = 1, 40 do local p = UI.plate and UI.plate['nameplate' .. i]; if p then hbs[#hbs + 1] = p.UnitFrame.HealthBarsContainer.healthBar end end
  local n, wrapped = 0, {}
  for _, hb in ipairs(hbs) do
    local set = ns.parts.platebar.setOf(hb)
    if set then for i = 1, 5 do local b = set[i]; local f = b.SetValue; wrapped[b] = f; rawset(b, 'SetValue', function(...) n = n + 1; return f(...) end) end end
  end
  local t = 0
  while t < secs do W.advance(1 / 60, 1 / 60); t = t + 1 / 60; if during then during(t) end end
  for b in pairs(wrapped) do rawset(b, 'SetValue', nil) end
  return n
end

return {
  ['a plate whose DoTs did not change is not drawn again'] = function(W, T)
    local ns, F, UI = setup(W, 3)
    W.advance(.5, 1 / 60)
    T.ok(ns.parts.platebar.setOf(UI.plate.nameplate2.UnitFrame.HealthBarsContainer.healthBar), 'pieces made on a dotted plate')
    T.eq(valuesSet(W, UI, ns, .5), 0, 'half a second with nothing new: no piece touched')
    local s0 = ns.dotsStamp('nameplate2')
    local hits = 0
    local n = valuesSet(W, UI, ns, 4, function(t) if t >= hits then hits = hits + 1; F.hit('nameplate2', 32); F.hit('nameplate2', 4) end end)
    T.ok(ns.dotsStamp('nameplate2') ~= s0, 'the tracking saw a tick')
    T.ok(n > 0, 'and plate 2 was drawn again: ' .. n)
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,
  ['40 plates ticking on one frame are drawn over a few frames, at most 12 a frame'] = function(W, T)
    local ns, F, UI = setup(W, 40)
    W.advance(1, 1 / 60)
    local most = 0
    local real = ns.model.listInto
    local perFrame = 0
    ns.model.listInto = function(u, ...) if u ~= 'target' and debug.traceback():find('KillPlates.lua', 1, true) then perFrame = perFrame + 1 end; return real(u, ...) end   -- the plates' kill bars only (not the target bar, the roster or the list)
    local total = 0
    for f = 0, 4 * 60 do
      if f % 60 == 0 then for i = 1, 40 do F.hit('nameplate' .. i, 32); F.hit('nameplate' .. i, 4) end end
      perFrame = 0; W.advance(1 / 60, 1 / 60); total = total + perFrame
      if perFrame > most then most = perFrame end
    end
    ns.model.listInto = real
    T.ok(total > 12, 'plates were drawn again as they ticked: ' .. total)
    T.ok(most <= 12, 'at most 12 plates a frame: ' .. most)
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,
}
