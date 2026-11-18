-- OmaDoomed: the team row (sheet 104 v7, approved 2026-11-17 "Yes, build it"). Under your target's frame, below its
-- cast bar and your rings: every other player's debuff on the mob, one line per class, each square in a thin neon frame
-- in that class's colour (Gemini art, art/team). Blizzard's own squares under the target frame are hidden on enemies so
-- its cast bar keeps one fixed spot right under the bars.
-- How it knows the class without reading anything hidden: one aura group per class, filtered to that class's spell IDs
-- (ClassAuras.lua, every rank). Blizzard applies the filter inside its own code; an enemy's debuffs may be filtered by
-- spell ID. Anything not on a class list goes on the last line in a neutral frame.
-- In a big group: classes in your group get full lines first, up to T.MAXLINES; the rest show as small dots in their
-- colour on the last line. Decided from your roster (plain) out of combat; empty lines take no space (the game's layout).
local ADDON, ns = ...
local R = ns.rings
local T = { MAXLINES = 4 }
ns.team = T

local ART = 'Interface\\AddOns\\OmaDoomed\\art\\team\\'
local MASK = 'Interface\\AddOns\\OmaDoomed\\Art\\rings\\softsq_mask'
local SQ, ICON, FRAMEW, STEP, DOT = 30, 26, 40, 32, 10
local FILTER = 'HARMFUL|!PLAYER'
local SORT = (AuraContainerSortMethod and AuraContainerSortMethod.AuraInstanceIDOnly) or 8
T.SQ, T.STEP = SQ, STEP

local function db() return ns.db and ns.db.rings end
function T.on() local d = db(); return d ~= nil and d.team ~= false end

-- ---------- the squares (all of it at creation: aura buttons are locked once initializeFrame returns) ----------
local function text(parent, size, point, x, y)
  local top = CreateFrame('Frame', nil, parent); top:SetAllPoints(parent); top:SetFrameLevel(parent:GetFrameLevel() + 3)
  local fs = top:CreateFontString(nil, 'OVERLAY')
  fs:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF', size, 'OUTLINE'); fs:SetPoint(point, parent, point, x, y)
  fs:SetTextColor(1, 1, 1, 1); fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
  return fs
end
-- the squares take the mouse (2026-11-17, "tooltips on hover for other players spells"): no script of ours on them,
-- so the game's own aura tooltip shows. The class dots stay click-through.
function T.squareInit(key)
  return function(b)
    b:SetSize(SQ, SQ); pcall(b.EnableMouse, b, true)
    local icon = b:CreateTexture(nil, 'ARTWORK', nil, 0)
    icon:SetSize(ICON, ICON); icon:SetPoint('CENTER', b, 'CENTER'); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local m = b:CreateMaskTexture(); m:SetTexture(MASK, 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE', 'TRILINEAR'); m:SetAllPoints(icon)
    icon:AddMaskTexture(m)
    local fr = b:CreateTexture(nil, 'OVERLAY', nil, 1)
    fr:SetTexture(ART .. 'frame_' .. key, nil, nil, 'TRILINEAR'); fr:SetSize(FRAMEW, FRAMEW); fr:SetPoint('CENTER', b, 'CENTER')
    local cd = CreateFrame('Cooldown', nil, b); cd:SetAllPoints(b)
    pcall(cd.SetDrawSwipe, cd, false); pcall(cd.SetDrawEdge, cd, false); pcall(cd.SetDrawBling, cd, false)
    pcall(cd.SetHideCountdownNumbers, cd, true); pcall(cd.SetUseAuraDisplayTime, cd, true)
    b:SetIcon(icon); b:SetDurationCooldown(cd)
    pcall(b.SetDurationText, b, text(b, 11, 'BOTTOM', 0, 2), R.textOpts and R.textOpts(R.numFmt and R.numFmt()) or {})
    if b.SetApplicationCount then pcall(b.SetApplicationCount, b, text(b, 10, 'TOPRIGHT', -2, -1)) end
  end
end
function T.dotInit(key)
  return function(b)
    b:SetSize(DOT, DOT); pcall(b.EnableMouse, b, false)
    local t = b:CreateTexture(nil, 'ARTWORK'); t:SetTexture(ART .. 'dot_' .. key, nil, nil, 'TRILINEAR')
    t:SetSize(DOT * 1.6, DOT * 1.6); t:SetPoint('CENTER', b, 'CENTER')
  end
end

-- ---------- the container: one group per class (full), the neutral line, then one small dot group per class ----------
local function idSet(list) local s = {}; for _, id in ipairs(list) do s[id] = true end; return s end
local FULL = { forceNewLine = true, elementSpacing = STEP - SQ, lineSpacing = STEP - SQ, groupLineSpacing = STEP - SQ }
local function dotLayout(first) return { forceNewLine = first and true or false, elementSpacing = 2, groupSpacing = 6, elementWidth = DOT, elementHeight = DOT } end

function T.build()
  if T.c or InCombatLockdown() or not TargetFrame or not ns.CLASS_AURAS or not T.on() then return T.c end
  T.holder = T.holder or CreateFrame('Frame', nil, TargetFrame); T.holder:SetSize(1, 1)
  local ok, c = pcall(CreateFrame, 'AuraContainer', nil, T.holder, 'CustomAuraContainerTemplate')
  if not ok or not c then R.log('team row failed: ' .. tostring(c)); return nil end
  pcall(c.SetEditModePreviewEnabled, c, false)
  c:SetSize(STEP * 8, 1)
  pcall(c.SetFlowLayoutMaximumLineSize, c, STEP * 8 + 0.01)
  local all = {}
  for _, e in ipairs(ns.CLASS_AURAS) do
    local key = e.class:lower()
    for _, id in ipairs(e.ids) do all[id] = true end
    local okG, err = pcall(c.AddAuraGroup, c, 'full_' .. key, FILTER, { initializeFrame = T.squareInit(key), maxFrameCount = 8,
      candidateFilters = { includeSpellIDs = idSet(e.ids) }, sortMethod = SORT, layout = FULL })
    if not okG then R.log('team row ' .. key .. ': ' .. tostring(err)) end
  end
  pcall(c.AddAuraGroup, c, 'other', FILTER, { initializeFrame = T.squareInit('other'), maxFrameCount = 8,
    candidateFilters = { excludeSpellIDs = all }, sortMethod = SORT, layout = FULL })
  for _, e in ipairs(ns.CLASS_AURAS) do
    local key = e.class:lower()
    pcall(c.AddAuraGroup, c, 'dot_' .. key, FILTER, { initializeFrame = T.dotInit(key), maxFrameCount = 6,
      candidateFilters = { includeSpellIDs = idSet(e.ids) }, sortMethod = SORT, layout = dotLayout(false) })
  end
  pcall(c.SetFrameStrata, c, 'MEDIUM'); c:SetFrameLevel(TargetFrame:GetFrameLevel() + 20)
  T.c = c
  T.place(); T.roster()
  c:SetUnit('target')
  return c
end

-- under your rings when they sit on the target frame, else right under the bars; down by the cast bar while it shows.
-- The container hangs off T.holder (a plain frame of ours), so the holder can move in a fight.
function T.place()
  local h, c = T.holder, T.c; if not h then return end
  h:ClearAllPoints()
  local anchor, y = R.frameRowBottom and R.frameRowBottom()
  if anchor then h:SetPoint('TOPLEFT', anchor, 'BOTTOMLEFT', 0, -(y or 4))
  else h:SetPoint('TOPLEFT', TargetFrame, 'BOTTOMLEFT', 24, -(4 + (R.castDrop and R.castDrop() or 0))) end
  if c and not InCombatLockdown() then c:ClearAllPoints(); c:SetPoint('TOPLEFT', h, 'TOPLEFT') end
end
-- Blizzard's target cast bar showing / hiding: slide the rows (our own frames only; allowed in a fight)
local function castChanged(on)
  R.castShown = on and true or false
  if R.placeFrameRow then R.placeFrameRow() end
  T.place()
end
T.castChanged = castChanged
local hooked
function T.hookCastBar()
  local bar = _G.TargetFrameSpellBar or (TargetFrame and TargetFrame.spellbar)
  if hooked or type(bar) ~= 'table' or type(bar.HookScript) ~= 'function' then return end
  hooked = true
  bar:HookScript('OnShow', function() castChanged(true) end)
  bar:HookScript('OnHide', function() castChanged(false) end)
  local ok, shown = pcall(bar.IsShown, bar); if ok and shown == true then castChanged(true) end
end

-- which classes get a full line: your group's classes first (fixed order), then the rest, up to MAXLINES; the others dots
function T.lines()
  local inGroup, order = {}, {}
  local function add(u) local ok, _, cls = pcall(UnitClass, u); if ok and type(cls) == 'string' then inGroup[cls] = true end end
  if IsInRaid and IsInRaid() then for i = 1, 40 do add('raid' .. i) end else for i = 1, 4 do add('party' .. i) end end
  for _, e in ipairs(ns.CLASS_AURAS or {}) do if inGroup[e.class] then order[#order + 1] = e.class end end
  for _, e in ipairs(ns.CLASS_AURAS or {}) do if not inGroup[e.class] then order[#order + 1] = e.class end end
  local full = {}
  local grouped = (IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())
  for i, cls in ipairs(order) do full[cls] = (not grouped) or i <= T.MAXLINES end   -- solo: every class its own line
  return full
end
function T.roster()
  local c = T.c; if not c or InCombatLockdown() then return end
  local full, first = T.lines(), true
  for _, e in ipairs(ns.CLASS_AURAS) do
    local key, f = e.class:lower(), full[e.class]
    pcall(c.SetAuraGroupEnabled, c, 'full_' .. key, f)
    pcall(c.SetAuraGroupEnabled, c, 'dot_' .. key, not f)
    if not f then pcall(c.SetAuraGroupLayout, c, 'dot_' .. key, dotLayout(first)); first = false end
  end
  T.full = full
end

function T.visible()
  local c = T.c; if not c then return end
  local d = db()
  local show = T.on() and d.enabled ~= false and UnitExists('target') and UnitCanAttack('player', 'target')
  if not InCombatLockdown() then c:SetShown(show and true or false) else c:SetAlpha(show and 1 or 0) end
  if show then c:SetAlpha(1) end
end

-- a warlock's session only (Core.lua runs ns.starts at a warlock's login)
local ev = CreateFrame('Frame')
ns.starts[#ns.starts + 1] = function()
  for _, e in ipairs({ 'PLAYER_ENTERING_WORLD', 'GROUP_ROSTER_UPDATE', 'PLAYER_REGEN_ENABLED', 'PLAYER_TARGET_CHANGED' }) do pcall(ev.RegisterEvent, ev, e) end
  C_Timer.After(1, function() if R.db and not T.c then T.build(); T.visible() end; T.hookCastBar() end)
end
ev:SetScript('OnEvent', function(_, e)
  if not R.db then return end
  if e == 'PLAYER_TARGET_CHANGED' then T.visible(); return end
  if not T.c then T.build() end
  T.hookCastBar(); T.roster(); T.place(); T.visible()
end)
