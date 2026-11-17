-- OmaDoomed's minimap button (2026-11-17, "Minimap button": "like how Details and Threat do it in that minimap circle").
-- A round button on the minimap's edge, Blizzard's tracking-button look. Left-click: the mob list on / off. Right-click:
-- OmaDoomed's options. Drag it round the edge; its place is kept (OmaDoomedDB.minimap.angle). The game draws it like
-- any minimap button, so add-ons that gather minimap buttons pick it up too.
local ADDON, ns = ...
local MB = {}; ns.minimap = MB

local ICON = 'Interface\\AddOns\\OmaDoomed\\Art\\icon'
local btn

local function db()
  ns.db.minimap = ns.db.minimap or {}
  return ns.db.minimap
end

-- place on the minimap's edge at an angle (degrees), round minimaps (Forever's default)
local function place(angle)
  if not (btn and Minimap) then return end
  local r = math.rad(angle or 225)
  local w = (Minimap:GetWidth() or 140) / 2 + 10
  local h = (Minimap:GetHeight() or 140) / 2 + 10
  btn:ClearAllPoints()
  btn:SetPoint('CENTER', Minimap, 'CENTER', math.cos(r) * w, math.sin(r) * h)
end

local function look(on)
  if not btn then return end
  btn.icon:SetDesaturated(not on); btn.icon:SetAlpha(on and 1 or .6)
end
function MB.refresh() look(not (ns.moblist and ns.moblist.isShown) or ns.moblist.isShown()) end

local function tooltip(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
  GameTooltip:AddLine('OmaDoomed')
  local shown = not (ns.moblist and ns.moblist.isShown) or ns.moblist.isShown()
  GameTooltip:AddLine(shown and 'Mob list: on' or 'Mob list: off', 1, 1, 1)
  GameTooltip:AddLine('Left-click: mob list on / off', .8, .8, .8)
  GameTooltip:AddLine('Right-click: options, move, reset', .8, .8, .8)
  GameTooltip:Show()
end

function MB.build()
  if btn or not Minimap then return end
  if db().hide then return end
  btn = CreateFrame('Button', 'OmaDoomedMinimapButton', Minimap)
  btn:SetSize(31, 31); btn:SetFrameStrata('MEDIUM'); btn:SetFrameLevel(8)
  btn:RegisterForClicks('LeftButtonUp', 'RightButtonUp'); btn:RegisterForDrag('LeftButton')
  btn:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
  local bg = btn:CreateTexture(nil, 'BACKGROUND'); bg:SetTexture('Interface\\Minimap\\UI-Minimap-Background'); bg:SetSize(20, 20); bg:SetPoint('CENTER', 0, 1)
  btn.icon = btn:CreateTexture(nil, 'ARTWORK'); btn.icon:SetTexture(ICON); btn.icon:SetSize(18, 18); btn.icon:SetPoint('CENTER', 0, 1)
  local m = btn:CreateMaskTexture(); m:SetTexture('Interface\\CharacterFrame\\TempPortraitAlphaMask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE'); m:SetAllPoints(btn.icon)
  btn.icon:AddMaskTexture(m)
  local border = btn:CreateTexture(nil, 'OVERLAY'); border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder'); border:SetSize(53, 53); border:SetPoint('TOPLEFT')
  btn:SetScript('OnClick', function(self, b)
    if b == 'RightButton' then
      -- right-click: a small menu (options, unlock / lock the list, reset it); plain options if the client has no menus
      local L = ns.moblist
      if MenuUtil and MenuUtil.CreateContextMenu and L and L.toggleMove then
        MenuUtil.CreateContextMenu(self, function(_, root)
          root:CreateTitle('OmaDoomed')
          root:CreateButton('Options', function() if ns.openSettings then ns.openSettings() end end)
          root:CreateButton(L.isUnlocked and L.isUnlocked() and 'Lock the mob list' or 'Unlock the mob list to move', function() L.toggleMove() end)
          root:CreateButton('Reset the mob list to default', function() if L.resetPlace then L.resetPlace() end end)
        end)
        return
      elseif ns.openSettings then ns.openSettings() end
    elseif ns.moblist and ns.moblist.setShown then ns.moblist.setShown(not ns.moblist.isShown()) end
    MB.refresh(); tooltip(self)
  end)
  btn:SetScript('OnEnter', tooltip)
  btn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
  btn:SetScript('OnDragStart', function(self)
    self:SetScript('OnUpdate', function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      if not (mx and cx) then return end
      local a = math.deg(math.atan2(cy / s - my, cx / s - mx))
      db().angle = a; place(a)
    end)
  end)
  btn:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
  place(db().angle)
  MB.refresh()
end

ns.starts[#ns.starts + 1] = function() MB.build() end
