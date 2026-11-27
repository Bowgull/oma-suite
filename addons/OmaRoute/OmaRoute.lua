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
--   /omroute hearth on|off   keep the Hearthstone where it is (on by default): a "Set your home to" goal on
--                     Polestar's open step is ticked done, once, with a chat line. Nothing is bound.
-- Uses only Polestar's public tables: Polestar.Dungeons (List, PickUp, HandIn, HandinPlan) and Polestar.Engine
-- (GetTabs, TabIds, CloseTab, GetGuide, GetStepIndex, GoalDone, ToggleGoal) and its message bus (Polestar.On).
-- Without Polestar it says so once and does nothing.

local ADDON = ...

-- The route, in order (Joshua's picks: to level 40, no Gnomeregan). Each entry: words the dungeon's name must hold,
-- matched against Polestar's own list so its keys are never guessed. Eastern Kingdoms first (he's in Tarren Mill at
-- 30), Kalimdor at about 35, back by zeppelin to Stranglethorn and Tirisfal at the end.
-- Polestar keeps Scarlet Monastery as ONE dungeon (30-46, every wing), so it comes twice: Graveyard and Library early,
-- Armory and Cathedral late (its pick-up guide holds back the higher quests until their level). `as` names a visit.
local ROUTE = {
  { 'city of dalaran' },
  { 'excavation site' },
  { 'scarlet monastery', as = 'Scarlet Monastery: Graveyard and Library' },
  { 'razorfen kraul' },
  { 'razorfen downs' },
  { 'drowned city' },
  { 'scarlet monastery', as = 'Scarlet Monastery: Armory and Cathedral', last = 40 },
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
  if t.keepHearth == nil then t.keepHearth = true end
  if t.peopleOnly == nil then t.peopleOnly = true end
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
  for _, words in ipairs(ROUTE) do
    local found = false
    for _, x in ipairs(list) do
      local name = (x.name or ''):lower()
      local all = true
      for _, w in ipairs(words) do if not name:find(w, 1, true) then all = false end end
      if all and not found then
        found = true
        resolved[#resolved + 1] = { key = x.key, name = words.as or x.name, minLevel = x.minLevel, maxLevel = words.last or x.maxLevel, map = x.map }
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
      if title:find(w, 1, true) then local name = tabs[i].title; e.CloseTab(i); note('closed tab ' .. tostring(name)) end
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
  -- A new character (2026-11-26: the paladin alt at level 1) stays quiet until it is near the route's first dungeon:
  -- no tabs closed, no pick-up opened, no chat line.
  -- The route is Horde (Tarren Mill, the Barrens): an Alliance character is left alone (Joshua 2026-11-26: the paladin
  -- levels with Polestar's own "Dungeons in my route" instead).
  if UnitFactionGroup and UnitFactionGroup('player') ~= 'Horde' then return end
  local r = route()
  if not r or not r[1] or UnitLevel('player') < (r[1].minLevel or 0) - 2 then return end
  closeOld()
  local cur, i, n = current()
  if not cur then
    if db().i > 1 and not db().finished then db().finished = true; say('route finished. Nice.') end
    return
  end
  local t = db()
  local open = e.TabIds()
  local pick, hand = 'lookup/pickup/' .. cur.key, 'lookup/handin/' .. cur.key
  if t.ran[i] then
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
  if UnitFactionGroup and UnitFactionGroup('player') ~= 'Horde' then return end
  local cur, i = current()
  if not cur then return end
  local _, kind, _, _, _, _, _, mapID = GetInstanceInfo()
  if kind == 'party' and cur.map and mapID == cur.map and not db().ran[i] then
    db().ran[i] = true
    note('inside ' .. cur.key)
  end
end

-- Alliance (Joshua 2026-11-26, the paladin alt: quest + dungeons, "Run them"): Polestar's own "Dungeons in my route"
-- is built but held back by its author (ns.dungeonRoute = false, Core/Init.lua: "a test turns it on with
-- Polestar.dungeonRoute = true before login"; read at call time). Turned on here for Alliance characters only, with the
-- setting at "run"; the Set fires Polestar's own SETTING_CHANGED so its route re-reads. Horde characters keep it off,
-- so Bujuju's OmaRoute is unchanged.
local function allianceDungeons()
  local P = PS()
  if not (P and P.Set and UnitFactionGroup and UnitFactionGroup('player') == 'Alliance') then return end
  P.dungeonRoute = true
  P.Set('behavior.dungeons', 'run')
  note('Polestar dungeons in route: on, run')
end

-- Keep the Hearthstone (Joshua 2026-11-27: bound to Undercity or Orgrimmar, never "Set your home to <inn>").
-- Polestar has no setting for it, and its goal skip only takes optional goals, so a `sethome` goal on the open
-- step of the active guide is ticked with Polestar's own check-off (Engine.ToggleGoal, saved in its manual
-- ticks), once per goal per session: ToggleGoal on a ticked goal would clear it, so a goal already done (bound
-- there, or ticked) is left alone, and one the player un-ticks stays un-ticked. Nothing else is ticked, no bind
-- is made, no innkeeper is spoken to. Later `hearth` steps cope on their own: Polestar reads a Hearthstone bound
-- elsewhere as "travel there yourself" (Own.hearthElsewhere / Own.hearthPlan).
local hearthTicked = {}
local function keepHearth()
  if not db().keepHearth then return end
  local e = E()
  if not (e and e.GetGuide and e.GetStepIndex and e.GoalDone and e.ToggleGoal) then return end
  local guide, s = e.GetGuide(), e.GetStepIndex()
  local st = guide and s and guide.steps and guide.steps[s]
  if not (st and st.goals) then return end
  for g, goal in ipairs(st.goals) do
    local key = tostring(guide.id) .. ':' .. s .. ':' .. g
    if goal.t == 'sethome' and not hearthTicked[key] and not e.GoalDone(s, g) then
      hearthTicked[key] = true
      if e.ToggleGoal(s, g) then
        local inn = goal.location or goal.npcName or 'the inn'
        local bound = GetBindLocation and GetBindLocation()
        if not bound or bound == '' then bound = 'where it is' end
        say(('skipped setting your hearth to %s; it stays at %s.'):format(inn, bound))
        note('kept hearth: ticked ' .. key)
      end
    end
  end
end
-- Polestar's target list (the names beside its target button), people only (Joshua 2026-11-27: "only target quest
-- people, quest givers... I don't need it to target random trash mobs"). Polestar has no setting for it. Its list is
-- built by QoL.Buttons.TargetNames(view, raw, npcs, here, cap, info), called with info = true only for the list
-- (Buttons.lua:3643); with no kill/loot goal to name it falls back to the step's NPC goals (accept, turn in, talk,
-- train...). So for that call the step's kill/collect/loot goals are shown to it as nothing to name, the pinned
-- "Along the way" goals and the While you're here rows (mobs) are left out, and Polestar names the people.
-- The step key and the target button's own targeting (other calls) are untouched.
local MOB = { kill = true, collect = true }
local function hidePeopleless(goals)
  if type(goals) ~= 'table' then return goals end
  local out = {}
  for i, g in ipairs(goals) do
    if type(g) == 'table' and (MOB[g.t] or (g.t == 'use' and type(g.fromNpcs) == 'table')) then out[i] = { t = 'omaroute-hidden' } else out[i] = g end
  end
  return out
end
local function peopleOnlyHook()
  local P = PS(); local B = P and P.QoL and P.QoL.Buttons
  if not (B and type(B.TargetNames) == 'function') or B.omaroutePeople then return end
  local orig = B.TargetNames
  B.omaroutePeople = true
  B.TargetNames = function(view, raw, npcs, here, cap, info)
    if not (info and db().peopleOnly and type(view) == 'table') then return orig(view, raw, npcs, here, cap, info) end
    local v = {}; for k, val in pairs(view) do v[k] = val end
    v.goals = hidePeopleless(view.goals)
    local e = E(); local along = e and e.GetAlong
    if along then e.GetAlong = function() return {} end end
    local ok, a, b, c, d = pcall(orig, v, hidePeopleless(raw), true, false, cap, info)
    if along then e.GetAlong = along end
    if ok then return a, b, c, d end
    return orig(view, raw, npcs, here, cap, info)
  end
end
-- Polestar hands out STEP_CHANGED (a new open step, or another tab made active) while it evaluates: the tick
-- waits for the next frame so it never re-enters that evaluation.
local function keepHearthSoon() C_Timer.After(0, keepHearth) end
do
  local P = PS()
  if P and P.On then
    P.On('STEP_CHANGED', keepHearthSoon)
    P.On('GUIDE_CHANGED', keepHearthSoon)
  end
  peopleOnlyHook()
end

local f = CreateFrame('Frame')
f:RegisterEvent('PLAYER_LOGIN')
f:RegisterEvent('PLAYER_ENTERING_WORLD')
f:RegisterEvent('ZONE_CHANGED_NEW_AREA')
f:RegisterEvent('QUEST_TURNED_IN')
f:RegisterEvent('PLAYER_LEVEL_UP')
f:RegisterEvent('PLAYER_REGEN_ENABLED')
local warned = false
f:SetScript('OnEvent', function(_, ev)
  if ev == 'PLAYER_LOGIN' then allianceDungeons(); return end
  if not D() then
    if not warned and ev == 'PLAYER_ENTERING_WORLD' then warned = true; C_Timer.After(10, function() if not D() then say('Polestar is not loaded, so there is no route.') end end) end
    return
  end
  checkInside()
  local wait = ev == 'PLAYER_ENTERING_WORLD' and 8 or 2 -- Polestar builds its tabs after login
  C_Timer.After(wait, function() checkInside(); step(ev); keepHearth(); peopleOnlyHook() end)
end)

-- "Add to Polestar" from the phone (sheet omashu/remote/27, 2026-11-27): /omq <questId> asks Polestar to build its
-- own guide to that quest in a new tab (Polestar.Lookup.Guide, Lookup/Guide.lua: quests needed first, the giver,
-- accept, objectives, hand in). The main route stays as it is. Says why when Polestar can't.
local OMQ_WHY = { tabs = 'Polestar has too many tabs open: close one and tap again.', disabled = 'Polestar\'s Lookup is off.',
  missing = 'Polestar\'s quest data isn\'t loaded.', combat = 'in a fight: tap again after it.', noguide = 'Polestar has no route to that quest.' }
SLASH_OMQ1 = '/omq'
SlashCmdList.OMQ = function(msg)
  local id = tonumber((msg or ''):match('^%s*(%d+)%s*$'))
  local P = PS(); local L = P and P.Lookup
  if not id then say('/omq needs a quest number.'); return end
  if not (L and L.Guide) then say('Polestar isn\'t ready.'); return end
  if InCombatLockdown() then say(OMQ_WHY.combat); return end
  local ok, gid, why = pcall(L.Guide, 'quest', id)
  if ok and gid then
    local name = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    say(('added to Polestar: %s (new tab).'):format(name or ('quest ' .. id)))
  else
    say(OMQ_WHY[ok and why or ''] or ('Polestar couldn\'t add quest ' .. id .. (ok and why and (': ' .. tostring(why)) or '') .. '.'))
  end
end

SLASH_OMAROUTE1 = '/omroute'
SlashCmdList.OMAROUTE = function(msg)
  msg = (msg or ''):lower()
  local t = db()
  if msg == 'next' then
    local cur, e = current(), E()
    if cur and e and e.CloseTab then
      for _, id in ipairs({ 'lookup/handin/' .. cur.key, 'lookup/pickup/' .. cur.key }) do local ix = tabIndex(id); if ix then e.CloseTab(ix, true) end end
    end
    note('skipped ' .. (cur and cur.key or '?')); t.i = t.i + 1; t.announced = nil; step('skip')
  elseif msg == 'hearth on' or msg == 'hearth off' then
    t.keepHearth = msg == 'hearth on'
    say(t.keepHearth and 'keeping your Hearthstone where it is: "Set your home" steps are ticked for you.' or 'Polestar\'s "Set your home" steps are left to you.')
    if t.keepHearth then keepHearth() end
  elseif msg == 'hearth' then
    say('keep hearth is ' .. (t.keepHearth and 'on' or 'off') .. ' (/omroute hearth on|off).')
  elseif msg == 'targets people' or msg == 'targets all' then
    t.peopleOnly = msg == 'targets people'
    say(t.peopleOnly and "Polestar's target list: people you need only (quest givers, hand-ins, talk)." or "Polestar's target list: everything, mobs too.")
  elseif msg == 'back' then t.i = math.max(1, t.i - 1); t.announced = nil; step('back')
  else
    local cur, i, n = current()
    if cur then say(('dungeon %d of %d: %s%s.'):format(i, n, cur.name, t.ran[i] and ', run, handing in' or ''))
    else say('no route (Polestar not ready, or finished).') end
  end
end
