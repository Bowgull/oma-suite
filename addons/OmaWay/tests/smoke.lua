-- OmaWay offline smoke test: a small fake WoW, then the three files, then the checks.
--   cd addons/OmaWay && luajit tests/smoke.lua
local checks, fails = 0, 0
local function ok(v, what) checks = checks + 1; if not v then fails = fails + 1; print('FAIL ' .. what) end end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-3) end

-- ---------- fake frames ----------
local frames = {}
local Obj = {}
Obj.__index = function(t, k)
  local m = rawget(Obj, k); if m then return m end
  if type(k) == 'string' and k:sub(1, 1) == '_' then return nil end   -- the fake's own fields
  if type(k) == 'string' and k:match('^[a-z]') then return nil end    -- the add-on's own fields (f.tex...)
  return function() end                              -- any other method: a quiet no-op
end
function Obj.Show(s) s._shown = true end
function Obj.Hide(s) s._shown = false end
function Obj.SetShown(s, v) s._shown = v and true or false end
function Obj.IsShown(s) return s._shown ~= false end
function Obj.SetScript(s, k, fn) s._scripts = s._scripts or {}; s._scripts[k] = fn end
function Obj.GetScript(s, k) return s._scripts and s._scripts[k] end
function Obj.SetAlpha(s, a) s._alpha = a end
function Obj.GetAlpha(s) return s._alpha or 1 end
function Obj.SetRotation(s, r) s._rot = r end
function Obj.SetSize(s, w, h) s._w, s._h = w, h end
function Obj.GetLeft() return 900 end
function Obj.GetTop() return 1000 end
function Obj.GetEffectiveScale() return 1 end
function Obj.GetStringWidth() return 80 end
function Obj.SetText(s, t) s._text = t end
function Obj.GetText(s) return s._text end
function Obj.SetTexture(s, t) s._tex = t end
function Obj.GetPoint(s) return 'TOPLEFT', nil, 'BOTTOMLEFT', 900, 1000 end
function Obj.CreateTexture(s) local t = setmetatable({}, Obj); s._texs = s._texs or {}; s._texs[#s._texs + 1] = t; return t end
function Obj.CreateFontString() return setmetatable({}, Obj) end
function Obj.RegisterEvent(s, e) s._events = s._events or {}; s._events[e] = true end
function CreateFrame(kind, name, parent)
  local f = setmetatable({ _kind = kind, _name = name }, Obj)
  frames[#frames + 1] = f
  if name then _G[name] = f end
  return f
end
UIParent, Minimap = CreateFrame('Frame'), CreateFrame('Frame')
STANDARD_TEXT_FONT = 'Fonts\\FRIZQT__.TTF'
BackdropTemplateMixin = {}
function InCombatLockdown() return false end
function GetCursorPosition() return CURSOR or 0 end
local printed = {}
print0 = print
print = function(m) printed[#printed + 1] = tostring(m) end

-- ---------- fake world ----------
local facing, inside = 0, false
function GetPlayerFacing() return facing end
function IsInInstance() return inside, inside and 'party' or 'none' end
local player = { x = 100, y = 100 }
local HBD = {}
function HBD:GetWorldCoordinatesFromZone(x, y, mapID) return x * 1000, y * 1000, 0 end
function HBD:GetPlayerWorldPosition() return player.x, player.y, 0 end
function HBD:GetPlayerZone() return 1426 end
function HBD:GetPlayerZonePosition() return .1, .1 end
-- world X is north, Y is west; the angle runs counter-clockwise from north, like the real library
function HBD:GetWorldVector(inst, ox, oy, dx, dy) local x, y = dx - ox, dy - oy; return math.atan2(y, x) % (2 * math.pi), math.sqrt(x * x + y * y) end
function LibStub(name, silent) if name == 'HereBeDragons-2.0' then return HBD end end
C_AddOns = { IsAddOnLoaded = function() return false end }
-- the other add-ons
GuidelimeDataChar = { mainFrameShowing = true }
local glToggles = 0
Guidelime = { toggleMainFrame = function() glToggles = glToggles + 1; GuidelimeDataChar.mainFrameShowing = not GuidelimeDataChar.mainFrameShowing end }
local said = {}
SlashCmdList = {
  ACECONSOLE_QUESTIE = function(m) said[#said + 1] = 'questie ' .. m end,
  DETAILS = function(m) said[#said + 1] = 'details ' .. m end,
}

-- ---------- load ----------
local ns = {}
for _, file in ipairs({ 'Core.lua', 'Arrow.lua', 'Quests.lua', 'Modes.lua' }) do
  local chunk = assert(loadfile(file)); chunk('OmaWay', ns)
end
local function fire(e) for _, f in ipairs(frames) do if f._events and f._events[e] and f._scripts and f._scripts.OnEvent then f._scripts.OnEvent(f, e) end end end
fire('PLAYER_LOGIN'); fire('PLAYER_ENTERING_WORLD')
local arrow = _G.OmaWayArrow
local function tick(n, el) for _ = 1, n or 1 do local s = arrow:GetScript('OnUpdate'); if s then s(arrow, el or .05) end end end

-- ---------- the TomTom slot ----------
ok(TomTom and TomTom.omaway, 'with no TomTom installed, OmaWay answers in its place')
ok(TomTom.AddWaypoint and TomTom.SetCrazyArrow and TomTom.RemoveWaypoint, "Guidelime's check passes (AddWaypoint and SetCrazyArrow)")
ok(not arrow:IsShown(), 'no waypoint: no arrow')
-- Guidelime's own call (Map.lua updateTomTomArrow): 0..1 map coords, its options table
local uid = TomTom:AddWaypoint(1426, .5, .1, { title = 'Apothecary Lydon', from = 'Guidelime', crazy = true, arrivaldistance = 0 })
ok(uid ~= nil, 'a waypoint handle comes back')
ok(arrow:IsShown(), 'the arrow shows')
-- target straight north of the player (world X is north), facing north: the arrow points straight up
local w = ns.waypoint(); player.x, player.y = w.wx - 200, w.wy
local off, on = arrow._texs[1], arrow._texs[2]
facing = 0; tick(40)
ok(near(on._rot, 0, .01), 'on course: pointing straight up (' .. tostring(on._rot) .. ')')
ok(near(on:GetAlpha(), 1) and near(off:GetAlpha(), 0), 'on course: the violet well, no red')
ok(ns.distance() and near(ns.distance(), 200, .5), 'the distance is the world distance in yards (200)')
ok((arrow._texs and true) and (on._rot == off._rot), 'both wells turn together')
-- turn to face west (+90 deg): the target is now on your right, so the arrow turns -90 deg; it eases, not jumps
facing = math.pi / 2; tick(1, .016)
ok(on._rot < 0 and on._rot > -math.pi / 2 + .05, 'the first frame only starts the turn (eased): ' .. on._rot)
tick(80)
ok(near(on._rot, -math.pi / 2, .01), 'then it settles on -90 deg')
-- face away (south): red
facing = math.pi; tick(120)
ok(near(off:GetAlpha(), 1) and near(on:GetAlpha(), 0), 'facing away: the red well')
-- walk up to it: arrived
player.x, player.y = w.wx - 3, w.wy; tick(2)
local hereTex = arrow._texs[3]
ok(near(on:GetAlpha(), 0) and (hereTex:GetAlpha() or 0) > .5, "within 5 yards: the arrow gives way to the gold 'here' ring")
player.x, player.y = w.wx - 200, w.wy; facing = 0; tick(40)
-- remove: the arrow goes
TomTom:RemoveWaypoint(uid)
ok(not arrow:IsShown(), "Guidelime's RemoveWaypoint hides it")

-- ---------- modes ----------
TomTom:AddWaypoint(1426, .5, .1, { title = 'Test' })
ok(arrow:IsShown(), 'quest mode: the arrow shows')
said = {}; glToggles = 0
inside = true; fire('ZONE_CHANGED_NEW_AREA')
ok(ns.modes.current() == 'dungeon', 'inside a dungeon: dungeon mode by itself')
ok(not arrow:IsShown(), 'dungeon mode: the arrow is put away')
ok(GuidelimeDataChar.mainFrameShowing == false and glToggles == 1, 'the Guidelime guide is hidden')
local s = table.concat(said, ',')
ok(s:find('questie tracker hide', 1, true), 'the Questie tracker is hidden')
ok(s:find('details show', 1, true), 'the damage meter shows')
said = {}
inside = false; fire('ZONE_CHANGED_NEW_AREA')
ok(ns.modes.current() == 'quest', 'out of the dungeon: quest mode again')
ok(arrow:IsShown() and GuidelimeDataChar.mainFrameShowing == true, 'guide and arrow back')
s = table.concat(said, ',')
ok(s:find('questie tracker show', 1, true) and s:find('details hide', 1, true), 'tracker back, meter away')
-- the chip: a click switches and holds until the next dungeon door
local chip = _G.OmaWayModeChip
ok(chip, 'the chip is under the minimap')
chip:GetScript('OnClick')(chip)
ok(ns.modes.current() == 'dungeon' and OmaWayDB.mode == 'dungeon', 'a click: dungeon mode, held')
fire('ZONE_CHANGED_NEW_AREA')
ok(ns.modes.current() == 'dungeon', 'a zone change outside does not undo the click')
chip:GetScript('OnClick')(chip)
ok(ns.modes.current() == 'quest', 'click again: quest mode')
ok(chip:GetScript('OnMouseWheel') == nil and arrow:GetScript('OnMouseWheel') == nil, 'no mouse-wheel sizing anywhere')

-- ---------- quests (sheet 115): focus > another add-on > the nearest job ----------
do
  TomTom:RemoveWaypoint(); ns.clearWaypoint()
  local function spawnsAt(x, y) return { x = x, y = y } end
  local log = {
    [100] = { name = 'Elixir of Pain', IsComplete = function() return 0 end, Finisher = { NPC = { 2216 } },
      Objectives = { { Type = 'item', Description = 'Mountain Lion Blood', Collected = 3, Needed = 10, spawnList = spawnsAt(.6, .1) } } },
    [200] = { name = 'Battle of Hillsbrad', IsComplete = function() return 0 end,
      Objectives = { { Type = 'monster', Description = 'Hillsbrad Farmer slain', Collected = 4, Needed = 6, spawnList = spawnsAt(.5, .3) } } },
  }
  local D = {}
  -- distance from the player in world yards (the fake world: map x*1000, y*1000)
  function D.GetNearestObjective(sl) local dx, dy = sl.x * 1000 - player.x, sl.y * 1000 - player.y; return { sl.x * 100, sl.y * 100 }, 85, 'Thing', math.sqrt(dx * dx + dy * dy) end
  function D.GetNearestFinisherOrStarter(fin) local dx, dy = 400 - player.x, 100 - player.y; return { 40, 10 }, 85, 'Apothecary Lydon', math.sqrt(dx * dx + dy * dy) end
  local P = { currentQuestlog = log }
  local Z = { GetUiMapIdByAreaId = function(_, z) return 1426 end }
  QuestieLoader = { ImportModule = function(_, n) return ({ DistanceUtils = D, QuestiePlayer = P, ZoneDB = Z })[n] end }
  Questie = { db = { char = {} } }
  player.x, player.y = 500, 100
  ns.quests.step()
  local w = ns.waypoint()
  ok(w and w.questId == 100, 'nothing else steers: the nearest job (the lion blood, 100 yd, not the farmers, 200 yd)')
  ok(w and w.line2 == 'Mountain Lion Blood  3/10', 'its progress on the plate: ' .. tostring(w and w.line2))
  ok(w and w.icon:find('loot', 1, true), 'a loot icon for an item to collect')
  -- the farmers become only a little closer: no flick
  player.x, player.y = 550, 180; tick(1)
  ns.quests.step()
  ok(ns.waypoint().questId == 100, 'another quest just a bit closer: the arrow keeps its target')
  -- a Guidelime step arrives: it steers
  local g = TomTom:AddWaypoint(1426, .2, .2, { title = 'Krusk', from = 'Guidelime' })
  ns.quests.step()
  ok(ns.waypoint().title == 'Krusk', 'a guide step beats the nearest job')
  -- you focus a quest in Questie: it wins, even over the guide
  Questie.db.char.TrackerFocus = 200; ns.quests.step()
  ok(ns.waypoint().questId == 200 and ns.waypoint().focus, 'your focused quest beats the guide')
  ok(ns.waypoint().icon:find('slay', 1, true), 'a kill icon for mobs to slay')
  Questie.db.char.TrackerFocus = nil; ns.quests.step()
  ok(ns.waypoint().title == 'Krusk', 'unfocus: back to the guide')
  TomTom:RemoveWaypoint(g); ns.quests.step()
  ok(ns.waypoint() and ns.waypoint().questId ~= nil, 'the guide step gone: the nearest job again')
  -- a quest done: its hand-in
  log[200] = nil; log[100].IsComplete = function() return 1 end; ns.quests.step()
  ok(ns.waypoint().title == 'Apothecary Lydon' and ns.waypoint().icon:find('complete', 1, true), 'done: the hand-in, with the ? icon')
  ok(ns.waypoint().line2 == 'Elixir of Pain · hand in', 'and says so')
  log[100] = nil; ns.quests.step()
  ok(ns.waypoint() == nil, 'an empty quest log: no arrow')
end

-- ---------- sizing: only the //// grip, 32 to 192 ----------
ok(OmaWayDB.size == 64, 'starts at 64 px')
local grip
for _, f in ipairs(frames) do if f._kind == 'Button' and f:GetScript('OnMouseDown') and f ~= chip then grip = f end end
ok(grip, 'the //// grip exists')
CURSOR = 0; grip:GetScript('OnMouseDown')(grip); CURSOR = 500; grip:GetScript('OnUpdate')(grip, .016); grip:GetScript('OnMouseUp')(grip)
ok(OmaWayDB.size == 192, 'dragged far: stops at 192')
CURSOR = 0; grip:GetScript('OnMouseDown')(grip); CURSOR = -500; grip:GetScript('OnUpdate')(grip, .016); grip:GetScript('OnMouseUp')(grip)
ok(OmaWayDB.size == 32, 'dragged back: stops at 32')
OmaWayDB.locked = true; local before = OmaWayDB.size
CURSOR = 0; grip:GetScript('OnMouseDown')(grip); ok(grip:GetScript('OnUpdate') == nil, 'locked: the grip does nothing'); OmaWayDB.locked = false

-- ---------- the real TomTom wins ----------
do
  local savedTT = TomTom; TomTom = nil
  C_AddOns.IsAddOnLoaded = function(n) return n == 'TomTom' end
  local ns2 = {}; assert(loadfile('Core.lua'))('OmaWay', ns2)
  ok(TomTom == nil and not ns2.standIn, 'with TomTom installed OmaWay leaves its slot alone')
  TomTom = savedTT; C_AddOns.IsAddOnLoaded = function() return false end
end

print = print0
print(('OmaWay smoke: %d checks, %d failed'):format(checks, fails))
if fails > 0 then os.exit(1) end
