-- OmaChat: chat for the phone remote: new chat goes out as a thin line of coloured pixels along the very bottom-left
-- edge of the screen, and Couch Mode reads it back letter for letter. WoW's own chat log can't be used: WoW writes
-- it only when the game closes (tested 2026-11-09); research 2026-11-11 (reports/WoW live chat out of game.md)
-- found no better live route.
--
-- The strip (version 2, 2026-11-11): ONE row of 1x1 screen pixels on the bottom edge. Pixel 1 magenta, pixel 2 cyan,
-- pixel 3 = (2, 79, 77) ("v2"), then 3 bytes per pixel in red, green, blue (every level 0-255 arrives exactly: the
-- /omachat ramp test, 768 of 768). The bytes:
--   flags (1: chat box open, 2: aux's search box is on screen, 4: aux's search box has the keyboard) | how many lines (1) |
--   each line: number (2) + length (2) + speaker's class (1: 0 unknown, else WoW's class ID) + UTF-8 |
--   check (2: CRC-16/CCITT of every byte before it)
-- It always shows the NEWEST lines that fit (300 bytes, about 105 pixels), so a line stays on the strip for several
-- looks and Couch Mode loses nothing if it misses a moment; it keeps the lines whose number it hasn't had yet.
-- Version 1 (2x2 blocks, 6 bits each) was about 15 times the area; Couch Mode still reads both.
-- Lines are in WoWChatLog.txt's own format (that's what Aang reads).
local ROOM, GAP = 300, 0.15   -- bytes of lines on the strip, seconds between redraws

local strip = CreateFrame("Frame", "OmashuStrip", UIParent)
strip:SetFrameStrata("TOOLTIP"); strip:SetFrameLevel(10000)
strip:SetIgnoreParentScale(true); strip:SetScale(1)
local blocks, recent, nextId, drawnAt, dirty, lastFlags = {}, {}, 0, 0, true, nil

