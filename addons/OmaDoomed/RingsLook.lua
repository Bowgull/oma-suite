-- The rings' look: the sizes, the colour curves, the load check, the aura groups and what each aura button is built
-- from. Rings.lua puts rows on plates, RingsFade.lua fades them. Rules this is built on: reports/Nameplate DoT rules.md
-- and research_notes/Nameplate DoT timers/.
--
-- The one hard rule on Forever: addon code may not read enemy auras in combat (every C_UnitAuras call errors). So we
-- never read them. Blizzard's own AuraContainer (CustomAuraContainerTemplate) reads them untainted and drives the
-- countdown, the swipes and the colour curves for us. Our code only builds the look, once, in initializeFrame (buttons
-- are locked once it returns), and moves containers between plates.
--
-- Each plate gets a PAIR of containers with identical groups, sizes and sort, so their buttons land on the same spots:
--   ring  (below): dark backing disc, the colour ring, and a cooldown swipe that covers the spent part of the ring.
--   main  (above, a child of ring): round icon, brass bezel, a 50% dark swipe on the icon, the countdown number.
-- Why two: a button has exactly one duration text binding (the only thing that changes colour by "seconds left").
-- The number needs one. The ring needs another, so it can turn gold and breathe in a DoT's last seconds. The ring is a
-- font glyph (art/OmashuRing.ttf, its "O" is our ring) so a text colour curve can recolour it.
-- If that font or its formatter fails the load check, the ring falls back to a plain tinted texture that never goes
-- gold, and the NUMBER goes gold instead (the ThreatPlates "Highlight Expiring" route, proven on Forever).
local ADDON, ns = ...
local R = {}
ns.rings = R
local ART = 'Interface\\AddOns\\OmaDoomed\\Art\\rings\\'
local RING_FONT = ART .. 'OmashuRing.ttf'
local NUM_FONT = STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'
R.ART = ART

