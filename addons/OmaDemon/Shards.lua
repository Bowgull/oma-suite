-- OmaDemon shards: Bujuju's soul shards as five cut gems under the pet frame (mockup 12, "looks good!").
-- Spec and QA list: reports/Soul shard displays in WoW.md. On Forever shards are bag items (6265), no bar, no cap.
local _, ns = ...
local ITEM, N = 6265, 5
local SHEET = 'Interface\\AddOns\\OmaDemon\\shards\\art\\OmashuShards.tga'    -- 512x256, drawn at 2x
local CHIME = 'Interface\\AddOns\\OmaDemon\\shards\\snd\\five.ogg'
local PX = 1                                                              -- the row frame is scaled so that 1 unit = 1 TV pixel (see place)
local W, H, STEP = 40 * PX, 48 * PX, 48 * PX                              -- one cell drawn at 1x (gem 36x44 inside a 40x48 cell)
local CELL = {                                                            -- left, right, top, bottom in the sheet
  lit = { 0, 80, 0, 96 }, empty = { 80, 160, 0, 96 }, amber = { 160, 240, 0, 96 }, dark = { 240, 320, 0, 96 },
  glow = { 320, 416, 0, 112 }, flash = { 0, 96, 96, 192 }, spark = { 104, 120, 96, 112 } }
local function coords(t, c) t:SetTexCoord(c[1] / 512, c[2] / 512, c[3] / 256, c[4] / 256) end

local db
local function say(m) ns.say(m) end
local function log(m) if not db then return end; db.log = db.log or {}; table.insert(db.log, 1, date('%H:%M:%S ') .. m); while #db.log > 40 do table.remove(db.log) end end
local function reduced() return db.reduced end

-- ---------- count (guarded: a "secret" value in combat keeps the last known count) ----------
local last = nil
local function readCount()
  if db.fake ~= nil then return db.fake end
  local ok, n = pcall(function() return (C_Item and C_Item.GetItemCount or GetItemCount)(ITEM) end)
  if ok and type(n) == 'number' then return n end
  log('count unreadable (' .. tostring(ok and type(n) or n) .. '), keeping ' .. tostring(last))
  return last
end
local drainSoul = false
local function checkDrainSoul()
  local ok, known = pcall(function()
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo('Drain Soul')
    local id = info and info.spellID or (GetSpellInfo and select(7, GetSpellInfo('Drain Soul')))
    return id and IsPlayerSpell and IsPlayerSpell(id) or false
  end)
  drainSoul = ok and known or false
end

-- ---------- frames ----------
local root = CreateFrame('Frame', 'OmaDemonShards', UIParent)
root:SetSize(STEP * (N - 1) + W, H); root:SetFrameStrata('MEDIUM'); root:SetFrameLevel(5)
local gems, countText = {}, nil
local function tex(parent, cell, layer, blend, w, h)
  local t = parent:CreateTexture(nil, layer or 'ARTWORK'); t:SetTexture(SHEET); coords(t, cell)
  t:SetSize(w or W, h or H); t:SetPoint('CENTER'); if blend then t:SetBlendMode(blend) end
  pcall(t.SetSnapToPixelGrid, t, true); pcall(t.SetTexelSnappingBias, t, 0)
  return t
end
local function scaleAnim(group, from, to, dur, smooth, order, delay, origin)
  local a = group:CreateAnimation('Scale'); a:SetDuration(dur); a:SetSmoothing(smooth); a:SetOrder(order or 1)
  if delay then a:SetStartDelay(delay) end
  if a.SetScaleFrom then a:SetScaleFrom(from, from); a:SetScaleTo(to, to) else a:SetFromScale(from, from); a:SetToScale(to, to) end
  if origin then a:SetOrigin(origin, 0, 0) end
  return a
end
local function alphaAnim(group, from, to, dur, smooth, order, delay)
  local a = group:CreateAnimation('Alpha'); a:SetFromAlpha(from); a:SetToAlpha(to); a:SetDuration(dur); a:SetSmoothing(smooth or 'NONE'); a:SetOrder(order or 1)
  if delay then a:SetStartDelay(delay) end
  return a
