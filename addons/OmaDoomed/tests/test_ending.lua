-- One ending window for everything (2026-11-16, "i need to be sure ending soon works"): rings, the target's kill bar
-- and the preview all ask RingsLook R.windowFor, so they light at the same moment.
local function setup(casts, db)
  local ns = require('load').addon({ rings = true, before = function()
    C_Spell = C_Spell or {}
    C_Spell.GetSpellInfo = function(n) local ms = casts[n]; if ms then return { name = n, castTime = ms, spellID = 1 } end end
    if db then OmaDoomedDB = db end
  end })
  return ns
end
return {
  ['ending: defaults agree at 5 s for anything that is not a seat DoT'] = function(W, T)
    local ns = setup({})
    T.eq(ns.rings.windowFor('cc'), 5, 'crowd control: Ending soon default 5'); T.eq(ns.rings.windowFor(nil), 5)
  end,
  ['ending: the kill bar asks the same window as the ring, by spell name'] = function(W, T)
    local ns = setup({ Corruption = 2000 })
    T.eq(ns.rings.windowForName('Corruption'), 2.4, 'Corruption by name: its cast time + 0.4')
    T.eq(ns.rings.windowForName('Corruption'), ns.rings.windowFor('corruption'), 'bar and ring agree')
  end,
  ['ending: curves built before the spellbook loaded are rebuilt once the cast times show up'] = function(W, T)
    local casts = {}
    local ns = setup(casts)
    W.advance(1)
    local before = ns.rings.builtOn
    casts.Corruption = 2000
    T.ok(ns.rings.recheckWindows(), 'cast times changed: rebuilt')
    T.ok(ns.rings.builtOn ~= before, 'now built on the real cast times')
    T.ok(not ns.rings.recheckWindows(), 'nothing changed: left alone')
  end,
  ["ending: 'steady' is honoured with the recast light on"] = function(W, T)
    local ns = setup({ Corruption = 2000 }, { lowlook = 'steady' })
    W.advance(1)
    local c = ns.rings.numCurves and ns.rings.numCurves.corruption
    T.ok(c, 'a number curve')
    if c and c.Evaluate then
      local a1 = c:Evaluate(2.3); local a2 = c:Evaluate(1.8)
      T.ok(a1 and a2 and math.abs((a1.a or 1) - (a2.a or 1)) < 1e-6, 'steady: no breath inside the window')
    end
  end,
  ['ending: /omadoomed ending reports every seat and saves it'] = function(W, T)
    local ns = setup({ Corruption = 2000, Immolate = 1500 })
    W.advance(1)
    SlashCmdList.OMADOOMED('ending')
    local out = OmaDoomedDB.ending
    T.ok(out and #out >= 6, 'saved')
    T.ok(out[1]:find('corruption: lights at 2.4 s left', 1, true), out[1])
  end,
}
