-- OmaDoomed, the rings (was Omashu Plates / OmaPlates; one add-on since 2026-11-11: "the now unified name is
-- omadoomed"): your DoTs above every enemy nameplate, in the Omashu skin (mockup 15, section C, style 3, approved).
-- Rules this file is built on: reports/Nameplate DoT rules.md and research_notes/Nameplate DoT timers/.
--
-- The one hard rule on Forever: addon code may not read enemy auras in combat (every C_UnitAuras call errors). So we
-- never read them. Blizzard's own AuraContainer (CustomAuraContainerTemplate) reads them untainted and drives the
-- countdown, the swipes and the colour curves for us. Our code only builds the look, once, in initializeFrame, and
-- moves containers between plates.
--
-- Each plate gets a PAIR of containers with identical groups, sizes and sort, so their buttons land on the same spots:
--   ring  (below): dark backing disc, the colour ring, and a cooldown swipe that covers the spent part of the ring.
--   main  (above, a child of ring): round icon, brass bezel, a 50% dark swipe on the icon, the countdown number.
-- Why two: a button has exactly one duration text binding (the only thing that changes colour by "seconds left").
-- The number needs one. The ring needs another, so it can turn gold and breathe in the last 3 seconds. The ring is a
-- font glyph (art/OmashuRing.ttf, its "O" is our ring) so a text colour curve can recolour it.
-- If that font or its formatter fails the load check, the ring falls back to a plain tinted texture that never goes
-- gold, and the NUMBER goes gold instead (the ThreatPlates "Highlight Expiring" route, proven on Forever).

local ADDON, ns = ...
local ART = 'Interface\\AddOns\\OmaDoomed\\Art\\rings\\'
local RING_FONT = ART .. 'OmashuRing.ttf'
local NUM_FONT = STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'

-- Blizzard's own nameplate aura size, so nothing needs tuning: AURA_ITEM_HEIGHT 25 x Nameplate Size Huge (1.6) x
-- Debuff Scale 140% (1.4) = 56 units, square, no gaps; at that scale Blizzard puts 6 per row and grows rows upward.
local S = 25 * 1.6                -- 2026-11-10: 56 was too big; Blizzard Huge at 100% = 40
local PER_ROW = 6
local FRAME_ROW = 5                 -- target frame row (Haunt / Target frame): 5 rings fit under the bars, before the level badge
local FRAME_SCALE = 0.56            -- sheet 42 B: 40 px under the frame (they were 72 px over it: "too big")
local FRAME_GAP = 6                 -- between the bars' bottom edge and the rings (2026-11-11: was 3, the rings kissed the frame; ~5 px)
local FRAME_SPACE = 3               -- between rings in the row (they touched: "19" and "14" ran together)
local FRAME_LEFT = 7                -- the first ring's edge lines up with the frame's brass border (it stuck out ~7 px)
local OS = S * 0.6                  -- other players' DoTs: 60% size
local OTHERS_ALPHA = 0.55           -- and 55% alpha (settings 'Other players' DoTs' replaces it when the rings load)
local OTHERS_GAP = S * 6 / 70       -- mockup: 6 units gap on a 70-unit cell
local ICON_SIZE = S * 0.756         -- mockup draws the icon at 1.8r = 0.756 cell, clipped round by the mask
local GAP = 4                       -- row bottom sits this far above the name (mockup: ~5 of 70)
local LOW, BREATH, LOW_ALPHA = 3, 1.5, 0.3   -- last 3 s: gold, one breath every 1.5 s, down to 30%

local GOLD = { 0xff / 255, 0xf0 / 255, 0xb0 / 255 }
local WHITE = { 1, 1, 1 }
local DARK_BRASS = { 0x8a / 255, 0x6a / 255, 0x2a / 255 }

-- The DoTs, curses and channels, one group each, in Spells.lua's order with its ring colours and IDs. Belt and
-- braces: at login we also add whatever ID the game returns for each name, and we learn the exact ID every time you
-- cast one (UNIT_SPELLCAST_SUCCEEDED).
local Spells, Anim, Secret = ns.spells, ns.core.Anim, ns.core.Secret
local SPELLS = Spells.list

local OWN = 'HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY'        -- PLAYER = you, your pet or vehicle (AuraUtil.lua)
local OTHERS = 'HARMFUL|!PLAYER|INCLUDE_NAME_PLATE_ONLY'    -- "!" negates (AuraUtil.lua, forever branch)
local SORT = (AuraContainerSortMethod and AuraContainerSortMethod.AuraInstanceIDOnly) or 8   -- oldest first
local UP = (Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up) or 1
local REMAINING = (Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration) or 0

local POOL_START, POOL_MIN_FREE, POOL_MAX = 24, 4, 40   -- review #7: 12 ran out in big pulls

local db
local BC                            -- BlizzardControls.lua: Blizzard's nameplate debuffs and target-frame squares
local function say(m) print('|cffb48cffOmaDoomed:|r ' .. m) end
-- failures go to the error list (/omadoomed errors and bug reports); start-up probes are kept quiet
local function log(m) if ns.err and not m:find('^probe') and not m:find('^number formatter') then ns.err('rings: ' .. m) end end
local secret = Secret.is

-- ---------- what the load check decides (out of combat, before any container exists) ----------
local GLYPH = false           -- true: the ring is the font glyph and goes gold + breathes
local NUM_FMT, RING_FMT, BINDING
local numCurve, ringCurves, mineRingCurve = nil, {}, nil
local othersOK = true         -- false if the game refused the "!PLAYER" group

local function breath(x)
  -- x = seconds left (0..3). 1 at 3 s, 0.3 at 2.25 s, 1 at 1.5 s, 0.3 at 0.75 s, 1 at 0 s.
  return Anim.breath(x, LOW, BREATH, LOW_ALPHA)
end

local function makeCurve(normal, low, lowBreathes)
  -- Blizzard re-evaluates this every tick on the seconds left (DurationTextBinding:SetTextColorCurve). Linear with a
  -- point every 0.05 s draws the breath; the 3.000 -> 3.001 pair is the step into gold (points match exactly at 3).
  local ok, c = pcall(C_CurveUtil.CreateColorCurve)
  if not ok or not c then return nil end
  if c.SetType and Enum.LuaCurveType then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
  for i = 0, 60 do
    local x = i * LOW / 60
    c:AddPoint(x, CreateColor(low[1], low[2], low[3], lowBreathes and breath(x) or 1))
  end
  c:AddPoint(LOW + 0.001, CreateColor(normal[1], normal[2], normal[3], 1))
  c:AddPoint(86400, CreateColor(normal[1], normal[2], normal[3], 1))
  return c
end

local function curveColor(c, x, fallbackNormal, fallbackLow, lowBreathes)
  -- test mode only (out of combat, plain numbers): read the same curve, or compute it if Evaluate is missing
  if c and c.Evaluate then
    local ok, col = pcall(c.Evaluate, c, x)
    if ok and col then return col:GetRGBA() end
  end
  if x <= LOW then return fallbackLow[1], fallbackLow[2], fallbackLow[3], lowBreathes and breath(x) or 1 end
  return fallbackNormal[1], fallbackNormal[2], fallbackNormal[3], 1
end

local function probe()
  -- number: whole seconds rounded up ("3" for 2.2 s), minutes past a minute ("2m")
  local ok = pcall(function()
    NUM_FMT = C_StringUtil.CreateNumericRuleFormatter()
    NUM_FMT:AddBreakpoint({ threshold = 0, step = 1, rounding = UP, format = '%d' })
  end)
  if ok then pcall(NUM_FMT.AddBreakpoint, NUM_FMT, { threshold = 60, format = '%dm', components = { { div = 60, step = 1, rounding = UP } } }) end
  local okN, n = pcall(function() return NUM_FMT:FormatNumber(2.2) end)
  if not (ok and okN and n == '3') then log('number formatter check: ' .. tostring(n)); if not (ok and okN) then NUM_FMT = nil end end

  -- ring: a formatter that always prints "O" (a rule with no format specifier is allowed: NumericRuleFormatter docs)
  local okR, r = pcall(function()
    RING_FMT = C_StringUtil.CreateNumericRuleFormatter()
    RING_FMT:AddBreakpoint({ threshold = 0, format = 'O' })
    return RING_FMT:FormatNumber(5)
  end)
  local pf = CreateFrame('Frame'); pf:Hide()          -- our own scratch frame: never add regions to Blizzard's
  local fs = pf:CreateFontString(nil, 'BACKGROUND')
  local okF, fontSet = pcall(fs.SetFont, fs, RING_FONT, 32, '')
  if not fontSet then   -- which part is refused: the file, or the empty flags?
    local _, a = pcall(fs.SetFont, fs, RING_FONT, 32); local _, b2 = pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, 32, '')
    local _, c = pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, 32)
    local _, d = pcall(fs.SetFont, fs, 'Interface\\AddOns\\Details\\fonts\\Expressway.TTF', 32); log('probe: another add-on font (Details Expressway) ' .. tostring(d))
    log(('probe: ring nil-flags %s, std empty-flags %s, std nil-flags %s'):format(tostring(a), tostring(b2), tostring(c)))
    if a then fontSet = true end
  end

  -- the binding Blizzard copies into each button: update every tick so the breath is smooth
  local okB = pcall(function() BINDING = C_DurationUtil.CreateDurationTextBinding(); BINDING:SetUpdateInterval(0) end)
  if not okB then BINDING = nil end

  GLYPH = okR and r == 'O' and okF and fontSet and true or false
  log(('probe: ring glyph %s (fmt %s, font %s), binding %s'):format(tostring(GLYPH), tostring(r), tostring(fontSet), tostring(okB)))

  -- A font file the client hasn't drawn yet can refuse the very first SetFont (seen in game: "font false"
  -- right after a reload). Try again a few times; icons are styled when first made, so the ring is used
  -- from the next new icon on.
  if okR and r == 'O' and not GLYPH then
    local tries = 0
    local function retry()
      tries = tries + 1
      local ok2, set2 = pcall(fs.SetFont, fs, RING_FONT, 32)
      if ok2 and set2 then
        GLYPH = true; numCurve = makeCurve(WHITE, WHITE, true)
        log(('probe: ring font loaded on retry %d'):format(tries))
      elseif tries < 6 then C_Timer.After(tries, retry)
      else log('probe: ring font still refused after 6 tries') end
    end
    if C_Timer and C_Timer.After then C_Timer.After(.5, retry) end
  end

  for _, sp in ipairs(SPELLS) do ringCurves[sp.key] = makeCurve(sp.color, GOLD, true) end
  mineRingCurve = makeCurve(DARK_BRASS, GOLD, true)
  -- glyph mode: the number stays white and breathes with the ring. Fallback: the number itself goes gold.
  numCurve = makeCurve(WHITE, GLYPH and WHITE or GOLD, true)