end

for i = 1, N do
  local f = CreateFrame('Frame', nil, root); f:SetSize(W, H); f:SetPoint('LEFT', root, 'LEFT', (i - 1) * STEP, 0)
  local g = { frame = f }
  g.glow = tex(f, CELL.glow, 'BACKGROUND', 'ADD', 48 * PX, 56 * PX); g.glow:SetPoint('CENTER', 0, -4 * PX); g.glow:SetAlpha(.45)
  g.socket = tex(f, CELL.empty, 'BORDER')
  g.amber = tex(f, CELL.amber, 'BORDER'); g.amber:Hide()
  g.gem = tex(f, CELL.lit, 'ARTWORK')
  g.dark = tex(f, CELL.dark, 'OVERLAY'); g.dark:Hide()
  g.flash = tex(f, CELL.flash, 'OVERLAY', 'ADD', 48 * PX, 48 * PX); g.flash:SetAlpha(0)
  g.sparks = {}
  for s = 1, 7 do local sp = tex(f, CELL.spark, 'OVERLAY', 'ADD', 3 * PX, 3 * PX); sp:SetVertexColor(1, .84, 1); sp:Hide(); g.sparks[s] = sp end

  -- gain: 0.3 -> 1.18 (160 ms OUT), -> 0.95 (110 IN_OUT), -> 1.0 (90 OUT), dropping 6 px into the socket
  g.gain = g.gem:CreateAnimationGroup()
  scaleAnim(g.gain, .3, 1.18, .16, 'OUT', 1); scaleAnim(g.gain, 1.18, .95, .11, 'IN_OUT', 2); scaleAnim(g.gain, .95, 1, .09, 'OUT', 3)
  local drop = g.gain:CreateAnimation('Translation'); drop:SetOffset(0, -6 * PX); drop:SetDuration(.16); drop:SetSmoothing('OUT'); drop:SetOrder(1)
  g.gain:SetScript('OnPlay', function() g.gem:ClearAllPoints(); g.gem:SetPoint('CENTER', 0, 6 * PX); g.gem:Show() end)
  g.gain:SetScript('OnFinished', function() g.gem:ClearAllPoints(); g.gem:SetPoint('CENTER'); g.gem:SetAlpha(1) end)
  g.flashAnim = g.flash:CreateAnimationGroup(); alphaAnim(g.flashAnim, .8, 0, .14, 'OUT')
  g.flashAnim:SetScript('OnPlay', function() g.flash:SetAlpha(.8) end); g.flashAnim:SetScript('OnFinished', function() g.flash:SetAlpha(0) end)
  for s, sp in ipairs(g.sparks) do
    local ag = sp:CreateAnimationGroup()
    local mv = ag:CreateAnimation('Translation'); mv:SetDuration(.45); mv:SetSmoothing('OUT'); mv:SetOrder(1)
    alphaAnim(ag, 1, 0, .135, 'NONE', 1, .315)
    ag:SetScript('OnPlay', function() sp:ClearAllPoints(); sp:SetPoint('CENTER'); sp:SetAlpha(1); sp:Show() end)
    ag:SetScript('OnFinished', function() sp:Hide() end)
    sp.anim, sp.move = ag, mv
  end
  -- spend: dark flash 60 ms, then collapse into the point (180 ms IN), fading over the last 120 ms
  g.spend = g.gem:CreateAnimationGroup()
  scaleAnim(g.spend, 1, 0.01, .18, 'IN', 1, .06, 'BOTTOM'); alphaAnim(g.spend, 1, 0, .12, 'NONE', 1, .12)
  g.spend:SetScript('OnFinished', function() g.gem:Hide(); g.gem:SetAlpha(1) end)
  g.darkAnim = g.dark:CreateAnimationGroup(); alphaAnim(g.darkAnim, .85, .85, .06)
  g.darkAnim:SetScript('OnPlay', function() g.dark:SetAlpha(.85); g.dark:Show() end); g.darkAnim:SetScript('OnFinished', function() g.dark:Hide() end)
  -- zero: the first socket pulses amber, 600 ms each way
  g.zero = g.amber:CreateAnimationGroup(); g.zero:SetLooping('BOUNCE'); alphaAnim(g.zero, .45, 1, .6, 'IN_OUT')
  -- full (five held, in combat): the glow breathes like Blizzard's bar, 0.25 to 0.6 over 650 ms each way
  g.full = g.glow:CreateAnimationGroup(); g.full:SetLooping('BOUNCE'); alphaAnim(g.full, .25, .6, .65, 'IN_OUT')
  g.full:SetScript('OnFinished', function() g.glow:SetAlpha(.45) end)
  -- reduced motion: 150 ms fades
  g.fadeIn = g.gem:CreateAnimationGroup(); alphaAnim(g.fadeIn, 0, 1, .15); g.fadeIn:SetScript('OnPlay', function() g.gem:Show() end)
  g.fadeOut = g.gem:CreateAnimationGroup(); alphaAnim(g.fadeOut, 1, 0, .15); g.fadeOut:SetScript('OnFinished', function() g.gem:Hide(); g.gem:SetAlpha(1) end)
  gems[i] = g
