-- OmaWay modes (sheet 111, approved 2026-11-17): quest mode and dungeon mode.
--   Quest:   the Guidelime guide, its arrow (OmaWay's) and the Questie tracker show; the Details meter is put away.
--   Dungeon: the guide, the arrow and the tracker are hidden completely ("Hide both completely"); Details shows.
-- It switches by itself inside dungeons only (not in a plain group: "Inside a dungeon only"). A small QUEST / DUNGEON
-- chip under the minimap shows the mode; a click switches it ("Chip click only": no key binding). A click holds until
-- you next go in or out of a dungeon, then the automatic choice takes over again.
local ADDON, ns = ...
local Mo = {}; ns.modes = Mo
local mode = 'quest'
local wasInside
local pending = false

local function inDungeon()
  local ok, inside, kind = pcall(IsInInstance)
  return ok and inside and (kind == 'party' or kind == 'raid') or false
end
function Mo.current() return mode end
function Mo.allowArrow() return mode == 'quest' end

-- the other add-ons, each only if it's there; nothing fails if one is missing
local function guidelime(show)
  if not (Guidelime and Guidelime.toggleMainFrame and GuidelimeDataChar) then return end
  if (GuidelimeDataChar.mainFrameShowing and true or false) ~= show then pcall(Guidelime.toggleMainFrame) end
end
local function questie(show)
  local f = SlashCmdList and SlashCmdList.ACECONSOLE_QUESTIE
  if f then pcall(f, show and 'tracker show' or 'tracker hide') end
end
local function details(show)
  local f = SlashCmdList and SlashCmdList.DETAILS
  if f then pcall(f, show and 'show' or 'hide') end
end

local chip
local function chipLook()
  if not chip then return end
  local q, d = chip.q, chip.d
  local gold, dim = { 1, .82, 0 }, { .6, .56, .48 }
  local a, b = mode == 'quest' and gold or dim, mode == 'dungeon' and gold or dim
  q:SetTextColor(a[1], a[2], a[3]); d:SetTextColor(b[1], b[2], b[3])
  chip.qBg:SetAlpha(mode == 'quest' and 1 or 0); chip.dBg:SetAlpha(mode == 'dungeon' and 1 or 0)
end

function Mo.apply(m, quiet)
  mode = m
  if InCombatLockdown() then pending = true; chipLook(); return end   -- the other windows wait for the fight's end
  pending = false
  local quest = m == 'quest'
  guidelime(quest); questie(quest); details(not quest)
  if ns.arrowChanged then ns.arrowChanged() end
  chipLook()
  if not quiet then ns.say((quest and 'quest' or 'dungeon') .. ' mode.') end
end

local function auto(force)
  local inside = inDungeon()
  if force or inside ~= wasInside then
    wasInside = inside
    local db = ns.db()
    db.mode = 'auto'                                  -- going in or out of a dungeon ends a clicked choice
    Mo.apply(inside and 'dungeon' or 'quest', false)
  end
end

local function buildChip()
  if not Minimap then return end
  chip = CreateFrame('Button', 'OmaWayModeChip', Minimap, BackdropTemplateMixin and 'BackdropTemplate')
  chip:SetSize(124, 18); chip:SetPoint('TOP', Minimap, 'BOTTOM', 0, -14); chip:SetFrameStrata('MEDIUM')
  if chip.SetBackdrop then
    chip:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 1 })
    chip:SetBackdropColor(0, 0, 0, .7); chip:SetBackdropBorderColor(.42, .33, .13, 1)
  end
  local function half(side)
    local bg = chip:CreateTexture(nil, 'ARTWORK'); bg:SetColorTexture(.35, .26, .06, .85)
    bg:SetPoint('TOP', chip, 'TOP', 0, -1); bg:SetPoint('BOTTOM', chip, 'BOTTOM', 0, 1)
    if side == 'L' then bg:SetPoint('LEFT', chip, 'LEFT', 1, 0); bg:SetPoint('RIGHT', chip, 'CENTER', 0, 0)
    else bg:SetPoint('LEFT', chip, 'CENTER', 0, 0); bg:SetPoint('RIGHT', chip, 'RIGHT', -1, 0) end
    local t = chip:CreateFontString(nil, 'OVERLAY'); t:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF', 10, '')
    t:SetPoint('CENTER', bg, 'CENTER', 0, 0); t:SetShadowColor(0, 0, 0, 1); t:SetShadowOffset(1, -1)
    return bg, t
  end
  chip.qBg, chip.q = half('L'); chip.dBg, chip.d = half('R')
  chip.q:SetText('QUEST'); chip.d:SetText('DUNGEON')
  chip:RegisterForClicks('LeftButtonUp')
  chip:SetScript('OnClick', function() local db = ns.db(); local m = mode == 'quest' and 'dungeon' or 'quest'; db.mode = m; Mo.apply(m) end)
  chip:SetScript('OnEnter', function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, 'ANCHOR_BOTTOM'); GameTooltip:SetText('OmaWay mode', 1, .82, 0)
    GameTooltip:AddLine('Quest: guide, arrow and Questie tracker; no damage meter.', 1, 1, 1, true)
    GameTooltip:AddLine('Dungeon: guide, arrow and tracker put away; damage meter shows.', 1, 1, 1, true)
    GameTooltip:AddLine('Switches by itself in dungeons. Click to switch now.', .6, .6, .6, true)
    GameTooltip:Show()
  end)
  chip:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
  chipLook()
