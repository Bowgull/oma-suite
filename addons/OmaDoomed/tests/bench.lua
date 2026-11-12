-- OFFLINE speed and garbage bench for OmaDoomed:  luajit tests/bench.lua [jit]   (from the OmaDoomed folder)
-- Loads the whole add-on once (rings on, real fake aura containers, plates, settings) and plays 60 fps frames of:
-- standing, 1 target with 3 DoTs, a 15-mob pull, a 40-plate pull. Prints Lua ms/frame, KB/s of garbage and widget
-- calls/frame, then the budget table.
--
-- These are ESTIMATES. The JIT is off (closer to WoW's Lua VM, which is still slower: about x3 is assumed). Widget
-- calls are free here; in game each costs roughly 0.25 us, so the in-game estimate is ms x3 + calls x 0.00025 ms.
-- Blizzard's own aura container work and the countdown texts can't be measured offline at all. The harness adds a
-- little of its own (event loop, secret values), counted in the numbers below.
package.path = './tests/?.lua;' .. package.path
if jit and arg[1] ~= 'jit' then jit.off() end
local W = require('fakewow')
local L = require('load')
local ns, F, UI = L.addon({ rings = true })
W.advance(3)                                   -- out of combat: the ring pool fills (not measured)

local FPS, DT = 60, 1 / 60
local DOTS = { 172, 980, 348 }                 -- Corruption, Bane of Agony, Immolate
local out = {}                                 -- scenario -> numbers, for the budget table

local function measure(key, label, seconds, perFrame)
  for _ = 1, 30 do W.advance(DT, DT); if perFrame then perFrame() end end   -- warm up
  collectgarbage('collect'); collectgarbage('stop')
  local kb0, c0 = collectgarbage('count'), UI.calls
  UI.countNames = true; for k in pairs(UI.byName) do UI.byName[k] = nil end
  local frames, worst = math.floor(seconds * FPS), 0
  local t0 = os.clock()
  for _ = 1, frames do
    local f0 = os.clock()
    W.advance(DT, DT); if perFrame then perFrame() end
    local ft = os.clock() - f0; if ft > worst then worst = ft end
  end
  local t = os.clock() - t0
  local kb, calls = collectgarbage('count') - kb0, (UI.calls - c0) / frames
  UI.countNames = false
  collectgarbage('restart'); collectgarbage('collect')
  local top = {}; for k, v in pairs(UI.byName) do top[#top + 1] = { k, v } end
  table.sort(top, function(a, b) return a[2] > b[2] end)
  local tops = {}; for i = 1, math.min(6, #top) do tops[i] = ('%s %.1f'):format(top[i][1], top[i][2] / frames) end
  local r = { ms = t / frames * 1000, kbs = kb / seconds, calls = calls, worst = worst * 1000 }
  out[key] = r
  io.write(('%-28s %7.4f ms/frame  worst %6.3f ms  %7.1f KB/s garbage  %6.1f widget calls/frame\n'):format(label, r.ms, r.worst, r.kbs, r.calls))
  io.write('    most calls per frame: ' .. table.concat(tops, ', ') .. '\n')
  return r
end

-- a mob on a plate with your 3 DoTs (cast while targeted) and their debuffs on it
local function dotted(i, hp)
  local guid = 'Creature-0-1-0-1-' .. i .. '-B'
  local u = F.mob('nameplate' .. i, guid, 'Mob' .. i, hp or 30000); u.auras = DOTS
  W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate' .. i)
  return guid
end
local function dotAll(n, keep)
  for i = 1, n do F.target(W.units['nameplate' .. i].guid); for _, id in ipairs(DOTS) do F.cast(id) end end
  F.target(W.units['nameplate' .. keep].guid)
end
-- one hidden-amount Shadow and Fire hit per mob each second, seen through its plate (and the target token)
local function ticker(n)
  local acc = 0
  return function()
    acc = acc + DT
    if acc >= 1 then
      acc = 0
      for i = 1, n do F.hit('nameplate' .. i, 32); F.hit('nameplate' .. i, 4) end
      F.hit('target', 32); F.hit('target', 4)
    end
  end
end

io.write(('OmaDoomed offline bench, %s, %s. %d ring containers, %d aura buttons built.\n\n'):format(
  jit and jit.version or _VERSION, (jit and jit.status and (jit.status() and 'JIT on' or 'JIT off')) or '',
  #UI.aura.containers, UI.aura.buttons))

-- 1. standing: no target, no plates, out of combat
measure('standing', 'standing (no target)', 10)

-- 2. one target, three DoTs, in combat, ticks arriving
dotted(1); W.combat = false
dotAll(1, 1); W.combat = true
F.hit('nameplate1', 4)
measure('one', '1 target, 3 DoTs', 10, ticker(1))

-- 3. a 15-mob pull, 3 DoTs on each, one targeted
W.combat = false; for i = 2, 15 do dotted(i) end; W.advance(1, DT)
W.combat = true; dotAll(15, 1)
measure('pull15', '15 mobs x 3 DoTs', 10, ticker(15))

-- 4. a 40-plate pull
W.combat = false; for i = 16, 40 do dotted(i) end; W.advance(1, DT)
W.combat = true; dotAll(40, 1)
measure('pull40', '40 plates x 3 DoTs', 10, ticker(40))

local tracked = 0; for i = 1, 40 do tracked = tracked + #ns.dotsFor('nameplate' .. i) end
io.write(('  (DoTs tracked at the end: %d of 120; errors caught: %d)\n'):format(tracked, #(OmaDoomedDB.errs or {})))

-- ---------- the budget (reports/OmaDoomed ready plan.md, phase 7) ----------
local function game(r) return r.ms * 3 + r.calls * 0.00025 end
local function gameWorst(r) return r.worst * 3 + r.calls * 0.00025 end
local rows = {
  { 'standing', 'standing', game(out.standing), 0.1, 'ms/frame' },
  { 'fight, 1 target', 'one', game(out.one), 0.5, 'ms/frame' },
  { 'fight, 15 mobs', 'pull15', game(out.pull15), 0.5, 'ms/frame' },
  { 'fight, 40 plates', 'pull40', game(out.pull40), 0.5, 'ms/frame' },
  { 'worst frame, 40 plates', 'pull40', gameWorst(out.pull40), 5, 'ms' },
  { 'garbage, 15-mob pull', 'pull15', out.pull15.kbs, 100, 'KB/s' },
  { 'garbage, 40 plates', 'pull40', out.pull40.kbs, 100, 'KB/s' },
}
io.write('\nBudget (in-game estimate = offline ms x3 + widget calls x 0.25 us; garbage as measured)\n')
local over = 0
for _, r in ipairs(rows) do
  local ok = r[3] <= r[4]; if not ok then over = over + 1 end
  io.write(('  %-24s %9.3f %-8s budget %-6g %s\n'):format(r[1], r[3], r[5], r[4], ok and 'ok' or 'OVER'))
end
io.write(('%d of %d lines over budget (offline estimate; the in-game /omadoomed cpu check decides)\n'):format(over, #rows))