end
countText = root:CreateFontString(nil, 'OVERLAY'); countText:SetFont(STANDARD_TEXT_FONT, 30 * PX, 'OUTLINE')
countText:SetPoint('LEFT', root, 'RIGHT', 10 * PX, -2 * PX); countText:SetTextColor(.94, .94, .94); countText:Hide()

-- ---------- placing the row: 10 px under the pet frame, left edge on the pet portrait; never anchored to it ----------
local testNoPet = false   -- /omademon shards nopet: show the no-pet spot for 15 s
local function place()
  -- our own plain frame: fine to move in combat too (a pet summoned mid-fight)
  local s = UIParent:GetEffectiveScale()
  -- Scale the row so 1 unit = 1 TV pixel, measured NOW (at file load the UI scale isn't applied yet: that put the row
  -- 25 px high on 2026-11-09). Physical px = units * effective scale * (screen height / 768).
  local _, ph = GetPhysicalScreenSize(); ph = (ph and ph > 0) and ph or 1080
  root:SetScale((768 / ph) / UIParent:GetEffectiveScale())
  -- 2026-11-10 (Joshua: follow the pet frame; no pet = slide up under you). Measured with /omademon shards probe: the row's
  -- old spot (232,237 TV px) is the pet portrait's bottom-left (235,237) less 3 px. So: pinned to PetPortrait while
  -- the pet is out (it moves when the pet frame moves); with no pet, up where the pet frame's top is (157 px), just
  -- under your own bars, pinned to the frame that holds the pet frame. Only OUR frame is anchored; theirs untouched.
  local pet, holder = _G.PetPortrait, _G.PlayerBottomManagedFrameContainer or _G.PlayerFrame
  root:ClearAllPoints()
  if pet and pet:IsVisible() and not testNoPet then
    root:SetPoint('TOPLEFT', pet, 'BOTTOMLEFT', -3, 0); if db then db.placed = 'under pet' end
  elseif holder and holder == _G.PlayerBottomManagedFrameContainer then
    root:SetPoint('TOPLEFT', holder, 'TOPLEFT', 59, 0); if db then db.placed = 'under you' end
  else
    root:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', 232, -157); if db then db.placed = 'fixed, under you' end
  end
end

-- ---------- states ----------
local function setLit(g, lit, instant)
  g.gain:Stop(); g.spend:Stop(); g.fadeIn:Stop(); g.fadeOut:Stop()
  g.gem:ClearAllPoints(); g.gem:SetPoint('CENTER'); g.gem:SetAlpha(1)
  if lit then g.gem:Show() else g.gem:Hide() end
  g.glow:SetShown(lit)
