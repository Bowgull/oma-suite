-- The DoT model: what the kill bar draws, worked out from OmaDoomed's own tracking (Track/) and your casts. No frames
-- are drawn here. One snapshot per target mob holds everything learned about it (ticks, predicted ticks, bites, the
-- precast and landed pieces, ending ghosts); a new target starts a fresh snapshot, so nothing leaks between mobs.
-- Your own casts (a DoT's size when fresh, the moment it landed) are kept across targets.
--
-- Bus events: TICK (unit, name, key) a DoT ticked or is due to, TARGET a new target (fresh snapshot),
-- DOTS something may have changed (redraw), ROW (cur, extra) what the bar is about to draw (bug reports).
local ADDON, ns = ...
local M = {}
ns.model = M
local Spells, Anim, Secret = ns.spells, ns.core.Anim, ns.core.Secret
local Track = ns.track

local function beatOf(name) local sp = Spells.dot(name); return sp and sp.beat or 3 end

-- your casts, across targets
local fullBy = {}                -- DoT name -> its full damage when fresh (for a first cast the tracking doesn't list yet)
local landAt, landLook = {}, {}  -- DoT name -> when it last landed from a cast, and the cast look it had
local cast = {}                  -- the last cast START: { guid, plate }

-- the target's snapshot: per = { [name] = record }, order = names last drawn, cur = { dots, maxv, hp }, landed
-- A record: last (damage seen last time), bite { amt, at, quiet }, pred { est, at }, predK, predApplied, exp, wasPre,
-- and the kill bar's own notes for that DoT (shown: its size on screen, slot: the textures it owns).
local snap
local function fresh() snap = { per = {} } end
fresh()
M.fullBy, M.landAt, M.landLook = fullBy, landAt, landLook
function M.snap() return snap end
function M.rec(name) local r = snap.per[name]; if not r then r = {}; snap.per[name] = r end; return r end
function M.peek(name) return snap.per[name] end
function M.cur() return snap.cur end
function M.clearCur() snap.cur = nil end
M.test = false                   -- the bar's /omadoomed test: no predictions, no bug-report rows

-- the animation clock: like GetTime, but a stall of the game (0.15-0.2 s seen in town) only moves it one frame, so a
-- slide carries on from where it was instead of skipping ahead
function M.clock() return M.now or GetTime() end
function M.step(dt) M.dt = math.min(dt, .05); M.now = M.clock() + math.min(dt, .05) end

local function tick(name) ns.bus:Fire('TICK', 'target', name, Spells.key(name)) end

-- ---------- the list ----------
function M.source(unit) return ns.dotsFor(unit) end
-- one entry per name, the one that runs out first nearest the green; a copy (the source's own table is never
-- sorted). positive: only DoTs with damage left (the plate bar's list).
local function byExpiry(a, b) return (a.expiresAt or 0) < (b.expiresAt or 0) end
function M.list(unit, positive)
  local raw, list, seen = M.source(unit), {}, {}
  for _, e in ipairs(raw) do
    if e.name and not seen[e.name] and (not positive or (e.damage or 0) > 0) then seen[e.name] = true; list[#list + 1] = e end
  end
  table.sort(list, byExpiry)
  return list
end

-- the target's DoTs as the bar draws them: { {name, damage, expires, appliedAt, provisional, castStart, castEnd,
-- landed} }. Adds the precast piece (a DoT you're casting that the tracking doesn't list yet) and the landed piece
-- (it landed, the tracking lists it at its first tick).
function M.targetDots()
  local list = M.list('target')
  for _, e in ipairs(list) do Spells.see(e.spellID, e.name) end
  local dots = {}
  local cName, _, _, cStart, cEnd = UnitCastingInfo('player')
  local now = GetTime()
  for _, e in ipairs(list) do if (e.damage or 0) > 0 then
    local d = { name = e.name, damage = e.damage, expires = e.expiresAt, appliedAt = e.appliedAt, provisional = e.provisional }
    if e.provisional and cName == e.name and cStart and cEnd then d.castStart, d.castEnd = cStart / 1000, cEnd / 1000 end
    if not e.provisional and e.appliedAt and now - e.appliedAt < 4 then fullBy[e.name] = math.max(fullBy[e.name] or 0, e.damage) end
    dots[#dots + 1] = d
  end end
  -- a first cast showed nothing ("i didnt see precast"): while you cast a DoT it doesn't list, show it at the size
  -- it last had when fresh. A cast belongs to the mob you were targeting when it started (plate frames are never secret).
  local here = C_NamePlate.GetNamePlateForUnit('target', false) or false
  local sameMob = cast.plate == nil or cast.plate == here
  if cName and Spells.dot(cName) and cStart and cEnd and fullBy[cName] and sameMob then
    local listed = false; for _, d in ipairs(dots) do if d.name == cName then listed = true end end
    if not listed then dots[#dots + 1] = { name = cName, damage = fullBy[cName], expires = cEnd / 1000 + 30, provisional = true, castStart = cStart / 1000, castEnd = cEnd / 1000 } end
  end
  -- once it lands, keep it (solid) until the tracking lists it at its first tick, so it doesn't blink out for 3 s
  local ld = snap.landed
  if ld and not cName then
    local listed = false; for _, d in ipairs(dots) do if d.name == ld.name then listed = true end end
    if listed or now - ld.at > 4.5 then snap.landed = nil
    elseif M.landedHere(ld, here) then dots[#dots + 1] = { name = ld.name, damage = ld.dmg, expires = ld.at + 30, landed = true } end
  end
  return dots
end

-- ---------- bites ----------
-- what is still left of a bite (0 when done), and its flare 0..1
function M.bite(name, now)
  local r = snap.per[name]; local b = r and r.bite; if not b then return 0, 0 end
  local a = now - b.at
  if a >= .7 then r.bite = nil; return 0, 0 end
  -- 2026-11-11 'it flashes then almost jumps': the glide starts from rest, is quickest midway and settles
  -- (smootherstep over 0.5 s); the light swells instead of flashing.
  local k = Anim.smootherstep(a / .5)
  local left = b.amt * (1 - k)
  -- 2026-11-11 'the ticks are a bit jumpy, plain is smooth': the light swells and settles on smooth curves
  local ss = Anim.smoothstep
  local flare = a < .16 and ss(a / .16) or 1 - ss((a - .16) / .5)
  return left, flare
end
function M.biteOf(name) local r = snap.per[name]; return r and r.bite end
function M.dropBites() for _, r in pairs(snap.per) do r.bite = nil end end

-- ---------- ticks ----------
-- new numbers (10 times a second and on events): notice ticks (a drop in damage left), keep ended DoTs as empty
-- ghosts while their last bite closes, note casts landing. dots may grow (ghosts); maxv / hp may be hidden numbers.
function M.feed(dots, maxv, hp)
  local now, anow = GetTime(), M.clock()
  -- 2026-11-11 'when a DoT ends there's still a snap': it stays in its old place, empty, while that last bite closes
  local here = {}; for _, d in ipairs(dots) do here[d.name] = true end
  for idx, name in ipairs(snap.order or {}) do
    if not here[name] then
      local r = M.rec(name)
      local pr = r.pred
      local remaining = (r.last or 0) - (pr and pr.est or 0)
      if remaining > .5 then
        -- review #5: only a DoT that was about to end really ticked its last; one removed early slides out quietly
        local endsIn = r.exp and (r.exp - now) or 0
        local natural = endsIn < beatOf(name) * 1.2
        local b = r.bite
        if b then b.amt = b.amt + remaining; if not natural then b.quiet = true end
        else r.bite = { amt = remaining, at = anow, quiet = not natural }; if natural then tick(name) end end
      end
      r.pred = nil; r.last = 0
      if r.bite and M.bite(name, anow) > 0 then
        table.insert(dots, math.min(idx, #dots + 1), { name = name, damage = 0, expires = r.exp, ending = true })
      else r.last = nil end
    end
  end
  local order = {}
  for i, d in ipairs(dots) do order[i] = d.name; M.rec(d.name).exp = d.expires end
  snap.order = order
  for _, d in ipairs(dots) do
    local r = M.rec(d.name)
    if r.last and d.damage < r.last - .5 then
      local real = r.last - d.damage
      local pr = r.pred
      if pr and now - pr.at < 1 then
        -- already showing: this tick was predicted on its beat. Only the size is corrected (a small change).
        if r.bite then r.bite.amt = math.max(0, r.bite.amt + real - pr.est) end
        r.pred = nil
      else
        r.bite = { amt = M.bite(d.name, anow) + real, at = anow }
        tick(d.name)
      end
    end
    r.last = d.damage
  end
  for _, r in pairs(snap.per) do if r.pred and now - r.pred.at >= 1 then r.pred = nil end end   -- not a tick after all
  -- a precast piece that lands: remember when and in which look (the bar eases it to full colour)
  local look = ns.db.cast or 'charging'
  for _, d in ipairs(dots) do
    local r = M.rec(d.name)
    if d.provisional then r.wasPre = look
    elseif r.wasPre then landAt[d.name] = anow; landLook[d.name] = r.wasPre; r.wasPre = nil end
  end
  snap.cur = { dots = dots, maxv = maxv, hp = hp }
  if not M.test then
    local nb = 0; for _, r in pairs(snap.per) do if r.bite then nb = nb + 1 end end
    ns.bus:Fire('ROW', snap.cur, nb > 0 and ('bites' .. nb) or nil)   -- the bug-report record (Report.lua)
  end
  return snap.cur
end

-- the health just changed: if a DoT is due to tick right now (its beat, within 0.25 s), start its bite this frame
function M.onHealth()
  local cur = snap.cur
  if not cur or M.test then return end
  -- review #2: any hit near a DoT's beat looked like its tick. In a group others hit all the time, so only predict solo.
  if IsInGroup and IsInGroup() then return end
  local now = GetTime()
  for _, d in ipairs(cur.dots) do
    local beat = d.appliedAt and beatOf(d.name)
    local r = beat and M.rec(d.name)
    if beat and r.predApplied ~= d.appliedAt then r.predApplied = d.appliedAt; r.predK = nil end   -- review #13: a recast starts the count again
    if beat and not d.provisional then
      local k = math.floor((now - d.appliedAt) / beat + .5)
      if k >= 1 and math.abs(now - (d.appliedAt + k * beat)) < .25 and (r.predK or 0) < k then
        r.predK = k
        local ticksLeft = math.max(1, math.floor(((d.expires or now) - (d.appliedAt + k * beat)) / beat + .5) + 1)
        local est = d.damage / ticksLeft
        r.bite = { amt = M.bite(d.name, M.clock()) + est, at = M.clock() }
        r.pred = { est = est, at = now }
        tick(d.name)
      end
    end
  end
end

-- ---------- casts and targets ----------
local function targetPlate() return C_NamePlate.GetNamePlateForUnit('target', false) or false end
-- a landed piece shows on the mob its cast went to: the tracking's mob key for that cast when it knows it, else the
-- plate it was cast at
function M.landedHere(ld, here)
  if ld.key then
    local ok, key = pcall(Track.tracking.unitKey, 'target')
    return ok and key == ld.key
  end
  return ld.plate == here
end
-- the start of a cast: the mob it belongs to
function M.castStart(castGUID)
  cast.guid = Secret.readable(castGUID) and castGUID or nil
  cast.plate = targetPlate()
end
-- a cast went off: a DoT the tracking won't list until its first tick shows as landed. Its mob, matched by cast ID:
-- where the tracking put that cast (a [@mouseover] or [@focus] cast too), else the plate its START was on; an instant
-- cast has no START, so then the target's (never the previous cast's mob).
function M.castSucceeded(castGUID, spellID)
  local n = spellID and Secret.readable(spellID) and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
  if n then Spells.see(spellID, n) end
  if not (n and Spells.dot(n) and fullBy[n]) then return end
  local same = Secret.readable(castGUID)
  local plate
  if same and cast.guid ~= nil and cast.guid == castGUID then plate = cast.plate else plate = targetPlate() end
  local lc = Track and Track.tracking and Track.tracking.omaLastCast
  local key = same and lc and Secret.readable(lc.guid) and lc.guid == castGUID and lc.key or nil
  snap.landed = { name = n, at = GetTime(), dmg = fullBy[n], plate = plate, key = key }
end
-- /omadoomed test: forget what was seen (no ticks or bites carried into the fake DoTs)
function M.forget() for _, r in pairs(snap.per) do r.last = nil; r.bite = nil end end
-- a new target: a fresh snapshot, in one place
function M.reset() fresh() end

function M.start()
  local ev = CreateFrame('Frame')
  ev:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player'); ev:RegisterUnitEvent('UNIT_SPELLCAST_START', 'player')
  ev:RegisterEvent('PLAYER_TARGET_CHANGED'); ev:RegisterUnitEvent('UNIT_HEALTH', 'target'); ev:RegisterUnitEvent('UNIT_AURA', 'target')
  local function onEv(_, e, unit, castGUID, spellID)
    if e == 'UNIT_SPELLCAST_SUCCEEDED' then return M.castSucceeded(castGUID, spellID) end
    if e == 'UNIT_SPELLCAST_START' then return M.castStart(castGUID) end
    if e == 'UNIT_HEALTH' then pcall(M.onHealth) end
    if e == 'PLAYER_TARGET_CHANGED' then M.reset(); return ns.bus:Fire('TARGET') end
    ns.bus:Fire('DOTS')
  end
  ev:SetScript('OnEvent', function(...) local ok, err = pcall(onEv, ...); if not ok then ns.error('model event: ' .. tostring(err)) end end)
  ns.onTrackChanged = function() ns.bus:Fire('DOTS') end
end