end

-- ---------- spell IDs for the per-spell groups ----------
local function spellIdByName(name)
  local ok, id = pcall(function()
    if C_Spell and C_Spell.GetSpellInfo then local i = C_Spell.GetSpellInfo(name); return i and i.spellID end
    return GetSpellInfo and select(7, GetSpellInfo(name))
  end)
  if ok and type(id) == 'number' then return id end
end

local function idSet(sp)
  local set = {}
  for _, id in ipairs(sp.ids) do set[id] = true end
  for id in pairs(db.learned[sp.key] or {}) do set[id] = true end
  for _, n in ipairs(sp.names) do local id = spellIdByName(n); if id then set[id] = true end end
  return set
end

-- which eye (ring key) a spell ID belongs to, for the tracking (Track/Forever.lua)
function ns.eyeKeyFor(id)
  if not db or type(id) ~= 'number' then return nil end
  for _, sp in ipairs(SPELLS) do if sp.key ~= 'channel' and sp.key ~= 'curse' and idSet(sp)[id] then return sp.key end end
end

local function filtersFor(key)
  if key == 'others' then return { isFromPlayerOrPlayerPet = true } end   -- other players and their pets, not NPCs
  if key == 'mine' then
    local ex = {}
    for _, sp in ipairs(SPELLS) do for id in pairs(idSet(sp)) do ex[id] = true end end
    return { excludeSpellIDs = ex }
  end
  for _, sp in ipairs(SPELLS) do if sp.key == key then return { includeSpellIDs = idSet(sp) } end end
end

-- ---------- button looks (all of it happens here: buttons are locked once initializeFrame returns) ----------
local function textOpts(formatter, curve)
  local o = {}
  if BINDING then o.binding = BINDING end
  if formatter then o.textFormatter = formatter end
  if curve then o.textColor = { curve = curve, property = REMAINING } end
  return o
end

local function styleCooldown(cd, swipe)
  cd:SetAllPoints(cd:GetParent())
  pcall(cd.SetSwipeTexture, cd, swipe, 1, 1, 1, 1)
  pcall(cd.SetSwipeColor, cd, 1, 1, 1, 1)
  pcall(cd.SetDrawSwipe, cd, true)
  pcall(cd.SetDrawEdge, cd, false)
  pcall(cd.SetDrawBling, cd, false)
  pcall(cd.SetReverse, cd, true)                 -- the swipe covers the spent part, so the ring drains
  pcall(cd.SetHideCountdownNumbers, cd, true)    -- our number comes from the duration text, not the cooldown
  pcall(cd.SetUseAuraDisplayTime, cd, true)      -- "stay in sync with aura timers"
