-- Omashu Guide (2026-11-10, Joshua: "yes"): WoW Forever's controller navigation (SmartNavigation) only knows Blizzard's
-- own windows, so View said "No interface frame to focus" at the RestedXP box. This registers that box with Blizzard's
-- FrameControlsManager the way KroGamepadBags registers its bag window (the one proven pattern on Forever), so:
--   View cycles to the box, D-pad moves the highlight between the step lines, A ticks a line (A again unticks).
-- Blizzard's own code performs the press (a real click), so RestedXP's handlers run exactly as for a mouse click.
-- Nothing on RestedXP's or Blizzard's frames is changed; the box never takes focus by itself (shouldFocus = false).
local reg, pending = false, nil
local function say(m) print('|cffe8c860Omashu Guide:|r ' .. m) end
local function mgr() return GamepadMode and GamepadMode.FrameControlsManager end
local function ready() local m = mgr(); return m and m.FrameShown and InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() end

-- The box, its title bar and each step frame drag with the mouse (OnMouseDown/Up), which SmartNavigation would treat
-- as big buttons: mark them "container" (skipped, children still searched). The tick boxes (CheckButtons) stay reachable.
local marked = {}
local function mark(f, how)
  if not f or marked[f] then return end
  marked[f] = true
  if how == 'all' then if SmartNavigation_MarkFrameIgnored then SmartNavigation_MarkFrameIgnored(f) end
  elseif SmartNavigation_MarkFrameIgnoredContainerFrame then SmartNavigation_MarkFrameIgnoredContainerFrame(f) end
end
local function markAll()
  local f = _G.RXPFrame; if not f then return end
  mark(f); mark(f.CurrentStepFrame)
  mark(_G.RXPFrameGuideName, 'all'); mark(_G.RXPFrameGuideNameResize, 'all')   -- title bar, cog and resize grip: not steps
  local pool = f.CurrentStepFrame and f.CurrentStepFrame.framePool
  if type(pool) == 'table' then for _, sf in ipairs(pool) do mark(sf); mark(sf.number, 'all') end end
end

-- Only while you use it (Joshua 2026-11-10: with the box always on WoW's window list, backing out of any menu, and
-- Start's wheel, landed on the guide box, because WoW then counts the UI as focused). Now: press View with nothing
-- else open and WoW says "no frame to focus"; right after that we put the box on the list AND focus it. Leaving it
-- (B, or View again) takes it off the list. Any other window opening takes it off too. Nothing stays registered.
local function othersOpen()
  local m = mgr(); if not (m and m.shownFrames) then return false end
  for _, x in ipairs(m.shownFrames) do if x ~= _G.RXPFrame then return true end end
  return false
end
local function show(focus)
  local m, f = mgr(), _G.RXPFrame
  if not (ready() and f and f:IsShown()) or othersOpen() then return end
  if InCombatLockdown() then pending = 'show'; return end
  pending = nil; markAll()
  if reg then m:FrameHidden(f) end
  m:FrameShown(f, false, focus and true or false)
  reg = true
end
local function hide()
  local m, f = mgr(), _G.RXPFrame
  if not (reg and m and f) then return end
  if InCombatLockdown() then pending = 'hide'; return end
  pending = nil; reg = false; m:FrameHidden(f)
end

local ev = CreateFrame('Frame')
ev:RegisterEvent('PLAYER_ENTERING_WORLD'); ev:RegisterEvent('PLAYER_REGEN_ENABLED')
ev:SetScript('OnEvent', function(_, e)
  if e == 'PLAYER_REGEN_ENABLED' then if pending == 'show' then show(true) elseif pending == 'hide' then hide() end; return end
  local f, m = _G.RXPFrame, mgr()
  if f and m and not f.omashuHooked then
    f.omashuHooked = true
    f:HookScript('OnHide', hide)
    -- Blizzard's "close everything" path calls HideUIPanel on every registered window: the guide box must come back
    hooksecurefunc('HideUIPanel', function(frame) if frame == _G.RXPFrame and reg then C_Timer.After(0, function() _G.RXPFrame:Show() end) end end)
    -- View (ToggleUIFocus -> SetUIFocusState): with nothing open WoW refuses; then the box goes on and gets focus
    hooksecurefunc(m, 'SetUIFocusState', function(self, want)
      if want then
        if not reg and not self.isUIFocused and #self.shownFrames == 0 then C_Timer.After(0, function() show(true) end) end
      elseif reg then C_Timer.After(0, hide) end
    end)
    -- another window opened while the box was on the list: off the list, so backing out never lands on it
    hooksecurefunc(m, 'FrameShown', function(_, frame) if frame ~= _G.RXPFrame and reg then C_Timer.After(0, hide) end end)
    C_Timer.NewTicker(2, markAll)   -- step frames are created as the guide moves on
  end
end)

SLASH_OMASHUGUIDE1 = '/omguide'
SlashCmdList.OMASHUGUIDE = function(msg)
  if msg == 'off' then hide(); say('off'); return elseif msg == 'on' then show(true); say('on'); return end
  local m, f = mgr(), _G.RXPFrame
  local inList = m and m.shownFrames and f and tIndexOf(m.shownFrames, f) or nil
  local active = m and m.GetActiveFrame and m:GetActiveFrame(); active = active and active.GetName and active:GetName() or tostring(active)
  say(('registered %s | in Blizzard list %s | windows known %s | active %s | gamepad UI %s'):format(tostring(reg), tostring(inList ~= nil), tostring(m and m.shownFrames and #m.shownFrames), tostring(active), tostring(ready() and true or false)))
end
