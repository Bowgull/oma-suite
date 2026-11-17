-- Phase 2 foundations inside the add-on: the warlock gate, Blizzard's nameplate debuffs put back at logout,
-- saved-data versions, the spells registry, the bug-report recorder and the settings bus.
local A = 'Creature-0-1-0-1-100-AAAA'
local function rings(W, before)
  local ns, F, UI = require('load').addon({ rings = true, before = before }); W.advance(3)
  return ns, F, UI
end
local NPC, PLR = 'nameplateEnemyNpcAuraDisplay', 'nameplateEnemyPlayerAuraDisplay'

return {
  ['a non-warlock: nothing built, no events, no page, no slash, no game setting changed (even at logout)'] = function(W, T)
    local ns, F, UI = require('load').addon({ rings = true, class = 'MAGE' }); W.advance(3)
    T.eq(#UI.aura.containers, 0, 'no aura containers built')
    T.eq(W.cvars[NPC], '7'); T.eq(W.cvars[PLR], '7')
    T.eq(#UI.S.categories, 0, 'no Options page'); T.eq(SlashCmdList.OMADOOMED, nil, 'no /omadoomed')
    T.ok(not ns.blizzard.started, 'Blizzard controls never started')
    F.mob('nameplate1', A, 'Kobold', 300); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); F.target(A); W.advance(1)
    T.eq(#UI.aura.containers, 0, 'still nothing after a plate and a target')
    W.fire('PLAYER_LOGOUT'); T.eq(W.cvars[NPC], '7', 'logout changes nothing')
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,

  ["Blizzard's nameplate debuffs: put back at logout, the saved copy cleared"] = function(W, T)
    local ns, F, UI = rings(W)
    T.eq(C_CVar.GetCVarBitfield(NPC, 2), false, 'off while the rings show')
    W.fire('PLAYER_LOGOUT')
    T.eq(W.cvars[NPC], '7', 'mobs: put back'); T.eq(W.cvars[PLR], '7', 'players: put back')
    T.eq(next(OmaDoomedDB.rings.saved), nil, 'nothing left to restore')
  end,
  ["Blizzard's nameplate debuffs: a warlock's login turns them off again, keeping the player's own value"] = function(W, T)
    local ns, F, UI = rings(W, function() W.cvars = { [NPC] = '5', [PLR] = '7' }; OmaDoomedDB = { v = 1, rings = { saved = {} } } end)
    T.eq(C_CVar.GetCVarBitfield(NPC, 2), false); T.eq(OmaDoomedDB.rings.saved[NPC], '5', 'their own value kept')
    W.fire('PLAYER_LOGOUT'); T.eq(W.cvars[NPC], '5', 'and put back as it was')
  end,
  ["Blizzard's nameplate debuffs: logging out in combat leaves the saved copy for the next login"] = function(W, T)
    local ns, F, UI = rings(W)
    W.combat = true; W.fire('PLAYER_LOGOUT')
    T.eq(C_CVar.GetCVarBitfield(NPC, 2), false, 'not set in combat')
    T.eq(OmaDoomedDB.rings.saved[NPC], '7', 'the old value still kept')
    T.ok(OmaDoomedDB.errs and OmaDoomedDB.errs[1]:find('logged out in combat', 1, true), 'noted for bug reports')
  end,
  ["Blizzard's nameplate debuffs: /omadoomed rings off in combat waits for the fight to end"] = function(W, T)
    local ns, F, UI = rings(W)
    W.combat = true; SlashCmdList.OMADOOMED('rings off')
    T.eq(C_CVar.GetCVarBitfield(NPC, 2), false, 'untouched in combat')
    T.ok(W.printed[#W.printed]:find('after this fight', 1, true), 'says when')
    W.combat = false; W.fire('PLAYER_REGEN_ENABLED')
    T.eq(W.cvars[NPC], '7', 'back after the fight'); T.eq(W.cvars[PLR], '7')
  end,
  ["Blizzard's squares: 'All but my DoTs' on a mob, every new target (hooked, not replaced)"] = function(W, T)
    local orig = function() end
    local ns, F, UI = rings(W, function() TargetFrame.ConfigureAuraContainer = orig end)
    local au = TargetFrame.TargetFrameContent.TargetFrameContentContextual.Auras
    F.mob('nameplate1', A, 'Kobold', 300); F.target(A)
    T.eq(au:GetMaxDebuffs(), 0, 'debuff row off on a mob'); T.eq(au:GetMaxBuffs(), 32, 'buffs kept')
    au:SetMaxDebuffs(16); TargetFrame.ConfigureAuraContainer()
    T.eq(au:GetMaxDebuffs(), 0, 're-applied after Blizzard sets it')
    OmaDoomedDB.rings.squares = 'all'; ns.bus:Fire('SETTING', 'squares', 'rings')
    T.eq(au:GetMaxDebuffs(), 16, "'All' gives the row back")
  end,

  ['saved data: a fresh install is the newest version with every default'] = function(W, T)
    local ns = require('load').addon()
    T.eq(OmaDoomedDB.v, #ns.MIGRATIONS)
    T.eq(OmaDoomedDB.doomed, true); T.eq(OmaDoomedDB.platebar, true); T.eq(OmaDoomedDB.cast, 'charging')
    T.eq(OmaDoomedDB.rings.enabled, true); T.eq(OmaDoomedDB.rings.others, true); T.eq(OmaDoomedDB.rings.size, 40)
  end,
  ['saved data: an old save (no version) keeps its values; OmaPlatesDB is no longer read or cleared'] = function(W, T)
    local old = { size = 99 }
    local ns = require('load').addon({ rings = true, before = function()
      OmaDoomedDB = { cast = 'motes', tick = 'cinders', rings = { where = 'split', saved = {} } }; OmaPlatesDB = old
    end })
    T.eq(OmaDoomedDB.v, #ns.MIGRATIONS); T.eq(OmaDoomedDB.cast, 'motes'); T.eq(OmaDoomedDB.tick, 'cinders'); T.eq(OmaDoomedDB.rings.where, 'split')
    T.eq(OmaDoomedDB.rings.size, 40, 'not taken from OmaPlatesDB'); T.ok(OmaPlatesDB == old and old.size == 99, 'OmaPlatesDB left alone')
    local toc = io.open('OmaDoomed.toc'):read('*a'); T.ok(not toc:find('OmaPlatesDB', 1, true), 'not a SavedVariable any more')
  end,
  ['saved data: a newer version than this build is left as it is'] = function(W, T)
    require('load').addon({ before = function() OmaDoomedDB = { v = 7, cast = 'plain' } end })
    T.eq(OmaDoomedDB.v, 7); T.eq(OmaDoomedDB.cast, 'plain')
  end,

  ['spells: every rank, both colours and the beat, the same numbers as before'] = function(W, T)
    local ns = require('load').addon()
    local S = ns.spells
    local deep = { corruption = { 41, 40, 136 }, agony = { 128, 30, 97 }, immolate = { 160, 66, 22 }, siphon = { 110, 20, 22 } }
    local ring = { corruption = '7d7bff', agony = 'ff4fc8', immolate = 'ff8a3d', siphon = 'e8363a', curse = '96ce54', channel = 'ece2c6' }
    for key, c in pairs(deep) do for i = 1, 3 do T.eq(S.byKey[key].deep[i], c[i] / 255, key .. ' piece colour') end end
    for key, h in pairs(ring) do for i = 1, 3 do T.eq(S.byKey[key].color[i], tonumber(h:sub(2 * i - 1, 2 * i), 16) / 255, key .. ' ring colour') end end
    T.eq(S.byKey.agony.beat, 2); T.eq(S.byKey.corruption.beat, 3); T.eq(S.byKey.immolate.beat, 3); T.eq(S.byKey.siphon.beat, 3)
    for _, id in ipairs({ 172, 27216, 980, 27218, 348, 27215, 18265, 30911 }) do T.ok(S.ofID(id) and S.ofID(id).kind == 'dot', 'rank ' .. id) end
    T.eq(S.ofID(603).key, 'curse'); T.eq(S.ofID(689).key, 'channel')
    T.eq(S.key('Curse of Agony'), 'agony'); T.eq(S.key('Bane of Agony'), 'agony'); T.eq(S.key('Drain Life'), 'channel')
    T.eq(S.dot('Drain Life'), nil, 'a channel is not a kill bar piece'); T.eq(S.dot('Bane of Doom'), nil)
    T.eq(S.key(W.secret('Corruption')), nil, 'a secret name finds nothing')
    local keys = {}; for _, sp in ipairs(S.list) do keys[#keys + 1] = sp.key end
    T.eq(table.concat(keys, ','), 'cc,corruption,agony,immolate,siphon,curse,channel', 'the rings\' group order')
  end,
  ['spells: a client in another language finds its DoTs by ID (names learned at login and from the tracking)'] = function(W, T)
    local F = require('fight')
    local s = {}; for id, v in pairs(F.SPELLS) do s[id] = v end
    s[172] = { name = 'Verderbnis' }; s[348] = { name = 'Feuerbrand' }; s[603] = { name = 'Bann der Verdammnis' }
    local ns = require('load').addon({ spells = s })
    T.eq(ns.spells.key('Verderbnis'), 'corruption'); T.eq(ns.spells.key('Feuerbrand'), 'immolate')
    T.eq(ns.spells.key('Bann der Verdammnis'), nil, 'curse names are matched by ID, not learned')
    ns.spells.see(18265, 'Lebensentzug'); T.eq(ns.spells.key('Lebensentzug'), 'siphon')
    ns.spells.see(689, 'Blutsauger'); T.eq(ns.spells.key('Blutsauger'), nil, 'channels are not learned')
  end,

  ['bug report: rows are numbers until saved, a repeat is not stored twice, a hidden number shows as ?'] = function(W, T)
    local ns = require('load').addon()
    local function row(dmg, prov) return { dots = { { name = 'Corruption', damage = dmg, provisional = prov }, { name = 'Immolate', damage = 12.4, ending = true } } } end
    ns.recordRow(row(47)); W.now = W.now + .1
    ns.recordRow(row(47)); W.now = W.now + .1
    ns.recordRow(row(47)); W.now = W.now + .1
    ns.recordRow(row(35.6, true), 'bites1'); W.now = W.now + .1
    ns.recordRow(row(W.secret(30))); W.now = W.now + .1
    ns.recordRow(nil)
    ns.saveReport('command')
    local rows = OmaDoomedDB.reports[1].rows
    T.eq(#rows, 4, 'three identical rows stored once: ' .. table.concat(rows, ' / '))
    T.ok(rows[1]:find('^%d+%.%d Corr=47 Immo=12E fps60 same to %d+%.%d$'), rows[1])
    T.ok(rows[2]:find('Corr=36P Immo=12E bites1 fps60', 1, true), rows[2])
    T.ok(rows[3]:find('Corr=? Immo=12E', 1, true), rows[3])
    T.ok(rows[4]:find(' none fps60', 1, true), rows[4])
    W.now = W.now + 61; ns.saveReport('command'); T.eq(#OmaDoomedDB.reports[1].rows, 0, 'older than 60 s: gone')
  end,
  ['bug report: the settings come from the settings table, with defaults'] = function(W, T)
    local ns = require('load').addon({ before = function() OmaDoomedDB = { cast = 'motes', rings = { size = 52 } } end })
    ns.saveReport('command')
    local r = OmaDoomedDB.reports[1]
    T.eq(r.bar.cast, 'motes'); T.eq(r.bar.low, 5); T.eq(r.bar.v, #ns.MIGRATIONS); T.eq(r.rings.size, 52); T.eq(r.rings.where, 'enemy')
  end,

  ['bus: a kill bar tick pulses its ring on the target plate'] = function(W, T)
    local ns, F, UI = rings(W)
    F.mob('nameplate1', A, 'Kobold', 300).auras = { 172 }; W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); F.target(A); W.advance(.5)
    T.ok(UI.rowOn('nameplate1'), 'a row')
    local pulses = 0
    ns.bus:Fire('TICK', 'target', 'Corruption')
    for _, c in ipairs(UI.aura.containers) do if c.unit == 'nameplate1' then for _, g in ipairs(c.groups) do for _, b in ipairs(g.buttons) do
      local g2 = rawget(b, 'omPulse'); if g2 and rawget(g2, '_plays') then pulses = pulses + g2._plays end end end end end
    T.eq(pulses, 1, "Corruption's ring breathed once")
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,
  ['a failing part says one line in chat, and the error handler sees it'] = function(W, T)
    local seen = {}
    local ns, F = require('load').addon({ before = function() geterrorhandler = function() return function(m) seen[#seen + 1] = m end end end })
    local P = ns.parts.doomed
    F.mob('nameplate1', A, 'Kobold', 300); F.target(A)
    ns.model.source = function() error('engine broke', 0) end
    W.advance(1, 1 / 30)
    local lines = 0; for _, p in ipairs(W.printed) do if p:find('paused until /reload', 1, true) then lines = lines + 1 end end
    T.eq(lines, 1, 'one chat line'); T.eq(#seen, 1, 'one error for BugSack'); T.ok(seen[1]:find('engine broke', 1, true), seen[1])
    T.ok(P.off, 'the kill bar is off for the session')
  end,
}
