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
R.FRAME_NUM_K = 0.44                -- the number's height as a share of the ring in this row (0.58 over the mobs)
local OS = S * 0.6                  -- other players' DoTs: 60% size
R.OS = OS
R.OTHERS_ALPHA = 0.55               -- and 55% alpha (settings 'Other players' DoTs' sets it when the rings load)
local OTHERS_GAP = S * 6 / 70       -- mockup: 6 units gap on a 70-unit cell
R.GAP = 6.5   -- sheet 55 (2026-11-13): 6 px of air above the name on his screen (was 4: 3 px, the row read as part of the name)
R.GAP_OLD = 4                           -- row bottom sits this far above the name (mockup: ~5 of 70)
-- Seats (sheets 69/70 A, 73, approved 2026-11-16 "build it"): over a mob each DoT has its own fixed spot, so where a
-- ring sits tells you which DoT it is, and a missing one leaves its spot blank (nothing drawn). Order as on the
-- sheets: Corruption, Agony, the curse, Immolate, then Siphon Life. Only the seats you know take a spot, so the row
-- stays centred over the bar (4 now, 5 once Siphon Life is learned). Rings sit 20% of a ring apart (sheet 73:
-- an ending ring's glow stays in its own gap). Each seat is one Blizzard aura slot (1 button, not 10).
R.SEATS = { 'corruption', 'agony', 'curse', 'immolate', 'siphon' }
R.SEAT_GAP = 0.2 * S
-- your other rings (crowd control, channel, your other debuffs, other players' DoTs) flow in a row above the seats
R.ABOVE_SEATS = S + R.SEAT_GAP
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
local numCurves, lightCurves, haloCurves = {}, {}, {}   -- per spell key ('mine' for your other debuffs): the number, the whole-band light
R.othersOK = true             -- false if the game refused the "!PLAYER" group

-- 'Ending soon' (kill bar settings, shared): how many seconds, and whether the gold breathes
local function lowSecs() return (ns.db and ns.db.low) or 3 end
local function breathes() return not (ns.db and ns.db.lowlook == 'steady') end

-- Blizzard re-evaluates a curve on the seconds left (DurationTextBinding:SetTextColorCurve). Linear with a point
-- every 1/60 of the gold time draws the breath; the low -> low + 0.001 pair is the step into gold.
-- light: the whole-band light (sheet 58 C): nothing until the last seconds, then it rises and falls with the breath
-- sheet 64 B (2026-11-15, "B: white-hot"): in a big pull the ending ring must be unmissable, so the whole band
-- flares most of the way to white in its own colour (was 0.45 strength, 22% lift)
local LIGHT_A = 0.85
local function fillCurve(c, normal, low, lowBreathes, light)
  local LOW = lowSecs()
  local breathe = lowBreathes and breathes()
  for i = 0, 60 do
    local x = i * LOW / 60
    local a = breathe and Anim.breath(x, LOW, BREATH, LOW_ALPHA) or 1
    if light then a = LIGHT_A * (a - LOW_ALPHA) / (1 - LOW_ALPHA) end
    c:AddPoint(x, CreateColor(low[1], low[2], low[3], a))
  end
  local na = light and 0 or 1
  c:AddPoint(LOW + 0.001, CreateColor(normal[1], normal[2], normal[3], na))
  c:AddPoint(86400, CreateColor(normal[1], normal[2], normal[3], na))
end
local function makeCurve(normal, low, lowBreathes, light)
  local ok, c = pcall(C_CurveUtil.CreateColorCurve)
  if not ok or not c then return nil end
  if c.SetType and Enum.LuaCurveType then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
  fillCurve(c, normal, low, lowBreathes, light)
  curves[#curves + 1] = { c = c, normal = normal, low = low, breathes = lowBreathes, light = light }
  return c
end
-- Sheet 58 C (approved 2026-11-13, "C, own colour"): a DoT that is ending flares in its OWN colour, lifted towards
-- white: the ring by 22%, the number by 45%. No gold on the rings any more (the kill bar keeps its gold).
local function lit(c, k) return { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k } end
R.lit, R.LIT_RING, R.LIT_NUM = lit, 0.6, 0.1   -- white-hot ring; the number turns its DoT's own full colour (70% white read as white)

-- the 'Ending soon' settings changed: every curve again, in place (buttons keep the curve they were given).
-- Out of combat only. False when the client can't clear a curve: then the change shows after a /reload.
function R.rebuildCurves()
  for _, e in ipairs(curves) do
    if not e.c.ClearPoints then return false end
    local ok = pcall(e.c.ClearPoints, e.c)
    if not ok then return false end
    fillCurve(e.c, e.normal, e.low, e.breathes, e.light)
  end
  return true
end

-- run f once the ring font has loaded (or given up): rows built before it would never get their ending effects
local glyphQueue = {}
function R.whenGlyph(f) if R.glyphWaiting then glyphQueue[#glyphQueue + 1] = f else f() end end
function R.glyphReady()
  R.glyphWaiting = false
  local q = glyphQueue; glyphQueue = {}
  for _, f in ipairs(q) do local ok, err = pcall(f); if not ok then log('after the ring font: ' .. tostring(err)) end end
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
  if not fontSet and _G.OmaDoomedRingFont then okF, fontSet = pcall(fs.SetFontObject, fs, _G.OmaDoomedRingFont); if okF then fontSet = true end end
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
    -- 2026-11-16 ("its misable"): rings built in this first moment had no ending effects at all (the band light and
    -- the outer glow both need the font), and the pool was built right away. Now the rows wait for this (R.whenGlyph).
    R.glyphWaiting = true
    local tries = 0
    local function retry()
      tries = tries + 1
      local ok2, set2 = pcall(fs.SetFont, fs, RING_FONT, 32)
      if ok2 and set2 then
        R.GLYPH = true
        log(('probe: ring font loaded on retry %d'):format(tries))
        R.glyphReady()
      elseif tries < 6 then C_Timer.After(tries, retry)
      else log('probe: ring font still refused after 6 tries'); R.glyphReady() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(.5, retry) else R.glyphWaiting = false end
  end

  for _, sp in ipairs(SPELLS) do
    ringCurves[sp.key] = makeCurve(sp.color, lit(sp.color, R.LIT_RING), true)
    numCurves[sp.key] = makeCurve(WHITE, lit(sp.color, R.LIT_NUM), true)
    lightCurves[sp.key] = makeCurve(sp.color, lit(sp.color, R.LIT_RING), true, true)
    haloCurves[sp.key] = makeCurve(sp.color, lit(sp.color, R.LIT_HALO), true, true)
  end
  mineRingCurve = makeCurve(DARK_BRASS, lit(DARK_BRASS, R.LIT_RING), true)
  numCurves.mine = makeCurve(WHITE, lit(DARK_BRASS, R.LIT_NUM), true)
  lightCurves.mine = makeCurve(DARK_BRASS, lit(DARK_BRASS, R.LIT_RING), true, true)
  R.numCurves, R.lightCurves = numCurves, lightCurves
  -- for '/omadoomed rings': what the ending effects stand on (2026-11-16: they never showed in game)
  R.diag = function()
    local n = 0; for _ in pairs(curves) do n = n + 1 end
    local okE, v = false, nil
    if numCurves.agony and numCurves.agony.Evaluate then okE, v = pcall(numCurves.agony.Evaluate, numCurves.agony, 1) end
    return ('ring font %s, number formatter %s, timer binding %s, colour curves %d (test %s), ending soon %ss'):format(
      tostring(R.GLYPH), tostring(NUM_FMT ~= nil), tostring(BINDING ~= nil), n,
      okE and type(v) == 'table' and ('ok %.2f/%.2f/%.2f'):format(v.r or 0, v.g or 0, v.b or 0) or 'FAILED', tostring(lowSecs()))
  end
  -- sheet 55 (2026-11-13): the number always turns gold and breathes in the last seconds. With 2 s left only a
  -- sliver of ring is left to turn gold, so the ring alone was easy to miss.
  numCurve = makeCurve(WHITE, GOLD, true)
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
  m:SetTexture(ART .. 'mask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE', 'TRILINEAR'); m:SetAllPoints(b)
  icon:AddMaskTexture(m)
  return icon
end

-- the number's height as a share of the ring: sheet 39 A 'Bold'. Curses last minutes, so theirs reads "2m" (two
-- characters at that height overran the ring, Joshua 2026-11-13: "the curses text for the timer is too big")
-- Two ring looks, the 'Ring look' setting (2026-11-13: "can we go back to the other rich rings ... maybe this can be
-- a setting?"). Rich (the default, sheets 39/41): shadow, backing, lit ring, bezel, a dark spot under a bold number.
-- Flat (sheet 52 F): a hard black disc, the draining colour band, the icon; a white number with a thin outline.
-- A ring's parts are fixed when it is built, so a change shows after a /reload.
function R.flat() local d = R.db or (ns.db and ns.db.rings); return d ~= nil and d.look == 'flat' end
-- Sheet 54 (approved 2026-11-13): the number must fit inside the icon area (at most ~80% of it) and stay readable.
-- Measured on Joshua's screen a ring is 47 px over a mob and 33 px under the frame: 58% filled 95% of the icon area.
-- DoT number: 46% over the mobs in both looks, 44% (Modern) / 46% (Classic) in the frame row. A minutes-long timer
-- ("2m", curses) is 36% everywhere: the old scaled-down share left it 7 px tall under the frame.
R.NUM_K_LONG = 0.36
function R.numK(frame) if R.flat() then return 0.46 end; return frame and R.FRAME_NUM_K or 0.46 end
R.NUM_K = 0.46
local function numberOn(cd, b, size, k)
  -- the number lives in a child of the cooldown, so it always draws above the dark swipe; it never moves
  local top = CreateFrame('Frame', nil, cd); top:SetAllPoints(b)
  local num = top:CreateFontString(nil, 'OVERLAY')
  local flat = R.flat()
  num:SetFont(NUM_FONT, math.floor(size * (type(k) == 'number' and k or R.numK()) + 0.5), flat and 'OUTLINE' or 'THICKOUTLINE')
  num:SetPoint('CENTER', b, 'CENTER', 0, -size * 0.02)
  num:SetTextColor(1, 1, 1, 1)
  if flat then num:SetShadowColor(0, 0, 0, 0); num:SetShadowOffset(0, 0) else num:SetShadowColor(0, 0, 0, 1); num:SetShadowOffset(1, -1) end
  return num
end

local function mainOwn(b, k, key)
  b:SetSize(S, S); pcall(b.EnableMouse, b, false)
  local icon = roundIcon(b, S)
  if not R.flat() then   -- Rich (sheet 41): a dark spot behind the number, the brass bezel
    icon:SetAlpha(.8)
    local spot = b:CreateTexture(nil, 'ARTWORK', nil, 1); spot:SetTexture(ART .. 'numspot', nil, nil, 'TRILINEAR'); spot:SetAllPoints(b)
    local bezel = b:CreateTexture(nil, 'ARTWORK', nil, 2); bezel:SetTexture(ART .. 'bezel', nil, nil, 'TRILINEAR'); bezel:SetAllPoints(b)
    -- sheet 55: the band's inside edge, over the bezel's outer rim
    local edge = b:CreateTexture(nil, 'ARTWORK', nil, 3); edge:SetTexture(ART .. (R.GLYPH and 'ring_edge_in_thin' or 'ring_edge_in'), nil, nil, 'TRILINEAR'); edge:SetAllPoints(b)
  end
  local cd = CreateFrame('Cooldown', nil, b); styleCooldown(cd, ART .. 'swipe_inner')
  -- Classic: the icon stays full strength all the way down; the ring alone drains (in game the 50% dark sweep over
  -- the icon made Classic duller than its sheet, Joshua 2026-11-13: "not as rich as youre showing it here")
  if R.flat() then pcall(cd.SetDrawSwipe, cd, false) end
  local num = numberOn(cd, b, S, k)
  b:SetIcon(icon)
  b:SetDurationCooldown(cd)
  b:SetDurationText(num, textOpts(NUM_FMT, (key and numCurves[key]) or numCurve))   -- ending: the number in its DoT's own colour, lit
end
-- one set of builders per group, so each number ends in its own DoT's colour. long: minutes-long timers (curses) get a
-- smaller number; frame: the target-frame row's own number size (sheet 51 B)
local function mainsFor(key, long)
  local function k(frame) return long and R.NUM_K_LONG or R.numK(frame) end
  return function(b) mainOwn(b, k(false), key) end, function(b) mainOwn(b, k(true), key) end
end

local function mainOthers(b)
  b:SetSize(OS, OS); pcall(b.EnableMouse, b, false); b:SetAlpha(R.OTHERS_ALPHA)
  local icon = roundIcon(b, OS)
  local ring = b:CreateTexture(nil, 'ARTWORK', nil, 2); ring:SetTexture(ART .. 'ring_plain', nil, nil, 'TRILINEAR'); ring:SetAllPoints(b)
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
    -- Forever can answer IsVisible with a hidden value (seen 2026-11-16: 'boolean test on a secret boolean'): skip those
    local okV, vis = pcall(b.IsVisible, b)
    if k == key and okV and not Secret.is(vis) and vis == true then
      local p = b; for _ = 1, 12 do p = p and p:GetParent(); if p == plate then break end end
      if p == plate and b.omPulse then b.omPulse:Stop(); b.omPulse:Play() end
    end
  end
end

-- The ending glow OUTSIDE the ring (sheets 64 B / 73, 2026-11-16 "its misable"): a button can drive only one timed
-- colour and the ring's is taken by its band light, so the glow is a third layer of its own, one aura slot per seat
-- (Rings.lua: the 'halo' container, under the rings). It's the ring glyph drawn half again as big, invisible with time
-- to spare, then breathing in the DoT's own colour lifted towards white for its last seconds.
R.LIT_HALO = 0.5
R.HALO_K = 1.5
function R.haloFor(key)
  local sp = Spells.byKey[key]
  local color, curve = sp and sp.color, haloCurves[key]
  return function(b)
    b:SetSize(S, S); pcall(b.EnableMouse, b, false)
    if not (R.GLYPH and curve and color) then return end
    local k = R.HALO_K
    local fs = b:CreateFontString(nil, 'ARTWORK')
    R.ringFont(fs, S * k); fs:SetSize(S * k * 2, S * k * 2); fs:SetPoint('CENTER', b, 'CENTER')
    fs:SetJustifyH('CENTER'); fs:SetJustifyV('MIDDLE'); pcall(fs.SetWordWrap, fs, false)
    fs:SetTextColor(color[1], color[2], color[3], 0)
    b:SetDurationText(fs, textOpts(RING_FMT, curve))
  end
end

function R.ringFont(fs, size)
  local ok, set = pcall(fs.SetFont, fs, RING_FONT, size, '')
  if ok and set then return true end
  local obj = size > S * 1.2 and _G.OmaDoomedRingFontBig or _G.OmaDoomedRingFont
  if obj then return (pcall(fs.SetFontObject, fs, obj)) end
  return false
end

local function ringOwn(color, curve, key, light)
  return function(b)
    b:SetSize(S, S); pcall(b.EnableMouse, b, false)
    local flat = R.flat()
    if not flat then local shadow = b:CreateTexture(nil, 'BACKGROUND', nil, -8); shadow:SetTexture(ART .. 'ring_shadow', nil, nil, 'TRILINEAR'); shadow:SetAllPoints(b) end   -- sheet 41: sits in the world
    local back = b:CreateTexture(nil, 'BACKGROUND'); back:SetTexture(ART .. (flat and 'backing_flat' or 'backing'), nil, nil, 'TRILINEAR'); back:SetAllPoints(b)
    -- The band is ALWAYS the art (2026-11-16: drawn with the ring font, the bands went blank in game once the font
    -- loaded). The font only adds the ending light above it (below), so a font problem can never blank a ring.
    do
      local t = b:CreateTexture(nil, 'ARTWORK'); t:SetTexture(ART .. (flat and 'ring_bold' or 'ring_bold_hard'), nil, nil, 'TRILINEAR'); t:SetAllPoints(b)
      t:SetVertexColor(color[1], color[2], color[3])
    end
    -- Rich (sheet 41): the ring lit like metal (cream on top, shade underneath, a warm sheen up-left), under the dark track
    if not flat then local light = b:CreateTexture(nil, 'ARTWORK', nil, 3); light:SetTexture(ART .. 'ring_light', nil, nil, 'TRILINEAR'); light:SetAllPoints(b) end
    local cd = CreateFrame('Cooldown', nil, b); styleCooldown(cd, ART .. 'swipe_track_bold')
    b:SetDurationCooldown(cd)
    -- sheet 55 / 53 B: Modern's band sits in a channel: a 1 px black line outside it, above the dark track so it
    -- runs the whole way round (the inside line is drawn over the bezel, in the main button)
    local top
    if not flat then
      top = CreateFrame('Frame', nil, cd); top:SetAllPoints(b)
      local edge = top:CreateTexture(nil, 'OVERLAY'); edge:SetTexture(ART .. 'ring_edge', nil, nil, 'TRILINEAR'); edge:SetAllPoints(b)
    end
    -- sheet 58 C: in the last seconds the WHOLE ring, drained part too, breathes in the DoT's own lit colour. Only a
    -- font string can follow the time left on a locked button, so this needs the ring font (R.GLYPH); it sits above
    -- the dark track.
    if R.GLYPH and light then
      top = top or CreateFrame('Frame', nil, cd); top:SetAllPoints(b)
      local fl = top:CreateFontString(nil, 'ARTWORK')
      R.ringFont(fl, S); fl:SetSize(S * 2, S * 2); fl:SetPoint('CENTER', b, 'CENTER')
      fl:SetJustifyH('CENTER'); fl:SetJustifyV('MIDDLE'); pcall(fl.SetWordWrap, fl, false)
      fl:SetTextColor(color[1], color[2], color[3], 0)
      b:SetDurationText(fl, textOpts(RING_FMT, light))
    end
    if key then
      local glow = b:CreateTexture(nil, 'OVERLAY', nil, 7); glow:SetTexture(ART .. 'ring_bold', nil, nil, 'TRILINEAR'); glow:SetAllPoints(b)
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
  local back = b:CreateTexture(nil, 'BACKGROUND'); back:SetTexture(ART .. (R.flat() and 'backing_flat' or 'backing'), nil, nil, 'TRILINEAR'); back:SetAllPoints(b)
end

-- ---------- everything else on a mob (sheet 78, approved 2026-11-16 "build the rest of sheet 78") ----------
-- Soft squares (Blizzard's square, corners 20% of the side, no frame), their colour a soft glow behind them that the
-- GAME tints by debuff type (AddDispelTypeTexture with a colour map: nothing hidden is ever read here).
R.SQ = 'softsq'
local DISPEL_RGB = { Magic = { .24, .61, 1 }, Curse = { .64, .21, .93 }, Disease = { .6, .4, 0 }, Poison = { .12, .75, .12 },
  Bleed = { .82, .1, .1 }, None = { .82, .1, .1 } }
local dispelMap
local function colorMap()
  if dispelMap or not CreateColor then return dispelMap end
  dispelMap = {}
  for k, c in pairs(DISPEL_RGB) do dispelMap[k] = CreateColor(c[1], c[2], c[3], 1) end
  return dispelMap
end
-- Blizzard's style that keeps our own glow art and only tints it ('PreserveAsset'); found by name, any enum spelling
local function preserveStyle()
  for _, t in pairs(Enum or {}) do if type(t) == 'table' and t.PreserveAsset ~= nil then return t.PreserveAsset end end
end
local function softIcon(b, size)
  local icon = b:CreateTexture(nil, 'ARTWORK', nil, 0)
  icon:SetSize(size, size); icon:SetPoint('CENTER', b, 'CENTER')
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local m = b:CreateMaskTexture(); m:SetTexture(ART .. 'softsq_mask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE', 'TRILINEAR'); m:SetAllPoints(icon)
  icon:AddMaskTexture(m)
  local edge = b:CreateTexture(nil, 'ARTWORK', nil, 2); edge:SetTexture(ART .. 'softsq_edge', nil, nil, 'TRILINEAR'); edge:SetAllPoints(icon)
  return icon
end
local function glowBehind(b, size, fixed)
  local g = b:CreateTexture(nil, 'BACKGROUND', nil, -6); g:SetTexture(ART .. 'softsq_glow', nil, nil, 'TRILINEAR'); g:SetSize(size * 1.5, size * 1.5)
  g:SetPoint('CENTER', b, 'CENTER'); g:SetBlendMode('ADD')
  if fixed then g:SetVertexColor(fixed[1], fixed[2], fixed[3], fixed[4] or 1); return g end
  -- the game colours it by the debuff's type; if this client refuses, a quiet red stays
  g:SetVertexColor(.82, .1, .1, .6)
  local style = preserveStyle()
  if b.AddDispelTypeTexture then
    pcall(b.AddDispelTypeTexture, b, g, { style = style, showWhenHarmful = true, showWithoutDispelType = true, customDispelColorMap = colorMap() })
  end
  return g
end
local function numberSmall(b, size)
  local top = CreateFrame('Frame', nil, b); top:SetAllPoints(b); top:SetFrameLevel(b:GetFrameLevel() + 3)
  local num = top:CreateFontString(nil, 'OVERLAY')
  num:SetFont(NUM_FONT, math.max(8, math.floor(size * .46 + .5)), 'OUTLINE'); num:SetPoint('CENTER', b, 'CENTER', 0, 0)
  num:SetTextColor(1, 1, 1, 1); num:SetShadowColor(0, 0, 0, 1); num:SetShadowOffset(1, -1)
  return num
end

-- Other players' debuffs (Sunder, poisons, slows, Faerie Fire...): half a ring, soft squares, right of the level box
R.ODEB = S * 0.5
R.LEVEL_BOX = 36                    -- past Blizzard's level box (28 px + its gaps), in the row's own units
local function odebButton(b)
  local s = R.ODEB
  b:SetSize(s, s); pcall(b.EnableMouse, b, false)
  local icon = softIcon(b, s)
  glowBehind(b, s)
  local cd = CreateFrame('Cooldown', nil, b); cd:SetAllPoints(b); pcall(cd.SetDrawSwipe, cd, false); pcall(cd.SetDrawEdge, cd, false)
  pcall(cd.SetHideCountdownNumbers, cd, true); pcall(cd.SetUseAuraDisplayTime, cd, true)
  b:SetIcon(icon); b:SetDurationCooldown(cd)
  b:SetDurationText(numberSmall(b, s), textOpts(NUM_FMT, nil))
  b:SetAlpha(.9)
end
R.odebButton = odebButton

-- Someone else's crowd control (sheet 78): the health bar BECOMES its timer. The button covers the bar with a dark
-- panel (no red behind), a teal bar the game drains as the CC runs out, the number riding its end, and the spell as
-- a soft square, one ring wide, left of the bar in Blizzard's white crowd-control glow. place(b, barFrame) puts it.
R.OCC_TEAL = { .18, .72, .65 }
local function occButton(b)
  pcall(b.EnableMouse, b, false)
  local back = b:CreateTexture(nil, 'BACKGROUND', nil, -7); back:SetAllPoints(b); back:SetColorTexture(.05, .04, .03, 1)
  local bar = CreateFrame('StatusBar', nil, b); bar:SetAllPoints(b)
  bar:SetStatusBarTexture('Interface\\TargetingFrame\\UI-StatusBar'); bar:SetStatusBarColor(R.OCC_TEAL[1], R.OCC_TEAL[2], R.OCC_TEAL[3])
  bar:SetMinMaxValues(0, 1); bar:SetValue(1)
  local sheen = bar:CreateTexture(nil, 'OVERLAY'); sheen:SetPoint('TOPLEFT', bar:GetStatusBarTexture(), 'TOPLEFT')
  sheen:SetPoint('BOTTOMRIGHT', bar:GetStatusBarTexture(), 'RIGHT'); sheen:SetColorTexture(1, 1, 1, .16)
  local top = CreateFrame('Frame', nil, bar); top:SetAllPoints(b); top:SetFrameLevel(bar:GetFrameLevel() + 2)
  local num = top:CreateFontString(nil, 'OVERLAY')
  num:SetFont(NUM_FONT, 13, 'OUTLINE'); num:SetTextColor(.87, .98, .96, 1)
  num:SetPoint('LEFT', bar:GetStatusBarTexture(), 'RIGHT', 3, 0)
  local holder = CreateFrame('Frame', nil, b); holder:SetSize(S, S); holder:SetPoint('RIGHT', b, 'LEFT', -6, 0)
  local icon = softIcon(holder, S * .82)
  glowBehind(holder, S * .82, { 1, 1, 1, .85 })
  b:SetIcon(icon)
  if b.SetDurationBar then pcall(b.SetDurationBar, b, bar) end
  b:SetDurationText(num, textOpts(NUM_FMT, nil))
end
R.occButton = occButton
R.OCC_FILTER = 'HARMFUL|!PLAYER|CROWD_CONTROL|INCLUDE_NAME_PLATE_ONLY'
R.ODEB_FILTER = 'HARMFUL|!PLAYER|!CROWD_CONTROL|INCLUDE_NAME_PLATE_ONLY'
-- other warlocks' DoTs keep their faint rings (the 'others' group): the squares leave them out
function R.odebFilters()
  local ex = {}
  for _, sp in ipairs(SPELLS) do idSet(sp, ex) end
  return { excludeSpellIDs = ex }
end

-- ---------- seats ----------
R.SEAT_OF = {}; for i, k in ipairs(R.SEATS) do R.SEAT_OF[k] = i end
-- do you know this spell (any rank)? Without the API (or before spells load) every seat counts.
local function knows(sp)
  if not (IsPlayerSpell or IsSpellKnown) then return true end
  for _, id in ipairs(sp.ids) do
    local ok, v = pcall(IsPlayerSpell or IsSpellKnown, id)
    if ok and v == true then return true end
  end
  return false
end
-- key -> its spot (1..n) among the seats you know, and n. A seat you don't know gets no spot (hidden).
function R.seatSpots()
  local spots, n = {}, 0
  for _, k in ipairs(R.SEATS) do
    local sp = Spells.byKey[k]
    if sp and knows(sp) then n = n + 1; spots[k] = n end
  end
  if n == 0 then for i, k in ipairs(R.SEATS) do spots[k] = i end; n = #R.SEATS end
  return spots, n
end
-- x of a spot's centre from the row's centre, in the row's own units
function R.seatX(i, n) return (i - (n + 1) / 2) * (S + R.SEAT_GAP) end
-- put every seat button of a row in its spot; out of combat only (Rings.lua calls it on build and SPELLS_CHANGED)
function R.placeSeats(btns, anchor)
  local spots, n = R.seatSpots()
  for b, key in pairs(btns) do
    b:ClearAllPoints()
    local i = spots[key]
    -- a seat you don't know never has an aura to show, so it just waits in the middle
    b:SetPoint('BOTTOM', anchor, 'BOTTOM', i and R.seatX(i, n) or 0, 0)
  end
end

-- group order is layout order: crowd control first (sheet 48), the four DoTs (fixed order, one group each so each can carry its own colour), the
-- curses and the channels (each their own colour too, and Haunt keeps the channel and curse groups over the mob), your other
-- debuffs (neutral ring), then other players' DoTs to the right. Within a group: oldest first.
R.GROUPS = {}
function R.buildGroups()
  local G = {}
  for _, sp in ipairs(SPELLS) do
    local main, mainFrame = mainsFor(sp.key, sp.kind == 'curse')
    G[#G + 1] = { key = sp.key, filter = OWN, max = 2, main = main, mainFrame = mainFrame, seat = R.SEAT_OF[sp.key],
      ring = ringOwn(sp.color, ringCurves[sp.key], sp.key, lightCurves[sp.key]) }
  end
  local mine, mineFrame = mainsFor('mine', false)
  G[#G + 1] = { key = 'mine', filter = OWN, max = 6, main = mine, mainFrame = mineFrame, ring = ringOwn(DARK_BRASS, mineRingCurve, nil, lightCurves.mine) }
  G[#G + 1] = { key = 'others', filter = OTHERS, max = 3,   -- a pack's rings crowded the next plate
    main = mainOthers, ring = ringOthers, layout = { groupSpacing = OTHERS_GAP } }
  R.GROUPS = G
end
