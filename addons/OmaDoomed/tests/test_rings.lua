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

-- sheet 51 B, and the 'Ring look' setting (Rich by default; Flat is sheet 52 F)
local function ringLook(look)
  return function(W, T)
    local function numSize(UI, b)
      for _, e in ipairs(UI.fontSizes) do
        local o = e[1]
        for _ = 1, 4 do o = type(o) == 'table' and rawget(o, '_parent') or nil; if o == b then return e[2] end end
      end
    end
    local function polish(UI)   -- how many shadow / gloss / bezel / number-spot textures were set up
      local n = 0
      for _, t in ipairs(UI.textures) do
        t = tostring(t)
        if t:find('ring_shadow') or t:find('ring_light') or t:find('bezel') or t:find('numspot') then n = n + 1 end
      end
      return n
    end
    do
      local U0 = require('ui'); for k = #U0.textures, 1, -1 do U0.textures[k] = nil end; for k = #U0.fontSizes, 1, -1 do U0.fontSizes[k] = nil end
      local ns, F, UI = setup(W, { where = 'frame', look = look ~= 'rich' and look or nil })
      F.mob('nameplate1', A, 'Kobold', 300).auras = { 172 }
      W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); F.target(A); W.advance(.5)
      local R = ns.rings
      local frame = hauntRows(UI)
      T.ok(frame, look .. ': the frame row exists')
      T.near(40 * R.FRAME_SCALE, 28, .01, '28 px ring'); T.near(R.FRAME_SPACE * R.FRAME_SCALE, 4, .05, '4 px between rings')
      T.ok(5 * 28 + 4 * R.FRAME_SPACE * R.FRAME_SCALE <= 157, 'five fit under the health bar')
      local fm = UI.mainOf(frame)
      local plateMain
      for _, c in ipairs(UI.ringContainers()) do if c ~= frame then plateMain = UI.mainOf(c); break end end
      local fnum, pnum = numSize(UI, UI.group(fm, 'corruption').buttons[1]), numSize(UI, UI.group(plateMain, 'corruption').buttons[1])
      if look == 'rich' then
        T.eq(fnum, math.floor(40 * .44 + .5), 'rich: frame row number 44% (sheet 51 B)'); T.eq(pnum, math.floor(40 * .46 + .5), 'rich: over the mobs 46% (sheet 54: 58% filled the icon)')
        T.ok(polish(UI) > 0, 'rich: the lit ring, bezel and number spot are there')
        local edged = false; for _, t in ipairs(UI.textures) do if tostring(t):find('ring_edge') then edged = true end end
        T.ok(edged, 'rich: the colour band has its black edge (sheet 55)')
      else
        T.eq(fnum, math.floor(40 * .46 + .5), 'flat: 46% on the frame row'); T.eq(pnum, math.floor(40 * .46 + .5), 'flat: 46% over the mobs')
        T.eq(polish(UI), 0, 'flat: no shadow, gloss, bezel or number spot')
        for _, t in ipairs(UI.textures) do T.ok(not tostring(t):find('ring_edge'), 'flat: no extra edge art') end
      end
      T.eq(numSize(UI, UI.group(fm, 'curse').buttons[1]), math.floor(40 * .36 + .5), look .. ': the curse number is 36% in the frame row too (sheet 54)')
      T.eq(numSize(UI, UI.group(plateMain, 'curse').buttons[1]), math.floor(40 * .36 + .5), look .. ': and over the mobs')
      T.near(R.GAP * 1.18, 7.7, .2, 'the row sits 6 px clear of the name on a 1.18 px/unit screen (ring art has ~1.5 px of its own margin)')
      noErrors(T)
    end
  end
end

