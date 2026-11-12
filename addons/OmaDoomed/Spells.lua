-- The warlock spells OmaDoomed draws, keyed by spell ID: every rank's ID, an English key, the colours, the tick beat
-- and the kind (dot, curse, channel). Names are only a way in: the English names here, plus whatever name the game
-- client itself gives each ID (any language), plus names the tracking reports with a spell ID (ns.spells.see).
-- IDs: Classic Era ranks plus TBC ranks; Forever kept Classic IDs for renamed spells (980 is its Bane of Agony).
-- Rings.lua also learns IDs it sees cast.
local _, ns = ...

local function rgb(r, g, b) return { r / 255, g / 255, b / 255 } end
local function hex(h) return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 } end

-- deep: the kill bar piece (sheet 34 B, deep pieces); color: the ring and the tick light (sheet 25); beat: seconds
-- between ticks. Order is the rings' group order.
local LIST = {
  { key = 'corruption', kind = 'dot', beat = 3, names = { 'Corruption' }, deep = rgb(78, 40, 136), color = hex('b078ff'),
    ids = { 172, 6222, 6223, 7648, 11671, 11672, 25311, 27216 } },
  { key = 'agony', kind = 'dot', beat = 2, names = { 'Bane of Agony', 'Curse of Agony' }, deep = rgb(128, 30, 74), color = hex('f05496'),
    ids = { 980, 1014, 6217, 11711, 11712, 11713, 27218 } },
  { key = 'immolate', kind = 'dot', beat = 3, names = { 'Immolate' }, deep = rgb(160, 66, 22), color = hex('ff8a3d'),
    ids = { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309, 27215 } },
  { key = 'siphon', kind = 'dot', beat = 3, names = { 'Siphon Life' }, deep = rgb(110, 20, 30), color = hex('d63048'),
    ids = { 18265, 18879, 18880, 18881, 27264, 30911 } },
  -- curses that do no damage: their own ring (sheet 41)
  { key = 'curse', kind = 'curse', names = { 'Curse of Weakness', 'Curse of Tongues', 'Curse of the Elements', 'Curse of Exhaustion',
      'Curse of Recklessness', 'Curse of Shadow', 'Curse of Doom' }, color = hex('96ce54'),
    ids = { 702, 1108, 6205, 7646, 11707, 11708, 27224, 30909, 1714, 11719, 1490, 11721, 11722, 27228, 18223,
      704, 7658, 7659, 11717, 27226, 17862, 17937, 603, 30910 } },
  -- channels: bone white (sheet 28). 'Soul Siphon' by name only; Wrack is Forever's channel
  { key = 'channel', kind = 'channel', names = { 'Drain Soul', 'Drain Life', 'Drain Mana', 'Wrack', 'Soul Siphon' }, color = hex('ece2c6'),
    ids = { 1120, 8288, 8289, 11675, 27217, 689, 699, 709, 7651, 11699, 11700, 27219, 27220, 5138, 6226, 11703, 11704, 27221 } },
}

local Spells = { list = LIST, byKey = {}, byID = {}, hex = hex }
ns.spells = Spells
local byName = {}
for _, sp in ipairs(LIST) do
  Spells.byKey[sp.key] = sp
  for _, id in ipairs(sp.ids) do Spells.byID[id] = sp end
  for _, n in ipairs(sp.names) do byName[n] = sp end
end

local function plain(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

-- the entry for a spell ID or a name (English or the client's), or nil
function Spells.ofID(id) return plain(id) and Spells.byID[id] or nil end
function Spells.ofName(name) return plain(name) and byName[name] or nil end
function Spells.key(name) local sp = Spells.ofName(name); return sp and sp.key end
-- a damage-over-time spell (the kill bar's pieces), or nil
function Spells.dot(name) local sp = Spells.ofName(name); return sp and sp.kind == 'dot' and sp or nil end

-- Names learned from IDs are taken for DoTs only: curse and channel IDs share names with spells we don't draw
-- (603 is Forever's Bane of Doom), and their rings are matched by ID anyway.
-- the tracking hands over name + ID: remember that name for the ID's DoT (a client name in another language)
function Spells.see(id, name)
  if not (plain(id) and plain(name)) or byName[name] then return end
  local sp = Spells.byID[id]; if sp and sp.kind == 'dot' then byName[name] = sp end
end
-- an ID learned in game (Rings.lua) joins its spell
function Spells.addID(id, key)
  local sp = Spells.byKey[key]; if sp and plain(id) and not Spells.byID[id] then Spells.byID[id] = sp end
end

-- the client's own name for each DoT (any language), from its rank 1 ID, once at login
function Spells.learnClientNames()
  local get = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
  if not get then return end
  for _, sp in ipairs(LIST) do
    if sp.kind == 'dot' then
      local ok, name = pcall(get, sp.ids[1])
      if ok and type(name) == 'string' and plain(name) and not byName[name] then byName[name] = sp end
    end
  end
end
