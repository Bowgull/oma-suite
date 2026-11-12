-- The kill bar over every dotted mob (sheet 41, "I should be able to see the dots in the enemy bar
-- above the actual enemy"). Each enemy nameplate's health bar shows the health your DoTs will still take, in each
-- DoT's colour, at the end of its health: the same pieces as the target frame, without the slide and the skull.
--
-- Forever hides health in combat, so nothing here reads a size. Each piece is measured by an invisible
-- reverse-filling status bar pinned to the end of Blizzard's own fill, scaled 0..max health (a hidden number may be
-- handed to a status bar), stacked: bar k holds the damage of DoTs 1..k, the one ending first nearest the green. What
-- shows is the fill's own art, cut between two of those edges (piecesFor). It never draws past the health bar.
-- Which plates and which bar: PlateManager.lua (live enemy plates; Blizzard's bar or another add-on's, e.g. Plater).
-- Colours and cast looks: KillBarStyle.lua, the same as the target bar's.
-- When: the model's DOTS (10 times a second and on every change) and the plates' own events, at most once a frame,
-- over the live plates only; a value is handed to a bar only when it changed. Each plate is drawn in its own error
-- guard: one odd plate never switches the others off.
local ADDON, ns = ...
local K = {}; ns.parts.platebar = K
local Spells, Secret, Style = ns.spells, ns.core.Secret, ns.killStyle
local PM = ns.plates

local MAX = 5
local TEX = 'Interface\\TargetingFrame\\UI-StatusBar'
local SMOOTH = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local made = setmetatable({}, { __mode = 'k' })   -- health bar -> its pieces (plate frames are reused between mobs)
local shown = {}                                   -- health bar -> true while it shows pieces
local foundLogged
local charging = {}                                -- precast fills and landing eases, moved every frame
local look, ask = Style.new(), {}                  -- the style's answer and question (reused)
local list, seenName = {}, {}                      -- one plate's DoTs (reused)

-- setters that skip a call changing nothing (our own bars and textures); a measuring bar shows with its piece
local function show(t, v)
  if t.omShown ~= v then t.omShown = v; if v then t:Show() else t:Hide() end end
  local art = rawget(t, "omArt"); if art then show(art, v) end
end
local texColor
local function barColor(b, r, g, bl) texColor(b.omArt, r, g, bl, 1) end   -- a piece's colour is its texture's
function texColor(t, r, g, b, a)
  if t.omR ~= r or t.omG ~= g or t.omB ~= b or t.omA ~= a then t.omR, t.omG, t.omB, t.omA = r, g, b, a; if a then t:SetVertexColor(r, g, b, a) else t:SetVertexColor(r, g, b) end end
end
local function plain(v) return type(v) == 'number' and not Secret.is(v) end
-- width, max health and value of one bar; max health may be hidden (then always handed over, never compared)
local function setBar(b, w, maxv, v)
  if not (plain(w) and b.omW == w) then b.omW = plain(w) and w or nil; b:SetWidth(w) end
  local newMax = not (plain(maxv) and b.omMax == maxv)
  if newMax then b.omMax = plain(maxv) and maxv or nil; b:SetMinMaxValues(0, maxv) end
  if newMax or b.omV ~= v then b.omV = v; if SMOOTH then b:SetValue(v, SMOOTH) else b:SetValue(v) end end
end

