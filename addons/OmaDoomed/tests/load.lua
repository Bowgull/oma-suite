-- Loads OmaDoomed's tracking and (for comparison) the original DoesItDie engine into one fake WoW.
local W = require('fakewow')
local L = {}
local TRACK = { 'Track/Shim.lua', 'Track/Locale.lua', 'Track/Locale_deDE.lua', 'Track/Locale_esES.lua', 'Track/Locale_frFR.lua',
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
return L
