-- The kill bar over every dotted mob (KillPlates.lua): each enemy nameplate's health bar gets one stacked piece per
-- DoT, the one ending first nearest the green, scaled to the mob's max health (a hidden number in combat).
local function tocFiles()
  local files = {}
  for line in io.lines('OmaDoomed.toc') do
    if not line:match('^##') and line:match('%S') then files[#files + 1] = (line:gsub('\\', '/'):gsub('%s+$', '')) end
  end
  return files
end

local function setup(W)
  local F = require('fight'); F.start({ compare = false })
  local UI = require('ui'); UI.install()
  local made = {}                        -- every status bar made after load, with what it was told
  local realCreate = CreateFrame
  CreateFrame = function(kind, ...)
    local f = realCreate(kind, ...)
    if kind == 'StatusBar' then
      f.rec = { shown = false }
      f.SetValue = function(self, v) self.rec.value = v end
      f.SetMinMaxValues = function(self, a, b) self.rec.max = b end
      f.SetStatusBarColor = function(self, r, g, b) self.rec.color = { r, g, b } end
      f.Show = function(self) self.rec.shown = true end
      f.Hide = function(self) self.rec.shown = false end
      made[#made + 1] = f
    end
    return f
  end
  local ns = W.load('.', 'OmaDoomed', tocFiles(), {})
  W.fire('ADDON_LOADED', 'OmaDoomed'); W.fire('PLAYER_LOGIN'); W.fire('PLAYER_ENTERING_WORLD')
  F.mob('nameplate1', 'Creature-1', 'Darkhound', 300); F.mob('nameplate2', 'Creature-2', 'Darkhound', 200)
  local plates = {}
  for i = 1, 2 do
    local hb = UI.obj('healthBar'); hb.GetWidth = function() return 120 end
    local uf = UI.obj('UnitFrame'); uf.HealthBarsContainer = { healthBar = hb }
    plates['nameplate' .. i] = { UnitFrame = uf }
  end
  C_NamePlate.GetNamePlateForUnit = function(u) return plates[u] end
  local DOTS = {
    nameplate1 = { { name = 'Immolate', damage = 40, expiresAt = 9 }, { name = 'Corruption', damage = 30, expiresAt = 5 } },
    nameplate2 = {},
  }
  ns.parts.doomed.source = function(u) return DOTS[u] or {} end
  for i = #made, 1, -1 do made[i] = nil end   -- only what KillPlates makes from here on
  -- KillPlates makes, per piece, its bar then its Charging fill: pieces[k] / fills[k]
  local view = setmetatable({}, { __index = function(_, k) if k == 'count' then return #made / 2 end; return made[2 * k - 1] end })
  local fills = setmetatable({}, { __index = function(_, k) return made[2 * k] end })
  return ns, F, DOTS, view, fills
end

return {
  ['a dotted mob gets stacked pieces: ending first nearest the green, max health, colours'] = function(W, T)
    local ns, F, DOTS, made = setup(W)
    W.advance(.3)
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
    T.ok(ns.db.platebar == true, 'on by default')
    T.eq(made.count, 5, 'one set of five pieces, only for the dotted mob')
    T.ok(made[1].rec.shown and made[2].rec.shown, 'two pieces shown')
    T.ok(not made[3].rec.shown, 'the rest hidden')
    T.eq(made[1].rec.value, 30, 'piece 1: Corruption (ends first)')
    T.eq(made[2].rec.value, 70, 'piece 2: Corruption + Immolate')
    T.eq(made[1].rec.max, 300, 'scaled to max health')
    T.near(made[1].rec.color[1], 78 / 255, 1e-6, "Corruption's kill bar colour")
  end,
  ['in combat the max health is handed over hidden, never read'] = function(W, T)
    local ns, F, DOTS, made = setup(W)
    W.combat = true
    W.advance(.3)
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
    T.ok(issecretvalue(made[1].rec.max), 'max passed through as the hidden value')
  end,
  ['pieces go when the DoTs end, the mob dies, or the setting is off'] = function(W, T)
    local ns, F, DOTS, made = setup(W)
    W.advance(.3)
    DOTS.nameplate1 = {}
    W.advance(.3)
    T.ok(not made[1].rec.shown and not made[2].rec.shown, 'DoTs ended: pieces hidden')
    DOTS.nameplate1 = { { name = 'Corruption', damage = 30, expiresAt = 5 } }
    W.advance(.3); T.ok(made[1].rec.shown, 'back')
    W.units.nameplate1.dead = true
    W.advance(.3); T.ok(not made[1].rec.shown, 'dead mob: hidden')
    W.units.nameplate1.dead = false
    W.advance(.3); T.ok(made[1].rec.shown, 'back again')
    ns.db.platebar = false
    W.advance(.3); T.ok(not made[1].rec.shown, 'setting off: hidden')
  end,
  ['precast follows "While you cast": Charging fills with the cast bar, then lands without a snap'] = function(W, T)
    local ns, F, DOTS, made, fills = setup(W)
    ns.db.cast = 'charging'
    local t0 = W.now
    UnitCastingInfo = function() return 'Immolate', nil, nil, t0 * 1000, (t0 + 2) * 1000 end
    DOTS.nameplate1 = { { name = 'Corruption', damage = 30, expiresAt = 5 }, { name = 'Immolate', damage = 40, expiresAt = 99, provisional = true } }
    W.advance(1.0)
    T.ok(fills[2].rec.shown, 'Immolate fill shown while casting')
    T.near(fills[2].rec.value, 40 * .5, 2, 'halfway through the cast: half of its own piece, filled from its far edge toward the green')
    T.near(made[2].rec.color[1], 160 / 255 * .45, 1e-6, 'the piece itself sits dim')
    T.ok(not fills[1].rec.shown, 'Corruption (not being cast) has no fill')
    UnitCastingInfo = function() return nil end
    DOTS.nameplate1[2].provisional = false
    W.advance(.2)
    T.ok(not fills[2].rec.shown, 'landed: fill gone')
    T.near(made[2].rec.color[1], 160 / 255, 1e-6, 'and the piece is its full colour at once (the fill was already whole)')
  end,
  ['precast Smoulder: the piece rises out of the dark, no fill; eases to full as it lands'] = function(W, T)
    local ns, F, DOTS, made, fills = setup(W)
    ns.db.cast = 'smoulder'
    local t0 = W.now
    UnitCastingInfo = function() return 'Immolate', nil, nil, t0 * 1000, (t0 + 2) * 1000 end
    DOTS.nameplate1 = { { name = 'Immolate', damage = 40, expiresAt = 99, provisional = true } }
    W.advance(.3)
    local early = made[1].rec.color[1]
    W.advance(1.4)
    T.ok(made[1].rec.color[1] > early, 'brighter as the cast goes on')
    T.ok(not fills[1].rec.shown, 'no Charging fill')
    UnitCastingInfo = function() return nil end
    DOTS.nameplate1[1].provisional = false
    W.advance(.5)
    T.near(made[1].rec.color[1], 160 / 255, 1e-6, 'full colour after the ease')
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,
  ['precast Drifting stripes: piece dim, no Charging fill, no errors'] = function(W, T)
    local ns, F, DOTS, made, fills = setup(W)
    ns.db.cast = 'stripes'
    local t0 = W.now
    UnitCastingInfo = function() return 'Immolate', nil, nil, t0 * 1000, (t0 + 2) * 1000 end
    DOTS.nameplate1 = { { name = 'Immolate', damage = 40, expiresAt = 99, provisional = true } }
    W.advance(1)
    T.near(made[1].rec.color[1], 160 / 255 * .45, 1e-6, 'piece dim while casting')
    T.ok(not fills[1].rec.shown, 'no Charging fill')
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,
  ['precast Motes: piece dim, no Charging fill, no errors'] = function(W, T)
    local ns, F, DOTS, made, fills = setup(W)
    ns.db.cast = 'motes'
    local t0 = W.now
    UnitCastingInfo = function() return 'Immolate', nil, nil, t0 * 1000, (t0 + 2) * 1000 end
    DOTS.nameplate1 = { { name = 'Immolate', damage = 40, expiresAt = 99, provisional = true } }
    W.advance(1)
    T.near(made[1].rec.color[1], 160 / 255 * .45, 1e-6, 'piece dim while casting')
    T.ok(not fills[1].rec.shown, 'no Charging fill')
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,
  ['precast Plain: piece dim, no Charging fill, no errors'] = function(W, T)
    local ns, F, DOTS, made, fills = setup(W)
    ns.db.cast = 'plain'
    local t0 = W.now
    UnitCastingInfo = function() return 'Immolate', nil, nil, t0 * 1000, (t0 + 2) * 1000 end
    DOTS.nameplate1 = { { name = 'Immolate', damage = 40, expiresAt = 99, provisional = true } }
    W.advance(1)
    T.near(made[1].rec.color[1], 160 / 255 * .45, 1e-6, 'piece dim while casting')
    T.ok(not fills[1].rec.shown, 'no Charging fill')
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,
}