-- How a piece is built (Blizzard's own heal-prediction segments, StatusBarOverlaySegment.lua UpdateFillPosition):
-- the visible piece is a texture inside the health bar, in the fill's own art (its atlas or file) laid over the whole
-- bar one sublevel above the fill, so its shape, inset and rim are the fill's at any UI scale. A square mask shows
-- only this piece's stretch. Blizzard sizes that mask with amount / max x width; max health is hidden in combat, so
-- here an invisible reverse-filling status bar per piece does that sum (a status bar takes hidden numbers) and the
-- mask is pinned to its fill's edges, which ride the health fill: top and bottom are the fill texture's.
local function edge(reversed, side) if reversed then return side == 'near' and 'LEFT' or 'RIGHT' end; return side == 'near' and 'RIGHT' or 'LEFT' end
local function artOf(fill)
  local okA, atlas = false, nil
  if fill.GetAtlas then okA, atlas = pcall(fill.GetAtlas, fill) end
  if okA and type(atlas) == 'string' and atlas ~= '' then return atlas, true end
  local okT, file = false, nil
  if fill.GetTexture then okT, file = pcall(fill.GetTexture, fill) end
  if okT and (type(file) == 'string' or type(file) == 'number') and file ~= '' then return file, false end
  return TEX, false
end

-- reversed: another add-on's bar whose health drains to the right, so every piece is mirrored
local function piecesFor(hb, addon, reversed)
  local set = made[hb]; if set then return set end
  local fill = hb:GetStatusBarTexture(); if type(fill) ~= 'table' then return nil end
  set = { fill = fill, addon = addon, reversed = reversed }
  -- the measuring bars: invisible, they only give the pieces their edges
  set.rulers = CreateFrame('Frame', nil, hb); set.rulers:SetAllPoints(hb); set.rulers:SetAlpha(0)
  local art, isAtlas = artOf(fill)
  local okL, layerName, sub = pcall(fill.GetDrawLayer, fill)
  if not okL or type(layerName) ~= 'string' then layerName, sub = 'ARTWORK', 0 end
  sub = type(sub) == 'number' and sub or 0
  local function lv(k) return math.min(7, sub + k) end
  local function ruler(from)
    local b = CreateFrame('StatusBar', nil, set.rulers)
    b:SetStatusBarTexture(TEX); b:SetMinMaxValues(0, 1); b:SetValue(0)
    local near = edge(reversed, 'near')
    if from then   -- grows away from the green, from a piece's far edge
      b:SetReverseFill(reversed and true or false)
      local far = edge(reversed, 'far')
      b:SetPoint('TOP' .. far, from, 'TOP' .. far); b:SetPoint('BOTTOM' .. far, from, 'BOTTOM' .. far)
    else           -- grows from the health's end
      b:SetReverseFill(not reversed)
      b:SetPoint('TOP' .. near, fill, 'TOP' .. near); b:SetPoint('BOTTOM' .. near, fill, 'BOTTOM' .. near)
    end
    b:Hide(); b.omShown = false
    return b
  end
  -- a texture in the fill's art over the whole bar: top and bottom from the fill, the sides from the bar
  local function paintTex(k, mask)
    local t = hb:CreateTexture(nil, layerName, nil, lv(k))
    if isAtlas then t:SetAtlas(art, false) else t:SetTexture(art) end
    if t.SetDesaturated then t:SetDesaturated(true) end
    t:SetPoint('TOP', fill, 'TOP'); t:SetPoint('BOTTOM', fill, 'BOTTOM')
    t:SetPoint('LEFT', hb, 'LEFT'); t:SetPoint('RIGHT', hb, 'RIGHT')
    t:AddMaskTexture(mask); t:Hide(); t.omShown = false
    return t
  end
  local function newMask() local m = hb:CreateMaskTexture(); m:SetTexture('Interface\\Buttons\\WHITE8X8', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE'); return m end
  set.charge, set.ov, set.mask = {}, {}, {}
  local near, far = edge(reversed, 'near'), edge(reversed, 'far')
  for i = 1, MAX do
    local b = ruler(); set[i] = b
    -- piece i: from its ruler's far edge to piece i-1's far edge (piece 1: the health's end)
    local m = newMask(); set.mask[i] = m
    local here = b:GetStatusBarTexture()
    local prev = i == 1 and fill or set[i - 1]:GetStatusBarTexture()
    local prevSide = i == 1 and near or far
    m:SetPoint('TOP' .. far, here, 'TOP' .. far); m:SetPoint('BOTTOM' .. near, prev, 'BOTTOM' .. prevSide)
    b.omArt = paintTex(1, m)
    -- Charging: fills over this piece in its landed colour from its far edge toward the green, as on the target frame
    local ch = ruler(here)
    local cm = newMask()
    local cTex = ch:GetStatusBarTexture()
    cm:SetPoint('TOP' .. far, cTex, 'TOP' .. far); cm:SetPoint('BOTTOM' .. near, cTex, 'BOTTOM' .. near)
    ch.omArt = paintTex(2, cm)
    set.charge[i] = ch
    -- Drifting stripes / Motes: laid across the whole bar (its width is known) and cut by the piece's own mask
    local ov = {}
    ov.pre = hb:CreateTexture(nil, layerName, nil, lv(4)); ov.pre:SetTexture('Interface/RaidFrame/Shield-Overlay', 'REPEAT', 'REPEAT')
    ov.pre:SetDesaturated(true); ov.pre:SetBlendMode('ADD')
    ov.motes = hb:CreateTexture(nil, layerName, nil, lv(3)); ov.motes:SetTexture('Interface\\AddOns\\OmaDoomed\\Art\\motes', 'REPEAT', 'REPEAT'); ov.motes:SetBlendMode('ADD')
    for _, t in ipairs({ ov.pre, ov.motes }) do
      t:SetPoint('TOP', fill, 'TOP'); t:SetPoint('BOTTOM', fill, 'BOTTOM'); t:SetPoint('LEFT', hb, 'LEFT'); t:SetPoint('RIGHT', hb, 'RIGHT')
      t:AddMaskTexture(m); t:Hide(); t.omShown = false
    end
    set.ov[i] = ov
  end
  made[hb] = set
  return set
end

local function quietSlot(set, i)
  show(set.charge[i], false); show(set.ov[i].pre, false); show(set.ov[i].motes, false); charging[set[i]] = nil
end
local function clear(hb) local set = made[hb]; if set then for i = 1, MAX do show(set[i], false); quietSlot(set, i) end end; shown[hb] = nil end

-- the style of a plate piece: no gold (the plate bars never had it), the cast look and progress, or a landing
local function styleOf(sp, provisional, lk, pr, landAge, landLook)
  ask.left, ask.low, ask.steady = nil, 3, false
  ask.provisional, ask.look, ask.pr = provisional, lk, pr
  ask.landAge, ask.landLook, ask.light, ask.quiet = landAge, landLook, nil, nil
  return Style.piece(look, sp, ask)
end

-- every frame: what moves with your cast bar ('While you cast', the same setting as the target frame), and the
-- ease to full colour as a cast lands (no snap)
local function chargeOne(b, c, now)
  if c.landAt then
    local o = styleOf(c.sp, false, nil, nil, now - c.landAt, c.look)
    barColor(b, o.base[1], o.base[2], o.base[3])
    if not o.animating then charging[b] = nil end
  else
    local pr = math.max(0, math.min(1, (now - c.s) / (c.e - c.s)))
    if c.look == 'charging' then c.ch:SetValue(c.dmg * pr)
    elseif c.look == 'smoulder' then local o = styleOf(c.sp, true, 'smoulder', pr); barColor(b, o.base[1], o.base[2], o.base[3])
    elseif c.look == 'stripes' then
      local bw, bh = c.hb:GetWidth(), c.hb:GetHeight(); local o = Style.stripesAt(now)
      c.ov.pre:SetTexCoord(o, o + bw / 24, 0, math.max(.01, bh / 24))
    elseif c.look == 'motes' then
      local bw = c.hb:GetWidth(); local o = Style.motesAt(now)
      c.ov.motes:SetTexCoord(o, o + bw / 128 * 2, 0, 1)
    end
  end
end
local function chargeStep()
  if next(charging) == nil then return end
  local now = GetTime()
  for b, c in pairs(charging) do
    local ok, err = pcall(chargeOne, b, c, now)
    if not ok then charging[b] = nil; ns.error('platebar charge: ' .. tostring(err)) end   -- that piece only
  end
end

local function paint(unit)
  local found = PM.barOf(unit)
  local hb = found and found.bar
  if not hb or found.hidden then   -- no bar on screen: nothing to draw on (Blizzard's only if it really shows)
    if not hb and not foundLogged then foundLogged = true; ns.err('platebar: no health bar on the nameplate') end
    return nil
  end
  -- the model's list for this plate: one entry per DoT with damage left, the one ending first nearest the green
  local ok = pcall(ns.model.listInto, unit, true, list, seenName)
  if not ok then wipe(list) end
  if #list == 0 then if shown[hb] then clear(hb) end; return hb end
  local set = piecesFor(hb, found.addon, found.addon and PM.reversed(hb)); if not set then return hb end
  local w = hb:GetWidth()
  local maxv = UnitHealthMax(unit)
  -- precast ("I don't see the precast" on these bars; "whatever look I chose from settings"):
  -- while you cast a DoT at this mob its piece shows your 'While you cast' look, as on the target frame
  local cName, _, _, cStart, cEnd = UnitCastingInfo('player')
  local lk = ns.db.cast or 'charging'
  local sum = 0
  for i = 1, MAX do
    local b, ch, d = set[i], set.charge[i], list[i]
    if d then
      sum = sum + d.damage
      setBar(b, w, maxv, sum)
      local sp = Spells.dot(d.name)
      local casting = d.provisional and cName == d.name and cStart and cEnd and cEnd > cStart
      local ov, st = set.ov[i], charging[b]
      if casting then
        if not (st and not st.landAt and st.name == d.name) then
          st = { name = d.name, sp = sp, look = lk, hb = hb, ov = ov, ch = ch }
          charging[b] = st
        end
        st.dmg, st.s, st.e = d.damage, cStart / 1000, cEnd / 1000
        local o = styleOf(sp, true, lk, 0)
        if lk ~= 'smoulder' then barColor(b, o.base[1], o.base[2], o.base[3]) end
        if lk == 'charging' then
          setBar(ch, w, maxv, ch.omV or 0); barColor(ch, o.fill[1], o.fill[2], o.fill[3])   -- its landed colour: landing changes nothing
        end
        show(ch, lk == 'charging')
        if lk == 'stripes' then texColor(ov.pre, o.tn[1], o.tn[2], o.tn[3], Style.STRIPES_A) end
        if lk == 'motes' then texColor(ov.motes, o.tn[1] * Style.MOTES_K, o.tn[2] * Style.MOTES_K, o.tn[3] * Style.MOTES_K) end
        show(ov.pre, lk == 'stripes'); show(ov.motes, lk == 'motes')
      else
        show(ch, false); show(ov.pre, false); show(ov.motes, false)
        if st and not st.landAt then   -- it landed: Charging's fill was already whole; the other looks ease up
          st.landAt = GetTime()
          chargeOne(b, st, st.landAt)
        elseif not st then local o = styleOf(sp, false); barColor(b, o.base[1], o.base[2], o.base[3]) end
      end
      show(b, true)
    else show(b, false); quietSlot(set, i) end
  end
  shown[hb] = true
  return hb
end

local dirty = true
local live = {}
local function refresh()
  if not (ns.db and ns.db.doomed and ns.db.platebar) then
    for hb in pairs(shown) do clear(hb) end; return
  end
  wipe(live)
  -- the live enemy plates (PlateManager); each in its own guard, so one odd plate never stops the others
  for u in pairs(PM.live) do
    if PM.enemy[u] and not UnitIsDead(u) then
      local ok, hb = pcall(paint, u)
      if ok then if hb then live[hb] = true end
      else ns.error('platebar: ' .. u .. ': ' .. tostring(hb)) end
    end
  end
  for hb in pairs(shown) do if not live[hb] then pcall(clear, hb) end end   -- plates that left, died or changed mob
end

function K.setOf(hb) return made[hb] end   -- tests and /omadoomed plates

function K.start()
  if select(2, UnitClass('player')) ~= 'WARLOCK' then return end
  local function again() dirty = true end
  for _, e in ipairs({ 'DOTS', 'PLATE_ADDED', 'PLATE_REMOVED', 'PLATE_CHANGED' }) do ns.bus:On(e, again) end
  ns.bus:On('SETTING', function(_, store) if store ~= 'rings' then dirty = true end end)
  local off = false
  local f = CreateFrame('Frame')
  f:SetScript('OnUpdate', function()
    if off then return end
    local ok, err = true, nil
    if dirty then dirty = false; ok, err = pcall(refresh) end
    if ok then ok, err = pcall(chargeStep) end
    if not ok then ns.fail('platebar: ' .. tostring(err), 'the kill bar over enemies'); off = true; for hb in pairs(shown) do pcall(clear, hb) end end   -- off for this session only
  end)
end
