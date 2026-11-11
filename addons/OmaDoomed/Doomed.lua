-- Doomed (sheets omashu/wow/22 v5 and 23 v5, approved 2026-11-10/11): on your target's health bar, the health your DoTs
-- will still take shows in each DoT's colour, at the end of the green; a skull and bones on the portrait marks a mob
-- they will finish. Maths: DoesItDie's public API for now (MIT, Joe Greive), to be folded in later.
--
-- Forever hides health in combat, so nothing here reads a size: reverse-filling status bars pinned to the end of the
-- green, scaled by max health, let WoW place every piece. The skull rides the end of a very long bar inside a small
-- clipped window (DoesItDie's trick), so it shows only when the DoTs' damage reaches the mob's health. Because of
-- that it can't "pop" (no event says the moment it becomes true); it appears at once.
local ADDON, ns = ...
local P = {}; ns.parts.doomed = P

local COLOR = {   -- sheet 25 (approved 2026-11-11): one colour per DoT, shared with the nameplate rings, at the green's strength
  ['Corruption'] = { 40 / 255, 150 / 255, 168 / 255 }, ['Curse of Agony'] = { 120 / 255, 56 / 255, 192 / 255 },
  ['Bane of Agony'] = { 120 / 255, 56 / 255, 192 / 255 }, ['Immolate'] = { 206 / 255, 106 / 255, 36 / 255 },
  ['Siphon Life'] = { 160 / 255, 30 / 255, 50 / 255 },
}
local GOLD = { 206 / 255, 160 / 255, 44 / 255 }   -- gold means only 'ending soon' (last 3 s); at the green's strength like the other pieces
local LOW = 3
local function breath(x)              -- the rings' own breath (Rings.lua): 1 at 3 s, 0.3 at 2.25 s, 1 at 1.5 s ...
  local ph = (LOW - x) / 1.5 % 1; return .3 + .7 * (math.cos(ph * 2 * math.pi) * .5 + .5)
end
local OTHER = { .55, .45, .65 }
local FILL = 'UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health'
local WHITE = 'Interface\\Buttons\\WHITE8X8'
local MARK = 'Interface\\AddOns\\OmaDoomed\\Art\\doomed-mark'
local MARK_W, MARK_H = 78, 54          -- screen pixels at 1080p (sheet 23: the skull's own size)
local MAX = 6

local hb, fill, portrait, built
local clip, holder, shine
local segs = {}
local win, longBar, mark
local last = {}                      -- damage per DoT name last time (a drop = a tick: flash)
local test
local JOIN = { crease = 4, fade = 6, thin = 2, none = 0 }   -- sheet 25: 'crease' = hard join + soft dark crease (Blizzard's way)

local function atlasOK(n) return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(n) ~= nil end
-- the bar's own grain: a thin middle slice of Blizzard's health texture (the whole texture stretched into a short piece
-- carried its left-to-right shading, so each colour went dark-to-bright and duller than the green)
local function barTex(t)
  local a = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(FILL)
  if a and a.file then
    t:SetTexture(a.file); local l, r = a.leftTexCoord, a.rightTexCoord
    t:SetTexCoord(l + (r - l) * .45, l + (r - l) * .55, a.topTexCoord, a.bottomTexCoord)
  else t:SetTexture('Interface\\TargetingFrame\\UI-StatusBar') end
  t:SetDesaturated(true)
end
local function px(n, frame)           -- screen pixels -> UI units of that frame (the target frame has its own scale)
  local _, h = GetPhysicalScreenSize(); return n * 768 / h / (frame or UIParent):GetEffectiveScale()
end

local function find()
  local tf = TargetFrame
  local main = tf and tf.TargetFrameContent and tf.TargetFrameContent.TargetFrameContentMain
  hb = main and main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
  portrait = tf and tf.TargetFrameContainer and tf.TargetFrameContainer.Portrait
  fill = hb and hb:GetStatusBarTexture()
  return hb and fill and portrait
end

local function build()
  if built then return true end
  if not find() then return false end
  -- clipped to the bar, minus the see-through margin Blizzard's texture has at its left end (measured: 5 screen px)
  clip = CreateFrame('Frame', nil, hb); clip:SetPoint('TOPLEFT', hb, 'TOPLEFT', px(5, hb), 0); clip:SetPoint('BOTTOMRIGHT', hb, 'BOTTOMRIGHT')
  clip:SetClipsChildren(true); clip:SetFrameLevel(hb:GetFrameLevel() + 1)
  -- sheet 30: while a bite closes, everything nearer the bar's end sits a little to the right and slides back. A 0..max
  -- bar starting at the health's end carries that offset (a plain number, the bite left), so no size is ever read.
  P.slide = CreateFrame('StatusBar', nil, clip); P.slide:SetWidth(hb:GetWidth())
  P.slide:SetPoint('TOPLEFT', fill, 'TOPRIGHT'); P.slide:SetPoint('BOTTOMLEFT', fill, 'BOTTOMRIGHT')
  P.slide:SetStatusBarTexture(WHITE); P.slide:SetStatusBarColor(0, 0, 0, 0); P.slide:SetMinMaxValues(0, 1); P.slide:SetValue(0)
  local slideEdge = P.slide:GetStatusBarTexture()
  holder = CreateFrame('Frame', nil, clip)
  holder:SetPoint('TOPRIGHT', slideEdge, 'TOPRIGHT'); holder:SetPoint('BOTTOMRIGHT', slideEdge, 'BOTTOMRIGHT'); holder:SetWidth(hb:GetWidth())
  local art = CreateFrame('Frame', nil, clip); art:SetAllPoints(clip); art:SetFrameLevel(clip:GetFrameLevel() + 2)
  P.lost = art:CreateTexture(nil, 'ARTWORK', nil, 0); barTex(P.lost); P.lost:SetVertexColor(.14, .09, .05); P.lost:Hide()   -- test only: the empty bar
  for i = 1, MAX do
    local bar = CreateFrame('StatusBar', nil, holder); bar:SetAllPoints(holder); bar:SetReverseFill(true)
    bar:SetStatusBarTexture(WHITE); bar:SetStatusBarColor(0, 0, 0, 0); bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    local s = { bar = bar, edge = bar:GetStatusBarTexture(), shown = 0, target = 0 }
    s.base = art:CreateTexture(nil, 'ARTWORK', nil, 1); barTex(s.base)
    s.lift = art:CreateTexture(nil, 'ARTWORK', nil, 2); barTex(s.lift); s.lift:SetBlendMode('ADD')
    -- the flash and the shine use the bar's own texture: a plain white one also lit the bar's see-through top edge
    s.flash = art:CreateTexture(nil, 'OVERLAY', nil, 1); barTex(s.flash); s.flash:SetVertexColor(1, 1, 1); s.flash:SetBlendMode('ADD'); s.flash:SetAlpha(0)
    s.join = art:CreateTexture(nil, 'ARTWORK', nil, 3); barTex(s.join)      -- the fade into the next piece
    s.joinLift = art:CreateTexture(nil, 'ARTWORK', nil, 4); barTex(s.joinLift); s.joinLift:SetBlendMode('ADD')   -- same brightening as the pieces, or the fade reads as a dark seam
    -- the crease uses the bar's own texture tinted black, so it has the bar's exact shape and never runs onto the brass
    -- borders into the name banner or the mana bar (a plain square did, Joshua 2026-11-11)
    s.creaseL = art:CreateTexture(nil, 'OVERLAY', nil, 0); barTex(s.creaseL)
    s.creaseR = art:CreateTexture(nil, 'OVERLAY', nil, 0); barTex(s.creaseR)
    local g = s.flash:CreateAnimationGroup()
    local a1 = g:CreateAnimation('Alpha'); a1:SetFromAlpha(0); a1:SetToAlpha(.42); a1:SetDuration(.08); a1:SetOrder(1)
    local a2 = g:CreateAnimation('Alpha'); a2:SetFromAlpha(.42); a2:SetToAlpha(0); a2:SetDuration(.45); a2:SetOrder(2); a2:SetSmoothing('OUT')
    s.flashAnim = g
    -- sheet 27 (approved "Looks right"): the bite. A second bar holds where this piece's edge WAS; the chunk between it and
    -- the new edge glows bright in the DoT's colour, holds 120 ms, then drains over 380 ms.
    s.gbar = CreateFrame('StatusBar', nil, holder); s.gbar:SetAllPoints(holder); s.gbar:SetReverseFill(true)
    s.gbar:SetStatusBarTexture(WHITE); s.gbar:SetStatusBarColor(0, 0, 0, 0); s.gbar:SetMinMaxValues(0, 1); s.gbar:SetValue(0)
    s.gedge = s.gbar:GetStatusBarTexture()
    s.ghost = art:CreateTexture(nil, 'ARTWORK', nil, 5); barTex(s.ghost); s.ghost:Hide()   -- the bite: solid, its own colour
    -- the light it casts: 9 screen px onto each neighbour, fading out (left fade, core, right fade), the bar's own shape
    s.spillL = art:CreateTexture(nil, 'OVERLAY', nil, 4); barTex(s.spillL); s.spillL:SetBlendMode('ADD'); s.spillL:Hide()
    s.spillC = art:CreateTexture(nil, 'OVERLAY', nil, 4); barTex(s.spillC); s.spillC:SetBlendMode('ADD'); s.spillC:Hide()
    s.spillR = art:CreateTexture(nil, 'OVERLAY', nil, 4); barTex(s.spillR); s.spillR:SetBlendMode('ADD'); s.spillR:Hide()
    segs[i] = s
  end
  for i, s in ipairs(segs) do
    local right, rp = (i == 1) and holder or segs[i - 1].edge, (i == 1) and 'BOTTOMRIGHT' or 'BOTTOMLEFT'
    for _, t in ipairs({ s.base, s.lift, s.flash }) do
      t:SetPoint('TOPLEFT', s.edge, 'TOPLEFT'); t:SetPoint('BOTTOMRIGHT', right, rp)
    end
    -- the bite sits at this piece's end nearest the bar's end: from the bite bar's edge to the previous piece's edge
    s.ghost:SetPoint('TOPLEFT', s.gedge, 'TOPLEFT'); s.ghost:SetPoint('BOTTOMRIGHT', right, rp)
    local sp = px(9, hb)
    s.spillC:SetPoint('TOPLEFT', s.gedge, 'TOPLEFT'); s.spillC:SetPoint('BOTTOMRIGHT', right, rp)
    s.spillL:SetPoint('TOPRIGHT', s.gedge, 'TOPLEFT'); s.spillL:SetPoint('BOTTOMRIGHT', s.gedge, 'BOTTOMLEFT'); s.spillL:SetWidth(sp)
    s.spillR:SetPoint('TOPLEFT', right, (i == 1) and 'TOPRIGHT' or 'TOPLEFT'); s.spillR:SetPoint('BOTTOMLEFT', right, rp); s.spillR:SetWidth(sp)
    -- the join sits on this piece's right edge, fading from this colour into the previous (nearer the green) one
    if i > 1 then
      for _, t in ipairs({ s.join, s.joinLift }) do t:SetPoint('TOP', segs[i - 1].edge, 'TOPLEFT'); t:SetPoint('BOTTOM', segs[i - 1].edge, 'BOTTOMLEFT'); t:SetWidth(px(6, hb)) end
      -- the crease: 2 screen px of soft dark either side of the join, darkest (45%) on it
      s.creaseL:SetPoint('TOPRIGHT', segs[i - 1].edge, 'TOPLEFT'); s.creaseL:SetPoint('BOTTOMRIGHT', segs[i - 1].edge, 'BOTTOMLEFT'); s.creaseL:SetWidth(px(2, hb))
      s.creaseR:SetPoint('TOPLEFT', segs[i - 1].edge, 'TOPLEFT'); s.creaseR:SetPoint('BOTTOMLEFT', segs[i - 1].edge, 'BOTTOMLEFT'); s.creaseR:SetWidth(px(2, hb))
      if CreateColor then
        s.creaseL:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, .45))
        s.creaseR:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, .45), CreateColor(0, 0, 0, 0))
      end   -- 6 screen px: what the 2-game-pixel fade looked like on sheet 22 (seen ~3x); 2 px read as a hard cut on the TV
    end
  end
  -- one shine along the top of all the pieces (sheet 22: "fade and shine")
  shine = art:CreateTexture(nil, 'OVERLAY', nil, 2); barTex(shine); shine:SetBlendMode('ADD')
  shine:SetPoint('TOPRIGHT', holder, 'TOPRIGHT'); shine:SetPoint('BOTTOMRIGHT', holder, 'BOTTOMRIGHT')
  if CreateColor then shine:SetGradient('VERTICAL', CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, .30)) end

  -- the skull and bones, on the ring's top edge like a raid mark (sheet 23 v5)
  win = CreateFrame('Frame', nil, portrait:GetParent() or UIParent); win:SetClipsChildren(true); win:SetFrameStrata('HIGH')
  local W, H = px(MARK_W, win), px(MARK_H, win)
  -- sheet 23 v5: centred over the ring (measured on the sheet: 0.5 px off; a -6 px offset put it 6.8 px left in game)
  -- and 65.5 px above the ring's centre, on its top edge
  win:SetSize(W, H); win:SetPoint('CENTER', portrait, 'CENTER', px(.8, win), px(65.5, win))
  longBar = CreateFrame('StatusBar', nil, win); longBar:SetSize(W * 400, H); longBar:SetPoint('RIGHT', win, 'RIGHT')
  longBar:SetStatusBarTexture(WHITE); longBar:SetStatusBarColor(0, 0, 0, 0); longBar:SetMinMaxValues(0, 1); longBar:SetValue(0)
  mark = longBar:CreateTexture(nil, 'OVERLAY'); mark:SetTexture(MARK); mark:SetTexCoord(0, MARK_W / 128, 0, MARK_H / 64)
  mark:SetSize(W, H); mark:SetPoint('RIGHT', longBar:GetStatusBarTexture(), 'RIGHT')
  built = true
  return true
