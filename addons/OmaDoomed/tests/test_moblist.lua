-- The mob list (MobList.lua), built the way Warlock HUD and Warlock All-in-One do it on Forever: a row per nameplate
-- token, shown by plain code, packed at a fight's start and frozen during it; an invisible secure button per row for
-- the click, shown by Blizzard's state driver. The secure parts are faked here the way the game runs them.
local function secure(W)
  local drivers = {}
  local create = CreateFrame
  CreateFrame = function(kind, name, parent, template)
    local f = create(kind, name, parent, template)
    local attrs = {}
    f.SetAttribute = function(self, k, v) attrs[k] = v end
    f.GetAttribute = function(_, k) return attrs[k] end
    f._template = template
    return f
  end
  local function eval(cond)
    if cond == '[combat] show; hide' then return W.combat and 'show' or 'hide' end
    local t = cond:match('^%[@(nameplate%d+),exists')
    local u = t and W.units[t]
    return (u and u.enemy and not u.dead) and 'show' or 'hide'
  end
  RegisterStateDriver = function(f, state, cond)
    drivers[f] = drivers[f] or {}
    local v = eval(cond); drivers[f][state] = { cond = cond, v = v }
    if state == 'visibility' then f:SetShown(v == 'show') end
  end
  UnregisterStateDriver = function(f, state) if drivers[f] then drivers[f][state] = nil end end
  return function()   -- the state driver manager's pass (every frame in the game)
    for f, ds in pairs(drivers) do for state, d in pairs(ds) do
      local v = eval(d.cond); if v ~= d.v then d.v = v; if state == 'visibility' then f:SetShown(v == 'show') end end
    end end
  end
end

local pump
local function setup(W)
  local ns, F, UI = require('load').addon({ rings = true, before = function()
    pump = secure(W)
    SetPortraitTexture = SetPortraitTexture or function() end
    -- the threat list: a mob in your fight (not friendly, not dead, not .idle) has you on it
    UnitThreatSituation = function(who, u) local x = W.units[u]; if who == 'player' and x and x.enemy and not x.dead and not x.idle then return 0 end end
  end })
  W.advance(3)
  return ns, F, UI
