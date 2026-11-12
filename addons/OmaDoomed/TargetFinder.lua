-- The target's health bar: Blizzard's TargetFrame, EllesmereUI's target frame, then a saved frame path (OmaDoomedDB.
-- targetPath, set by typing it or by Pick). ns.targetBar() -> bar, portrait, source, blizzard, hidden.
--   hidden: the bar exists but isn't on screen; the kill bar then draws nothing and says so once.
-- The frame path, its Pick and the known replacement frames are adapted from Does It Die (MIT, notice in
-- Track/LICENSE-DoesItDie), Frames.lua. Pick: out of combat only, with the mouse; typing the path works for everyone.
local ADDON, ns = ...
local Secret = ns.core.Secret
local PM = ns.plates

local function index(t, k) return t[k] end
local function get(t, k)
  if type(t) ~= 'table' then return nil end
  local v = rawget(t, k); if v ~= nil then return v end
  local ok, r = pcall(index, t, k); if ok then return r end
end
local function call(o, m, ...)   -- always one value (nil when missing, failed or hidden)
  local f = type(o) == 'table' and get(o, m); if type(f) ~= 'function' then return nil end
  local v = Secret.call(f, o, ...); return v
end
local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

-- "GlobalFrame.key.key" -> that frame or texture, or nil (some add-ons build their frames late)
function ns.resolveFramePath(path)
  path = trim(path); if path == '' then return nil end
  local obj
  for part in path:gmatch('[^%.]+') do
    if obj == nil then obj = _G[part] else obj = get(obj, part) end
    if type(obj) ~= 'table' then return nil end
  end
  if type(get(obj, 'GetObjectType')) == 'function' and type(get(obj, 'GetWidth')) == 'function' then return obj end
end

local function keyIn(region, parent)
  local k = call(region, 'GetParentKey')
  if type(k) == 'string' and get(parent, k) == region then return k end
  local ok, found = pcall(function()
    for kk, v in pairs(parent) do if v == region and type(kk) == 'string' and kk:match('^[%a_][%w_]*$') then return kk end end
  end)
  if ok then return found end
end
local function globalName(f)
  local n = call(f, 'GetName')
  if type(n) == 'string' and not n:find('.', 1, true) and _G[n] == f then return n end
