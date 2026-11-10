-- Throwaway test (2026-11-10): draw the two "does it die" options on the REAL target frame with Blizzard's own art,
-- out of combat, for a screenshot. /omart probe | cut | cutdies | badge | off
local function say(m) print('|cffe8c860Omashu art:|r ' .. tostring(m)) end
local function atlasOK(n) return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(n) ~= nil end
local function walk(f, fn, depth)
  depth = depth or 0; if not f or depth > 8 then return end
  fn(f, depth)
  if f.GetRegions then for _, r in ipairs({ f:GetRegions() }) do fn(r, depth + 1) end end
  if f.GetChildren then for _, c in ipairs({ f:GetChildren() }) do walk(c, fn, depth + 1) end end
end
local function findBar()
  local best
  walk(TargetFrame, function(r) if r.IsObjectType and r:IsObjectType('StatusBar') and r:IsVisible() then
    local w = r:GetWidth() or 0; if not best or (w >= (best:GetWidth() or 0) and r:GetTop() > best:GetTop() - 1) then if w > 60 then best = best and (r:GetTop() > best:GetTop() and r or best) or r end end end end)
  return best
end
local function findLevel()
  local lvl = tostring(UnitLevel('target')); local hit
  walk(TargetFrame, function(r) if r.IsObjectType and r:IsObjectType('FontString') and r:IsVisible() and r:GetText() == lvl then hit = r end end)
  return hit
end
local layer = CreateFrame('Frame', nil, UIParent); layer:SetFrameStrata('HIGH'); layer:SetAllPoints()
local cut = layer:CreateTexture(nil, 'ARTWORK'); local edge = layer:CreateTexture(nil, 'OVERLAY')
local skull = layer:CreateTexture(nil, 'OVERLAY')
local CUT_ATLAS = { 'UI-HUD-UnitFrame-Target-PortraitOn-Bar-TempHPLoss', 'raidframe-absorb-fill', 'RaidFrame-Absorb-Fill' }
local SKULL = { 'UI-HUD-UnitFrame-Target-HighLevelTarget_Icon', 'ui-hud-nameplates-levelindicator-skull' }
local function setAtlas(t, list, file)
  for _, a in ipairs(list) do if atlasOK(a) then t:SetAtlas(a); return a end end
  if file then t:SetTexture(file); return file end
end
local hiddenLevel
local function off() cut:Hide(); edge:Hide(); skull:Hide(); if hiddenLevel then hiddenLevel:SetAlpha(1); hiddenLevel = nil end end
local function drawCut(frac)
  local bar = findBar(); if not bar then say('no target bar'); return end
  local w = bar:GetWidth()   -- health fill size can be a hidden value: anchor to the bar itself (target is at full health in this demo)
  local used = setAtlas(cut, CUT_ATLAS, 'Interface\\RaidFrame\\Absorb-Fill')
  if used == 'Interface\\RaidFrame\\Absorb-Fill' then cut:SetHorizTile(true) end
  cut:ClearAllPoints(); cut:SetPoint('TOPRIGHT', bar, 'TOPRIGHT'); cut:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMRIGHT')
  local green = w; cut:SetWidth(math.max(1, w * frac)); cut:Show()
  if atlasOK('!raidframe-absorb-edge') then edge:SetAtlas('!raidframe-absorb-edge') else edge:SetTexture('Interface\\RaidFrame\\Absorb-Edge') end
  edge:ClearAllPoints(); edge:SetPoint('TOPRIGHT', cut, 'TOPLEFT', 2, 0); edge:SetPoint('BOTTOMRIGHT', cut, 'BOTTOMLEFT', 2, 0); edge:SetWidth(6); edge:Show()
  say('cut uses ' .. tostring(used) .. ', bar ' .. math.floor(w) .. ' px, green ' .. math.floor(green))
end
local function drawSkull()
  local lv = findLevel(); if not lv then say('no level text'); return end
  local used = setAtlas(skull, SKULL, 'Interface\\TargetingFrame\\UI-TargetingFrame-Skull')
  local h = math.max(18, (lv:GetStringHeight() or 14) * 1.5)
  skull:ClearAllPoints(); skull:SetPoint('CENTER', lv, 'CENTER'); skull:SetSize(h, h); skull:Show()
  lv:SetAlpha(0); hiddenLevel = lv
  say('skull uses ' .. tostring(used))
end
SLASH_OMASHUART1 = '/omart'
SlashCmdList.OMASHUART = function(m)
  if InCombatLockdown() then say('out of combat only'); return end
  off()
  if m == 'probe' then
    for _, a in ipairs({ CUT_ATLAS[1], CUT_ATLAS[2], '!raidframe-absorb-edge', SKULL[1], SKULL[2], 'UI-HUD-UnitFrame-SmallCircle' }) do say(a .. ' = ' .. tostring(atlasOK(a))) end
    local b = findBar(); say('bar ' .. tostring(b and (b:GetName() or b:GetDebugName()) or 'none')); local l = findLevel(); say('level ' .. tostring(l and (l:GetName() or l:GetDebugName()) or 'none'))
  elseif m == 'cut' then drawCut(.35)
  elseif m == 'cutdies' then drawCut(1); drawSkull()
  elseif m == 'badge' then drawSkull()
  end
end