end

local function roundIcon(b, size)
  local icon = b:CreateTexture(nil, 'ARTWORK', nil, 0)
  icon:SetSize(size * 0.756, size * 0.756); icon:SetPoint('CENTER', b, 'CENTER')
  icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)       -- trim the icon's own border; the mask makes it round
  local m = b:CreateMaskTexture()
  m:SetTexture(ART .. 'mask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE'); m:SetAllPoints(b)
  icon:AddMaskTexture(m)
  return icon
end

local function numberOn(cd, b, size)
  -- the number lives in a child of the cooldown, so it always draws above the dark swipe; it never moves
  local top = CreateFrame('Frame', nil, cd); top:SetAllPoints(b)
  local num = top:CreateFontString(nil, 'OVERLAY')
  num:SetFont(NUM_FONT, math.floor(size * 0.58 + 0.5), 'THICKOUTLINE')   -- sheet 39 A 'Bold': big outlined number
  num:SetPoint('CENTER', b, 'CENTER', 0, -size * 0.02)
  num:SetTextColor(1, 1, 1, 1); num:SetShadowColor(0, 0, 0, 1); num:SetShadowOffset(1, -1)
  return num
end

local function mainOwn(b)
  b:SetSize(S, S); pcall(b.EnableMouse, b, false)
  -- sheet 41 'Bold, richer' (2026-11-11): the icon stays clear (was .42); a dark spot behind the number keeps it readable
  local icon = roundIcon(b, S); icon:SetAlpha(.8)
  local spot = b:CreateTexture(nil, 'ARTWORK', nil, 1); spot:SetTexture(ART .. 'numspot'); spot:SetAllPoints(b)
  local bezel = b:CreateTexture(nil, 'ARTWORK', nil, 2); bezel:SetTexture(ART .. 'bezel'); bezel:SetAllPoints(b)
  local cd = CreateFrame('Cooldown', nil, b); styleCooldown(cd, ART .. 'swipe_inner')
  local num = numberOn(cd, b, S)
  b:SetIcon(icon)
  b:SetDurationCooldown(cd)
  b:SetDurationText(num, textOpts(NUM_FMT, numCurve))
end

local function mainOthers(b)
  b:SetSize(OS, OS); pcall(b.EnableMouse, b, false); b:SetAlpha(OTHERS_ALPHA)
  local icon = roundIcon(b, OS)
  local ring = b:CreateTexture(nil, 'ARTWORK', nil, 2); ring:SetTexture(ART .. 'ring_plain'); ring:SetAllPoints(b)
  ring:SetVertexColor(DARK_BRASS[1], DARK_BRASS[2], DARK_BRASS[3])
  local cd = CreateFrame('Cooldown', nil, b); styleCooldown(cd, ART .. 'swipe_inner')
  local num = numberOn(cd, b, OS)
  b:SetIcon(icon)
  b:SetDurationCooldown(cd)
  b:SetDurationText(num, textOpts(NUM_FMT, nil))   -- plain white: no colour change, no breath
end

-- sheet 27 (approved): on each tick the bar calls ns.ringsPulse(unit, spell name) and that DoT's ring on that
-- unit's nameplate breathes brighter for 400 ms, in the same instant as its piece in the bar
local pulseRings = setmetatable({}, { __mode = 'k' })     -- ring button -> spell key
local keyOfName = Spells.key
local framePair, attachAll, chanPair -- defined further down (forward-declared so earlier code sees them, not a nil global)
function ns.ringsPulse(unit, name)
  local key = keyOfName(name); if not key then return end
  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
  -- review #9: in Haunt and Target frame the ring you can see is the one on the target frame
  if unit == 'target' and db and (db.where == 'split' or db.where == 'frame') and framePair then plate = framePair.anchor end
  if not plate then return end
  for b, k in pairs(pulseRings) do
    if k == key and b:IsVisible() then
      local p = b; for _ = 1, 12 do p = p and p:GetParent(); if p == plate then break end end
      if p == plate and b.omPulse then b.omPulse:Stop(); b.omPulse:Play() end
    end
  end
end

local function ringOwn(color, curve, key)
  return function(b)
    b:SetSize(S, S); pcall(b.EnableMouse, b, false)
    local shadow = b:CreateTexture(nil, 'BACKGROUND', nil, -8); shadow:SetTexture(ART .. 'ring_shadow'); shadow:SetAllPoints(b)   -- sheet 41: sits in the world
    local back = b:CreateTexture(nil, 'BACKGROUND'); back:SetTexture(ART .. 'backing'); back:SetAllPoints(b)
    if GLYPH and curve then
      local fs = b:CreateFontString(nil, 'ARTWORK')
      fs:SetFont(RING_FONT, S, ''); fs:SetSize(S * 2, S * 2); fs:SetPoint('CENTER', b, 'CENTER')
      fs:SetJustifyH('CENTER'); fs:SetJustifyV('MIDDLE'); pcall(fs.SetWordWrap, fs, false)
      fs:SetTextColor(color[1], color[2], color[3], 1)
      b:SetDurationText(fs, textOpts(RING_FMT, curve))
    else
      local t = b:CreateTexture(nil, 'ARTWORK'); t:SetTexture(ART .. 'ring_bold'); t:SetAllPoints(b)   -- sheet 39 A: twice as thick
      t:SetVertexColor(color[1], color[2], color[3])
    end
    -- sheet 41: the ring lit like metal (cream on top, shade underneath, a warm sheen up-left), under the dark track
    local light = b:CreateTexture(nil, 'ARTWORK', nil, 3); light:SetTexture(ART .. 'ring_light'); light:SetAllPoints(b)
    local cd = CreateFrame('Cooldown', nil, b); styleCooldown(cd, ART .. 'swipe_track_bold')
    b:SetDurationCooldown(cd)
    if key then
      local glow = b:CreateTexture(nil, 'OVERLAY', nil, 7); glow:SetTexture(ART .. 'ring_bold'); glow:SetAllPoints(b)
      glow:SetVertexColor(color[1], color[2], color[3]); glow:SetBlendMode('ADD'); glow:SetAlpha(0)
      local g = glow:CreateAnimationGroup()
      local a1 = g:CreateAnimation('Alpha'); a1:SetFromAlpha(0); a1:SetToAlpha(.4); a1:SetDuration(.12); a1:SetOrder(1); a1:SetSmoothing('OUT')
      local a2 = g:CreateAnimation('Alpha'); a2:SetFromAlpha(.4); a2:SetToAlpha(0); a2:SetDuration(.45); a2:SetOrder(2); a2:SetSmoothing('IN')
      b.omPulse = g; pulseRings[b] = key
    end
  end
