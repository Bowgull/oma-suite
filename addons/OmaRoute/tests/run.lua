-- Offline tests for OmaRoute:  luajit tests/run.lua   (from the OmaRoute folder)
-- A fake WoW and a fake Polestar: a dungeon list, tabs, pick-up and hand-in guides that open tabs.
local W
local function world(level)
  W = { faction = 'Horde', level = level, tabs = {}, said = {}, inst = { nil, 'none' }, hand = {}, events = nil, timers = {} }
  _G.OmaRouteDB = nil
  _G.UnitLevel = function() return W.level end
  _G.UnitFactionGroup = function() return W.faction end
  _G.InCombatLockdown = function() return false end
  _G.date = os.date
  _G.print = function(m) W.said[#W.said + 1] = m end
  _G.C_Timer = { After = function(_, fn) W.timers[#W.timers + 1] = fn end }
  _G.GetInstanceInfo = function() return 'x', W.inst[2], 0, '', 5, 0, false, W.inst[1] end
  _G.CreateFrame = function() local fr = {}; function fr:RegisterEvent() end; function fr:SetScript(_, fn) W.events = fn end; return fr end
  _G.SlashCmdList = {}
  local list = {
    { key = 'excavation-site-wetlands', name = 'Excavation Site: Wetlands', minLevel = 26, maxLevel = 33, map = 2998 },
    { key = 'city-of-dalaran', name = 'City of Dalaran', minLevel = 28, maxLevel = 35, map = 2959 },
    { key = 'scarlet-monastery', name = 'Scarlet Monastery', minLevel = 30, maxLevel = 46, map = 189 },
    { key = 'razorfen-downs', name = 'Razorfen Downs', minLevel = 37, maxLevel = 46, map = 129 },
    { key = 'the-drowned-city', name = 'The Drowned City', minLevel = 35, maxLevel = 42, map = 3001 },
    { key = 'razorfen-kraul', name = 'Razorfen Kraul', minLevel = 29, maxLevel = 38, map = 47 },
    { key = 'gnomeregan', name = 'Gnomeregan', minLevel = 29, maxLevel = 38, map = 90 },
  }
  local function open(id, title) W.tabs[#W.tabs + 1] = { guideId = id, title = title }; return id end
  _G.Polestar = {
    settings = {},
    Set = function(k, v) _G.Polestar.settings[k] = v end,
    Dungeons = {
      List = function() return list end,
      PickUp = function(k) return open('lookup/pickup/' .. k, k .. ': pick up') end,
      HandIn = function(k) return open('lookup/handin/' .. k, k .. ': hand in') end,
      HandinPlan = function(k) return { hand = W.hand[k] or {} } end,
    },
    Engine = {
      GetTabs = function() return W.tabs end,
      TabIds = function() local o = {}; for _, t in ipairs(W.tabs) do o[t.guideId] = true end; return o end,
      CloseTab = function(i) table.remove(W.tabs, i) end,
    },
  }
  dofile('OmaRoute.lua')
end
local function fire(ev) W.events(nil, ev); local t = W.timers; W.timers = {}; for _, fn in ipairs(t) do fn() end end
local function has(id) for _, t in ipairs(W.tabs) do if t.guideId == id then return true end end end
local function eq(a, b, m) if a ~= b then error((m or 'eq') .. ': expected ' .. tostring(b) .. ', got ' .. tostring(a), 2) end end
local function ok(v, m) if not v then error(m or 'expected true', 2) end end

local tests = {}
tests['Alliance: Polestar dungeons in route switched on at Run them; Horde left off'] = function()
  world(1); W.faction = 'Alliance'; fire('PLAYER_LOGIN')
  eq(Polestar.dungeonRoute, true); eq(Polestar.settings['behavior.dungeons'], 'run')
  world(30); fire('PLAYER_LOGIN')
  eq(Polestar.dungeonRoute, nil, 'Horde: untouched'); eq(Polestar.settings['behavior.dungeons'], nil)
end

tests['an Alliance character is never touched, at any level'] = function()
  world(30); W.faction = 'Alliance'
  W.tabs = { { guideId = 'a/redridge', title = 'Redridge Mountains' }, { guideId = 'h/ash27', title = 'Ashenvale & Thousand Needles' } }
  fire('PLAYER_ENTERING_WORLD'); W.level = 40; fire('PLAYER_LEVEL_UP')
  eq(#W.tabs, 2, 'tabs untouched'); eq(#W.said, 0, 'silent')
end

tests['a level 1 alt is left alone: no tabs closed, no pick-up, no chat line'] = function()
  world(1)
  W.tabs = { { guideId = 'a/elwynn', title = 'Elwynn Forest' }, { guideId = 'h/ash27', title = 'Ashenvale & Thousand Needles' } }
  fire('PLAYER_ENTERING_WORLD'); fire('PLAYER_LEVEL_UP')
  eq(#W.tabs, 2, 'tabs untouched'); eq(#W.said, 0, 'silent')
  W.level = 26; fire('PLAYER_LEVEL_UP')
  ok(has('lookup/pickup/city-of-dalaran'), 'starts two levels before Dalaran (28)')
end

tests['Scarlet Monastery comes twice, each visit run and handed in on its own'] = function()
  world(30)
  fire('PLAYER_ENTERING_WORLD')
  local function finish(map, key)
    W.inst = { map, 'party' }; W.hand[key] = { 1 }; fire('ZONE_CHANGED_NEW_AREA')
    W.inst = { nil, 'none' }; fire('ZONE_CHANGED_NEW_AREA'); W.hand[key] = {}; fire('QUEST_TURNED_IN')
  end
  finish(2959, 'city-of-dalaran'); finish(2998, 'excavation-site-wetlands')
  ok(has('lookup/pickup/scarlet-monastery'), 'first SM visit'); eq(OmaRouteDB.i, 3)
  finish(189, 'scarlet-monastery')
  ok(has('lookup/pickup/razorfen-kraul'), 'then Razorfen Kraul'); eq(OmaRouteDB.i, 4)
  SlashCmdList.OMAROUTE('next'); SlashCmdList.OMAROUTE('next'); SlashCmdList.OMAROUTE('next')
  ok(has('lookup/pickup/scarlet-monastery'), 'second SM visit opens its pick-up again'); eq(OmaRouteDB.i, 7)
  ok(not OmaRouteDB.ran[7], 'second visit not marked run by the first')
end

tests['login: Ashenvale tabs close, Dalaran pick-up opens first (route order, not Polestar list order)'] = function()
  world(30)
  W.tabs = { { guideId = 'h/ash27', title = 'Ashenvale & Thousand Needles' }, { guideId = 'h/ash22', title = 'Ashenvale & Silverpine Forest' }, { guideId = 'x', title = 'Hillsbrad Foothills' } }
  fire('PLAYER_ENTERING_WORLD')
  ok(not has('h/ash27') and not has('h/ash22'), 'Ashenvale closed'); ok(has('x'), 'other tab kept')
  ok(has('lookup/pickup/city-of-dalaran'), 'Dalaran pick-up open')
  ok(not has('lookup/pickup/gnomeregan'), 'Gnomeregan never in the route')
end
tests['run it, hand in, then the next dungeon opens; done tabs close'] = function()
  world(30)
  fire('PLAYER_ENTERING_WORLD')
  W.inst = { 2959, 'party' }; W.hand['city-of-dalaran'] = { 1, 2 }; fire('ZONE_CHANGED_NEW_AREA')
  W.inst = { nil, 'none' }; fire('ZONE_CHANGED_NEW_AREA')
  ok(has('lookup/handin/city-of-dalaran'), 'hand-in opens after the run')
  W.hand['city-of-dalaran'] = {}; fire('QUEST_TURNED_IN')
  ok(not has('lookup/handin/city-of-dalaran') and not has('lookup/pickup/city-of-dalaran'), 'Dalaran tabs closed')
  ok(has('lookup/pickup/excavation-site-wetlands'), 'Excavation next')
  eq(OmaRouteDB.i, 2)
end
tests['outlevelled dungeons are skipped with a line'] = function()
  world(34)
  fire('PLAYER_ENTERING_WORLD')
  ok(has('lookup/pickup/city-of-dalaran'), '34 still fits Dalaran (to 35)')
  W.level = 36; fire('PLAYER_LEVEL_UP')
  ok(has('lookup/pickup/scarlet-monastery'), 'Excavation (to 33) and Dalaran (to 35) skipped at 36: Scarlet Monastery')
  local skipped = 0; for _, m in ipairs(W.said) do if m:find('skipped') then skipped = skipped + 1 end end
  eq(skipped, 2)
end
tests['/omroute next skips; a missing dungeon is noted, not guessed'] = function()
  world(30)
  fire('PLAYER_ENTERING_WORLD')
  SlashCmdList.OMAROUTE('next')
  ok(has('lookup/pickup/excavation-site-wetlands'))
  W.tabs = {}; W.hand = {}
  _G.Polestar.Dungeons.List = function() return { { key = 'city-of-dalaran', name = 'City of Dalaran', minLevel = 28, maxLevel = 35, map = 2959 } } end
  world(30) -- reload with a list missing most of the route
  _G.Polestar.Dungeons.List = function() return { { key = 'city-of-dalaran', name = 'City of Dalaran', minLevel = 28, maxLevel = 35, map = 2959 } } end
  fire('PLAYER_ENTERING_WORLD')
  local missing = false; for _, l in ipairs(OmaRouteDB.log) do if l:find('not in Polestar: drowned city') then missing = true end end
  ok(missing, 'Drowned City (not in that list) noted')
end

local pass, fail = 0, 0
local names = {}; for n in pairs(tests) do names[#names + 1] = n end; table.sort(names)
for _, n in ipairs(names) do
  local good, err = pcall(tests[n])
  if good then pass = pass + 1; io.write('ok   ' .. n .. '\n') else fail = fail + 1; io.write('FAIL ' .. n .. '\n     ' .. tostring(err) .. "\n") end
end
io.write(pass .. ' passed, ' .. fail .. ' failed\n')
os.exit(fail == 0 and 0 or 1)