local function u16(t, n) t[#t + 1] = math.floor(n / 256) % 256; t[#t + 1] = n % 256 end
local function crc16(bytes)   -- CRC-16/CCITT-FALSE: catches torn or half-drawn frames the old sum let through
  local c = 0xFFFF
  for _, b in ipairs(bytes) do
    c = bit.bxor(c, bit.lshift(b, 8))
    for _ = 1, 8 do
      if bit.band(c, 0x8000) ~= 0 then c = bit.band(bit.bxor(bit.lshift(c, 1), 0x1021), 0xFFFF) else c = bit.band(bit.lshift(c, 1), 0xFFFF) end
    end
  end
  return c
end
local function draw(bytes)
  u16(bytes, crc16(bytes))
  local cols = { { 255, 0, 255 }, { 0, 255, 255 }, { 2, 79, 77 } }
  for i = 1, #bytes, 3 do cols[#cols + 1] = { bytes[i], bytes[i + 1] or 0, bytes[i + 2] or 0 } end
  local _, ph = GetPhysicalScreenSize()
  local px = 768 / ph / strip:GetEffectiveScale()   -- one screen pixel in this frame's units
  strip:ClearAllPoints(); strip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  strip:SetSize(#cols * px, px)
  for i, c in ipairs(cols) do
    local t = blocks[i]
    if not t then
      t = strip:CreateTexture(nil, "OVERLAY"); blocks[i] = t
      if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
    end
    t:ClearAllPoints(); t:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", (i - 1) * px, 0)
    t:SetSize(px, px); t:SetColorTexture(c[1] / 255, c[2] / 255, c[3] / 255, 1); t:Show()
  end
  for i = #cols + 1, #blocks do blocks[i]:Hide() end
end

local function boxOpen() return ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() and 1 or 0 end

-- Auction search from the phone (sheet omashu/remote/14). aux keeps its search box private, so it's found on screen:
-- the EditBox carrying aux's own enter/complete/char handlers (aux's search bar is the only one with all three).
-- While it's on screen, Ctrl+Shift+F11 (a binding only while the auction house is open) puts the keyboard in it,
-- empty, so Couch Mode can type the search and press Enter (aux's own search). Couch Mode types only after the strip
-- says the box has the keyboard (flag 4), so letters never reach the game's key bindings.
local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded") or function() return false end
local auxBox, lookedAt = nil, 0
local function findAuxBox()
  if auxBox then return auxBox end
  if GetTime() - lookedAt < 1 then return nil end   -- the scan walks every frame: at most once a second
  lookedAt = GetTime()
  if not loaded("auxForever") then return nil end   -- no aux: never walk every frame for nothing
  local f = EnumerateFrames()
  while f do
    if f.IsObjectType and f:IsObjectType("EditBox") and type(f.enter) == "function" and type(f.complete) == "function"
      and type(f.char) == "function" then auxBox = f; return f end
    f = EnumerateFrames(f)
  end
end
local ahOpen = false
-- ImprovedForever's auction house (Joshua 2026-11-26: the one auction house now, aux off). Its own search box only
-- shows in mouse mode, so the phone types into a hidden box of ours; Enter searches every category in its Buy tab
-- (ImprovedForever.AuctionBuy: main 0 = no category filter, search, Query). "name/exact" (aux's form) is cut to the name.
local function improved() local IF = rawget(_G, "ImprovedForever"); return IF and IF.AuctionBuy end
local ourBox = CreateFrame("EditBox", "OmashuAhSearchBox", UIParent)
ourBox:SetSize(4, 4); ourBox:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0); ourBox:SetAlpha(0)
ourBox:SetAutoFocus(false); ourBox:SetFontObject(ChatFontNormal); ourBox:SetMaxLetters(60); ourBox:Hide()
ourBox:SetScript("OnEscapePressed", function(b) b:SetText(""); b:ClearFocus() end)
ourBox:SetScript("OnEnterPressed", function(b)
  local text = (b:GetText() or ""):gsub("/exact$", ""):gsub("^%s+", ""):gsub("%s+$", "")
  b:SetText(""); b:ClearFocus()
  local B = improved()
  if text == "" or not B then return end
  if B.SetTab then pcall(B.SetTab, "buy") end
  B.main, B.sub, B.subsub, B.search = 0, 1, 1, text
  pcall(B.Query)
end)
local function searchBox()
  if improved() and loaded("ImprovedForever_Auction") then return ourBox end
  return findAuxBox()
end
local focusBtn = CreateFrame("Button", "OmashuAuxSearchFocus", UIParent)
focusBtn:SetScript("OnClick", function()
  local b = ahOpen and searchBox()
  if b then b:Show() end
  if b and b:IsVisible() then b:SetFocus(); b:SetText(""); b:SetCursorPosition(0) end
end)
local KEY = "CTRL-SHIFT-F11"
local ahEv = CreateFrame("Frame")
ahEv:RegisterEvent("AUCTION_HOUSE_SHOW"); ahEv:RegisterEvent("AUCTION_HOUSE_CLOSED")
ahEv:SetScript("OnEvent", function(_, e)
  if e ~= "PLAYER_REGEN_ENABLED" then ahOpen = (e == "AUCTION_HOUSE_SHOW") end
  if ahOpen and improved() then ourBox:Show() else ourBox:ClearFocus(); ourBox:Hide() end
  if InCombatLockdown() then ahEv:RegisterEvent("PLAYER_REGEN_ENABLED"); return end   -- set (or cleared) once combat ends
  ahEv:UnregisterEvent("PLAYER_REGEN_ENABLED")
  if ahOpen then SetOverrideBindingClick(focusBtn, true, KEY, "OmashuAuxSearchFocus") else ClearOverrideBindings(focusBtn) end
end)
local function auxFlags()
  if not ahOpen then return 0 end
  local b = searchBox()
  if not (b and b:IsVisible()) then return 0 end
  return 2 + (b:HasFocus() and 4 or 0)
end

-- The newest lines that fit, oldest first.
local function packet(flags)
  local pick, used = {}, 0
  for i = #recent, 1, -1 do
    local l = recent[i]
    if used + #l.text + 5 > ROOM then break end
    table.insert(pick, 1, l); used = used + #l.text + 5
  end
  local bytes = { flags, #pick }
  for _, l in ipairs(pick) do
    u16(bytes, l.id); u16(bytes, #l.text); bytes[#bytes + 1] = l.cls or 0
    for i = 1, #l.text do bytes[#bytes + 1] = l.text:byte(i) end
  end
  return bytes
end

strip:SetScript("OnUpdate", function()
  local now, flags = GetTime(), boxOpen() + auxFlags()
  if flags ~= lastFlags then dirty = true end
  if dirty and now - drawnAt >= GAP then draw(packet(flags)); drawnAt = now; dirty = false; lastFlags = flags end
end)

-- Chat events, written the way WoWChatLog.txt writes them (that's what Aang reads).
local LABEL = {
  CHAT_MSG_GUILD = "Guild", CHAT_MSG_OFFICER = "Officer", CHAT_MSG_PARTY = "Party", CHAT_MSG_PARTY_LEADER = "Party Leader",
  CHAT_MSG_RAID = "Raid", CHAT_MSG_RAID_LEADER = "Raid Leader", CHAT_MSG_RAID_WARNING = "Raid Warning",
  CHAT_MSG_INSTANCE_CHAT = "Instance", CHAT_MSG_INSTANCE_CHAT_LEADER = "Instance Leader",
}
local function short(name) return (Ambiguate and name and Ambiguate(name, "short")) or name or "" end
local function body(event, text, who, _, _, _, _, _, chanNum, chanName)
  who = short(who)
  if LABEL[event] then return "[" .. LABEL[event] .. "] " .. who .. ": " .. text end
  if event == "CHAT_MSG_CHANNEL" then return "[" .. chanNum .. ". " .. chanName .. "] " .. who .. ": " .. text end
  if event == "CHAT_MSG_SAY" then return who .. " says: " .. text end
  if event == "CHAT_MSG_YELL" then return who .. " yells: " .. text end
  if event == "CHAT_MSG_WHISPER" then return who .. " whispers: " .. text end
  if event == "CHAT_MSG_WHISPER_INFORM" then return "To " .. who .. ": " .. text end
  if event == "CHAT_MSG_EMOTE" then return who .. " " .. text end
  if event == "CHAT_MSG_ACHIEVEMENT" or event == "CHAT_MSG_GUILD_ACHIEVEMENT" then return (text:gsub("%%s", who)) end
  return text   -- system, text emotes
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
  "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_SYSTEM", "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT",
  "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
  "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do f:RegisterEvent(e) end
f:RegisterEvent("PLAYER_ENTERING_WORLD"); f:RegisterEvent("DISPLAY_SIZE_CHANGED"); f:RegisterEvent("UI_SCALE_CHANGED")
-- Locked chat (2026-11-11, research 'WoW live chat out of game'): Forever has Midnight's "secret values". In boss
-- fights, Mythic+, PvP and some instances a chat line reaches add-ons locked: it can be shown but not read, so it
-- can't go on the strip (counting or reading its letters is an error). Such lines are skipped, and the phone gets
-- one plain line saying chat is hidden here, at most every 30 s.
local function locked(v) return issecretvalue and v ~= nil and issecretvalue(v) or false end
-- The speaker's class for the phone's name colours (2026-11-11, Joshua: "On the phone I'd like to see colours"): the
-- chat event's 12th value is the speaker's GUID; GetPlayerInfoByGUID gives back the English class name, sent as WoW's
-- class ID. 0 = unknown (system lines, NPCs, locked chat, a player WoW has no info on yet).
local CLASSID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8,
  WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13 }
local function classOf(guid)
  if type(guid) ~= "string" or guid == "" or locked(guid) or not GetPlayerInfoByGUID then return 0 end
  local ok, _, eng = pcall(GetPlayerInfoByGUID, guid)
  if not ok or locked(eng) then return 0 end
  return CLASSID[eng] or 0
end
local hiddenAt = -1e9
local function onLocked()
  local now = GetTime(); if now - hiddenAt < 30 then return end
  hiddenAt = now
  recent[#recent + 1] = { id = (nextId % 65535) + 1, text = date("%m/%d %H:%M:%S") .. string.format(".%03d", math.floor((now % 1) * 1000))
    .. "  OmaChat: chat is hidden here (WoW keeps chat from add-ons in this fight or instance)" }
  nextId = (nextId % 65535) + 1
  if #recent > 40 then table.remove(recent, 1) end
  dirty = true
end
-- "No player named X is currently playing" from other add-ons' hidden messages (Mastercraft's crafter network asks
-- players nearby; Joshua 2026-11-26: keep the network, hide the noise): hidden in game chat and on the phone. A name
-- he whispered himself in the last 30 s still shows, so he still learns his friend is offline.
local mine = {}
local function short(n) n = n:gsub("%-.*$", ""); return n:lower() end   -- "Bob-Realm" and "Bob" are the same friend
local function sent(_, kind, _, target) if kind == "WHISPER" and type(target) == "string" then mine[short(target)] = GetTime() end end
if hooksecurefunc then
  hooksecurefunc("SendChatMessage", sent)                                  -- older chat code
  if C_ChatInfo and C_ChatInfo.SendChatMessage then hooksecurefunc(C_ChatInfo, "SendChatMessage", sent) end   -- newer
end
local NOT_FOUND = (ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."):gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)")
local function noise(text)
  if type(text) ~= "string" then return false end
  local name = text:match("^" .. NOT_FOUND .. "$")
  if not name then return false end
  local at = mine[short(name)]
  return not (at and GetTime() - at < 30)
end
if ChatFrame_AddMessageEventFilter then
  ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, text) if noise(text) then return true end end)
end
f:SetScript("OnEvent", function(_, event, ...)
  if event:sub(1, 9) ~= "CHAT_MSG_" then dirty = true; return end   -- screen changed: redraw
  if event == "CHAT_MSG_SYSTEM" and noise((...)) then return end
  local text0, who0, _, _, _, _, _, _, chan0 = ...
  if locked(text0) or locked(who0) or locked(chan0) then return onLocked() end
  local ok, b = pcall(body, event, ...)
  if not ok or locked(b) or type(b) ~= "string" or b == "" then return end
  local cls = classOf(select(12, ...))
  local t = GetTime()
  local text = date("%m/%d %H:%M:%S") .. string.format(".%03d", math.floor((t % 1) * 1000)) .. "  " .. b
  if #text > ROOM - 5 then text = text:sub(1, ROOM - 5) end
  nextId = (nextId % 65535) + 1
  recent[#recent + 1] = { id = nextId, text = text, cls = cls }
  if #recent > 40 then table.remove(recent, 1) end
  dirty = true
end)

-- ---------- Guild, who's on (phone sheet 11, Joshua 2026-11-10) ----------
-- The online guild list rides the same strip as chat lines, one member per line, trickled out (one line every half
-- second) so a burst never pushes chat off the strip:   {omashu-guild} <list> <i>/<n> Name|level|CLASS|zone
-- <list> numbers each full list; Aang swaps its list in only once it has all n lines of one. "<list> 0/0" = nobody
-- (or not in a guild). Sent when the list changes and again every 60 s; WoW is asked for a fresh roster every 30 s.
local TAG, queue, lastSig, listNo, trickleAt = "{omashu-guild} ", {}, nil, 0, 0
local function stamp() local t = GetTime(); return date("%m/%d %H:%M:%S") .. string.format(".%03d", math.floor((t % 1) * 1000)) .. "  " end
local function push(text)
  if #text > ROOM - 5 then text = text:sub(1, ROOM - 5) end
  nextId = (nextId % 65535) + 1
  recent[#recent + 1] = { id = nextId, text = text }
  if #recent > 40 then table.remove(recent, 1) end
  dirty = true
end
local function clean(s) return (tostring(s or ""):gsub("[|\r\n]", " ")) end
local function onlineList()
  local out, me = {}, UnitName("player")
  if not (IsInGuild and IsInGuild()) then return out end
  for i = 1, (GetNumGuildMembers() or 0) do
    local name, _, _, level, _, zone, _, _, online, _, class = GetGuildRosterInfo(i)
    if name and online then out[#out + 1] = { n = short(name), l = tonumber(level) or 0, c = class or "", z = zone or "" } end
  end
  table.sort(out, function(a, b)
    if (a.n == me) ~= (b.n == me) then return b.n == me end      -- you at the bottom
    if a.l ~= b.l then return a.l > b.l end                      -- highest level first
    return a.n < b.n
  end)
  return out
end
local function sendList()
  local list, parts = onlineList(), {}
  for _, m in ipairs(list) do parts[#parts + 1] = m.n .. "|" .. m.l .. "|" .. m.c .. "|" .. clean(m.z) end
  local sig = table.concat(parts, ";")
  if sig == lastSig then return end
  lastSig = sig; listNo = (listNo % 9999) + 1; queue = {}
  if #list == 0 then queue[1] = TAG .. listNo .. " 0/0" end
  for i, p in ipairs(parts) do queue[#queue + 1] = TAG .. listNo .. " " .. i .. "/" .. #parts .. " " .. p end
end
local g = CreateFrame("Frame")
g:RegisterEvent("PLAYER_ENTERING_WORLD"); g:RegisterEvent("GUILD_ROSTER_UPDATE"); g:RegisterEvent("PLAYER_GUILD_UPDATE")
g:SetScript("OnEvent", function(_, e) if e == "PLAYER_ENTERING_WORLD" then lastSig = nil end; pcall(sendList) end)
local asked = 0
g:SetScript("OnUpdate", function()
  local now = GetTime()
  -- every 60 s the whole list goes again even if unchanged: a reader that missed part of it (Couch Mode restarting,
  -- a reload) still gets a complete list within a minute (2026-11-10: lines 1-4 of 7 were missed after a reload)
  if now - (g.full or 0) > 60 and #queue == 0 then g.full = now; lastSig = nil; pcall(sendList) end
  if now - asked > 30 then asked = now; if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end end
  if #queue > 0 and now - trickleAt >= 0.5 then trickleAt = now; push(stamp() .. table.remove(queue, 1)) end
end)


-- ---------- /omachat ramp: a 15 s colour test for a thinner strip (2026-11-11) ----------
-- Three 1-pixel rows at the bottom-left edge, each 256 pixels long: row 1 red 0..255, row 2 green, row 3 blue, one
-- level per pixel. A screen capture then shows whether every level arrives exactly (needed for 8 bits per channel).
local ramp
SLASH_OMACHAT1 = "/omachat"
SlashCmdList.OMACHAT = function(m)
  if (m or ""):lower() ~= "ramp" then print("|cffb48cffOmaChat:|r /omachat ramp  shows a 15 s colour test at the bottom-left"); return end
  if not ramp then
    ramp = CreateFrame("Frame", nil, UIParent); ramp:SetFrameStrata("TOOLTIP"); ramp:SetFrameLevel(10001)
    ramp:SetIgnoreParentScale(true); ramp:SetScale(1); ramp.t = {}
  end
  local _, ph = GetPhysicalScreenSize()
  local px = 768 / ph / ramp:GetEffectiveScale()
  ramp:ClearAllPoints(); ramp:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0); ramp:SetSize(256 * px, 3 * px)
  local k = 0
  for row = 1, 3 do
    for v = 0, 255 do
      k = k + 1
      local t = ramp.t[k] or ramp:CreateTexture(nil, "OVERLAY"); ramp.t[k] = t
      if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
      t:ClearAllPoints(); t:SetPoint("BOTTOMLEFT", ramp, "BOTTOMLEFT", v * px, (3 - row) * px); t:SetSize(px, px)
      local c = v / 255
      t:SetColorTexture(row == 1 and c or 0, row == 2 and c or 0, row == 3 and c or 0, 1); t:Show()
    end
  end
  strip:Hide(); ramp:Show()
  print("|cffb48cffOmaChat:|r colour test on for 15 s (the chat strip is paused)")
  C_Timer.After(15, function() ramp:Hide(); strip:Show() end)
end
