-- OmaWay: the guide arrow and the quest / dungeon modes (sheets 111 and 112, approved 2026-11-17).
-- Core: saved settings, chat, the waypoint the arrow follows, and the TomTom stand-in.
--
-- How the arrow gets its directions: Guidelime ("Use TomTom arrow") and Questie (ctrl-click a map icon) hand a
-- waypoint to TomTom:AddWaypoint(mapID, x, y, opts) and take it back with TomTom:RemoveWaypoint(uid); Guidelime also
-- checks that TomTom.SetCrazyArrow exists. When the real TomTom isn't loaded, OmaWay answers those calls itself and
-- shows the waypoint on its own arrow. With the real TomTom loaded OmaWay leaves it alone (its arrow is TomTom's).
local ADDON, ns = ...
ns.name = ADDON

local DEFAULTS = {
  size = 64,            -- px at scale 1 (Joshua 2026-11-17: "64 px")
  locked = false,
  alpha = 100,          -- %
  text = 12,            -- yards line font size
  yards = true,         -- show the yards / name line
  mode = 'auto',        -- 'auto' (dungeon inside instances), 'quest' or 'dungeon' (a click on the chip)
}
ns.DEFAULTS = DEFAULTS

function ns.say(msg) print('|cffb48cffOmaWay:|r ' .. tostring(msg)) end

function ns.db()
  OmaWayDB = OmaWayDB or {}
  local db = OmaWayDB
  for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
  return db
end

-- ---------- the waypoint ----------
-- Two sources (sheet 115): ext, what another add-on hands in (a Guidelime step, a Questie ctrl-click), and auto,
-- OmaWay's own (Quests.lua: the quest you focused in Questie, or the nearest quest job). The order:
--   a focused quest  >  ext  >  the nearest quest job
local ext, auto     -- { mapID, x, y, title, line2, icon, arrive, from, focus, wx, wy, inst }
local uidN = 0
function ns.waypoint()
  if auto and auto.focus then return auto end
  return ext or auto
end
function ns.external() return ext end

local function hbd() return LibStub and LibStub('HereBeDragons-2.0', true) end
ns.hbd = hbd

local function make(mapID, x, y, opts)
  opts = type(opts) == 'table' and opts or {}
  if type(mapID) ~= 'number' or type(x) ~= 'number' or type(y) ~= 'number' then return nil end
  uidN = uidN + 1
  local w = { uid = uidN, mapID = mapID, x = x, y = y, title = opts.title, line2 = opts.line2, icon = opts.icon,
    arrive = tonumber(opts.arrivaldistance) or 0, from = opts.from, focus = opts.focus }
  local H = hbd()
  if H then
    local ok, wx, wy, inst = pcall(H.GetWorldCoordinatesFromZone, H, x, y, mapID)
    if ok then w.wx, w.wy, w.inst = wx, wy, inst end
  end
  return w
end
local function changed() if ns.arrowChanged then ns.arrowChanged() end end

-- another add-on's waypoint (the TomTom slot)
function ns.setWaypoint(mapID, x, y, opts)
  local w = make(mapID, x, y, opts); if not w then return nil end
  ext = w; changed(); return w
end
function ns.clearWaypoint(uid)
  if ext and (uid == nil or uid == ext or uid == ext.uid) then ext = nil; changed() end
end
-- OmaWay's own (Quests.lua)
function ns.setAuto(mapID, x, y, opts) auto = make(mapID, x, y, opts); changed(); return auto end
function ns.clearAuto() if auto then auto = nil; changed() end end
function ns.autoTarget() return auto end

-- ---------- the TomTom stand-in ----------
-- Only when the real TomTom is absent (OptionalDeps loads it first when it's installed).
local function realTomTom()
  local f = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  local ok, v = pcall(f, 'TomTom'); return ok and v and true or false
end
if not realTomTom() and _G.TomTom == nil then
  local T = { omaway = true }
  -- both TomTom:AddWaypoint(...) and TomTom.AddWaypoint(TomTom, ...) arrive here as (self, mapID, x, y, opts)
  function T.AddWaypoint(self, mapID, x, y, opts) return ns.setWaypoint(mapID, x, y, opts) end
  function T.AddWaypointToCurrentZone(self, x, y, title)
    local H = hbd(); local m = H and H:GetPlayerZone()
    return m and ns.setWaypoint(m, x / 100, y / 100, { title = title }) or nil
  end
  function T.RemoveWaypoint(self, uid) ns.clearWaypoint(uid) end
  function T.ClearWaypoint(self, uid) ns.clearWaypoint(uid) end
  function T.SetCrazyArrow(self, uid) if type(uid) == 'table' and uid.uid then ext = uid; changed() end end
  function T.IsValidWaypoint(self, uid) return ext ~= nil and (uid == ext or uid == ext.uid) end
  function T.GetDistanceToWaypoint(self, uid) if ns.distance and ext and (uid == ext or uid == ext.uid) then return ns.distance() end end
  _G.TomTom = T
  ns.standIn = true
end
