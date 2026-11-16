-- OmaPointer (test build, 2026-11-13): a mouse pointer for the controller. Design 7 from reports/Controller cursor in
-- OmaCore.md, proven piece by piece on the Shadow with a pretend pad:
--   * the right stick moves the REAL mouse (the game allows SetCursorPosition on each stick event)
--   * the D-pad jumps the real mouse to the nearest button in that direction (ConsolePort's "best candidate" rule)
--   * A clicks and X right-clicks through a hidden secure "click" button (ConsolePort's way: a real, clean click)
--   * Y opens your target's right-click menu (Inspect, Invite, Trade, Whisper)
--   * B, walking (left stick) or a fight puts it away
-- Call it up: LB + right-stick click, or the "Pointer" macro this add-on puts on set 2, RT + X (if that slot is empty).
-- Nothing here runs on a timer by itself; everything follows a press or a stick movement.
local ADDON = ...
OmaPointerDB = OmaPointerDB or {}
local DEF = { speed = 1.4, deadzone = 0.10, outer = 0.08, curve = 2.0, boost = 0.5, rampDelay = 0.10, rampTime = 0.33, size = 1.0, chord = 'CTRL-PADRSTICK' }
local S
local function say(...)
  local t = { '|cffc9a35aOmaPointer:|r' }
  for i = 1, select('#', ...) do t[#t + 1] = tostring((select(i, ...))) end
  local line = table.concat(t, ' ')
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) end
  OmaPointerDB.log = OmaPointerDB.log or {}; table.insert(OmaPointerDB.log, date('%H:%M:%S ') .. line)
  if #OmaPointerDB.log > 200 then table.remove(OmaPointerDB.log, 1) end
end

-- ---------- the pointer you see (drawn by us, follows the real mouse) ----------
local ring = CreateFrame('Frame', 'OmaPointerRing', UIParent)
ring:SetFrameStrata('TOOLTIP'); ring:SetFrameLevel(9999); ring:SetSize(40, 40); ring:Hide()
ring:SetIgnoreParentScale(true); ring:EnableMouse(false)
local MASK = 'Interface\\CHARACTERFRAME\\TempPortraitAlphaMask'
local function disc(size, layer, sub)
  local t = ring:CreateTexture(nil, layer, nil, sub); t:SetSize(size, size); t:SetPoint('CENTER'); t:SetColorTexture(1, 1, 1, 1)
  local m = ring:CreateMaskTexture(); m:SetAllPoints(t); m:SetTexture(MASK, 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE'); t:AddMaskTexture(m)
  return t
end
local edge = disc(40, 'OVERLAY', 0); edge:SetVertexColor(0, 0, 0, .55)     -- dark rim so it shows on bright ground
local fill = disc(34, 'OVERLAY', 1); fill:SetVertexColor(1, 1, 1, .30)     -- soft disc
local dot = disc(8, 'OVERLAY', 2); dot:SetVertexColor(1, 1, 1, 1)          -- the exact point

-- ---------- state ----------
local P = { up = false, x = 0, y = 0, sx = 0, sy = 0, lastT = nil, full = 0, target = nil }
local function scr() local w, h = GetPhysicalScreenSize(); return w, h end
local function dbg(...)   -- always kept in OmaPointerDB.log (read after logout); shown in chat only with /omapointer debug
  local t = {}
  for i = 1, select('#', ...) do t[#t + 1] = tostring((select(i, ...))) end
  local line = table.concat(t, ' ')
  OmaPointerDB.log = OmaPointerDB.log or {}; table.insert(OmaPointerDB.log, date('%H:%M:%S ') .. line)
  if #OmaPointerDB.log > 300 then table.remove(OmaPointerDB.log, 1) end
  if OmaPointerDB.debug == true and DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cffc9a35aOmaPointer|r |cff888888' .. line .. '|r') end
end

-- ---------- secure pieces: the click buttons and the binding owner (cleared by the game itself in a fight) ----------
local header = CreateFrame('Frame', 'OmaPointerHeader', UIParent, 'SecureHandlerStateTemplate')
header:SetAttribute('_onstate-combat', [[ if newstate == 'in' then self:ClearBindings() end ]])
RegisterStateDriver(header, 'combat', '[combat] in; out')
local function clicker(name, btn)
  local b = CreateFrame('Button', name, UIParent, 'SecureActionButtonTemplate')
  b:RegisterForClicks('AnyUp', 'AnyDown'); b:SetAttribute('type', 'click')
  return b
end
local clickL, clickR = clicker('OmaPointerClickL'), clicker('OmaPointerClickR')

-- what is under the mouse and can be clicked
local function underMouse()
  local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
  if OmaPointerDB.debug ~= false and foci and foci[1] then P.lastFocus = foci[1].GetDebugName and foci[1]:GetDebugName() or tostring(foci[1]) end
  for _, f in ipairs(foci or {}) do
    local ok, yes = pcall(function()
      return f ~= WorldFrame and not f:IsForbidden() and (f:IsObjectType('Button') or (f:HasScript('OnMouseUp') and f:GetScript('OnMouseUp') ~= nil))
    end)
    if ok and yes then return f end
  end
end
local function aim()
  if InCombatLockdown() then return end
  local f = underMouse()
  if f ~= P.target then
    P.target = f
    clickL:SetAttribute('clickbutton', f); clickR:SetAttribute('clickbutton', f)
  end
  if f then dot:SetVertexColor(1, .82, .2, 1); fill:SetVertexColor(1, .82, .2, .35) else dot:SetVertexColor(1, 1, 1, 1); fill:SetVertexColor(1, 1, 1, .30) end
end

local function moveTo(x, y)
  local s = UIParent:GetEffectiveScale()
  local w, h = UIParent:GetWidth() * s, UIParent:GetHeight() * s
  P.x = math.max(0, math.min(w - 1, x)); P.y = math.max(0, math.min(h - 1, y))
  local ok = pcall(SetCursorPosition, P.x, P.y)   -- the game allows this only right after a controller input
  if not ok then local x, y = GetCursorPosition(); P.x, P.y = x, y end
  ring:ClearAllPoints(); ring:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', P.x / ring:GetEffectiveScale(), P.y / ring:GetEffectiveScale())  -- pixels to its own units
end

-- ---------- D-pad: nearest button that way (off-line ones count as farther: 1 + degrees / 15, ConsolePort's rule) ----------
local function blocked(f) return not f or (f.IsForbidden and f:IsForbidden()) end   -- Blizzard's locked frames: never touch
local function candidates(under)
  local out, seen = {}, {}
  local function walk(f, depth)
    if depth > 8 or blocked(f) or seen[f] then return end
    seen[f] = true
    local ok = pcall(function()
      if not f:IsVisible() then return end
      if f:IsObjectType('Button') and f:IsMouseEnabled() and f:GetEffectiveAlpha() > .2 then
        local l, b, w, h = f:GetScaledRect()
        if l and w > 4 and h > 4 then out[#out + 1] = { f = f, x = l + w / 2, y = b + h / 2 } end
      end
      for _, c in ipairs({ f:GetChildren() }) do walk(c, depth + 1) end
    end)
  end
  -- only windows that are open (never a sweep of every frame in the game). If the pointer is over a window, only that one.
  local tops = { UIParent:GetChildren() }
  if under then tops = { under } end
  for _, top in ipairs(tops) do
    if not blocked(top) and top ~= ring and top ~= header then
      pcall(function()
        if top:IsVisible() and top:IsMouseEnabled() then
          local strata = top:GetFrameStrata()
          if strata ~= 'BACKGROUND' and strata ~= 'TOOLTIP' then walk(top, 0) end
        end
      end)
    end
  end
  return out
end
local function windowUnder()
  local x, y = P.x, P.y
  local best
  for _, top in ipairs({ UIParent:GetChildren() }) do
    if not blocked(top) and top ~= ring and top ~= header then
      pcall(function()
        if top:IsVisible() and top:IsMouseEnabled() and top:GetFrameStrata() ~= 'BACKGROUND' then
          local l, b, w, h = top:GetScaledRect()
          if l and x >= l and x <= l + w and y >= b and y <= b + h and w < 1600 then best = top end
        end
      end)
    end
  end
  return best
end
-- lists that scroll (aux results, bags, Blizzard lists): the frame that owns the scrolling, if the button is in one
local function scrollOwner(f)
  local cur = f
  for _ = 1, 6 do
    if blocked(cur) then return end
    local ok, found = pcall(function()
      if cur:IsObjectType('ScrollFrame') or (cur:HasScript('OnMouseWheel') and cur:GetScript('OnMouseWheel')) then return cur end
      for _, c in ipairs({ cur:GetChildren() }) do
        if not blocked(c) and c:IsObjectType('ScrollFrame') then return cur end
      end
    end)
    if ok and found then return found end
    local okp, par = pcall(cur.GetParent, cur)
    if not okp or not par or par == UIParent then return end
    cur = par
  end
end
local function inside(f, owner)
  local cur = f
  for _ = 1, 12 do
    if not cur then return false end
    if cur == owner then return true end
    local ok, par = pcall(cur.GetParent, cur); if not ok then return false end
    cur = par
  end
  return false
end
local function step(dir)
  local ox, oy = P.x, P.y   -- the same units as GetScaledRect (scale-1 units, what GetCursorPosition gives)
  local best, bs
  local win = windowUnder()
  local list = candidates(win)
  if #list == 0 then list = candidates() end
  for _, c in ipairs(list) do
    local dx, dy = c.x - ox, c.y - oy
    local along = (dir == 'L' and -dx) or (dir == 'R' and dx) or (dir == 'U' and dy) or -dy
    if along > 2 then
      local off = (dir == 'L' or dir == 'R') and dy or dx
      local w = 1 + math.deg(math.atan2(math.abs(off), along)) / 15
      local sc = (dx * w) ^ 2 + (dy * w) ^ 2
      if not bs or sc < bs then best, bs = c, sc end
    end
  end
  -- at the edge of a list, up / down scroll the list and the pointer stays on its row
  if (dir == 'U' or dir == 'D') and P.target then
    local owner = scrollOwner(P.target)
    if owner and (not best or not inside(best.f, owner)) then
      local ok, err = pcall(SimulateMouseWheel, dir == 'D' and -1 or 1)
      dbg('scroll', dir, ok and 'ok' or ('failed: ' .. tostring(err)))
      return
    end
  end
  dbg('step', dir, 'in', win and (win:GetName() or 'a window') or 'everything', 'candidates', #list, 'picked', best and (best.f:GetName() or best.f:GetDebugName()) or 'none')
  if best then
    local ok, err = pcall(moveTo, best.x, best.y)
    if not ok then dbg('move failed:', err) end
    C_Timer.After(0.05, function() aim(); local x, y = GetCursorPosition(); dbg('mouse now', math.floor(x), math.floor(y), 'under it:', P.target and (P.target:GetName() or P.target:GetDebugName()) or 'nothing') end)
  end
end

-- ---------- pad input while the pointer is up ----------
local pad = CreateFrame('Frame', 'OmaPointerPad', UIParent)
pad:EnableMouse(false)
local function stickAmount(x, y)   -- scaled radial deadzone, outer threshold, power curve
  local m = math.sqrt(x * x + y * y)
  local t = (m - S.deadzone) / math.max(.05, 1 - S.deadzone - S.outer)
  if t <= 0 then return 0, 0, 0 end
  t = math.min(1, t)
  return t ^ S.curve, x / m, y / m
end
local DIR = { PADDUP = 'U', PADDDOWN = 'D', PADDLEFT = 'L', PADDRIGHT = 'R' }
pad:SetScript('OnGamePadButtonDown', function(_, b)
  if not P.up then return end
  dbg('pad button', b)
  if DIR[b] then local ok, err = pcall(step, DIR[b]); if not ok then dbg('step failed:', err) end end
end)
pad:SetScript('OnGamePadStick', function(_, stick, x, y)
  if not P.up then return end
  if stick == 'Movement' or stick == 'Left' then   -- the left stick: walking puts the pointer away
    if math.sqrt(x * x + y * y) > .5 and not InCombatLockdown() then OmaPointer_Hide('walking') end
    return
  end
  local now = GetTime(); local dt = P.lastT and math.min(.05, now - P.lastT) or 0; P.lastT = now
  local amt, ux, uy = stickAmount(x, y)
  if amt == 0 then P.full = 0; return end
  if amt >= .98 then P.full = P.full + dt else P.full = 0 end
  local boost = 1
  if P.full > S.rampDelay then boost = 1 + S.boost * math.min(1, (P.full - S.rampDelay) / math.max(.01, S.rampTime)) end
  if P.target then boost = boost * .5 end                     -- slow down over something clickable
  local h = UIParent:GetHeight() * UIParent:GetEffectiveScale()
  local v = S.speed * h * amt * boost * dt
  moveTo(P.x + ux * v, P.y + uy * v)
  aim()
end)

-- ---------- show / hide ----------
local function bindings()
  ClearOverrideBindings(header)
  SetOverrideBindingClick(header, true, 'PAD1', 'OmaPointerClickL', 'LeftButton')     -- A
  SetOverrideBindingClick(header, true, 'PAD3', 'OmaPointerClickR', 'RightButton')    -- X
  SetOverrideBindingClick(header, true, 'PAD2', 'OmaPointerOff', 'LeftButton')        -- B
  SetOverrideBindingClick(header, true, 'PAD4', 'OmaPointerMenu', 'LeftButton')       -- Y
  -- the D-pad is read straight from the pad (below); these bindings only stop it casting your D-pad spells meanwhile
  for _, k in ipairs({ 'PADDUP', 'PADDDOWN', 'PADDLEFT', 'PADDRIGHT' }) do SetOverrideBindingClick(header, true, k, 'OmaPointerNoop', 'LeftButton') end
end
function OmaPointer_Show()
  if InCombatLockdown() then say('not in a fight'); return end
  local auxLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded('auxForever')
  if P.ah and auxLoaded then say('auxForever has its own controller controls here (D-pad, A, X, Y, LB/RB), so the pointer stays away.'); return end
  if P.up then return end
  P.up = true
  -- with a pad in use WoW pins the mouse to the screen centre unless its own pad pointer is on; ConsolePort's trick:
  -- stop sticks from switching it straight off again, then switch it on
  P.oldSticks = C_CVar.GetCVar('GamePadCursorAutoDisableSticks')
  C_CVar.SetCVar('GamePadCursorAutoDisableSticks', '0')
  pcall(SetGamePadCursorControl, true)
  dbg('game pad pointer on:', tostring(IsGamePadCursorControlEnabled()))
  local x, y = GetCursorPosition()
  local w, h = scr()
  if x <= 0 and y <= 0 then x, y = w / 2, h / 2 end
  P.x, P.y, P.lastT, P.full = x, y, nil, 0
  pad:EnableGamePadStick(true); pad:EnableGamePadButton(true)
  if pad.SetPropagateKeyboardInput then pad:SetPropagateKeyboardInput(true) end   -- A, X, Y, B still reach their bindings
  local ok, err = pcall(bindings)
  if not ok then dbg('bindings failed:', err) end
  ring:ClearAllPoints(); ring:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', P.x / ring:GetEffectiveScale(), P.y / ring:GetEffectiveScale())
  dbg('pointer up at', math.floor(P.x), math.floor(P.y))
  ring:SetScale(S.size); ring:Show(); aim()
end
function OmaPointer_Hide(why)
  if not P.up then return end
  P.up = false
  pad:EnableGamePadStick(false); pad:EnableGamePadButton(false)
  ring:Hide()
  pcall(SetGamePadCursorControl, false)
  if P.oldSticks then C_CVar.SetCVar('GamePadCursorAutoDisableSticks', P.oldSticks); P.oldSticks = nil end
  if not InCombatLockdown() then ClearOverrideBindings(header); clickL:SetAttribute('clickbutton', nil); clickR:SetAttribute('clickbutton', nil) end
  P.target = nil
end
local function toggle() if P.up then OmaPointer_Hide('button') else OmaPointer_Show() end end

local function plain(name, fn)
  local b = CreateFrame('Button', name, UIParent); b:RegisterForClicks('AnyDown'); b:SetScript('OnClick', fn); return b
end
plain('OmaPointerToggle', toggle)
plain('OmaPointerOff', function() OmaPointer_Hide('B') end)
plain('OmaPointerNoop', function() end)
plain('OmaPointerMenu', function()
  if UnitExists('target') and UnitIsPlayer('target') and UnitPopup_OpenMenu then
    local ok = pcall(UnitPopup_OpenMenu, UnitIsUnit('target', 'player') and 'SELF' or (UnitInParty('target') and 'PARTY' or 'PLAYER'), { unit = 'target', name = UnitName('target') })
    if not ok then say('could not open the menu') end
  else
    say('target a player first, then Y opens their menu')
  end
end)

-- ---------- setup: the chord, the macro on set 2 RT + X, combat ----------
local ev = CreateFrame('Frame')
ev:RegisterEvent('PLAYER_LOGIN'); ev:RegisterEvent('PLAYER_REGEN_DISABLED')
-- the auction house: auxForever has its own controller support there, so the pointer stays out of its way
for _, e in ipairs({ 'AUCTION_HOUSE_SHOW', 'AUCTION_HOUSE_CLOSED' }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript('OnEvent', function(_, e)
  if e == 'AUCTION_HOUSE_SHOW' then P.ah = true; return end
  if e == 'AUCTION_HOUSE_CLOSED' then P.ah = false; return end
  if e == 'PLAYER_REGEN_DISABLED' then if P.up then P.up = false; ring:Hide(); pad:EnableGamePadStick(false); pad:EnableGamePadButton(false); P.target = nil; pcall(SetGamePadCursorControl, false); if P.oldSticks then C_CVar.SetCVar('GamePadCursorAutoDisableSticks', P.oldSticks); P.oldSticks = nil end end; return end
  S = OmaPointerDB
  for k, v in pairs(DEF) do if S[k] == nil then S[k] = v end end
  -- the chord (owned by a normal frame, so it survives; changes only out of combat)
  local owner = CreateFrame('Frame', 'OmaPointerChordOwner')
  SetOverrideBindingClick(owner, true, S.chord, 'OmaPointerToggle', 'LeftButton')
  -- the macro on set 2, RT + X (slot 225), only if that slot is empty
  say('chord bound:', S.chord, '->', tostring(GetBindingAction(S.chord, true)))
  local i = GetMacroIndexByName('Pointer')
  if i == 0 then local ok, r = pcall(CreateMacro, 'Pointer', 'INV_Misc_Spyglass_02', '/click OmaPointerToggle', true); i = ok and r or 0; if not ok then say('could not make the macro:', r) end end
  local slot = 225
  if i and i > 0 and not HasAction(slot) and not InCombatLockdown() then
    PickupMacro('Pointer'); PlaceAction(slot); ClearCursor()
    say('put the Pointer button on set 2, RT + X')
  end
  say('ready. The Pointer button (set 2, RT + X) or LB + right-stick click calls it up. Right stick moves, D-pad steps (and scrolls at the end of a list), A click, X right-click, Y player menu, B away.')
end)

SLASH_OMAPOINTER1 = '/omapointer'
SlashCmdList.OMAPOINTER = function(msg)
  local k, v = msg:match('^(%S+)%s+(%S+)$')
  if k and S[k] ~= nil and tonumber(v) then S[k] = tonumber(v); say(k, '=', S[k]); return end
  if msg == 'debug' then S.debug = not S.debug; say('test messages', S.debug and 'on' or 'off'); return end
  if msg == 'reset' then for kk, vv in pairs(DEF) do S[kk] = vv end; say('settings reset'); return end
  if msg == '' then toggle(); return end
  say('speed', S.speed, 'deadzone', S.deadzone, 'outer', S.outer, 'curve', S.curve, 'boost', S.boost, 'size', S.size, '| /omapointer speed 1.8')
end