end

local function ringOthers(b)
  -- only the dark backing disc for other players' DoTs (their plain ring is drawn by the main button)
  b:SetSize(OS, OS); pcall(b.EnableMouse, b, false); b:SetAlpha(OTHERS_ALPHA)
  local back = b:CreateTexture(nil, 'BACKGROUND'); back:SetTexture(ART .. 'backing'); back:SetAllPoints(b)
end

-- group order is layout order: the four DoTs (fixed order, one group each so each can carry its own colour), your
-- other debuffs (neutral ring), then other players' DoTs to the right. Within a group: oldest first.
local GROUPS = {}
local function buildGroups()
  GROUPS = {}
  for _, sp in ipairs(SPELLS) do
    GROUPS[#GROUPS + 1] = { key = sp.key, filter = OWN, max = 2, main = mainOwn, ring = ringOwn(sp.color, ringCurves[sp.key], sp.key) }
  end
  GROUPS[#GROUPS + 1] = { key = 'mine', filter = OWN, max = 6, main = mainOwn, ring = ringOwn(DARK_BRASS, mineRingCurve) }
  GROUPS[#GROUPS + 1] = { key = 'others', filter = OTHERS, max = 3,   -- review #10: a pack's rings crowded the next plate
    main = mainOthers, ring = ringOthers, layout = { groupSpacing = OTHERS_GAP } }
end

-- ---------- the eyes: an invisible third container per plate (2026-11-11) ----------
-- Add-on code can't read enemy auras in combat, but Blizzard's container shows a button per aura it lets through.
-- One group per DoT (plus Improved Shadow Bolt's Shadow Vulnerability), buttons invisible and 1 px: whether a group's
-- button is shown says whether that debuff of yours is on the mob. The tracking uses it (Track/Forever.lua) to drop a
-- DoT that's gone (dispelled, eaten, mob reset) even while other hits look like its ticks. Always shown, so it keeps
-- reading when the visible rings are faded out. If the game hides this from us, ns.eyes answers nil and nothing changes.
local EYES = {
  { key = 'corruption' }, { key = 'agony' }, { key = 'immolate' }, { key = 'siphon' },
  { key = 'isb', names = { 'Shadow Vulnerability' }, ids = { 17794, 17797, 17798, 17799, 17800 } },
}
local function eyeIds(e)
  if not e.ids then for _, sp in ipairs(SPELLS) do if sp.key == e.key then return idSet(sp) end end end
  local set = {}; for _, id in ipairs(e.ids) do set[id] = true end
  for _, n in ipairs(e.names or {}) do local id = spellIdByName(n); if id then set[id] = true end end
  return set
end
local function setupEyes(c)
  pcall(c.SetEditModePreviewEnabled, c, false)
  for _, e in ipairs(EYES) do
    local key = e.key
    pcall(c.AddAuraGroup, c, key, OWN, {
      initializeFrame = function(b) b:SetSize(1, 1); b:SetAlpha(0); pcall(b.EnableMouse, b, false); b.omaEye = key end,
      candidateFilters = { includeSpellIDs = eyeIds(e) }, sortMethod = SORT, maxFrameCount = 1 })
  end
end

-- ---------- the pool: containers can't be created in combat, so we keep spares and fill up after each fight ----------
local holder                        -- parent of every spare row (made at start)
local pairsAll, free, active = {}, {}, {}

-- What the eyes see on a plate: { corruption = true/false, ... }, or nil when unknown (no eyes, or secret).
function ns.eyes(unit)
  local p = active[unit]
  if not p or not p.eyes then return nil end
  local seen = {}
  for _, e in ipairs(EYES) do seen[e.key] = false end
  local kids = { p.eyes:GetChildren() }
  for _, b in ipairs(kids) do
    if b.omaEye then
      local ok, shown = pcall(b.IsShown, b)
      if not ok or secret(shown) then return nil end
      if shown then seen[b.omaEye] = true end
    end
  end
  return seen
end
function ns.eyesUnits() local out = {}; for unit, p in pairs(active) do if p.eyes then out[#out + 1] = unit end end; return out end


local function setupContainer(c, kind, gap)   -- gap: space between rings (the target frame row only)
  pcall(c.SetEditModePreviewEnabled, c, false)    -- no fake auras on every plate when Edit Mode opens
  c:SetFlowLayoutAnchorPoint('BOTTOMLEFT')
  c:SetFlowLayoutGrowthDirection(1, 1)             -- AnchorUtil.FlowDirection.Right, .Up: left to right, then upward
  c:SetFlowLayoutMaximumLineSize(S * PER_ROW + 0.01)
  for _, g in ipairs(GROUPS) do
    if g.key ~= 'others' or othersOK then
      local ok, err = pcall(c.AddAuraGroup, c, g.key, g.filter, {
        initializeFrame = g[kind], candidateFilters = filtersFor(g.key), sortMethod = SORT,
        maxFrameCount = g.max, layout = g.layout or (gap and { groupSpacing = gap }) or nil })
      if not ok then
        log(kind .. ' group ' .. g.key .. ' failed: ' .. tostring(err))
        if g.key == 'others' then othersOK = false else error(err) end
      end
    end
  end
end

local function newPair(gap)
  if InCombatLockdown() or #pairsAll >= POOL_MAX then return nil end
  local ok, p = pcall(function()
    local anchor = CreateFrame('Frame', nil, holder); anchor:SetSize(1, 1); anchor:Hide()
    local ring = CreateFrame('AuraContainer', nil, anchor, 'CustomAuraContainerTemplate')
    setupContainer(ring, 'ring', gap)
    -- main is a CHILD of ring: that alone keeps every main button drawn above the ring's backing disc
    local main = CreateFrame('AuraContainer', nil, ring, 'CustomAuraContainerTemplate')
    setupContainer(main, 'main', gap)
    if not othersOK then pcall(ring.SetAuraGroupEnabled, ring, 'others', false)       -- keep both layouts identical
    elseif not db.others then pcall(ring.SetAuraGroupEnabled, ring, 'others', false); pcall(main.SetAuraGroupEnabled, main, 'others', false) end
    ring:SetPoint('BOTTOM', anchor, 'BOTTOM'); main:SetPoint('BOTTOM', anchor, 'BOTTOM')
    local eyes
    local okE = pcall(function()
      eyes = CreateFrame('AuraContainer', nil, holder, 'CustomAuraContainerTemplate'); eyes:SetSize(1, 1); eyes:SetAlpha(0)
      setupEyes(eyes)
    end)
    if not okE then eyes = nil; log('eyes container failed') end
    return { anchor = anchor, ring = ring, main = main, eyes = eyes }
  end)
  if not ok then log('new pair failed: ' .. tostring(p)); return nil end
  pairsAll[#pairsAll + 1] = p; free[#free + 1] = p
  return p
end

local filler                        -- made at start
local function wanted() local n = 0; for _ in pairs(active) do n = n + 1 end; return math.min(POOL_MAX, math.max(POOL_START, n + POOL_MIN_FREE)) end
local function fill()
  -- one pair per frame, out of combat, so login never hitches
  filler:SetScript('OnUpdate', function(self)
    if InCombatLockdown() or #pairsAll >= wanted() or not newPair() then self:SetScript('OnUpdate', nil) end
  end)
end

-- ---------- placing a row on a plate ----------
local function nameInsideBar()
  local style = tonumber(C_CVar.GetCVar('nameplateStyle') or '')
  local e = Enum.NamePlateStyle
  return e and style ~= nil and (style == e.Modern or style == e.Block) or false
end

local function place(anchor, plate)
  -- Like Blizzard's debuff row: bottom on the name's top (or the bar's top when the name sits inside the bar), plus
  -- nameplateDebuffPadding. Centred over the health bar, as the mockup draws it. We only anchor OUR frame to theirs.
  anchor:ClearAllPoints()
  local uf = plate.UnitFrame
  local bar = uf and uf.HealthBarsContainer
  local pad = tonumber(C_CVar.GetCVar('nameplateDebuffPadding') or '') or 0
  if bar then
    -- 2026-11-10: reading the name's top came back secret/empty in a real fight, so the row sat on the bar and covered
    -- the name (a screenshot). Blizzard anchors its debuff row TO the name frame, which needs no numbers: do the same.
    local above = bar
    if not nameInsideBar() and uf.name then above = uf.name end
    anchor:SetPoint('BOTTOM', above, 'TOP', 0, pad + GAP)
    anchor:SetPoint('LEFT', bar, 'LEFT'); anchor:SetPoint('RIGHT', bar, 'RIGHT')
    anchor:SetHeight(1)
  else
    anchor:SetPoint('BOTTOM', plate, 'CENTER', 0, S * 0.5)
  end
end

local function isEnemy(unit)
  local ok, can = pcall(UnitCanAttack, 'player', unit)
  if not ok or secret(can) then return false end
  return can == true
end

local function release(unit)
  local p = active[unit]; if not p then return end
  active[unit] = nil
  if ns.ringsUnfade then ns.ringsUnfade(p) end
  p.anchor:Hide(); p.anchor:ClearAllPoints(); p.anchor:SetParent(holder)
  if p.eyes then p.eyes:ClearAllPoints(); p.eyes:SetParent(holder) end
  free[#free + 1] = p
  if InCombatLockdown() and attachAll then C_Timer.After(0, function() attachAll() end) end   -- review #7: hand it to a plate that has no row
end

local look, visible                 -- settings helpers, defined below (attach needs them)
local function attach(unit)
  if not db or not db.enabled or active[unit] then return end
  if not unit or not unit:match('^nameplate%d+$') or not isEnemy(unit) then return end
  local plate = C_NamePlate.GetNamePlateForUnit(unit, false)
  if not plate then return end
  local p = table.remove(free) or newPair()
  if not p then log('no free container for ' .. unit .. (InCombatLockdown() and ' (in combat; filled after)' or '')); return end
  active[unit] = p
  p.anchor:SetParent(plate)
  p.anchor:SetFrameLevel(plate:GetFrameLevel() + 20)
  place(p.anchor, plate)
  p.ring:SetUnit(unit); p.main:SetUnit(unit)   -- while hidden: no event churn; Show re-reads every aura
  if p.eyes then p.eyes:SetParent(plate); p.eyes:SetPoint('CENTER', plate, 'CENTER'); p.eyes:SetUnit(unit); p.eyes:Show() end
  p.want = nil; p.anchor:SetAlpha(0); p.anchor:Hide(); look(p); p.want = false; p.curA = 0; visible()
end

-- ---------- settings: size, opacity, where, which ----------
-- framePair: the row above the target frame ('Where the rings show': frame / split), declared above
look = function(p)
  p.anchor:SetScale((db.size or 40) / 40 * (p.frameScale or 1)); if p.curA then p.anchor:SetAlpha(p.curA * (db.alpha or 100) / 100) end
end
-- which plate is your target: compare nameplate FRAMES, not units. Frames are never secret, so this keeps working in
-- combat, where Forever can hide unit comparisons (Haunt would otherwise show your target's rings in both places)
local function isTarget(u)
  local ok, tp = pcall(C_NamePlate.GetNamePlateForUnit, 'target', false)
  local ok2, up = pcall(C_NamePlate.GetNamePlateForUnit, u, false)
  if ok and ok2 and tp and up then return tp == up end
  local ok3, v = pcall(UnitIsUnit, u, 'target'); return ok3 and not secret(v) and v == true
end
-- sheet 38 'Fade' ("i want fade ... rich and smooth for both"): leave quick, arrive soft.
-- Leaving: lifts 6 px and fades out over 0.2 s (ease-in). Arriving: starts 0.06 s later, rises 8 px into place and
-- fades in over 0.25 s (ease-out). Driven per frame from GetTime, so it's the same at any frame rate.
local LEAVE, ARRIVE, ARRIVE_DELAY, LIFT, RISE = .2, .25, .06, 6, 8
local fading = {}
local fader                         -- made at start
local easeIn, easeOut = Anim.easeIn, Anim.easeOut
local function fadeStep(p, now)
  local a = now - p.fadeAt
  local base = (db and db.alpha or 100) / 100
  local alpha, dy, done
  if p.want then
    local k = math.max(0, math.min(1, (a - ARRIVE_DELAY) / ARRIVE)); local e = easeOut(k)
    alpha = p.fromA + (1 - p.fromA) * e; dy = -RISE * (1 - e); done = k >= 1
  else
    local k = math.max(0, math.min(1, a / LEAVE))
    alpha = p.fromA * (1 - easeIn(k)); dy = LIFT * easeOut(k); done = k >= 1
  end
  p.curA = alpha
  p.anchor:SetAlpha(alpha * base)
  local pt = p.pt or 'BOTTOM'; p.ring:ClearAllPoints(); p.ring:SetPoint(pt, p.anchor, pt, 0, dy)
  return done
end
local function fadeAll()
  local now, any = GetTime(), false
  for p in pairs(fading) do if fadeStep(p, now) then fading[p] = nil; if not p.want then p.anchor:Hide() end else any = true end end   -- review #8
  if not any then fader:Hide() end
end
local function setVis(p, show)
  show = show and true or false
  if p.want == show then return end
  if p.want == nil then   -- first time: start from where it should be, no motion
    p.want, p.curA = show, show and 1 or 0
    p.anchor:SetAlpha((show and 1 or 0) * (db and db.alpha or 100) / 100); p.anchor:SetShown(show); return
  end
  p.fromA = p.curA or (p.want and 1 or 0); p.want = show; p.fadeAt = GetTime()
  if show then p.anchor:Show() end
  fading[p] = true; fader:Show()
end
ns.ringsSetVis = setVis
function ns.ringsUnfade(p) fading[p] = nil; p.want = nil; p.curA = nil; local pt = p.pt or 'BOTTOM'; p.ring:ClearAllPoints(); p.ring:SetPoint(pt, p.anchor, pt) end

visible = function()
  if not db then return end
  local where, which = db.where or 'enemy', db.which or 'all'
  local fight = UnitAffectingCombat('player')
  for u, p in pairs(active) do
    local show = where ~= 'frame' and (which == 'all' or (which == 'target' and isTarget(u)) or (which == 'combat' and fight))
    if where == 'split' and isTarget(u) then show = false end   -- 'Target on its frame, others overhead'
    setVis(p, show)
  end
  if framePair then
    local show = (where == 'frame' or where == 'both' or where == 'split') and UnitExists('target') and isEnemy('target') and (which ~= 'combat' or fight)
    setVis(framePair, show)
  end
  if chanPair then
    local show = where == 'split' and UnitExists('target') and isEnemy('target') and (which ~= 'combat' or fight)
    if show and not ns.placeChanPair() then show = false end
    setVis(chanPair, show)
  end
end
ns.ringsVisible = visible
local function channelGroup(p, on)
  if not p or InCombatLockdown() then return end
  pcall(p.ring.SetAuraGroupEnabled, p.ring, 'channel', on); pcall(p.main.SetAuraGroupEnabled, p.main, 'channel', on)
end
local function makeFramePair()
  if framePair or InCombatLockdown() or not TargetFrame then return end
  local p = newPair(FRAME_SPACE); if not p then return end
  for i, q in ipairs(free) do if q == p then table.remove(free, i) break end end
  framePair = p
  p.anchor:SetParent(TargetFrame); p.anchor:SetFrameLevel(TargetFrame:GetFrameLevel() + 20)
  -- sheet 42 B ("B"): a row UNDER the bars, where WoW itself puts your debuffs on a target, 40 px
  -- (it was 72 px over the name box and looked like a hat). Hung on the mana bar's bottom left (the frame's lowest
  -- bar); the row's own bottom sits S + gap below it, in the row's own scaled units.
  local main = TargetFrame.TargetFrameContent and TargetFrame.TargetFrameContent.TargetFrameContentMain
  local low = main and (main.ManaBar or (main.HealthBarsContainer and main.HealthBarsContainer.HealthBar))
  p.anchor:ClearAllPoints(); p.anchor:SetSize(S * FRAME_ROW, 1)
  if low then p.anchor:SetPoint('BOTTOMLEFT', low, 'BOTTOMLEFT', FRAME_LEFT, -(S + FRAME_GAP))
  else p.anchor:SetPoint('BOTTOMLEFT', TargetFrame, 'TOPLEFT', 24, -14) end
  p.frameScale = FRAME_SCALE
  p.pt = 'BOTTOMLEFT'
  for _, c in ipairs({ p.ring, p.main }) do
    c:ClearAllPoints(); c:SetPoint('BOTTOMLEFT', p.anchor, 'BOTTOMLEFT'); pcall(c.SetFlowLayoutMaximumLineSize, c, (S + FRAME_SPACE) * FRAME_ROW + 0.01)
  end
  channelGroup(p, db.where ~= 'split')   -- in Haunt your channel stays over the mob (chanPair), not on the frame
  p.ring:SetUnit('target'); p.main:SetUnit('target')
  look(p); visible()
end

-- sheet 41 ("channels I'd also want to see above the enemy in Haunt mode"): in Haunt your target's rings sit
-- on its frame, which took your Drain Life off the mob too. chanPair is one more row, channel group only, unit
-- 'target', that rides your target's plate. Moving our own frames between plates is allowed in combat.
local function makeChanPair()
  if chanPair or InCombatLockdown() then return end
  local p = newPair(); if not p then return end
  for i, q in ipairs(free) do if q == p then table.remove(free, i) break end end
  chanPair = p
  for _, g in ipairs(GROUPS) do if g.key ~= 'channel' then pcall(p.ring.SetAuraGroupEnabled, p.ring, g.key, false); pcall(p.main.SetAuraGroupEnabled, p.main, g.key, false) end end
  if p.eyes then p.eyes:SetParent(holder); p.eyes:Hide() end
  p.ring:SetUnit('target'); p.main:SetUnit('target')
  look(p)
end
local function placeChanPair()
  if not chanPair then return false end
  local plate = UnitExists('target') and C_NamePlate.GetNamePlateForUnit('target', false)
  if not plate then return false end
  chanPair.anchor:SetParent(plate); chanPair.anchor:SetFrameLevel(plate:GetFrameLevel() + 20); place(chanPair.anchor, plate)
  return true
end
ns.makeChanPair, ns.placeChanPair = makeChanPair, placeChanPair

attachAll = function() for i = 1, 40 do local u = 'nameplate' .. i; if UnitExists(u) then attach(u) end end end
local function releaseAll() local us = {}; for u in pairs(active) do us[#us + 1] = u end; for _, u in ipairs(us) do release(u) end end

local filtersDirty = false
local function refreshFilters()
  if InCombatLockdown() then filtersDirty = true; return end
  filtersDirty = false
  for _, p in ipairs(pairsAll) do
    for _, c in ipairs({ p.ring, p.main }) do
      for _, g in ipairs(GROUPS) do
        if g.key ~= 'others' then pcall(c.SetAuraGroupCandidateFilters, c, g.key, filtersFor(g.key)) end
      end
    end
  end
end

local function setOthers(on)
  db.others = on
  for _, p in ipairs(pairsAll) do
    pcall(p.ring.SetAuraGroupEnabled, p.ring, 'others', on and othersOK)
    pcall(p.main.SetAuraGroupEnabled, p.main, 'others', on and othersOK)
  end
end

-- ---------- /omadoomed rings test: a fake row on your target, plain frames, out of combat only ----------
local test
local TEST_ROW = {
  { sp = 1, dur = 18, left = 11.4 }, { sp = 2, dur = 24, left = 19.2 },
  { sp = 3, dur = 15, left = 3, loop = true },          -- loops through its last 3 seconds
  { sp = 1, dur = 18, left = 7.5, other = true },
}
local function spellIcon(sp)
  local id = spellIdByName(sp.names[1]) or sp.ids[1]
  local ok, tex = pcall(function() return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id)) end)
  return ok and tex or 'Interface\\Icons\\INV_Misc_QuestionMark'
end

local function buildTestIcon(parent, item)
  local sp, size = SPELLS[item.sp], item.other and OS or S
  local f = CreateFrame('Frame', nil, parent); f:SetSize(size, size)
  local back = f:CreateTexture(nil, 'BACKGROUND'); back:SetTexture(ART .. 'backing'); back:SetAllPoints()
  local icon = roundIcon(f, size); icon:SetTexture(spellIcon(sp))
  if item.other then
    local ring = f:CreateTexture(nil, 'ARTWORK', nil, 2); ring:SetTexture(ART .. 'ring_plain'); ring:SetAllPoints()
    ring:SetVertexColor(DARK_BRASS[1], DARK_BRASS[2], DARK_BRASS[3]); f:SetAlpha(OTHERS_ALPHA)
  else
    local bezel = f:CreateTexture(nil, 'ARTWORK', nil, 2); bezel:SetTexture(ART .. 'bezel'); bezel:SetAllPoints()
  end
  local base = f:GetFrameLevel()
  local cdIn = CreateFrame('Cooldown', nil, f); styleCooldown(cdIn, ART .. 'swipe_inner'); cdIn:SetFrameLevel(base + 1)
  local t = { f = f, item = item, sp = sp, cds = { cdIn }, levels = { { cdIn, 1 } } }
  if not item.other then
    local rf = CreateFrame('Frame', nil, f); rf:SetAllPoints(); rf:SetFrameLevel(base + 2); t.levels[#t.levels + 1] = { rf, 2 }
    if GLYPH then
      local fs = rf:CreateFontString(nil, 'ARTWORK'); fs:SetFont(RING_FONT, size, ''); fs:SetSize(size * 2, size * 2)
      fs:SetPoint('CENTER', f, 'CENTER'); fs:SetJustifyH('CENTER'); fs:SetJustifyV('MIDDLE'); fs:SetText('O'); t.ringText = fs
    else
      local rt = rf:CreateTexture(nil, 'ARTWORK'); rt:SetTexture(ART .. 'ring'); rt:SetAllPoints(); rt:SetVertexColor(unpack(sp.color))
    end
    local cdTr = CreateFrame('Cooldown', nil, f); styleCooldown(cdTr, ART .. 'swipe_track'); cdTr:SetFrameLevel(base + 3)
    t.cds[2] = cdTr; t.levels[#t.levels + 1] = { cdTr, 3 }
  end
  local top = CreateFrame('Frame', nil, f); top:SetAllPoints(); top:SetFrameLevel(base + 5); t.levels[#t.levels + 1] = { top, 5 }
  local num = top:CreateFontString(nil, 'OVERLAY'); num:SetFont(NUM_FONT, math.floor(size * 0.4 + 0.5), 'THICKOUTLINE')
  num:SetPoint('CENTER', f, 'CENTER', 0, -size * 0.02); num:SetShadowColor(0, 0, 0, 1); num:SetShadowOffset(1, -1)
  t.num = num
  return t
end

local function testStart(item, now)
  item.t0 = now; item.from = item.loop and LOW or item.left
  for _, cd in ipairs(item.ui.cds) do cd:SetCooldown(now - (item.dur - item.from), item.dur) end
end

local function stopTest() if test then test:Hide(); test:SetScript('OnUpdate', nil); test.until_ = nil end end

local function startTest()
  if InCombatLockdown() then say('test works out of combat only.'); return end
  if not test then
    -- test = the anchor (placed like a real row), test.row = the icons, centred on it like a container
    test = CreateFrame('Frame', nil, UIParent); test:SetSize(1, 1)
    test.row = CreateFrame('Frame', nil, test); test.row:SetPoint('BOTTOM', test, 'BOTTOM')
    test.icons = {}
    local x = 0
    for k, item in ipairs(TEST_ROW) do
      item.ui = buildTestIcon(test.row, item); test.icons[k] = item
      -- like the containers: own icons touching, left to right; others 60% size to the right, bottom-aligned
      if item.other and not (TEST_ROW[k - 1] or {}).other then x = x + OTHERS_GAP end
      item.ui.f:SetPoint('BOTTOMLEFT', test.row, 'BOTTOMLEFT', x, 0); x = x + (item.other and OS or S)
    end
    test.row:SetSize(x, S)
  end
  local plate = C_NamePlate.GetNamePlateForUnit('target', false)
  test:SetParent(plate or UIParent); test:ClearAllPoints()
  if plate then
    place(test, plate)
  else
    test:SetSize(1, 1); test:SetPoint('CENTER', UIParent, 'CENTER', 0, 120)
    say('no target nameplate: showing the test row in the middle of the screen.')
  end
  local now = GetTime()
  for _, item in ipairs(test.icons) do testStart(item, now) end
  test.until_ = now + 60
  test:SetFrameLevel((plate and plate:GetFrameLevel() or 1) + 20)
  for _, item in ipairs(test.icons) do        -- plain frames out of combat: re-stack each icon's layers after the move
    local base = test:GetFrameLevel() + 2; item.ui.f:SetFrameLevel(base)
    for _, l in ipairs(item.ui.levels) do l[1]:SetFrameLevel(base + l[2]) end
  end
  test:Show()
  test:SetScript('OnUpdate', function()
    local t = GetTime()
    if t > test.until_ then stopTest(); return end
    for _, item in ipairs(test.icons) do
      local left = item.from - (t - item.t0)
      if left <= 0 then
        if item.loop then testStart(item, t); left = item.from else item.left = item.dur; testStart(item, t); left = item.from end
      end
      item.ui.num:SetText(math.ceil(left))
      if item.other then
        item.ui.num:SetTextColor(1, 1, 1, 1)
      else
        item.ui.num:SetTextColor(curveColor(numCurve, left, WHITE, GLYPH and WHITE or GOLD, true))
        if item.ui.ringText then item.ui.ringText:SetTextColor(curveColor(ringCurves[item.ui.sp.key], left, item.ui.sp.color, GOLD, true)) end
      end
    end
  end)
  say('test row on for 60 s: Corruption 11, Agony 19, Immolate looping its last 3 s, one other player\'s DoT.')
end

-- ---------- events (registered at a warlock's login only) ----------
local ev

local function learn(spellID)
  -- every cast of a DoT teaches us its exact ID on Forever; filters update after combat
  if spellID == nil or secret(spellID) then return end
  local ok, name = pcall(function() return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or (GetSpellInfo and GetSpellInfo(spellID)) end)
  if not ok or type(name) ~= 'string' then return end
  local sp = Spells.ofName(name); if not sp then return end
  db.learned[sp.key] = db.learned[sp.key] or {}
  local known = false
  for _, id in ipairs(sp.ids) do if id == spellID then known = true end end
  if not known and not db.learned[sp.key][spellID] then
    db.learned[sp.key][spellID] = true; log('learned ' .. name .. ' = ' .. spellID); refreshFilters()
  end
  Spells.addID(spellID, sp.key)
end

local onEvent
-- a warlock's login (Core.lua): settings live in OmaDoomedDB.rings (defaults from Settings.lua)
local function start()
  db = ns.db.rings
  BC = ns.blizzard
  if db.othersAlpha then OTHERS_ALPHA = db.othersAlpha / 100; if db.othersAlpha == 0 then db.others = false end end
  db.saved = db.saved or {}; db.learned = db.learned or {}
  if not (C_UnitAuras and C_NamePlate and C_CurveUtil and C_StringUtil) then say('this client is missing the aura container APIs; the OmaDoomed rings are off.'); db = nil; return end
  holder = CreateFrame('Frame', nil, UIParent); holder:Hide()
  filler = CreateFrame('Frame')
  fader = CreateFrame('Frame'); fader:SetScript('OnUpdate', fadeAll); fader:Hide()
  ev = CreateFrame('Frame')
  for _, e in ipairs({ 'NAME_PLATE_UNIT_ADDED', 'NAME_PLATE_UNIT_REMOVED', 'PLAYER_REGEN_ENABLED',
    'PLAYER_REGEN_DISABLED', 'PLAYER_TARGET_CHANGED', 'SPELLS_CHANGED' }) do pcall(ev.RegisterEvent, ev, e) end
  pcall(ev.RegisterUnitEvent, ev, 'UNIT_SPELLCAST_SUCCEEDED', 'player')
  ev:SetScript('OnEvent', function(...) local ok, err = pcall(onEvent, ...); if not ok then ns.error('rings event: ' .. tostring(err)) end end)
  ns.bus:On('TICK', ns.ringsPulse)
  ns.bus:On('SETTING', function(key, store) if store == 'rings' then ns.ringsApply(key) end end)
  probe(); buildGroups()
  if db.enabled then BC.blizzardRow(false) end
  fill(); attachAll()
  if db.where ~= 'enemy' then C_Timer.After(1, function() makeFramePair(); if db.where == 'split' then ns.makeChanPair() end; visible() end) end
  BC.squaresApply()
end
ns.starts[#ns.starts + 1] = start
onEvent = (function(_, e, a1, _, a3)
  if not db then return end
  if e == 'NAME_PLATE_UNIT_ADDED' then attach(a1)
  elseif e == 'NAME_PLATE_UNIT_REMOVED' then release(a1)
  elseif e == 'PLAYER_TARGET_CHANGED' then
    visible(); BC.squaresApply()
    -- 2026-11-12 ("in haunt mode switching between targets rapidly shows the wrong or missing dots under frame
    -- and over head"): framePair and chanPair follow the unit 'target', and a container re-reads its auras only when
    -- it is shown (Blizzard_AuraContainer OnShow). Going from one enemy straight to another keeps them shown, so they
    -- kept the last mob's rings. A hide + show on the container (our own frame, allowed in combat) makes it re-read.
    for _, p in ipairs({ framePair, chanPair }) do
      if p and p.ring then pcall(p.ring.Hide, p.ring); pcall(p.ring.Show, p.ring) end
    end
    -- the name can appear or move when the target changes; keep each row on top of its name
    for u, p in pairs(active) do local plate = C_NamePlate.GetNamePlateForUnit(u, false); if plate then place(p.anchor, plate) end end
  elseif e == 'PLAYER_REGEN_DISABLED' then stopTest(); visible()
  elseif e == 'PLAYER_REGEN_ENABLED' then
    if filtersDirty then refreshFilters() end
    fill(); attachAll()                                  -- plates that showed up in combat with no spare container
    if db.where ~= 'enemy' then makeFramePair() end
    if db.where == 'split' then ns.makeChanPair() end
    channelGroup(framePair, db.where ~= 'split')
    visible()
  elseif e == 'SPELLS_CHANGED' then if not InCombatLockdown() then refreshFilters() else filtersDirty = true end
  elseif e == 'UNIT_SPELLCAST_SUCCEEDED' then learn(a3)
  end
end)

function ns.ringsApply(key)
  if not db then return end
  if key == 'size' or key == 'alpha' then for _, p in ipairs(pairsAll) do look(p) end; visible()
  elseif key == 'othersAlpha' then
    OTHERS_ALPHA = (db.othersAlpha or 55) / 100
    setOthers((db.othersAlpha or 55) > 0)
    say("other players' rings: new strength shows after a /reload" .. ((db.othersAlpha or 55) == 0 and ' (hidden now)' or ''))
  elseif key == 'where' then
    if db.where ~= 'enemy' then makeFramePair() end
    if db.where == 'split' then ns.makeChanPair() end
    channelGroup(framePair, db.where ~= 'split')   -- out of combat only; otherwise after the fight (REGEN_ENABLED)
    visible()
  elseif key == 'which' then visible()
  elseif key == 'squares' then BC.squaresApply()
  end
end

-- ---------- /omadoomed rings ... ----------
function ns.ringsSlash(msg)
  if not db then return end
  local cmd, arg = (msg or ''):match('^(%S*)%s*(.-)$'); cmd = cmd:lower(); arg = arg:lower()
  if cmd == 'off' then
    db.enabled = false; releaseAll(); BC.blizzardRow(true); stopTest()
    say('off: Blizzard\'s debuff row is back' .. (BC.pending() and ' after this fight.' or '.'))
  elseif cmd == 'on' then
    db.enabled = true; BC.blizzardRow(false); fill(); attachAll()
    say('on' .. (BC.pending() and ' (Blizzard\'s row goes off after this fight).' or '.'))
  elseif cmd == 'test' then
    if test and test:IsShown() then stopTest(); say('test off.') else startTest() end
  elseif cmd == 'others' and (arg == 'on' or arg == 'off') then
    setOthers(arg == 'on'); say('other players\' DoTs ' .. ((db.others and othersOK) and 'on' or 'off') .. '.')
  else
    local n = 0; for _ in pairs(active) do n = n + 1 end
    say(('%s. Rows on %d plates, %d spare.'):format(db.enabled and 'On' or 'Off', n, #free))
    say('Last 3 s: ' .. (GLYPH and 'ring turns gold and breathes, number breathes.' or 'ring font unavailable, so the number turns gold and breathes.'))
    say('Other players\' DoTs: ' .. ((db.others and othersOK) and 'on' or (othersOK and 'off' or 'not allowed by the game')) .. '.')
    say('Blizzard\'s debuff row: ' .. BC.state() .. '.')
  end
end
