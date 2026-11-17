-- The recast light (sheet 85, approved 2026-11-16): a ring lights when it's time to start the recast.
local function setup(casts)
  local ns = require('load').addon({ rings = true, before = function()
    C_Spell = C_Spell or {}
    C_Spell.GetSpellInfo = function(n) local ms = casts[n]; if ms then return { name = n, castTime = ms, spellID = 1 } end end
  end })
  return ns
end
return {
  ['recast light: a DoT with a cast time lights at that cast time + 0.4 s; an instant in its last 1.5 s'] = function(W, T)
    local ns = setup({ Corruption = 2000, Immolate = 1500, ['Curse of Agony'] = 0 })
    local R = ns.rings
    T.eq(R.windowFor('corruption'), 2.4, 'Corruption: 2 s cast')
    T.eq(R.windowFor('immolate'), 1.9, 'Immolate with a faster cast (talents): 1.5 s cast')
    T.eq(R.windowFor('agony'), 1.5, 'Agony: instant, one global cooldown')
  end,
  ["recast light off: rings use 'Ending soon' instead"] = function(W, T)
    local ns = setup({ Corruption = 2000 })
    ns.db.recast = false; ns.db.low = 4
    T.eq(ns.rings.windowFor('corruption'), 4, 'the Ending soon seconds')
  end,
  ["the ring font is measured: asked 1/1.05 the size and moved right by the font's own offset, so it sits on the band"] = function(W, T)
    local ns = setup({})
    local R = ns.rings
    T.ok(R.GLYPH_MEASURED, 'measured in game')
    local fs = { SetFont = function(self, f, size) self.size = size; return true end, SetSize = function() end, ClearAllPoints = function() end,
      SetPoint = function(self, a, b, c, x, y) self.x, self.y = x, y end, SetJustifyH = function() end, SetJustifyV = function() end, SetWordWrap = function() end }
    R.placeGlyph(fs, {}, 34)
    T.ok(math.abs(fs.size - 34 / 1.05) < .01, 'font size asked so the ring comes out 34: ' .. tostring(fs.size))
    T.ok(math.abs(fs.x - 34 * 0.1076) < .01, 'moved right 0.1076 of its size: ' .. tostring(fs.x))
  end,
}
