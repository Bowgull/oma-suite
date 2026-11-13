-- Phase 3: the DoT model (DotModel.lua), standalone tracking, non-English clients, engine housekeeping.
local A, B, C = 'Creature-0-1-0-1-100-AAAA', 'Creature-0-1-0-1-101-BBBB', 'Creature-0-1-0-1-102-CCCC'
local FRAME = 1 / 30

-- the whole add-on with the kill bar fed straight from DOTS (the model's source), three mobs on plates, A targeted
local function bar(W, opts)
  local ns, F, UI = require('load').addon(opts)
  local M = ns.model
  F.mob('nameplate1', A, 'Kobold', 100); F.mob('nameplate2', B, 'Gnoll', 100); F.mob('nameplate3', C, 'Murloc', 100)
  local DOTS = { [A] = {}, [B] = {}, [C] = {} }
  M.source = function(u) local t = W.units[u]; return t and DOTS[t.guid] or {} end
  F.target(A)
  return ns, F, UI, M, DOTS
end
local function dot(W, name, damage, lasts, o)
  o = o or {}
  return { name = name, damage = damage, expiresAt = W.now + lasts, appliedAt = o.appliedAt or (W.now - 1), provisional = o.provisional or false }
end
local function order(M) return table.concat(M.snap().order or {}, ',') end
-- Corruption seen fresh once (so its size is known), then gone from the list
local function knowCorruption(W, DOTS)
  DOTS[A] = { dot(W, 'Corruption', 47, 12, { appliedAt = W.now }) }; W.advance(.3, FRAME)
  DOTS[A] = {}; W.advance(1.5, FRAME)
end
local function noErrors(T) T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1])) end

-- clients in other languages: names and descriptions as the client gives them
local function client(lang)
  local F = require('fight')
  local s = {}; for id, v in pairs(F.SPELLS) do s[id] = v end
  if lang == 'frFR' then
    s[172] = { name = 'Corruption', desc = "Corrompt la cible et lui inflige 47 points de dégâts d'Ombre en 12 sec." }
    s[348] = { name = 'Immolation', desc = "Brûle l'ennemi et lui inflige 11 points de dégâts de Feu, puis 20 points de dégâts de Feu en 15 sec." }
    s[17962] = { name = 'Conflagration', desc = "Enflamme une cible déjà affectée par votre Immolation." }
    s[18288] = { name = 'Malédiction amplifiée', desc = "Augmente l'effet de votre prochaine Plaie d'agonie de 50%." }
    s[980] = { name = "Plaie d'agonie", desc = "Maudit la cible et lui inflige 84 points de dégâts d'Ombre en 24 sec." }
  elseif lang == 'esES' then
    s[172] = { name = 'Corrupción', desc = 'Corrompe al objetivo y le inflige 47 p. de daño de las Sombras durante 12 s.' }
    s[348] = { name = 'Inmolar', desc = 'Quema al enemigo y le inflige 11 p. de daño de Fuego y 20 p. de daño de Fuego más durante 15 s.' }
    s[17962] = { name = 'Conflagrar', desc = 'Inflama a un objetivo afectado por tu Inmolar.' }
    s[603] = { name = 'Perdición de fatalidad', desc = 'Maldice al objetivo con una fatalidad inminente.' }
    s[980] = { name = 'Perdición de agonía', desc = 'Maldice al objetivo y le inflige 84 p. de daño de las Sombras durante 24 s.' }
  elseif lang == 'deDE' then
    s[172] = { name = 'Verderbnis', desc = 'Verdirbt das Ziel und verursacht 12 Sek. lang 47 Punkt(e) Schattenschaden.' }
    s[348] = { name = 'Feuerbrand', desc = 'Verbrennt den Feind und fügt ihm 11 Feuerschaden sowie im Verlauf von 15 Sek. insgesamt 20 zusätzlichen Feuerschaden zu.' }
    s[17962] = { name = 'Feuersbrunst', desc = 'Entzündet ein Ziel, das von Eurem Feuerbrand betroffen ist.' }
  end
  return s
end
local function trackOnly(W, lang)
  local F = require('fight'); F.start({ compare = false, spells = client(lang) }); W.locale = lang
  F.mob('nameplate1', A, 'Kobold', 500); F.target(A); W.combat = true
  return F
