-- OmaDoomed, the rings: your DoTs above every enemy nameplate, in the Omashu skin (mockup 15, section C, style 3,
-- approved). This file puts rows on plates and on the target frame and keeps them there; the look is RingsLook.lua,
-- the fade RingsFade.lua, Blizzard's own settings BlizzardControls.lua.
--
-- A row is a pair of Blizzard AuraContainers (RingsLook.lua says why two). Containers can't be made in combat, so a
-- pool of spare pairs is kept: it starts small and grows out of combat, up to one pair for each of the 40 plates plus
-- the two rows that follow your target (Haunt, Target frame).
local ADDON, ns = ...
local R = ns.rings
local Spells, Secret = ns.spells, ns.core.Secret
local PM = ns.plates                -- PlateManager.lua: the live plates and which bar each one uses

local SORT = (AuraContainerSortMethod and AuraContainerSortMethod.AuraInstanceIDOnly) or 8   -- oldest first

-- 2026-11-16: seats made a plate's pair half the cost (90 aura buttons, was 180: each DoT is one slot, not a group
-- of 10), so 20 to start and 10 kept spare out of combat: big pulls ran out at 12/6 ("no free container for
-- nameplate3 (in combat)"). 42 = one pair for each of the 40 plates, plus the target frame and channel rows.
local POOL_START, POOL_MIN_FREE, POOL_MAX = 20, 10, 42
R.POOL_START, R.POOL_MIN_FREE, R.POOL_MAX = POOL_START, POOL_MIN_FREE, POOL_MAX

local db
local BC                            -- BlizzardControls.lua: Blizzard's nameplate debuffs and target-frame squares
local S, log = R.S, R.log
local function say(m) print('|cffb48cffOmaDoomed:|r ' .. m) end
local secret = Secret.is
local framePair, chanPair           -- the rows that follow your target: on its frame, and its channel and curses over the mob

-- ---------- the pool ----------
local holder                        -- parent of every spare row (made at start)
local pairsAll, free, active = {}, {}, {}
R.pairsAll, R.free, R.active = pairsAll, free, active

-- gap: space between rings (the target frame row only). seats: a plate row, whose DoTs each get a fixed seat (one
-- aura slot, placed on the row's anchor; RingsLook.lua R.placeSeats); seatBtns collects those buttons -> spell key.
local function setupContainer(c, kind, gap, seats, anchor)
  pcall(c.SetEditModePreviewEnabled, c, false)    -- no fake auras on every plate when Edit Mode opens
  c:SetFlowLayoutAnchorPoint('BOTTOMLEFT')
  c:SetFlowLayoutGrowthDirection(1, 1)             -- AnchorUtil.FlowDirection.Right, .Up: left to right, then upward
  c:SetFlowLayoutMaximumLineSize(S * R.PER_ROW + 0.01)
  for _, g in ipairs(R.GROUPS) do
    if seats and g.seat then
      -- the seats live in their own packed row (seatRow below)
    elseif g.key ~= 'others' or R.othersOK then
      local ok, err = pcall(c.AddAuraGroup, c, g.key, g.filter, {
        initializeFrame = (gap and kind == 'main' and g.mainFrame) or g[kind], candidateFilters = R.filtersFor(g.key), sortMethod = SORT,
        maxFrameCount = g.max, layout = g.layout or (gap and { groupSpacing = gap }) or nil })
      if not ok then
        log(kind .. ' group ' .. g.key .. ' failed: ' .. tostring(err))
        if g.key == 'others' then R.othersOK = false else error(err) end
      end
    end
  end
end

-- 2026-11-16 ("dots have their place but never an empty spot they organize themselves correctly to where they
-- belong"): the seat DoTs are one small group each, in seat order (Corruption, Agony, the curse, Immolate, Siphon
-- Life), in their own flowing row. Blizzard lays the row out, in combat too: a DoT that isn't up takes no space, so the
-- others close up in their order, and it slots back into its place when it lands. Three rows flow identically: the
-- ending glow (halo), the bands (ring) and the icons and numbers (main, a child of ring so it draws above).
local function groupByKey(key) for _, g in ipairs(R.GROUPS) do if g.key == key then return g end end end
local function seatRow(c, kind)
  pcall(c.SetEditModePreviewEnabled, c, false)
  c:SetFlowLayoutAnchorPoint('BOTTOMLEFT')
  c:SetFlowLayoutGrowthDirection(1, 1)
  c:SetFlowLayoutMaximumLineSize(S * 12)
  for _, key in ipairs(R.SEATS) do
    local g = groupByKey(key)
    if g then
      local init = kind == 'halo' and R.haloFor(key) or g[kind]
      local ok, err = pcall(c.AddAuraGroup, c, key, g.filter, { initializeFrame = init, candidateFilters = R.filtersFor(key),
        sortMethod = SORT, maxFrameCount = 1, layout = { groupSpacing = R.SEAT_GAP } })
      if not ok then log(kind .. ' seat ' .. key .. ' failed: ' .. tostring(err)); if kind ~= 'halo' then error(err) end end
    end
  end
end
-- the packed row starts at the row anchor's left edge (2026-11-16, "Yes, line them up"): over a mob that is the
-- health bar's left edge (the anchor spans the bar), in the mob list the start of the seat area
function R.placeSeatRow(p)
  if not (p and p.sring) then return end
  for _, c in ipairs({ p.halo, p.sring, p.smain }) do
    if c then c:ClearAllPoints(); c:SetPoint('BOTTOMLEFT', p.anchor, 'BOTTOMLEFT', 0, 0) end
  end
end

-- spare: a pool spare (on the free list). Otherwise the caller owns it at once (a plate, the target rows).
-- what building the ring pool costs on this machine (bug reports print it): pairs built, total and worst ms
local built = { n = 0, total = 0, worst = 0 }
R.built = built
-- flow: a row that follows your target (target frame, Haunt's channel row): no seats, every group in the flow
local listPairs = 0                 -- the mob list's rows (MobList.lua): outside the pool, never handed to a plate
local function newPair(gap, spare, flow, list)
  if InCombatLockdown() or R.glyphWaiting or (not list and #pairsAll - listPairs >= POOL_MAX) then return nil end
  local t0 = debugprofilestop and debugprofilestop()
  local ok, p = pcall(function()
    local anchor = CreateFrame('Frame', nil, holder); anchor:SetSize(1, 1); anchor:Hide()
    local seats = not flow and {} or nil
    -- the ending glow, under the rings: one slot per seat, placed with the seats (RingsLook.lua R.haloFor)
    local halo, sring, smain
    if seats then
      halo = CreateFrame('AuraContainer', nil, anchor, 'CustomAuraContainerTemplate'); seatRow(halo, 'halo')
      sring = CreateFrame('AuraContainer', nil, anchor, 'CustomAuraContainerTemplate'); seatRow(sring, 'ring')
      smain = CreateFrame('AuraContainer', nil, sring, 'CustomAuraContainerTemplate'); seatRow(smain, 'main')
    end
    local ring = CreateFrame('AuraContainer', nil, anchor, 'CustomAuraContainerTemplate')
    setupContainer(ring, 'ring', gap, seats, anchor)
    -- main is a CHILD of ring: that alone keeps every main button drawn above the ring's backing disc
    local main = CreateFrame('AuraContainer', nil, ring, 'CustomAuraContainerTemplate')
    setupContainer(main, 'main', gap, seats, anchor)
    if not R.othersOK then pcall(ring.SetAuraGroupEnabled, ring, 'others', false)       -- keep both layouts identical
    elseif not db.others then pcall(ring.SetAuraGroupEnabled, ring, 'others', false); pcall(main.SetAuraGroupEnabled, main, 'others', false) end
    -- on a plate the flowing rings (crowd control, channel, your other debuffs, others' DoTs) ride above the seats
    local up = seats and R.ABOVE_SEATS or 0
    ring:SetPoint('BOTTOM', anchor, 'BOTTOM', 0, up); main:SetPoint('BOTTOM', anchor, 'BOTTOM', 0, up)
    -- sheet 78: a frame that follows the health bar (placeBar), someone else's crowd control laid over it as the
    -- bar's own timer, and other players' debuffs as soft squares right of the level box (a small third container)
    local bar, side = CreateFrame('Frame', nil, anchor), nil
    bar:SetSize(1, 1)
    if seats and db.occ ~= false then
      local okC, errC = pcall(main.AddAuraSlot, main, 'occ', R.OCC_FILTER, { sortMethod = SORT,
        initializeFrame = function(b) R.occButton(b); b:ClearAllPoints(); b:SetAllPoints(bar) end })
      if not okC then log('crowd-control slot failed: ' .. tostring(errC)) end
    end
    if seats and not list and db.odeb ~= false then
      side = CreateFrame('AuraContainer', nil, anchor, 'CustomAuraContainerTemplate')
      pcall(side.SetEditModePreviewEnabled, side, false)
      side:SetFlowLayoutAnchorPoint('LEFT'); side:SetFlowLayoutGrowthDirection(1, 1)
      side:SetFlowLayoutMaximumLineSize(R.ODEB * 4.2)
      local okD, errD = pcall(side.AddAuraGroup, side, 'odeb', R.ODEB_FILTER, { initializeFrame = R.odebButton,
        candidateFilters = R.odebFilters(), sortMethod = SORT, maxFrameCount = 3, layout = { groupSpacing = R.ODEB * .3 } })
      if not okD then log("other players' debuffs failed: " .. tostring(errD)); side = nil
      else side:SetPoint('LEFT', bar, 'RIGHT', R.LEVEL_BOX, 0) end
    end
    if halo then halo:SetFrameLevel(math.max(0, ring:GetFrameLevel() - 1)) end
    local pp = { anchor = anchor, ring = ring, main = main, seats = seats, up = up, bar = bar, side = side, halo = halo, sring = sring, smain = smain }
    if sring then sring.omIsSeat, smain.omIsSeat = true, true; ring.omSeat, main.omSeat = sring, smain end   -- tests and diagnostics
    R.placeSeatRow(pp)
    if halo and sring then halo:SetFrameLevel(math.max(0, sring:GetFrameLevel() - 1)) end
    return pp
  end)
  if not ok then log('new pair failed: ' .. tostring(p)); return nil end
  if t0 then
    local ms = debugprofilestop() - t0
    built.n, built.total = built.n + 1, built.total + ms
    if ms > built.worst then built.worst = ms end
  end
  pairsAll[#pairsAll + 1] = p; if spare then free[#free + 1] = p end
  return p
end

-- a row of seats for the mob list (MobList.lua): your DoTs only, no flowing rings. parent: the list row. Out of
-- combat, at the list's start. Filter and seat updates reach it like any plate's row.
function R.newListPair(parent)
  local p = newPair(nil, false, false, true); if not p then return nil end
  listPairs = listPairs + 1
  for _, g in ipairs(R.GROUPS) do
    if not g.seat then pcall(p.ring.SetAuraGroupEnabled, p.ring, g.key, false); pcall(p.main.SetAuraGroupEnabled, p.main, g.key, false) end
  end
  p.anchor:SetParent(parent); p.anchor:SetFrameLevel(parent:GetFrameLevel() + 5)
  p.list = true   -- its size is the list's own (look leaves it at 1)
  p.anchor:Show(); p.want = true
  return p
end

local filler                        -- made at start
-- pairs wanted: every plate's row, the target rows and the spares
local function wanted()
  local n = (framePair and 1 or 0) + (chanPair and 1 or 0)
  for _ in pairs(active) do n = n + 1 end
  return math.min(POOL_MAX, math.max(POOL_START, n + POOL_MIN_FREE))
end
local function fill()
  -- one pair per frame, out of combat, so nothing hitches
  filler:SetScript('OnUpdate', function(self)
    if InCombatLockdown() or #pairsAll - listPairs >= wanted() or not newPair(nil, true) then self:SetScript('OnUpdate', nil) end
  end)
end
R.fill = fill

-- ---------- placing a row on a plate ----------
local function nameInsideBar()
  local style = tonumber(C_CVar.GetCVar('nameplateStyle') or '')
  local e = Enum.NamePlateStyle
  return e and style ~= nil and (style == e.Modern or style == e.Block) or false
end

-- the bar PlateManager found for this plate, when it is another add-on's (Plater, Threat Plates...)
local function addonBar(plate, unit)
  unit = unit or PM.unitOf[plate]
  local found = unit and PM.barOf(unit)
  if found and found.addon and found.bar then return found end
end
-- our row's parent and layer: Blizzard's plate as always; on another add-on's bar, its host frame and its layer
local function hostOn(anchor, plate, unit)
  local found = addonBar(plate, unit)
  if found then
    anchor:SetParent(found.host or plate)
    local strata, level = PM.layerOf(found.bar)
    if strata then anchor:SetFrameStrata(strata); anchor.strataSet = true end
    anchor:SetFrameLevel((level or 200) + 20)
  else
    anchor:SetParent(plate)
    if anchor.strataSet then local st = PM.layerOf(plate); if st then anchor:SetFrameStrata(st) end; anchor.strataSet = nil end
    anchor:SetFrameLevel(plate:GetFrameLevel() + 20)
  end
end

local function place(anchor, plate, unit)
  -- Like Blizzard's debuff row: bottom on the name's top (or the bar's top when the name sits inside the bar), plus
  -- nameplateDebuffPadding. Centred over the health bar, as the mockup draws it. We only anchor OUR frame to theirs.
  anchor:ClearAllPoints()
  local uf = plate.UnitFrame
  local bar = uf and uf.HealthBarsContainer
  local pad = tonumber(C_CVar.GetCVar('nameplateDebuffPadding') or '') or 0
  local other = addonBar(plate, unit)
  if other then   -- another add-on's bar: just above it (its name's place is its own; checked in game)
    anchor:SetPoint('BOTTOM', other.bar, 'TOP', 0, pad + R.GAP)
    anchor:SetPoint('LEFT', other.bar, 'LEFT'); anchor:SetPoint('RIGHT', other.bar, 'RIGHT')
    anchor:SetHeight(1)
  elseif bar then
    -- reading the name's top came back secret/empty in a real fight, so the row sat on the bar and covered the name.
    -- Blizzard anchors its debuff row TO the name frame, which needs no numbers: do the same.
    local above = bar
    if not nameInsideBar() and uf.name then above = uf.name end
    anchor:SetPoint('BOTTOM', above, 'TOP', 0, pad + R.GAP)
    anchor:SetPoint('LEFT', bar, 'LEFT'); anchor:SetPoint('RIGHT', bar, 'RIGHT')
    anchor:SetHeight(1)
  else
    anchor:SetPoint('BOTTOM', plate, 'CENTER', 0, S * 0.5)
  end
end

-- the pair's bar frame on the plate's health bar (Blizzard's, or another add-on's); the CC timer lies over it
local function placeBar(p, plate, unit)
  if not (p and p.bar) then return end
  p.bar:ClearAllPoints()
  local other = addonBar(plate, unit)
  local uf = plate and plate.UnitFrame
  local hb = (other and other.bar) or (uf and uf.HealthBarsContainer)
  if hb then p.bar:SetAllPoints(hb) else p.bar:SetSize(1, 1); p.bar:SetPoint('CENTER', p.anchor, 'BOTTOM') end
  if p.side then pcall(p.side.SetUnit, p.side, unit) end
end
R.placeBar = placeBar

local function isEnemy(unit)
  local ok, can = pcall(UnitCanAttack, 'player', unit)
  if not ok or secret(can) then return false end
  return can == true
end

local attachAll, visible
local function release(unit)
  local p = active[unit]; if not p then return end
  active[unit] = nil
  R.unfade(p)
  p.anchor:Hide(); p.anchor:ClearAllPoints(); p.anchor:SetParent(holder)
  free[#free + 1] = p
  if InCombatLockdown() and attachAll then C_Timer.After(0, function() attachAll() end) end   -- hand it to a plate that has no row
end

local look                          -- settings helper, defined below (attach needs it)
local function attach(unit)
  if not db or not db.enabled or active[unit] then return end
  if not unit or not PM.enemy[unit] then return end   -- PlateManager keeps the live plates and who is an enemy
  local plate = PM.live[unit]
  if not plate then return end
  local p = table.remove(free) or newPair()
  if not p then log('no free container for ' .. unit .. (InCombatLockdown() and ' (in combat; filled after)' or '')); return end
  active[unit] = p
  hostOn(p.anchor, plate, unit)
  place(p.anchor, plate, unit); placeBar(p, plate, unit)
  p.ring:SetUnit(unit); p.main:SetUnit(unit); if p.halo then p.halo:SetUnit(unit) end   -- while hidden: no event churn; Show re-reads every aura
  if p.sring then p.sring:SetUnit(unit); p.smain:SetUnit(unit) end
  p.want = nil; p.anchor:SetAlpha(0); p.anchor:Hide(); look(p); p.want = false; p.curA = 0; visible()
  if #free < POOL_MIN_FREE and not InCombatLockdown() then fill() end   -- keep spares for the next pull
end

-- ---------- settings: size, opacity, where, which ----------
look = function(p)
  p.anchor:SetScale(p.list and 1 or (db.size or 40) / 40 * (p.frameScale or 1)); if p.list then return end; if p.curA then p.anchor:SetAlpha(p.curA * (db.alpha or 100) / 100) end
end
-- which plate is your target: compare nameplate FRAMES, not units. Frames are never secret, so this keeps working in
-- combat, where Forever can hide unit comparisons (Haunt would otherwise show your target's rings in both places)
local function isTarget(u)
  local ok, tp = pcall(C_NamePlate.GetNamePlateForUnit, 'target', false)
  local ok2, up = pcall(C_NamePlate.GetNamePlateForUnit, u, false)
  if ok and ok2 and tp and up then return tp == up end
  local ok3, v = pcall(UnitIsUnit, u, 'target'); return ok3 and not secret(v) and v == true
end

local placeChanPair
visible = function()
  if not db then return end
  local where, which = db.where or 'enemy', db.which or 'all'
  local fight = UnitAffectingCombat('player')
  for u, p in pairs(active) do
    local show = where ~= 'frame' and (which == 'all' or (which == 'target' and isTarget(u)) or (which == 'combat' and fight))
    if where == 'split' and isTarget(u) then show = false end   -- 'Target on its frame, others overhead'
    R.setVis(p, show)
  end
  if framePair then
    local show = db.enabled ~= false and (where == 'frame' or where == 'both' or where == 'split') and UnitExists('target') and isEnemy('target') and (which ~= 'combat' or fight)
    R.setVis(framePair, show)
  end
  if chanPair then
    local show = db.enabled ~= false and where == 'split' and UnitExists('target') and isEnemy('target') and (which ~= 'combat' or fight)
    if show and not placeChanPair() then show = false end
    R.setVis(chanPair, show)
  end
end
ns.ringsVisible = visible
-- in Haunt these groups stay over your target's nameplate (chanPair), off its frame row: your channel (sheet 41),
-- your curses (2026-11-13, Joshua: "in haunt mode this is always on") and your crowd control (2026-11-13: "yes keep
-- it over the mob in haunt")
local OVERHEAD = { channel = true, curse = true, cc = true }
R.OVERHEAD = OVERHEAD
local function channelGroup(p, on)
  if not p or InCombatLockdown() then return end
  for key in pairs(OVERHEAD) do
    local k = on and not (key == 'cc' and db.cc == false)   -- the crowd-control switch still wins
    pcall(p.ring.SetAuraGroupEnabled, p.ring, key, k); pcall(p.main.SetAuraGroupEnabled, p.main, key, k)
  end
end
local function makeFramePair()
  if framePair or InCombatLockdown() or not TargetFrame then return end
  local p = newPair(R.FRAME_SPACE, nil, true); if not p then return end
  framePair = p; R.framePair = p
  p.anchor:SetParent(TargetFrame); p.anchor:SetFrameLevel(TargetFrame:GetFrameLevel() + 20)
  -- sheet 42 B: a row UNDER the bars, where WoW itself puts your debuffs on a target, 40 px. Hung on the mana bar's
  -- bottom left (the frame's lowest bar); the row's own bottom sits S + gap below it, in the row's own scaled units.
  local main = TargetFrame.TargetFrameContent and TargetFrame.TargetFrameContent.TargetFrameContentMain
  local low = main and (main.ManaBar or (main.HealthBarsContainer and main.HealthBarsContainer.HealthBar))
  p.anchor:ClearAllPoints(); p.anchor:SetSize(S * R.FRAME_ROW, 1)
  if low then p.anchor:SetPoint('BOTTOMLEFT', low, 'BOTTOMLEFT', R.FRAME_LEFT, -(S + R.FRAME_GAP))
  else p.anchor:SetPoint('BOTTOMLEFT', TargetFrame, 'TOPLEFT', 24, -14) end
  p.frameScale = R.FRAME_SCALE
  p.pt = 'BOTTOMLEFT'
  for _, c in ipairs({ p.ring, p.main }) do
    c:ClearAllPoints(); c:SetPoint('BOTTOMLEFT', p.anchor, 'BOTTOMLEFT'); pcall(c.SetFlowLayoutMaximumLineSize, c, (S + R.FRAME_SPACE) * R.FRAME_ROW + 0.01)
  end
  channelGroup(p, db.where ~= 'split')   -- in Haunt your channel and curses stay over the mob (chanPair), not on the frame
  p.ring:SetUnit('target'); p.main:SetUnit('target')
  look(p); visible()
end

-- sheet 41 ("channels I'd also want to see above the enemy in Haunt mode"): in Haunt your target's rings sit on its
-- frame, which took your Drain Life off the mob too. chanPair is one more row, the channel and curse groups only
-- (OVERHEAD), unit 'target', that rides your target's plate. Moving our own frames between plates is allowed in combat.
local function makeChanPair()
  if chanPair or InCombatLockdown() then return end
  local p = newPair(nil, nil, true); if not p then return end
  chanPair = p; R.chanPair = p
  for _, g in ipairs(R.GROUPS) do if not OVERHEAD[g.key] then pcall(p.ring.SetAuraGroupEnabled, p.ring, g.key, false); pcall(p.main.SetAuraGroupEnabled, p.main, g.key, false) end end
  p.ring:SetUnit('target'); p.main:SetUnit('target')
  look(p)
end
placeChanPair = function()
  if not chanPair then return false end
  local plate = UnitExists('target') and C_NamePlate.GetNamePlateForUnit('target', false)
  if not plate then return false end
  local unit = PM.unitOf[plate]
  hostOn(chanPair.anchor, plate, unit); place(chanPair.anchor, plate, unit)
  return true
end
ns.makeChanPair, ns.placeChanPair = makeChanPair, placeChanPair

-- A row following 'target' keeps its unit token when the target changes, and a container re-reads on a new token,
-- a group change or a show, never on its own here. Blizzard's own call for "the unit behind the token changed"
-- (Blizzard_AuraContainer.lua: UpdateAllAuras, what its target frame does on a new target), on both containers:
-- unlike a hide and show it doesn't cascade from ring to main.
local function reread(p)
  if not p then return end
  pcall(p.ring.UpdateAllAuras, p.ring); pcall(p.main.UpdateAllAuras, p.main)
end

attachAll = function() for u in pairs(PM.live) do attach(u) end end
local function releaseAll() local us = {}; for u in pairs(active) do us[#us + 1] = u end; for _, u in ipairs(us) do release(u) end end

-- a seat learned or lost (Siphon Life at 30): every row's seats move so the row stays centred. Out of combat only.
local function placeAllSeats()
  for _, p in ipairs(pairsAll) do if p.sring then R.placeSeatRow(p) end end
end
R.placeAllSeats = placeAllSeats

local filtersDirty = false
local function refreshFilters()
  if InCombatLockdown() then filtersDirty = true; return end
  filtersDirty = false
  for _, p in ipairs(pairsAll) do
    for _, c in ipairs({ p.ring, p.main }) do
      for _, g in ipairs(R.GROUPS) do
        if p.seats and g.seat then
          if c == p.ring then
            for _, sc in ipairs({ p.sring, p.smain, p.halo }) do if sc then pcall(sc.SetAuraGroupCandidateFilters, sc, g.key, R.filtersFor(g.key)) end end
          end
        elseif g.key ~= 'others' or R.othersOK then pcall(c.SetAuraGroupCandidateFilters, c, g.key, R.filtersFor(g.key)) end
      end
    end
  end
end

local function setOthers(on)
  db.others = on
  for _, p in ipairs(pairsAll) do
    if not p.list then   -- the mob list's rows show your DoTs only
      pcall(p.ring.SetAuraGroupEnabled, p.ring, 'others', on and R.othersOK)
      pcall(p.main.SetAuraGroupEnabled, p.main, 'others', on and R.othersOK)
    end
  end
end

-- 'Ending soon' changed: the rings' gold follows (curves are rebuilt out of combat)
local curvesDirty = false
local toldCurves = false
local function applyCurves()
  if InCombatLockdown() then curvesDirty = true; return end
  curvesDirty = false
  if not R.rebuildCurves() and not toldCurves then
    toldCurves = true; say('the rings show the new ending-soon setting after a /reload.')
  end
end
R.applyCurves = applyCurves
-- the spellbook may not be loaded when the curves are first made (cast-time DoTs would get the instant window):
-- look again a moment after entering the world, and rebuild only if the cast times differ from what they were built on
function R.recheckWindows()
  if R.builtOn ~= R.castPrint() then applyCurves(); return true end
  return false
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
  R.db = db
  BC = ns.blizzard
  if db.othersAlpha then R.OTHERS_ALPHA = db.othersAlpha / 100; if db.othersAlpha == 0 then db.others = false end end
  if db.othersMode == 'blizzard' then db.others = false; db.squares = 'all' elseif db.othersMode == 'rings' then db.others = true; db.squares = 'notmine' end
  db.saved = db.saved or {}; db.learned = db.learned or {}
  if not (C_UnitAuras and C_NamePlate and C_CurveUtil and C_StringUtil) then say('this client is missing the aura container APIs; the OmaDoomed rings are off.'); db = nil; R.db = nil; return end
  holder = CreateFrame('Frame', nil, UIParent); holder:Hide()
  filler = CreateFrame('Frame')
  R.fadeStart()
  ev = CreateFrame('Frame')
  for _, e in ipairs({ 'PLAYER_REGEN_ENABLED', 'PLAYER_REGEN_DISABLED', 'PLAYER_TARGET_CHANGED', 'SPELLS_CHANGED', 'PLAYER_ENTERING_WORLD' }) do pcall(ev.RegisterEvent, ev, e) end
  pcall(ev.RegisterUnitEvent, ev, 'UNIT_SPELLCAST_SUCCEEDED', 'player')
  ev:SetScript('OnEvent', function(...) local ok, err = pcall(onEvent, ...); if not ok then ns.error('rings event: ' .. tostring(err)) end end)
  ns.bus:On('TICK', function(unit, name, key) if ns.db.tick ~= 'plain' then ns.ringsPulse(unit, name, key) end end)
  ns.bus:On('SETTING', function(key, store)
    if store == 'rings' then ns.ringsApply(key)
    elseif key == 'low' or key == 'lowlook' or key == 'recast' then applyCurves() end
  end)
  -- plates come and go through PlateManager (the one owner of the nameplate events)
  ns.bus:On('PLATE_ADDED', function(u, plate, enemy) if db and enemy then attach(u) end end)
  ns.bus:On('PLATE_REMOVED', function(u) if db then release(u) end end)
  ns.bus:On('PLATE_CHANGED', function(u, plate, enemy, why)
    if not db then return end
    if why == 'hostility' then if enemy then attach(u) else release(u) end   -- a duel starts, a mob is charmed
    else local p = active[u]; if p then hostOn(p.anchor, plate, u); place(p.anchor, plate, u); placeBar(p, plate, u) end end   -- another bar
  end)
  R.probe(); R.buildGroups()
  if db.enabled then BC.blizzardRow(false) end
  R.whenGlyph(function() fill(); attachAll() end)   -- rows wait for the ring font (their ending effects need it)
  if db.where ~= 'enemy' then C_Timer.After(1, function() makeFramePair(); if db.where == 'split' then ns.makeChanPair() end; visible() end) end
  BC.squaresApply()
end
ns.starts[#ns.starts + 1] = start
onEvent = (function(_, e, a1, _, a3)
  if not db then return end
  if e == 'PLAYER_TARGET_CHANGED' then
    visible(); BC.squaresApply()
    -- switching straight from one enemy to another (Haunt, Target frame): the rows that follow 'target' re-read
    reread(framePair); reread(chanPair)
    -- the name can appear or move when the target changes; keep each row on top of its name
    for u, p in pairs(active) do local plate = PM.live[u]; if plate then place(p.anchor, plate, u); placeBar(p, plate, u) end end
  elseif e == 'PLAYER_REGEN_DISABLED' then visible()
  elseif e == 'PLAYER_REGEN_ENABLED' then
    if filtersDirty then refreshFilters(); placeAllSeats() end
    if curvesDirty then applyCurves() end
    fill(); attachAll()                                  -- plates that showed up in combat with no spare container
    if db.where ~= 'enemy' then makeFramePair() end
    if db.where == 'split' then ns.makeChanPair() end
    channelGroup(framePair, db.where ~= 'split')
    visible()
  elseif e == 'PLAYER_ENTERING_WORLD' then if C_Timer and C_Timer.After then C_Timer.After(2, R.recheckWindows) end
  elseif e == 'SPELLS_CHANGED' then applyCurves(); if not InCombatLockdown() then refreshFilters(); placeAllSeats() else filtersDirty = true end
  elseif e == 'UNIT_SPELLCAST_SUCCEEDED' then learn(a3)
  end
end)

local toldReload = false
-- the rings on or off (Options or /omadoomed rings on|off); Blizzard's own row comes back while they're off
local function setEnabled(on)
  db.enabled = on
  if on then BC.blizzardRow(false); BC.squaresApply(); fill(); attachAll(); visible()
  else releaseAll(); BC.blizzardRow(true); BC.squaresApply(); visible() end
end
function ns.ringsApply(key)
  if not db then return end
  if key == 'enabled' then setEnabled(db.enabled ~= false)
  elseif key == 'size' or key == 'alpha' then for _, p in ipairs(pairsAll) do look(p) end; visible()
  elseif key == 'othersAlpha' then
    R.OTHERS_ALPHA = (db.othersAlpha or 55) / 100
    setOthers(db.othersMode ~= 'blizzard' and (db.othersAlpha or 55) > 0)
    -- a slider sends every step: say it once
    if not toldReload then toldReload = true; say("other players' rings: a new strength shows after a /reload (0 hides them at once).") end
  elseif key == 'where' then
    if db.where ~= 'enemy' then makeFramePair() end
    if db.where == 'split' then ns.makeChanPair() end
    channelGroup(framePair, db.where ~= 'split')   -- out of combat only; otherwise after the fight (REGEN_ENABLED)
    visible()
  elseif key == 'which' then visible()
  elseif key == 'squares' then BC.squaresApply()
  elseif key == 'othersMode' then
    db.squares = db.othersMode == 'blizzard' and 'all' or 'notmine'; BC.squaresApply()
    setOthers(db.othersMode ~= 'blizzard')
  end
end

-- ---------- /omadoomed rings ... ----------
function ns.ringsSlash(msg)
  if not db then return end
  local cmd, arg = (msg or ''):match('^(%S*)%s*(.-)$'); cmd = cmd:lower(); arg = arg:lower()
  if cmd == 'off' then
    setEnabled(false)
    say('off: Blizzard\'s debuff row is back' .. (BC.pending() and ' after this fight.' or '.'))
  elseif cmd == 'on' then
    setEnabled(true)
    say('on' .. (BC.pending() and ' (Blizzard\'s row goes off after this fight).' or '.'))
  elseif cmd == 'others' and (arg == 'on' or arg == 'off') then
    setOthers(arg == 'on'); say('other players\' DoTs ' .. ((db.others and R.othersOK) and 'on' or 'off') .. '.')
  else
    local n = 0; for _ in pairs(active) do n = n + 1 end
    say(('%s. Rows on %d plates, %d spare.'):format(db.enabled and 'On' or 'Off', n, #free))
    if R.diag then say('Ending effects: ' .. R.diag() .. '.') end
    say('Ending soon: ' .. (R.GLYPH and 'ring turns gold and breathes, number breathes.' or 'ring font unavailable, so the number turns gold and breathes.'))
    say('Other players\' DoTs: ' .. ((db.others and R.othersOK) and 'on' or (R.othersOK and 'off' or 'not allowed by the game')) .. '.')
    say('Blizzard\'s debuff row: ' .. BC.state() .. '.')
  end
end