end
-- a path that finds `region` again after a /reload, or nil (checked: it must lead back to region itself)
function ns.framePath(region)
  local parts, cur = {}, region
  for _ = 1, 12 do
    local name = globalName(cur)
    if name then
      table.insert(parts, 1, name)
      local path = table.concat(parts, '.')
      return ns.resolveFramePath(path) == region and path or nil
    end
    local parent = call(cur, 'GetParent'); if not parent then break end
    local k = keyIn(cur, parent); if not k then break end
    table.insert(parts, 1, k); cur = parent
  end
  -- moved into an unnamed holder but still a field of a named ancestor: the lowest key wins (the same every session)
  local anc = call(region, 'GetParent')
  for _ = 1, 12 do
    if not anc then return nil end
    local name = globalName(anc)
    if name then
      local ok, keys = pcall(function()
        local found = {}
        for k, v in pairs(anc) do if v == region and type(k) == 'string' and k:match('^[%a_][%w_]*$') then found[#found + 1] = k end end
        table.sort(found); return found
      end)
      if ok and keys[1] then local path = name .. '.' .. keys[1]; if ns.resolveFramePath(path) == region then return path end end
    end
    anc = call(anc, 'GetParent')
  end
end

-- ---------- the finder ----------
local function blizzard()
  local tf = _G.TargetFrame
  local main = get(get(tf, 'TargetFrameContent'), 'TargetFrameContentMain')
  local hb = get(get(main, 'HealthBarsContainer'), 'HealthBar')
  local portrait = get(get(tf, 'TargetFrameContainer'), 'Portrait')
  if type(hb) == 'table' then return hb, portrait end
end
ns.blizzardTargetBar = blizzard

-- known replacement target frames: global name, bar key, portrait key (frame names are facts, from their code)
local KNOWN = { { frame = 'EllesmereUIUnitFrames_Target', bar = 'Health', portrait = 'Portrait', name = 'EllesmereUI' } }
-- a portrait next to a picked bar: a Portrait field on the bar's parents, if shown
local function portraitNear(bar)
  local cur = bar
  for _ = 1, 3 do
    cur = call(cur, 'GetParent'); if not cur then return nil end
    local p = get(cur, 'Portrait') or get(cur, 'portrait')
    if type(p) == 'table' and call(p, 'IsVisible') == true then return p end
  end
end

-- bar, portrait, source, blizzard, hidden
function ns.targetBar()
  local hb, portrait = blizzard()
  if hb and PM.onScreen(hb) then return hb, portrait, 'Blizzard', true end
  local hidden
  for _, k in ipairs(KNOWN) do
    local bar = ns.resolveFramePath(k.frame .. '.' .. k.bar)
    if bar then
      local p = ns.resolveFramePath(k.frame .. '.' .. k.portrait)
      if p and call(p, 'IsVisible') ~= true then p = nil end
      if PM.onScreen(bar) then return bar, p, k.name, false end
      hidden = hidden or { bar, p, k.name }
    end
  end
  local path = ns.db and trim(ns.db.targetPath)
  if path and path ~= '' then
    local bar = ns.resolveFramePath(path)
    if bar and PM.onScreen(bar) then return bar, portraitNear(bar), 'path ' .. path, false end
    if bar then hidden = hidden or { bar, nil, 'path ' .. path } end
  end
  -- nothing on screen: say which one we would use (another add-on's frame first: Blizzard's is hidden on purpose then)
  if hidden then return hidden[1], hidden[2], hidden[3], false, true end
  if hb then return hb, portrait, 'Blizzard', true, true end
  return nil, nil, 'none'
end

function ns.targetBarLine()
  local bar, portrait, source, _, hidden = ns.targetBar()
  local s, l = PM.layerOf(bar)
  return ('target frame: %s%s%s, layer %s %s%s'):format(source or 'none', hidden and ' (hidden)' or '',
    bar and (PM.reversed(bar) and ', fills right to left' or ', fills left to right') or '', s or '?', l and tostring(l) or '?',
    portrait and '' or ', no portrait')
end

-- ---------- Pick: click the target's health bar ----------
local picker, pickFrame, edge, label
local function focus()
  if GetMouseFoci then local f = GetMouseFoci(); return f and f[1] end
  if GetMouseFocus then return GetMouseFocus() end
end
local function root(region)
  local cur = region
  for _ = 1, 20 do local p = call(cur, 'GetParent'); if not p or p == UIParent then return cur end; cur = p end
  return cur
end
-- the smallest shown StatusBar under the mouse, inside the frame the mouse is on
local function under(region)
  if call(region, 'IsVisible') ~= true then return nil end
  local ok, l, b, w, h = pcall(region.GetRect, region)
  if not ok or type(l) ~= 'number' or Secret.is(b) or Secret.is(w) or Secret.is(h) or Secret.is(l) then return nil end
  local over = call(region, 'IsMouseOver')
  if over == nil then
    local sc = call(region, 'GetEffectiveScale'); if type(sc) ~= 'number' or sc <= 0 then return nil end
    local x, y = GetCursorPosition(); x, y = x / sc, y / sc
    over = x >= l and x <= l + w and y >= b and y <= b + h
  end
  if over then return w * h end
end
local function candidate()
  local f = focus()
  if not f or f == WorldFrame or f == pickFrame then return nil end
  local best, area
  local function visit(fr, depth)
    if call(fr, 'GetObjectType') == 'StatusBar' then local a = under(fr); if a and (not area or a < area) then best, area = fr, a end end
    if depth < 8 then for _, c in ipairs({ fr:GetChildren() }) do visit(c, depth + 1) end end
  end
  visit(root(f), 0)
  return best
end
local function stop() picker = nil; if pickFrame then pickFrame:Hide() end end
ns.stopPick = stop

local function makePickFrame()
  pickFrame = CreateFrame('Frame', nil, UIParent); pickFrame:SetFrameStrata('TOOLTIP'); pickFrame:Hide()
  edge = CreateFrame('Frame', nil, pickFrame); edge:SetFrameStrata('TOOLTIP')
  for _, side in ipairs({ 'TOP', 'BOTTOM', 'LEFT', 'RIGHT' }) do
    local t = edge:CreateTexture(nil, 'OVERLAY'); t:SetColorTexture(206 / 255, 160 / 255, 44 / 255, 1)
    if side == 'TOP' or side == 'BOTTOM' then t:SetHeight(2); t:SetPoint(side .. 'LEFT'); t:SetPoint(side .. 'RIGHT')
    else t:SetWidth(2); t:SetPoint('TOP' .. side); t:SetPoint('BOTTOM' .. side) end
  end
  label = pickFrame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight'); label:SetPoint('TOP', UIParent, 'TOP', 0, -120)
  local acc = 0
  pickFrame:SetScript('OnUpdate', function(_, dt)
    acc = acc + dt; if not picker or acc < .05 then return end
    acc = 0
    local ok, err = pcall(function()
      local c = candidate(); picker.c = c
      edge:ClearAllPoints()
      if c then edge:SetAllPoints(c); edge:Show() else edge:Hide() end
      label:SetText("OmaDoomed: click your target's health bar (right-click cancels)\n" .. (c and (ns.framePath(c) or 'this bar has no name to save') or ''))
    end)
    if not ok then stop(); ns.error('pick: ' .. tostring(err)); ns.say('pick stopped after an error. You can type the name: /omadoomed frame <name>') end
  end)
  pcall(pickFrame.RegisterEvent, pickFrame, 'GLOBAL_MOUSE_DOWN')
  pickFrame:RegisterEvent('PLAYER_REGEN_DISABLED')
  pickFrame:SetScript('OnEvent', function(_, e, button)
    if not picker then return end
    local cur = picker; stop()
    if e == 'PLAYER_REGEN_DISABLED' then ns.say('pick cancelled: a fight started.'); return end
    if button == 'RightButton' then ns.say('pick cancelled.'); return end
    local path = cur.c and ns.framePath(cur.c)
    if not cur.c then ns.say('no health bar there.'); return end
    if not path then ns.say("that bar has no name to save. Try the frame around it, or type its name: /omadoomed frame <name>"); return end
    cur.done(path)
  end)
end

local function setPath(path)
  ns.db.targetPath = path
  ns.bus:Fire('TARGET_BAR')
  ns.say(path == '' and "target bar: back to finding it by itself." or ('target bar: ' .. path .. (ns.resolveFramePath(path) and '.' or " (not there right now; it's used once it shows).")))
end
function ns.startPick()
  if InCombatLockdown() then ns.say('pick works out of combat only.'); return end
  if not pickFrame then makePickFrame() end
  picker = { done = setPath }
  pickFrame:Show()
  ns.say("pick: close Options, then click your target's health bar. Right-click cancels.")
end

-- /omadoomed frame pick | clear | <name>
function ns.frameSlash(rest)
  rest = trim(rest)
  if rest == '' then ns.say(ns.targetBarLine()); ns.say('/omadoomed frame pick, /omadoomed frame <name>, /omadoomed frame clear'); return end
  if rest == 'pick' then return ns.startPick() end
  if rest == 'clear' then return setPath('') end
  setPath(rest)
end
