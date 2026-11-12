-- OmaDemon offline smoke test: loads the add-on in TOC order into OmaDoomed's fake WoW (with the Settings fake),
-- logs in a warlock with a demon out, then works every setting, Preview, Move gems and the edge looks.
-- Run from the OmaDemon folder:  luajit tests/smoke.lua
package.path = '../OmaDoomed/tests/?.lua;' .. package.path
local W = require('fakewow')
local UI = require('ui'); UI.install(); UI.settings()
UnitClass = function() return 'Warlock', 'WARLOCK' end
UnitExists = function(u) return u == 'pet' or u == 'player' end
UnitIsDeadOrGhost = function() return false end
local hp = .2
UnitHealthPercent = function(u, pred, curve) if curve then return curve:Evaluate(hp) end; return hp end
local function mkCurve() local pts = {}; return { SetType = function() end, AddPoint = function(_, x, y) pts[#pts + 1] = { x, y } end,
  Evaluate = function(_, x) for i = 1, #pts - 1 do local a, b = pts[i], pts[i + 1]; if x >= a[1] and x <= b[1] then if b[1] == a[1] then return b[2] end; return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1]) end end; return 0 end } end
C_CurveUtil = { CreateCurve = mkCurve }; Enum = Enum or {}; Enum.LuaCurveType = { Linear = 1 }
GetCVarBool = GetCVarBool or function() return false end
local binds = {}
SetOverrideBindingClick = function(owner, prio, key, btn) binds[key] = btn end
ClearOverrideBindings = function() binds = {} end
HideUIPanel = HideUIPanel or function(f) f:Hide() end
local count = 3
C_Item = C_Item or {}; C_Item.GetItemCount = function() return count end
local files = {}
for line in io.lines('OmaDemon.toc') do if not line:match('^##') and line:match('%S') then files[#files + 1] = (line:gsub('\\', '/'):gsub('%s+$', '')) end end
local ns = W.load('.', 'OmaDemon', files, {})
W.fire('ADDON_LOADED', 'OmaDemon'); W.fire('PLAYER_LOGIN'); W.fire('PLAYER_ENTERING_WORLD')
local ok = 0
local function check(c, m) if not c then error('FAIL: ' .. m, 2) end; ok = ok + 1 end
check(ns.category ~= nil, 'settings page built')
check(OmaDemonDB.glow.look == 'default' and OmaDemonDB.shards.gemLook == 'default', 'defaults filled, first choice called default')
-- every setting change runs without error
for _, it in ipairs(ns.settings.items) do
  if it.key and it.control then
    local store = OmaDemonDB[it.store]
    local v = it.default
    if it.control == 'check' then v = not v elseif it.control == 'slider' then v = it.max elseif it.control == 'dropdown' then v = it.choices[#it.choices][1] end
    store[it.key] = v; for _, fn in ipairs(ns.onSetting) do fn(it.key, it.store) end
    store[it.key] = it.default; for _, fn in ipairs(ns.onSetting) do fn(it.key, it.store) end
    check(true, it.key)
  end
end
for _, L in ipairs({ 'default', 'heart', 'wisps', 'essence', 'fire' }) do
  OmaDemonDB.glow.look = L; for _, fn in ipairs(ns.onSetting) do fn('look', 'glow') end
  W.advance(3); check(true, 'look ' .. L)
end
ns.previewWarning(); W.advance(1); check(true, 'preview')
OmaDemonDB.shards.pin = false; for _, fn in ipairs(ns.onSetting) do fn('pin', 'shards') end
check(OmaDemonDB.shards.pin == false, 'unpinned (the fake has no layout, so no spot to keep)')
ns.moveGems(); check(_G.OmaDemonGemMover:IsShown(), 'move box shows'); _G.OmaDemonNudgeUp:Click(); ns.endMove()
check(not _G.OmaDemonGemMover:IsShown(), 'done hides the box')
count = 7; W.fire('BAG_UPDATE_DELAYED'); check(true, 'over keep')
io.write(('OmaDemon smoke: %d checks passed\n'):format(ok))
