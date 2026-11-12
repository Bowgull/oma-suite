-- The one file that changes Blizzard's own settings and frames (the taint surface, kept small):
--   * Blizzard's debuff row on enemy nameplates (two secure CVars): off while the rings show ours, the old value kept
--     in OmaDoomedDB.rings.saved. Put back at every logout, switched off again at a warlock's login, so an uninstall
--     or another character finds Blizzard's own setting. Never set in combat: a change asked for in combat waits for
--     PLAYER_REGEN_ENABLED.
--   * Blizzard's squares on the target frame (SetMaxDebuffs / SetMaxBuffs, public calls, only when the value changes),
--     re-applied after Blizzard's own ConfigureAuraContainer through hooksecurefunc.
-- Warlocks only: Core.lua runs start() at a warlock's login; on other classes this file does nothing.
local ADDON, ns = ...
local BC = {}
ns.blizzard = BC

local function rdb() return ns.db and ns.db.rings end

-- ---------- Blizzard's nameplate debuff row ----------
local CVARS = {
  { name = 'nameplateEnemyNpcAuraDisplay', bit = Enum.NamePlateEnemyNpcAuraDisplay and Enum.NamePlateEnemyNpcAuraDisplay.Debuffs or 2 },
  { name = 'nameplateEnemyPlayerAuraDisplay', bit = Enum.NamePlateEnemyPlayerAuraDisplay and Enum.NamePlateEnemyPlayerAuraDisplay.Debuffs or 2 },
}
local pendingBlizzard = nil   -- true / false: a change asked for in combat, made when it ends

-- show = true puts the saved value back; false keeps the current value and turns the debuff bit off
function BC.blizzardRow(show)
  local db = rdb(); if not db then return end
  db.saved = db.saved or {}
  if InCombatLockdown() then pendingBlizzard = show; return end   -- secure CVars: never set in combat
  pendingBlizzard = nil
  for _, cv in ipairs(CVARS) do
    local ok, cur = pcall(C_CVar.GetCVar, cv.name)
    if ok and cur ~= nil then
      if show then
        if db.saved[cv.name] ~= nil then pcall(C_CVar.SetCVar, cv.name, db.saved[cv.name]); db.saved[cv.name] = nil end
      else
        if db.saved[cv.name] == nil then db.saved[cv.name] = cur end
        local okS, err = pcall(C_CVar.SetCVarBitfield, cv.name, cv.bit, false)
        if not okS then ns.err('rings: could not turn off ' .. cv.name .. ': ' .. tostring(err)) end
      end
    end
  end
end
function BC.pending() return pendingBlizzard ~= nil end
function BC.state()
  local out = {}
  for _, cv in ipairs(CVARS) do
    local ok, on = pcall(C_CVar.GetCVarBitfield, cv.name, cv.bit)
    out[#out + 1] = (cv.name:find('Npc') and 'mobs ' or 'players ') .. (ok and (on and 'on' or 'off') or '?')
  end
  return table.concat(out, ', ')
end

-- ---------- Blizzard's squares on the target frame ----------
-- They live in TargetFrame...TargetFrameContentContextual.Auras, a TargetFrameAuraContainer (Forever source:
-- Blizzard_UnitFrame/Shared/TargetFrameAuraContainer.lua). Its filter string is ignored: ShouldShowAuraAsDebuff
-- decides, and on an enemy NPC it shows only your (and your pet's) debuffs plus ones NPCs cast; other players' DoTs
-- never show there. So on mobs 'All but my DoTs' turns the debuff row off and keeps the mob's buffs. On a player
-- target Blizzard shows everyone's debuffs, so there the row stays whole.
local function targetAuras()
  local c = TargetFrame and TargetFrame.TargetFrameContent and TargetFrame.TargetFrameContent.TargetFrameContentContextual
  return c and c.Auras
end
local function squaresNow()
  local db = rdb(); local au = targetAuras(); if not au or not db then return end
  local mode = db.squares or 'notmine'
  local onPlayer = UnitExists('target') and UnitIsPlayer('target')
  local ok, err = pcall(function()
    -- only touch Blizzard's container when the value really changes (fewer chances to taint it)
    local md = (mode == 'hide' or (mode == 'notmine' and not onPlayer)) and 0 or (MAX_TARGET_DEBUFFS or 16)
    local mb = mode == 'hide' and 0 or (MAX_TARGET_BUFFS or 32)
    if au:GetMaxDebuffs() ~= md then au:SetMaxDebuffs(md) end
    if au:GetMaxBuffs() ~= mb then au:SetMaxBuffs(mb) end
  end)
  if not ok then ns.error('squares: ' .. tostring(err)) end
end
local sqHooked
function BC.squaresApply()
  if not BC.started then return end
  if not sqHooked and TargetFrame and TargetFrame.ConfigureAuraContainer then
    sqHooked = true; hooksecurefunc(TargetFrame, 'ConfigureAuraContainer', function() squaresNow() end)   -- Blizzard re-sets the limits on every new target
  end
  squaresNow()
end

-- ---------- a warlock's session ----------
local function start()
  BC.started = true
  local ev = CreateFrame('Frame')
  ev:RegisterEvent('PLAYER_REGEN_ENABLED'); ev:RegisterEvent('PLAYER_LOGOUT')
  ev:SetScript('OnEvent', function(_, e)
    if e == 'PLAYER_REGEN_ENABLED' then
      if pendingBlizzard ~= nil then BC.blizzardRow(pendingBlizzard) end
    elseif e == 'PLAYER_LOGOUT' then
      -- Blizzard's own value goes back for the next character or an uninstall; the rings' login turns it off again
      local db = rdb()
      if db and db.saved and next(db.saved) then
        BC.blizzardRow(true)
        if pendingBlizzard ~= nil then pendingBlizzard = nil; ns.err('rings: logged out in combat, so Blizzard\'s nameplate debuffs could not be put back') end
      end
    end
  end)
end
ns.starts[#ns.starts + 1] = start
