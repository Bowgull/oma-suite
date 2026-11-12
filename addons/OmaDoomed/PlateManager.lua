-- PlateManager: the one owner of the nameplate events. It keeps the list of live plates and tells the views on the bus:
--   PLATE_ADDED   (unit, plate, enemy)        a plate appeared
--   PLATE_REMOVED (unit, plate)               it went
--   PLATE_CHANGED (unit, plate, enemy, why)   why = 'hostility' (duels, charm, mobs turning) or 'bar' (another bar found)
-- Rebuilt at PLAYER_ENTERING_WORLD: a loading screen may not say every plate went.
--
-- And the health bar finder, for other nameplate add-ons: ns.plateBar(plate, unit) -> bar, host, source, addon, hidden.
--   addon: another add-on's bar (match its layer, no Blizzard atlas mask). hidden: Blizzard's bar, not on screen.
-- The EllesmereUI, Platynator, Threat Plates, visibility and automatic search parts are adapted from Does It Die (MIT,
-- notice in Track/LICENSE-DoesItDie), Nameplates.lua. The Plater part is our own, from the idea in its issue #34.
-- Warlocks only: Core.lua runs start() at a warlock's login.
local ADDON, ns = ...
local Secret = ns.core.Secret
local PM = { live = {}, enemy = {}, bars = {}, unitOf = setmetatable({}, { __mode = 'k' }) }
ns.plates = PM

-- ---------- reading other add-ons' frames, always guarded ----------
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

local function isStatusBar(v)
  if type(v) ~= 'table' then return false end
  local kind = call(v, 'GetObjectType')
  if type(kind) == 'string' then return kind == 'StatusBar' end
  return type(get(v, 'GetStatusBarTexture')) == 'function'
end
local function forbidden(f) return call(f, 'IsForbidden') == true end

-- On screen: shown, not see-through, and not cut loose (Plater can't hide Blizzard's protected plate, so it un-parents
-- it: still "visible", nowhere on screen). Read through parents only; Forever won't measure nameplate regions.
-- `stop`: an ancestor known to be on screen (the plate itself).
function PM.onScreen(bar, stop)
  if type(bar) ~= 'table' then return false end
  if call(bar, 'IsVisible') == false then return false end
  local a = call(bar, 'GetEffectiveAlpha'); if type(a) == 'number' and a <= 0 then return false end
  local cur = bar
  for _ = 1, 20 do
    if cur == stop or cur == UIParent or cur == WorldFrame then return true end
    local p = call(cur, 'GetParent')
    if p == nil then return call(cur, 'GetNumPoints') ~= 0 end
    cur = p
  end
  return true
end

-- a bar's layer: strata (string) and level (number), nil when unreadable
function PM.layerOf(bar)
  local s, l = call(bar, 'GetFrameStrata'), call(bar, 'GetFrameLevel')
  return type(s) == 'string' and s or nil, type(l) == 'number' and l or nil
end
function PM.reversed(bar) return call(bar, 'GetReverseFill') == true end

-- ---------- the finders, in order ----------
-- Plater: its unit frame hangs off Blizzard's plate as unitFramePlater / unitFrame (lower case), often parented to
-- UIParent. Our widgets go on that frame, so they fade, scale and hide with it.
local function plater(plate)
  local uf = get(plate, 'unitFramePlater') or get(plate, 'unitFrame')
  if type(uf) ~= 'table' or uf == get(plate, 'UnitFrame') then return end
  local bar = get(uf, 'healthBar')
  if isStatusBar(bar) and not forbidden(bar) and PM.onScreen(bar, plate) then return bar, uf end
end

-- EllesmereUI: a pooled plate of its own, listed by unit, bar at .health
local function ellesmere(plate, unit)
  local eui = _G.EllesmereNameplates_NS
  local p = type(eui) == 'table' and type(get(eui, 'plates')) == 'table' and unit and eui.plates[unit]
  if type(p) == 'table' and get(p, 'nameplate') == plate and type(get(p, 'health')) == 'table' then return p.health, p end
end

-- Platynator: display frames hung off UIParent on Forever (or off the plate), matched by .unit, health widget
-- details.kind == 'health' -> .statusBar. Rescanned at most every 2 s when a unit has none.
local platy, platyScan = {}, -math.huge
local function isPlaty(f) return type(get(f, 'widgets')) == 'table' and type(get(f, 'Install')) == 'function' and type(get(f, 'SetUnit')) == 'function' end
local function platyBar(unit)
  for d in pairs(platy) do
    if get(d, 'unit') == unit and call(d, 'IsShown') == true then
      for _, w in ipairs(d.widgets) do
        local det = get(w, 'details')
        if type(det) == 'table' and det.kind == 'health' and type(get(w, 'statusBar')) == 'table' then return w.statusBar end
      end
    end
  end
end
local function platynator(plate, unit)
  if not (_G.Platynator and unit) then return end
  local bar = platyBar(unit); if bar then return bar end
  local now = GetTime(); if now - platyScan < 2 then return end
  platyScan = now
  for _, parent in ipairs({ UIParent, plate }) do
    local kids = { pcall(get(parent, 'GetChildren'), parent) }
    for i = 2, #kids do local c = kids[i]; if type(c) == 'table' and not platy[c] and isPlaty(c) then platy[c] = true end end
  end
  return platyBar(unit)
