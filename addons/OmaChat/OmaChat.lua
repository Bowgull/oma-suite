-- OmaChat: chat for the phone remote: new chat goes out as a thin strip of coloured blocks along the bottom-left
-- edge of the screen, and Couch Mode reads it back letter for letter. WoW's own chat log can't be used: WoW writes
-- it only when the game closes (tested 2026-11-09).
--
-- The strip: blocks of 2x2 screen pixels on the bottom two rows. Block 1 magenta, block 2 cyan (the start), then
-- 6 bits per block, 2 in each of red, green and blue as 0 / 85 / 170 / 255. The bytes:
--   flags (1: chat box open, 2: aux's search box is on screen, 4: aux's search box has the keyboard) | how many lines (1) | each line: number (2) + length (2) + UTF-8 |
--   check (2: sum of every byte before it)
-- It always shows the NEWEST lines that fit (300 bytes, at most ~40% of the screen width), so a line stays on the strip for several looks and
-- Couch Mode loses nothing if it misses a moment; it keeps the lines whose number it hasn't had yet.
-- Lines are in WoWChatLog.txt's own format (that's what Aang reads).
local W, H, ROOM, GAP = 2, 2, 300, 0.15   -- block size (px), bytes of lines on the strip, seconds between redraws

local strip = CreateFrame("Frame", "OmashuStrip", UIParent)
strip:SetFrameStrata("TOOLTIP"); strip:SetFrameLevel(10000)
strip:SetIgnoreParentScale(true); strip:SetScale(1)
local blocks, recent, nextId, drawnAt, dirty, lastFlags = {}, {}, 0, 0, true, nil

local function u16(t, n) t[#t + 1] = math.floor(n / 256) % 256; t[#t + 1] = n % 256 end
local function draw(bytes)
  local sum = 0
  for _, b in ipairs(bytes) do sum = sum + b end
  u16(bytes, sum % 65536)
  local cols, acc, nb = { {1, 0, 1}, {0, 1, 1} }, 0, 0
  local function sym(s) cols[#cols + 1] = { math.floor(s / 16) / 3, (math.floor(s / 4) % 4) / 3, (s % 4) / 3 } end
  for _, b in ipairs(bytes) do
    acc = acc * 256 + b; nb = nb + 8
    while nb >= 6 do nb = nb - 6; local s = math.floor(acc / 2 ^ nb); sym(s); acc = acc - s * 2 ^ nb end
  end
  if nb > 0 then sym(acc * 2 ^ (6 - nb)) end
  local _, ph = GetPhysicalScreenSize()
  local px = 768 / ph / strip:GetEffectiveScale()   -- one screen pixel in this frame's units
  strip:ClearAllPoints(); strip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  strip:SetSize(#cols * W * px, H * px)
  for i, c in ipairs(cols) do
    local t = blocks[i]
    if not t then
      t = strip:CreateTexture(nil, "OVERLAY"); blocks[i] = t
      if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
    end
    t:ClearAllPoints(); t:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", (i - 1) * W * px, 0)
    t:SetSize(W * px, H * px); t:SetColorTexture(c[1], c[2], c[3], 1); t:Show()
  end
  for i = #cols + 1, #blocks do blocks[i]:Hide() end
end

local function boxOpen() return ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() and 1 or 0 end

-- Auction search from the phone (sheet omashu/remote/14). aux keeps its search box private, so it's found on screen:
-- the EditBox carrying aux's own enter/complete/char handlers (aux's search bar is the only one with all three).
-- While it's on screen, Ctrl+Shift+F11 (a binding only while the auction house is open) puts the keyboard in it,
-- empty, so Couch Mode can type the search and press Enter (aux's own search). Couch Mode types only after the strip
-- says the box has the keyboard (flag 4), so letters never reach the game's key bindings.
local auxBox, lookedAt = nil, 0
local function findAuxBox()
  if auxBox then return auxBox end
  if GetTime() - lookedAt < 1 then return nil end   -- the scan walks every frame: at most once a second
  lookedAt = GetTime()
  if not (AuctionFrame or AuctionHouseFrame or IsAddOnLoaded and IsAddOnLoaded("auxForever")) then return nil end
  local f = EnumerateFrames()
  while f do
    if f.IsObjectType and f:IsObjectType("EditBox") and type(f.enter) == "function" and type(f.complete) == "function"
      and type(f.char) == "function" then auxBox = f; return f end
    f = EnumerateFrames(f)
  end
end
local ahOpen = false
local focusBtn = CreateFrame("Button", "OmashuAuxSearchFocus", UIParent)
focusBtn:SetScript("OnClick", function()
  local b = ahOpen and findAuxBox()
  if b and b:IsVisible() then b:SetFocus(); b:SetText(""); b:SetCursorPosition(0) end
end)
local KEY = "CTRL-SHIFT-F11"
local ahEv = CreateFrame("Frame")
ahEv:RegisterEvent("AUCTION_HOUSE_SHOW"); ahEv:RegisterEvent("AUCTION_HOUSE_CLOSED")
ahEv:SetScript("OnEvent", function(_, e)
  ahOpen = (e == "AUCTION_HOUSE_SHOW")
  if InCombatLockdown() then return end
  if ahOpen then SetOverrideBindingClick(focusBtn, true, KEY, "OmashuAuxSearchFocus") else ClearOverrideBindings(focusBtn) end
end)
local function auxFlags()
  if not ahOpen then return 0 end
  local b = findAuxBox()
  if not (b and b:IsVisible()) then return 0 end
  return 2 + (b:HasFocus() and 4 or 0)
end

-- The newest lines that fit, oldest first.
local function packet(flags)
  local pick, used = {}, 0
  for i = #recent, 1, -1 do
    local l = recent[i]
    if used + #l.text + 4 > ROOM then break end
    table.insert(pick, 1, l); used = used + #l.text + 4
  end
  local bytes = { flags, #pick }
  for _, l in ipairs(pick) do
    u16(bytes, l.id); u16(bytes, #l.text)
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
f:SetScript("OnEvent", function(_, event, ...)
  if event:sub(1, 9) ~= "CHAT_MSG_" then dirty = true; return end   -- screen changed: redraw
  local ok, b = pcall(body, event, ...)
  if not ok or type(b) ~= "string" or b == "" then return end
  local t = GetTime()
  local text = date("%m/%d %H:%M:%S") .. string.format(".%03d", math.floor((t % 1) * 1000)) .. "  " .. b
  if #text > ROOM - 4 then text = text:sub(1, ROOM - 4) end
  nextId = (nextId % 65535) + 1
  recent[#recent + 1] = { id = nextId, text = text }
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
  if #text > ROOM - 4 then text = text:sub(1, ROOM - 4) end
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

