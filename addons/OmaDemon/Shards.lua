-- OmaDemon shards: Bujuju's soul shards as five cut gems under the pet frame (mockup 12, "looks good!").
-- Spec and QA list: reports/Soul shard displays in WoW.md. On Forever shards are bag items (6265), no bar, no cap.
local _, ns = ...
local ITEM, N = 6265, 5
local ARTDIR = 'Interface\\AddOns\\OmaDemon\\shards\\art\\'
local SHEETS = { default = 'OmashuShards', crystal = 'OmashuShards-crystal', pixel = 'OmashuShards-pixel' }   -- 512x256, drawn at 2x, same cells
local function sheet() local d = ns.shardsDB(); return ARTDIR .. (SHEETS[d.gemLook or 'default'] or SHEETS.default) .. '.tga' end
local allTex = {}
local CHIME = 'Interface\\AddOns\\OmaDemon\\shards\\snd\\five.ogg'
local PX = 1                                                              -- the row frame is scaled so that 1 unit = 1 TV pixel (see place)
local W, H, STEP = 40 * PX, 48 * PX, 34 * PX   -- 2026-11-13 sheet 46 B: tighter, so the row spans the pet frame                              -- one cell drawn at 1x (gem 36x44 inside a 40x48 cell)
local CELL = {                                                            -- left, right, top, bottom in the sheet
  lit = { 0, 80, 0, 96 }, empty = { 80, 160, 0, 96 }, amber = { 160, 240, 0, 96 }, dark = { 240, 320, 0, 96 },
  glow = { 320, 416, 0, 112 }, flash = { 0, 96, 96, 192 }, spark = { 104, 120, 96, 112 } }
local function coords(t, c) t:SetTexCoord(c[1] / 512, c[2] / 512, c[3] / 256, c[4] / 256) end

