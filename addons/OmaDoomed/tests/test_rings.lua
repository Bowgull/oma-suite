-- The rings (Rings.lua) on the fake AuraContainer: the pool, rows on plates, Haunt's target rows, Blizzard's own
-- debuff row. They lock in today's behaviour before the rebuild.
local A, B = 'Creature-0-1-0-1-100-AAAA', 'Creature-0-1-0-1-101-BBBB'

local function setup(W, rings)
  local ns, F, UI = require('load').addon({ rings = true, before = function()
    if rings then OmaDoomedDB = { rings = rings } end
  end })
  W.advance(3)            -- out of combat: the pool fills one pair per frame
  return ns, F, UI
end
local function noErrors(T) T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1])) end
local function plates(W, F, from, to)
  for i = from, to do
    F.mob('nameplate' .. i, 'Creature-0-1-0-1-' .. i .. '-P', 'Mob' .. i, 300)
    W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate' .. i)
  end
end
local function rows(UI, from, to) local n = 0; for i = from, to do if UI.rowOn('nameplate' .. i) then n = n + 1 end end; return n end
-- Haunt's two rows that follow your target: the one on the target frame, and the channel row over the mob
local function hauntRows(UI)
  local frame, chan
  for _, c in ipairs(UI.ringContainers()) do
    if c.unit == 'target' then if UI.under(c, TargetFrame) then frame = c else chan = c end end
  end
  return frame, chan
end
local function errsWith(text) local n = 0; for _, e in ipairs(OmaDoomedDB.errs or {}) do if e:find(text, 1, true) then n = n + 1 end end; return n end

