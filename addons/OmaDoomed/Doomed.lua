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

local Spells, M, Secret = ns.spells, ns.model, ns.core.Secret
local K = ns.killStyle                -- colours and looks (KillBarStyle.lua); colours and beats by spell: Spells.lua
local function LOWS() return (ns.db and ns.db.low) or 3 end   -- 'Ending soon' (settings): seconds of gold
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
local C0, C45, GA, GB                  -- colours reused for every gradient (a texture copies the values)

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

-- The masks that shape the green itself (2026-11-13, 'the mob target health was spilling over into the frame'):
-- Blizzard's frame, and BetterBlizzFrames' big or portrait-less health bar, draw the green through a mask
-- (HealthBarsContainer.HealthBarMask) and the bar's own box is bigger than what shows. Pieces filling the box ran onto
-- the frame art; through the same masks they show exactly where the green does, on every style and scale.
local function greenMasks(f)
  local out = {}
  if not (f and f.GetNumMaskTextures and f.GetMaskTexture) then return out end
  local ok, n = pcall(f.GetNumMaskTextures, f)
  if not ok or Secret.is(n) or type(n) ~= 'number' then return out end
  for i = 1, math.min(n, 4) do
    local okM, m = pcall(f.GetMaskTexture, f, i)
    if okM and type(m) == 'table' and m.GetObjectType and m:GetObjectType() == 'MaskTexture' then out[#out + 1] = m end
  end
  return out
end
P.greenMasks = greenMasks

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

-- the health bar's width, or a stand-in when it's hidden or not laid out yet (the sizer then sets the real one)
local function barWidth()
  local ok, w = pcall(hb.GetWidth, hb)
  if ok and not Secret.is(w) and type(w) == 'number' and w > 0 then return w end
  return 120
end

local function build()
  if built then return true end
  if not find() then return false end
  if CreateColor and not C0 then C0, C45, GA, GB = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, .45), CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 1) end
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
  P.base = CreateFrame('StatusBar', nil, clip); P.base:SetPoint('TOPLEFT', hb, 'TOPLEFT'); P.base:SetPoint('BOTTOMLEFT', hb, 'BOTTOMLEFT'); P.base:SetWidth(barWidth())
  P.base:SetStatusBarTexture(WHITE); P.base:SetStatusBarColor(0, 0, 0, 0); P.base:SetMinMaxValues(0, 1); P.base:SetValue(0)
  local baseEdge = P.base:GetStatusBarTexture(); nosnap(baseEdge); P.hungOn = fill
  -- 2026-11-11 'jittery, like rubber bands': the pieces used to hang off a chain (health's end -> slide bar -> holder ->
  -- piece bar -> edge), and WoW settles each link of a chain on its own, so mid-slide the pieces wobbled against the
  -- green. Now every edge is a "mark" hung straight off the health's end, one link deep, all moved in the same pass:
  -- the way Blizzard's own smooth bars work (one value glides, everything is drawn from it).
  local W = barWidth()
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
  function P.fitWidth(w)
    if Secret.is(w) or type(w) ~= 'number' or w <= 0 or w == W then return end
    W = w; P.base:SetWidth(w)
    for _, m in ipairs(P.marks) do m.L:SetWidth(w); m.R:SetWidth(w) end
  end
  P.E = { [0] = newMark() }   -- E[0]: the far end of the pieces (the health's end plus any bite still closing)
  local art = CreateFrame('Frame', nil, clip); art:SetAllPoints(clip); art:SetFrameLevel(clip:GetFrameLevel() + 2)
  -- the health bar's own shape, as a mask: anything striped stays inside it (2026-11-11: the stripes ran onto the
  -- name banner and the mana bar)
  P.masks = greenMasks(fill)
  if #P.masks > 0 then P.barMask = nil
  elseif art.CreateMaskTexture then
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
    -- the crease uses the bar's own texture tinted black, so it has the bar's exact shape and never runs onto the brass
    -- borders into the name banner or the mana bar (a plain square did)
    s.creaseL = art:CreateTexture(nil, 'OVERLAY', nil, 0); barTex(s.creaseL)
    s.creaseR = art:CreateTexture(nil, 'OVERLAY', nil, 0); barTex(s.creaseR)
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
    -- the light a tick casts on the bitten part (the bar's own shape)
    s.spillC = art:CreateTexture(nil, 'OVERLAY', nil, 4); barTex(s.spillC); s.spillC:SetBlendMode('ADD'); s.spillC:Hide()
    -- every texture of a piece keeps to the health bar's own shape (2026-11-11: saw colour outside the bar once)
    local shape = (#P.masks > 0) and P.masks or { P.barMask }
    for _, t in ipairs({ s.base, s.lift, s.creaseL, s.creaseR, s.ghost, s.spillC, s.pre, s.cbase, s.clift, s.spark, s.wash, s.motes, s.parts[1], s.parts[2], s.parts[3], s.parts[4], s.parts[5] }) do
      for _, m in ipairs(shape) do t:AddMaskTexture(m) end
    end
    s.quiet = { s.wash, s.motes, s.parts[1], s.parts[2], s.parts[3], s.parts[4], s.parts[5], s.cbase, s.clift, s.spark, s.pre, s.ghost, s.spillC }   -- an empty slot hides these
    segs[i] = s
  end
  for i, s in ipairs(segs) do
    local right, rp = (i == 1) and P.E[0].f or segs[i - 1].edge, 'BOTTOMLEFT'
    for _, t in ipairs({ s.base, s.lift, s.pre }) do
      t:SetPoint('TOPLEFT', s.edge, 'TOPLEFT'); t:SetPoint('BOTTOMRIGHT', right, rp)
    end
    -- the bite sits at this piece's end nearest the bar's end: from the bite bar's edge to the previous piece's edge
    s.ghost:SetPoint('TOPLEFT', s.gedge, 'TOPLEFT'); s.ghost:SetPoint('BOTTOMRIGHT', right, rp)
    s.spillC:SetPoint('TOPLEFT', s.gedge, 'TOPLEFT'); s.spillC:SetPoint('BOTTOMRIGHT', right, rp)
    if i > 1 then
      -- the crease: 2 screen px of soft dark either side of the join, darkest (45%) on it
      s.creaseL:SetPoint('TOPRIGHT', segs[i - 1].edge, 'TOPLEFT'); s.creaseL:SetPoint('BOTTOMRIGHT', segs[i - 1].edge, 'BOTTOMLEFT'); s.creaseL:SetWidth(px(2, hb))
      s.creaseR:SetPoint('TOPLEFT', segs[i - 1].edge, 'TOPLEFT'); s.creaseR:SetPoint('BOTTOMLEFT', segs[i - 1].edge, 'BOTTOMLEFT'); s.creaseR:SetWidth(px(2, hb))
      if C0 then s.creaseL:SetGradient('HORIZONTAL', C0, C45); s.creaseR:SetGradient('HORIZONTAL', C45, C0) end
    end
  end
  function P.reanchor(s, right)
    -- the piece touching the health's end runs 1 screen px past it: Blizzard's green snaps to whole pixels and ours
    -- don't, so a 1 px sliver of green showed beside it ('a tiny bit of green peeking out')
    local dx = (right == P.E[0].f) and px(1, hb) or 0
    for _, t in ipairs({ s.base, s.lift, s.pmask }) do t:ClearAllPoints(); t:SetPoint('TOPLEFT', s.edge, 'TOPLEFT'); t:SetPoint('BOTTOMRIGHT', right, 'BOTTOMLEFT', dx, 0) end
    for _, t in ipairs({ s.ghost, s.spillC }) do t:ClearAllPoints(); t:SetPoint('TOPLEFT', s.gedge, 'TOPLEFT'); t:SetPoint('BOTTOMRIGHT', right, 'BOTTOMLEFT', dx, 0) end
    s.creaseL:ClearAllPoints(); s.creaseL:SetPoint('TOPRIGHT', right, 'TOPLEFT'); s.creaseL:SetPoint('BOTTOMRIGHT', right, 'BOTTOMLEFT'); s.creaseL:SetWidth(px(2, hb))
    s.creaseR:ClearAllPoints(); s.creaseR:SetPoint('TOPLEFT', right, 'TOPLEFT'); s.creaseR:SetPoint('BOTTOMLEFT', right, 'BOTTOMLEFT'); s.creaseR:SetWidth(px(2, hb))
    if C0 then s.creaseL:SetGradient('HORIZONTAL', C0, C45); s.creaseR:SetGradient('HORIZONTAL', C45, C0) end
    s.right = right
  end
  -- one shine along the top of all the pieces (sheet 22: "fade and shine")
  shine = art:CreateTexture(nil, 'OVERLAY', nil, 2); barTex(shine); shine:SetBlendMode('ADD')
  shine:SetPoint('TOPRIGHT', P.E[0].f, 'TOPLEFT'); shine:SetPoint('BOTTOMRIGHT', P.E[0].f, 'BOTTOMLEFT')
  if CreateColor then shine:SetGradient('VERTICAL', CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, .30)) end
  for _, m in ipairs((#P.masks > 0) and P.masks or { P.barMask }) do shine:AddMaskTexture(m); P.lost:AddMaskTexture(m) end
  P.shineFar = nil
  -- the pieces' bars are as wide as the health bar; another add-on may resize it after we're built (BetterBlizzFrames
  -- does at login and on its settings): our own frame on the bar hears it and follows (a hidden size is skipped)
  local sizer = CreateFrame('Frame', nil, clip); sizer:SetAllPoints(hb)
  sizer:SetScript('OnSizeChanged', function(_, w) P.fitWidth(w) end)
  P.sizer = sizer

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
  P.hidden, P.animating, P.wakeAt, P.redraw = false, false, nil, true
  built = true
  return true
end

-- Setters that remember what they last set and skip a call that changes nothing (our own textures only; a value that
-- may be hidden is never compared: health goes through a counter of new readings instead).
local function shown(t, v) if t.omShown ~= v then t.omShown = v; t:SetShown(v) end end
local function color3(t, r, g, b) if t.omR ~= r or t.omG ~= g or t.omB ~= b or t.omA ~= false then t.omR, t.omG, t.omB, t.omA = r, g, b, false; t:SetVertexColor(r, g, b) end end
local function color4(t, r, g, b, a) if t.omR ~= r or t.omG ~= g or t.omB ~= b or t.omA ~= a then t.omR, t.omG, t.omB, t.omA = r, g, b, a; t:SetVertexColor(r, g, b, a) end end
local function alpha(t, a) if t.omAl ~= a then t.omAl = a; t:SetAlpha(a) end end
local function texCoord(t, a, b, c, d) if t.omT1 ~= a or t.omT2 ~= b or t.omT3 ~= c or t.omT4 ~= d then t.omT1, t.omT2, t.omT3, t.omT4 = a, b, c, d; t:SetTexCoord(a, b, c, d) end end
-- black at the left fading into (r, g, b) at the right
local function glowRight(t, r, g, b)
  if t.omGR ~= r or t.omGG ~= g or t.omGB ~= b then
    t.omGR, t.omGG, t.omGB = r, g, b
    if GA then GA:SetRGBA(0, 0, 0, 1); GB:SetRGBA(r, g, b, 1); t:SetGradient('HORIZONTAL', GA, GB) end
  end
end

-- health and max health may be hidden numbers: a new reading bumps a counter, and only status bars are handed them
local hpGen, maxGen, lastMax = 0, 0, nil
local function newHealth(cur)
  hpGen = hpGen + 1
  local m = cur.maxv
  if Secret.is(m) or Secret.is(lastMax) or m ~= lastMax then maxGen = maxGen + 1 end
  lastMax = m
end

local function hide()
  if not built then return end
  if P.hidden then M.dropBites(); return end   -- already hidden: nothing left to put away
  P.hidden, P.animating, P.wakeAt = true, false, nil
  clip:Hide(); if win then shown(win, false) end
  for _, r in pairs(M.snap().per) do r.slot = nil end
  for _, s in ipairs(segs) do s.owner = nil; s.shown = 0; shown(s.ghost, false); shown(s.spillC, false) end
  M.dropBites()
end

-- put a mark p health-points from the health's end (negative = into the green), on whichever side it falls
local function setMark(m, p, maxv)
  if m.omGen ~= maxGen then
    m.omGen = maxGen; m.L:SetMinMaxValues(0, maxv); m.R:SetMinMaxValues(0, maxv); m.omP = nil
  end
  local side = p < 0 and 'L' or 'R'
  -- both sides stay alive (never 0): a side WoW had hidden took a frame or two to place when an edge first crossed the
  -- health's end (filmed 2026-11-11: the last DoT's piece vanished for 2 frames as it ended)
  if m.omP ~= p then m.omP = p; m.L:SetValue(math.max(-p, .0001)); m.R:SetValue(math.max(p, .0001)) end
  if side ~= m.side then
    m.f:ClearAllPoints()
    local t, a, b = (side == 'L') and m.lt or m.rt, (side == 'L') and 'TOPLEFT' or 'TOPRIGHT', (side == 'L') and 'BOTTOMLEFT' or 'BOTTOMRIGHT'
    m.f:SetPoint('TOPLEFT', t, a); m.f:SetPoint('BOTTOMLEFT', t, b); m.side = side
  end
end

-- sheet 30 (approved "Yes, build it", 2026-11-11). dots: { {name, damage, expires} } nearest the bar's end first;
-- maxv / hp may be hidden numbers (only handed to status bars). A tick spends part of its own DoT's piece: the bite
-- flares hot in that DoT's colour (60 ms), holds (to 160 ms), then cools to an ember while the gap closes, fast then
-- settling (340 ms). The green never moves. Its ring breathes the same instant.
-- Ticks, bites, precast and landed pieces and ending ghosts are worked out by the model (DotModel.lua); colours and
-- looks by KillBarStyle.lua. It draws only when something moves (P.animating), the numbers changed (P.redraw) or a
-- piece is due to turn gold (P.wakeAt); health alone moves only the skull and the test bar's end.
local look = K.new()                  -- the style's answer for one piece (reused)
local ask = {}                        -- the style's question (reused)
local seen, order, used = {}, {}, {}
local run, slide, wake, moving

-- the skull, and the health's own end (the test bar's): the parts that follow health
local function drawHealth(cur)
  local maxv, hp = cur.maxv, cur.hp
  if P.base.omGen ~= hpGen then P.base.omGen = hpGen; P.base:SetMinMaxValues(0, maxv); P.base:SetValue(hp) end
  -- the skull: hidden when the mob already carries a real raid mark (that one wins)
  if not win then return end -- no portrait on this frame: no skull
  if GetRaidTargetIndex('target') or ns.db.skull == false then shown(win, false)
  else
    shown(win, true)
    if longBar.omGen ~= hpGen then longBar.omGen = hpGen; longBar:SetMinMaxValues(0, hp); longBar.omV = nil end
    if longBar.omV ~= P.total then longBar.omV = P.total; longBar:SetValue(P.total) end
  end
end

local function drawPiece(s, d, i, now, anow)
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
    if want - sh > 1e-6 then moving = true end
    r.shown = sh; seen[d.name] = true
    run = run + sh; s.shown = run; s.sz = sh
    local b = M.biteOf(d.name)
    if b then moving = true end
    -- the style: gold through its last seconds and on past zero while it glides out
    local left = d.expires and (d.expires - now)
    ask.left, ask.low, ask.steady = left, LOWS(), ns.db.lowlook == 'steady'
    ask.provisional, ask.look, ask.pr = d.provisional, ns.db.cast or 'charging', 1
    if d.provisional and d.castStart and d.castEnd and d.castEnd > d.castStart then ask.pr = math.max(0, math.min(1, (now - d.castStart) / (d.castEnd - d.castStart))) end
    local la = M.landAt[d.name]
    ask.landAge, ask.landLook = la and (anow - la) or 9, M.landLook[d.name]
    ask.light, ask.quiet = bl > 0 and (ns.db.tick or 'ember') or nil, b and b.quiet
    local o = K.piece(look, Spells.dot(d.name), ask)
    if o.animating then moving = true end
    if left and not o.lowNow then local w = d.expires - ask.low; if not wake or w < wake then wake = w end end
    local c = o.c
    color3(s.base, o.base[1], o.base[2], o.base[3]); color3(s.lift, o.lift[1], o.lift[2], o.lift[3])
    s.cpr = o.cpr
    local charge = d.provisional and o.cpr ~= nil
    if charge then
      color3(s.cbase, o.fill[1], o.fill[2], o.fill[3]); color3(s.clift, o.fillLift[1], o.fillLift[2], o.fillLift[3])
    end
    shown(s.cbase, charge); shown(s.clift, charge)
    if o.spark then local al = o.spark; glowRight(s.spark, o.glow[1] * al, o.glow[2] * al, o.glow[3] * al) end
    shown(s.spark, o.spark ~= nil)
    if o.stripes then   -- the stripes drift toward the green
      local bw, bh = hb:GetWidth(), hb:GetHeight(); local at = K.stripesAt(anow)
      texCoord(s.pre, at, at + bw / 24, 0, bh / 24); color4(s.pre, o.tn[1], o.tn[2], o.tn[3], K.STRIPES_A)
    end
    shown(s.pre, o.stripes)
    if o.motes then
      local bw = hb:GetWidth(); local at = K.motesAt(anow)
      texCoord(s.motes, at, at + bw / 128 * 2, 0, 1); color3(s.motes, o.tn[1] * K.MOTES_K, o.tn[2] * K.MOTES_K, o.tn[3] * K.MOTES_K)
    end
    shown(s.motes, o.motes)
    s.biteK = 1
    local lit = false
    local np = 0                                      -- particles alive this frame
    if bl > 0 then
      -- settings 'Tick light'. The light (Ember, Cinders, Essence) washes up out of the piece across the seam into the
      -- bitten part (sheet 37: no hard cut, no band) and settles back into its own colour.
      local tone = o.tone
      s.biteK = (b and b.amt > 0) and math.min(1, bl / b.amt) or 0
      s.gtarget = before + bl; color3(s.ghost, o.ghost[1], o.ghost[2], o.ghost[3])
      if o.light ~= 'plain' then
        lit = true
        local a = K.lightA(flare)
        color3(s.spillC, tone[1] * a, tone[2] * a, tone[3] * a)
        glowRight(s.wash, tone[1] * a * .6, tone[2] * a * .6, tone[3] * a * .6)
        if (o.light == 'cinders' or o.light == 'essence') and b and s.right then
          local age = anow - b.at; local H = hb:GetHeight()
          for k = 1, 5 do
            local l, fade, e = K.particle(k, age)
            local t = s.parts[k]
            if l then
              np = k
              local sd = (b.at * 7.3 + k * .618) % 1
              t:ClearAllPoints()
              t:SetPoint('CENTER', s.right, 'LEFT', -px(2 + (k - 1) * 3 + math.sin(age * 4 + k * 1.7) * 2, hb), -H * .3 + e * H * (.5 + sd * .3))
              if o.light == 'cinders' then
                if t.omTex ~= 1 then t.omTex = 1; t:SetTexture('Interface\\AddOns\\OmaDoomed\\Art\\mote') end
                local z = px(5 - 2 * l, hb); t:SetSize(z, z)
                color4(t, tone[1], tone[2], tone[3], .7 * fade)
              else
                if t.omTex ~= 2 then t.omTex = 2; t:SetTexture('Interface\\AddOns\\OmaDoomed\\Art\\haze') end
                local z = px(12 + 16 * l, hb); t:SetSize(z, z)
                color4(t, o.haze[1], o.haze[2], o.haze[3], .45 * fade)
              end
              shown(t, true)
            else shown(t, false) end
          end
        end
      end
    end
    if np == 0 then for k = 1, 5 do shown(s.parts[k], false) end end
    shown(s.ghost, bl > 0); shown(s.spillC, lit); shown(s.wash, lit)
  else
    s.shown = run; s.sz = 0; s.cpr = nil
    for _, t in ipairs(s.quiet) do shown(t, false) end
  end
  local on = d and true or false
  -- no crease next to an empty piece (a DoT that just ended): two creases stacked on one spot, then popped away
  local cr = (on and i > 1 and (s.sz or 0) > .3 and order[i - 1] and (order[i - 1].sz or 0) > .3) and true or false
  shown(s.creaseL, cr); shown(s.creaseR, cr)
  local ck = (ns.db.tick ~= 'plain' and d and s.biteK) and (1 - .85 * s.biteK) or 1; alpha(s.creaseL, ck); alpha(s.creaseR, ck)
  shown(s.base, on); shown(s.lift, on)
end

local function render()
  local cur = M.cur()
  if not cur or not built then return end
  local dots, maxv = cur.dots, cur.maxv
  if #dots == 0 then return hide() end
  if P.hidden then P.hidden = false; clip:Show() end
  local now = GetTime()
  local anow = M.clock()
  run, slide, wake, moving = 0, 0, nil, false
  wipe(seen); wipe(order); wipe(used)
  -- 2026-11-11 'the entire bar repaints for a second when a DoT ends': pieces were slots, so when one DoT left, every
  -- DoT behind it moved into the next slot and borrowed that slot's textures, glows and edges, still showing the old
  -- DoT for a frame or two. Now each DoT owns its slot (textures and edges) for its whole life; when the order
  -- changes only the neighbour anchors move, in the same frame as the edges.
  for j, d in ipairs(dots) do
    if j > MAX then break end
    local r = M.rec(d.name)
    local s = r.slot
    if not s then for _, c in ipairs(segs) do if not c.owner then s = c; break end end end
    if s then s.owner = d.name; r.slot = s; order[#order + 1] = s; used[s] = d end
  end
  for _, r in pairs(M.snap().per) do local s = r.slot; if s and used[s] == nil then s.owner = nil; r.slot = nil end end
  for j, s in ipairs(order) do local right = (j == 1) and P.E[0].f or order[j - 1].edge; if s.right ~= right then P.reanchor(s, right) end end
  for j, s in ipairs(order) do drawPiece(s, used[s], j, now, anow) end
  for _, c in ipairs(segs) do if used[c] == nil then drawPiece(c, nil, 99, now, anow) end end
  for name, r in pairs(M.snap().per) do if not seen[name] then r.shown = nil end end
  -- every edge in one pass, all one link from the health's end
  setMark(P.E[0], slide, maxv)
  for _, s in ipairs(order) do
    setMark(s.mark, slide - s.shown, maxv)
    if s.ghost.omShown and s.gtarget then setMark(s.gmark, slide - s.gtarget, maxv) end
    if s.cpr then setMark(s.cmark, slide - s.shown + s.cpr * (s.sz or 0), maxv) end
  end
  local far = order[#order] or segs[1]
  if P.shineFar ~= far then P.shineFar = far; shine:ClearAllPoints(); shine:SetPoint('TOPRIGHT', P.E[0].f, 'TOPLEFT'); shine:SetPoint('BOTTOMLEFT', far.edge, 'BOTTOMLEFT') end
  -- the pieces hang one status bar deeper than the health's end, and WoW lays each level out a frame later; so the end
  -- takes its new value one frame late too, or on every tick the pieces slipped 2 px for a frame (filmed 2026-11-11)
  local total = 0; for _, d in ipairs(dots) do if not d.provisional and not d.landed then total = total + d.damage end end   -- only confirmed DoTs make the skull
  P.total = total
  drawHealth(cur)
  P.animating, P.wakeAt = moving, wake
end

-- what the bar last drew from, to tell whether new numbers change anything (plain numbers only)
local sig, sigN = {}, 0
local function put(v) sigN = sigN + 1; if sig[sigN] ~= v then sig[sigN] = v; P.redraw = true end end
local function noteChanges(cur)
  sigN = 0
  put(maxGen); put(#cur.dots)
  for _, d in ipairs(cur.dots) do
    put(d.name); put(d.damage); put(d.expires); put(d.provisional or false); put(d.castStart or false); put(d.castEnd or false)
    put(d.landed or false); put(d.ending or false)
    local r = M.peek(d.name); local pr, b = r and r.pred, r and r.bite
    put(pr and pr.est or false); put(b and b.at or false); put(b and b.amt or false); put(b and b.quiet or false)
    put(M.landAt[d.name] or false); put(M.landLook[d.name] or false)
  end
end

-- new numbers (10 times a second and on events): the model notices ticks and keeps them for render
local function draw(dots, maxv, hp)
  if not build() then return end
  local cur = M.feed(dots, maxv, hp)
  newHealth(cur); noteChanges(cur)
  if P.base.omGen ~= hpGen and not P.hidden then P.hpDirty = true end
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
  segs = {}; built = false; P.hidden = nil
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
  if bar and not blizz and ns.text and not tostring(source):find('^path ') then ns.tellOnce('frame:' .. tostring(source), ns.text.frame:format(tostring(source))) end
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
    if build() then shown(P.lost, true); P.hangOn(P.baseEdge) end   -- the empty bar past the fake health (P.base carries its end)
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
local function otherMarkers() if ns.doesItDieOn() then ns.tellOnce('doesitdie', ns.text.doesItDie) end end

function P.start()
  if select(2, UnitClass('player')) ~= 'WARLOCK' then return end
  M.start()
  pcall(otherMarkers)
  local function newTarget()
    for _, s in ipairs(segs) do s.owner = nil; s.shown = 0 end
    P.dirty = true; P.redraw = true; update()
  end
  ns.bus:On('TARGET', newTarget)
  ns.bus:On('DOTS', function() P.dirty = true end)
  ns.bus:On('TICK', function() P.redraw = true end)
  -- health alone moves only the skull (and the test bar's end); a death takes the bar away at once
  ns.bus:On('HEALTH', function()
    if UnitIsDead('target') then P.dirty = true; return end
    local cur = M.cur(); if not cur or test or not built then return end
    cur.hp, cur.maxv = UnitHealth('target'), UnitHealthMax('target')
    local mg = maxGen; newHealth(cur)
    if maxGen ~= mg then P.redraw = true else P.hpDirty = true end
  end)
  ns.bus:On('TARGET_BAR', function() told.hidden = nil; chosenAt = -1; P.dirty = true end)   -- a frame path was set or cleared
  local ev = CreateFrame('Frame')
  -- the skull's whole-number step follows the screen and the UI scale; a raid mark on the target hides the skull
  for _, e in ipairs({ 'UI_SCALE_CHANGED', 'DISPLAY_SIZE_CHANGED', 'RAID_TARGET_UPDATE' }) do pcall(ev.RegisterEvent, ev, e) end
  ev:SetScript('OnEvent', function(_, e) if e == 'RAID_TARGET_UPDATE' then P.hpDirty = true else P.sizeSkull() end end)
  local acc = 0
  ev:SetScript('OnUpdate', function(_, dt)
    M.step(dt)
    acc = acc + dt
    if P.dirty or acc >= .1 then   -- review #6: once a frame at most, however busy
      acc = 0; P.dirty = false
      local ok, err = pcall(update)
      if not ok then ns.fail('update: ' .. tostring(err), 'the kill bar'); P.off = true; pcall(hide); M.clearCur() end
    end
    -- draw only when something moves, the numbers changed, or a piece is due to turn gold
    local ok, err = true, nil
    if P.redraw or P.animating or (P.wakeAt and GetTime() >= P.wakeAt - .001) then
      P.redraw, P.hpDirty = false, false
      ok, err = pcall(render)
    elseif P.hpDirty then
      P.hpDirty = false
      local cur = M.cur()
      if cur and built and not P.hidden then ok, err = pcall(drawHealth, cur) end
    end
    if not ok then ns.fail('render: ' .. tostring(err), 'the kill bar'); P.off = true; pcall(hide); M.clearCur() end
  end)
end

-- /omadoomed on | off    the kill bar part on or off
-- /omadoomed test        fake DoTs on your current target (live)   ... test off
function P.slash(m)
  P.redraw = true
  if m == 'test off' then test = nil; M.test = false; if built then shown(P.lost, false); P.hangOn(fill) end; ns.say('test off.'); return update() end
  if m:match('^test') then
    test = {}; M.test = true; M.forget()
    ns.say('test DoTs on your target. /omadoomed test off'); return update()
  end
  if m == 'on' or m == 'off' then
    ns.db.doomed = (m == 'on'); ns.say('kill bar ' .. (ns.db.doomed and 'on.' or 'off.')); return update()
  end
  ns.say('/omadoomed on|off, options, report, report show, errors, plates, frame · /omadoomed rings on|off, others on|off')
end

-- a setting changed on the Options page (Settings.lua): show it at once
ns.bus:On('SETTING', function(key, store)
  if store == 'rings' then return end
  P.redraw = true
  if key == 'doomed' then update() end
end)