local db
local function say(m) ns.say(m) end
local function log(m) if not db then return end; db.log = db.log or {}; table.insert(db.log, 1, date('%H:%M:%S ') .. m); while #db.log > 40 do table.remove(db.log) end end
local function reduced() return ns.reduced() end

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
  local t = parent:CreateTexture(nil, layer or 'ARTWORK'); t:SetTexture(sheet()); coords(t, cell); allTex[#allTex + 1] = t
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
  -- The art is drawn in pixels of a 1080p screen at WoW's default UI scale. The row now scales with the UI like
  -- Blizzard's own frames (it used to be pinned to physical pixels, so on a smaller UI scale the gems dwarfed the
  -- pet frame). Same size as before at 1080p and the default UI scale.
  -- 2026-11-13 (sheet 46 B, Joshua: "b for soul shard"): gem size is tied to the pet frame's scale, so the gems grow and
  -- shrink with the pet frame (Edit Mode size, the couch layout). At 100% they're ~1.8x the old size on the Shadow.
  local pf = _G.PetFrame
  local rel = 1
  if pf and pf.GetEffectiveScale and UIParent:GetEffectiveScale() > 0 then rel = pf:GetEffectiveScale() / UIParent:GetEffectiveScale() end
  -- .55: tuned on the Shadow 2026-11-13 with Joshua (.65 was "still a bit big, only slightly"); ~40 px crystals there
  root:SetScale(.55 * rel * ((db and db.size) or 100) / 100)
  -- 2026-11-10 (Joshua: follow the pet frame; no pet = slide up under you). Measured with /omademon shards probe: the row's
  -- old spot (232,237 TV px) is the pet portrait's bottom-left (235,237) less 3 px. So: pinned to PetPortrait while
  -- the pet is out (it moves when the pet frame moves); with no pet, up where the pet frame's top is (157 px), just
  -- under your own bars, pinned to the frame that holds the pet frame. Only OUR frame is anchored; theirs untouched.
  local pet, holder = _G.PetPortrait, _G.PlayerBottomManagedFrameContainer or _G.PlayerFrame
  root:ClearAllPoints()
  if db and db.pin == false and db.pos then
    -- placed by hand (Move gems): the row's centre, in UIParent units from the bottom left
    local k = root:GetEffectiveScale() / UIParent:GetEffectiveScale()
    root:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', db.pos.x / k, db.pos.y / k); db.placed = 'where you put it'
  elseif pet and pet:IsVisible() and not testNoPet then
    -- 2026-11-12 Joshua: "Centered under whole pet frame". Top stays on the portrait's bottom; the row's middle lines
    -- up with the middle of the whole pet frame (picture + bars). Worked out in screen pixels so any frame scale
    -- (BetterBlizzFrames on the Shadow, the couch UI on the laptop) lands the same. Falls back to the old spot.
    local pf = _G.PetFrame
    local fx, px = pf and pf:GetCenter(), pet:GetCenter()
    local rs = root:GetEffectiveScale()
    if fx and px and rs and rs > 0 then
      local dx = (fx * pf:GetEffectiveScale() - px * pet:GetEffectiveScale()) / rs
      -- 2026-11-13 optical centre (sheet 47 B, Joshua: "yes build it ... the optical center and brass"): the round
      -- portrait reads lighter than the square bar box, so the box centre looks left. Nudge toward the bars by about a
      -- quarter of the portrait's width (17 px on the Shadow), so it scales with the frame on every layout.
      dx = dx + .26 * (pet:GetWidth() * pet:GetEffectiveScale()) / rs
      root:SetPoint('TOP', pet, 'BOTTOM', dx, 0); if db then db.placed = 'optically centred under pet frame' end
    else
      root:SetPoint('TOPLEFT', pet, 'BOTTOMLEFT', -3, 0); if db then db.placed = 'under pet' end
    end
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
    if count >= N and inCombat and not reduced() and db.breathe ~= false then if not g.full:IsPlaying() then g.full:Play() end
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
    local keep = db.keep or 6
    if db.chat ~= false and n > keep and old <= keep then say(('%d soul shards, over your %d. Clear some bag space when you can.'):format(n, keep)) end
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
    checkDrainSoul(); place(); ns.shardsVis()
  elseif e == 'PLAYER_ENTERING_WORLD' then checkDrainSoul(); place(); C_Timer.After(1, function() update('enter') end)
  elseif e == 'BAG_UPDATE_DELAYED' then update('bags')
  elseif e == 'PLAYER_REGEN_DISABLED' then inCombat = true; if ns.endMove then ns.endMove() end; ns.shardsVis(); if last then refreshFull(last) end
  elseif e == 'PLAYER_REGEN_ENABLED' then inCombat = false; place(); ns.shardsVis(); if last then refreshFull(last) end
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
  elseif cmd == 'place' or cmd == 'where' then
    place(); say('placed at ' .. tostring(db.placed))
    -- where each pet frame piece really sits, in UI units from the screen's left/top, printed to chat for a screenshot
    local sh = UIParent:GetHeight()
    local function where(name, f)
      if not f or not f.GetRect then print(name .. ': none'); return end
      local ok, l, b, w, h = pcall(f.GetRect, f)
      if not ok or not l then print(name .. ': no rect'); return end
      local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
      local a = f.GetEffectiveAlpha and f:GetEffectiveAlpha() or (f.GetAlpha and f:GetAlpha()) or 1
      print(('%s x=%.0f y=%.0f w=%.0f h=%.0f alpha=%.2f shown=%s'):format(name, l * k, sh - (b + h) * k, w * k, h * k, a, tostring(f:IsVisible())))
    end
    where('gems', root); where('glow', _G.OmaDemonGlow); where('PetPortrait', _G.PetPortrait); where('PetFrame', _G.PetFrame)
    where('PetFrameTexture', _G.PetFrameTexture); where('PetName', _G.PetName); where('PetHealth', _G.PetFrameHealthBar)
    local frames = {}
    for _, a in ipairs({ 'BetterBlizzFrames', 'ClassicFrames', 'EasyFrames', 'ElvUI', 'ShadowedUnitFrames', 'Pitbull4', 'UnhaltedUnitFrames' }) do
      if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(a) then frames[#frames + 1] = a end
    end
    local bbf = _G.BetterBlizzFramesDB
    print('frame add-ons: ' .. (#frames > 0 and table.concat(frames, ', ') or 'none') .. (bbf and (' | bbf classic=' .. tostring(bbf.classicFrames) .. ' noPortrait=' .. tostring(bbf.noPortraitModes)) or ''))
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

-- ---------- settings: look, size, showing, moving (sheet 31 v3, approved 2026-11-12) ----------
local previewUntil, moving = 0, false
function ns.shardsVis()
  local d = ns.shardsDB()
  local show = d.gems ~= false and (not d.hideOOC or inCombat or moving or GetTime() < previewUntil)
  if select(2, UnitClass('player')) ~= 'WARLOCK' then show = false end
  root:SetShown(show)
end
function ns.shardsPreview(sec)
  previewUntil = GetTime() + (sec or 6); ns.shardsVis()
  C_Timer.After((sec or 6) + .05, ns.shardsVis)
end
local function setLook() local path = sheet(); for _, t in ipairs(allTex) do t:SetTexture(path) end end

-- five small gems beside the Size slider, in the chosen look and size (kept in our own table, never on Blizzard's frame)
local minis = setmetatable({}, { __mode = 'k' })
local function paintMini(m)
  local d = ns.shardsDB(); local h = math.floor(24 * (d.size or 100) / 100 + .5)
  for i, t in ipairs(m.gems) do
    t:SetTexture(sheet()); coords(t, i <= 2 and CELL.lit or CELL.empty); t:SetSize(h * 40 / 48, h)
    t:ClearAllPoints(); t:SetPoint('LEFT', m, 'LEFT', (i - 1) * (h * 40 / 48 + 2), 0)
  end
end
function ns.sizeRow(frame)
  local sl = frame.SliderWithSteppers
  if not sl then return end
  local m = minis[frame]
  if not m then
    m = CreateFrame('Frame', nil, frame); m:SetSize(120, 40); m.gems = {}
    for i = 1, N do m.gems[i] = m:CreateTexture(nil, 'ARTWORK') end
    minis[frame] = m
  end
  m:ClearAllPoints(); m:SetPoint('LEFT', sl, 'RIGHT', 44, 0); m:Show(); m.isSize = true; paintMini(m)
end
if SettingsSliderControlMixin and SettingsSliderControlMixin.Init then
  -- a recycled slider row may be another setting now: hide our gems; the Size row shows them again after
  hooksecurefunc(SettingsSliderControlMixin, 'Init', function(frame) local m = minis[frame]; if m then m:Hide() end end)
end

-- Move gems: like Blizzard's Edit Mode. Options step aside, the row gets a blue box you drag (mouse) or nudge
-- (D-pad / arrow keys), A or Enter puts the Options back. Out of combat only; a fight ends it and keeps the spot.
local mover = CreateFrame('Frame', 'OmaDemonGemMover', UIParent); mover:Hide(); mover:SetFrameStrata('DIALOG')
mover:SetPoint('TOPLEFT', root, 'TOPLEFT', -8, 6); mover:SetPoint('BOTTOMRIGHT', root, 'BOTTOMRIGHT', 8, -6)
local fill = mover:CreateTexture(nil, 'BACKGROUND'); fill:SetAllPoints(); fill:SetColorTexture(.24, .55, 1, .28)
for _, e in ipairs({ { 'TOPLEFT', 'TOPRIGHT', 0, 2 }, { 'BOTTOMLEFT', 'BOTTOMRIGHT', 0, 2 }, { 'TOPLEFT', 'BOTTOMLEFT', 2, 0 }, { 'TOPRIGHT', 'BOTTOMRIGHT', 2, 0 } }) do
  local t = mover:CreateTexture(nil, 'BORDER'); t:SetColorTexture(.47, .75, 1, .95)
  t:SetPoint(e[1]); t:SetPoint(e[2]); if e[3] > 0 then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
end
local label = mover:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight'); label:SetPoint('TOPLEFT', mover, 'BOTTOMLEFT', 0, -6)
label:SetText('Soul shard gems: drag with the mouse, or nudge with the arrow keys or D-pad. Enter or A when done.')
local function savePos()
  local x, y = root:GetCenter(); if not (x and y) then return end
  local k = root:GetEffectiveScale() / UIParent:GetEffectiveScale()
  db.pos = { x = x * k, y = y * k }; db.pin = false; place()
end
mover:EnableMouse(true); mover:RegisterForDrag('LeftButton')
mover:SetScript('OnDragStart', function() if InCombatLockdown() then return end; root:SetMovable(true); root:StartMoving() end)
mover:SetScript('OnDragStop', function() root:StopMovingOrSizing(); savePos() end)
local function nudge(dx, dy)
  local p = db.pos or {}; local x, y = root:GetCenter(); if not (x and y) then return end
  local k = root:GetEffectiveScale() / UIParent:GetEffectiveScale()
  db.pos = { x = (p.x or x * k) + dx, y = (p.y or y * k) + dy }; db.pin = false; place()
end
local keys = { { 'Up', 0, 4, { 'PADDUP', 'UP' } }, { 'Down', 0, -4, { 'PADDDOWN', 'DOWN' } }, { 'Left', -4, 0, { 'PADDLEFT', 'LEFT' } }, { 'Right', 4, 0, { 'PADDRIGHT', 'RIGHT' } } }
for _, k in ipairs(keys) do
  local bt = CreateFrame('Button', 'OmaDemonNudge' .. k[1], mover); bt:SetScript('OnClick', function() nudge(k[2], k[3]) end)
end
local done = CreateFrame('Button', 'OmaDemonGemMoverDone', mover, 'UIPanelButtonTemplate'); done:SetSize(90, 24); done:SetText(DONE or 'Done')
done:SetPoint('TOPLEFT', label, 'BOTTOMLEFT', 0, -6)
function ns.endMove()
  if not moving then return end
  moving = false; mover:Hide(); ClearOverrideBindings(mover); ns.shardsVis()
  if not InCombatLockdown() and ns.settings then ns.settings:Open() end
end
done:SetScript('OnClick', ns.endMove)
function ns.moveGems()
  if InCombatLockdown() then say('not in combat'); return end
  if db.pin ~= false then say('turn off Pin to pet first, then Move.'); return end
  moving = true; ns.shardsVis(); place()
  if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
  mover:Show()
  for _, k in ipairs(keys) do for _, key in ipairs(k[4]) do SetOverrideBindingClick(mover, true, key, 'OmaDemonNudge' .. k[1]) end end
  for _, key in ipairs({ 'PAD1', 'ENTER', 'ESCAPE', 'PAD2' }) do SetOverrideBindingClick(mover, true, key, 'OmaDemonGemMoverDone') end
end

table.insert(ns.onSetting, function(key, store)
  if store ~= 'shards' or not db then return end
  if key == 'gemLook' then setLook() end
  if key == 'gemLook' or key == 'size' then for _, m in pairs(minis) do if m.isSize and m:IsShown() then paintMini(m) end end end
  if key == 'size' or key == 'pin' then
    if key == 'pin' and db.pin == false and not db.pos then
      local x, y = root:GetCenter(); local k = root:GetEffectiveScale() / UIParent:GetEffectiveScale()
      if x and y then db.pos = { x = x * k, y = y * k } end
    end
    place()
  end
  if key == 'gems' or key == 'hideOOC' then ns.shardsVis() end
  if key == 'breathe' and last then refreshFull(last) end
  if key == 'zeroHint' and last then refreshZero(last) end
  if key == 'gemLook' or key == 'size' or key == 'hideOOC' then ns.shardsPreview(4) end
end)
-- the pet frame's size changes (Edit Mode): follow it. Our own frame only; theirs untouched.
if _G.PetFrame and hooksecurefunc then hooksecurefunc(_G.PetFrame, 'SetScale', function() place() end) end
local lookEv = CreateFrame('Frame'); lookEv:RegisterEvent('PLAYER_LOGIN')
lookEv:SetScript('OnEvent', function() setLook() end)