end

local function hide()
  if not built then return end
  clip:Hide(); win:Hide()
  for _, s in ipairs(segs) do s.shown = 0; s.ghost:Hide(); s.spillL:Hide(); s.spillC:Hide(); s.spillR:Hide() end
  wipe(P.bites)
end

local function colorOf(name) return COLOR[name] or OTHER end

-- sheet 30 (approved "Yes, build it", 2026-11-11). Every frame. dots: { {name, damage, expires} } nearest the bar's end
-- first; maxv / hp may be hidden numbers (only handed to status bars). A tick spends part of its own DoT's piece: the
-- bite flares hot in that DoT's colour (60 ms), holds (to 160 ms), then cools to an ember while the gap closes, fast
-- then settling (340 ms); it lights 9 px of its neighbours. The green never moves. Its ring breathes the same instant.
P.bites = {}                         -- DoT name -> { amt, at }
local EMPTY = { 30 / 255, 19 / 255, 10 / 255 }
local function easeOut(x) x = math.max(0, math.min(1, x)); return 1 - (1 - x) ^ 3 end
local function mix(a, b, k) return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k } end
local RINGTONE = {   -- the rings' own colours (Rings.lua), for the flare
  ['Corruption'] = { 95 / 255, 216 / 255, 232 / 255 }, ['Curse of Agony'] = { 196 / 255, 108 / 255, 1 }, ['Bane of Agony'] = { 196 / 255, 108 / 255, 1 },
  ['Immolate'] = { 1, 150 / 255, 64 / 255 }, ['Siphon Life'] = { 214 / 255, 48 / 255, 72 / 255 },
}
local RINGGOLD = { 1, 214 / 255, 110 / 255 }

