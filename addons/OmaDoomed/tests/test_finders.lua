-- Finding the bars (PlateManager.lua, TargetFinder.lua): other add-ons' nameplates (Plater, EllesmereUI, Platynator,
-- Threat Plates, anything else by the automatic search), Blizzard's bar only when it really shows, the target frame
-- (Blizzard, EllesmereUI, a saved frame path, Pick), the hidden-bar rule, hostility changes, loading screens, and the
-- skull's whole-number step. The add-ons are fakes built from the frame names in their own code (not run here).
local A, B = 'Creature-0-1-0-1-100-AAAA', 'Creature-0-1-0-1-101-BBBB'
local FRAME = 1 / 30

local function noErrors(T) T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1])) end
local function dot(W, name, damage, lasts) return { name = name, damage = damage, expiresAt = W.now + lasts, appliedAt = W.now - 1, provisional = false } end

-- the add-on with rings, mobs on nameplate1 and 2 (plates not added yet), DoTs fed straight into the model
local function setup(W, o)
  o = o or {}
  local ns, F, UI = require('load').addon({ rings = true, before = o.before })
  W.advance(3)
  F.mob('nameplate1', A, 'Kobold', 300); F.mob('nameplate2', B, 'Gnoll', 300)
  local DOTS = { [A] = { dot(W, 'Corruption', 30, 12) }, [B] = { dot(W, 'Corruption', 30, 12) } }
  ns.model.source = function(u) local t = W.units[u]; return t and DOTS[t.guid] or {} end
  return ns, F, UI, DOTS
end
local function plate(token) return C_NamePlate.GetNamePlateForUnit(token) end
local function bar(UI, kind, parent, w)
  local b = UI.obj(kind or 'StatusBar'); b._type = 'StatusBar'; b._w, b._h = w or 100, 8
  if parent then b:SetParent(parent) end
  return b
end
local function add(W, ...) for _, t in ipairs({ ... }) do W.fire('NAME_PLATE_UNIT_ADDED', t) end end
-- the kill bar's clip frame on a health bar (KillPlates: a child of the bar that clips its children)
local function clipOn(UI, hb) for _, k in ipairs(UI.kids(hb)) do if rawget(k, 'kind') == 'Frame' then return k end end end
local function piecesShown(UI, hb)
  local c = clipOn(UI, hb); if not c then return 0 end
  local n = 0
  for _, k in ipairs(UI.kids(c)) do if rawget(k, 'kind') == 'StatusBar' and rawget(k, 'shown') ~= false and rawget(k, '_value') then n = n + 1 end end
  return n
end
-- the ring row for a token, wherever its host is
local function rowFor(UI, token)
  for _, c in ipairs(UI.ringContainers()) do if c.unit == token and UI.isVisible(c.parent ~= nil and c or c) then return c end end
end
local function rowUnder(UI, token, host)
  for _, c in ipairs(UI.ringContainers()) do if c.unit == token and UI.under(c, host) then return c end end
end
-- Blizzard's plate bar out of the way, the way plate add-ons do it
local function cutLoose(p) p.UnitFrame:SetParent(nil) end              -- Plater: un-parented, no anchors
local function hideBlizzard(p) p.UnitFrame:Hide() end                   -- others: hidden

