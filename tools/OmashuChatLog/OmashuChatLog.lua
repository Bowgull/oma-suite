-- Omashu chat for the phone remote.
-- TEST BUILD (2026-11-09): draws one fixed test line as a strip of coloured blocks at the bottom-left edge of the
-- screen, so Joshua can see how visible it is and Couch Mode can prove it decodes it exactly.
-- Code: blocks of 4x2 screen pixels. Block 1 magenta, block 2 cyan (where it starts), then 6 bits per block:
-- 2 bits in each of red, green, blue, as 0 / 85 / 170 / 255. The bytes: length (1 byte), then the UTF-8 text.
local TEST = "TEST [Guild] Bujuju Banton: hello from the strip! éè ✓"
local W, H = 4, 2   -- block size in screen pixels

local function on() if LoggingChat and not LoggingChat() then LoggingChat(true) end end

local strip = CreateFrame("Frame", "OmashuStrip", UIParent)
strip:SetFrameStrata("TOOLTIP"); strip:SetFrameLevel(10000)
strip:SetIgnoreParentScale(true); strip:SetScale(1)
local blocks = {}

local function draw(text)
  local _, ph = GetPhysicalScreenSize()
  local px = 768 / ph / strip:GetEffectiveScale()   -- one screen pixel, in this frame's units (the screen is 768 units tall at scale 1)
  local bytes = { #text }
  for i = 1, #text do bytes[#bytes + 1] = text:byte(i) end
  local syms, acc, nb = {}, 0, 0
  for _, b in ipairs(bytes) do
    acc = acc * 256 + b; nb = nb + 8
    while nb >= 6 do nb = nb - 6; local s = math.floor(acc / 2 ^ nb); syms[#syms + 1] = s; acc = acc - s * 2 ^ nb end
  end
  if nb > 0 then syms[#syms + 1] = acc * 2 ^ (6 - nb) end
  local cols = { {1, 0, 1}, {0, 1, 1} }
  for _, s in ipairs(syms) do
    cols[#cols + 1] = { math.floor(s / 16) / 3, (math.floor(s / 4) % 4) / 3, (s % 4) / 3 }
  end
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
  strip:Show()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("DISPLAY_SIZE_CHANGED")
f:RegisterEvent("UI_SCALE_CHANGED")
f:SetScript("OnEvent", function() on(); draw(TEST) end)
