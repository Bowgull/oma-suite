-- Keeps WoW's chat log on (Logs\WoWChatLog.txt) so Couch Mode can pass chat to the phone remote.
-- WoW holds the log in memory and writes it only when the game closes, so every 2 seconds this switches logging
-- off and straight back on: switching off makes WoW write what it holds (tested 2026-11-09).
-- Typing /chatlog toggles it off; it comes back on within 2 seconds.
local function on() if LoggingChat and not LoggingChat() then LoggingChat(true) end end
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
  on()
  if not f.ticker and C_Timer then
    f.ticker = C_Timer.NewTicker(2, function() if LoggingChat and LoggingChat() then LoggingChat(false); LoggingChat(true) else on() end end)
  end
end)