end
local function noErrors(T) T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1])) end
local function mob(W, F, k, name, o) local u = F.mob('nameplate' .. k, 'C-' .. k, name or ('Mob' .. k), 300, o); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate' .. k); return u end
local function shownRows(ns) local t = {}; for k = 1, 16 do if ns.moblist.rows[k].shown then t[#t + 1] = k end end; return table.concat(t, ',') end

return {
  ['list: one row per nameplate, enemies only, packed to the top; clicks are secure target buttons'] = function(W, T)
    local ns, F, UI = setup(W)
    local L = ns.moblist
    mob(W, F, 2, 'Raptor'); mob(W, F, 3, 'Guard', { friendly = true }); mob(W, F, 5, 'Lashtail')
    pump()
    T.eq(shownRows(ns), '2,5', 'the two enemies show; the friendly guard has no row')
    T.eq(L.slotOf[2], 1, 'packed: the first enemy at the top'); T.eq(L.slotOf[5], 2, 'the second just under it')
    local b = L.rows[2].click
    T.eq(b._template, 'SecureUnitButtonTemplate', 'a secure unit button: hovering it makes it your mouseover')
    T.eq(b:GetAttribute('*type1'), 'macro', 'a click runs the macro'); T.eq(b:GetAttribute('*macrotext1'), '/target [@mouseover,harm,nodead]', 'which targets the hovered mob'); T.eq(b:GetAttribute('unit'), 'nameplate2', 'its own token, for good')
    T.ok(b._anchor ~= L.rows[2], 'placed by screen position, never anchored to its row (that made the row secure: ADDON_ACTION_BLOCKED)')
    T.ok(b._anchor ~= nil, 'and it IS placed, though the list is hidden out of combat (2026-11-16: clicking stopped working)')
    W.combat = true; pump()
    T.ok(b:IsShown() or b.shown, "an enemy's button shows in a fight")
    T.ok(not (L.rows[3].click.shown), "a friendly plate's button stays hidden")
    noErrors(T)
  end,
  ['list: in a fight nothing moves; a dead mob leaves its place empty; a newcomer takes its own place'] = function(W, T)
    local ns, F, UI = setup(W)
    local L = ns.moblist
    for k = 1, 3 do mob(W, F, k) end
    W.combat = true; W.fire('PLAYER_REGEN_DISABLED'); pump()
    local before = { L.slotOf[1], L.slotOf[2], L.slotOf[3], L.slotOf[4] }
    T.eq(shownRows(ns), '1,2,3')
    W.units.nameplate2.dead = true; W.fire('UNIT_HEALTH', 'nameplate2')
    T.eq(shownRows(ns), '1,3', 'the dead one goes')
    mob(W, F, 4, 'Late')
    T.eq(shownRows(ns), '1,3,4', 'a newcomer shows')
    T.eq(L.slotOf[1], before[1]); T.eq(L.slotOf[3], before[3]); T.eq(L.slotOf[4], before[4], 'in the place its token already had: nothing moved')
    W.combat = false; W.fire('PLAYER_REGEN_ENABLED')
    T.eq(L.slotOf[4], 3, 'after the fight the list packs again')
    noErrors(T)
  end,
  ['list: each row shows your DoTs in their seats, bound once to its own nameplate'] = function(W, T)
    local ns, F, UI = setup(W)
    W.advance(1)
    mob(W, F, 1, 'Raptor').auras = { 172, 980 }
    W.fire('UNIT_AURA', 'nameplate1'); W.advance(.5)
    local r = ns.moblist.rows[1]
    T.ok(r.pair, 'the row has its rings')
    T.eq(r.pair.ring.unit, 'nameplate1', 'bound to its own token')
    UI.mainOf(r.pair.ring):UpdateAllAuras()
    local seen = UI.showing(UI.mainOf(r.pair.ring))
    T.eq(#seen.corruption, 1, 'Corruption'); T.eq(#seen.agony, 1, 'Agony'); T.eq(#seen.immolate, 0, 'Immolate blank')
    T.ok(not UI.group(r.pair.ring, 'others').enabled, "other players' DoTs are not in the list")
    noErrors(T)
  end,
  ['list: shown in fights only (plain code); unlock shows it to move, lock puts it back'] = function(W, T)
    local ns, F, UI = setup(W)
    local h = ns.moblist.header
    T.ok(not h:IsShown(), 'hidden out of combat')
    W.combat = true; W.fire('PLAYER_REGEN_DISABLED'); T.ok(h:IsShown(), 'shown in a fight')
    W.combat = false; W.fire('PLAYER_REGEN_ENABLED'); T.ok(not h:IsShown(), 'hidden after')
    ns.moblist.slash('unlock'); T.ok(h:IsShown(), 'unlocked: shown to move'); T.eq(OmaDoomedDB.list.unlocked, true)
    ns.moblist.slash('lock'); T.ok(not h:IsShown(), 'locked: back to fights only')
    noErrors(T)
  end,
  ["list: the skull rides a bar from 0 to the mob's health, filled with your DoTs' damage"] = function(W, T)
    local ns, F, UI = setup(W)
    mob(W, F, 1, 'Raptor')
    ns.moblist.rows[1].unit = 'nameplate1'
    local r = ns.moblist.rows[1]
    T.ok(r.skullBar and r.skull, 'the skull and its bar are there')
    T.ok(r.skullWin, 'inside a small window over the portrait')
    noErrors(T)
  end,
  ["list: only mobs in your fight (his Barrens screenshots): a Kodo standing by stays off, a hyena that dies leaves"] = function(W, T)
    local ns, F, UI = setup(W)
    W.combat = true; W.fire('PLAYER_REGEN_DISABLED')
    mob(W, F, 1, 'Lost Barrens Kodo').idle = true      -- attackable, but not fighting you
    mob(W, F, 2, 'Hecklefang Hyena')                     -- pulled
    mob(W, F, 3, 'Hecklefang Hyena')                     -- joins mid-fight
    W.advance(.3)
    T.eq(shownRows(ns), '2,3', 'the two hyenas, not the Kodo')
    W.units.nameplate2.dead = true; W.advance(.3)
    T.eq(shownRows(ns), '3', 'the dead hyena leaves (it drops off the threat list)')
    noErrors(T)
  end,
}
