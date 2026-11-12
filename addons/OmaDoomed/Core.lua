-- OmaDoomed (named 2026-11-11). Settings live in OmaDoomedDB; /omadoomed.
local ADDON, ns = ...
ns.say = function(m) print('|cffb48cffOmaDoomed:|r ' .. tostring(m)) end
ns.parts = {}
-- errors are kept (last 30, saved on /reload) instead of popping up: /omadoomed errors shows them
function ns.err(m)
  OmaDoomedDB = OmaDoomedDB or {}; OmaDoomedDB.errs = OmaDoomedDB.errs or {}
  local e = OmaDoomedDB.errs; if e[1] and e[1]:sub(10) == m then return end
  table.insert(e, 1, date('%H:%M:%S ') .. m); while #e > 30 do table.remove(e) end
end
local DEFAULTS = { doomed = true }   -- the rest: Settings.lua (ns.DEFAULTS)
local f = CreateFrame('Frame')
f:RegisterEvent('PLAYER_LOGIN')
f:SetScript('OnEvent', function()
  OmaDoomedDB = OmaDoomedDB or {}
  for k, v in pairs(DEFAULTS) do if OmaDoomedDB[k] == nil then OmaDoomedDB[k] = v end end
  OmaDoomedDB.trace, OmaDoomedDB.traceErr, OmaDoomedDB.tffind, OmaDoomedDB.plateGeo = nil, nil, nil, nil   -- left by test builds' debug commands
  if type(OmaDoomedDB.rings) == 'table' then OmaDoomedDB.rings.log = nil end
  ns.db = OmaDoomedDB
  for _, p in pairs(ns.parts) do pcall(p.start) end
end)
SLASH_OMADOOMED1 = '/omadoomed'
SlashCmdList.OMADOOMED = function(m)
  m = (m or ''):lower()
  local rest = m:match('^rings%s*(.*)$'); if rest then return ns.ringsSlash and ns.ringsSlash(rest) end
  if m == 'report' then return ns.saveReport and ns.saveReport('command') end
  if m == 'cpu' then if ns.perf then for _, l in ipairs(ns.perfLines(ns.perf())) do print(l) end end; return end
  if m == 'report show' then return ns.showReport and ns.showReport() end
  if m == 'errors' then for i = math.min(8, #(OmaDoomedDB.errs or {})), 1, -1 do print(OmaDoomedDB.errs[i]) end; return end
  if m == 'options' or m == 'settings' then return ns.openSettings and ns.openSettings() end
  m = 'doomed ' .. m
  local p = ns.parts[m:match('^(%S+)')]
  if p and p.slash then p.slash(m:match('^%S+%s*(.*)$')) return end
  local on = {}; for k in pairs(ns.parts) do on[#on + 1] = k .. (ns.db[k] and ' on' or ' off') end
  ns.say(table.concat(on, ', ') .. '. /omadoomed (on/off, test, test off) · /omadoomed rings (on/off, test, others on|off) · /omadoomed cpu')
end
