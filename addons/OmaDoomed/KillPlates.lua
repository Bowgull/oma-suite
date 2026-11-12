-- The kill bar over every dotted mob (sheet 41, "I should be able to see the dots in the enemy bar
-- above the actual enemy"). Each enemy nameplate's health bar shows the health your DoTs will still take, in each
-- DoT's colour, at the end of its health: the same pieces as the target frame, without the slide and the skull.
--
-- Forever hides health in combat, so nothing here reads a size. Each piece is a reverse-filling status bar pinned to
-- the end of Blizzard's own fill, scaled 0..max health (a hidden number may be handed to a status bar), and the
-- pieces are stacked: piece k shows the damage of DoTs 1..k, the one ending first nearest the green. Clipped to the
-- health bar so nothing runs past its left end.
local ADDON, ns = ...
local K = {}; ns.parts.platebar = K

local MAX = 5
local TEX = 'Interface\\TargetingFrame\\UI-StatusBar'
local SMOOTH = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local made = setmetatable({}, { __mode = 'k' })   -- health bar -> its pieces (plate frames are reused between mobs)
local shown = {}                                   -- health bar -> true while it shows pieces
local foundLogged
local charging = {}                                -- precast fills, moved every frame so they glide with the cast bar

local function healthBarOf(plate)
  local uf = plate and plate.UnitFrame; if not uf then return nil end
  local c = uf.HealthBarsContainer
  local hb = (c and (c.healthBar or c.HealthBar)) or uf.healthBar
  if hb and hb.GetStatusBarTexture then return hb end
end

local function piecesFor(hb)
  local set = made[hb]; if set then return set end
  local fill = hb:GetStatusBarTexture(); if not fill then return nil end
  set = { clip = CreateFrame('Frame', nil, hb), fill = fill }
  set.clip:SetAllPoints(hb); set.clip:SetClipsChildren(true); set.clip:SetFrameLevel(hb:GetFrameLevel() + 2)
  -- 2026-11-11 ("spilling over just a little"; measured, OmaDoomedDB.plateGeo): Blizzard's fill is the atlas
  -- UI-HUD-CoolDownManager-Bar (ARTWORK 0 of the health bar), whose own shape is inset with soft ends; our pieces were
  -- a plain square texture filling the whole bar box, so they showed past that shape onto the border's inner edge.
  -- The fix is the fill's own shape as a stencil (below).
  local okA, atlas = false, nil
  if type(fill) == 'table' and fill.GetAtlas then okA, atlas = pcall(fill.GetAtlas, fill) end
  if not okA or type(atlas) ~= 'string' or atlas == '' then atlas = nil end
  set.atlas = atlas
  -- 2026-11-11 (2): drawing each piece WITH the atlas stretched the whole bar, round ends and all, over every piece
  -- ("pills"). Now the pieces are plain and square, so they meet cleanly, and each is cut by a stencil of the fill's
  -- own atlas laid over the whole health bar: only the bar's real ends are round, exactly where Blizzard's are.
  local function bar(level, from)
    local b = CreateFrame('StatusBar', nil, set.clip)
    b:SetStatusBarTexture(TEX); b:SetMinMaxValues(0, 1); b:SetValue(0)
    local t = b:GetStatusBarTexture(); if type(t) == "table" and t.SetDesaturated then t:SetDesaturated(true) end
    if atlas and type(t) == 'table' and t.AddMaskTexture then
      local m = b:CreateMaskTexture(); m:SetAllPoints(hb)
      if pcall(m.SetAtlas, m, atlas) then t:AddMaskTexture(m) end
    end
    if from then   -- fills rightward from a piece's far edge
      b:SetPoint('TOPLEFT', from, 'TOPLEFT'); b:SetPoint('BOTTOMLEFT', from, 'BOTTOMLEFT')
    else           -- fills leftward from the health's end
      b:SetReverseFill(true); b:SetPoint('TOPRIGHT', fill, 'TOPRIGHT'); b:SetPoint('BOTTOMRIGHT', fill, 'BOTTOMRIGHT')
    end
    b:SetFrameLevel(level); b:Hide()
    return b
  end
  set.charge, set.ov = {}, {}
  for i = 1, MAX do
    local lv = set.clip:GetFrameLevel() + 2 * (MAX - i)   -- the piece nearest the green on top
    set[i] = bar(lv)
    -- Charging: fills over this piece in its landed colour from its far edge toward the green, the same way as the
    -- target frame ("why is precast charge two different directions?")
    local far = set[i]:GetStatusBarTexture()
    set.charge[i] = bar(lv + 1, type(far) == 'table' and far or nil)
    -- Drifting stripes / Motes: laid across the whole bar (its width is known) and cut to this piece by a stencil
    -- hung on the piece's two edges (a piece's own width is hidden in combat), as on the target frame
    local ov = CreateFrame('Frame', nil, set.clip); ov:SetAllPoints(hb); ov:SetFrameLevel(lv + 1)
    ov.pre = ov:CreateTexture(nil, 'ARTWORK', nil, 4); ov.pre:SetTexture('Interface/RaidFrame/Shield-Overlay', 'REPEAT', 'REPEAT')
    ov.pre:SetDesaturated(true); ov.pre:SetBlendMode('ADD')
    ov.motes = ov:CreateTexture(nil, 'ARTWORK', nil, 3); ov.motes:SetTexture('Interface\\AddOns\\OmaDoomed\\Art\\motes', 'REPEAT', 'REPEAT'); ov.motes:SetBlendMode('ADD')
    ov.mask = ov:CreateMaskTexture(); ov.mask:SetTexture('Interface\\Buttons\\WHITE8X8', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
    for _, t in ipairs({ ov.pre, ov.motes }) do t:SetAllPoints(hb); t:AddMaskTexture(ov.mask); t:Hide() end
    if atlas then   -- and cut to the bar's own shape too, like the pieces
      ov.shape = ov:CreateMaskTexture(); ov.shape:SetAllPoints(hb)
      if pcall(ov.shape.SetAtlas, ov.shape, atlas) then ov.pre:AddMaskTexture(ov.shape); ov.motes:AddMaskTexture(ov.shape) end
    end
    set.ov[i] = ov
  end
  -- stencil i: from piece i's far edge to piece i-1's far edge (piece 1: the health's end)
  for i = 1, MAX do
    local m, here = set.ov[i].mask, set[i]:GetStatusBarTexture()
    local near = i == 1 and fill or set[i - 1]:GetStatusBarTexture()
    if type(here) == 'table' and type(near) == 'table' then
      m:SetPoint('TOPLEFT', here, 'TOPLEFT'); m:SetPoint('BOTTOMRIGHT', near, i == 1 and 'BOTTOMRIGHT' or 'BOTTOMLEFT')
    end
  end
  made[hb] = set
  return set
end

local function quietSlot(set, i)
  set.charge[i]:Hide(); set.ov[i].pre:Hide(); set.ov[i].motes:Hide(); charging[set[i]] = nil
end
local function clear(hb) local set = made[hb]; if set then for i = 1, MAX do set[i]:Hide(); quietSlot(set, i) end end; shown[hb] = nil end
-- every frame: what moves with your cast bar ('While you cast', the same setting as the target frame), and the
-- 0.3 s ease to full colour as a cast lands (no snap)
local function chargeStep()
  local now = GetTime()
  for b, c in pairs(charging) do
    local col = c.col
    if c.landAt then
      local v = math.min(1, (now - c.landAt) / .3); local k = .45 + .55 * v * v * (3 - 2 * v)
      b:SetStatusBarColor(col[1] * k, col[2] * k, col[3] * k, 1)
      if v >= 1 then charging[b] = nil end
    else
      local pr = math.max(0, math.min(1, (now - c.s) / (c.e - c.s)))
      if c.look == 'charging' then c.ch:SetValue(c.dmg * pr)
      elseif c.look == 'smoulder' then local k = .3 + .7 * pr ^ 1.6; b:SetStatusBarColor(col[1] * k, col[2] * k, col[3] * k, 1)
      elseif c.look == 'stripes' then
        local bw, bh = c.hb:GetWidth(), c.hb:GetHeight(); local o = (now * .35) % 1
        c.ov.pre:SetTexCoord(o, o + bw / 24, 0, math.max(.01, bh / 24))
      elseif c.look == 'motes' then
        local bw = c.hb:GetWidth(); local o = (now * .08) % 1
        c.ov.motes:SetTexCoord(o, o + bw / 128 * 2, 0, 1)
      end
    end
  end
end

local function dotsOn(unit)
  local src = ns.parts.doomed and ns.parts.doomed.source
  if not src then return {} end
  local ok, raw = pcall(src, unit); if not ok or type(raw) ~= 'table' then return {} end
  local list, seen = {}, {}
  for _, e in ipairs(raw) do
    if e.name and not seen[e.name] and (e.damage or 0) > 0 then seen[e.name] = true; list[#list + 1] = e end
  end
  table.sort(list, function(a, b) return (a.expiresAt or 0) < (b.expiresAt or 0) end)
  return list
end

local function paint(unit, plate)
  local hb = healthBarOf(plate)
  if not hb then
    if not foundLogged then foundLogged = true; ns.err('platebar: no health bar on the nameplate') end
    return nil
  end
  local list = dotsOn(unit)
  if #list == 0 then if shown[hb] then clear(hb) end; return hb end
  local set = piecesFor(hb); if not set then return hb end
  local w = hb:GetWidth()
  local maxv = UnitHealthMax(unit)
  local color = ns.doomedColor or {}
  -- precast ("I don't see the precast" on these bars; "whatever look I chose from settings"):
  -- while you cast a DoT at this mob its piece shows your 'While you cast' look, as on the target frame
  local cName, _, _, cStart, cEnd = UnitCastingInfo('player')
  local look = ns.db.cast or 'charging'
  local tone = ns.doomedTone or {}
  local sum = 0
  for i = 1, MAX do
    local b, ch, d = set[i], set.charge[i], list[i]
    if d then
      local before = sum
      sum = sum + d.damage
      b:SetWidth(w); b:SetMinMaxValues(0, maxv)
      if SMOOTH then b:SetValue(sum, SMOOTH) else b:SetValue(sum) end
      local c = color[d.name] or { .55, .45, .65 }
      local casting = d.provisional and cName == d.name and cStart and cEnd and cEnd > cStart
      local ov, st = set.ov[i], charging[b]
      if casting then
        local tn = tone[d.name] or c
        if not (st and not st.landAt and st.name == d.name) then
          st = { name = d.name, col = c, look = look, hb = hb, ov = ov, ch = ch }
          charging[b] = st
        end
        st.before, st.dmg, st.s, st.e = before, d.damage, cStart / 1000, cEnd / 1000
        if look ~= 'smoulder' then b:SetStatusBarColor(c[1] * .45, c[2] * .45, c[3] * .45, 1) end
        if look == 'charging' then
          ch:SetWidth(w); ch:SetMinMaxValues(0, maxv); ch:SetStatusBarColor(c[1], c[2], c[3], 1)   -- its landed colour: landing changes nothing
          ch:Show()
        else ch:Hide() end
        if look == 'stripes' then ov.pre:SetVertexColor(tn[1], tn[2], tn[3], .55); ov.pre:Show() else ov.pre:Hide() end
        if look == 'motes' then ov.motes:SetVertexColor(tn[1] * .8, tn[2] * .8, tn[3] * .8); ov.motes:Show() else ov.motes:Hide() end
      else
        ch:Hide(); ov.pre:Hide(); ov.motes:Hide()
        if st and not st.landAt then
          if st.look == 'charging' then charging[b] = nil; b:SetStatusBarColor(c[1], c[2], c[3], 1)   -- the fill was already whole
          else st.landAt = GetTime(); st.col = c end                                                 -- the rest ease up to full
        elseif not st then b:SetStatusBarColor(c[1], c[2], c[3], 1) end
      end
      b:Show()
    else b:Hide(); quietSlot(set, i) end
  end
  shown[hb] = true
  return hb
end

local function refresh()
  if not (ns.db and ns.db.doomed and ns.db.platebar) then
    for hb in pairs(shown) do clear(hb) end; return
  end
  local seen = {}
  for i = 1, 40 do
    local u = 'nameplate' .. i
    if UnitExists(u) then
      local okE, can = pcall(UnitCanAttack, 'player', u)
      local plate = C_NamePlate.GetNamePlateForUnit(u, false)
      if plate and okE and can == true and not UnitIsDead(u) then
        local hb = paint(u, plate); if hb then seen[hb] = true end
      end
    end
  end
  for hb in pairs(shown) do if not seen[hb] then clear(hb) end end   -- plates that left, died or changed mob
end

function K.start()
  if select(2, UnitClass('player')) ~= 'WARLOCK' then return end
  if ns.db.platebar == nil then ns.db.platebar = true end
  local acc, off = 0, false
  local f = CreateFrame('Frame')
  f:SetScript('OnUpdate', function(_, dt)
    if off then return end
    acc = acc + dt
    local ok, err = true, nil
    if acc >= .1 then acc = 0; ok, err = pcall(refresh) end
    if ok then ok, err = pcall(chargeStep) end
    if not ok then ns.err('platebar: ' .. tostring(err)); off = true; for hb in pairs(shown) do pcall(clear, hb) end end   -- off for this session only
  end)
end
