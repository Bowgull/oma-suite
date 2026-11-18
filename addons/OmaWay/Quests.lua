-- OmaWay: quests (sheet 115, 2026-11-17, Joshua: "oma also understands like where quests are right, it'll guide me to
-- the quest zones"). Where the arrow points, in order:
--   1. the quest you focused in Questie's tracker (its focus button): locked on it until it's done or unfocused
--   2. what another add-on handed in (a Guidelime step, a Questie ctrl-click)
--   3. the nearest job your quest log still needs: the nearest spawn of an unfinished objective, or the hand-in
-- Questie's own data and maths (DistanceUtils), every 3 seconds, out of combat. The plate gets the job's Questie
-- icon (kill, loot, object, hand in) and its progress ("Mountain Lion Blood 3/10"). Another quest only takes over
-- when it's clearly closer (10%), so the arrow never flicks between two.
local ADDON, ns = ...
local Q = {}; ns.quests = Q
local ICONS = 'Interface\\Addons\\Questie\\Icons\\'
local ICON_OF = { monster = 'slay', item = 'loot', object = 'object', event = 'event', killcredit = 'slay' }

local function questie()
  local L = _G.QuestieLoader
  if not (L and L.ImportModule) then return nil end
  local ok1, D = pcall(L.ImportModule, L, 'DistanceUtils')
  local ok2, P = pcall(L.ImportModule, L, 'QuestiePlayer')
  local ok3, Z = pcall(L.ImportModule, L, 'ZoneDB')
  if ok1 and ok2 and ok3 and D and P and Z and D.GetNearestObjective and Z.GetUiMapIdByAreaId then return D, P, Z end
end

local function isDone(quest)
  local ok, c = pcall(quest.IsComplete, quest)
  return ok and (c == 1 or (c ~= -1 and quest.isComplete)) or false
end

-- the best job in one quest: { x, y (0..100), map, dist, title, line2, icon, quest }
local function jobIn(id, quest, D, Z)
  local best
  local function consider(spawn, zone, name, dist, line2, icon)
    if type(spawn) ~= 'table' or not zone or type(dist) ~= 'number' then return end
    if best and dist >= best.dist then return end
    local okM, map = pcall(Z.GetUiMapIdByAreaId, Z, zone)
    if okM and map then best = { x = spawn[1], y = spawn[2], map = map, dist = dist, quest = id, title = name or quest.name or 'Quest', line2 = line2, icon = icon } end
  end
  if isDone(quest) then
    if D.GetNearestFinisherOrStarter and quest.Finisher then
      local ok, spawn, zone, name, dist = pcall(D.GetNearestFinisherOrStarter, quest.Finisher)
      if ok then consider(spawn, zone, name, dist, (quest.name or 'Quest') .. ' · hand in', ICONS .. 'complete') end
    end
    return best
  end
  for _, list in ipairs({ quest.Objectives or {}, quest.SpecialObjectives or {} }) do
    for _, o in pairs(list) do
      if type(o) == 'table' and o.spawnList and ((not o.Needed) or o.Needed ~= o.Collected) then
        local ok, spawn, zone, name, dist = pcall(D.GetNearestObjective, o.spawnList)
        local what = o.Description or name or quest.name
        local line2 = o.Needed and ('%s  %d/%d'):format(what, o.Collected or 0, o.Needed) or what
        if ok then consider(spawn, zone, name, dist, line2, ICONS .. (ICON_OF[o.Type] or 'object')) end
      end
    end
  end
  return best
end

-- the job to go to: one quest's (focus) or the nearest of all
function Q.job(onlyId)
  local D, P, Z = questie(); if not D then return nil end
  local log = P.currentQuestlog
  if type(log) ~= 'table' then return nil end
  if onlyId then local q = log[onlyId]; return type(q) == 'table' and jobIn(onlyId, q, D, Z) or nil end
  local best
  for id, quest in pairs(log) do
    if type(quest) == 'table' then local j = jobIn(id, quest, D, Z); if j and (not best or j.dist < best.dist) then best = j end end
  end
  return best
end
function Q.focus()
  local f = Questie and Questie.db and Questie.db.char and Questie.db.char.TrackerFocus
  return type(f) == 'number' and f or nil
end
local function inLog(id) local _, P = questie(); return id and P and type(P.currentQuestlog) == 'table' and P.currentQuestlog[id] ~= nil end

local function aim(j, focus)
  local a = ns.autoTarget()
  if a and a.questId == j.quest and a.x == j.x / 100 and a.y == j.y / 100 and (a.focus and true or false) == focus then
    a.line2 = j.line2; return                                   -- same spot: just the progress text
  end
  local w = ns.setAuto(j.map, j.x / 100, j.y / 100, { title = j.title, line2 = j.line2, icon = j.icon, from = focus and 'your focused quest' or 'nearest quest', focus = focus })
  if w then w.questId, w.dist = j.quest, j.dist end
end

function Q.step()
  local db = ns.db()
  if InCombatLockdown() or (ns.modes and not ns.modes.allowArrow()) then return end
  -- 1. your focused quest
  local f = Q.focus()
  if f and inLog(f) then local j = Q.job(f); if j then aim(j, true); return end end
  -- 2. another add-on steers
  if ns.external() then ns.clearAuto(); return end
  -- 3. the nearest job
  if db.nearest == false then ns.clearAuto(); return end
  local j = Q.job()
  if not j then ns.clearAuto(); return end
  local a = ns.autoTarget()
  if a and not a.focus and a.questId ~= j.quest and inLog(a.questId) then
    local now = (ns.distance and ns.distance()) or a.dist or 0
    if j.dist >= now * .9 then return end                      -- not clearly closer: keep going where you were
  end
  aim(j, false)
end

local acc = 0
local tick = CreateFrame('Frame')
tick:SetScript('OnUpdate', function(_, el) acc = acc + el; if acc >= 3 then acc = 0; pcall(Q.step) end end)
local ev = CreateFrame('Frame')
for _, e in ipairs({ 'QUEST_LOG_UPDATE', 'QUEST_ACCEPTED', 'QUEST_TURNED_IN', 'PLAYER_ENTERING_WORLD' }) do ev:RegisterEvent(e) end
ev:SetScript('OnEvent', function() acc = math.max(acc, 2.5) end)
