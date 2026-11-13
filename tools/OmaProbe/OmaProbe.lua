-- OmaProbe: throwaway. One window of buttons; each runs one test and writes what happened to the window and to
-- OmaProbeDB.log (saved at reload / logout). Nothing here is automatic: every test is one click.
OmaProbeDB = OmaProbeDB or {}
local lines = {}
local out
local function log(...)
  local t = {}
  for i = 1, select('#', ...) do t[#t + 1] = tostring((select(i, ...))) end
  local s = date('%H:%M:%S ') .. table.concat(t, ' ')
  lines[#lines + 1] = s
  OmaProbeDB.log = OmaProbeDB.log or {}; table.insert(OmaProbeDB.log, s)
  if out then local a = math.max(1, #lines - 21); out:SetText(table.concat(lines, '\n', a)) end
end
local function try(name, fn, ...)
  local r = { pcall(fn, ...) }
  if r[1] then log(name, 'ok ->', tostring(r[2]), tostring(r[3]), tostring(r[4])) else log(name, 'ERROR', tostring(r[2])) end
  return unpack(r)
end
local function esc(v)
  if v == nil then return 'nil' end
  if issecretvalue and issecretvalue(v) then return '<secret>' end
  local ok, s = pcall(function() return (tostring(v):gsub('|', '||')) end)
  return ok and s or '<unreadable>'
end

local f = CreateFrame('Frame', 'OmaProbeFrame', UIParent, 'BackdropTemplate')
f:SetSize(560, 640); f:SetPoint('LEFT', 20, 0); f:SetFrameStrata('DIALOG')
f:SetBackdrop({ bgFile = 'Interface/Buttons/WHITE8x8', edgeFile = 'Interface/Buttons/WHITE8x8', edgeSize = 1 })
f:SetBackdropColor(0, 0, 0, .85); f:SetBackdropBorderColor(.8, .65, .3, 1)
f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag('LeftButton'); f:SetScript('OnDragStart', f.StartMoving); f:SetScript('OnDragStop', f.StopMovingOrSizing)
out = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
out:SetPoint('TOPLEFT', 8, -200); out:SetPoint('BOTTOMRIGHT', -8, 8); out:SetJustifyH('LEFT'); out:SetJustifyV('TOP'); out:SetWordWrap(true)

local n = 0
local function place(b) local col, row = n % 3, math.floor(n / 3); b:SetSize(180, 24); b:SetPoint('TOPLEFT', 6 + col * 183, -6 - row * 27); n = n + 1 end
local function btn(label, fn)
  local b = CreateFrame('Button', nil, f, 'UIPanelButtonTemplate'); b:SetText(label); place(b)
  b:SetScript('OnClick', function() log('--', label); local ok, e = pcall(fn); if not ok then log('ERROR', e) end end)
  return b
end
local secures = {}
local function sec(label, name, setup)
  local b = CreateFrame('Button', name, f, 'UIPanelButtonTemplate,SecureActionButtonTemplate'); b:SetText(label); place(b)
  b:RegisterForClicks('AnyUp', 'AnyDown')
  b:HookScript('OnClick', function(_, _, down) if not down then log('-- (secure)', label) end end)
  b.setup = setup; secures[#secures + 1] = b
  return b
end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'ADDON_ACTION_BLOCKED', 'ADDON_ACTION_FORBIDDEN', 'MACRO_ACTION_BLOCKED', 'MACRO_ACTION_FORBIDDEN', 'LFG_LIST_SEARCH_RESULTS_RECEIVED',
  'LFG_LIST_SEARCH_FAILED', 'LFG_LIST_ACTIVE_ENTRY_UPDATE', 'LFG_LIST_ROLE_UPDATE', 'CHAT_MSG_WHISPER', 'CHAT_MSG_WHISPER_INFORM', 'UI_ERROR_MESSAGE', 'PLAYER_LOGIN' }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript('OnEvent', function(_, e, a, b2, c)
  if e == 'PLAYER_LOGIN' then
    log('OmaProbe loaded. build', (select(4, GetBuildInfo())), 'gamepadUI', tostring(InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()))
    return
  end
  if e == 'LFG_LIST_SEARCH_RESULTS_RECEIVED' then
    local ok, _, res = pcall(C_LFGList.GetSearchResults); log(e, 'results', ok and res and #res or '?'); return
  end
  if e == 'CHAT_MSG_WHISPER' or e == 'CHAT_MSG_WHISPER_INFORM' then log(e, esc(a), 'from/to', esc(b2)); return end
  log(e, esc(a), esc(b2), esc(c))
end)

local function firstActivity()
  local acts = C_LFGList.GetAvailableActivities(2) or {}
  local lvl = UnitLevel('player')
  for _, id in ipairs(acts) do
    local i = C_LFGList.GetActivityInfoTable(id)
    if i and (i.minLevelSuggestion or 0) <= lvl and (i.maxLevelSuggestion or 99) >= lvl then return id, i.fullName end
  end
  return acts[1], 'first'
end

btn('1 Names + state', function()
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded('Blizzard_GroupFinder_VanillaStyle')
  log('finder add-on loaded', tostring(loaded), 'LFGParentFrame', tostring(LFGParentFrame ~= nil), 'RefreshBtn', tostring(LFGBrowseFrameRefreshButton ~= nil))
  if LFGListingFrame then
    local p = LFGListingFrame.PostButton
    log('PostButton', tostring(p and p:GetName()), 'enabled', tostring(p and p:IsEnabled()), 'BackButton', tostring(LFGListingFrame.BackButton and LFGListingFrame.BackButton:GetName()))
  end
  try('style', C_LFGList.GetPremadeGroupFinderStyle); try('HasActiveEntry', C_LFGList.HasActiveEntryInfo)
  local cats = C_LFGList.GetAvailableCategories(); log('categories', cats and table.concat(cats, ',') or 'nil')
  local id, nm = firstActivity(); log('first activity for my level', tostring(id), tostring(nm))
  if C_LFGListRoles then local ok, r = pcall(C_LFGListRoles.GetRoles); if ok and type(r) == 'table' then log('roles tank', tostring(r.tank), 'healer', tostring(r.healer), 'dps', tostring(r.dps)) else log('GetRoles', tostring(r)) end else log('C_LFGListRoles missing') end
  log('lockdown', tostring(C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()))
end)
btn('2 Load finder add-on', function() try('LoadAddOn', C_AddOns.LoadAddOn, 'Blizzard_GroupFinder_VanillaStyle') end)
btn('3 Dump results', function()
  local _, res = C_LFGList.GetSearchResults(); log('results', res and #res or 'nil')
  for i = 1, math.min(4, res and #res or 0) do
    local r = C_LFGList.GetSearchResultInfo(res[i])
    if r then
      local acts = {}
      if type(r.activityIDs) == 'table' then for _, a in ipairs(r.activityIDs) do local inf = C_LFGList.GetActivityInfoTable(a); acts[#acts + 1] = inf and inf.fullName or a end end
      log(i, 'leader', esc(r.leaderName), 'n', esc(r.numMembers), 'age', esc(r.age), 'acts', table.concat(acts, '/'))
      log('   name=[' .. esc(r.name) .. '] comment=[' .. esc(r.comment) .. ']')
      local okf, found = pcall(function() return type(r.comment) == 'string' and (r.comment:lower():find('a', 1, true) ~= nil) end); log('   can search comment:', tostring(okf), tostring(found))
      for m = 1, math.min(5, tonumber(r.numMembers) or 0) do
        local okp, p = pcall(C_LFGList.GetSearchResultPlayerInfo, res[i], m)
        if okp and p then log('   member', esc(p.name), esc(p.level), esc(p.classFilename), 'roles', p.lfgRoles and ((p.lfgRoles.tank and 'T' or '') .. (p.lfgRoles.healer and 'H' or '') .. (p.lfgRoles.dps and 'D' or '')) or '?', 'assigned', esc(p.assignedRole)) end
      end
    end
  end
end)
btn('4 Search DIRECT', function()
  local acts = C_LFGList.GetAvailableActivities(2) or {}
  try('C_LFGList.Search', C_LFGList.Search, 2, 0, 0, nil, false, nil, acts)
end)
sec('5 Refresh (secure macro)', 'OmaProbeRefreshMacro', function(b) b:SetAttribute('type', 'macro'); b:SetAttribute('macrotext', '/click LFGBrowseFrameRefreshButton') end)
sec('6 Refresh (secure click)', 'OmaProbeRefreshClick', function(b) if LFGBrowseFrameRefreshButton then b:SetAttribute('type', 'click'); b:SetAttribute('clickbutton', LFGBrowseFrameRefreshButton) end end)
btn('7 Role: toggle tank', function()
  local r = C_LFGListRoles.GetRoles(); log('before T/H/D', tostring(r.tank), tostring(r.healer), tostring(r.dps))
  try('SetRoles', C_LFGListRoles.SetRoles, { tank = not r.tank, healer = r.healer, dps = r.dps }, false)
  local r2 = C_LFGListRoles.GetRoles(); log('after  T/H/D', tostring(r2.tank), tostring(r2.healer), tostring(r2.dps))
end)
btn('8 Whisper self (click)', function() try('SendChatMessage', C_ChatInfo.SendChatMessage, 'OmaProbe click test', 'WHISPER', nil, UnitName('player')) end)
btn('9 Whisper self (timer)', function() C_Timer.After(2, function() try('SendChatMessage after 2s', C_ChatInfo.SendChatMessage, 'OmaProbe timer test', 'WHISPER', nil, UnitName('player')) end) end)
btn('10 List me DIRECT', function()
  local id = firstActivity()
  try('CreateListing', C_LFGList.CreateListing, { activityIDs = { id }, newPlayerFriendly = false })
  C_Timer.After(1.5, function() try('HasActiveEntry', C_LFGList.HasActiveEntryInfo) end)
end)
sec('11 Post (secure click)', 'OmaProbePostClick', function(b) local p = LFGListingFrame and LFGListingFrame.PostButton; if p then b:SetAttribute('type', 'click'); b:SetAttribute('clickbutton', p) end end)
btn('12 Unlist DIRECT', function() try('RemoveListing', C_LFGList.RemoveListing); C_Timer.After(1.5, function() try('HasActiveEntry', C_LFGList.HasActiveEntryInfo) end) end)
btn('13 Active entry?', function()
  try('HasActiveEntry', C_LFGList.HasActiveEntryInfo)
  local ok, e = pcall(C_LFGList.GetActiveEntryInfo); if ok and e then log('entry acts', type(e.activityIDs) == 'table' and table.concat(e.activityIDs, ',') or '?', 'comment=[' .. esc(e.comment) .. ']') end
end)
btn('14 Cursor + pad facts', function()
  log('SetCursorPosition', tostring(SetCursorPosition ~= nil), 'SimulateMouseClick', tostring(SimulateMouseClick ~= nil), 'C_LimitedInput', tostring(C_LimitedInput ~= nil))
  if C_LimitedInput and Enum.LimitedInputType then for k, v in pairs(Enum.LimitedInputType) do log('  LimitedInputAllowed', k, tostring(C_LimitedInput.LimitedInputAllowed(v))) end end
  log('pad enabled', tostring(C_GamePad.IsEnabled()), 'active device', tostring(C_GamePad.GetActiveDeviceID()), 'CanGamePadControlCursor', tostring(CanGamePadControlCursor and CanGamePadControlCursor()), 'cursor control on', tostring(IsGamePadCursorControlEnabled()))
  try('SetGamePadCursorControl(true)', SetGamePadCursorControl, true); log('  now on?', tostring(IsGamePadCursorControlEnabled())); try('SetGamePadCursorControl(false)', SetGamePadCursorControl, false)
  try('SetCursorPosition (from a mouse click)', SetCursorPosition, 600, 400)
  local ids = C_GamePad.GetAllConfigIDs() or {}; log('pad configs', #ids)
  for i = 1, math.min(#ids, 6) do
    local c = C_GamePad.GetConfig(ids[i])
    if c and c.stickConfigs then for _, s in ipairs(c.stickConfigs) do log('  cfg', tostring(c.name or 'generic'), tostring(s.stick), 'dz', tostring(s.deadzone), tostring(s.deadzoneX), tostring(s.deadzoneY)) end end
  end
  for _, cv in ipairs({ 'GamePadCursorSpeedStart', 'GamePadCursorSpeedAccel', 'GamePadCursorSpeedMax', 'GamePadCursorLeftClick', 'GamePadCursorRightClick', 'cursorSizePreferred' }) do log('  ', cv, tostring(C_CVar.GetCVar(cv))) end
end)
btn('15 Arm secure buttons', function()
  if InCombatLockdown() then log('in combat, not now'); return end
  for _, b in ipairs(secures) do b.setup(b); log('armed', b:GetName(), tostring(b:GetAttribute('type'))) end
end)
btn('16 Reload (saves the log)', function() (C_UI and C_UI.Reload or ReloadUI)() end)
btn('17 Clear log', function() wipe(lines); OmaProbeDB.log = {}; out:SetText('') end)
OmaProbeRefreshMacro.setup(OmaProbeRefreshMacro)

-- Round 2 (2026-11-13): the phone route. The same actions, but started by a KEY PRESS that a helper program sends
-- from outside the game (the way Couch Mode presses Ctrl+Shift+F11 for the auction search), and by a timer with no
-- press at all, to learn where the game draws the line.
local function twoActs()
  local acts, out2, lvl = C_LFGList.GetAvailableActivities(2) or {}, {}, UnitLevel('player')
  for _, id in ipairs(acts) do
    local i = C_LFGList.GetActivityInfoTable(id)
    if i and (i.minLevelSuggestion or 0) <= lvl and (i.maxLevelSuggestion or 99) >= lvl then out2[#out2 + 1] = id end
    if #out2 == 2 then break end
  end
  return out2
end
local function playstyle()
  local e = Enum.LFGEntryGeneralPlaystyle
  if type(e) ~= 'table' then return nil end
  local best
  for k, v in pairs(e) do log('  playstyle enum', k, v); if v ~= 0 and (not best or v < best) then best = v end end
  return best
end
local function listMulti(tag)
  local a, ps = twoActs(), playstyle()
  log(tag, 'CreateListing with', #a, 'activities:', table.concat(a, ','), 'playstyle', tostring(ps))
  try(tag .. ' CreateListing', C_LFGList.CreateListing, { activityIDs = a, newPlayerFriendly = false, generalPlaystyle = ps })
  C_Timer.After(1.5, function()
    try(tag .. ' HasActiveEntry', C_LFGList.HasActiveEntryInfo)
    local ok, e = pcall(C_LFGList.GetActiveEntryInfo)
    if ok and e then log(tag, 'entry acts', type(e.activityIDs) == 'table' and table.concat(e.activityIDs, ',') or '?', 'playstyle', tostring(e.generalPlaystyle)) end
  end)
end
-- Round 3: which listing shape fails? Each key lists one shape, then checks at 1.5 s and 4 s.
local function state(tag)
  local ok, has = pcall(C_LFGList.HasActiveEntryInfo)
  local e = ok and has and C_LFGList.GetActiveEntryInfo() or nil
  log(tag, 'listed', tostring(has), e and ('acts ' .. (type(e.activityIDs) == 'table' and table.concat(e.activityIDs, ',') or '?') .. ' playstyle ' .. tostring(e.generalPlaystyle)) or '')
end
local function listShape(tag, n, withStyle)
  local all, a = twoActs(), {}
  for i = 1, math.min(n, #all) do a[i] = all[i] end
  local data = { activityIDs = a, newPlayerFriendly = false }
  if withStyle then data.generalPlaystyle = playstyle() end
  log(tag, 'CreateListing acts', table.concat(a, ','), 'playstyle', tostring(data.generalPlaystyle), 'already listed', tostring(C_LFGList.HasActiveEntryInfo()))
  try(tag .. ' CreateListing', C_LFGList.CreateListing, data)
  C_Timer.After(1.5, function() state(tag .. ' +1.5s') end)
  C_Timer.After(4, function() state(tag .. ' +4s') end)
end
local keyActs = {
  F1 = function() listShape('A one dungeon, no style', 1, false) end,
  F2 = function() listShape('B one dungeon, style', 1, true) end,
  F3 = function() listShape('C two dungeons, no style', 2, false) end,
  F4 = function() listShape('D two dungeons, style', 2, true) end,
  F9 = function() try('KEY RemoveListing', C_LFGList.RemoveListing); C_Timer.After(2, function() state('after unlist') end) end,
  F7 = function() try('KEY Search', C_LFGList.Search, 2, 0, 0, nil, false, nil, C_LFGList.GetAvailableActivities(2) or {}) end,
  F10 = function()
    state('STATE')
    local r = C_LFGListRoles and C_LFGListRoles.GetRoles(); if r then log('roles T/H/D', tostring(r.tank), tostring(r.healer), tostring(r.dps)) end
    log('lockdown', tostring(C_ChatInfo.InChatMessagingLockdown()), 'combat', tostring(InCombatLockdown()), 'zone', GetZoneText())
  end,
}
-- Round 4: the pointer, driven by a pretend Xbox pad (scripts/wow/pad.py).
--   Ctrl+Shift+F11: switch the game's pointer on, log where the mouse is
--   Ctrl+Shift+F12: try to open the right-click menu for yourself (stand-in for "Player menu" on a target)
--   pad D-pad up:    try to move the real mouse onto the test button (the D-pad rule)
--   pad D-pad left:  try a simulated left click (the test button logs it if it lands)
--   right stick:     count stick events, and try moving the mouse from a stick event once
local padf
local target = CreateFrame('Button', 'OmaProbeTarget', UIParent, 'UIPanelButtonTemplate')
target:SetSize(160, 40); target:SetPoint('CENTER', 300, 120); target:SetText('Pointer target')
target:RegisterForClicks('AnyUp'); target:SetScript('OnClick', function(_, b) log('TARGET BUTTON CLICKED with', tostring(b)) end)
target:SetScript('OnLeave', function() log('TARGET BUTTON left') end)
target:SetScript('OnMouseDown', function(_, b) log('TARGET mouse down', tostring(b)) end)
target:SetScript('OnEnter', function() log('TARGET BUTTON hovered') end)
local function mouse() local x, y = GetCursorPosition(); return math.floor(x) .. ',' .. math.floor(y) .. ' px' end
local function allowed() local t = {}; if C_LimitedInput and Enum.LimitedInputType then for k, v in pairs(Enum.LimitedInputType) do t[#t + 1] = k .. '=' .. tostring(C_LimitedInput.LimitedInputAllowed(v)) end end; return table.concat(t, ' ') end
keyActs.F11 = function()
  log('pad active', tostring(C_GamePad.GetActiveDeviceID()), 'CanGamePadControlCursor', tostring(CanGamePadControlCursor and CanGamePadControlCursor()))
  try('SetGamePadCursorControl(true)', SetGamePadCursorControl, true)
  log('cursor control on:', tostring(IsGamePadCursorControlEnabled()), 'mouse at', mouse())
  C_Timer.After(2.5, function() log('after right-stick tilt: cursor control on:', tostring(IsGamePadCursorControlEnabled()), 'mouse at', mouse()) end)
end
keyActs.F5 = function() padf:EnableGamePadButton(false); log('pad listener off: buttons go to bindings now', 'propagate fn', tostring(padf.SetPropagateGamePadInput ~= nil)) end
keyActs.F8 = function() log('MOUSE at', mouse(), 'cursor control on', tostring(IsGamePadCursorControlEnabled())) end
keyActs.F12 = function()
  local opened = false
  if UnitPopup_OpenMenu then opened = try('UnitPopup_OpenMenu SELF', UnitPopup_OpenMenu, 'SELF', { unit = 'player' }) end
  C_Timer.After(0.3, function()
    local m = Menu and Menu.GetManager and Menu.GetManager()
    local open = m and m.GetOpenMenu and m:GetOpenMenu()
    log('a menu is open:', tostring(open ~= nil))
    C_Timer.After(1.5, function() if CloseMenus then pcall(CloseMenus) end; if m and m.CloseMenus then pcall(m.CloseMenus, m) end end)
  end)
end
padf = CreateFrame('Frame', nil, UIParent)
padf:SetAllPoints(); padf:EnableMouse(false)
if padf.SetPropagateGamePadInput then padf:SetPropagateGamePadInput(true) end
if padf.EnableGamePadButton then padf:EnableGamePadButton(true) end
if padf.EnableGamePadStick then padf:EnableGamePadStick(true) end
local stickN, stickT, stickTried = 0, 0, false
padf:SetScript('OnGamePadButtonDown', function(_, b)
  log('pad button', b, 'allowed:', allowed())
  if b == 'PADDUP' then
    local x, y = target:GetCenter(); local s = target:GetEffectiveScale()
    try('SetCursorPosition from D-pad (pixels)', SetCursorPosition, x * s, y * s)
    C_Timer.After(0.2, function() log('mouse now at', mouse(), 'target centre', math.floor(x * s) .. ',' .. math.floor(y * s) .. ' px', 'over target', tostring(target:IsMouseOver())) end)
  elseif b == 'PADDLEFT' then
    try('SimulateMouseClick from D-pad', SimulateMouseClick, 'LeftButton')
  elseif b == 'PADDRIGHT' then
    try('SimulateMouseDown from D-pad', SimulateMouseDown, 'LeftButton')
  elseif b == 'PADDDOWN' then
    try('SimulateMouseUp from D-pad', SimulateMouseUp, 'LeftButton')
  end
end)
padf:SetScript('OnGamePadStick', function(_, stick, x, y, len)
  stickN = stickN + 1
  local now = GetTime(); if now - stickT > 1 then if stickN > 1 then log('stick events in the last second:', stickN, 'last stick', tostring(stick)) end; stickN, stickT = 0, now end
  if not stickTried and len and len > 0.5 then
    stickTried = true
    log('stick event, allowed:', allowed())
    try('SetCursorPosition from stick', SetCursorPosition, 200, 200); C_Timer.After(0.1, function() log('mouse after stick move', mouse()) end)
  end
end)

local binder = CreateFrame('Frame')
binder:RegisterEvent('PLAYER_ENTERING_WORLD')
binder:SetScript('OnEvent', function()
  if InCombatLockdown() or binder.done then return end
  binder.done = true
  for key, fn in pairs(keyActs) do
    local b = CreateFrame('Button', 'OmaProbeKey' .. key, UIParent)
    b:RegisterForClicks('AnyDown')
    b:SetScript('OnClick', function() log('-- key CTRL-SHIFT-' .. key); local ok, e = pcall(fn); if not ok then log('ERROR', e) end end)
    SetOverrideBindingClick(binder, true, 'CTRL-SHIFT-' .. key, b:GetName(), 'LeftButton')
  end
  log('key bindings set: CTRL-SHIFT-F1..F4, F7, F9, F10')
  -- Round 5: ConsolePort's way of clicking. A hidden secure button of type "click" points at the target; the pad
  -- button is bound to it, so the press reaches the target as a real hardware click, with no hover needed.
  --   A  -> left click on our test button       X -> right click on our test button
  --   Y  -> left click on a Blizzard button (the character micro button: opens the character window)
  local function secureClick(name, key, clickTarget, mouseButton)
    local s = CreateFrame('Button', name, UIParent, 'SecureActionButtonTemplate')
    s:RegisterForClicks('AnyUp', 'AnyDown')
    s:SetAttribute('type', 'click'); s:SetAttribute('clickbutton', clickTarget)
    s:HookScript('OnClick', function(_, b, down) if not down then log('secure click fired:', name, 'as', tostring(b)) end end)
    SetOverrideBindingClick(binder, true, key, name, mouseButton)
    log('bound', key, '->', name, mouseButton, 'target', tostring(clickTarget and clickTarget:GetName()))
  end
  secureClick('OmaProbeClickA', 'PAD1', OmaProbeTarget, 'LeftButton')
  secureClick('OmaProbeClickX', 'PAD3', OmaProbeTarget, 'RightButton')
  secureClick('OmaProbeClickY', 'PAD4', CharacterMicroButton, 'LeftButton')
  hooksecurefunc(CharacterFrame, 'Show', function() log('Blizzard character window opened') end)
end)

SLASH_OMAPROBE1 = '/omaprobe'
SlashCmdList.OMAPROBE = function() f:SetShown(not f:IsShown()) end
