-- OmaDoomed, the mob list (sheets 69, 72, 73, 75; approved 2026-11-16 "build it"): every enemy in the fight in one
-- TV-sized window, one row each: its portrait (with Blizzard's aggro glow when your threat climbs), its name, its
-- health with your kill bar, and your DoTs in their seats. Click a row to target that mob, in combat too.
--
-- How clicking works in combat: each row is a SecureUnitButton (type 'target'). Which mob a row shows is its 'unit'
-- attribute, a nameplate token. Blizzard's secure state drivers watch every token ("[@nameplateN,harm,nodead]") and a
-- secure snippet in the header hands a new enemy the first free row and frees a row when its mob goes. Rows never
-- move: a mob keeps its row for the whole fight, so you never click the wrong one because the list re-sorted.
-- Everything you see on a row (name, bar, rings, glow) follows that attribute from plain add-on code.
--
-- Shown in combat only. '/omadoomed list unlock' shows it out of combat to drag it (and its corner to size it).
local ADDON, ns = ...
local L = {}; ns.moblist = L
local R, Secret = ns.rings, ns.core.Secret
local ART = 'Interface\\AddOns\\OmaDoomed\\Art\\rings\\'

-- sheet 75: one grid, u = a quarter ring. Every distance is a whole number of u (in the list's own units).
local U = 10
local D = 4 * U                       -- ring = portrait
local PADX, PADY = 2 * U, 1.5 * U
local GP = 1.5 * U                    -- portrait -> name
local BW = 18 * U                     -- health / kill bar
local GB = 3 * U                      -- bar -> rings: wider than between rings, so the two groups read apart
local RH = 6 * U                      -- a row is 1.5 rings tall
local NAME, BAR_H, NB = 16, 12, 6     -- name size, bar height, name -> bar gap
L.U, L.D, L.RH = U, D, RH
local TCOL = { [1] = { 1, .82, 0 }, [2] = { 1, .48, 0 }, [3] = { 1, .1, .1 } }   -- Blizzard's threat colours

local db                              -- OmaDoomedDB.list
local header, rows = nil, {}
local N = 8
local function say(m) print('|cffb48cffOmaDoomed:|r ' .. m) end
local function plain(v) return v ~= nil and not Secret.is(v) end

local function seatWidth()
  local _, n = R.seatSpots()
  return n * D + (n - 1) * R.SEAT_GAP
end
local function width() return PADX + D + GP + BW + GB + seatWidth() + PADX end

-- ---------- the secure part ----------
-- states arrive as numbers or strings depending on the driver; both are handled
local SNIPPET = [[
  local tok = 'nameplate' .. strsub(stateid, 3)
  local n = self:GetAttribute('rows')
  local on = newstate == 1 or newstate == '1'
  for i = 1, n do
    local r = self:GetFrameRef('row' .. i)
    if r:GetAttribute('unit') == tok then
      if not on then r:SetAttribute('unit', nil); r:Hide() end
      return
    end
  end
  if on then
    for i = 1, n do
      local r = self:GetFrameRef('row' .. i)
      if not r:GetAttribute('unit') then r:SetAttribute('unit', tok); r:Show(); return end
    end
  end
]]

-- ---------- what a row shows ----------
local function isTarget(u)
  local ok, tp = pcall(C_NamePlate.GetNamePlateForUnit, 'target', false)
  local ok2, up = pcall(C_NamePlate.GetNamePlateForUnit, u, false)
  return ok and ok2 and tp ~= nil and tp == up
end

local function threat(r)
  local u = r.unit
  local ok, s = pcall(UnitThreatSituation, 'player', u)
  local c = ok and plain(s) and TCOL[s]
  if c then
    r.glow:SetVertexColor(c[1], c[2], c[3])
    if not r.glow:IsShown() then r.glow:Show(); r.breath:Play() end
  elseif r.glow:IsShown() then r.breath:Stop(); r.glow:Hide() end
end

local function health(r)
  local u = r.unit; if not u then return end
  pcall(r.bar.SetMinMaxValues, r.bar, 0, UnitHealthMax(u))
  pcall(r.bar.SetValue, r.bar, UnitHealth(u))
end

local function killbar(r)
  local K = ns.parts.platebar
  if K and K.paintRow then pcall(K.paintRow, r.unit, r.bar) end
end

local function fill(r)
  local u = r.unit
  if not u then killbar(r); return end
  pcall(r.name.SetText, r.name, UnitName(u))
  pcall(SetPortraitTexture, r.face, u)
  health(r); threat(r); killbar(r)
  r.tgt:SetShown(isTarget(u))
end

-- the row's unit changed (the secure snippet, in or out of combat): its rings, name and bar follow
local function bind(r, u)
  if u == nil or u == '' then u = false end
  r.unit = u
  if r.pair then
    if u then r.pair.ring:SetUnit(u); r.pair.main:SetUnit(u) end
  end
  if u then fill(r) else killbar(r) end
end

local function newRow(i)
  local r = CreateFrame('Button', 'OmaDoomedListRow' .. i, header, 'SecureUnitButtonTemplate')
  r:SetSize(width(), RH)
  r:SetPoint('TOPLEFT', header, 'TOPLEFT', 0, -PADY - (i - 1) * RH)
  r:SetAttribute('type1', 'target')
  r:RegisterForClicks('AnyUp')
  r:Hide()
  r.unit, r.pair = false, false   -- set, never nil: a row's unit and rings
  -- the row's panel: sheet 73/75's plain dark panel, no dividers
  local bg = r:CreateTexture(nil, 'BACKGROUND'); bg:SetAllPoints(r); bg:SetColorTexture(.043, .035, .035, .9)
  r.bgTex = bg
  r.tgt = r:CreateTexture(nil, 'BACKGROUND', nil, 1); r.tgt:SetPoint('TOPLEFT', 6, -3); r.tgt:SetPoint('BOTTOMRIGHT', -6, 3)
  r.tgt:SetColorTexture(1, .9, 0, .08); r.tgt:Hide()
  -- portrait in a brass ring; Blizzard's aggro colour breathes around it when your threat climbs
  local cx = PADX + D / 2
  r.glow = r:CreateTexture(nil, 'ARTWORK', nil, 0); r.glow:SetTexture(ART .. 'ring_bold'); r.glow:SetBlendMode('ADD')
  r.glow:SetSize(D * 1.45, D * 1.45); r.glow:SetPoint('CENTER', r, 'LEFT', cx, 0); r.glow:Hide()
  r.breath = r.glow:CreateAnimationGroup(); r.breath:SetLooping('BOUNCE')
  local a = r.breath:CreateAnimation('Alpha'); a:SetFromAlpha(1); a:SetToAlpha(.35); a:SetDuration(.8); a:SetSmoothing('IN_OUT')
  r.face = r:CreateTexture(nil, 'ARTWORK', nil, 1); r.face:SetSize(D * .9, D * .9); r.face:SetPoint('CENTER', r, 'LEFT', cx, 0)
  local m = r:CreateMaskTexture(); m:SetTexture(ART .. 'mask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE'); m:SetAllPoints(r.face)
  r.face:AddMaskTexture(m)
  local rim = r:CreateTexture(nil, 'ARTWORK', nil, 2); rim:SetTexture(ART .. 'bezel'); rim:SetSize(D, D); rim:SetPoint('CENTER', r, 'LEFT', cx, 0)
  -- name over the bar; the two as one block on the row's centre line
  local tx = PADX + D + GP
  local blk = NAME * .72 + NB + BAR_H
  r.bar = CreateFrame('StatusBar', nil, r)
  r.bar:SetSize(BW, BAR_H); r.bar:SetPoint('TOPLEFT', r, 'TOPLEFT', tx, -(RH / 2 - blk / 2 + NAME * .72 + NB))
  r.bar:SetStatusBarTexture('Interface\\TargetingFrame\\UI-StatusBar'); r.bar:SetStatusBarColor(.78, .08, .08)
  r.bar:SetMinMaxValues(0, 1); r.bar:SetValue(1)
  local bbg = r.bar:CreateTexture(nil, 'BACKGROUND'); bbg:SetPoint('TOPLEFT', -1, 1); bbg:SetPoint('BOTTOMRIGHT', 1, -1); bbg:SetColorTexture(0, 0, 0, 1)
  local bin = r.bar:CreateTexture(nil, 'BACKGROUND', nil, 1); bin:SetAllPoints(r.bar); bin:SetColorTexture(.16, .03, .03, 1)
  r.name = r:CreateFontString(nil, 'OVERLAY')
  r.name:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF', NAME, 'OUTLINE')
  r.name:SetTextColor(1, .82, 0); r.name:SetShadowColor(0, 0, 0, 1); r.name:SetShadowOffset(1, -1)
  r.name:SetPoint('BOTTOMLEFT', r.bar, 'TOPLEFT', 0, NB); r.name:SetWidth(BW); r.name:SetJustifyH('LEFT'); pcall(r.name.SetWordWrap, r.name, false)
  r:HookScript('OnAttributeChanged', function(self, k, v) if k == 'unit' then local ok, err = pcall(bind, self, v); if not ok then ns.error('list: ' .. tostring(err)) end end end)
  return r
end

-- seats: one row of rings per list row, built one per frame out of combat (no hitch)
local function placeSeats(r)
  local p = r.pair; if not p then return end
  local sw = seatWidth()
  p.anchor:ClearAllPoints(); p.anchor:SetSize(sw, 1)
  p.anchor:SetPoint('BOTTOM', r, 'BOTTOMLEFT', PADX + D + GP + BW + GB + sw / 2, (RH - D) / 2)
end
local builder
local function buildPairs()
  builder = builder or CreateFrame('Frame')
  builder:SetScript('OnUpdate', function(self)
    if InCombatLockdown() then self:SetScript('OnUpdate', nil); return end
    for _, r in ipairs(rows) do
      if not r.pair then
        r.pair = R.newListPair(r) or false
        if r.pair then placeSeats(r); if r.unit then bind(r, r.unit) end end
        return
      end
    end
    self:SetScript('OnUpdate', nil)
  end)
end

-- the window's size follows the seats you know (Siphon Life at 30 adds one); out of combat
local function layout()
  if InCombatLockdown() or not header then return end
  local w = width()
  header:SetSize(w, PADY * 2 + RH * N)
  for _, r in ipairs(rows) do r:SetWidth(w); placeSeats(r) end
end

-- ---------- moving and sizing (out of combat) ----------
local mover
local function savePos()
  local p, _, rp, x, y = header:GetPoint(1)
  db.point, db.rel, db.x, db.y = p, rp, x, y
end
local function makeMover()
  mover = CreateFrame('Frame', nil, header)
  mover:SetAllPoints(header); mover:SetFrameLevel(header:GetFrameLevel() + 40); mover:EnableMouse(true)
  local t = mover:CreateTexture(nil, 'BACKGROUND'); t:SetAllPoints(); t:SetColorTexture(.043, .035, .035, .6)
  for _, e in ipairs({ { 'TOPLEFT', 'TOPRIGHT' }, { 'BOTTOMLEFT', 'BOTTOMRIGHT' }, { 'TOPLEFT', 'BOTTOMLEFT' }, { 'TOPRIGHT', 'BOTTOMRIGHT' } }) do
    local l = mover:CreateTexture(nil, 'BORDER'); l:SetColorTexture(.42, .32, .15, 1)
    l:SetPoint(e[1]); l:SetPoint(e[2]); if e[1] == 'TOPLEFT' and e[2] == 'BOTTOMLEFT' or e[1] == 'TOPRIGHT' then l:SetWidth(2) else l:SetHeight(2) end
  end
  mover:SetScript('OnMouseDown', function(_, b) if b == 'LeftButton' and not InCombatLockdown() then header:StartMoving() end end)
  mover:SetScript('OnMouseUp', function() header:StopMovingOrSizing(); savePos() end)
  -- the corner sizes the whole window (its scale), so every distance keeps its grid
  local grip = CreateFrame('Frame', nil, mover); grip:SetSize(22, 22); grip:SetPoint('BOTTOMRIGHT'); grip:EnableMouse(true)
  local gt = grip:CreateTexture(nil, 'OVERLAY'); gt:SetAllPoints(); gt:SetTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
  grip:SetScript('OnMouseDown', function()
    local x = GetCursorPosition()
    grip.from, grip.scale = x, header:GetScale()
    grip:SetScript('OnUpdate', function()
      local cx = GetCursorPosition()
      local w = header:GetWidth() * grip.scale * header:GetEffectiveScale() / header:GetScale()
      local s = math.max(.6, math.min(2, grip.scale * (1 + (cx - grip.from) / w)))
      header:SetScale(s)
    end)
  end)
  grip:SetScript('OnMouseUp', function() grip:SetScript('OnUpdate', nil); db.scale = header:GetScale(); savePos() end)
  mover:Hide()
end

local function unlock(on)
  if InCombatLockdown() then say('the list can be moved after this fight.'); return end
  db.unlocked = on
  if on then
    UnregisterStateDriver(header, 'visibility'); header:Show()
    if not mover then makeMover() end
    mover:Show(); header:SetMovable(true)
  else
    if mover then mover:Hide() end
    RegisterStateDriver(header, 'visibility', '[combat] show; hide')
  end
end

-- ---------- the ticker: threat, your target, health ----------
local ticker, since = nil, 0
local function tick(_, el)
  since = since + el
  if since < .2 then return end
  since = 0
  for _, r in ipairs(rows) do
    if r.unit and r:IsShown() then pcall(threat, r); pcall(health, r); r.tgt:SetShown(isTarget(r.unit)) end
  end
end

local function start()
  if not R.db or not RegisterStateDriver or not CreateFrame then return end
  ns.db.list = ns.db.list or {}
  db = ns.db.list
  if db.enabled == false then return end
  N = math.max(4, math.min(16, tonumber(db.rows) or 8))
  header = CreateFrame('Frame', 'OmaDoomedList', UIParent, 'SecureHandlerStateTemplate')
  header:SetClampedToScreen(true); header:SetMovable(true)
  header:SetScale(db.scale or 1)
  header:SetPoint(db.point or 'CENTER', UIParent, db.rel or 'CENTER', db.x or 380, db.y or 120)
  header:SetAttribute('rows', N)
  for i = 1, N do rows[i] = newRow(i); header:SetFrameRef('row' .. i, rows[i]) end
  for k = 1, 40 do
    header:SetAttribute('_onstate-np' .. k, SNIPPET)
    RegisterStateDriver(header, 'np' .. k, ('[@nameplate%d,harm,nodead] 1; 0'):format(k))
  end
  layout()
  unlock(db.unlocked == true)
  buildPairs()
  ns.bus:On('DOTS', function() for _, r in ipairs(rows) do if r.unit then killbar(r) end end end)
  local ev = CreateFrame('Frame')
  for _, e in ipairs({ 'PLAYER_REGEN_ENABLED', 'SPELLS_CHANGED', 'PLAYER_TARGET_CHANGED', 'NAME_PLATE_UNIT_ADDED' }) do pcall(ev.RegisterEvent, ev, e) end
  ev:SetScript('OnEvent', function(_, e, u)
    if e == 'PLAYER_REGEN_ENABLED' then layout(); buildPairs()
    elseif e == 'SPELLS_CHANGED' then layout()
    elseif e == 'PLAYER_TARGET_CHANGED' then for _, r in ipairs(rows) do if r.unit then r.tgt:SetShown(isTarget(r.unit)) end end
    elseif e == 'NAME_PLATE_UNIT_ADDED' then   -- a token reused for a new mob while its row stays: show the new mob
      for _, r in ipairs(rows) do if r.unit == u then pcall(bind, r, u) end end
    end
  end)
  ticker = CreateFrame('Frame', nil, header); ticker:SetScript('OnUpdate', tick)
  L.header = header
end
ns.starts[#ns.starts + 1] = start

function L.slash(msg)
  local cmd, arg = (msg or ''):match('^(%S*)%s*(.-)$'); cmd = (cmd or ''):lower()
  if not header then say('the mob list is off (it needs the rings on).'); return end
  if cmd == 'unlock' then unlock(true); say('drag the list where you want it, and its corner to size it. /omadoomed list lock when done.')
  elseif cmd == 'lock' then unlock(false); say('list locked: it shows in fights.')
  elseif cmd == 'rows' then
    local n = tonumber(arg); if n then db.rows = math.max(4, math.min(16, n)); say(('the list holds %d mobs after a /reload.'):format(db.rows)) end
  elseif cmd == 'reset' then
    if InCombatLockdown() then return end
    db.point, db.rel, db.x, db.y, db.scale = nil, nil, nil, nil, nil
    header:ClearAllPoints(); header:SetPoint('CENTER', UIParent, 'CENTER', 380, 120); header:SetScale(1); say('list back in its first place.')
  else
    local n = 0; for _, r in ipairs(rows) do if r.unit then n = n + 1 end end
    say(('mob list: %d rows, %d in use. /omadoomed list unlock | lock | rows 4-16 | reset'):format(N, n))
  end
end
L.rows = rows
function L.headerOf() return header end
