-- The kill bar over every dotted mob (KillPlates.lua): each enemy nameplate's health bar gets one stacked piece per
-- DoT, the one ending first nearest the green, scaled to the mob's max health (a hidden number in combat).
local function tocFiles()
  local files = {}
  for line in io.lines('OmaDoomed.toc') do
    if not line:match('^##') and line:match('%S') and not line:match('%.xml%s*$') then files[#files + 1] = (line:gsub('\\', '/'):gsub('%s+$', '')) end
  end
  return files
end

-- a piece's colour: its texture's (the status bar only measures)
local function col(p) return rawget(rawget(p, 'omArt'), '_r') end

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
    local plate = UI.obj('NamePlate'); plate:SetParent(WorldFrame)
    local hb = UI.obj('healthBar'); hb.GetWidth = function() return 120 end
    local uf = UI.obj('UnitFrame'); uf:SetParent(plate); hb:SetParent(uf); uf.HealthBarsContainer = { healthBar = hb }
    plate.UnitFrame = uf
    plates['nameplate' .. i] = plate
  end
  C_NamePlate.GetNamePlateForUnit = function(u) return plates[u] end
  W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate2')
  local DOTS = {
    nameplate1 = { { name = 'Immolate', damage = 40, expiresAt = 9 }, { name = 'Corruption', damage = 30, expiresAt = 5 } },
    nameplate2 = {},
  }
  ns.model.source = function(u) return DOTS[u] or {} end
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
    -- phase 5: the plate pieces take the target bar's landed strength (x1.15, KillBarStyle), the one approved change
    T.near(col(made[1]), 41 / 255 * 1.15, 1e-6, "Corruption's kill bar colour, as on the target bar")
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
    T.near(col(made[2]), 160 / 255 * .45, 1e-6, 'the piece itself sits dim')
    T.ok(not fills[1].rec.shown, 'Corruption (not being cast) has no fill')
    UnitCastingInfo = function() return nil end
    DOTS.nameplate1[2].provisional = false
    W.advance(.2)
    T.ok(not fills[2].rec.shown, 'landed: fill gone')
    T.near(col(made[2]), 160 / 255 * 1.15, 1e-6, 'and the piece is its full colour at once (the fill was already whole)')
  end,
  ['precast Smoulder: the piece rises out of the dark, no fill; eases to full as it lands'] = function(W, T)
    local ns, F, DOTS, made, fills = setup(W)
    ns.db.cast = 'smoulder'
    local t0 = W.now
    UnitCastingInfo = function() return 'Immolate', nil, nil, t0 * 1000, (t0 + 2) * 1000 end
    DOTS.nameplate1 = { { name = 'Immolate', damage = 40, expiresAt = 99, provisional = true } }
    W.advance(.3)
    local early = col(made[1])
    W.advance(1.4)
    T.ok(col(made[1]) > early, 'brighter as the cast goes on')
    T.ok(not fills[1].rec.shown, 'no Charging fill')
    UnitCastingInfo = function() return nil end
    DOTS.nameplate1[1].provisional = false
    W.advance(.5)
    T.near(col(made[1]), 160 / 255 * 1.15, 1e-6, 'full colour after the ease')
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,
  ['precast Drifting stripes: piece dim, no Charging fill, no errors'] = function(W, T)
    local ns, F, DOTS, made, fills = setup(W)
    ns.db.cast = 'stripes'
    local t0 = W.now
    UnitCastingInfo = function() return 'Immolate', nil, nil, t0 * 1000, (t0 + 2) * 1000 end
    DOTS.nameplate1 = { { name = 'Immolate', damage = 40, expiresAt = 99, provisional = true } }
    W.advance(1)
    T.near(col(made[1]), 160 / 255 * .45, 1e-6, 'piece dim while casting')
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
    T.near(col(made[1]), 160 / 255 * .45, 1e-6, 'piece dim while casting')
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
    T.near(col(made[1]), 160 / 255 * .45, 1e-6, 'piece dim while casting')
    T.ok(not fills[1].rec.shown, 'no Charging fill')
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,
  ['built like Blizzard\'s segments: the fill\'s own art inside the bar, top and bottom from the fill texture'] = function(W, T)
    local ns, F, DOTS, made, fills = setup(W)
    local hb = C_NamePlate.GetNamePlateForUnit('nameplate1').UnitFrame.HealthBarsContainer.healthBar
    local fill = hb:GetStatusBarTexture()
    rawset(fill, 'GetAtlas', function() return 'UI-HUD-CoolDownManager-Bar' end)
    rawset(fill, 'GetDrawLayer', function() return 'ARTWORK', 0 end)
    W.combat = true   -- max health hidden: the build must not need it
    W.advance(.3)
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
    local set = ns.parts.platebar.setOf(hb)
    T.ok(set, 'pieces made for the bar')
    for i = 1, 5 do
      for _, art in ipairs({ set[i].omArt, set.charge[i].omArt, set.ov[i].pre, set.ov[i].motes }) do
        local pts = rawget(art, '_pts')
        T.ok(pts.TOP[1] == fill and pts.BOTTOM[1] == fill, 'piece ' .. i .. ': top and bottom are the fill texture\'s')
        T.ok(pts.LEFT[1] == hb and pts.RIGHT[1] == hb, 'piece ' .. i .. ': the sides are the bar\'s (the mask cuts it)')
        T.ok(rawget(art, '_parent') == hb, 'piece ' .. i .. ': inside the health bar')
        T.eq(#rawget(art, '_masks'), 1, 'piece ' .. i .. ': one square mask, no bar-wide stencil')
        -- 2026-11-13 'gaps between the bars': a smoothly filtered mask fades over width/16 at each end and the red shows
        T.eq(rawget(rawget(art, '_masks')[1], '_filter'), 'NEAREST', 'piece ' .. i .. ': its mask has hard edges')
      end
      T.eq(rawget(set[i].omArt, '_atlas'), 'UI-HUD-CoolDownManager-Bar', 'piece ' .. i .. ': the fill\'s own atlas')
      -- the mask hangs on measuring bars that ride the fill: their top and bottom are the fill's too
      local rp = rawget(set[1], '_pts')
      T.ok(rp.TOPRIGHT[1] == fill and rp.BOTTOMRIGHT[1] == fill, 'piece 1 measures from the fill\'s end')
    end
    T.ok(issecretvalue(made[1].rec.max), 'max health handed over hidden, never used in sums')
  end,
}