end
local function byID(F) local o = {}; for _, e in ipairs(F.oma.dotsFor('target')) do o[e.spellID] = e end; return o end

return {
  -- ---------- the model ----------
  ['landed: an instant cast on a new target shows its piece there (it used to look for the last cast\'s mob)'] = function(W, T)
    local ns, F, UI, M, DOTS = bar(W)
    knowCorruption(W, DOTS)
    F.cast(348, { castTime = .2 })                      -- a cast with a START on A
    F.target(B); F.cast(172); W.advance(.2, FRAME)       -- instant Corruption on B
    T.eq(order(M), 'Corruption', 'its landed piece shows on B')
    T.ok(M.snap().landed and M.snap().landed.key == B, 'matched to B by the cast')
    noErrors(T)
  end,
  ['landed: an instant cast at your focus never puts a phantom piece on your target'] = function(W, T)
    local ns, F, UI, M, DOTS = bar(W)
    knowCorruption(W, DOTS)
    F.cast(348, { castTime = .2 })                      -- START on A: the old code kept A's plate for the next cast
    F.alias('focus', 'nameplate3'); F.cast(172, { on = 'focus' }); W.advance(.2, FRAME)
    T.eq(order(M), '', 'no Corruption piece on A: it went to the focus')
    noErrors(T)
  end,
  ['landed: an instant cast on the target, same mob as the last cast, still shows'] = function(W, T)
    local ns, F, UI, M, DOTS = bar(W)
    knowCorruption(W, DOTS)
    F.cast(348, { castTime = .2 }); F.cast(172); W.advance(.2, FRAME)
    T.eq(order(M), 'Corruption')
  end,
  ['prediction: health changing on a DoT\'s beat starts its bite at once and pulses its ring (solo only)'] = function(W, T)
    local ns, F, UI, M, DOTS = bar(W)
    local seen = {}; ns.bus:On('TICK', function(unit, name, key) seen[#seen + 1] = unit .. ':' .. name .. ':' .. tostring(key) end)
    local t0 = W.now
    DOTS[A] = { dot(W, 'Corruption', 47, 12, { appliedAt = t0 }) }
    W.advance(3 - (W.now - t0), FRAME)                   -- on its first beat
    W.fire('UNIT_HEALTH', 'target')
    T.ok(M.biteOf('Corruption'), 'a bite on the beat')
    T.near(M.peek('Corruption').pred.est, 47 / 4, 1e-6, 'a quarter of what is left (4 ticks)')
    T.eq(seen[1], 'target:Corruption:corruption', 'TICK with its key')
    DOTS[A][1].damage = 35; W.advance(.2, FRAME)
    T.eq(#seen, 1, 'the real tick that follows is not a second tick')
    W.group = true; W.advance(3, FRAME); W.fire('UNIT_HEALTH', 'target')
    T.eq(#seen, 1, 'in a group nothing is predicted')
    noErrors(T)
  end,
  ['ending: a DoT that ran out stays as an empty ghost while its last bite closes, then goes'] = function(W, T)
    local ns, F, UI, M, DOTS = bar(W)
    DOTS[A] = { dot(W, 'Corruption', 12, 1) }; W.advance(.5, FRAME)
    DOTS[A] = {}; W.advance(.1, FRAME)
    local cur = M.cur(); T.ok(cur and cur.dots[1] and cur.dots[1].ending, 'a ghost in the list')
    T.ok(M.biteOf('Corruption') and not M.biteOf('Corruption').quiet, 'its last tick lights (it was ending)')
    W.advance(1, FRAME)
    T.eq(order(M), '', 'gone once the bite closed')
  end,
  ['bus: a new target fires TARGET with a fresh snapshot; tracking changes fire DOTS'] = function(W, T)
    local ns, F, UI, M = bar(W)
    local n, d, snaps = 0, 0, {}
    ns.bus:On('TARGET', function() n = n + 1; snaps[#snaps + 1] = M.snap() end)
    ns.bus:On('DOTS', function() d = d + 1 end)
    local before = M.snap(); F.target(B)
    T.eq(n, 1); T.ok(snaps[1] ~= before, 'fresh before TARGET')
    d = 0; ns.onTrackChanged(); T.eq(d, 1)
  end,

  -- ---------- standalone ----------
  ['standalone: Does It Die is never read or written; one chat line says both markers show'] = function(W, T)
    local touched = {}
    local function trap(name) return setmetatable({}, { __index = function(_, k) touched[#touched + 1] = name .. '.' .. tostring(k) end,
      __newindex = function(_, k) touched[#touched + 1] = name .. '.' .. tostring(k) .. '=' end }) end
    local ns, F = require('load').addon({ before = function() DoesItDie = trap('DoesItDie'); DoesItDieDB = trap('DoesItDieDB') end })
    F.mob('nameplate1', A, 'Kobold', 300); F.target(A); F.cast(172); W.advance(2)
    ns.saveReport('command'); W.advance(1)
    T.eq(#touched, 0, 'touched: ' .. table.concat(touched, ', '))
    local said = 0; for _, l in ipairs(W.printed) do if l:find('Does It Die is also on', 1, true) then said = said + 1 end end
    T.eq(said, 1, 'said once')
    local toc = io.open('OmaDoomed.toc'):read('*a'); T.ok(not toc:find('DoesItDie', 1, true), 'no OptionalDeps')
  end,
  ['standalone: no Does It Die, no line'] = function(W, T)
    require('load').addon()
    for _, l in ipairs(W.printed) do T.ok(not l:find('Does It Die', 1, true), l) end
  end,
  ['saved data 2: the engine choice, the side-by-side log, Does It Die\'s look and the trace lines are dropped'] = function(W, T)
    require('load').addon({ before = function() OmaDoomedDB = { v = 1, engine = 'did', compare = { checks = 3, log = {} },
      didSaved = { m = true }, cast = 'motes', track = { log = { 'x' }, ticks = { [172] = 15 } } } end })
    T.eq(OmaDoomedDB.v, 4); T.eq(OmaDoomedDB.engine, nil); T.eq(OmaDoomedDB.compare, nil); T.eq(OmaDoomedDB.didSaved, nil)
    T.eq(OmaDoomedDB.cast, 'motes', 'settings kept')
    T.eq(#OmaDoomedDB.track.log, 0, 'old trace lines gone')
  end,
  ['a fresh install takes nothing from Does It Die\'s saved ticks'] = function(W, T)
    require('load').addon({ before = function() DoesItDieDB = { version = 99, ticks = { [172] = 15 } } end })
    T.eq(next(OmaDoomedDB.track.ticks), nil)
  end,

  -- ---------- engine housekeeping ----------
  ['trace log: off by default, on with /omadoomed trace on'] = function(W, T)
    local ns, F = require('load').addon()
    F.mob('nameplate1', A, 'Kobold', 300); F.target(A); F.cast(172); W.advance(4); F.hit('nameplate1', 32)
    T.eq(#OmaDoomedDB.track.log, 0, 'nothing logged')
    SlashCmdList.OMADOOMED('trace on'); F.target(nil); F.target(A)
    T.ok(#OmaDoomedDB.track.log > 0, 'logged when asked')
    SlashCmdList.OMADOOMED('trace off'); T.eq(#OmaDoomedDB.track.log, 0, 'cleared')
  end,
  ['UNIT_COMBAT from units we don\'t watch (a party member on the same mob) never counts as a tick'] = function(W, T)
    local F = require('fight'); F.start({ compare = false })
    F.mob('nameplate1', A, 'Kobold'); F.target(A); W.combat = true
    F.alias('party1', 'nameplate1')
    F.cast(172)
    for i = 1, 4 do F.wait(3); F.hit('party1', 32) end   -- every beat, but only through party1
    F.wait(.5)
    T.eq(F.dots().Corruption, nil, 'never ticked as far as we can see: dropped')
    T.ok(F.oma.track.omaWatched('nameplate7') and F.oma.track.omaWatched('softenemy') and F.oma.track.omaWatched('mouseover'))
    T.ok(not F.oma.track.omaWatched('raid12') and not F.oma.track.omaWatched('player') and not F.oma.track.omaWatched('pet'))
  end,
  ['an evade seen through a party token is ignored; through the plate it drops the DoTs'] = function(W, T)
    local F = require('fight'); F.start({ compare = false })
    F.mob('nameplate1', A, 'Kobold'); F.target(A); W.combat = true; F.alias('party1', 'nameplate1')
    F.cast(172); F.wait(.2)
    W.fire('UNIT_COMBAT', 'party1', 'EVADE', '', 0, 1); T.ok(F.dots().Corruption)
    W.fire('UNIT_COMBAT', 'nameplate1', 'EVADE', '', 0, 1); T.eq(F.dots().Corruption, nil)
  end,
  ['a non-warlock: the engine, the Forever rules and Wrack listen to nothing'] = function(W, T)
    local before = #W.frames
    local ns = require('load').addon({ class = 'MAGE' })
    local loud = {}
    for i = before + 1, #W.frames do
      local f = W.frames[i]
      if next(f.events) or f.scripts.OnUpdate then loud[#loud + 1] = i .. ':' .. tostring(f.kind) .. ':' .. tostring(next(f.events)) end
    end
    T.eq(#loud, 0, 'frames still listening: ' .. table.concat(loud, ' '))
  end,

  -- ---------- other client languages ----------
  ['French client: Immolation and Corruption are tracked and keyed'] = function(W, T)
    local F = trackOnly(W, 'frFR'); F.cast(348); F.cast(172); F.wait(.2)
    local by = byID(F); T.ok(by[348], 'Immolation'); T.ok(by[172], 'Corruption')
    T.eq(F.oma.spells.ofID(by[348].spellID).key, 'immolate')
  end,
  ['Spanish client: Inmolar and Corrupción are tracked'] = function(W, T)
    local F = trackOnly(W, 'esES'); F.cast(348); F.cast(172); F.wait(.2)
    local by = byID(F); T.ok(by[348], 'Inmolar'); T.ok(by[172], 'Corrupción')
  end,
  ['Spanish client: Conflagrar eats Inmolar (no Shadow and Flame)'] = function(W, T)
    local F = trackOnly(W, 'esES'); F.cast(348); F.wait(.2); T.ok(byID(F)[348])
    F.cast(17962); F.wait(.1); T.eq(byID(F)[348], nil)
  end,
  ['Spanish client: Perdición de fatalidad replaces Perdición de agonía'] = function(W, T)
    local F = trackOnly(W, 'esES'); F.cast(980); F.wait(2.2); F.hit('nameplate1', 32); F.wait(.1); T.ok(byID(F)[980], 'Agony on')
    F.cast(603); F.wait(.1); T.eq(byID(F)[980], nil)
  end,
  ['French client: Malédiction amplifiée makes the next Plaie d\'agonie +50%'] = function(W, T)
    local F = trackOnly(W, 'frFR'); F.cast(18288); F.cast(980); F.wait(.1)
    local e = byID(F)[980]; T.ok(e, 'Agony tracked'); T.eq(e.damage, 126, '84 x 1.5')
  end,
  ['German client: Shadow and Flame is read by its place in the tree, keeping Feuerbrand from Feuersbrunst'] = function(W, T)
    local F = trackOnly(W, 'deDE'); F.talents({ ['Shadow and Flame'] = 5 }, { ['Shadow and Flame'] = 'Schatten und Flamme' })
    F.cast(348); F.wait(.2); F.cast(17962); F.wait(.1)
    T.ok(byID(F)[348], 'kept at 5/5')
  end,

  -- ---------- the eyes are gone ----------
  ['no eyes: each plate gets a ring and a main container, nothing else'] = function(W, T)
    local ns, F, UI = require('load').addon({ rings = true }); W.advance(3)
    local rings = #UI.ringContainers()
    T.ok(rings > 0); T.eq(#UI.aura.containers, 2 * rings, 'two containers per pair')
    for _, c in ipairs(UI.aura.containers) do T.eq(UI.group(c, 'isb'), nil, 'no eyes group') end
    T.eq(ns.eyes, nil); T.eq(ns.eyesUnits, nil); T.eq(ns.eyeKeyFor, nil)
  end,
}
