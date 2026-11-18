-- OmaWay arrow (sheet 112 "Soul well", sheet 115 v2 plate, 2026-11-17; Joshua the same day: starts at 64 px, "it
-- should only ever resize with a //// bottom right", no jumping while sizing; the plate and "you're here" painted,
-- "very AI driven, lets make it a bit more rich").
-- Direction: the same maths TomTom and Guidelime use (HereBeDragons' world vector minus your facing), drawn as one
-- painted texture rotated to the exact angle every frame, eased a touch, instead of one of 64-108 sprites.
-- On course it's the violet well; turning away it fades into the red one and the plate's gems turn to embers.
-- Under it a painted plate: the job's icon, the yards and the name, and the job's progress on a second line.
-- Within 5 yards (or the guide's arrival distance) the arrow gives way to a gold compass ring: "Here".
local ADDON, ns = ...
local ART = 'Interface\\AddOns\\OmaWay\\Art\\'
local A = {}; ns.arrow = A

local f, on, off, here, plate, plateBg, icon, line1, line2, grip
local shown = false
local cur              -- the angle on screen (eased), radians
local twopi = math.pi * 2
local function wrap(a) a = a % twopi; if a > math.pi then a = a - twopi end; return a end

-- distance in yards to the waypoint, or nil (another continent, or the game won't say where you are: instances)
local function vector()
  local w = ns.waypoint(); local H = ns.hbd()
  if not (w and H and w.wx and w.wy) then return nil end
  local okP, px, py, pinst = pcall(H.GetPlayerWorldPosition, H)
  if not (okP and px and py) or pinst ~= w.inst then return nil end
  local okV, angle, dist = pcall(H.GetWorldVector, H, w.inst, px, py, w.wx, w.wy)
  if not (okV and angle and dist) then return nil end
  return angle, dist
end
function ns.distance() local _, d = vector(); return d end

local FONT = STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'
local function art()
  local small = (ns.db().size or 64) <= 96
  on:SetTexture(ART .. (small and 'arrow_on_s' or 'arrow_on'), nil, nil, 'TRILINEAR')
  off:SetTexture(ART .. (small and 'arrow_off_s' or 'arrow_off'), nil, nil, 'TRILINEAR')
end

local function look()
  local db = ns.db()
  f:SetSize(db.size, db.size); art()
  f:SetAlpha((db.alpha or 100) / 100)
  line1:SetFont(FONT, db.text or 12, ''); line2:SetFont(FONT, math.max(9, (db.text or 12) - 2), '')
  plate:SetShown(db.yards ~= false)
  grip:SetShown(not db.locked)
end
A.look = look

-- the plate sizes itself around its text: icon, line one (yards and name), line two (progress)
local warnShown
local function setPlate(t1, t2, iconPath, warn)
  line1:SetText(t1 or ''); line2:SetText(t2 or ''); line2:SetShown(t2 ~= nil and t2 ~= '')
  if iconPath then icon:SetTexture(iconPath); icon:Show() else icon:Hide() end
  local tw = math.max(line1:GetStringWidth() or 0, (t2 and t2 ~= '') and (line2:GetStringWidth() or 0) or 0)
  local th = (ns.db().text or 12)
  plate:SetSize(tw + (iconPath and 26 or 0) + 58, (t2 and t2 ~= '') and (th * 2 + 22) or (th + 24))
  if (warn and true or false) ~= warnShown then
    warnShown = warn and true or false
    plateBg:SetTexture(ART .. (warn and 'plate_warn' or 'plate'), nil, nil, 'TRILINEAR')
  end
end

-- ---------- the frame ----------
local function savePos() local p, _, rp, x, y = f:GetPoint(1); local db = ns.db(); db.point, db.rel, db.x, db.y = p, rp, x, y end
local function place()
  local db = ns.db(); f:ClearAllPoints()
  f:SetPoint(db.point or 'TOP', UIParent, db.rel or 'TOP', db.x or -100, db.y or -40)   -- sheet 111: top, left of centre
end
function A.reset() local db = ns.db(); db.point, db.rel, db.x, db.y, db.size = nil, nil, nil, nil, ns.DEFAULTS.size; place(); look(); ns.say('arrow back in its first place, 64 px.') end

-- the //// grip: like the OmaDoomed list, the drag is measured once at the press and the size is applied about the
-- top-left corner pinned to its screen spot, so nothing slides while you drag
local function sizeKeep(px)
  local db = ns.db()
  local l, t = f:GetLeft(), f:GetTop()
  db.size = math.max(32, math.min(192, math.floor(px + .5)))
  f:SetSize(db.size, db.size)
  if l and t then f:ClearAllPoints(); f:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', l, t) end
end

local function build()
  f = CreateFrame('Frame', 'OmaWayArrow', UIParent)
  f:SetFrameStrata('MEDIUM'); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag('LeftButton')
  off = f:CreateTexture(nil, 'ARTWORK', nil, 1); off:SetAllPoints(); off:SetAlpha(0)
  on = f:CreateTexture(nil, 'ARTWORK', nil, 2); on:SetAllPoints()
  here = f:CreateTexture(nil, 'ARTWORK', nil, 3); here:SetAllPoints(); here:SetTexture(ART .. 'here', nil, nil, 'TRILINEAR'); here:SetAlpha(0)
  -- the painted plate, 9-sliced so its gem caps never stretch (texture 256x80: caps 30 px, frame 18 px)
  plate = CreateFrame('Frame', nil, f); plate:SetPoint('TOP', f, 'BOTTOM', 0, 2)
  plateBg = plate:CreateTexture(nil, 'BACKGROUND'); plateBg:SetAllPoints(); plateBg:SetTexture(ART .. 'plate', nil, nil, 'TRILINEAR')
  if plateBg.SetTextureSliceMargins then
    pcall(plateBg.SetTextureSliceMargins, plateBg, 30, 18, 30, 18)
    if Enum and Enum.UITextureSliceMode then pcall(plateBg.SetTextureSliceMode, plateBg, Enum.UITextureSliceMode.Stretched) end
  end
  icon = plate:CreateTexture(nil, 'ARTWORK'); icon:SetSize(18, 18); icon:SetPoint('LEFT', plate, 'LEFT', 26, 0); icon:Hide()
  line1 = plate:CreateFontString(nil, 'OVERLAY'); line1:SetShadowColor(0, 0, 0, 1); line1:SetShadowOffset(1, -1); line1:SetTextColor(.94, .89, .74)
  line2 = plate:CreateFontString(nil, 'OVERLAY'); line2:SetShadowColor(0, 0, 0, 1); line2:SetShadowOffset(1, -1); line2:SetTextColor(.72, .68, .58)
  line1:SetPoint('BOTTOMLEFT', icon, 'RIGHT', 6, 0); line2:SetPoint('TOPLEFT', icon, 'RIGHT', 6, -2)
  line1:SetJustifyH('LEFT'); line2:SetJustifyH('LEFT')
  grip = CreateFrame('Button', nil, f); grip:SetSize(16, 16); grip:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', 6, -6)
  grip:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
  grip:SetHighlightTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight')
  grip:SetPushedTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down')
  local from, start
  grip:SetScript('OnMouseDown', function()
    if InCombatLockdown() or ns.db().locked then return end
    from, start = GetCursorPosition(), ns.db().size
    local es = f:GetEffectiveScale()
    grip:SetScript('OnUpdate', function() sizeKeep(start + (GetCursorPosition() - from) / es); art() end)
  end)
  grip:SetScript('OnMouseUp', function() grip:SetScript('OnUpdate', nil); savePos(); look() end)
  f:SetScript('OnDragStart', function(self) if not ns.db().locked and not InCombatLockdown() then self:StartMoving() end end)
  f:SetScript('OnDragStop', function(self) self:StopMovingOrSizing(); savePos() end)
  f:SetScript('OnMouseUp', function(self, b) if b == 'RightButton' then A.menu(self) end end)
  f:SetScript('OnEnter', function(self)
    local w = ns.waypoint(); if not (w and GameTooltip) then return end
    GameTooltip:SetOwner(self, 'ANCHOR_BOTTOM'); GameTooltip:SetText(w.title or 'Waypoint', 1, .82, 0)
    if w.line2 then GameTooltip:AddLine(w.line2, 1, 1, 1, true) end
    if w.from then GameTooltip:AddLine((w.focus and '|cffffd100Locked:|r ' or 'From ') .. tostring(w.from), .7, .7, .7) end
    GameTooltip:AddLine(ns.db().locked and 'Right-click: unlock, reset, look' or 'Drag to move, //// to size. Right-click: lock, reset, look', .6, .6, .6, true)
    GameTooltip:Show()
  end)
  f:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
  f:Hide()
  place(); look()
end

-- ---------- every frame: turn, colour, yards ----------
local textAcc, pulse = 0, 0
local function step(_, el)
  local angle, dist = vector()
  local okF, facing = pcall(GetPlayerFacing)
  local w = ns.waypoint()
  if not (angle and okF and type(facing) == 'number' and w) then on:SetAlpha(0); off:SetAlpha(0); here:SetAlpha(0); setPlate(w and w.title or '', w and w.line2, w and w.icon); return end
  if dist <= math.max(5, w.arrive or 0) then                       -- arrived: the gold ring, breathing, "Here"
    pulse = pulse + el
    on:SetAlpha(0); off:SetAlpha(0); here:SetAlpha(.75 + .25 * math.sin(pulse * 3))
    if textAcc ~= -1 then textAcc = -1; setPlate('|cffffd100Here|r  ' .. (w.title or ''), w.line2, w.icon) end
    return
  end
  here:SetAlpha(0); if textAcc == -1 then textAcc = 1 end
  local want = wrap(angle - facing)
  cur = cur and (cur + wrap(want - cur) * math.min(1, el * 14)) or want   -- eased: glides, never lags behind a turn
  on:SetRotation(cur); off:SetRotation(cur)
  local away = math.min(1, math.max(0, (math.abs(cur) - math.pi / 3) / (math.pi / 3)))   -- 60 deg on course, red past 120
  on:SetAlpha(1 - away); off:SetAlpha(away)
  textAcc = textAcc + el
  if textAcc > .2 then
    textAcc = 0
    setPlate(((away > .5) and '|cffff8a6a' or '|cffffd100') .. ('%d yd'):format(dist + .5) .. '|r  ' .. (w.title or ''), w.line2, w.icon, away > .5)
  end
end

-- shown when there's a waypoint and quest mode allows it
function ns.arrowChanged()
  if not f then return end
  local want = ns.waypoint() ~= nil and (not ns.modes or ns.modes.allowArrow())
  textAcc = 1                                                      -- a new target: its plate at once
  if want == shown then return end
  shown = want; cur = nil
  f:SetShown(want); f:SetScript('OnUpdate', want and step or nil)
end

-- ---------- right-click menu ----------
function A.menu(owner)
  local db = ns.db()
  if not (MenuUtil and MenuUtil.CreateContextMenu) then db.locked = not db.locked; look(); return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle('OmaWay arrow')
    root:CreateButton(db.locked and 'Unlock to move' or 'Lock in place', function() db.locked = not db.locked; look() end)
    root:CreateButton('Reset position and size', A.reset)
    local o = root:CreateButton('Opacity')
    for _, v in ipairs({ 100, 85, 70, 50 }) do o:CreateRadio(v .. '%', function() return db.alpha == v end, function() db.alpha = v; look() end) end
    local t = root:CreateButton('Text size')
    for _, v in ipairs({ { 10, 'Small' }, { 12, 'Normal' }, { 15, 'Large' } }) do t:CreateRadio(v[2], function() return db.text == v[1] end, function() db.text = v[1]; look() end) end
    root:CreateCheckbox('Show the plate', function() return db.yards ~= false end, function() db.yards = not (db.yards ~= false); look() end)
    root:CreateCheckbox('Point to the nearest quest job', function() return db.nearest ~= false end, function() db.nearest = not (db.nearest ~= false) end)
  end)
end

local ev = CreateFrame('Frame')
ev:RegisterEvent('PLAYER_LOGIN')
ev:SetScript('OnEvent', function() ns.db(); build(); ns.arrowChanged() end)
A.build = build