return {
  ['the rings start: past the API check, every group on every container'] = function(W, T)
    local ns, F, UI = setup(W)
    for _, p in ipairs(W.printed) do T.ok(not p:find('missing the aura container APIs', 1, true), 'rings are on') end
    local ring = UI.ringContainers()[1]
    T.ok(ring, 'a pair was built')
    local keys = {}; for _, g in ipairs(ring.groups) do keys[#keys + 1] = g.key end
    T.eq(table.concat(keys, ','), 'cc,corruption,agony,immolate,siphon,curse,channel,mine,others', 'groups in layout order')
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
  -- 2026-11-13, Joshua: "in haunt mode this is always on": your curse stays over the mob like your channel
  ['Haunt: your curse and your channel stay over the mob; the frame row has your DoTs only'] = function(W, T)
    local ns, F, UI = setup(W, { where = 'split' })
    F.mob('nameplate1', A, 'Kobold', 300).auras = { 172, 702, 689 }   -- Corruption, Curse of Weakness, Drain Life
    W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1')
    F.target(A); W.combat = true; W.advance(.5)
    local frame, chan = hauntRows(UI)
    T.ok(frame and chan, 'both target rows exist')
    T.ok(UI.isVisible(chan) and UI.under(chan, UI.plate.nameplate1), "the over-the-mob row rides the target's plate")
    local over, onFrame = UI.showing(UI.mainOf(chan)), UI.showing(UI.mainOf(frame))
    T.eq(#over.curse, 1, 'Curse of Weakness over the mob'); T.eq(#over.channel, 1, 'Drain Life over the mob')
    T.eq(#(over.corruption or {}), 0, 'no DoT over the mob in Haunt')
    T.eq(#onFrame.curse, 0, 'no curse on the frame row'); T.eq(#onFrame.channel, 0, 'no channel on the frame row')
    T.eq(ns.rings.OVERHEAD.cc, true, 'crowd control stays over the mob in Haunt too')
    T.eq(UI.group(UI.mainOf(frame), 'cc').enabled, false, 'no crowd-control ring on the frame row in Haunt'); T.eq(UI.group(UI.mainOf(chan), 'cc').enabled, true, 'it is on the over-the-mob row')
    T.eq(#onFrame.corruption, 1, 'Corruption on the frame row')
    noErrors(T)
  end,
  -- 2026-11-13, Joshua: "the curses text for the timer is too big" (a curse reads "2m")
  ['curse ring: its timer number is smaller than a DoT ring\'s'] = function(W, T)
    local ns, F, UI = setup(W)
    -- the number of a button: the font string set up under it (button > cooldown > top frame > font string)
    local function numSize(b)
      for _, e in ipairs(UI.fontSizes) do
        local o = e[1]
        for _ = 1, 4 do o = type(o) == 'table' and rawget(o, '_parent') or nil; if o == b then return e[2] end end
      end
    end
    local main = UI.mainOf(UI.ringContainers()[1])
    local dot = numSize(UI.group(main, 'corruption').buttons[1])
    local curse = numSize(UI.group(main, 'curse').buttons[1])
    T.ok(dot and curse, 'both numbers found')
    T.ok(curse < dot, ('curse %s smaller than DoT %s'):format(tostring(curse), tostring(dot)))
    T.eq(dot, math.floor(40 * .46 + .5), 'DoT number 46% of the ring (sheet 54)'); T.eq(curse, math.floor(40 * .36 + .5), 'curse number 36% (sheet 54)')
    T.eq(numSize(UI.group(main, 'channel').buttons[1]), dot, 'channels keep the big number')
    noErrors(T)
  end,
  -- sheet 51 B (approved "B"): the target-frame row is 28 px with a smaller number
  ['Ring look: Rich by default (lit ring, bezel, bold number); frame row 28 px, 4 px apart'] = ringLook('rich'),
  ['Ring look: Flat strips the shadow, gloss, bezel and number spot; thin 46% number'] = ringLook('flat'),
  ['not Haunt: the curse is on the frame row with the rest'] = function(W, T)
    local ns, F, UI = setup(W, { where = 'frame' })
    F.mob('nameplate1', A, 'Kobold', 300).auras = { 172, 702 }
    W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1')
    F.target(A); W.combat = true; W.advance(.5)
    local frame, chan = hauntRows(UI)
    T.ok(frame, 'the frame row exists'); T.ok(not (chan and UI.isVisible(chan)), 'no over-the-mob row outside Haunt')
    T.eq(#UI.showing(UI.mainOf(frame)).curse, 1, 'Curse of Weakness on the frame row')
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