return {
  ['Blizzard plates: Blizzard\'s bar, its own layer, rows on the plate as before'] = function(W, T)
    local ns, F, UI = setup(W)
    add(W, 'nameplate1'); W.advance(.5, FRAME)
    local b, host, source, addon, hidden = ns.plateBar(plate('nameplate1'), 'nameplate1')
    T.eq(source, 'Blizzard'); T.eq(addon, false); T.ok(not hidden)
    T.eq(b, plate('nameplate1').UnitFrame.HealthBarsContainer.healthBar, "Blizzard's health bar")
    T.ok(piecesShown(UI, b) > 0, 'kill bar pieces on it')
    T.eq(rawget(clipOn(UI, b), '_strata'), nil, 'no strata set on Blizzard bars (same as before)')
    T.ok(UI.rowOn('nameplate1'), 'a ring row on the plate')
    noErrors(T)
  end,

  ['Plater: its own bar (UIParent), pieces in its layer, rows on its unit frame'] = function(W, T)
    local ns, F, UI = setup(W)
    local p = plate('nameplate1'); cutLoose(p)
    local uf = UI.obj('PlaterUnitFrame'); uf:SetParent(UIParent)
    local hb = bar(UI, 'PlaterHealthBar', uf); hb:SetFrameStrata('LOW'); hb:SetFrameLevel(10)
    uf.healthBar = hb; p.unitFrame = uf; p.unitFramePlater = uf; Plater = {}
    add(W, 'nameplate1'); W.advance(.5, FRAME)
    local b, host, source, addon = ns.plateBar(p, 'nameplate1')
    T.eq(source, 'Plater'); T.eq(b, hb); T.eq(host, uf); T.ok(addon)
    local clip = clipOn(UI, hb)
    T.ok(clip, 'pieces on Plater\'s bar'); T.eq(clip._strata, 'LOW', 'its strata'); T.eq(clip._level, 12, 'just above its level')
    T.ok(piecesShown(UI, hb) > 0, 'pieces shown')
    T.eq(piecesShown(UI, p.UnitFrame.HealthBarsContainer.healthBar), 0, "nothing on Blizzard's cut-loose bar")
    local row = rowUnder(UI, 'nameplate1', uf)
    T.ok(row, 'the ring row rides Plater\'s unit frame'); T.eq(rawget(row, '_parent')._strata, 'LOW', 'in its strata')
    -- Plater lifts your target's plate: the pieces follow
    hb:SetFrameStrata('MEDIUM'); hb:SetFrameLevel(30); W.advance(.3, FRAME)
    T.eq(clip._strata, 'MEDIUM'); T.eq(clip._level, 32, 'followed the new layer')
    noErrors(T)
  end,

  ['Plater only when its frame differs from Blizzard\'s UnitFrame'] = function(W, T)
    local ns, F, UI = setup(W)
    local p = plate('nameplate1'); p.unitFrame = p.UnitFrame   -- the case a rival got wrong
    local _, _, source = ns.plateBar(p, 'nameplate1')
    T.eq(source, 'Blizzard')
  end,

  ['EllesmereUI: its plate by unit, bar .health'] = function(W, T)
    local ns, F, UI = setup(W)
    local p = plate('nameplate1'); hideBlizzard(p)
    local ep = UI.obj('EllesmerePlate'); ep:SetParent(p)
    local hb = bar(UI, 'EllesmereHealth', ep); hb:SetFrameStrata('MEDIUM'); hb:SetFrameLevel(5)
    ep.nameplate = p; ep.health = hb
    EllesmereNameplates_NS = { plates = { nameplate1 = ep } }
    add(W, 'nameplate1'); W.advance(.5, FRAME)
    local b, host, source = ns.plateBar(p, 'nameplate1')
    T.eq(source, 'EllesmereUI'); T.eq(b, hb); T.eq(host, ep)
    T.ok(piecesShown(UI, hb) > 0, 'pieces on its bar'); T.eq(clipOn(UI, hb)._strata, 'MEDIUM')
    T.ok(rowUnder(UI, 'nameplate1', ep), 'rows on its plate')
    noErrors(T)
  end,

  ['Platynator: its display under UIParent, matched by unit'] = function(W, T)
    local ns, F, UI = setup(W)
    local p = plate('nameplate1'); hideBlizzard(p)
    Platynator = {}
    local d = UI.obj('PlatyDisplay'); d:SetParent(UIParent)
    local hb = bar(UI, 'PlatyBar', d); hb:SetFrameStrata('MEDIUM')
    d.widgets = { { details = { kind = 'cast' }, statusBar = bar(UI) }, { details = { kind = 'health' }, statusBar = hb } }
    d.Install = function() end; d.SetUnit = function() end; d.unit = 'nameplate1'
    add(W, 'nameplate1'); W.advance(.5, FRAME)
    local b, host, source = ns.plateBar(p, 'nameplate1')
    T.eq(source, 'Platynator'); T.eq(b, hb); T.eq(host, p, 'widgets stay on the plate')
    T.ok(piecesShown(UI, hb) > 0, 'pieces on its bar')
    d.unit = 'nameplate7'
    local _, _, s2 = ns.plateBar(p, 'nameplate1')
    T.ok(s2 ~= 'Platynator', 'a display showing another unit is not ours')
    noErrors(T)
  end,

  ['Threat Plates: plate.TPFrame, active, .visual.Healthbar'] = function(W, T)
    local ns, F, UI = setup(W)
    local p = plate('nameplate1'); hideBlizzard(p)
    local tp = UI.obj('TPFrame'); tp:SetParent(WorldFrame)
    local hb = bar(UI, 'TPHealthbar', tp)
    tp.Active = true; tp.visual = { Healthbar = hb }; p.TPFrame = tp
    add(W, 'nameplate1'); W.advance(.5, FRAME)
    local b, host, source = ns.plateBar(p, 'nameplate1')
    T.eq(source, 'Threat Plates'); T.eq(b, hb)
    T.ok(piecesShown(UI, hb) > 0, 'pieces on its bar')
    tp.Active = false
    local _, _, s2, _, hidden = ns.plateBar(p, 'nameplate1')
    T.eq(s2, 'Blizzard (hidden)', 'inactive: not used'); T.ok(hidden)
    noErrors(T)
  end,

  ['anything else: the automatic search finds a shown "health" status bar inside the plate'] = function(W, T)
    local ns, F, UI = setup(W)
    local p = plate('nameplate1'); hideBlizzard(p)
    local kui = UI.obj('KuiFrame'); kui:SetParent(p)
    local hb = bar(UI, 'KuiBar', kui); kui.HealthBar = hb; p.kui = kui
    add(W, 'nameplate1'); W.advance(.5, FRAME)
    local b, _, source, addon = ns.plateBar(p, 'nameplate1')
    T.eq(source, 'found kui.HealthBar'); T.eq(b, hb); T.ok(addon)
    T.ok(piecesShown(UI, hb) > 0, 'pieces on it')
    noErrors(T)
  end,

  ['Blizzard\'s bar hidden and nothing else: no pieces drawn, rows keep Blizzard\'s place'] = function(W, T)
    local ns, F, UI = setup(W)
    local p = plate('nameplate1'); p.UnitFrame:SetAlpha(0)
    add(W, 'nameplate1'); W.advance(.5, FRAME)
    local b, _, source, addon, hidden = ns.plateBar(p, 'nameplate1')
    T.eq(source, 'Blizzard (hidden)'); T.ok(hidden); T.eq(addon, false)
    T.eq(piecesShown(UI, b), 0, 'nothing drawn on a see-through bar')
    T.ok(UI.rowOn('nameplate1'), 'the row still goes on the plate')
    p.UnitFrame:SetAlpha(1); W.advance(.5, FRAME)
    T.ok(piecesShown(UI, b) > 0, 'shown again: drawn')
    noErrors(T)
  end,

  ['reverse fill: pieces are mirrored on a bar that drains to the right'] = function(W, T)
    local ns, F, UI = setup(W)
    local p1, p2 = plate('nameplate1'), plate('nameplate2')
    for _, p in ipairs({ p1, p2 }) do
      hideBlizzard(p)
      local tp = UI.obj('TPFrame'); tp:SetParent(WorldFrame)
      tp.Active = true; tp.visual = { Healthbar = bar(UI, 'TPHealthbar', tp) }; p.TPFrame = tp
    end
    p2.TPFrame.visual.Healthbar:SetReverseFill(true)
    add(W, 'nameplate1', 'nameplate2'); W.advance(.5, FRAME)
    local function firstPiece(hb) for _, k in ipairs(UI.kids(clipOn(UI, hb))) do if rawget(k, 'kind') == 'StatusBar' then return k end end end
    local normal, mirrored = firstPiece(p1.TPFrame.visual.Healthbar), firstPiece(p2.TPFrame.visual.Healthbar)
    T.eq(normal:GetReverseFill(), true, 'normal bar: pieces fill leftward from the health\'s end')
    T.eq(mirrored:GetReverseFill(), false, 'mirrored bar: pieces fill rightward from the health\'s end')
    T.eq(rawget(mirrored, '_anchor'), p2.TPFrame.visual.Healthbar:GetStatusBarTexture(), 'pinned to its fill')
    noErrors(T)
  end,

  ['one bad plate never switches the plate bars off'] = function(W, T)
    local ns, F, UI = setup(W)
    local p1 = plate('nameplate1'); hideBlizzard(p1)
    local tp = UI.obj('TPFrame'); tp:SetParent(WorldFrame)
    local bad = bar(UI, 'TPHealthbar', tp); bad.GetStatusBarTexture = function() error('broken add-on bar') end
    tp.Active = true; tp.visual = { Healthbar = bad }; p1.TPFrame = tp
    add(W, 'nameplate1', 'nameplate2'); W.advance(1, FRAME)
    local good = plate('nameplate2').UnitFrame.HealthBarsContainer.healthBar
    T.ok(piecesShown(UI, good) > 0, 'the good plate is drawn')
    local errs = table.concat(OmaDoomedDB.errs or {}, '\n')
    T.ok(errs:find('broken add-on bar', 1, true), 'the bad one is logged')
    T.ok(not errs:find('paused', 1, true), 'nothing paused')
    for _, l in ipairs(W.printed) do T.ok(not l:find('paused until', 1, true), 'no pause line in chat') end
  end,

  ['hostility: plate bars follow a mob turning friendly and back'] = function(W, T)
    local ns, F, UI = setup(W)
    add(W, 'nameplate1'); W.advance(.5, FRAME)
    local hb = plate('nameplate1').UnitFrame.HealthBarsContainer.healthBar
    T.ok(piecesShown(UI, hb) > 0)
    W.units.nameplate1.enemy = false; W.fire('UNIT_FACTION', 'nameplate1'); W.advance(.3, FRAME)
    T.eq(piecesShown(UI, hb), 0, 'charmed: no pieces'); T.eq(UI.rowOn('nameplate1'), nil, 'and no row')
    W.units.nameplate1.enemy = true; W.fire('UNIT_FLAGS', 'nameplate1'); W.advance(.3, FRAME)
    T.ok(piecesShown(UI, hb) > 0, 'hostile again: pieces'); T.ok(UI.rowOn('nameplate1'), 'and the row')
  end,

  ['hostility hidden in combat: nothing changes'] = function(W, T)
    local ns, F, UI = setup(W)
    add(W, 'nameplate1'); W.advance(.5, FRAME)
    local real = UnitCanAttack
    UnitCanAttack = function() return W.secret(false) end
    W.fire('UNIT_FACTION', 'nameplate1'); W.advance(.3, FRAME)
    T.ok(UI.rowOn('nameplate1'), 'kept the row: we can\'t tell, so we don\'t guess')
    UnitCanAttack = real
    noErrors(T)
  end,

  ['a loading screen: the plates are rebuilt'] = function(W, T)
    local ns, F, UI = setup(W)
    add(W, 'nameplate1', 'nameplate2'); W.advance(.5, FRAME)
    -- through the loading screen nameplate2's mob left (no event said so) and a new mob took nameplate3
    W.units.nameplate2 = nil
    F.mob('nameplate3', 'Creature-0-1-0-1-102-CCCC', 'Murloc', 300)
    W.fire('PLAYER_ENTERING_WORLD'); W.advance(.5, FRAME)
    T.ok(ns.plates.live.nameplate1 and ns.plates.live.nameplate3, 'live: the plates that are there')
    T.eq(ns.plates.live.nameplate2, nil, 'the stale one is gone')
    T.ok(UI.rowOn('nameplate3'), 'the new mob has its row'); T.eq(UI.rowOn('nameplate2'), nil)
  end,

  ['/omadoomed plates says which bar each plate and the target frame use; the bug report carries it'] = function(W, T)
    local ns, F, UI = setup(W)
    local p = plate('nameplate2'); hideBlizzard(p)
    local tp = UI.obj('TPFrame'); tp:SetParent(WorldFrame); tp.Active = true; tp.visual = { Healthbar = bar(UI, 'TPHealthbar', tp) }; p.TPFrame = tp
    add(W, 'nameplate1', 'nameplate2'); W.advance(.5, FRAME)
    W.printed = {}
    SlashCmdList.OMADOOMED('plates')
    local out = table.concat(W.printed, '\n')
    T.ok(out:find('nameplate1: Blizzard', 1, true), out)
    T.ok(out:find('nameplate2: Threat Plates', 1, true), out)
    T.ok(out:find('target frame: Blizzard', 1, true), out)
    ns.saveReport('test')
    local r = OmaDoomedDB.reports[1]
    T.ok(r.bars and table.concat(r.bars, '\n'):find('nameplate2: Threat Plates', 1, true), 'in the saved report')
    for _, l in ipairs(W.printed) do T.ok(not l:find('Kobold', 1, true) and not l:find('Gnoll', 1, true), 'no names: ' .. l) end
  end,

  -- ---------- the target frame ----------
  ['target: Blizzard\'s frame, its 5 px margin and atlas shape'] = function(W, T)
    local ns, F, UI = setup(W)
    F.target(A); W.advance(.5, FRAME)
    local bar0, portrait, source, blizz = ns.targetBar()
    T.eq(source, 'Blizzard'); T.ok(blizz); T.eq(bar0, TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar)
    T.eq(ns.parts.doomed.blizz, true)
    noErrors(T)
  end,

  ['target: EllesmereUI\'s frame when Blizzard\'s is hidden; no margin, a plain shape, its layer'] = function(W, T)
    local points = {}
    local ns, F, UI = setup(W, { before = function()
      local real = CreateFrame
      CreateFrame = function(kind, name, parent, ...)
        local f = real(kind, name, parent, ...)
        if parent and rawget(parent, 'kind') == 'EllesmereHealth' and kind == 'Frame' then
          local sp = f.SetPoint
          rawset(f, 'SetPoint', function(self, p, rel, rp, x, y) points[#points + 1] = { p, x }; return sp(self, p, rel, rp, x, y) end)
        end
        return f
      end
    end })
    TargetFrame:Hide()
    local ef = CreateFrame('Frame', 'EllesmereUIUnitFrames_Target', UIParent)
    local hb = UI.obj('EllesmereHealth'); hb._type = 'StatusBar'; hb._w = 150; hb:SetParent(ef); hb:SetFrameStrata('MEDIUM'); hb:SetFrameLevel(8)
    local portrait = UI.obj('Texture'); portrait._w = 40; portrait:SetParent(ef)
    ef.Health = hb; ef.Portrait = portrait
    F.target(A); W.advance(.5, FRAME)
    local b, p, source, blizz = ns.targetBar()
    T.eq(source, 'EllesmereUI'); T.eq(b, hb); T.eq(p, portrait); T.ok(not blizz)
    T.eq(points[1] and points[1][1], 'TOPLEFT'); T.eq(points[1] and points[1][2], 0, 'its own margin: none (Blizzard\'s is 5 px)')
    local clip; for _, k in ipairs(UI.kids(hb)) do if rawget(k, 'kind') == 'Frame' then clip = k end end
    T.eq(clip._strata, 'MEDIUM'); T.eq(clip._level, 9)
    noErrors(T)
  end,

  ['target: a saved frame path (typed), found again after a reload'] = function(W, T)
    local ns, F, UI = setup(W)
    TargetFrame:Hide()
    local tf = CreateFrame('Frame', 'MyTargetFrame', UIParent)
    local hb = CreateFrame('StatusBar', nil, tf); hb._w = 140; tf.Bar = hb
    T.eq(ns.framePath(hb), 'MyTargetFrame.Bar', 'a path that leads back to the bar')
    SlashCmdList.OMADOOMED('frame MyTargetFrame.Bar')
    T.eq(ns.db.targetPath, 'MyTargetFrame.Bar', 'saved')
    F.target(A); W.advance(.5, FRAME)
    local b, _, source = ns.targetBar()
    T.eq(b, hb); T.eq(source, 'path MyTargetFrame.Bar')
    SlashCmdList.OMADOOMED('frame clear'); T.eq(ns.db.targetPath, '')
    noErrors(T)
  end,

  ['target: Pick, by mouse, out of combat only'] = function(W, T)
    local ns, F, UI = setup(W)
    local tf = CreateFrame('Frame', 'MyTargetFrame', UIParent)
    local hb = CreateFrame('StatusBar', nil, tf); tf.Bar = hb
    hb.GetRect = function() return 10, 10, 100, 20 end; hb.IsMouseOver = function() return true end
    tf.GetRect = function() return 0, 0, 200, 60 end; tf.IsMouseOver = function() return true end
    GetMouseFoci = function() return { hb } end
    W.combat = true; W.printed = {}
    ns.startPick()
    T.ok(table.concat(W.printed, ' '):find('out of combat only', 1, true), 'refused in combat')
    W.combat = false
    ns.startPick(); W.advance(.2, FRAME)
    W.fire('GLOBAL_MOUSE_DOWN', 'LeftButton')
    T.eq(ns.db.targetPath, 'MyTargetFrame.Bar', 'the clicked bar is saved by name')
    ns.startPick(); W.advance(.2, FRAME); W.fire('GLOBAL_MOUSE_DOWN', 'RightButton')
    T.eq(ns.db.targetPath, 'MyTargetFrame.Bar', 'right-click cancels')
    ns.startPick(); W.advance(.2, FRAME); W.combat = true; W.fire('PLAYER_REGEN_DISABLED')
    W.fire('GLOBAL_MOUSE_DOWN', 'LeftButton')
    T.ok(table.concat(W.printed, ' '):find('a fight started', 1, true), 'a fight cancels it')
    noErrors(T)
  end,

  ['target: the bar we would draw on is hidden while a target exists: nothing drawn, said once'] = function(W, T)
    local ns, F, UI, DOTS = setup(W)
    local tf = CreateFrame('Frame', 'MyTargetFrame', UIParent)
    local hb = CreateFrame('StatusBar', nil, tf); hb._w = 140; tf.Bar = hb
    ns.db.targetPath = 'MyTargetFrame.Bar'
    TargetFrame:Hide()
    F.target(A); W.advance(.5, FRAME)
    T.eq(ns.targetBar(), hb, 'on the picked bar')
    T.ok(ns.model.cur(), 'drawing')
    tf:Hide(); W.printed = {}
    W.advance(.2, FRAME)
    T.eq(ns.model.cur(), nil, 'hidden: nothing drawn, at once (not Blizzard\'s)')
    W.advance(2, FRAME)
    local n = 0; for _, l in ipairs(W.printed) do if l:find('is hidden', 1, true) then n = n + 1 end end
    T.eq(n, 1, 'said once')
  end,

  ['target: Blizzard\'s own frame hidden: half a second\'s grace, then nothing drawn and said once'] = function(W, T)
    local ns, F, UI, DOTS = setup(W)
    F.target(A); W.advance(.5, FRAME)
    T.ok(ns.model.cur(), 'drawing on Blizzard\'s')
    TargetFrame:Hide(); W.printed = {}
    W.advance(.2, FRAME); T.ok(ns.model.cur(), 'still drawing inside the grace (it is inside the hidden frame anyway)')
    W.advance(1, FRAME); T.eq(ns.model.cur(), nil, 'then nothing')
    W.advance(2, FRAME)
    local n = 0; for _, l in ipairs(W.printed) do if l:find('is hidden', 1, true) then n = n + 1 end end
    T.eq(n, 1, 'said once')
    TargetFrame:Show(); W.advance(.3, FRAME); T.ok(ns.model.cur(), 'back when it shows')
  end,

  ['target: a picked bar that fills from the right: nothing drawn, said once'] = function(W, T)
    local ns, F, UI = setup(W)
    TargetFrame:Hide()
    local tf = CreateFrame('Frame', 'MyTargetFrame', UIParent)
    local hb = CreateFrame('StatusBar', nil, tf); hb:SetReverseFill(true); tf.Bar = hb
    ns.db.targetPath = 'MyTargetFrame.Bar'; W.printed = {}
    F.target(A); W.advance(2, FRAME)
    T.eq(ns.model.cur(), nil)
    local n = 0; for _, l in ipairs(W.printed) do if l:find('fills from the right', 1, true) then n = n + 1 end end
    T.eq(n, 1)
  end,

  -- ---------- the skull ----------
  ['skull: today\'s size at 1080p; whole-number steps from the portrait\'s size on screen'] = function(W, T)
    local function skullAt(h)
      local ns, F, UI = require('load').addon({ before = function() GetPhysicalScreenSize = function() return h * 16 / 9, h end end })
      GetPhysicalScreenSize = function() return h * 16 / 9, h end
      F.mob('nameplate1', A, 'Kobold', 100); F.target(A)
      ns.model.source = function() return { dot(W, 'Corruption', 30, 12) } end
      W.advance(.5, FRAME)
      for _, k in ipairs(UI.kids(TargetFrame.TargetFrameContainer)) do if rawget(k, '_strata') == 'HIGH' then return k._w, k._h end end
    end
    local w, hgt = skullAt(1080)
    T.eq(w, 78 * 768 / 1080, '1080p: 78 screen px, exactly as before'); T.eq(hgt, 54 * 768 / 1080)
    local w4 = skullAt(2160)
    T.near(w4, 2 * 78 * 768 / 2160, 1e-9, '4K: twice the pixels (the portrait is twice as big on screen)')
    local w2 = skullAt(1440)
    T.near(w2, 78 * 768 / 1440, 1e-9, '1440p: still x1 (1.33 rounds to 1: whole steps keep the pixel art crisp)')
  end,
}
