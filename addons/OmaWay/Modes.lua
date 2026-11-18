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
-- 2026-11-17 (Joshua: "i didnt know it would reload my entire screen everytime"): never '/questie tracker show|hide'.
-- Those switch the tracker off at the root and ReloadUI(), and 'hide' also wipes Questie's tracked-quest list. Only
-- the tracker window's own Hide() / Show(), which reload nothing and keep every setting.
-- 2026-11-18 (Joshua: "when i turn it off questie collapses and tugs hides"): off folds the tracker to its header line
-- (its own Collapse / Expand, as clicking its header does), it never disappears.
local function questie(show)
  local L = _G.QuestieLoader
  local ok, T = pcall(function() return L and L:ImportModule('QuestieTracker') end)
  if not (ok and T) then return end
  if T.Show then pcall(T.Show, T) end
  if show then if T.Expand then pcall(T.Expand, T) end else if T.Collapse then pcall(T.Collapse, T) end end
end

-- the right-side column (2026-11-18, "get the guidelime tug thing under the questie tracker in the right side of the
-- screen"): the Questie tracker under the minimap, TUG's window docked under it at the tracker's width, so it follows
-- when the tracker folds or grows. A drag of either window still works; the dock comes back at the next login or
-- switch (right-click the minimap button > Dock guide under tracker: off to keep your own spots).
local DOCK_GAP = 6
function Mo.dock()
  local db = ns.db()
  if db.dock == false or InCombatLockdown() then return end
  local tracker, guide = _G.Questie_BaseFrame, _G.GuidelimeWindow
  if tracker and Minimap and not db.trackerPlaced then
    tracker:ClearAllPoints(); tracker:SetPoint('TOPRIGHT', Minimap, 'BOTTOMRIGHT', 12, -34)
    local p = Questie and Questie.db and Questie.db.profile
    if p then
      local s = tracker:GetEffectiveScale() / UIParent:GetEffectiveScale()
      local r, t = tracker:GetRight(), tracker:GetTop()
      local cx, cy = UIParent:GetCenter()
      if r and t and cx then p.TrackerLocation = { 'TOPRIGHT', 'UIParent', 'CENTER', r * s - cx, t * s - cy } end
    end
    db.trackerPlaced = true                             -- once: after that the tracker stays where you put it
  end
  if tracker and guide and guide:IsShown() then
    guide:ClearAllPoints(); guide:SetPoint('TOPRIGHT', tracker, 'BOTTOMRIGHT', 0, -DOCK_GAP)
    local w = tracker:GetWidth()
    if w and w > 200 then guide:SetWidth(w) end
  end
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
  if quest and C_Timer then C_Timer.After(.3, Mo.dock) end    -- after the guide window exists and the tracker has unfolded
  if ns.arrowChanged then ns.arrowChanged() end
  chipLook()
  if not quiet then ns.say(quest and 'guide, tracker and arrow on.' or 'guide and arrow off, tracker folded; damage meter on.') end
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
    local H = ns.hbd(); local x, y, m
    if H then x, y, m = H:GetPlayerZonePosition() end   -- ('H and H:f()' keeps only the first value: y came back nil)
    m = m or (H and H:GetPlayerZone())
    if m and x then ns.setWaypoint(m, x + .03, y - .03, { title = 'OmaWay test', from = 'OmaWay' }); ns.say('a test waypoint a little north-east of you.')
    else ns.say("the game won't say where you are here (inside a dungeon?).") end
  elseif cmd == 'icons' then
    -- every step type's icon, drawn by the game itself at 64 px on a black board, for the mockups (2026-11-18: "make
    -- sure you're using the right icons for each step"). Run again to close.
    if Mo.board then Mo.board:SetShown(not Mo.board:IsShown()); return end
    local L = {
      { 'Fly to', 'Interface\\GossipFrame\\TaxiGossipIcon' }, { 'Get flight point', 'Interface\\AddOns\\Guidelime\\Icons\\getflightpoint' },
      { 'Accept', 'Interface\\GossipFrame\\AvailableQuestIcon' }, { 'Turn in', 'Interface\\GossipFrame\\ActiveQuestIcon' },
      { 'Turn in (not done)', 'Interface\\GossipFrame\\IncompleteQuestIcon' }, { 'Complete', 'Interface\\GossipFrame\\WorkOrderGossipIcon' },
      { 'Kill', 'Interface\\GossipFrame\\BattleMasterGossipIcon' }, { 'Talk to', 'Interface\\GossipFrame\\ChatBubbleGossipIcon' },
      { 'Buy / collect', 'Interface\\GossipFrame\\VendorGossipIcon' }, { 'Use object', 'Interface\\GossipFrame\\BinderGossipIcon' },
      { 'Train', 'Interface\\GossipFrame\\TrainerGossipIcon' }, { 'Set hearth', 'Interface\\AddOns\\Guidelime\\Icons\\set_hearth' },
      { 'Hearth to', 'Interface\\AddOns\\Guidelime\\Icons\\hearth' }, { 'Repair', 'Interface\\AddOns\\Guidelime\\Icons\\repair' },
      { 'Zeppelin', 'Interface\\Icons\\INV_Misc_Bomb_08' }, { 'Boat', 'Interface\\Icons\\Spell_Frost_SummonWaterElemental' },
      { 'Go to', 'Interface\\Minimap\\Tracking\\None' }, { 'Note', 'Interface\\Icons\\INV_Misc_Note_01' },
    }
    local b = CreateFrame('Frame', 'OmaWayIconBoard', UIParent); Mo.board = b
    b:SetSize(6 * 150, 3 * 110); b:SetPoint('CENTER'); b:SetFrameStrata('FULLSCREEN_DIALOG')
    local bg = b:CreateTexture(nil, 'BACKGROUND'); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 1)
    for i, e in ipairs(L) do
      local c, r = (i - 1) % 6, math.floor((i - 1) / 6)
      local t = b:CreateTexture(nil, 'ARTWORK'); t:SetSize(64, 64); t:SetPoint('TOPLEFT', b, 'TOPLEFT', c * 150 + 43, -(r * 110 + 10)); t:SetTexture(e[2])
      local f = b:CreateFontString(nil, 'OVERLAY'); f:SetFont(STANDARD_TEXT_FONT, 12, ''); f:SetPoint('TOP', t, 'BOTTOM', 0, -4); f:SetText(e[1])
    end
    ns.say('icon board shown in the middle of the screen. /omaway icons again to close it.')
  elseif cmd == 'clear' then ns.clearWaypoint(); ns.say('waypoint cleared.')
  elseif cmd == 'why' then
    -- what OmaWay sees, in chat (2026-11-17: "i dont see the arrow or guide at all")
    local L = _G.QuestieLoader
    local log = ns.quests and ns.quests.questLog and ns.quests.questLog()
    local n = 0; if log then for _ in pairs(log) do n = n + 1 end end
    ns.say(('Questie: %s, quests in its log: %d. Guidelime: %s. Mode: %s.'):format(L and 'found' or 'NOT found', n,
      (Guidelime and GuidelimeDataChar) and (GuidelimeDataChar.mainFrameShowing and 'on, window open' or 'on, window closed') or 'off', mode))
    local okJ, j = pcall(function() return ns.quests and ns.quests.job() end)
    if not okJ then ns.say('nearest job: error ' .. tostring(j))
    elseif j then ns.say(('nearest job: %s (%s), %d yd, map %s'):format(tostring(j.title), tostring(j.line2), j.dist or -1, tostring(j.map)))
    else ns.say('nearest job: none found') end
    local w = ns.waypoint()
    ns.say(w and ('arrow target: %s, from %s; world position %s; distance %s'):format(tostring(w.title), tostring(w.from), w.wx and 'known' or 'UNKNOWN', tostring(ns.distance and ns.distance()))
      or 'arrow target: none (so no arrow)')
  else
    ns.say('mode: ' .. mode .. (db.mode == 'auto' and ' (automatic)' or ' (clicked)') .. (ns.standIn and '. Guidelime and Questie steer the arrow through its TomTom slot.' or '. TomTom is installed, so its own arrow is used.'))
    ns.say('/omaway quest | dungeon | auto | lock | unlock | reset | test | clear')
  end
end
