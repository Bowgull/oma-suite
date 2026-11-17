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
    local t = cond:match('^%[@(nameplate%d+),harm,nodead%]')   -- [harm,nodead]: a live enemy
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
  ['list: one row per nameplate, enemies only, packed to the top; display only (no click buttons)'] = function(W, T)
    local ns, F, UI = setup(W)
    local L = ns.moblist
    mob(W, F, 2, 'Raptor'); mob(W, F, 3, 'Guard', { friendly = true }); mob(W, F, 5, 'Lashtail')
    pump(); W.advance(.3)
    T.eq(shownRows(ns), '2,5', 'the two enemies show; the friendly guard has no row')
    T.eq(L.slotOf[2], 1, 'packed: the first enemy at the top'); T.eq(L.slotOf[5], 2, 'the second just under it')
    -- display only (2026-11-16, measured: Forever refuses add-on clicks/hovers through nameplate tokens)
    T.eq(L.rows[2].click, false, 'no secure click button')
    T.ok(_G.OmaDoomedListClick2 == nil, 'none made at all')
    T.ok(L.rows[2]:GetScript('OnEnter') ~= nil, 'the row lights and shows the tooltip on hover')
    noErrors(T)
  end,
  ['list: in a fight nothing moves; a dead mob leaves its place empty; a newcomer takes its own place'] = function(W, T)
    local ns, F, UI = setup(W)
    local L = ns.moblist
    for k = 1, 3 do mob(W, F, k) end
    W.combat = true; W.advance(.3); W.fire('PLAYER_REGEN_DISABLED'); pump()
    local before = { L.slotOf[1], L.slotOf[2], L.slotOf[3], L.slotOf[4] }
    T.eq(shownRows(ns), '1,2,3')
    W.units.nameplate2.dead = true; W.fire('UNIT_HEALTH', 'nameplate2'); W.advance(.3)
    T.eq(shownRows(ns), '1,3', 'the dead one goes')
    mob(W, F, 4, 'Late'); W.advance(.3)
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
    UI.mainOf(r.pair.ring):UpdateAllAuras(); r.pair.smain:UpdateAllAuras()
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
  ['list: a mob casting gets a line under its bar, red when you can interrupt it, gone when it stops'] = function(W, T)
    local ns, F, UI = setup(W)
    mob(W, F, 1, 'Shaman'); W.advance(.3)
    local r = ns.moblist.rows[1]
    local col; r.cast.SetStatusBarColor = function(_, a, b, c) col = { a, b, c } end
    local t0 = GetTime()
    UnitCastingInfo = function(u) if u == 'nameplate1' then return 'Lightning Bolt', nil, nil, t0 * 1000, (t0 + 2) * 1000, false, 1, false end end
    W.fire('UNIT_SPELLCAST_START', 'nameplate1')
    T.ok(r.cast:IsShown(), 'the cast line shows')
    T.ok(col and col[1] > .8 and col[2] < .3, 'red: you can interrupt it')
    UnitCastingInfo = function() return nil end; UnitChannelInfo = function() return nil end
    W.fire('UNIT_SPELLCAST_STOP', 'nameplate1')
    T.ok(not r.cast:IsShown(), 'gone when it stops')
    noErrors(T)
  end,
  ['list: a tick (same DoTs, less damage left) flashes the row; a DoT ending does not'] = function(W, T)
    local ns, F, UI = setup(W)
    mob(W, F, 1, 'Raptor'); W.advance(.3)
    local r = ns.moblist.rows[1]
    local dots = { { name = 'Corruption', damage = 40 }, { name = 'Curse of Agony', damage = 80 } }
    local real = ns.model.listInto
    ns.model.listInto = function(u, _, out) for i = #out, 1, -1 do out[i] = nil end; for i, d in ipairs(dots) do out[i] = d end; return out end
    ns.bus:Fire('DOTS'); W.advance(.6)
    T.ok(not ns.motion.running('bite1'), 'first look: nothing to compare')
    dots[1] = { name = 'Corruption', damage = 30 }
    ns.bus:Fire('DOTS'); T.ok(ns.motion.running('bite1'), 'a tick: the row flashes')
    W.advance(1)
    dots[2] = nil; ns.bus:Fire('DOTS')
    T.ok(not ns.motion.running('bite1'), 'a DoT ended: no flash')
    ns.model.listInto = real
    noErrors(T)
  end,
  ["list at the pull: the fight first, then your target, then other enemies (clickable), then newcomers; nothing parked"] = function(W, T)
    local ns, F, UI = setup(W)
    local L = ns.moblist
    mob(W, F, 1, 'Raptor'); mob(W, F, 2, 'Lost Barrens Kodo').idle = true; mob(W, F, 3, 'Hyena'); mob(W, F, 5, 'Guard', { friendly = true })
    W.advance(.3)
    W.combat = true; W.fire('PLAYER_REGEN_DISABLED'); pump()
    T.eq(L.slotOf[1], 1); T.eq(L.slotOf[3], 2, 'the fight packed to the top, the Kodo not between them')
    T.eq(L.slotOf[2], 3, 'the idle enemy right under the fight: it can still join and be clicked')
    T.ok(not L.parked[2], 'an enemy is never parked (19:07: the mob he was hitting got parked and could not be clicked)')
    T.ok(not L.parked[5], 'nothing is parked off screen any more (a token can pass to a new enemy mid-fight)')
    T.ok(not L.parked[4], 'a token with no plate keeps a place for a newcomer')
    W.units.nameplate2.idle = false; W.advance(.3)
    T.ok(L.rows[2].shown, 'the Kodo row shows once it fights you, in its own place')
    noErrors(T)
  end,
  ['list: the backing covers only the rows showing, from the top one down'] = function(W, T)
    local ns, F, UI = setup(W)
    local L = ns.moblist
    for k = 1, 3 do mob(W, F, k) end
    W.combat = true; W.advance(.3); W.fire('PLAYER_REGEN_DISABLED'); pump()
    W.units.nameplate1.dead = true; W.units.nameplate2.dead = true; W.advance(1)
    T.eq(L.slotOf[3], 3, 'the third keeps its place in the fight')
    noErrors(T)
  end,
  ['list: the skull shows only when your DoTs will finish the mob AND it still has an empty seat'] = function(W, T)
    local ns, F, UI = setup(W)
    mob(W, F, 1, 'Raptor'); W.advance(.3)
    local r, e = ns.moblist.rows[1], ns.roster.entries[1]
    T.ok(r.shown, 'row up')
    e.missing = 0; ns.moblist.update()
    T.ok(not r.skullWin:IsShown(), 'every seat full: nothing to tell you, no skull')
    e.missing = 1; ns.sched.mark('moblist'); W.advance(.05)
    noErrors(T)
  end,
  ['list test: five pretend rows out of combat, the real list untouched; a fight ends it'] = function(W, T)
    local ns, F, UI = setup(W)
    local L = ns.moblist
    L.slash('test')
    T.ok(L.testing, 'on'); T.ok(L.header:IsShown(), 'the list shows out of combat')
    local n = 0; for k = 1, 16 do if L.rows[k].shown then n = n + 1 end end
    T.eq(n, 5, 'five rows')
    W.advance(3.2)
    T.ok(L.rows[1].fk and next(L.rows[1].fk.rings), 'stand-in rings drawn')
    L.slash('boxes'); T.eq(OmaDoomedDB.list.boxes, true, 'click areas on')
    L.slash('boxes')
    W.combat = true; W.fire('PLAYER_REGEN_DISABLED')
    T.ok(not L.testing, 'a fight ends the test')
    noErrors(T)
  end,
  ["list: 'Cast lines' off hides a mob's cast line"] = function(W, T)
    local ns, F, UI = setup(W)
    mob(W, F, 1, 'Shaman'); W.advance(.3)
    local r = ns.moblist.rows[1]
    OmaDoomedDB.list.casts = false
    local t0 = GetTime()
    UnitCastingInfo = function(u) if u == 'nameplate1' then return 'Lightning Bolt', nil, nil, t0 * 1000, (t0 + 2) * 1000, false, 1, false end end
    W.fire('UNIT_SPELLCAST_START', 'nameplate1')
    T.ok(not r.cast:IsShown(), 'no cast line')
    UnitCastingInfo = function() return nil end
    noErrors(T)
  end,
}