end
local function playGain(g)
  if reduced() then g.fadeIn:Play(); g.glow:Show(); return end
  g.glow:Show(); g.gain:Play(); g.flashAnim:Play()
  local n = 5 + math.random(0, 2)
  for s = 1, n do
    local sp = g.sparks[s]; local ang = (s - 1) * 2 * math.pi / n + (math.random() - .5) * math.pi / 4.5
    local d = (18 + 12 * (s % 2)) * PX
    sp.move:SetOffset(math.cos(ang) * d, math.sin(ang) * d - 4 * PX); sp.anim:Play()
  end
end
local function playSpend(g)
  if reduced() then g.fadeOut:Play(); g.glow:Hide(); return end
  g.darkAnim:Play(); g.spend:Play(); g.glow:Hide()
end
local inCombat = false
local function refreshFull(count)
  for i = 1, N do local g = gems[i]
    if count >= N and inCombat and not reduced() then if not g.full:IsPlaying() then g.full:Play() end
    else if g.full:IsPlaying() then g.full:Stop() end; g.glow:SetAlpha(.45) end
  end
end
local function refreshZero(count)
  local g = gems[1]
  -- 2026-11-10 Joshua: "It's annoying turn off the glow". Off unless /omademon shards hint on.
  if count == 0 and drainSoul and db and db.zeroHint then
    g.amber:Show(); if reduced() then g.zero:Stop(); g.amber:SetAlpha(.6) elseif not g.zero:IsPlaying() then g.zero:Play() end
  else g.zero:Stop(); g.amber:Hide() end
end
local function refreshCount(count)
  if count >= 6 then countText:SetText(count); countText:Show() else countText:Hide() end
end

local firstShown = false
local function update(why)
  local n = readCount(); if n == nil then return end
  local old = last; last = n
  if not firstShown then
    firstShown = true
    for i = 1, N do setLit(gems[i], i <= n, true) end
    refreshCount(n); refreshZero(n); refreshFull(n); log('shown ' .. n .. ' (' .. why .. ')'); return
  end
  if n > old then
    local k = 0
    for i = old + 1, math.min(n, N) do k = k + 1; local g = gems[i]
      if k == 1 then playGain(g) else C_Timer.After(.08 * (k - 1), function() playGain(g) end) end
    end
    if old < N and n >= N and db.sound ~= false then pcall(PlaySoundFile, CHIME, 'SFX') end
    log(('gain %d -> %d (%s)'):format(old, n, why))
  elseif n < old then
    local k = 0
    for i = math.min(old, N), n + 1, -1 do k = k + 1; local g = gems[i]
      if k == 1 then playSpend(g) else C_Timer.After(.08 * (k - 1), function() playSpend(g) end) end
    end
    log(('spend %d -> %d (%s)'):format(old, n, why))
  end
  refreshCount(n); refreshZero(n); refreshFull(n)
end

-- ---------- events ----------
local ev = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'BAG_UPDATE_DELAYED', 'PLAYER_REGEN_ENABLED', 'PLAYER_REGEN_DISABLED', 'SPELLS_CHANGED', 'EDIT_MODE_LAYOUTS_UPDATED', 'UI_SCALE_CHANGED', 'DISPLAY_SIZE_CHANGED', 'UNIT_PET', 'PET_UI_UPDATE' }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript('OnEvent', function(_, e)
  if e ~= 'PLAYER_LOGIN' and not db then return end
  if e == 'PLAYER_LOGIN' then
    db = ns.shardsDB()
    if select(2, UnitClass('player')) ~= 'WARLOCK' then root:Hide(); ev:UnregisterAllEvents(); return end
    checkDrainSoul(); place(); root:Show()
  elseif e == 'PLAYER_ENTERING_WORLD' then checkDrainSoul(); place(); C_Timer.After(1, function() update('enter') end)
  elseif e == 'BAG_UPDATE_DELAYED' then update('bags')
  elseif e == 'PLAYER_REGEN_DISABLED' then inCombat = true; if last then refreshFull(last) end
  elseif e == 'PLAYER_REGEN_ENABLED' then inCombat = false; place(); if last then refreshFull(last) end
  elseif e == 'SPELLS_CHANGED' then checkDrainSoul(); if last then refreshZero(last) end
  else place(); C_Timer.After(0.3, place) end   -- pet in or out: the pet frame settles a moment later
end)