end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'ZONE_CHANGED_NEW_AREA', 'PLAYER_REGEN_ENABLED' }) do ev:RegisterEvent(e) end
ev:SetScript('OnEvent', function(_, e)
  if e == 'PLAYER_LOGIN' then buildChip(); return end
  if e == 'PLAYER_REGEN_ENABLED' then if pending then Mo.apply(mode, true) end; return end
  local db = ns.db()
  if e == 'PLAYER_ENTERING_WORLD' and wasInside == nil then
    -- a login or /reload: a clicked choice made in this same place holds; otherwise the place decides
    wasInside = inDungeon()
    if db.mode == 'quest' or db.mode == 'dungeon' then Mo.apply(db.mode, true) else Mo.apply(wasInside and 'dungeon' or 'quest', true) end
    return
  end
  auto(false)
end)

-- ---------- /omaway ----------
SLASH_OMAWAY1 = '/omaway'
SlashCmdList.OMAWAY = function(msg)
  local cmd, arg = (msg or ''):lower():match('^(%S*)%s*(.-)$')
  local db = ns.db()
  if cmd == 'quest' or cmd == 'dungeon' then db.mode = cmd; Mo.apply(cmd)
  elseif cmd == 'auto' then auto(true); ns.say('mode follows dungeons again.')
  elseif cmd == 'lock' then db.locked = true; ns.arrow.look(); ns.say('arrow locked.')
  elseif cmd == 'unlock' then db.locked = false; ns.arrow.look(); ns.say('arrow unlocked: drag it, size it with the //// corner.')
  elseif cmd == 'reset' then ns.arrow.reset()
  elseif cmd == 'test' then
    local H = ns.hbd(); local m = H and H:GetPlayerZone(); local x, y = H and H:GetPlayerZonePosition()
    if m and x then ns.setWaypoint(m, x + .03, y - .03, { title = 'OmaWay test', from = 'OmaWay' }); ns.say('a test waypoint a little north-east of you.')
    else ns.say("the game won't say where you are here (inside a dungeon?).") end
  elseif cmd == 'clear' then ns.clearWaypoint(); ns.say('waypoint cleared.')
  else
    ns.say('mode: ' .. mode .. (db.mode == 'auto' and ' (automatic)' or ' (clicked)') .. (ns.standIn and '. Guidelime and Questie steer the arrow through its TomTom slot.' or '. TomTom is installed, so its own arrow is used.'))
    ns.say('/omaway quest | dungeon | auto | lock | unlock | reset | test | clear')
  end
end
