-- Doomed (sheets omashu/wow/22 v5 and 23 v5, approved 2026-11-10/11): on your target's health bar, the health your DoTs
-- will still take shows in each DoT's colour, at the end of the green; a skull and bones on the portrait marks a mob
-- they will finish. The numbers come from the DoT model (DotModel.lua); this file only draws.
--
-- Forever hides health in combat, so nothing here reads a size: reverse-filling status bars pinned to the end of the
-- green, scaled by max health, let WoW place every piece. The skull rides the end of a very long bar inside a small
-- clipped window, so it shows only when the DoTs' damage reaches the mob's health. Because of
-- that it can't "pop" (no event says the moment it becomes true); it appears at once.
-- The bar: Blizzard's target frame, or another add-on's (TargetFinder.lua); Blizzard's always looks exactly as approved.
local ADDON, ns = ...
local P = {}; ns.parts.doomed = P

local Spells, Anim, M = ns.spells, ns.core.Anim, ns.model
-- colours, ring tones and beats: Spells.lua (by spell ID; a DoT's name, in any client language, finds its entry)
local GOLD = { 206 / 255, 160 / 255, 44 / 255 }   -- gold means only 'ending soon' (last 3 s); at the green's strength like the other pieces
local function LOWS() return (ns.db and ns.db.low) or 3 end   -- 'Ending soon' (settings): seconds of gold
local function breath(x)              -- the rings' own breath (Anim.breath): 1 at the start, 0.3 halfway, 1 every 1.5 s
  if ns.db and ns.db.lowlook == 'steady' then return 1 end
  return Anim.breath(x, LOWS(), 1.5, .3)
end
local OTHER = { .55, .45, .65 }
local FILL = 'UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health'
local WHITE = 'Interface\\Buttons\\WHITE8X8'
local MARK = 'Interface\\AddOns\\OmaDoomed\\Art\\doomed-mark'
local MARK_W, MARK_H = 78, 54          -- screen pixels at 1080p (sheet 23: the skull's own size)
-- Blizzard's target portrait at 1080p, UI scale 1 (58 units): the skull steps up in whole multiples when the
-- portrait is about twice that or more on screen (4K, a big UI scale), so the pixel art stays crisp
local PORTRAIT_REF = 58 * 1080 / 768
local MAX = 6

local hb, fill, portrait, built
local clip, shine
local segs = {}
local win, longBar, mark
local test
local JOIN = { crease = 4, fade = 6, thin = 2, none = 0 }   -- sheet 25: 'crease' = hard join + soft dark crease (Blizzard's way)

local function atlasOK(n) return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(n) ~= nil end
-- the bar's own grain: a thin middle slice of Blizzard's health texture (the whole texture stretched into a short piece
-- carried its left-to-right shading, so each colour went dark-to-bright and duller than the green)
-- 2026-11-11 'jumpy and bouncy': WoW snaps every texture edge to whole pixels, so a slow slide moved in 1-2 px hops
-- and anchored edges hopped out of step. Ours glide on sub-pixels instead.
local function nosnap(t) if t and t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end end
local function barTex(t)
  nosnap(t)
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

-- the bar we draw on (TargetFinder.lua): Blizzard's, EllesmereUI's or a saved frame path. P.blizz: Blizzard's own.
local want                             -- { bar, portrait, blizz } chosen by update()
local function find()
  if not want then return nil end
  hb, portrait, P.blizz = want.bar, want.portrait, want.blizz
  fill = hb and hb:GetStatusBarTexture()
  return hb and fill
end

-- the skull's whole-number step: 1 at 1080p on Blizzard's frame (today's size), 2 when the portrait is twice that on screen
local function skullStep()
  if not (portrait and win) then return 1 end
  local okW, w = pcall(portrait.GetWidth, portrait)
  local okS, sc = pcall(win.GetEffectiveScale, win)
  local _, h = GetPhysicalScreenSize()
  if not (okW and okS) or ns.core.Secret.is(w) or ns.core.Secret.is(sc) or type(w) ~= 'number' or type(sc) ~= 'number' or type(h) ~= 'number' then return 1 end
  return math.max(1, math.floor(w * sc * h / 768 / PORTRAIT_REF + .5))
end
local function sizeSkull()
  if not (win and longBar and mark) then return end
  local k = skullStep()
  local W, H = px(MARK_W, win), px(MARK_H, win)
  if k ~= 1 then W, H = W * k, H * k end
  -- sheet 23 v5: centred over the ring (measured on the sheet: 0.5 px off; a -6 px offset put it 6.8 px left in game)
  -- and 65.5 px above the ring's centre, on its top edge
  win:SetSize(W, H); win:ClearAllPoints(); win:SetPoint('CENTER', portrait, 'CENTER', px(.8, win) * k, px(65.5, win) * k)
  longBar:SetSize(W * 400, H); mark:SetSize(W, H)
end
P.sizeSkull = function() pcall(sizeSkull) end

local function build()
  if built then return true end
  if not find() then return false end
  -- clipped to the bar, minus the see-through margin Blizzard's texture has at its left end (measured: 5 screen px);
  -- another add-on's bar has its own margin: none
  clip = CreateFrame('Frame', nil, hb); clip:SetPoint('TOPLEFT', hb, 'TOPLEFT', P.blizz and px(5, hb) or 0, 0); clip:SetPoint('BOTTOMRIGHT', hb, 'BOTTOMRIGHT')
  if P.blizz then clip:SetFrameLevel(hb:GetFrameLevel() + 1)
  else   -- its own layer (strata first: a strata change resets the level)
    local strata, level = ns.plates.layerOf(hb)
    if strata then clip:SetFrameStrata(strata) end
    clip:SetFrameLevel((level or 200) + 1)
  end
  clip:SetClipsChildren(true)
  -- sheet 30: while a bite closes, everything nearer the bar's end sits a little to the right and slides back. A 0..max
  -- bar starting at the health's end carries that offset (a plain number, the bite left), so no size is ever read.
  -- our own copy of the health's end (2026-11-11, 'really jumpy'): pinning to Blizzard's fill mixed two clocks, so on a
  -- tick the pieces jumped left for one frame before the bite caught them. Now the health's end and the bite move in
  -- the same SetValue pass, every frame. Health may be a hidden number: only a status bar is handed it.
  P.base = CreateFrame('StatusBar', nil, clip); P.base:SetPoint('TOPLEFT', hb, 'TOPLEFT'); P.base:SetPoint('BOTTOMLEFT', hb, 'BOTTOMLEFT'); P.base:SetWidth(hb:GetWidth())
  P.base:SetStatusBarTexture(WHITE); P.base:SetStatusBarColor(0, 0, 0, 0); P.base:SetMinMaxValues(0, 1); P.base:SetValue(0)
  local baseEdge = P.base:GetStatusBarTexture(); nosnap(baseEdge); P.hungOn = fill
  -- 2026-11-11 'jittery, like rubber bands': the pieces used to hang off a chain (health's end -> slide bar -> holder ->
  -- piece bar -> edge), and WoW settles each link of a chain on its own, so mid-slide the pieces wobbled against the
  -- green. Now every edge is a "mark" hung straight off the health's end, one link deep, all moved in the same pass:
  -- the way Blizzard's own smooth bars work (one value glides, everything is drawn from it).
  local W = hb:GetWidth()
  P.marks = {}
  P.baseEdge = baseEdge
  local function hang(m, edge)
    m.L:ClearAllPoints(); m.L:SetPoint('TOPRIGHT', edge, 'TOPRIGHT'); m.L:SetPoint('BOTTOMRIGHT', edge, 'BOTTOMRIGHT')
    m.R:ClearAllPoints(); m.R:SetPoint('TOPLEFT', edge, 'TOPRIGHT'); m.R:SetPoint('BOTTOMLEFT', edge, 'BOTTOMRIGHT')
  end
  -- 2026-11-11 'the green peeks out': in a real fight the pieces sit on Blizzard's own drawn health (their fill), so
  -- anyone's damage, and Blizzard's own easing of the bar, move green and pieces together
  function P.hangOn(edge) if P.hungOn == edge then return end; P.hungOn = edge; for _, m in ipairs(P.marks) do hang(m, edge) end end
  local function newMark()
    local m = {}
    m.L = CreateFrame('StatusBar', nil, clip); m.L:SetWidth(W); m.L:SetReverseFill(true)
    m.R = CreateFrame('StatusBar', nil, clip); m.R:SetWidth(W)
    hang(m, P.hungOn or fill); P.marks[#P.marks + 1] = m
    for _, b in ipairs({ m.L, m.R }) do b:SetStatusBarTexture(WHITE); b:SetStatusBarColor(0, 0, 0, 0); b:SetMinMaxValues(0, 1); b:SetValue(.0001) end
    m.lt, m.rt = m.L:GetStatusBarTexture(), m.R:GetStatusBarTexture(); nosnap(m.lt); nosnap(m.rt)
    m.f = CreateFrame('Frame', nil, clip); m.f:SetWidth(.001)
    return m
  end
  P.newMark = newMark
  P.E = { [0] = newMark() }   -- E[0]: the far end of the pieces (the health's end plus any bite still closing)
  local art = CreateFrame('Frame', nil, clip); art:SetAllPoints(clip); art:SetFrameLevel(clip:GetFrameLevel() + 2)
  -- the health bar's own shape, as a mask: anything striped stays inside it (2026-11-11: the stripes ran onto the
  -- name banner and the mana bar)
  if art.CreateMaskTexture then
    P.barMask = art:CreateMaskTexture(); P.barMask:SetAllPoints(hb)
    if not P.blizz then P.barMask:SetTexture(WHITE, 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')   -- not Blizzard's shape: the bar's box
    elseif atlasOK(FILL) then P.barMask:SetAtlas(FILL) else P.barMask:SetTexture('Interface\\TargetingFrame\\UI-StatusBar', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE') end
  end
  P.lost = art:CreateTexture(nil, 'ARTWORK', nil, 0); barTex(P.lost); P.lost:SetVertexColor(.14, .09, .05); P.lost:Hide()
  P.lost:SetPoint('TOPLEFT', baseEdge, 'TOPRIGHT'); P.lost:SetPoint('BOTTOMRIGHT', hb, 'BOTTOMRIGHT')   -- test only: the empty bar
  for i = 1, MAX do
    P.E[i] = newMark()
    local s = { mark = P.E[i], edge = P.E[i].f, shown = 0, target = 0 }
    s.base = art:CreateTexture(nil, 'ARTWORK', nil, 1); barTex(s.base)
    s.lift = art:CreateTexture(nil, 'ARTWORK', nil, 2); barTex(s.lift); s.lift:SetBlendMode('ADD')
    -- the flash and the shine use the bar's own texture: a plain white one also lit the bar's see-through top edge
    s.flash = art:CreateTexture(nil, 'OVERLAY', nil, 1); barTex(s.flash); s.flash:SetVertexColor(1, 1, 1); s.flash:SetBlendMode('ADD'); s.flash:SetAlpha(0)
    s.join = art:CreateTexture(nil, 'ARTWORK', nil, 3); barTex(s.join)      -- the fade into the next piece
    s.joinLift = art:CreateTexture(nil, 'ARTWORK', nil, 4); barTex(s.joinLift); s.joinLift:SetBlendMode('ADD')   -- same brightening as the pieces, or the fade reads as a dark seam
    -- the crease uses the bar's own texture tinted black, so it has the bar's exact shape and never runs onto the brass
    -- borders into the name banner or the mana bar (a plain square did)
    s.creaseL = art:CreateTexture(nil, 'OVERLAY', nil, 0); barTex(s.creaseL)
    s.creaseR = art:CreateTexture(nil, 'OVERLAY', nil, 0); barTex(s.creaseR)
    local g = s.flash:CreateAnimationGroup()
    local a1 = g:CreateAnimation('Alpha'); a1:SetFromAlpha(0); a1:SetToAlpha(.42); a1:SetDuration(.08); a1:SetOrder(1)
    local a2 = g:CreateAnimation('Alpha'); a2:SetFromAlpha(.42); a2:SetToAlpha(0); a2:SetDuration(.45); a2:SetOrder(2); a2:SetSmoothing('OUT')
    s.flashAnim = g
    -- sheet 27 (approved "Looks right"): the bite. A second bar holds where this piece's edge WAS; the chunk between it and
    -- the new edge glows bright in the DoT's colour, holds 120 ms, then drains over 380 ms.
    s.gmark = newMark(); s.gedge = s.gmark.f
    -- sheet 36 C 'charging' ("Yes, build it"): while you cast, the piece fills with your cast bar in
    -- its landed colour (so landing changes nothing), an ember glow in its own colour at the front; never white
    -- tick light parts (settings 'Tick light'): a soft wash that reaches into the piece, and five particles
    s.wash = art:CreateTexture(nil, 'OVERLAY', nil, 4); barTex(s.wash); s.wash:SetBlendMode('ADD'); s.wash:Hide()
    s.wash:SetPoint('TOPRIGHT', s.gedge, 'TOPLEFT'); s.wash:SetPoint('BOTTOMRIGHT', s.gedge, 'BOTTOMLEFT'); s.wash:SetWidth(px(16, hb))
    s.parts = {}
    for k = 1, 5 do local t = art:CreateTexture(nil, 'OVERLAY', nil, 6); t:SetBlendMode('ADD'); t:Hide(); s.parts[k] = t end
    s.motes = art:CreateTexture(nil, 'ARTWORK', nil, 3); s.motes:SetTexture('Interface\\AddOns\\OmaDoomed\\Art\\motes', 'REPEAT', 'REPEAT'); s.motes:SetBlendMode('ADD'); s.motes:Hide()
    s.cmark = newMark()
    s.cbase = art:CreateTexture(nil, 'ARTWORK', nil, 1); barTex(s.cbase); s.cbase:Hide()
    s.clift = art:CreateTexture(nil, 'ARTWORK', nil, 2); barTex(s.clift); s.clift:SetBlendMode('ADD'); s.clift:Hide()
    for _, t in ipairs({ s.cbase, s.clift }) do t:SetPoint('TOPLEFT', s.edge, 'TOPLEFT'); t:SetPoint('BOTTOMRIGHT', s.cmark.f, 'BOTTOMLEFT') end
    s.spark = art:CreateTexture(nil, 'OVERLAY', nil, 5); barTex(s.spark); s.spark:SetBlendMode('ADD'); s.spark:Hide()
    s.spark:SetPoint('TOPRIGHT', s.cmark.f, 'TOPLEFT', px(2, hb), 0); s.spark:SetPoint('BOTTOMRIGHT', s.cmark.f, 'BOTTOMLEFT', px(2, hb), 0); s.spark:SetWidth(px(8, hb))
    s.ghost = art:CreateTexture(nil, 'ARTWORK', nil, 5); barTex(s.ghost); s.ghost:Hide()   -- the bite: solid, its own colour
    -- while you cast it (DoesItDie marks it provisional): Blizzard's own shield stripes and shield edge glow, tinted
    s.pre = art:CreateTexture(nil, 'ARTWORK', nil, 4); s.pre:SetTexture('Interface/RaidFrame/Shield-Overlay', 'REPEAT', 'REPEAT')
    s.pre:SetDesaturated(true); s.pre:SetBlendMode('ADD'); s.pre:Hide()   -- the art is shield-blue: grey it, then tint
    -- stripes and motes lie across the WHOLE bar (its width never changes, so they can slide at a fixed size) and a
    -- stencil the shape of this piece cuts them down to it (a piece's own width is hidden in combat on Forever)
    for _, t in ipairs({ s.pre, s.motes }) do t:ClearAllPoints(); t:SetPoint('TOPLEFT', hb, 'TOPLEFT'); t:SetPoint('BOTTOMRIGHT', hb, 'BOTTOMRIGHT') end
    s.pmask = art:CreateMaskTexture(); s.pmask:SetTexture('Interface\\Buttons\\WHITE8X8', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
    s.pre:AddMaskTexture(s.pmask); s.motes:AddMaskTexture(s.pmask)
    s.preGlow = art:CreateTexture(nil, 'OVERLAY', nil, 3); s.preGlow:SetTexture('Interface/RaidFrame/Shield-Overshield'); s.preGlow:SetBlendMode('ADD'); s.preGlow:SetDesaturated(true); s.preGlow:Hide()
    -- the light it casts: 9 screen px onto each neighbour, fading out (left fade, core, right fade), the bar's own shape
    s.spillL = art:CreateTexture(nil, 'OVERLAY', nil, 4); barTex(s.spillL); s.spillL:SetBlendMode('ADD'); s.spillL:Hide()
    s.spillC = art:CreateTexture(nil, 'OVERLAY', nil, 4); barTex(s.spillC); s.spillC:SetBlendMode('ADD'); s.spillC:Hide()
    s.spillR = art:CreateTexture(nil, 'OVERLAY', nil, 4); barTex(s.spillR); s.spillR:SetBlendMode('ADD'); s.spillR:Hide()
    -- every texture of a piece keeps to the health bar's own shape (2026-11-11: saw colour outside the bar once)
    if P.barMask then
      for _, t in ipairs({ s.base, s.lift, s.flash, s.join, s.joinLift, s.creaseL, s.creaseR, s.ghost, s.spillL, s.spillC, s.spillR, s.pre, s.preGlow, s.cbase, s.clift, s.spark, s.wash, s.motes, s.parts[1], s.parts[2], s.parts[3], s.parts[4], s.parts[5] }) do t:AddMaskTexture(P.barMask) end
    end
    segs[i] = s
  end
  for i, s in ipairs(segs) do
    local right, rp = (i == 1) and P.E[0].f or segs[i - 1].edge, 'BOTTOMLEFT'
    for _, t in ipairs({ s.base, s.lift, s.flash, s.pre }) do
      t:SetPoint('TOPLEFT', s.edge, 'TOPLEFT'); t:SetPoint('BOTTOMRIGHT', right, rp)
    end
    s.preGlow:SetPoint('TOPLEFT', s.edge, 'TOPLEFT', -px(3, hb), 0); s.preGlow:SetPoint('BOTTOMLEFT', s.edge, 'BOTTOMLEFT', -px(3, hb), 0); s.preGlow:SetWidth(px(8, hb))
    -- the bite sits at this piece's end nearest the bar's end: from the bite bar's edge to the previous piece's edge
    s.ghost:SetPoint('TOPLEFT', s.gedge, 'TOPLEFT'); s.ghost:SetPoint('BOTTOMRIGHT', right, rp)
    local sp = px(9, hb)
    s.spillC:SetPoint('TOPLEFT', s.gedge, 'TOPLEFT'); s.spillC:SetPoint('BOTTOMRIGHT', right, rp)
    s.spillL:SetPoint('TOPRIGHT', s.gedge, 'TOPLEFT'); s.spillL:SetPoint('BOTTOMRIGHT', s.gedge, 'BOTTOMLEFT'); s.spillL:SetWidth(sp)
    s.spillR:SetPoint('TOPLEFT', right, 'TOPLEFT'); s.spillR:SetPoint('BOTTOMLEFT', right, rp); s.spillR:SetWidth(sp)
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
  function P.reanchor(s, right)
    -- the piece touching the health's end runs 1 screen px past it: Blizzard's green snaps to whole pixels and ours
    -- don't, so a 1 px sliver of green showed beside it ('a tiny bit of green peeking out')
    local dx = (right == P.E[0].f) and px(1, hb) or 0
    for _, t in ipairs({ s.base, s.lift, s.flash, s.pmask }) do t:ClearAllPoints(); t:SetPoint('TOPLEFT', s.edge, 'TOPLEFT'); t:SetPoint('BOTTOMRIGHT', right, 'BOTTOMLEFT', dx, 0) end
    for _, t in ipairs({ s.ghost, s.spillC }) do t:ClearAllPoints(); t:SetPoint('TOPLEFT', s.gedge, 'TOPLEFT'); t:SetPoint('BOTTOMRIGHT', right, 'BOTTOMLEFT', dx, 0) end
    s.spillR:ClearAllPoints(); s.spillR:SetPoint('TOPLEFT', right, 'TOPLEFT'); s.spillR:SetPoint('BOTTOMLEFT', right, 'BOTTOMLEFT'); s.spillR:SetWidth(px(9, hb))
    for _, t in ipairs({ s.join, s.joinLift }) do t:ClearAllPoints(); t:SetPoint('TOP', right, 'TOPLEFT'); t:SetPoint('BOTTOM', right, 'BOTTOMLEFT'); t:SetWidth(px(6, hb)) end
    s.creaseL:ClearAllPoints(); s.creaseL:SetPoint('TOPRIGHT', right, 'TOPLEFT'); s.creaseL:SetPoint('BOTTOMRIGHT', right, 'BOTTOMLEFT'); s.creaseL:SetWidth(px(2, hb))
    s.creaseR:ClearAllPoints(); s.creaseR:SetPoint('TOPLEFT', right, 'TOPLEFT'); s.creaseR:SetPoint('BOTTOMLEFT', right, 'BOTTOMLEFT'); s.creaseR:SetWidth(px(2, hb))
    if CreateColor then
      s.creaseL:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, .45))
      s.creaseR:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, .45), CreateColor(0, 0, 0, 0))
    end
    s.right = right
  end
  -- one shine along the top of all the pieces (sheet 22: "fade and shine")
  shine = art:CreateTexture(nil, 'OVERLAY', nil, 2); barTex(shine); shine:SetBlendMode('ADD')
  shine:SetPoint('TOPRIGHT', P.E[0].f, 'TOPLEFT'); shine:SetPoint('BOTTOMRIGHT', P.E[0].f, 'BOTTOMLEFT')
  if CreateColor then shine:SetGradient('VERTICAL', CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, .30)) end

  -- the skull and bones, on the ring's top edge like a raid mark (sheet 23 v5); none when the frame has no portrait
  win, longBar, mark = nil, nil, nil
  if portrait then
    win = CreateFrame('Frame', nil, portrait:GetParent() or UIParent); win:SetClipsChildren(true); win:SetFrameStrata('HIGH')
    local k = skullStep()
    local W, H = px(MARK_W, win), px(MARK_H, win)
    if k ~= 1 then W, H = W * k, H * k end
    -- sheet 23 v5: centred over the ring (measured on the sheet: 0.5 px off; a -6 px offset put it 6.8 px left in game)
    -- and 65.5 px above the ring's centre, on its top edge
    win:SetSize(W, H); win:SetPoint('CENTER', portrait, 'CENTER', px(.8, win) * k, px(65.5, win) * k)
    longBar = CreateFrame('StatusBar', nil, win); longBar:SetSize(W * 400, H); longBar:SetPoint('RIGHT', win, 'RIGHT')
    longBar:SetStatusBarTexture(WHITE); longBar:SetStatusBarColor(0, 0, 0, 0); longBar:SetMinMaxValues(0, 1); longBar:SetValue(0)
    mark = longBar:CreateTexture(nil, 'OVERLAY'); mark:SetTexture(MARK); mark:SetTexCoord(0, MARK_W / 128, 0, MARK_H / 64)
    mark:SetSize(W, H); mark:SetPoint('RIGHT', longBar:GetStatusBarTexture(), 'RIGHT')
  end
  P.builtOn = hb
  built = true
  return true
end

local function hide()
  if not built then return end
  P.hpLate = nil
  clip:Hide(); if win then win:Hide() end
  for _, r in pairs(M.snap().per) do r.slot = nil end
  for _, s in ipairs(segs) do s.owner = nil; s.shown = 0; s.ghost:Hide(); s.spillL:Hide(); s.spillC:Hide(); s.spillR:Hide() end
  M.dropBites()
end

-- put a mark p health-points from the health's end (negative = into the green), on whichever side it falls
local function setMark(m, p, maxv)
  m.L:SetMinMaxValues(0, maxv); m.R:SetMinMaxValues(0, maxv)
  local side = p < 0 and 'L' or 'R'
  -- both sides stay alive (never 0): a side WoW had hidden took a frame or two to place when an edge first crossed the
  -- health's end (filmed 2026-11-11: the last DoT's piece vanished for 2 frames as it ended)
  m.L:SetValue(math.max(-p, .0001)); m.R:SetValue(math.max(p, .0001))
  if side ~= m.side then
    m.f:ClearAllPoints()
    local t, a, b = (side == 'L') and m.lt or m.rt, (side == 'L') and 'TOPLEFT' or 'TOPRIGHT', (side == 'L') and 'BOTTOMLEFT' or 'BOTTOMRIGHT'
    m.f:SetPoint('TOPLEFT', t, a); m.f:SetPoint('BOTTOMLEFT', t, b); m.side = side
  end
end

local function colorOf(name) local sp = Spells.dot(name); return sp and sp.deep or OTHER end

-- sheet 30 (approved "Yes, build it", 2026-11-11). Every frame. dots: { {name, damage, expires} } nearest the bar's end
-- first; maxv / hp may be hidden numbers (only handed to status bars). A tick spends part of its own DoT's piece: the
-- bite flares hot in that DoT's colour (60 ms), holds (to 160 ms), then cools to an ember while the gap closes, fast
-- then settling (340 ms); it lights 9 px of its neighbours. The green never moves. Its ring breathes the same instant.
-- Ticks, bites, precast and landed pieces and ending ghosts are worked out by the model (DotModel.lua).
local function mix(a, b, k) return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k } end
local function toneOf(name) local sp = Spells.dot(name); return sp and sp.color end   -- the ring's colour, for the tick

local function render()
  local cur = M.cur()
  if not cur or not built then return end
  local dots, maxv, hp = cur.dots, cur.maxv, cur.hp
  if #dots == 0 then return hide() end
  clip:Show()
  local now = GetTime()
  local anow = M.clock()
  local run, slide = 0, 0
  local seen = {}
  -- 2026-11-11 'the entire bar repaints for a second when a DoT ends': pieces were slots, so when one DoT left, every
  -- DoT behind it moved into the next slot and borrowed that slot's textures, glows and edges, still showing the old
  -- DoT for a frame or two. Now each DoT owns its slot (textures and edges) for its whole life; when the order
  -- changes only the neighbour anchors move, in the same frame as the edges.
  local order, used = {}, {}
  for j, d in ipairs(dots) do
    if j > MAX then break end
    local r = M.rec(d.name)
    local s = r.slot
    if not s then for _, c in ipairs(segs) do if not c.owner then s = c; break end end end
    if s then s.owner = d.name; r.slot = s; order[#order + 1] = s; used[s] = d end
  end
  for _, r in pairs(M.snap().per) do local s = r.slot; if s and used[s] == nil then s.owner = nil; r.slot = nil end end
  for j, s in ipairs(order) do local right = (j == 1) and P.E[0].f or order[j - 1].edge; if s.right ~= right then P.reanchor(s, right) end end
  local seq = {}
  for j, s in ipairs(order) do seq[#seq + 1] = { s, used[s], j } end
  for _, c in ipairs(segs) do if used[c] == nil then seq[#seq + 1] = { c, nil, 99 } end end
  for _, e in ipairs(seq) do
    local s, d, i = e[1], e[2], e[3]
    if d then
      local bl, flare = M.bite(d.name, anow); slide = slide + bl
      local before = run                                 -- where this piece starts, from the bar's end
      local r = M.rec(d.name)
      local pr = r.pred
      -- each DoT remembers its OWN size (2026-11-11: sizes were kept per slot, so when a DoT ended the others moved up a
      -- slot, took the wrong size and regrew: the green jumped out). A new or refreshed DoT grows in; shrinking is bites.
      local want = math.max(0, d.damage - (pr and pr.est or 0)) + bl
      local sh = r.shown or 0
      if want > sh then sh = sh + (want - sh) * (1 - math.exp(-(M.dt or .033) * 9)) else sh = want end
      r.shown = sh; seen[d.name] = true
      run = run + sh; s.shown = run; s.sz = sh
      local left = d.expires and (d.expires - now)
      local lowNow = left and left <= LOWS()   -- gold through its last 3 s and on past zero while it glides out (it flipped back)
      local c = colorOf(d.name)
      if lowNow then local b = .6 + .4 * breath(left); c = { GOLD[1] * b, GOLD[2] * b, GOLD[3] * b } end
      local tn = toneOf(d.name) or c
      local sp = mix(c, tn, .7)   -- the glow: its own colour, low (no white: warlock light)
      local function spark(al)
        if CreateColor then s.spark:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 1), CreateColor(sp[1] * al, sp[2] * al, sp[3] * al, 1)) end
        s.spark:Show()
      end
      local look = ns.db.cast or 'charging'
      s.pre:Hide(); s.preGlow:Hide(); s.motes:Hide()
      local full = { math.min(1, c[1] * 1.15), math.min(1, c[2] * 1.15), math.min(1, c[3] * 1.15) }
      if d.provisional then   -- still being cast (settings 'While you cast')
        local pr = 1
        if d.castStart and d.castEnd and d.castEnd > d.castStart then pr = math.max(0, math.min(1, (now - d.castStart) / (d.castEnd - d.castStart))) end
        s.base:SetVertexColor(c[1] * .45, c[2] * .45, c[3] * .45); s.lift:SetVertexColor(0, 0, 0)
        s.cbase:Hide(); s.clift:Hide(); s.spark:Hide(); s.cpr = nil
        if look == 'charging' then   -- fills with your cast bar in its landed colour, an ember at the front
          s.cpr = pr
          s.cbase:SetVertexColor(full[1], full[2], full[3]); s.cbase:Show()
          s.clift:SetVertexColor(c[1] * .7, c[2] * .7, c[3] * .7); s.clift:Show()
          spark(.45)
        elseif look == 'smoulder' then   -- its colour rises out of the dark as you cast
          local k = pr ^ 1.6
          s.base:SetVertexColor(c[1] * (.3 + .85 * k), c[2] * (.3 + .85 * k), c[3] * (.3 + .85 * k)); s.lift:SetVertexColor(c[1] * .7 * k, c[2] * .7 * k, c[3] * .7 * k)
        elseif look == 'stripes' then   -- Blizzard's shield stripes in its ring colour, drifting toward the green
          local bw, bh = hb:GetWidth(), hb:GetHeight(); local o = (anow * .35) % 1
          s.pre:SetTexCoord(o, o + bw / 24, 0, bh / 24); s.pre:SetVertexColor(tn[1], tn[2], tn[3], .55); s.pre:Show()
        elseif look == 'motes' then   -- small pixels drifting through the dim piece toward the green
          local bw = hb:GetWidth(); local o = (anow * .08) % 1
          s.motes:SetTexCoord(o, o + bw / 128 * 2, 0, 1); s.motes:SetVertexColor(tn[1] * .8, tn[2] * .8, tn[3] * .8); s.motes:Show()
        end
      else
        -- landed (the model noted when, and in which look)
        s.cbase:Hide(); s.clift:Hide()
        local la = M.landAt[d.name] and (anow - M.landAt[d.name]) or 9
        local ll = M.landLook[d.name]
        if ll == 'charging' and la < .35 then s.cpr = 1; spark(.45 * (1 - la / .35) ^ 2) else s.cpr = nil; s.spark:Hide() end
        local k = 1   -- the other looks ease from dim to full colour as it lands (no snap)
        if ll and ll ~= 'charging' and ll ~= 'smoulder' and la < .3 then k = .4 + .6 * Anim.smoothstep(la / .3) end
        s.base:SetVertexColor(full[1] * k, full[2] * k, full[3] * k)
        s.lift:SetVertexColor(c[1] * .7 * k, c[2] * .7 * k, c[3] * .7 * k)
      end
      local tl = ns.db.tick or 'ember'
      local b = M.biteOf(d.name)
      if b and b.quiet then tl = 'plain' end   -- removed early: no light
      s.biteK = 1
      for k = 1, 5 do s.parts[k]:Hide() end
      if bl > 0 then
        -- settings 'Tick light'. The bitten part keeps its piece's colour; the light (Ember, Cinders, Essence) washes up out
        -- of the piece across the seam into it (sheet 37: no hard cut, no band) and settles back into its own colour.
        local tone = lowNow and { math.min(1, c[1] * 1.3), math.min(1, c[2] * 1.3), math.min(1, c[3] * 1.3) } or (toneOf(d.name) or c)
        s.biteK = (b and b.amt > 0) and math.min(1, bl / b.amt) or 0
        s.gtarget = before + bl; s.ghost:SetVertexColor(full[1] + c[1] * .7, full[2] + c[2] * .7, full[3] + c[3] * .7); s.ghost:Show()
        if tl == 'plain' then
          s.spillC:Hide(); s.wash:Hide()
        else
          local a = flare * .55
          s.spillC:SetVertexColor(tone[1] * a, tone[2] * a, tone[3] * a); s.spillC:Show()
          if CreateColor then s.wash:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 1), CreateColor(tone[1] * a * .6, tone[2] * a * .6, tone[3] * a * .6, 1)) end
          s.wash:Show()
          if (tl == 'cinders' or tl == 'essence') and b and s.right then
            local age = anow - b.at; local life = age / .7; local H = hb:GetHeight()
            for k = 1, 5 do
              local l = math.max(0, math.min(1, (life - (k - 1) * .04) / .9))
              if l > 0 and l < 1 then
                local t = s.parts[k]; local fade = math.sin(math.pi * math.min(1, l * 1.15)); local e = 1 - (1 - l) ^ 2
                local sd = (b.at * 7.3 + k * .618) % 1
                t:ClearAllPoints()
                t:SetPoint('CENTER', s.right, 'LEFT', -px(2 + (k - 1) * 3 + math.sin(age * 4 + k * 1.7) * 2, hb), -H * .3 + e * H * (.5 + sd * .3))
                if tl == 'cinders' then
                  t:SetTexture('Interface\\AddOns\\OmaDoomed\\Art\\mote'); local z = px(5 - 2 * l, hb); t:SetSize(z, z)
                  t:SetVertexColor(tone[1], tone[2], tone[3], .7 * fade)
                else
                  t:SetTexture('Interface\\AddOns\\OmaDoomed\\Art\\haze'); local z = px(12 + 16 * l, hb); t:SetSize(z, z)
                  local hz = mix(c, tone, .45); t:SetVertexColor(hz[1], hz[2], hz[3], .45 * fade)
                end
                t:Show()
              end
            end
          end
        end
        s.spillL:Hide(); s.spillR:Hide()
      else
        s.ghost:Hide(); s.spillL:Hide(); s.spillC:Hide(); s.spillR:Hide(); s.wash:Hide()
      end
    else
      s.shown = run; s.sz = 0; s.cpr = nil; s.wash:Hide(); s.motes:Hide(); for k = 1, 5 do s.parts[k]:Hide() end; s.cbase:Hide(); s.clift:Hide(); s.spark:Hide(); s.pre:Hide(); s.preGlow:Hide(); s.ghost:Hide(); s.spillL:Hide(); s.spillC:Hide(); s.spillR:Hide()
    end
    local on = d and true or false
    local mode = 'crease'
    local jw = mode == 'crease' and 0 or (JOIN[mode] or 0)
    -- no crease next to an empty piece (a DoT that just ended): two creases stacked on one spot, then popped away
    local cr = on and i > 1 and mode == 'crease' and (s.sz or 0) > .3 and order[i - 1] and (order[i - 1].sz or 0) > .3
    s.creaseL:SetShown(cr); s.creaseR:SetShown(cr)
    local ck = (ns.db.tick ~= 'plain' and d and s.biteK) and (1 - .85 * s.biteK) or 1; s.creaseL:SetAlpha(ck); s.creaseR:SetAlpha(ck)
    if jw > 0 then s.join:SetWidth(px(jw, hb)); s.joinLift:SetWidth(px(jw, hb)) end
    s.base:SetShown(on); s.lift:SetShown(on); s.flash:SetShown(false); s.join:SetShown(on and i > 1 and jw > 0); s.joinLift:SetShown(on and i > 1 and jw > 0)
  end
  -- the pieces hang one status bar deeper than the health's end, and WoW lays each level out a frame later; so the end
  -- takes its new value one frame late too, or on every tick the pieces slipped 2 px for a frame (filmed 2026-11-11)
  P.base:SetMinMaxValues(0, maxv); P.base:SetValue(hp)
  for name, r in pairs(M.snap().per) do if not seen[name] then r.shown = nil end end
  -- every edge in one pass, all one link from the health's end
  setMark(P.E[0], slide, maxv)
  for _, s in ipairs(order) do
    setMark(s.mark, slide - s.shown, maxv)
    if s.ghost:IsShown() and s.gtarget then setMark(s.gmark, slide - s.gtarget, maxv) end
    if s.cpr then setMark(s.cmark, slide - s.shown + s.cpr * (s.sz or 0), maxv) end
  end
  local far = order[#order] or segs[1]
  shine:ClearAllPoints(); shine:SetPoint('TOPRIGHT', P.E[0].f, 'TOPLEFT'); shine:SetPoint('BOTTOMLEFT', far.edge, 'BOTTOMLEFT')
  -- the skull: hidden when the mob already carries a real raid mark (that one wins)
  local total = 0; for _, d in ipairs(dots) do if not d.provisional and not d.landed then total = total + d.damage end end   -- review #4: only confirmed DoTs make the skull
  if not win then -- no portrait on this frame: no skull
  elseif GetRaidTargetIndex('target') or ns.db.skull == false then win:Hide() else win:Show(); longBar:SetMinMaxValues(0, hp); longBar:SetValue(total) end
end

-- new numbers (10 times a second and on events): the model notices ticks and keeps them for render
local function draw(dots, maxv, hp)
  if not build() then return end
  M.feed(dots, maxv, hp)
end

-- Which bar to draw on, every update. A different bar (another add-on's target frame showed up, or one was picked)
-- builds the pieces again on it. Rule: a bar that isn't on screen while you have a target gets nothing drawn on it,
-- and chat says so once. Blizzard's own frame gets half a second first (it can show a moment after the target
-- changes; our pieces sit inside it, so nothing floats meanwhile): its look never changes.
local told, hiddenSince, rebuilds = {}, nil, 0
local chosenAt, chosen = -1, false   -- the last answer, kept 0.15 s (update can run every frame in a fight)
local function once(key, msg) if not told[key] then told[key] = true; ns.say(msg) end end
local function unbuild()
  if not built then return end
  hide(); clip:Hide(); if win then win:Hide() end
  segs = {}; built = false
end
local choose1
local function choose()
  local now = GetTime()
  if now - chosenAt < .15 then return chosen end
  chosenAt = now; chosen = choose1()
  return chosen
end
choose1 = function()
  local bar, pf, source, blizz, hidden = ns.targetBar()
  P.source = source
  if not bar then return false end
  if hidden then
    local now = GetTime(); hiddenSince = hiddenSince or now
    if not blizz or now - hiddenSince >= .5 then
      if now - hiddenSince >= .5 then once('hidden', "your target's health bar is hidden, so the kill bar shows nothing. Another add-on's target frame? /omadoomed frame pick") end
      return false
    end
  else hiddenSince = nil end
  if not blizz and ns.plates.reversed(bar) then
    once('reversed', "your target's health bar fills from the right; the kill bar can't draw on that one yet.")
    return false
  end
  if not want or want.bar ~= bar or want.portrait ~= pf then
    if built and (P.builtOn ~= bar or portrait ~= pf) then
      if rebuilds >= 20 then ns.err('kill bar: target bar keeps changing; staying on the last one'); return false end
      rebuilds = rebuilds + 1; unbuild()
    end
    want = { bar = bar, portrait = pf, blizz = blizz }
  end
  return true
end

local function update()
  if not ns.db or not ns.db.doomed or P.off then M.clearCur(); return hide() end
  if test then
    if not UnitExists('target') or not choose() then M.clearCur(); return hide() end
    local now = GetTime()
    if not test.t0 or now - test.t0 > 28 then   -- sheet 30's numbers, from DoesItDie's log: 198-health mob at 140
      test.t0 = now
      local ag = {}; for k = 1, 12 do ag[k] = 6.1 * (k <= 4 and .5 or (k <= 8 and 1 or 1.5)) end
      -- sheet 35: Corruption cast 0-2 s, Bane of Agony at 2.4 s, Immolate cast 2.4-4.4 s
      test.dots = { { n = 'Corruption', ticks = { 10.25, 10.25, 10.25, 10.25 }, every = 3, cast = { 0, 2 }, dur = 12 },
        { n = 'Immolate', ticks = { 3, 3, 3, 3, 3 }, every = 3, cast = { 2.4, 4.4 }, dur = 15 },
        { n = 'Curse of Agony', ticks = ag, every = 2, cast = { 2.4, 2.4 }, dur = 24 } }
    end
    local t = now - test.t0
    local m, hp = 198, 140
    local dots = {}
    for _, d in ipairs(test.dots) do
      if t >= d.cast[1] then
        local land = d.cast[2]; local first = land + d.every
        local done, left = 0, 0
        for k, v in ipairs(d.ticks) do if t >= first + (k - 1) * d.every then done = done + v else left = left + v end end
        hp = hp - done
        if left > 0 then dots[#dots + 1] = { name = d.n, damage = left, expires = test.t0 + land + d.dur, provisional = t < land, castStart = test.t0 + d.cast[1], castEnd = test.t0 + d.cast[2] } end
      end
    end
    table.sort(dots, function(a, b) return a.expires < b.expires end)
    if build() then P.lost:Show(); P.hangOn(P.baseEdge) end   -- the empty bar past the fake health (P.base carries its end)
    return draw(dots, m, hp)
  end
  if not UnitExists('target') or UnitIsDead('target') or not choose() then M.clearCur(); return hide() end
  local dots = M.targetDots()
  local ok, err = pcall(draw, dots, UnitHealthMax('target'), UnitHealth('target'))
  if not ok then ns.fail('draw: ' .. tostring(err), 'the kill bar'); P.off = true; hide() end   -- review #12: off for this session only
end

-- Standalone: Does It Die is never read, written or relied on. If it is on too, its markers show beside ours.
function ns.doesItDieOn()
  return (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded('DoesItDie')) and true or DoesItDie ~= nil
end
local function otherMarkers() if ns.doesItDieOn() then ns.say("Does It Die is also on: you'll see both markers.") end end

function P.start()
  if select(2, UnitClass('player')) ~= 'WARLOCK' then return end
  M.start()
  pcall(otherMarkers)
  local function newTarget()
    for _, s in ipairs(segs) do s.owner = nil; s.shown = 0 end
    P.dirty = true; update()
  end
  ns.bus:On('TARGET', newTarget)
  ns.bus:On('DOTS', function() P.dirty = true end)
  ns.bus:On('TARGET_BAR', function() told.hidden = nil; chosenAt = -1; P.dirty = true end)   -- a frame path was set or cleared
  local ev = CreateFrame('Frame')
  -- the skull's whole-number step follows the screen and the UI scale
  for _, e in ipairs({ 'UI_SCALE_CHANGED', 'DISPLAY_SIZE_CHANGED' }) do pcall(ev.RegisterEvent, ev, e) end
  ev:SetScript('OnEvent', function() P.sizeSkull() end)
  local acc = 0
  ev:SetScript('OnUpdate', function(_, dt)
    M.step(dt)
    acc = acc + dt
    if P.dirty or acc >= .1 then   -- review #6: once a frame at most, however busy
      acc = 0; P.dirty = false
      local ok, err = pcall(update)
      if not ok then ns.fail('update: ' .. tostring(err), 'the kill bar'); P.off = true; pcall(hide); M.clearCur() end
    end
    local ok, err = pcall(render)
    if not ok then ns.fail('render: ' .. tostring(err), 'the kill bar'); P.off = true; pcall(hide); M.clearCur() end
  end)
end

-- /omadoomed on | off    the kill bar part on or off
-- /omadoomed test        fake DoTs on your current target (live)   ... test off
function P.slash(m)
  if m == 'test off' then test = nil; M.test = false; if built then P.lost:Hide(); P.hangOn(fill) end; ns.say('test off.'); return update() end
  if m:match('^test') then
    test = {}; M.test = true; M.forget()
    ns.say('test DoTs on your target. /omadoomed test off'); return update()
  end
  if m == 'on' or m == 'off' then
    ns.db.doomed = (m == 'on'); ns.say('kill bar ' .. (ns.db.doomed and 'on.' or 'off.')); return update()
  end
  ns.say('/omadoomed on|off, options, report, report show, errors, plates, frame · /omadoomed rings on|off, others on|off')
end

-- a setting changed on the Options page (Settings.lua): show it at once; every other kill bar setting is read each frame
ns.bus:On('SETTING', function(key) if key == 'doomed' then update() end end)