-- ---------- /omademon shards: test and options ----------
ns.shardsSlash = function(msg)
  local cmd, arg = msg:match('^(%S*)%s*(.-)$'); cmd = cmd:lower()
  if cmd == 'test' then
    arg = arg:lower()
    if arg == 'gain' then db.fake = (last or 0) + 1 elseif arg == 'spend' then db.fake = math.max(0, (last or 0) - 1)
    elseif arg == 'zero' then db.fake = 0 elseif arg == 'full' then db.fake = 5 elseif arg == 'seven' then db.fake = 7
    elseif arg == 'two' then db.fake = (last or 0) + 2 elseif arg == 'off' then db.fake = nil
    elseif tonumber(arg) then db.fake = tonumber(arg) else say('/omademon shards test gain|spend|two|zero|full|seven|<n>|off'); return end
    update('test ' .. arg); say('test: count ' .. tostring(db.fake == nil and 'real' or db.fake))
  elseif cmd == 'hint' then db.zeroHint = (arg == 'on'); if last then refreshZero(last) end; say('empty-shard hint ' .. (db.zeroHint and 'on' or 'off'))
  elseif cmd == 'motion' then db.reduced = (arg == 'off'); say('motion ' .. (db.reduced and 'reduced' or 'full'))
  elseif cmd == 'sound' then db.sound = (arg ~= 'off'); say('chime ' .. (db.sound and 'on' or 'off'))
  elseif cmd == 'nopet' then testNoPet = true; place(); say('no-pet spot for 15 s'); C_Timer.After(15, function() testNoPet = false; place() end)
  elseif cmd == 'place' then place(); say('placed at ' .. tostring(db.placed))
  elseif cmd == 'probe' then   -- where the pet and player frames are, in TV pixels (top-left origin), for placing the row
    local _, ph = GetPhysicalScreenSize(); ph = (ph and ph > 0) and ph or 1080
    local out = {}
    local function rect(name, f)
      if not f or not f.GetRect then return end
      local ok, l, b, w, h = pcall(f.GetRect, f); if not ok or not l then out[#out + 1] = name .. ' no rect'; return end
      local k = f:GetEffectiveScale() * ph / 768
      local parent = f.GetParent and f:GetParent(); local pn = parent and parent.GetName and parent:GetName() or tostring(parent)
      out[#out + 1] = ('%s x=%.0f top=%.0f w=%.0f h=%.0f shown=%s parent=%s'):format(name, l * k, ph - (b + h) * k, w * k, h * k, tostring(f:IsVisible()), tostring(pn))
    end
    local p = _G.PetPortrait; local depth = 0
    while p and depth < 6 do rect('pet' .. depth .. ':' .. tostring(p.GetName and p:GetName()), p); p = p.GetParent and p:GetParent(); depth = depth + 1 end
    -- named frames only: walking every global set off WoW's "blocked action" warning on 2026-11-09
    for _, name in ipairs({ 'PlayerFrame', 'PetFrame', 'PlayerPortrait', 'TargetFrame' }) do rect(name, _G[name]) end
    local q = _G.PlayerPortrait; depth = 0
    while q and depth < 4 do rect('player' .. depth .. ':' .. tostring(q.GetName and q:GetName()), q); q = q.GetParent and q:GetParent(); depth = depth + 1 end
    db.probe = out; say('probe saved: ' .. #out .. ' frames (/reload to write)')
  elseif cmd == 'log' then for i = math.min(10, #(db.log or {})), 1, -1 do print(db.log[i]) end
  else say('/omademon shards test ... | motion on|off | sound on|off | hint on|off | place | log') end
end
