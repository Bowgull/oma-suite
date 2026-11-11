-- The kill bar over every dotted mob (sheet 41, Joshua 2026-11-11: "I should be able to see the dots in the enemy bar
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
  for i = 1, MAX do
    local b = CreateFrame('StatusBar', nil, set.clip)
    b:SetReverseFill(true); b:SetStatusBarTexture(TEX); b:SetMinMaxValues(0, 1); b:SetValue(0)
    local t = b:GetStatusBarTexture(); if type(t) == "table" and t.SetDesaturated then t:SetDesaturated(true) end
    b:SetPoint('TOPRIGHT', fill, 'TOPRIGHT'); b:SetPoint('BOTTOMRIGHT', fill, 'BOTTOMRIGHT')
    b:SetFrameLevel(set.clip:GetFrameLevel() + MAX - i)   -- the piece nearest the green on top
    b:Hide(); set[i] = b
  end
  made[hb] = set
  return set
end

local function clear(hb) local set = made[hb]; if set then for i = 1, MAX do set[i]:Hide() end end; shown[hb] = nil end

local function dotsOn(unit)
  local src = ns.parts.doomed and ns.parts.doomed.source
  if not src then return {} end
  local ok, raw = pcall(src, unit); if not ok or type(raw) ~= 'table' then return {} end
  local list, seen = {}, {}
  for _, e in ipairs(raw) do
    if e.name and not seen[e.name] and (e.damage or 0) > 0 and not e.provisional then seen[e.name] = true; list[#list + 1] = e end
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
  local sum = 0
  for i = 1, MAX do
    local b, d = set[i], list[i]
    if d then
      sum = sum + d.damage
      b:SetWidth(w); b:SetMinMaxValues(0, maxv)
      if SMOOTH then b:SetValue(sum, SMOOTH) else b:SetValue(sum) end
      local c = color[d.name] or { .55, .45, .65 }
      b:SetStatusBarColor(c[1], c[2], c[3], 1)
      b:Show()
    else b:Hide() end
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
    acc = acc + dt; if acc < .1 then return end; acc = 0
    local ok, err = pcall(refresh)
    if not ok then ns.err('platebar: ' .. tostring(err)); off = true; for hb in pairs(shown) do pcall(clear, hb) end end   -- off for this session only
  end)
end