-- Blizzard's own nameplate aura size, so nothing needs tuning: AURA_ITEM_HEIGHT 25 x Nameplate Size Huge (1.6) = 40
-- units, square, no gaps; Blizzard puts 6 per row and grows rows upward.
local S = 25 * 1.6
R.S = S
R.PER_ROW = 6
R.FRAME_ROW = 5                     -- target frame row (Haunt / Target frame): 5 rings fit under the bars, before the level badge
-- sheet 51 B (approved 2026-11-13, "B"): the target-frame row at 28 px with a smaller number, so the icon shows
-- round it and the numbers no longer run together. All in the row's own scaled units (x FRAME_SCALE = screen px).
R.FRAME_SCALE = 0.70                -- 28 px under the frame (was 0.56: 22 px)
R.FRAME_GAP = 5                     -- between the bars' bottom edge and the rings (~3.5 px, as before)
R.FRAME_SPACE = 5.7                 -- between rings in the row: 4 px (5 x 28 + 4 x 4 = 156 of the bar's 157)
R.FRAME_LEFT = 5.6                  -- the first ring's edge lines up with the frame's brass border (~4 px, as before)
R.FRAME_NUM_K = 0.46                -- the number's height as a share of the ring in this row (0.58 over the mobs)
local OS = S * 0.6                  -- other players' DoTs: 60% size
R.OS = OS
R.OTHERS_ALPHA = 0.55               -- and 55% alpha (settings 'Other players' DoTs' sets it when the rings load)
local OTHERS_GAP = S * 6 / 70       -- mockup: 6 units gap on a 70-unit cell
R.GAP = 4                           -- row bottom sits this far above the name (mockup: ~5 of 70)
local BREATH, LOW_ALPHA = 1.5, 0.3  -- a DoT's last seconds ('Ending soon'): gold, one breath every 1.5 s, down to 30%
-- How often Blizzard re-draws each countdown number and ring colour, in seconds (0 = every frame). The number changes
-- once a second; the breath is the only thing that needs speed. Set back to 0 if the breath looks stepped in game.
local TEXT_INTERVAL = 0.05
R.TEXT_INTERVAL = TEXT_INTERVAL

local GOLD = { 0xff / 255, 0xf0 / 255, 0xb0 / 255 }
local WHITE = { 1, 1, 1 }
local DARK_BRASS = { 0x8a / 255, 0x6a / 255, 0x2a / 255 }
R.GOLD, R.WHITE, R.DARK_BRASS = GOLD, WHITE, DARK_BRASS

-- The DoTs, curses and channels, one group each, in Spells.lua's order with its ring colours and IDs. Belt and
-- braces: at login we also add whatever ID the game returns for each name, and we learn the exact ID every time you
-- cast one (UNIT_SPELLCAST_SUCCEEDED, Rings.lua).
local Spells, Anim, Secret = ns.spells, ns.core.Anim, ns.core.Secret
local SPELLS = Spells.list
R.SPELLS = SPELLS

local OWN = 'HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY'        -- PLAYER = you, your pet or vehicle (AuraUtil.lua)
local OTHERS = 'HARMFUL|!PLAYER|INCLUDE_NAME_PLATE_ONLY'    -- "!" negates (AuraUtil.lua, forever branch)
local UP = (Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up) or 1
local REMAINING = (Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration) or 0

-- failures go to the error list (/omadoomed errors and bug reports); start-up probes are kept quiet
local function log(m) if ns.err and not m:find('^probe') and not m:find('^number formatter') then ns.err('rings: ' .. m) end end
R.log = log

-- ---------- what the load check decides (out of combat, before any container exists) ----------
R.GLYPH = false               -- true: the ring is the font glyph and goes gold + breathes
local NUM_FMT, RING_FMT, BINDING
local curves = {}             -- every colour curve made, with what it is made of (rebuilt in place on a setting change)
local numCurve, ringCurves, mineRingCurve = nil, {}, nil
R.othersOK = true             -- false if the game refused the "!PLAYER" group

-- 'Ending soon' (kill bar settings, shared): how many seconds, and whether the gold breathes
local function lowSecs() return (ns.db and ns.db.low) or 3 end
local function breathes() return not (ns.db and ns.db.lowlook == 'steady') end

-- Blizzard re-evaluates a curve on the seconds left (DurationTextBinding:SetTextColorCurve). Linear with a point
-- every 1/60 of the gold time draws the breath; the low -> low + 0.001 pair is the step into gold.
local function fillCurve(c, normal, low, lowBreathes)
  local LOW = lowSecs()
  local breathe = lowBreathes and breathes()
  for i = 0, 60 do
    local x = i * LOW / 60
    c:AddPoint(x, CreateColor(low[1], low[2], low[3], breathe and Anim.breath(x, LOW, BREATH, LOW_ALPHA) or 1))
  end
  c:AddPoint(LOW + 0.001, CreateColor(normal[1], normal[2], normal[3], 1))
  c:AddPoint(86400, CreateColor(normal[1], normal[2], normal[3], 1))
end
local function makeCurve(normal, low, lowBreathes)
  local ok, c = pcall(C_CurveUtil.CreateColorCurve)
  if not ok or not c then return nil end
  if c.SetType and Enum.LuaCurveType then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
  fillCurve(c, normal, low, lowBreathes)
  curves[#curves + 1] = { c = c, normal = normal, low = low, breathes = lowBreathes }
  return c
end

-- the 'Ending soon' settings changed: every curve again, in place (buttons keep the curve they were given).
-- Out of combat only. False when the client can't clear a curve: then the change shows after a /reload.
function R.rebuildCurves()
  for _, e in ipairs(curves) do
    if not e.c.ClearPoints then return false end
    local ok = pcall(e.c.ClearPoints, e.c)
    if not ok then return false end
    fillCurve(e.c, e.normal, e.low, e.breathes)
  end
  return true
end

function R.probe()
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
    log(('probe: ring nil-flags %s, std empty-flags %s, std nil-flags %s'):format(tostring(a), tostring(b2), tostring(c)))
    if a then fontSet = true end
  end

  -- the binding Blizzard copies into each button (TEXT_INTERVAL: how often the number and the breath are re-drawn)
  local okB = pcall(function() BINDING = C_DurationUtil.CreateDurationTextBinding(); BINDING:SetUpdateInterval(TEXT_INTERVAL) end)
  if not okB then BINDING = nil end

  R.GLYPH = okR and r == 'O' and okF and fontSet and true or false
  log(('probe: ring glyph %s (fmt %s, font %s), binding %s'):format(tostring(R.GLYPH), tostring(r), tostring(fontSet), tostring(okB)))

  -- A font file the client hasn't drawn yet can refuse the very first SetFont (seen in game: "font false"
  -- right after a reload). Try again a few times; icons are styled when first made, so the ring is used
  -- from the next new icon on.
  if okR and r == 'O' and not R.GLYPH then
    local tries = 0
    local function retry()
      tries = tries + 1
      local ok2, set2 = pcall(fs.SetFont, fs, RING_FONT, 32)
      if ok2 and set2 then
        R.GLYPH = true; numCurve = makeCurve(WHITE, WHITE, true)
        log(('probe: ring font loaded on retry %d'):format(tries))
      elseif tries < 6 then C_Timer.After(tries, retry)
      else log('probe: ring font still refused after 6 tries') end
    end
    if C_Timer and C_Timer.After then C_Timer.After(.5, retry) end
  end

  for _, sp in ipairs(SPELLS) do ringCurves[sp.key] = makeCurve(sp.color, GOLD, true) end
  mineRingCurve = makeCurve(DARK_BRASS, GOLD, true)
  -- glyph mode: the number stays white and breathes with the ring. Fallback: the number itself goes gold.
  numCurve = makeCurve(WHITE, R.GLYPH and WHITE or GOLD, true)
end

-- ---------- spell IDs for the per-spell groups ----------
local function spellIdByName(name)
  local ok, id = pcall(function()
    if C_Spell and C_Spell.GetSpellInfo then local i = C_Spell.GetSpellInfo(name); return i and i.spellID end
    return GetSpellInfo and select(7, GetSpellInfo(name))
  end)
  if ok and type(id) == 'number' then return id end
end

local function idSet(sp, into)
  local set = into or {}
  for _, id in ipairs(sp.ids) do set[id] = true end
  for id in pairs(R.db.learned[sp.key] or {}) do set[id] = true end
  for _, n in ipairs(sp.names) do local id = spellIdByName(n); if id then set[id] = true end end
  return set
end

function R.filtersFor(key)
  -- other players' (and their pets') warlock DoTs, not everyone's debuffs, and not NPCs'
  if key == 'others' then
    local inc = {}
    for _, sp in ipairs(SPELLS) do if sp.kind == 'dot' then idSet(sp, inc) end end
    return { isFromPlayerOrPlayerPet = true, includeSpellIDs = inc }
  end
  if key == 'mine' then
    local ex = {}
    for _, sp in ipairs(SPELLS) do idSet(sp, ex) end
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

-- the number's height as a share of the ring: sheet 39 A 'Bold'. Curses last minutes, so theirs reads "2m" (two
-- characters at that height overran the ring, Joshua 2026-11-13: "the curses text for the timer is too big")
-- Sheet 52 F (approved 2026-11-13, "F with white centred, apply to all rings"): every ring is flat: a hard black
-- disc, one band in the DoT's colour that drains, the icon. No shadow, gloss, bezel or dark spot; the number is white
-- with a thin outline at 46% of the ring, so the icon shows round it.
R.NUM_K, R.NUM_K_LONG = 0.46, 0.40
local function numberOn(cd, b, size, k)
  -- the number lives in a child of the cooldown, so it always draws above the dark swipe; it never moves
  local top = CreateFrame('Frame', nil, cd); top:SetAllPoints(b)
  local num = top:CreateFontString(nil, 'OVERLAY')
  num:SetFont(NUM_FONT, math.floor(size * (type(k) == 'number' and k or R.NUM_K) + 0.5), 'OUTLINE')
  num:SetPoint('CENTER', b, 'CENTER', 0, -size * 0.02)
  num:SetTextColor(1, 1, 1, 1); num:SetShadowColor(0, 0, 0, 0); num:SetShadowOffset(0, 0)
  return num
