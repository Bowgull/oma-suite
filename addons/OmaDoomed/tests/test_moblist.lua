-- The mob list (MobList.lua): rows handed out by Blizzard's secure state drivers, fixed for the whole fight,
-- clickable to target, each with your DoTs in their seats. The secure parts are faked here the way the game runs
-- them: a state driver re-evaluates its macro condition and, on a change, runs the header's _onstate snippet.
local function secure(W)
  local drivers = {}
  local create = CreateFrame
  CreateFrame = function(kind, name, parent, template)
    local f = create(kind, name, parent, template)
    local attrs = {}
    f.SetAttribute = function(self, k, v) attrs[k] = v; local h = self:GetScript('OnAttributeChanged'); if h then h(self, k, v) end end
    f.GetAttribute = function(_, k) return attrs[k] end
    f.SetFrameRef = function(_, k, o) attrs['frameref-' .. k] = o end
    f.GetFrameRef = function(_, k) return attrs['frameref-' .. k] end
    f._template = template
    return f
  end
  local function eval(cond)
    if cond == '[combat] show; hide' then return W.combat and 'show' or 'hide' end
    local tok = cond:match('^%[@(nameplate%d+),harm,nodead%]')
    local u = tok and W.units[tok]
    return (u and u.enemy and not u.dead) and 1 or 0
  end
  local function run(f, state, v)
    if state == 'visibility' then f:SetShown(v == 'show'); return end
    local code = f:GetAttribute('_onstate-' .. state); if not code then return end
    local fn = assert(loadstring(code))
    setfenv(fn, { self = f, stateid = state, newstate = v, strsub = string.sub })
    fn()
  end
  RegisterStateDriver = function(f, state, cond)
    drivers[f] = drivers[f] or {}
    local v = eval(cond); drivers[f][state] = { cond = cond, v = v }; run(f, state, v)
  end
  UnregisterStateDriver = function(f, state) if drivers[f] then drivers[f][state] = nil end end
  -- the state driver manager's pass (every frame in the game)
  return function()
    for f, ds in pairs(drivers) do for state, d in pairs(ds) do
      local v = eval(d.cond); if v ~= d.v then d.v = v; run(f, state, v) end
    end end
  end
end

local pump
local function setup(W)
  local ns, F, UI = require('load').addon({ rings = true, before = function()
    pump = secure(W)
    SetPortraitTexture = SetPortraitTexture or function() end
    UnitThreatSituation = UnitThreatSituation or function() return nil end
  end })
  W.advance(3)
  return ns, F, UI
end
local function noErrors(T) T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1])) end
local function units(ns) local t = {}; for i, r in ipairs(ns.moblist.rows) do t[i] = r:GetAttribute('unit') or '-' end; return table.concat(t, ',') end

return {
  ['list: enemies take rows in turn, friends never; rows are secure target buttons'] = function(W, T)
    local ns, F, UI = setup(W)
    T.ok(ns.moblist.rows[1], 'the list is built')
    T.eq(#ns.moblist.rows, 8, '8 rows by default')
    T.eq(ns.moblist.rows[1]._template, 'SecureUnitButtonTemplate', 'a secure unit button')
    T.eq(ns.moblist.rows[1]:GetAttribute('type1'), 'target', 'a click targets')
    F.mob('nameplate1', 'C-1', 'Raptor', 300); F.mob('nameplate2', 'C-2', 'Screecher', 300)
    F.mob('nameplate3', 'C-3', 'Guard', 300, { friendly = true }); F.mob('nameplate4', 'C-4', 'Lashtail', 300)
    pump()
    T.eq(units(ns), 'nameplate1,nameplate2,nameplate4,-,-,-,-,-', 'three enemies, in turn; the friendly guard has no row')
    T.ok(ns.moblist.rows[1]:IsShown(), 'a used row shows'); T.ok(not ns.moblist.rows[4]:IsShown(), 'a free row is hidden')
    noErrors(T)
  end,
  ['list: a mob keeps its row for the whole fight; a new one takes the first free row'] = function(W, T)
    local ns, F, UI = setup(W)
    W.combat = true
    for i = 1, 3 do F.mob('nameplate' .. i, 'C-' .. i, 'Mob' .. i, 300) end
    pump(); T.eq(units(ns), 'nameplate1,nameplate2,nameplate3,-,-,-,-,-')
    W.units.nameplate2.dead = true; pump()
    T.eq(units(ns), 'nameplate1,-,nameplate3,-,-,-,-,-', 'the dead one frees its row; the others do not move')
    T.ok(not ns.moblist.rows[2]:IsShown(), 'its row hides')
    F.mob('nameplate7', 'C-7', 'Late', 300); pump()
    T.eq(units(ns), 'nameplate1,nameplate7,nameplate3,-,-,-,-,-', 'a newcomer takes the free row')
    noErrors(T)
  end,
  ['list: each row shows your DoTs in their seats, for its own mob'] = function(W, T)
    local ns, F, UI = setup(W)
    F.mob('nameplate1', 'C-1', 'Raptor', 300).auras = { 172, 980 }
    pump(); W.advance(1)
    local r = ns.moblist.rows[1]
    T.ok(r.pair, 'the row has its rings')
    T.eq(r.pair.ring.unit, 'nameplate1', 'bound to its mob')
    local seen = UI.showing(UI.mainOf(r.pair.ring))
    T.eq(#seen.corruption, 1, 'Corruption'); T.eq(#seen.agony, 1, 'Agony'); T.eq(#seen.immolate, 0, 'Immolate blank')
    T.ok(not UI.group(r.pair.ring, 'others').enabled, "other players' DoTs are not in the list")
    T.ok(not UI.group(r.pair.ring, 'cc').enabled, 'only your DoT seats')
    noErrors(T)
  end,
  ['list: shown in fights only; unlock shows it to move, lock puts it back'] = function(W, T)
    local ns, F, UI = setup(W)
    local h = ns.moblist.header
    T.ok(not h:IsShown(), 'hidden out of combat')
    W.combat = true; pump(); T.ok(h:IsShown(), 'shown in a fight')
    W.combat = false; pump(); T.ok(not h:IsShown(), 'hidden after')
    ns.moblist.slash('unlock'); T.ok(h:IsShown(), 'unlocked: shown to move'); T.eq(OmaDoomedDB.list.unlocked, true)
    ns.moblist.slash('lock'); pump(); T.ok(not h:IsShown(), 'locked: back to fights only')
    noErrors(T)
  end,
}
