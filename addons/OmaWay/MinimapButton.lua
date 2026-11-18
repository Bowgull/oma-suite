-- OmaWay's minimap button (2026-11-17, Joshua: "this would help me quick hide or show", then "these should all be one
-- thing"): the one control, made like OmaDoomed's button (Blizzard's tracking-button look, the Soul well as its icon).
--   Left-click: the guide, the Questie tracker and the arrow on / off together (off brings the damage meter; greyed
--   while off). Dungeons still switch it off and back on by themselves.   Right-click: lock, reset, nearest quest job.
--   Drag it round the edge; its place is kept (OmaWayDB.minimapAngle).
local ADDON, ns = ...
local MB = {}; ns.minimap = MB
local btn

local function place(angle)
  if not (btn and Minimap) then return end
  local r = math.rad(angle or 250)                       -- OmaDoomed's sits at 225: start a little further round
  local w = (Minimap:GetWidth() or 140) / 2 + 10
  local h = (Minimap:GetHeight() or 140) / 2 + 10
  btn:ClearAllPoints(); btn:SetPoint('CENTER', Minimap, 'CENTER', math.cos(r) * w, math.sin(r) * h)
end

local function isOn() return not ns.modes or ns.modes.current() == 'quest' end
function MB.refresh()
  if not btn then return end
  local on = isOn()
  btn.icon:SetDesaturated(not on); btn.icon:SetAlpha(on and 1 or .55)
end

local function tooltip(self)
  if not GameTooltip then return end
  local db = ns.db()
  GameTooltip:SetOwner(self, 'ANCHOR_LEFT'); GameTooltip:AddLine('OmaWay')
  GameTooltip:AddLine(isOn() and 'Guide, tracker and arrow: on' or 'Guide, tracker and arrow: off (damage meter on)', 1, 1, 1)
  if db.mode == 'auto' then GameTooltip:AddLine('Dungeons switch it off by themselves', .6, .6, .6) end
  GameTooltip:AddLine('Left-click: all on / off', .8, .8, .8)
  GameTooltip:AddLine('Right-click: lock, reset, options', .8, .8, .8)
  GameTooltip:Show()
end

function MB.toggle() if ns.modes and ns.modes.toggle then ns.modes.toggle() end; MB.refresh() end

local function menu(self)
  local db = ns.db()
  if not (MenuUtil and MenuUtil.CreateContextMenu) then MB.toggle(); return end
  MenuUtil.CreateContextMenu(self, function(_, root)
    root:CreateTitle('OmaWay')
    root:CreateCheckbox('Guide, tracker and arrow', function() return isOn() end, function() MB.toggle() end)
    if db.mode ~= 'auto' then root:CreateButton('Let dungeons switch it again', function() SlashCmdList.OMAWAY('auto') end) end
    root:CreateButton(db.locked and 'Unlock the arrow to move' or 'Lock the arrow', function() SlashCmdList.OMAWAY(db.locked and 'unlock' or 'lock') end)
    root:CreateButton('Reset the arrow', function() SlashCmdList.OMAWAY('reset') end)
    root:CreateCheckbox('Dock guide under tracker', function() return db.dock ~= false end, function() db.dock = not (db.dock ~= false); if db.dock ~= false and ns.modes then ns.modes.dock() end end)
    root:CreateCheckbox('Point to the nearest quest job', function() return db.nearest ~= false end, function() db.nearest = not (db.nearest ~= false) end)
  end)
end

function MB.build()
  if btn or not Minimap or ns.db().minimapHide then return end
  btn = CreateFrame('Button', 'OmaWayMinimapButton', Minimap)
  btn:SetSize(31, 31); btn:SetFrameStrata('MEDIUM'); btn:SetFrameLevel(8)
  btn:RegisterForClicks('LeftButtonUp', 'RightButtonUp'); btn:RegisterForDrag('LeftButton')
  btn:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
  local bg = btn:CreateTexture(nil, 'BACKGROUND'); bg:SetTexture('Interface\\Minimap\\UI-Minimap-Background'); bg:SetSize(20, 20); bg:SetPoint('CENTER', 0, 1)
  btn.icon = btn:CreateTexture(nil, 'ARTWORK'); btn.icon:SetTexture('Interface\\AddOns\\OmaWay\\Art\\arrow_on_s'); btn.icon:SetSize(22, 22); btn.icon:SetPoint('CENTER', 0, 1)
  local border = btn:CreateTexture(nil, 'OVERLAY'); border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder'); border:SetSize(53, 53); border:SetPoint('TOPLEFT')
  btn:SetScript('OnClick', function(self, b)
    if b == 'RightButton' then menu(self); return end
    MB.toggle(); tooltip(self)
  end)
  btn:SetScript('OnEnter', tooltip)
  btn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
  btn:SetScript('OnDragStart', function(self)
    self:SetScript('OnUpdate', function()
      local mx, my = Minimap:GetCenter(); local cx, cy = GetCursorPosition(); local s = Minimap:GetEffectiveScale()
      if not (mx and cx) then return end
      local a = math.deg(math.atan2(cy / s - my, cx / s - mx)); ns.db().minimapAngle = a; place(a)
    end)
  end)
  btn:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
  place(ns.db().minimapAngle)
  MB.refresh()
end

local ev = CreateFrame('Frame')
ev:RegisterEvent('PLAYER_LOGIN')
ev:SetScript('OnEvent', function() MB.build() end)
