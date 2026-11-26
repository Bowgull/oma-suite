-- OmaRoute: a dungeon route for levelling with less questing (Joshua, 2026-11-26: "all dungeons for my level in
-- order, I'm a bit tired of questing"). Polestar already runs ONE dungeon live: its pick-up guide reads the quest log,
-- level and prerequisites and routes to the entrance; its hand-in guide routes the finished quests home; its own
-- "Learn the flight path" lines catch every flight master passed. What it has no way to do is go on to the next
-- dungeon. This keeps the order and opens the next dungeon's pick-up when one is done, so everything stays live.
--
--   Done with a dungeon = been inside it, and Polestar's hand-in plan has nothing left to hand in.
--   Outlevelled (above the dungeon's top level) = skipped, with a chat line.
--   Once per character: Polestar's Ashenvale guides are closed (Joshua's pick: the route is the only guide).
--   /omroute          where the route stands
--   /omroute next     skip the current dungeon
--   /omroute back     go back one
-- Uses only Polestar's public tables: Polestar.Dungeons (List, PickUp, HandIn, HandinPlan) and Polestar.Engine
-- (GetTabs, TabIds, CloseTab). Without Polestar it says so once and does nothing.

local ADDON = ...

-- The route, in order (Joshua's picks: to level 40, no Gnomeregan). Each entry: words the dungeon's name must hold,
-- matched against Polestar's own list so its keys are never guessed. Eastern Kingdoms first (he's in Tarren Mill at
-- 30), Kalimdor at about 35, back by zeppelin to Stranglethorn and Tirisfal at the end.
local ROUTE = {
  { 'city of dalaran' },
  { 'excavation site' },
  { 'scarlet monastery', 'graveyard' },
  { 'scarlet monastery', 'library' },
  { 'razorfen kraul' },
  { 'razorfen downs' },
  { 'drowned city' },
  { 'scarlet monastery', 'armory' },
  { 'scarlet monastery', 'cathedral' },
}
local OLD_GUIDES = { 'ashenvale' } -- tab titles closed once

local function say(msg) print('|cffe8c860OmaRoute:|r ' .. msg) end
local function PS() return _G.Polestar end
local function D() local p = PS(); return p and p.Dungeons end
local function E() local p = PS(); return p and p.Engine end

local function db()
  OmaRouteDB = OmaRouteDB or {}
  local t = OmaRouteDB
  t.i = t.i or 1
  t.ran = t.ran or {}
  t.log = t.log or {}
  return t
end
local function note(msg)
  local t = db()
  t.log[#t.log + 1] = date('%Y-%m-%d %H:%M ') .. msg
  while #t.log > 40 do table.remove(t.log, 1) end
end

-- The route as Polestar's keys: { { key, name, minLevel, maxLevel, map } } in ROUTE's order. A word list matching
-- several dungeons takes each once; one matching none is noted and left out.
local resolved
local function route()
  if resolved then return resolved end
  local d = D()
  if not (d and d.List) then return nil end
  local list = d.List()
  if #list == 0 then return nil end
  resolved = {}
  local taken = {}
  for _, words in ipairs(ROUTE) do
    local found = false
    for _, x in ipairs(list) do
      local name = (x.name or ''):lower()
      local all = true
      for _, w in ipairs(words) do if not name:find(w, 1, true) then all = false end end
      if all and not taken[x.key] then
        taken[x.key] = true; found = true
        resolved[#resolved + 1] = { key = x.key, name = x.name, minLevel = x.minLevel, maxLevel = x.maxLevel, map = x.map }
      end
    end
    if not found then note('not in Polestar: ' .. table.concat(words, ' ')) end
  end
  return resolved
end

local function tabIndex(id)
  local e = E()
  local tabs = e and e.GetTabs and e.GetTabs() or {}
  for i, t in ipairs(tabs) do if t.guideId == id then return i end end
end

local function closeOld()
  local t, e = db(), E()
  if t.closedOld or not (e and e.GetTabs and e.CloseTab) then return end
  local tabs = e.GetTabs()
  for i = #tabs, 1, -1 do
    local title = (tabs[i].title or ''):lower()
    for _, w in ipairs(OLD_GUIDES) do
      if title:find(w, 1, true) then e.CloseTab(i); note('closed tab ' .. tabs[i].title) end
    end
  end
  t.closedOld = true
end

-- The dungeon the route is on, past any he has outlevelled.
local function current()
  local r, t = route(), db()
  if not r then return nil end
  local lvl = UnitLevel('player')
  while r[t.i] and r[t.i].maxLevel and lvl > r[t.i].maxLevel do
    say(('%s skipped: level %d is past its %d.'):format(r[t.i].name, lvl, r[t.i].maxLevel))
    note('outlevelled ' .. r[t.i].key)
    t.i = t.i + 1
  end
  return r[t.i], t.i, #r
end

local function announce(d, i, n)
  say(('dungeon %d of %d: %s (%s-%s). Polestar has its quests up.'):format(i, n, d.name, tostring(d.minLevel), tostring(d.maxLevel)))
end

-- Open what the current dungeon needs now: its hand-in once it has been run and something is ready, else its pick-up.
local opening = false
local function step(reason)
  if opening or InCombatLockdown() then return end
  local d, e = D(), E()
  if not (d and e and e.TabIds) then return end
  closeOld()
  local cur, i, n = current()
  if not cur then
    if db().i > 1 and not db().finished then db().finished = true; say('route finished. Nice.') end
    return
  end
  local t = db()
  local open = e.TabIds()
  local pick, hand = 'lookup/pickup/' .. cur.key, 'lookup/handin/' .. cur.key
  if t.ran[cur.key] then
    local plan = d.HandinPlan and d.HandinPlan(cur.key)
    if plan and plan.hand and #plan.hand > 0 then
      if not open[hand] then opening = true; d.HandIn(cur.key); opening = false; note('hand-in ' .. cur.key) end
      return
    end
    -- Nothing left to hand in: this one is done. Close its tabs quietly and go on.
    for _, id in ipairs({ hand, pick }) do local ix = tabIndex(id); if ix then e.CloseTab(ix, true) end end
    note('done ' .. cur.key .. ' (' .. tostring(reason) .. ')')
    t.i = t.i + 1
    t.announced = nil
    return step('next')
  end
  if not open[pick] and not open[hand] then
    opening = true
    local ok, id, why = pcall(d.PickUp, cur.key)
    opening = false
    if ok and id then note('pick-up ' .. cur.key)
    elseif not t.announced then
      say(('%s: no quests to pick up (%s). Head straight in: the entrance is on its Polestar page.'):format(cur.name, tostring(ok and why or id)))
    end
  end
  if t.announced ~= cur.key then t.announced = cur.key; announce(cur, i, n) end
end

-- Inside the current dungeon: mark it run.
local function checkInside()
  local cur = current()
  if not cur then return end
  local _, kind, _, _, _, _, _, mapID = GetInstanceInfo()
  if kind == 'party' and cur.map and mapID == cur.map and not db().ran[cur.key] then
    db().ran[cur.key] = true
    note('inside ' .. cur.key)
  end
end

local f = CreateFrame('Frame')
f:RegisterEvent('PLAYER_ENTERING_WORLD')
f:RegisterEvent('ZONE_CHANGED_NEW_AREA')
f:RegisterEvent('QUEST_TURNED_IN')
f:RegisterEvent('PLAYER_LEVEL_UP')
f:RegisterEvent('PLAYER_REGEN_ENABLED')
local warned = false
f:SetScript('OnEvent', function(_, ev)
  if not D() then
    if not warned and ev == 'PLAYER_ENTERING_WORLD' then warned = true; C_Timer.After(10, function() if not D() then say('Polestar is not loaded, so there is no route.') end end) end
    return
  end
  checkInside()
  local wait = ev == 'PLAYER_ENTERING_WORLD' and 8 or 2 -- Polestar builds its tabs after login
  C_Timer.After(wait, function() checkInside(); step(ev) end)
end)

SLASH_OMAROUTE1 = '/omroute'
SlashCmdList.OMAROUTE = function(msg)
  msg = (msg or ''):lower()
  local t = db()
  if msg == 'next' then t.i = t.i + 1; t.announced = nil; step('skip')
  elseif msg == 'back' then t.i = math.max(1, t.i - 1); t.announced = nil; step('back')
  else
    local cur, i, n = current()
    if cur then say(('dungeon %d of %d: %s%s.'):format(i, n, cur.name, t.ran[cur.key] and ', run, handing in' or ''))
    else say('no route (Polestar not ready, or finished).') end
  end
end
