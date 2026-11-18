-- OmaWay modes (sheet 111, approved 2026-11-17): quest stuff on (quest mode) or off (dungeon mode).
--   On:  the Guidelime guide, its arrow (OmaWay's) and the Questie tracker show; the Details meter is put away.
--   Off: the guide, the arrow and the tracker are hidden completely ("Hide both completely"); Details shows.
-- It switches by itself inside dungeons only ("Inside a dungeon only"). One control (2026-11-17, "these should all be
-- one thing"; the QUEST / DUNGEON chip is gone): the minimap button's left-click turns it all on or off together. A
-- click holds until you next go in or out of a dungeon, then the automatic choice takes over again.
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

local function chipLook() if ns.minimap and ns.minimap.refresh then ns.minimap.refresh() end end   -- the button shows the state

function Mo.apply(m, quiet)
  mode = m
  if InCombatLockdown() then pending = true; chipLook(); return end   -- the other windows wait for the fight's end
  pending = false
  local quest = m == 'quest'
  guidelime(quest); questie(quest); details(not quest)
  if ns.arrowChanged then ns.arrowChanged() end
  chipLook()
  if not quiet then ns.say(quest and 'guide, tracker and arrow on.' or 'guide, tracker and arrow off; damage meter on.') end
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

-- a click on the minimap button: everything on or off together, held until the next dungeon door
function Mo.toggle() local db = ns.db(); local m = mode == 'quest' and 'dungeon' or 'quest'; db.mode = m; Mo.apply(m) end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'ZONE_CHANGED_NEW_AREA', 'PLAYER_REGEN_ENABLED' }) do ev:RegisterEvent(e) end
ev:SetScript('OnEvent', function(_, e)
  if e == 'PLAYER_LOGIN' then return end
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