return {
  ['the rings start: past the API check, every group on every container'] = function(W, T)
    local ns, F, UI = setup(W)
    for _, p in ipairs(W.printed) do T.ok(not p:find('missing the aura container APIs', 1, true), 'rings are on') end
    local ring = UI.ringContainers()[1]
    T.ok(ring, 'a pair was built')
    local keys = {}; for _, g in ipairs(ring.groups) do keys[#keys + 1] = g.key end
    T.eq(table.concat(keys, ','), 'corruption,agony,immolate,siphon,curse,channel,mine,others', 'groups in layout order')
    T.eq(#UI.mainOf(ring).groups, #ring.groups, 'ring and main have the same groups, so buttons line up')
    noErrors(T)
  end,
  ['the pool: built one pair per frame out of combat, up to 12'] = function(W, T)
    local ns, F, UI = require('load').addon({ rings = true })
    T.eq(#UI.ringContainers(), 0, 'nothing built at login itself')
    W.advance(.5); T.eq(#UI.ringContainers(), 5, 'one pair per frame')
    W.advance(3); T.eq(#UI.ringContainers(), 12, 'then stops at 12')
  end,
  ['the pool grows out of combat: 6 spare beside the plates showing, up to 40 plates and the two target rows'] = function(W, T)
    local ns, F, UI = setup(W, { where = 'split' })
    local base = #UI.ringContainers()
    plates(W, F, 1, 10); W.advance(1)
    T.eq(rows(UI, 1, 10), 10, 'every plate has a row')
    T.eq(#UI.ringContainers(), 10 + 6 + 2, '6 spare (and the two Haunt rows)')
    plates(W, F, 11, 40); W.advance(2)
    T.eq(rows(UI, 1, 40), 40, 'all 40 plates have a row')
    T.eq(#UI.ringContainers(), 42, 'the most there can be: 40 plates and the two Haunt rows')
    T.ok(base <= 14, 'it started small: ' .. base)
    noErrors(T)
  end,
  ['the pool does not grow in combat'] = function(W, T)
    local ns, F, UI = setup(W)
    W.combat = true
    plates(W, F, 1, 8); W.advance(1)
    T.eq(#UI.ringContainers(), 12, 'nothing built in combat')
    W.combat = false; W.fire('PLAYER_REGEN_ENABLED'); W.advance(1)
    T.eq(#UI.ringContainers(), 8 + 6, 'after the fight: back to 6 spare')
  end,
  ['a row goes on an enemy plate, not a friendly one, and back to the pool when the plate goes'] = function(W, T)
    local ns, F, UI = setup(W)
    F.mob('nameplate1', A, 'Kobold', 300).auras = { 172, 348 }
    F.mob('nameplate2', 'Creature-F', 'Guard', 300, { friendly = true })
    W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate2')
    W.advance(.5)
    local ring = UI.rowOn('nameplate1')
    T.ok(ring, 'a row on the enemy plate'); T.ok(UI.isVisible(ring), 'and it shows')
    T.eq(UI.rowOn('nameplate2'), nil, 'no row on a friendly plate')
    local seen = UI.showing(UI.mainOf(ring))
    T.eq(#seen.corruption, 1); T.eq(#seen.immolate, 1); T.eq(#seen.agony, 0)
    W.fire('NAME_PLATE_UNIT_REMOVED', 'nameplate1')
    T.eq(UI.rowOn('nameplate1'), nil, 'released'); T.ok(not UI.isVisible(ring), 'and hidden')
    F.mob('nameplate3', B, 'Gnoll', 300); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate3')
    T.ok(UI.rowOn('nameplate3') == ring, 'the spare pair is reused')
    T.eq(#UI.ringContainers(), 12, 'no new pair needed')
    noErrors(T)
  end,
  ['pool in combat: the 12 spares are used, nothing is built, the rest is logged'] = function(W, T)
    local ns, F, UI = setup(W)
    W.combat = true
    plates(W, F, 1, 30)
    T.eq(rows(UI, 1, 30), 12, 'the 12 spares are used')
    T.eq(#UI.ringContainers(), 12, 'no containers made in combat')
    T.ok(errsWith('no free container') > 0, 'logged')
  end,
  ['pool: a plate past the spares gets a new pair out of combat'] = function(W, T)
    local ns, F, UI = setup(W)
    plates(W, F, 1, 25)
    T.eq(rows(UI, 1, 25), 25, 'all 25 plates'); T.eq(#UI.ringContainers(), 25, 'one new pair')
    noErrors(T)
  end,
  ['Haunt: switching straight from one enemy to another makes both target rows re-read (ring and main)'] = function(W, T)
    local ns, F, UI = setup(W, { where = 'split' })
    F.mob('nameplate1', A, 'Kobold', 300).auras = { 172, 348 }
    F.mob('nameplate2', B, 'Gnoll', 300).auras = { 980 }
    W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate2')
    F.target(A); W.combat = true; W.advance(.5)
    local frame, chan = hauntRows(UI)
    T.ok(frame and chan, 'the target-frame row and the channel row exist')
    T.ok(UI.isVisible(frame), 'the frame row shows')
    T.ok(UI.under(chan, UI.plate.nameplate1), "the channel row rides the target's plate")
    T.ok(not UI.isVisible(UI.rowOn('nameplate1')), "the target's own plate row is hidden in Haunt")
    T.eq(#UI.showing(UI.mainOf(frame)).corruption, 1, "A's Corruption on the frame row")
    local frameMain, chanMain = UI.mainOf(frame), UI.mainOf(chan)
    local before = { UI.reads(frame), UI.reads(frameMain), UI.reads(chan), UI.reads(chanMain) }
    F.target(B)
    T.ok(UI.reads(frame) > before[1], 'frame row ring re-read')
    T.ok(UI.reads(frameMain) > before[2], 'frame row main re-read')
    T.ok(UI.reads(chan) > before[3], 'channel row ring re-read')
    T.ok(UI.reads(chanMain) > before[4], 'channel row main re-read')
    local seen = UI.showing(frameMain)
    T.eq(#seen.corruption, 0, "A's Corruption gone"); T.eq(#seen.agony, 1, "B's Agony shown")
    T.ok(UI.under(chan, UI.plate.nameplate2), 'the channel row moved to the new plate')
    noErrors(T)
  end,
  ["Blizzard's nameplate debuffs: off while the rings are on, put back by /omadoomed rings off"] = function(W, T)
    local ns, F, UI = setup(W)
    T.eq(C_CVar.GetCVarBitfield('nameplateEnemyNpcAuraDisplay', 2), false, 'mobs: off')
    T.eq(C_CVar.GetCVarBitfield('nameplateEnemyPlayerAuraDisplay', 2), false, 'players: off')
    T.eq(OmaDoomedDB.rings.saved.nameplateEnemyNpcAuraDisplay, '7', 'the old value kept')
    ns.ringsSlash('off')
    T.eq(W.cvars.nameplateEnemyNpcAuraDisplay, '7', 'put back'); T.eq(W.cvars.nameplateEnemyPlayerAuraDisplay, '7')
  end,
}
