-- OmaWay: the nearest quest (2026-11-17, Joshua: "oma also understands like where quests are right, it'll guide me
-- to the quest zones"). When nothing else is steering the arrow (no Guidelime step, nothing you picked on the map),
-- it points at the nearest thing your quest log still needs, as Questie knows it: the nearest spawn of an objective
-- you haven't finished, or the quest's hand-in once it's done. Questie's own maths (DistanceUtils), every 3 seconds,
-- out of combat; it only changes target when another is clearly closer (10%), so it doesn't flick between two.
local ADDON, ns = ...
local Q = {}; ns.quests = Q
local FROM = 'nearest quest'

local function questie()
  local L = _G.QuestieLoader
  if not (L and L.ImportModule) then return nil end
  local ok1, D = pcall(L.ImportModule, L, 'DistanceUtils')
  local ok2, P = pcall(L.ImportModule, L, 'QuestiePlayer')
  local ok3, Z = pcall(L.ImportModule, L, 'ZoneDB')
  if ok1 and ok2 and ok3 and D and P and Z and D.GetNearestSpawnForQuest and Z.GetUiMapIdByAreaId then return D, P, Z end
end

-- the nearest thing to go to: spawn {x, y} in 0..100, its uiMapID, a title, the distance
function Q.nearest()
  local D, P, Z = questie(); if not D then return nil end
  local log = P.currentQuestlog
  if type(log) ~= 'table' then return nil end
  local best
  for id, quest in pairs(log) do
    if type(quest) == 'table' then
      local ok, spawn, zone, name, dist = pcall(D.GetNearestSpawnForQuest, quest)
      if ok and type(spawn) == 'table' and zone and type(dist) == 'number' and (not best or dist < best.dist) then
        local okM, map = pcall(Z.GetUiMapIdByAreaId, Z, zone)
        if okM and map then
          best = { x = spawn[1], y = spawn[2], map = map, dist = dist, quest = id,
            title = (name and quest.name and name ~= quest.name) and (name .. ' · ' .. quest.name) or (name or quest.name or 'Quest') }
        end
      end
    end
  end
  return best
end

local cur          -- the target we set: { quest, x, y, dist }
function Q.step()
  local db = ns.db()
  if db.nearest == false or InCombatLockdown() or (ns.modes and not ns.modes.allowArrow()) then return end
  local w = ns.waypoint()
  if w and w.from ~= FROM then cur = nil; return end           -- something else steers: leave it
  local n = Q.nearest()
  if not n then if w then ns.clearWaypoint() end; cur = nil; return end
  if w and cur and cur.quest == n.quest and cur.x == n.x and cur.y == n.y then return end   -- already there
  -- another quest takes over only when it's clearly closer (10%) or ours is gone; the same quest's nearer spawn
  -- (you killed the last one here) is followed at once
  if w and cur and n.quest ~= cur.quest and Q.stillNeeded(cur) then
    local now = (ns.distance and ns.distance()) or cur.dist
    if n.dist >= now * .9 then return end
  end
  cur = n
  ns.setWaypoint(n.map, n.x / 100, n.y / 100, { title = n.title, from = FROM })
end
-- is the quest we point at still in the log?
function Q.stillNeeded(c) local _, P = questie(); return c and P and type(P.currentQuestlog) == 'table' and P.currentQuestlog[c.quest] ~= nil end

local acc = 0
local tick = CreateFrame('Frame')
tick:SetScript('OnUpdate', function(_, el) acc = acc + el; if acc >= 3 then acc = 0; pcall(Q.step) end end)
-- a quest changes: look again soon
local ev = CreateFrame('Frame')
for _, e in ipairs({ 'QUEST_LOG_UPDATE', 'QUEST_ACCEPTED', 'QUEST_TURNED_IN', 'PLAYER_ENTERING_WORLD' }) do ev:RegisterEvent(e) end
ev:SetScript('OnEvent', function() acc = math.max(acc, 2.5) end)