end

local function mainOwn(b, k)
  b:SetSize(S, S); pcall(b.EnableMouse, b, false)
  local icon = roundIcon(b, S)   -- sheet 52 F: the icon alone, full strength
  local cd = CreateFrame('Cooldown', nil, b); styleCooldown(cd, ART .. 'swipe_inner')
  local num = numberOn(cd, b, S, k)
  b:SetIcon(icon)
  b:SetDurationCooldown(cd)
  b:SetDurationText(num, textOpts(NUM_FMT, numCurve))
end
local function mainLong(b) mainOwn(b, R.NUM_K_LONG) end   -- curses: minutes-long, so a smaller number
-- the target-frame row's own numbers (sheet 51 B); a curse keeps its smaller share
local function mainFrame(b) mainOwn(b, R.FRAME_NUM_K) end
local function mainFrameLong(b) mainOwn(b, R.FRAME_NUM_K * R.NUM_K_LONG / R.NUM_K) end

local function mainOthers(b)
  b:SetSize(OS, OS); pcall(b.EnableMouse, b, false); b:SetAlpha(R.OTHERS_ALPHA)
  local icon = roundIcon(b, OS)
  local ring = b:CreateTexture(nil, 'ARTWORK', nil, 2); ring:SetTexture(ART .. 'ring_plain'); ring:SetAllPoints(b)
  ring:SetVertexColor(DARK_BRASS[1], DARK_BRASS[2], DARK_BRASS[3])
  local cd = CreateFrame('Cooldown', nil, b); styleCooldown(cd, ART .. 'swipe_inner')
  local num = numberOn(cd, b, OS)
  b:SetIcon(icon)
  b:SetDurationCooldown(cd)
  b:SetDurationText(num, textOpts(NUM_FMT, nil))   -- plain white: no colour change, no breath
