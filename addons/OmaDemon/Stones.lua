-- OmaDemon: Soulstone tracker and the three group chat lines (sheet 48 v2, approved 2026-11-13).
-- Tracker: your soul crystal (the Gem look you picked, brass cradle and all) with the time left, in the top-right
-- corner of the party/raid frame of whoever has YOUR Soulstone. On yourself: a smaller, separate socket at the end of
-- your gem row. Under a minute the time turns gold. Only our own frames are made; Blizzard's are only anchored to.
-- Chat lines (each its own switch, off by default; never sent when you're alone):
--   "Soulstone on <name>."   "summoning <name>, click the portal pls"   "healthstones ready, grab one"
local _, ns = ...

local LIFE = 30 * 60
local STONE_BUFFS = { 'Soulstone Resurrection', 'Soulstone' }
local db = function() return ns.groupDB() end

local stone            -- { name = 'Lindarra', guid = ..., ends = GetTime() + LIFE, placed = GetTime() }
local sentTarget       -- the name UNIT_SPELLCAST_SENT gave for our last cast

-- ---------- chat ----------
local function inGroup() local ok, v = pcall(IsInGroup); return ok and v end
local function say(msg)
  if not inGroup() then return end
  local ch = 'PARTY'
  local okI, inst = pcall(IsInGroup, LE_PARTY_CATEGORY_INSTANCE)
  if LE_PARTY_CATEGORY_INSTANCE and okI and inst then ch = 'INSTANCE_CHAT' elseif IsInRaid and IsInRaid() then ch = 'RAID' end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if send then pcall(send, msg, ch) end
end
local function short(name) if name and Ambiguate then local ok, n = pcall(Ambiguate, name, 'short'); if ok and n then return n end end; return name end

-- ---------- finding the group member and their frame ----------
local function units()
  local list = { 'player' }
  if IsInRaid and IsInRaid() then for i = 1, 40 do list[#list + 1] = 'raid' .. i end
  else for i = 1, 4 do list[#list + 1] = 'party' .. i end end
  return list
end
local function unitByName(name)
  if not name then return end
  for _, u in ipairs(units()) do
    local ok, same = pcall(function() return UnitExists(u) and short(UnitName(u)) == short(name) end)
    if ok and same then return u end
  end
end
local function unitByGUID(guid)
  if not guid then return end
  for _, u in ipairs(units()) do
    local ok, same = pcall(function() return UnitExists(u) and UnitGUID(u) == guid end)
    if ok and same then return u end
  end
end
local function frameFor(guid)
  local function is(f)
    if not f then return false end
    local ok, yes = pcall(function()
      if not f:IsVisible() then return false end
      local u = (type(f.displayedUnit) == 'string' and f.displayedUnit) or (type(f.unit) == 'string' and f.unit)
      return u and UnitGUID(u) == guid
    end)
    return ok and yes
  end
  for i = 1, 5 do local f = _G['CompactPartyFrameMember' .. i]; if is(f) then return f end end
  local pool = _G.PartyFrame and _G.PartyFrame.PartyMemberFramePool
  if pool and pool.EnumerateActive then for f in pool:EnumerateActive() do if is(f) then return f end end end
  for i = 1, 4 do local f = _G['PartyMemberFrame' .. i]; if is(f) then return f end end
  for g = 1, 8 do for m = 1, 5 do local f = _G['CompactRaidGroup' .. g .. 'Member' .. m]; if is(f) then return f end end end
  for i = 1, 40 do local f = _G['CompactRaidFrame' .. i]; if is(f) then return f end end
end

-- ---------- the crystal ----------
local holder = CreateFrame('Frame', 'OmaDemonSoulstone', UIParent); holder:SetSize(24, 24); holder:Hide()
holder:SetFrameStrata('MEDIUM'); holder:SetFrameLevel(30)
local sock = holder:CreateTexture(nil, 'ARTWORK', nil, 1)
local gem = holder:CreateTexture(nil, 'ARTWORK', nil, 2)
local clock = holder:CreateFontString(nil, 'OVERLAY'); clock:SetFont(STANDARD_TEXT_FONT, 11, 'OUTLINE'); clock:SetTextColor(1, 1, 1)
local function cell(t, c) t:SetTexCoord(c[1] / 512, c[2] / 512, c[3] / 256, c[4] / 256) end
local function paint()
  if not (ns.gemSheet and ns.gemCells) then return end
  local path = ns.gemSheet()
  sock:SetTexture(path); cell(sock, ns.gemCells.empty)
  gem:SetTexture(path); cell(gem, ns.gemCells.lit)
end

local mode
local function layout(where, anchor)
  holder:ClearAllPoints(); sock:ClearAllPoints(); gem:ClearAllPoints(); clock:ClearAllPoints()
  if where == 'self' then
    -- a sixth socket, set apart at the end of the gem row, in the row's own scale; the time under it
    holder:SetParent(anchor); holder:SetScale(1); holder:SetSize(24, 29)
    holder:SetPoint('LEFT', anchor, 'RIGHT', 4, 2)
    sock:SetSize(24, 29); sock:SetPoint('CENTER'); gem:SetSize(24, 29); gem:SetPoint('CENTER')
    clock:SetFont(STANDARD_TEXT_FONT, 15, 'OUTLINE'); clock:SetPoint('TOP', holder, 'BOTTOM', 0, 1)
  else
    -- top-right inside corner of their frame, time to the left of the crystal
    holder:SetParent(UIParent); holder:SetScale(1); holder:SetSize(15, 18)
    holder:SetPoint('TOPRIGHT', anchor, 'TOPRIGHT', -2, -2)
    sock:SetSize(15, 18); sock:SetPoint('CENTER'); gem:SetSize(15, 18); gem:SetPoint('CENTER')
    clock:SetFont(STANDARD_TEXT_FONT, 11, 'OUTLINE'); clock:SetPoint('RIGHT', holder, 'LEFT', 1, 0)
  end
  holder:SetFrameStrata('MEDIUM'); holder:SetFrameLevel(30)
  mode = where
end

local function clear() stone = nil; holder:Hide(); mode = nil end
local function place()
  if not stone or db().soulstone == false then holder:Hide(); return end
  local left = stone.ends - GetTime()
  if left <= 0 then clear(); return end
  local f = stone.guid and frameFor(stone.guid)
  if f then layout('party', f)
  elseif stone.guid and stone.guid == UnitGUID('player') and ns.gemRoot and ns.gemRoot:IsShown() then layout('self', ns.gemRoot)
  else holder:Hide(); return end
  holder:Show()
end

local function tick()
  if not stone then return end
  local left = stone.ends - GetTime()
  if left <= 0 then clear(); return end
  if left >= 60 then clock:SetText(math.ceil(left / 60) .. 'm'); clock:SetTextColor(1, 1, 1)
  else clock:SetText(math.ceil(left) .. 's'); clock:SetTextColor(1, .84, .35) end
end

-- out of combat (aura data can be secret in a fight): is our stone still on them? also finds one after a /reload
local function auraOn(u)
  for _, n in ipairs(STONE_BUFFS) do
    local ok, a = pcall(function()
      if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then return C_UnitAuras.GetAuraDataBySpellName(u, n, 'HELPFUL') end
    end)
    if ok and a then
      local mine = false
      pcall(function() mine = a.sourceUnit and UnitIsUnit(a.sourceUnit, 'player') end)
      if mine then return a end
    end
  end
end
local function audit()
  if InCombatLockdown() then return end
  if stone then
    local u = unitByGUID(stone.guid)
    if not stone.test and u and GetTime() - stone.placed > 5 and not auraOn(u) then clear(); return end
  else
    for _, u in ipairs(units()) do
      local a = UnitExists(u) and auraOn(u)
      if a then
        local ends = GetTime() + LIFE
        pcall(function() if a.expirationTime and a.expirationTime > 0 then ends = a.expirationTime end end)
        stone = { name = short(UnitName(u)), guid = UnitGUID(u), ends = ends, placed = GetTime() - 10 }
        paint(); place(); tick(); return
      end
    end
  end
end

-- ---------- our casts ----------
local lastStones = 0
local function spellName(id)
  local ok, n = pcall(function() return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id)) end)
  if ok and type(n) == 'string' then return n end
end
local function onCast(id)
  local name = spellName(id); if not name then return end
  local d = db()
  if name == 'Soulstone Resurrection' or (name:find('Soulstone', 1, true) and not name:find('Create', 1, true)) then
    local who = sentTarget or UnitName('target') or UnitName('player')
    local u = unitByName(who) or 'player'
    stone = { name = short(who), guid = UnitGUID(u), ends = GetTime() + LIFE, placed = GetTime() }
    paint(); place(); tick()
    if d.sayStone then say(('Soulstone on %s.'):format(stone.name)) end
  elseif name == 'Ritual of Summoning' then
    local who = sentTarget or UnitName('target')
    if d.saySummon and who and who ~= '' then say(('summoning %s, click the portal pls'):format(short(who))) end
  elseif name == 'Ritual of Souls' then   -- only the group stones; a Create Healthstone is just for you
    if d.sayStones and GetTime() - lastStones > 60 then lastStones = GetTime(); say('healthstones ready, grab one') end
  end
end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_LOGIN', 'UNIT_SPELLCAST_SENT', 'UNIT_SPELLCAST_SUCCEEDED', 'GROUP_ROSTER_UPDATE',
  'PLAYER_REGEN_ENABLED', 'PLAYER_ENTERING_WORLD' }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript('OnEvent', function(_, e, unit, a2, a3, a4)
  if e == 'PLAYER_LOGIN' then
    if select(2, UnitClass('player')) ~= 'WARLOCK' then ev:UnregisterAllEvents(); return end
    paint(); C_Timer.After(3, audit)
  elseif e == 'UNIT_SPELLCAST_SENT' then
    if unit == 'player' then pcall(function() sentTarget = (type(a2) == 'string' and a2 ~= '') and a2 or nil end) end
  elseif e == 'UNIT_SPELLCAST_SUCCEEDED' then
    if unit == 'player' then onCast(a3); sentTarget = nil end
  elseif e == 'GROUP_ROSTER_UPDATE' or e == 'PLAYER_ENTERING_WORLD' then
    C_Timer.After(.5, place)
  elseif e == 'PLAYER_REGEN_ENABLED' then
    audit(); place()
  end
end)

local acc, auditAcc = 0, 0
holder:SetScript('OnUpdate', function(_, dt)
  acc = acc + dt; auditAcc = auditAcc + dt
  if acc >= .5 then acc = 0; tick() end
  if auditAcc >= 3 then auditAcc = 0; audit(); place() end
end)
-- the holder only runs while shown: a slow outside clock keeps placing it (frames come and go in a group)
if C_Timer.NewTicker then C_Timer.NewTicker(2, function() if stone and not holder:IsShown() then place() end end) end

table.insert(ns.onSetting, function(key, store)
  if store == 'shards' and key == 'gemLook' then paint() end
  if store == 'shards' and (key == 'gems' or key == 'size' or key == 'pin') then C_Timer.After(.1, place) end
  if store == 'group' and key == 'soulstone' then place() end
end)

-- /omademon stone test: a 90-second stone on yourself (solo socket) to see it
function ns.stoneTest(target)
  local u = unitByName(target) or 'player'
  stone = { name = short(UnitName(u)), guid = UnitGUID(u), ends = GetTime() + 90, placed = GetTime(), test = true }
  paint(); place(); tick()
  ns.say('test Soulstone on ' .. tostring(stone.name) .. ' for 90 s')
end