end

-- Threat Plates: plate.TPFrame (it hangs off WorldFrame), active while it draws this unit, bar .visual.Healthbar
local function threatPlates(plate)
  local tp = get(plate, 'TPFrame')
  if type(tp) ~= 'table' or not get(tp, 'Active') then return end
  local v = get(tp, 'visual'); if type(v) ~= 'table' then return end
  local bar = get(v, 'Healthbar') or get(v, 'healthbar')
  if isStatusBar(bar) and not forbidden(bar) and PM.onScreen(bar, plate) then return bar end
end

-- Blizzard's own bar (the same paths the kill bar always used)
local function blizzard(plate)
  local uf = get(plate, 'UnitFrame'); if type(uf) ~= 'table' then return end
  local c = get(uf, 'HealthBarsContainer')
  local hb = (type(c) == 'table' and (get(c, 'healthBar') or get(c, 'HealthBar'))) or get(uf, 'healthBar')
  if type(hb) == 'table' and type(get(hb, 'GetStatusBarTexture')) == 'function' then return hb end
end

-- Automatic search: a shown StatusBar under a key containing "health", inside the plate (not Blizzard's UnitFrame),
-- breadth first, 4 deep. Each field read under its own guard. Kept per plate; searched again at most once a second.
local DEPTH, BIG = 4, 200
local cache = setmetatable({}, { __mode = 'k' })
local function isUnder(f, plate)
  local cur = f
  for _ = 1, 12 do local p = call(cur, 'GetParent'); if p == nil then return false end; if p == plate then return true end; cur = p end
  return false
end
local function fields(t, plain)
  local ok, out = pcall(function()
    local found, n = {}, 0
    for k, v in pairs(t) do
      n = n + 1; if plain and n > BIG then return nil end
      if type(k) == 'string' and type(v) == 'table' then found[#found + 1] = { k, v } end
    end
    return found
  end)
  if not ok or not out then return nil end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end
local function search(plate)
  local skip = get(plate, 'UnitFrame')
  local q, seen, head = { { plate, '', 0, false } }, { [plate] = true }, 1
  while q[head] do
    local node, path, depth, plain = q[head][1], q[head][2], q[head][3], q[head][4]; head = head + 1
    local fs = fields(node, plain)
    if fs then
      for _, f in ipairs(fs) do
        local ok, hit = pcall(function()
          return f[1]:lower():find('health', 1, true) and isStatusBar(f[2]) and not forbidden(f[2]) and isUnder(f[2], plate) and PM.onScreen(f[2], plate)
        end)
        if ok and hit then return f[2], path .. f[1] end
      end
      if depth < DEPTH then
        for _, f in ipairs(fs) do
          local v = f[2]
          if not seen[v] and v ~= skip then
            seen[v] = true
            local frame = type(call(v, 'GetObjectType')) == 'string'
            if not frame or (not isStatusBar(v) and not forbidden(v) and isUnder(v, plate)) then
              q[#q + 1] = { v, path .. f[1] .. '.', depth + 1, not frame }
            end
          end
        end
      end
    end
  end
end
local function auto(plate)
  local c, now = cache[plate], GetTime()
  if c and c.bar and PM.onScreen(c.bar, plate) then return c.bar, c.path end
  if c and now - c.at < 1 then return end
  local ok, bar, path = pcall(search, plate)
  if not ok then bar, path = nil, nil end
  cache[plate] = { bar = bar, path = path, at = now }
  return bar, path
end

-- bar, host, source, addon, hidden
function ns.plateBar(plate, unit)
  if type(plate) ~= 'table' then return nil, nil, 'no plate' end
  local ok, bar, host = pcall(plater, plate)
  if ok and bar then return bar, host, _G.Plater and 'Plater' or 'unitFrame.healthBar', true end
  ok, bar, host = pcall(ellesmere, plate, unit)
  if ok and bar then return bar, host, 'EllesmereUI', true end
  ok, bar = pcall(platynator, plate, unit)
  if ok and bar then return bar, plate, 'Platynator', true end
  ok, bar = pcall(threatPlates, plate)
  if ok and bar then return bar, plate, 'Threat Plates', true end
  local okB, blz = pcall(blizzard, plate)
  if not okB then blz = nil end
  if blz and PM.onScreen(blz, plate) then return blz, plate, 'Blizzard', false end
  local okA, found, path = pcall(auto, plate)
  if okA and found then return found, plate, 'found ' .. path, true end
  if blz then return blz, plate, 'Blizzard (hidden)', false, true end
  return nil, nil, 'none'
end

-- ---------- the live list ----------
local function hostile(u) return Secret.call(UnitCanAttack, 'player', u) end   -- true / false / nil (hidden: can't tell)

local function find(u, plate)
  local bar, host, source, addon, hidden = ns.plateBar(plate, u)
  return { bar = bar, host = host, source = source, addon = addon, hidden = hidden }
end
-- the bar found for a live unit (kept; looked for again when it had none or a hidden one)
function PM.barOf(u)
  local plate = PM.live[u]; if not plate then return nil end
  local b = PM.bars[u]
  if not b or not b.bar or b.hidden then b = find(u, plate); PM.bars[u] = b end
  return b
end

local function add(u)
  if not (type(u) == 'string' and u:match('^nameplate%d+$')) or PM.live[u] then return end
  local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, u, false)
  if not ok or not plate then return end
  PM.live[u] = plate; PM.unitOf[plate] = u
  PM.enemy[u] = hostile(u) == true
  PM.bars[u] = find(u, plate)
  ns.bus:Fire('PLATE_ADDED', u, plate, PM.enemy[u])
end
local function remove(u)
  local plate = PM.live[u]; if not plate then return end
  PM.live[u], PM.enemy[u], PM.bars[u] = nil, nil, nil
  if PM.unitOf[plate] == u then PM.unitOf[plate] = nil end
  ns.bus:Fire('PLATE_REMOVED', u, plate)
end
local function hostilityChanged(u)
  local plate = PM.live[u]; if not plate then return end
  local h = hostile(u); if h == nil then return end   -- hidden in combat: keep what we knew
  if h ~= PM.enemy[u] then PM.enemy[u] = h; ns.bus:Fire('PLATE_CHANGED', u, plate, h, 'hostility') end
end
-- every live plate again: the bar it uses may have changed (another add-on took over, a display was assigned late).
-- Nothing is made unless something changed.
local function recheckOne(u, plate)
  local bar, host, source, addon, hidden = ns.plateBar(plate, u)
  local b = PM.bars[u]
  if b and b.bar == bar and b.host == host and b.source == source and b.hidden == hidden then return end
  PM.bars[u] = { bar = bar, host = host, source = source, addon = addon, hidden = hidden }
  ns.bus:Fire('PLATE_CHANGED', u, plate, PM.enemy[u], 'bar')
end
local function recheck()
  for u, plate in pairs(PM.live) do
    local ok, err = pcall(recheckOne, u, plate)
    if not ok then ns.error('plates: ' .. u .. ': ' .. tostring(err)) end
  end
end
function PM.scan() for i = 1, 40 do local u = 'nameplate' .. i; if UnitExists(u) then add(u) end end end
function PM.rebuild()
  local us = {}; for u in pairs(PM.live) do us[#us + 1] = u end
  for _, u in ipairs(us) do remove(u) end
  PM.scan()
end

local function onEvent(_, e, u)
  if e == 'NAME_PLATE_UNIT_ADDED' then
    add(u)   -- and once more next frame: some add-ons set their plate up after this event
    C_Timer.After(0, function() local plate = PM.live[u]; if plate then local ok, err = pcall(recheckOne, u, plate); if not ok then ns.error('plates: ' .. tostring(err)) end end end)
  elseif e == 'NAME_PLATE_UNIT_REMOVED' then remove(u)
  elseif e == 'UNIT_FACTION' or e == 'UNIT_FLAGS' then if PM.live[u] then hostilityChanged(u) end
  elseif e == 'PLAYER_ENTERING_WORLD' then PM.rebuild()
  end
end

local function start()
  local ev = CreateFrame('Frame')
  for _, e in ipairs({ 'NAME_PLATE_UNIT_ADDED', 'NAME_PLATE_UNIT_REMOVED', 'UNIT_FACTION', 'UNIT_FLAGS', 'PLAYER_ENTERING_WORLD' }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  ev:SetScript('OnEvent', function(...) local ok, err = pcall(onEvent, ...); if not ok then ns.error('plates event: ' .. tostring(err)) end end)
  local acc = 0
  ev:SetScript('OnUpdate', function(_, dt) acc = acc + dt; if acc >= 1 then acc = 0; recheck() end end)
  PM.scan()
end
ns.starts[#ns.starts + 1] = start

-- ---------- /omadoomed plates: which bar each plate and the target frame use (for bug reports) ----------
local function layerText(bar)
  local s, l = PM.layerOf(bar)
  return (s or '?') .. ' ' .. (l and tostring(l) or '?')
end
function ns.barLines()
  local out = {}
  local us = {}; for u in pairs(PM.live) do us[#us + 1] = u end
  table.sort(us, function(a, b) return (tonumber(a:match('%d+')) or 0) < (tonumber(b:match('%d+')) or 0) end)
  for _, u in ipairs(us) do
    local b = PM.barOf(u) or {}
    out[#out + 1] = ('%s: %s%s, %s, layer %s'):format(u, b.source or '?', PM.enemy[u] and '' or ' (not an enemy)',
      b.bar and (PM.reversed(b.bar) and 'fills right to left' or 'fills left to right') or 'no bar', b.bar and layerText(b.bar) or '-')
  end
  if #out == 0 then out[1] = 'no nameplates showing' end
  if ns.targetBarLine then out[#out + 1] = ns.targetBarLine() end
  return out
end
