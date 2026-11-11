-- A tiny fight script language for tests: casts, ticks and target changes on the fake clock, with both engines
-- (OmaDoomed's copy and the original DoesItDie) listening, and a comparison of what each says is left.
local W = require('fakewow')
local L = require('load')
local F = {}

-- Forever's warlock spells as the client describes them (Classic wording; totals checked against DoesItDie's log
-- from Bujuju's fights: Corruption 47 over 12 s, Immolate 20 over 15 s, Bane of Agony 84 over 24 s).
F.SPELLS = {
  [172] = { name = 'Corruption', desc = 'Corrupts the target, causing 47 Shadow damage over 12 sec.' },
  [348] = { name = 'Immolate', desc = 'Burns the enemy for 11 Fire damage and then an additional 20 Fire damage over 15 sec.' },
  [980] = { name = 'Bane of Agony', desc = 'Curses the target with agony, causing 84 Shadow damage over 24 sec. This damage is dealt slowly at first, and builds up as the Curse reaches its full duration.' },
  [18265] = { name = 'Siphon Life', desc = 'Transfers 15 health from the target to the caster every 3 sec. Lasts 30 sec.' },
  [686] = { name = 'Shadow Bolt', desc = 'Sends a shadowy bolt at the enemy, causing 13 to 18 Shadow damage.' },
  [689] = { name = 'Drain Life', desc = 'Transfers 10 health every 1 sec from the target to the caster. Lasts 5 sec.' },
  [11719] = { name = 'Curse of Tongues', desc = 'Forces the target to speak in Demonic, increasing the casting time of all spells by 50%. Only one Curse per Warlock can be active on any one target. Lasts 30 sec.' },
  [1978] = { name = 'Serpent Sting', desc = 'Stings the target, causing 20 Nature damage over 15 sec.' },
}

local castN = 0
function F.start(opts)
  opts = opts or {}
  W.now = opts.at or 1000
  L.spells(F.SPELLS)
  C_CVar = { GetCVarBool = function(n) return n == 'enableMouseoverCast' and F.mouseoverCast or false end }
  F.mouseoverCast = false
  GetCVarBool = C_CVar.GetCVarBool
  GetModifiedClick = function() return F.mouseoverCast and 'NONE' or nil end
  IsModifiedClick = function() return false end
  -- a unit has a plate when the same mob also sits on a nameplateN token
  C_NamePlate = { GetNamePlateForUnit = function(unit)
    local u = W.units[unit]; if not u then return nil end
    for k, v in pairs(W.units) do if v == u and k:match('^nameplate%d+$') then return { namePlateUnitToken = k } end end
  end }
  GetComboPoints = function() return 0 end
  CopyTable = function(t) local o = {}; for k, v in pairs(t) do o[k] = v end; return o end
  W.units.player = { guid = 'Player-1', name = 'Me' }
  F.oma = L.oma()
  if opts.compare ~= false then F.did = L.did() end
  F.diffs = {}
end

-- mob(token, guid, name, hp, opts): opts.secretGuid (instances), opts.dead, opts.friendly
function F.mob(token, guid, name, hp, o)
  o = o or {}
  local u = { guid = guid, name = name or guid, hp = hp or 200, maxhp = hp or 200, enemy = not o.friendly,
    dead = o.dead, secretGuid = o.secretGuid }
  W.units[token] = u
  return u
end
-- put an existing mob on another token too (focus, mouseover, softenemy, a plate)
function F.alias(token, fromToken) W.units[token] = W.units[fromToken] end
function F.target(guid)
  local found
  for k, u in pairs(W.units) do if u.guid == guid and k ~= 'target' then found = u end end
  W.units.target = guid and found or nil
  W.fire('PLAYER_TARGET_CHANGED')
end

-- cast(spellID, { castTime = s, on = 'target' }) : SENT, START (cast time), then SUCCEEDED when the cast ends.
function F.cast(id, o)
  o = o or {}
  castN = castN + 1
  local guid = 'Cast-' .. castN
  local name = W.units[o.on or 'target'] and W.units[o.on or 'target'].name
  W.fire('UNIT_SPELLCAST_SENT', 'player', name, guid, id)
  if o.castTime and o.castTime > 0 then
    W.fire('UNIT_SPELLCAST_START', 'player', guid, id)
    F.wait(o.castTime)
    if o.interrupted then W.fire('UNIT_SPELLCAST_INTERRUPTED', 'player', guid, id); return guid end
    W.fire('UNIT_SPELLCAST_STOP', 'player', guid, id)
  end
  W.fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id)
  return guid
end

-- hit(unit, school, amount): a damage event the game reports on a unit. amount nil = hidden (secret, in combat).
function F.hit(unit, school, amount, action)
  local a = amount
  if a == nil then a = W.secret(0) end
  W.fire('UNIT_COMBAT', unit, action or 'WOUND', '', a, school)
end

-- wait(s): move the clock in 0.05 s steps; after each step compare both engines on the target (if comparing).
function F.wait(s)
  local target = W.now + s
  while W.now < target - 1e-9 do
    W.advance(math.min(0.05, target - W.now), 0.05)
    if F.did then F.compare('target') end
  end
end

local function fmt(list)
  local p = {}
  for _, e in ipairs(list) do p[#p + 1] = ('%s=%d%s'):format(e.name, e.damage, e.provisional and 'P' or '') end
  return table.concat(p, ' ')
end
function F.dots(unit)
  local o = {}; for _, e in ipairs(F.oma.dotsFor(unit or 'target')) do o[e.name] = e end; return o
end
function F.compare(unit)
  local mine = F.oma.dotsFor(unit)
  local ref = {}
  if F.did.tracking then
    local ok, key = pcall(F.did.tracking.unitKey, unit)
    if ok and key then
      for i, e in ipairs((F.did.dotBreakdownForUnit(unit))) do
        ref[i] = { name = e.name, damage = math.floor(e.damage + 0.5), provisional = e.provisional }
      end
    end
  end
  local a, b = fmt(mine), fmt(ref)
  if a ~= b then F.diffs[#F.diffs + 1] = ('%.2f  oma[%s]  did[%s]'):format(W.now, a, b) end
end
function F.left(unit)
  local t = 0; for _, e in ipairs(F.oma.dotsFor(unit or 'target')) do t = t + e.damage end; return t
end
return F
