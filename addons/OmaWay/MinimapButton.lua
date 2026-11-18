-- OmaWay's minimap button (2026-11-17, Joshua: "this would help me quick hide or show"), made like OmaDoomed's: a
-- round button on the minimap's edge in Blizzard's tracking-button look, the Soul well as its icon.
--   Left-click: the arrow on / off (greyed while off).   Right-click: modes, lock, reset, nearest quest job.
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

function MB.refresh()
  if not btn then return end
  local on = not ns.db().hidden
  btn.icon:SetDesaturated(not on); btn.icon:SetAlpha(on and 1 or .55)
end

local function tooltip(self)
  if not GameTooltip then return end
  local db = ns.db()
  GameTooltip:SetOwner(self, 'ANCHOR_LEFT'); GameTooltip:AddLine('OmaWay')
  GameTooltip:AddLine(db.hidden and 'Arrow: off' or 'Arrow: on', 1, 1, 1)
  GameTooltip:AddLine('Mode: ' .. ((ns.modes and ns.modes.current()) or 'quest') .. (db.mode == 'auto' and ' (automatic)' or ''), 1, 1, 1)
  GameTooltip:AddLine('Left-click: arrow on / off', .8, .8, .8)
  GameTooltip:AddLine('Right-click: mode, lock, reset', .8, .8, .8)
  GameTooltip:Show()
end

function MB.setHidden(h)
  ns.db().hidden = h and true or nil
  if ns.arrowChanged then ns.arrowChanged() end
  MB.refresh()
end

local function menu(self)
  local db = ns.db()
  if not (MenuUtil and MenuUtil.CreateContextMenu) then MB.setHidden(not db.hidden); return end
  MenuUtil.CreateContextMenu(self, function(_, root)
    root:CreateTitle('OmaWay')
    root:CreateCheckbox('Show the arrow', function() return not db.hidden end, function() MB.setHidden(not db.hidden) end)
    root:CreateRadio('Quest mode', function() return db.mode == 'quest' end, function() SlashCmdList.OMAWAY('quest') end)
    root:CreateRadio('Dungeon mode', function() return db.mode == 'dungeon' end, function() SlashCmdList.OMAWAY('dungeon') end)
    root:CreateRadio('Automatic (dungeons switch it)', function() return db.mode == 'auto' end, function() SlashCmdList.OMAWAY('auto') end)
    root:CreateButton(db.locked and 'Unlock the arrow to move' or 'Lock the arrow', function() SlashCmdList.OMAWAY(db.locked and 'unlock' or 'lock') end)
    root:CreateButton('Reset the arrow', function() SlashCmdList.OMAWAY('reset') end)
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
    MB.setHidden(not ns.db().hidden); tooltip(self)
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
