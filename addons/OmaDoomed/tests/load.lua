-- Loads OmaDoomed's tracking and (for comparison) the original DoesItDie engine into one fake WoW.
local W = require('fakewow')
local L = {}
local TRACK = { 'Spells.lua', 'Track/Shim.lua', 'Track/Locale.lua', 'Track/Locale_deDE.lua', 'Track/Locale_esES.lua', 'Track/Locale_frFR.lua',
  'Track/Locale_koKR.lua', 'Track/Locale_ptBR.lua', 'Track/Locale_zhCN.lua', 'Track/Locale_ruRU.lua', 'Track/Engine.lua', 'Track/Wrack.lua', 'Track/Forever.lua' }
L.TRACK = TRACK

-- spells: id -> { name=, desc= } (what C_Spell would answer on Forever)
function L.spells(list)
  C_Spell = {
    GetSpellName = function(id) return list[id] and list[id].name end,
    GetSpellDescription = function(id) return list[id] and list[id].desc end,
  }
end

function L.oma()
  local OMA = W.load('.', 'OmaDoomed', TRACK, {})
  W.fire('ADDON_LOADED', 'OmaDoomed')
  return OMA
end

-- The original DoesItDie engine, display stubbed the same way, as the reference.
function L.did()
  local noop = function() end
  local ns = { display = setmetatable({ schoolColors = {}, attach = function() return true end }, { __index = function() return noop end }),
    registerOptions = noop, playFlash = noop }
  ns.refresh = function() if ns.tracking then ns.tracking.housekeep(GetTime()) end end
  local up = 'tools/upstream'
  W.load(up, 'DoesItDie', { 'Locale.lua', 'Locale_deDE.lua', 'Locale_esES.lua', 'Locale_frFR.lua', 'Locale_koKR.lua',
    'Locale_ptBR.lua', 'Locale_zhCN.lua', 'Locale_ruRU.lua', 'DoesItDie.lua' }, ns)
  W.fire('ADDON_LOADED', 'DoesItDie')
  return ns
end
-- The add-on's files in TOC order.
function L.toc()
  local files = {}
  for line in io.lines('OmaDoomed.toc') do
    if not line:match('^##') and line:match('%S') and not line:match('%.xml%s*$') then files[#files + 1] = (line:gsub('\\', '/'):gsub('%s+$', '')) end
  end
  return files
end

-- The whole add-on, loaded once in TOC order into a fake WoW with the UI fakes, the way the game loads it.
-- opts: class ('WARLOCK'), rings (true: the aura container APIs exist, so the rings start), settings (default on),
-- spells (another spell list), before (a function run just before the files load: saved variables, locale),
-- login (default on: ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD; off: ADDON_LOADED only).
-- Returns ns, the fight helpers (F.oma = ns) and the UI fake.
function L.addon(opts)
  opts = opts or {}
  local F = require('fight'); F.world(opts)
  local UI = require('ui'); UI.install(); UI.plates()
  if opts.settings ~= false then UI.settings() end
  if opts.rings then UI.auras() end
  if opts.class then local c = opts.class; UnitClass = function() return c:sub(1, 1) .. c:sub(2):lower(), c end end
  if opts.before then opts.before() end
  local ns = W.load('.', 'OmaDoomed', L.toc(), {})
  F.oma = ns
  W.fire('ADDON_LOADED', 'OmaDoomed')
  if opts.login ~= false then W.fire('PLAYER_LOGIN'); W.fire('PLAYER_ENTERING_WORLD') end
  return ns, F, UI
end
return L