local function biteNow(name, now)    -- what is still left of a bite (0 when done), and its flare 0..1
  local b = P.bites[name]; if not b then return 0, 0 end
  local a = now - b.at
  if a >= .5 then P.bites[name] = nil; return 0, 0 end
  local left = b.amt * (1 - easeOut((a - .16) / .34))
  local flare = a < .06 and a / .06 or (a < .16 and 1 or math.max(0, 1 - (a - .16) / .34))
  return left, flare
end

local cur                            -- the latest dots, maxv, hp (from update), drawn every frame
local function render()
  if not cur or not built then return end
  local dots, maxv, hp = cur.dots, cur.maxv, cur.hp
  if #dots == 0 then return hide() end
  clip:Show()
  local now = GetTime()
  local run, slide = 0, 0
  for i, s in ipairs(segs) do
    local d = dots[i]
    s.bar:SetMinMaxValues(0, maxv); s.gbar:SetMinMaxValues(0, maxv)
    if d then
      local bl, flare = biteNow(d.name, now); slide = slide + bl
      local before = run                                 -- where this piece starts, from the bar's end
      run = run + d.damage + bl
      -- a new DoT grows in; shrinking happens only through bites
      if run > s.shown then s.shown = s.shown + (run - s.shown) * .25 else s.shown = run end
      s.bar:SetValue(s.shown)
      local left = d.expires and (d.expires - now)
      local lowNow = left and left > 0 and left <= LOW
      local c = colorOf(d.name)
      if lowNow then local b = .6 + .4 * breath(left); c = { GOLD[1] * b, GOLD[2] * b, GOLD[3] * b } end
      s.base:SetVertexColor(c[1] * 1.15, c[2] * 1.15, c[3] * 1.15)
      s.lift:SetVertexColor(c[1] * .7, c[2] * .7, c[3] * .7)
      if bl > 0 then
        local tone = lowNow and RINGGOLD or (RINGTONE[d.name] or c)
        local hot = mix({ math.min(1, tone[1] * 1.25), math.min(1, tone[2] * 1.25), math.min(1, tone[3] * 1.25) }, { 1, .98, .92 }, .2)
        local base = colorOf(d.name); local ember = mix(base, EMPTY, .75)
        local col = (now - P.bites[d.name].at) < .16 and mix(base, hot, flare) or mix(ember, hot, flare)
        s.gbar:SetValue(before + bl); s.ghost:SetVertexColor(col[1], col[2], col[3]); s.ghost:Show()
        local a = flare * .8
        s.spillC:SetVertexColor(tone[1] * a, tone[2] * a, tone[3] * a)
        if CreateColor then
          s.spillL:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 0), CreateColor(tone[1] * a, tone[2] * a, tone[3] * a, 1))
          s.spillR:SetGradient('HORIZONTAL', CreateColor(tone[1] * a, tone[2] * a, tone[3] * a, 1), CreateColor(0, 0, 0, 0))
        end
        s.spillL:Show(); s.spillC:Show(); s.spillR:Show()
      else
        s.ghost:Hide(); s.spillL:Hide(); s.spillC:Hide(); s.spillR:Hide()
      end
    else
      s.shown = run; s.bar:SetValue(run); s.ghost:Hide(); s.spillL:Hide(); s.spillC:Hide(); s.spillR:Hide()
    end
    local on = d and true or false
    local mode = ns.db.doomedJoin or 'crease'
    local jw = mode == 'crease' and 0 or (JOIN[mode] or 0)
    s.creaseL:SetShown(on and i > 1 and mode == 'crease'); s.creaseR:SetShown(on and i > 1 and mode == 'crease')
    if jw > 0 then s.join:SetWidth(px(jw, hb)); s.joinLift:SetWidth(px(jw, hb)) end
    s.base:SetShown(on); s.lift:SetShown(on); s.flash:SetShown(false); s.join:SetShown(on and i > 1 and jw > 0); s.joinLift:SetShown(on and i > 1 and jw > 0)
  end
  P.slide:SetMinMaxValues(0, maxv); P.slide:SetValue(slide)
  local far = segs[math.min(#dots, MAX)]
  shine:ClearAllPoints(); shine:SetPoint('TOPRIGHT', holder, 'TOPRIGHT'); shine:SetPoint('BOTTOMLEFT', far.edge, 'BOTTOMLEFT')
  -- the skull: hidden when the mob already carries a real raid mark (that one wins)
  local total = 0; for _, d in ipairs(dots) do total = total + d.damage end
  if GetRaidTargetIndex('target') then win:Hide() else win:Show(); longBar:SetMinMaxValues(0, hp); longBar:SetValue(total) end
end

-- new numbers (10 times a second and on events): notice ticks, keep them for render
local function draw(dots, maxv, hp)
  if not build() then return end
  local now = GetTime()
  for _, d in ipairs(dots) do
    if last[d.name] and d.damage < last[d.name] - .5 then
      P.bites[d.name] = { amt = last[d.name] - d.damage, at = now }
      if ns.ringsPulse then pcall(ns.ringsPulse, 'target', d.name) end   -- its ring, same instant
    end
    last[d.name] = d.damage
  end
  cur = { dots = dots, maxv = maxv, hp = hp }
  render()
end

local function update()
  if not ns.db or not ns.db.doomed then cur = nil; return hide() end
  if test then
    if not UnitExists('target') then cur = nil; return hide() end
    local now = GetTime()
    if not test.t0 or now - test.t0 > 27 then   -- sheet 30's numbers, from DoesItDie's log: 198-health mob at 140
      test.t0 = now
      local ag = {}; for k = 1, 12 do ag[k] = 6.1 * (k <= 4 and .5 or (k <= 8 and 1 or 1.5)) end
      test.dots = { { n = 'Corruption', ticks = { 10.25, 10.25, 10.25, 10.25 }, every = 3, first = 3, dur = 12 },
        { n = 'Immolate', ticks = { 3, 3, 3, 3, 3 }, every = 3, first = 3, dur = 15 },
        { n = 'Curse of Agony', ticks = ag, every = 2, first = 2, dur = 24 } }
    end
    local t = now - test.t0
    local m, hp = 198, 140
    local dots = {}
    for _, d in ipairs(test.dots) do
      local done, left = 0, 0
      for k, v in ipairs(d.ticks) do if t >= d.first + (k - 1) * d.every then done = done + v else left = left + v end end
      hp = hp - done
      if left > 0 then dots[#dots + 1] = { name = d.n, damage = left, expires = test.t0 + d.dur } end
    end
    table.sort(dots, function(a, b) return a.expires < b.expires end)
    if build() then   -- the health's end, as Blizzard's bar would draw it
      local W = hb:GetWidth()
      P.slide:ClearAllPoints(); P.slide:SetPoint('TOPLEFT', hb, 'TOPLEFT', W * hp / m, 0); P.slide:SetPoint('BOTTOMLEFT', hb, 'BOTTOMLEFT', W * hp / m, 0)
      P.lost:ClearAllPoints(); P.lost:SetPoint('TOPLEFT', hb, 'TOPLEFT', W * hp / m, 0); P.lost:SetPoint('BOTTOMRIGHT', hb, 'BOTTOMRIGHT'); P.lost:Show()
    end
    return draw(dots, m, hp)
  end
  if not UnitExists('target') or UnitIsDead('target') or not (DoesItDie and DoesItDie.GetDoTs) then cur = nil; return hide() end
  local list = DoesItDie.GetDoTs('target')
  table.sort(list, function(a, b) return (a.expiresAt or 0) < (b.expiresAt or 0) end)   -- runs out first = nearest the green
  local dots = {}
  for _, e in ipairs(list) do if (e.damage or 0) > 0 then dots[#dots + 1] = { name = e.name, damage = e.damage, expires = e.expiresAt } end end
  local ok, err = pcall(draw, dots, UnitHealthMax('target'), UnitHealth('target'))
  if not ok then ns.say('Doomed stopped: ' .. tostring(err)); ns.db.doomed = false; hide() end
end

-- DoesItDie's own box and icon stay off while Doomed is on, and come back when it's off
local function quiet(on)
  if not DoesItDieDB then return end
  if on then
    if ns.db.didSaved == nil then ns.db.didSaved = { m = DoesItDieDB.showMarkers, s = DoesItDieDB.showSkull } end
    DoesItDieDB.showMarkers, DoesItDieDB.showSkull = false, false
  elseif ns.db.didSaved then
    DoesItDieDB.showMarkers, DoesItDieDB.showSkull = ns.db.didSaved.m, ns.db.didSaved.s; ns.db.didSaved = nil
  end
end

function P.start()
  if select(2, UnitClass('player')) ~= 'WARLOCK' then return end
  if not (DoesItDie and DoesItDie.GetDoTs) then ns.say('Doomed needs DoesItDie for now (its maths).'); return end
  quiet(ns.db.doomed)
  local ev = CreateFrame('Frame')
  ev:RegisterEvent('PLAYER_TARGET_CHANGED'); ev:RegisterUnitEvent('UNIT_HEALTH', 'target'); ev:RegisterUnitEvent('UNIT_AURA', 'target')
  ev:SetScript('OnEvent', function(_, e) if e == 'PLAYER_TARGET_CHANGED' then wipe(last); wipe(P.bites); cur = nil; for _, s in ipairs(segs) do s.shown = 0 end end; update() end)
  local acc = 0
  ev:SetScript('OnUpdate', function(_, dt) local ok, err = pcall(render); if not ok then ns.say('Doomed stopped: ' .. tostring(err)); ns.db.doomed = false; hide(); cur = nil end; acc = acc + dt; if acc >= .1 then acc = 0; update() end end)
  if DoesItDie.RegisterCallback then DoesItDie.RegisterCallback(ADDON, function() update() end) end
end

-- /omadoomed            on/off
-- /omadoomed test       fake DoTs on your current target (live)   /omadoomed test die   (doomed)   ... test off
function P.slash(m)
  local j = m:match('^join (%a+)'); if j and JOIN[j] then ns.db.doomedJoin = j; ns.say('Doomed join: ' .. j); return update() end
  if m == 'test off' then test = nil; if built then P.lost:Hide(); P.slide:ClearAllPoints(); P.slide:SetPoint('TOPLEFT', fill, 'TOPRIGHT'); P.slide:SetPoint('BOTTOMLEFT', fill, 'BOTTOMRIGHT') end; ns.say('Doomed test off'); return update() end
  if m:match('^test') then
    test = {}; wipe(last); wipe(P.bites)
    ns.say('Doomed test on your target (Bujuju\'s real ticks, sheet 30). /omadoomed test off'); return update()
  end
  ns.db.doomed = not ns.db.doomed; quiet(ns.db.doomed); ns.say('Doomed ' .. (ns.db.doomed and 'on' or 'off (DoesItDie back after /reload)')); update()
end