end

-- sheet 27 (approved): on each tick (the model's TICK, unless the kill bar's tick light is Plain) that DoT's ring on
-- that unit's nameplate breathes brighter for 400 ms, in the same instant as its piece in the bar. Out of combat only:
-- in a fight Blizzard locks every aura button against add-on access while auras are hidden.
local pulseRings = setmetatable({}, { __mode = 'k' })     -- ring button -> spell key
function ns.ringsPulse(unit, name, key)
  if InCombatLockdown() then return end
  key = key or Spells.key(name); if not key then return end
  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
  -- in Haunt and Target frame the ring you can see is the one on the target frame
  local db = R.db
  if unit == 'target' and db and (db.where == 'split' or db.where == 'frame') and R.framePair then plate = R.framePair.anchor end
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
    local back = b:CreateTexture(nil, 'BACKGROUND'); back:SetTexture(ART .. 'backing_flat'); back:SetAllPoints(b)   -- sheet 52 F: a hard black disc
    if R.GLYPH and curve then
      local fs = b:CreateFontString(nil, 'ARTWORK')
      fs:SetFont(RING_FONT, S, ''); fs:SetSize(S * 2, S * 2); fs:SetPoint('CENTER', b, 'CENTER')
      fs:SetJustifyH('CENTER'); fs:SetJustifyV('MIDDLE'); pcall(fs.SetWordWrap, fs, false)
      fs:SetTextColor(color[1], color[2], color[3], 1)
      b:SetDurationText(fs, textOpts(RING_FMT, curve))
    else
      local t = b:CreateTexture(nil, 'ARTWORK'); t:SetTexture(ART .. 'ring_bold'); t:SetAllPoints(b)   -- sheet 39 A: twice as thick
      t:SetVertexColor(color[1], color[2], color[3])
    end
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
    -- crowd control: the plate's ring is the exact one; CrowdControl.lua learns from it when a hold ends early
    if key == 'cc' and ns.ccPlateHook then pcall(ns.ccPlateHook, b) end
  end
end

local function ringOthers(b)
  -- only the dark backing disc for other players' DoTs (their plain ring is drawn by the main button)
  b:SetSize(OS, OS); pcall(b.EnableMouse, b, false); b:SetAlpha(R.OTHERS_ALPHA)
  local back = b:CreateTexture(nil, 'BACKGROUND'); back:SetTexture(ART .. 'backing_flat'); back:SetAllPoints(b)
end

-- group order is layout order: crowd control first (sheet 48), the four DoTs (fixed order, one group each so each can carry its own colour), the
-- curses and the channels (each their own colour too, and Haunt keeps the channel and curse groups over the mob), your other
-- debuffs (neutral ring), then other players' DoTs to the right. Within a group: oldest first.
R.GROUPS = {}
function R.buildGroups()
  local G = {}
  for _, sp in ipairs(SPELLS) do
    G[#G + 1] = { key = sp.key, filter = OWN, max = 2, main = sp.kind == 'curse' and mainLong or mainOwn,
      mainFrame = sp.kind == 'curse' and mainFrameLong or mainFrame, ring = ringOwn(sp.color, ringCurves[sp.key], sp.key) }
  end
  G[#G + 1] = { key = 'mine', filter = OWN, max = 6, main = mainOwn, mainFrame = mainFrame, ring = ringOwn(DARK_BRASS, mineRingCurve) }
  G[#G + 1] = { key = 'others', filter = OTHERS, max = 3,   -- a pack's rings crowded the next plate
    main = mainOthers, ring = ringOthers, layout = { groupSpacing = OTHERS_GAP } }
  R.GROUPS = G
end
