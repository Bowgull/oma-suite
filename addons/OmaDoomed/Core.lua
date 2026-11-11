-- OmaDoomed (named by Joshua 2026-11-11). Settings live in OmaDoomedDB; /omadoomed.
local ADDON, ns = ...
ns.say = function(m) print('|cffb48cffOmaDoomed:|r ' .. tostring(m)) end
ns.parts = {}
local DEFAULTS = { doomed = true }
local f = CreateFrame('Frame')
f:RegisterEvent('PLAYER_LOGIN')
f:SetScript('OnEvent', function()
  OmaDoomedDB = OmaDoomedDB or {}
  for k, v in pairs(DEFAULTS) do if OmaDoomedDB[k] == nil then OmaDoomedDB[k] = v end end
  ns.db = OmaDoomedDB
  for _, p in pairs(ns.parts) do pcall(p.start) end
end)
SLASH_OMADOOMED1 = '/omadoomed'
SlashCmdList.OMADOOMED = function(m)
  m = (m or ''):lower()
  local rest = m:match('^rings%s*(.*)$'); if rest then return ns.ringsSlash and ns.ringsSlash(rest) end
  if m == 'trace' then return ns.startTrace and ns.startTrace() end
  m = 'doomed ' .. m
  local p = ns.parts[m:match('^(%S+)')]
  if p and p.slash then p.slash(m:match('^%S+%s*(.*)$')) return end
  local on = {}; for k in pairs(ns.parts) do on[#on + 1] = k .. (ns.db[k] and ' on' or ' off') end
  ns.say(table.concat(on, ', ') .. '. /omadoomed (on/off, test, test off) · /omadoomed rings (on/off, test, others on|off)')
end
