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

local COLOR = {   -- sheet 34 B 'shadow and fire' (Joshua 2026-11-11: "shadow and fire for sure"): deep pieces, bright only on the tick and the rings
  ['Corruption'] = { 78 / 255, 40 / 255, 136 / 255 }, ['Curse of Agony'] = { 128 / 255, 30 / 255, 74 / 255 },
  ['Bane of Agony'] = { 128 / 255, 30 / 255, 74 / 255 }, ['Immolate'] = { 160 / 255, 66 / 255, 22 / 255 },
  ['Siphon Life'] = { 110 / 255, 20 / 255, 30 / 255 },
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
local clip, shine
local segs = {}
local win, longBar, mark
local last = {}                      -- damage per DoT name last time (a drop = a tick: flash)
local test
local trace                          -- /omadoomed trace: 30 s of numbers, health changes and tick drops (saved on /reload)
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
    if atlasOK(FILL) then P.barMask:SetAtlas(FILL) else P.barMask:SetTexture('Interface\\TargetingFrame\\UI-StatusBar', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE') end
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
    -- borders into the name banner or the mana bar (a plain square did, Joshua 2026-11-11)
    s.creaseL = art:CreateTexture(nil, 'OVERLAY', nil, 0); barTex(s.creaseL)
    s.creaseR = art:CreateTexture(nil, 'OVERLAY', nil, 0); barTex(s.creaseR)
    local g = s.flash:CreateAnimationGroup()
    local a1 = g:CreateAnimation('Alpha'); a1:SetFromAlpha(0); a1:SetToAlpha(.42); a1:SetDuration(.08); a1:SetOrder(1)
    local a2 = g:CreateAnimation('Alpha'); a2:SetFromAlpha(.42); a2:SetToAlpha(0); a2:SetDuration(.45); a2:SetOrder(2); a2:SetSmoothing('OUT')
    s.flashAnim = g
    -- sheet 27 (approved "Looks right"): the bite. A second bar holds where this piece's edge WAS; the chunk between it and
    -- the new edge glows bright in the DoT's colour, holds 120 ms, then drains over 380 ms.
    s.gmark = newMark(); s.gedge = s.gmark.f
    -- sheet 36 C 'charging' (Joshua 2026-11-11: "Yes, build it"): while you cast, the piece fills with your cast bar in
    -- its landed colour (so landing changes nothing), an ember glow in its own colour at the front; never white
    s.cmark = newMark()
    s.cbase = art:CreateTexture(nil, 'ARTWORK', nil, 1); barTex(s.cbase); s.cbase:Hide()
    s.clift = art:CreateTexture(nil, 'ARTWORK', nil, 2); barTex(s.clift); s.clift:SetBlendMode('ADD'); s.clift:Hide()
    for _, t in ipairs({ s.cbase, s.clift }) do t:SetPoint('TOPLEFT', s.edge, 'TOPLEFT'); t:SetPoint('BOTTOMRIGHT', s.cmark.f, 'BOTTOMLEFT') end
    s.spark = art:CreateTexture(nil, 'OVERLAY', nil, 5); barTex(s.spark); s.spark:SetBlendMode('ADD'); s.spark:Hide()
    s.spark:SetPoint('TOPRIGHT', s.cmark.f, 'TOPLEFT', px(2, hb), 0); s.spark:SetPoint('BOTTOMRIGHT', s.cmark.f, 'BOTTOMLEFT', px(2, hb), 0); s.spark:SetWidth(px(8, hb))
    s.ghost = art:CreateTexture(nil, 'ARTWORK', nil, 5); barTex(s.ghost); s.ghost:Hide()   -- the bite: solid, its own colour
    -- while you cast it (DoesItDie marks it provisional): Blizzard's own shield stripes and shield edge glow, tinted
    s.pre = art:CreateTexture(nil, 'ARTWORK', nil, 4); s.pre:SetTexture('Interface/RaidFrame/Shield-Overlay', 'REPEAT', 'REPEAT')
    s.pre:SetHorizTile(true); s.pre:SetVertTile(true); s.pre:SetDesaturated(true); s.pre:SetBlendMode('ADD'); s.pre:Hide()   -- the art is shield-blue: grey it, then tint
    s.preGlow = art:CreateTexture(nil, 'OVERLAY', nil, 3); s.preGlow:SetTexture('Interface/RaidFrame/Shield-Overshield'); s.preGlow:SetBlendMode('ADD'); s.preGlow:SetDesaturated(true); s.preGlow:Hide()
    -- the light it casts: 9 screen px onto each neighbour, fading out (left fade, core, right fade), the bar's own shape
    s.spillL = art:CreateTexture(nil, 'OVERLAY', nil, 4); barTex(s.spillL); s.spillL:SetBlendMode('ADD'); s.spillL:Hide()
    s.spillC = art:CreateTexture(nil, 'OVERLAY', nil, 4); barTex(s.spillC); s.spillC:SetBlendMode('ADD'); s.spillC:Hide()
    s.spillR = art:CreateTexture(nil, 'OVERLAY', nil, 4); barTex(s.spillR); s.spillR:SetBlendMode('ADD'); s.spillR:Hide()
    -- every texture of a piece keeps to the health bar's own shape (2026-11-11: Joshua saw colour outside the bar once)
    if P.barMask then
      for _, t in ipairs({ s.base, s.lift, s.flash, s.join, s.joinLift, s.creaseL, s.creaseR, s.ghost, s.spillL, s.spillC, s.spillR, s.pre, s.preGlow, s.cbase, s.clift, s.spark }) do t:AddMaskTexture(P.barMask) end
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
    -- don't, so a 1 px sliver of green showed beside it (Joshua, 2026-11-11: 'a tiny bit of green peeking out')
    local dx = (right == P.E[0].f) and px(1, hb) or 0
    for _, t in ipairs({ s.base, s.lift, s.flash, s.pre }) do t:ClearAllPoints(); t:SetPoint('TOPLEFT', s.edge, 'TOPLEFT'); t:SetPoint('BOTTOMRIGHT', right, 'BOTTOMLEFT', dx, 0) end
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
  P.hpLate = nil
  clip:Hide(); win:Hide()
  wipe(P.slotOf)
  for _, s in ipairs(segs) do s.owner = nil; s.shown = 0; s.ghost:Hide(); s.spillL:Hide(); s.spillC:Hide(); s.spillR:Hide() end
  wipe(P.bites)
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

local function colorOf(name) return COLOR[name] or OTHER end

-- sheet 30 (approved "Yes, build it", 2026-11-11). Every frame. dots: { {name, damage, expires} } nearest the bar's end
-- first; maxv / hp may be hidden numbers (only handed to status bars). A tick spends part of its own DoT's piece: the
-- bite flares hot in that DoT's colour (60 ms), holds (to 160 ms), then cools to an ember while the gap closes, fast
-- then settling (340 ms); it lights 9 px of its neighbours. The green never moves. Its ring breathes the same instant.
P.bites = {}                         -- DoT name -> { amt, at }
local biteNow                        -- defined below; P.onHealth needs it (it was a nil global before)
-- the animation clock: like GetTime, but a stall of the game (0.15-0.2 s seen in town) only moves it one frame, so a
-- slide carries on from where it was instead of skipping ahead
local function aclock() return P.clock or GetTime() end
P.pred = {}                          -- DoT name -> { est, at, k }: a tick shown on its beat, waiting for DoesItDie's number
local BEAT = { ['Corruption'] = 3, ['Curse of Agony'] = 2, ['Bane of Agony'] = 2, ['Immolate'] = 3, ['Siphon Life'] = 3 }
-- the health just changed: if a DoT is due to tick right now (its beat, within 0.25 s), start its bite this frame
function P.onHealth()
  if not cur or test then return end
  local now = GetTime()
  local note = trace and { string.format('HEALTH %.3f', now - trace.t0) }
  for _, d in ipairs(cur.dots) do
    local beat = d.appliedAt and (BEAT[d.name] or 3)
    if note then
      local kk = beat and math.floor((now - d.appliedAt) / beat + .5)
      note[#note + 1] = d.name:sub(1, 3) .. (beat and string.format(' k%d off%.3f pk%d', kk, now - (d.appliedAt + kk * beat), P.predK[d.name] or 0) or ' noApplied') .. (d.provisional and ' P' or '')
    end
    if beat and not d.provisional then
      local k = math.floor((now - d.appliedAt) / beat + .5)
      if k >= 1 and math.abs(now - (d.appliedAt + k * beat)) < .25 and (P.predK[d.name] or 0) < k then
        P.predK[d.name] = k
        local ticksLeft = math.max(1, math.floor(((d.expires or now) - (d.appliedAt + k * beat)) / beat + .5) + 1)
        local est = d.damage / ticksLeft
        local was = biteNow(d.name, aclock())
        P.bites[d.name] = { amt = was + est, at = aclock() }
        P.pred[d.name] = { est = est, at = now }
        if ns.ringsPulse then pcall(ns.ringsPulse, 'target', d.name) end
        if note then note[#note + 1] = 'PREDICTED ' .. d.name:sub(1, 3) .. string.format(' est%.1f', est) end
      end
    end
  end
  if note then trace.rows[#trace.rows + 1] = table.concat(note, ' | ') end
end
P.predK = {}
P.landAt = {}
P.shownBy = {}               -- DoT name -> its piece's size on screen
P.wasPre = {}
P.slotOf = {}                -- DoT name -> the slot (textures and edges) it owns
P.fullBy = {}                -- DoT name -> its full damage when fresh (for a first cast DoesItDie doesn't list yet)
local EMPTY = { 30 / 255, 19 / 255, 10 / 255 }
local function easeOut(x) x = math.max(0, math.min(1, x)); return 1 - (1 - x) ^ 3 end
local function mix(a, b, k) return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k } end
local RINGTONE = {   -- the rings' own colours (Rings.lua), for the tick
  ['Corruption'] = { 176 / 255, 120 / 255, 1 }, ['Curse of Agony'] = { 240 / 255, 84 / 255, 150 / 255 }, ['Bane of Agony'] = { 240 / 255, 84 / 255, 150 / 255 },
  ['Immolate'] = { 1, 138 / 255, 61 / 255 }, ['Siphon Life'] = { 214 / 255, 48 / 255, 72 / 255 },
}
local RINGGOLD = { 1, 214 / 255, 110 / 255 }

biteNow = function(name, now)    -- what is still left of a bite (0 when done), and its flare 0..1
  local b = P.bites[name]; if not b then return 0, 0 end
  local a = now - b.at
  if a >= .7 then P.bites[name] = nil; return 0, 0 end
  -- 2026-11-11 'it flashes then almost jumps': the glide started at full speed the instant the light peaked. Now it
  -- starts from rest, is quickest midway and settles (smootherstep over 0.5 s); the light swells instead of flashing.
  local k = math.max(0, math.min(1, a / .5)); k = k * k * k * (k * (k * 6 - 15) + 10)
  local left = b.amt * (1 - k)
  -- 2026-11-11 'the ticks are a bit jumpy, plain is smooth': the light swells and settles on smooth curves and cools back
  -- into the piece's own colour (it used to start from, and cool to, a dark ember: a dip that read as a jump)
  local function ss(v) v = math.max(0, math.min(1, v)); return v * v * (3 - 2 * v) end
  local flare = a < .16 and ss(a / .16) or 1 - ss((a - .16) / .5)
  return left, flare
end

local cur                            -- the latest dots, maxv, hp (from update), drawn every frame
function ns.startTrace() trace = { t0 = GetTime(), untilT = GetTime() + 150, rows = {} }; OmaDoomedDB.trace = trace.rows; ns.say('tracing 150 s (saved as it goes)') end
local traceRow
local function traceFrame(now) if trace then local ok, e = pcall(traceRow, now); if not ok then OmaDoomedDB.traceErr = tostring(e); trace = nil end end end
traceRow = function(now)
  if now > trace.untilT then OmaDoomedDB.trace = trace.rows; trace = nil; ns.say('trace saved (' .. #OmaDoomedDB.trace .. ' frames); /reload to write it'); return end
  local row = { string.format('%.3f', now - trace.t0), string.format('dt%.3f', P.dt or 0) }
  row[#row + 1] = 'hp' .. tostring(cur and cur.hp)
  for i, d in ipairs(cur and cur.dots or {}) do row[#row + 1] = d.name:sub(1, 3) .. string.format('%.1f', d.damage) .. (d.provisional and 'P' or '') .. (d.ending and 'E' or '') end
  for i = 1, 3 do local s = segs[i]; row[#row + 1] = s and (string.format('%.2f', s.shown) .. (s.mark.side or '?')) or '-' end
  for n, v in pairs(P.shownBy) do row[#row + 1] = n:sub(1, 3) .. '=' .. string.format('%.2f', v) end
  row[#row + 1] = 'S' .. string.format('%.2f', P.slideV or 0)
  for n, b in pairs(P.bites) do row[#row + 1] = n:sub(1, 3) .. string.format('%.2f', now - b.at) end
  trace.rows[#trace.rows + 1] = table.concat(row, ' ')
end
local function render()
  if not cur or not built then return end
  local dots, maxv, hp = cur.dots, cur.maxv, cur.hp
  if #dots == 0 then return hide() end
  clip:Show()
  local now = GetTime()
  local anow = aclock()
  local run, slide = 0, 0
  local seen = {}
  -- 2026-11-11 'the entire bar repaints for a second when a DoT ends': pieces were slots, so when one DoT left, every
  -- DoT behind it moved into the next slot and borrowed that slot's textures, glows and edges, still showing the old
  -- DoT for a frame or two. Now each DoT owns its slot (textures and edges) for its whole life; when the order
  -- changes only the neighbour anchors move, in the same frame as the edges.
  local order, used = {}, {}
  for j, d in ipairs(dots) do
    if j > MAX then break end
    local s = P.slotOf[d.name]
    if not s then for _, c in ipairs(segs) do if not c.owner then s = c; break end end end
    if s then s.owner = d.name; P.slotOf[d.name] = s; order[#order + 1] = s; used[s] = d end
  end
  for name, s in pairs(P.slotOf) do if used[s] == nil then s.owner = nil; P.slotOf[name] = nil end end
  for j, s in ipairs(order) do local right = (j == 1) and P.E[0].f or order[j - 1].edge; if s.right ~= right then P.reanchor(s, right) end end
  local seq = {}
  for j, s in ipairs(order) do seq[#seq + 1] = { s, used[s], j } end
  for _, c in ipairs(segs) do if used[c] == nil then seq[#seq + 1] = { c, nil, 99 } end end
  for _, e in ipairs(seq) do
    local s, d, i = e[1], e[2], e[3]
    if d then
      local bl, flare = biteNow(d.name, anow); slide = slide + bl
      local before = run                                 -- where this piece starts, from the bar's end
      local pr = P.pred[d.name]
      -- each DoT remembers its OWN size (2026-11-11: sizes were kept per slot, so when a DoT ended the others moved up a
      -- slot, took the wrong size and regrew: the green jumped out). A new or refreshed DoT grows in; shrinking is bites.
      local want = math.max(0, d.damage - (pr and pr.est or 0)) + bl
      local sh = P.shownBy[d.name] or 0
      if want > sh then sh = sh + (want - sh) * (1 - math.exp(-(P.dt or .033) * 9)) else sh = want end
      P.shownBy[d.name] = sh; seen[d.name] = true
      run = run + sh; s.shown = run; s.sz = sh
      local left = d.expires and (d.expires - now)
      local lowNow = left and left <= LOW   -- gold through its last 3 s and on past zero while it glides out (it flipped back)
      local c = colorOf(d.name)
      if lowNow then local b = .6 + .4 * breath(left); c = { GOLD[1] * b, GOLD[2] * b, GOLD[3] * b } end
      local tn = RINGTONE[d.name] or c
      local sp = mix(c, tn, .7)   -- the glow: its own colour, low (no white: warlock light)
      local function spark(al)
        if CreateColor then s.spark:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 1), CreateColor(sp[1] * al, sp[2] * al, sp[3] * al, 1)) end
        s.spark:Show()
      end
      s.pre:Hide(); s.preGlow:Hide()
      if d.provisional and ns.db.doomedPrecast ~= false then   -- still being cast: dark, filling with the cast bar
        local pr = 1
        if d.castStart and d.castEnd and d.castEnd > d.castStart then pr = math.max(0, math.min(1, (now - d.castStart) / (d.castEnd - d.castStart))) end
        s.cpr = pr
        s.base:SetVertexColor(c[1] * .45, c[2] * .45, c[3] * .45); s.lift:SetVertexColor(0, 0, 0)
        s.cbase:SetVertexColor(math.min(1, c[1] * 1.15), math.min(1, c[2] * 1.15), math.min(1, c[3] * 1.15)); s.cbase:Show()
        s.clift:SetVertexColor(c[1] * .7, c[2] * .7, c[3] * .7); s.clift:Show()
        spark(.45)
        P.wasPre[d.name] = true
      else
        if P.wasPre[d.name] then P.landAt[d.name] = anow; P.wasPre[d.name] = nil end
        s.cbase:Hide(); s.clift:Hide()
        local la = P.landAt[d.name] and (anow - P.landAt[d.name]) or 9   -- it landed: nothing changes but the glow fading where it ended
        if la < .35 then s.cpr = 1; spark(.45 * (1 - la / .35) ^ 2) else s.cpr = nil; s.spark:Hide() end
        s.base:SetVertexColor(math.min(1, c[1] * 1.15), math.min(1, c[2] * 1.15), math.min(1, c[3] * 1.15))
        s.lift:SetVertexColor(c[1] * .7, c[2] * .7, c[3] * .7)
      end
      if bl > 0 then
        -- 2026-11-11 'when a DoT ends there's still a flash': its last tick always lands in the gold last 3 s, and lit up
        -- in bright ring gold x1.85, near white. The light now comes from the piece's own colour, like every other tick.
        local tone = lowNow and { math.min(1, c[1] * 1.3), math.min(1, c[2] * 1.3), math.min(1, c[3] * 1.3) } or (RINGTONE[d.name] or c)
        local hot = mix(c, tone, .4)
        local base = c; local ember = mix(base, EMPTY, .75)
        local col = mix(base, hot, flare)
        s.gtarget = before + bl; s.ghost:SetVertexColor(math.min(1, col[1] * 1.85), math.min(1, col[2] * 1.85), math.min(1, col[3] * 1.85)); s.ghost:Show()   -- 1.85: base 1.15 + lift .7, as the pieces
        local a = flare * .4
        s.spillC:SetVertexColor(tone[1] * a, tone[2] * a, tone[3] * a)
        if CreateColor then
          s.spillL:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 0), CreateColor(tone[1] * a, tone[2] * a, tone[3] * a, 1))
          s.spillR:SetGradient('HORIZONTAL', CreateColor(tone[1] * a, tone[2] * a, tone[3] * a, 1), CreateColor(0, 0, 0, 0))
        end
        s.spillC:Show(); s.spillL:Hide(); s.spillR:Hide()   -- 2026-11-11 'bouncy': the light past the bite's edges made the bar swell out and back; the glow stays on the bite
      else
        s.ghost:Hide(); s.spillL:Hide(); s.spillC:Hide(); s.spillR:Hide()
      end
    else
      s.shown = run; s.sz = 0; s.cpr = nil; s.cbase:Hide(); s.clift:Hide(); s.spark:Hide(); s.pre:Hide(); s.preGlow:Hide(); s.ghost:Hide(); s.spillL:Hide(); s.spillC:Hide(); s.spillR:Hide()
    end
    local on = d and true or false
    local mode = ns.db.doomedJoin or 'crease'
    local jw = mode == 'crease' and 0 or (JOIN[mode] or 0)
    -- no crease next to an empty piece (a DoT that just ended): two creases stacked on one spot, then popped away
    local cr = on and i > 1 and mode == 'crease' and (s.sz or 0) > .3 and order[i - 1] and (order[i - 1].sz or 0) > .3
    s.creaseL:SetShown(cr); s.creaseR:SetShown(cr)
    if jw > 0 then s.join:SetWidth(px(jw, hb)); s.joinLift:SetWidth(px(jw, hb)) end
    s.base:SetShown(on); s.lift:SetShown(on); s.flash:SetShown(false); s.join:SetShown(on and i > 1 and jw > 0); s.joinLift:SetShown(on and i > 1 and jw > 0)
  end
  -- the pieces hang one status bar deeper than the health's end, and WoW lays each level out a frame later; so the end
  -- takes its new value one frame late too, or on every tick the pieces slipped 2 px for a frame (filmed 2026-11-11)
  P.base:SetMinMaxValues(0, maxv); P.base:SetValue(hp)
  for name in pairs(P.shownBy) do if not seen[name] then P.shownBy[name] = nil end end
  -- every edge in one pass, all one link from the health's end
  setMark(P.E[0], slide, maxv)
  for _, s in ipairs(order) do
    setMark(s.mark, slide - s.shown, maxv)
    if s.ghost:IsShown() and s.gtarget then setMark(s.gmark, slide - s.gtarget, maxv) end
    if s.cpr then setMark(s.cmark, slide - s.shown + s.cpr * (s.sz or 0), maxv) end
  end
  P.slideV = slide
  traceFrame(now)
  local far = order[#order] or segs[1]
  shine:ClearAllPoints(); shine:SetPoint('TOPRIGHT', P.E[0].f, 'TOPLEFT'); shine:SetPoint('BOTTOMLEFT', far.edge, 'BOTTOMLEFT')
  -- the skull: hidden when the mob already carries a real raid mark (that one wins)
  local total = 0; for _, d in ipairs(dots) do total = total + d.damage end
  if GetRaidTargetIndex('target') then win:Hide() else win:Show(); longBar:SetMinMaxValues(0, hp); longBar:SetValue(total) end
end

-- new numbers (10 times a second and on events): notice ticks, keep them for render
local function draw(dots, maxv, hp)
  if not build() then return end
  local now = GetTime()
  -- 2026-11-11 'when a DoT ends there's still a snap': the last tick made it vanish from the list, so its piece and
  -- the slide went with it. Now it stays in its old place, empty, while that last bite glides shut.
  local here = {}; for _, d in ipairs(dots) do here[d.name] = true end
  for idx, name in ipairs(P.order or {}) do
    if not here[name] then
      local pr = P.pred[name]
      local remaining = (last[name] or 0) - (pr and pr.est or 0)
      if remaining > .5 then
        local b = P.bites[name]
        if b then b.amt = b.amt + remaining else P.bites[name] = { amt = remaining, at = aclock() }; if ns.ringsPulse then pcall(ns.ringsPulse, 'target', name) end end
      end
      P.pred[name] = nil; last[name] = 0
      if P.bites[name] and biteNow(name, aclock()) > 0 then
        table.insert(dots, math.min(idx, #dots + 1), { name = name, damage = 0, expires = P.exp and P.exp[name], ending = true })
      else last[name] = nil end
    end
  end
  P.order, P.exp = {}, {}
  for i, d in ipairs(dots) do P.order[i] = d.name; P.exp[d.name] = d.expires end
  local drop = false
  for _, d in ipairs(dots) do if last[d.name] and d.damage < last[d.name] - .5 then drop = true end end
  for _, d in ipairs(dots) do
    if last[d.name] and d.damage < last[d.name] - .5 then
      local real = last[d.name] - d.damage
      local pr = P.pred[d.name]
      if trace then trace.rows[#trace.rows + 1] = string.format('DROP %.3f %s real%.1f %s', now - trace.t0, d.name:sub(1, 3), real, pr and string.format('pred est%.1f %.3fs ago', pr.est, now - pr.at) or 'unpredicted') end
      if pr and now - pr.at < 1 then
        -- already showing: this tick was predicted on its beat. Only the size is corrected (a small change).
        local b = P.bites[d.name]; if b then b.amt = math.max(0, b.amt + real - pr.est) end
        P.pred[d.name] = nil
      else
        local was = biteNow(d.name, aclock())
        P.bites[d.name] = { amt = was + real, at = aclock() }
        if ns.ringsPulse then pcall(ns.ringsPulse, 'target', d.name) end   -- its ring, same instant
      end
    end
    last[d.name] = d.damage
  end
  for name, pr in pairs(P.pred) do if now - pr.at >= 1 then P.pred[name] = nil end end   -- not a tick after all
  cur = { dots = dots, maxv = maxv, hp = hp }
  render()
end

local function update()
  if not ns.db or not ns.db.doomed then cur = nil; return hide() end
  if test then
    if not UnitExists('target') then cur = nil; return hide() end
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
  if not UnitExists('target') or UnitIsDead('target') or not (DoesItDie and DoesItDie.GetDoTs) then cur = nil; return hide() end
  local list = DoesItDie.GetDoTs('target')
  table.sort(list, function(a, b) return (a.expiresAt or 0) < (b.expiresAt or 0) end)   -- runs out first = nearest the green
  local dots = {}
  local cName, _, _, cStart, cEnd = UnitCastingInfo('player')
  for _, e in ipairs(list) do if (e.damage or 0) > 0 then
    local d = { name = e.name, damage = e.damage, expires = e.expiresAt, appliedAt = e.appliedAt, provisional = e.provisional }
    if e.provisional and cName == e.name and cStart and cEnd then d.castStart, d.castEnd = cStart / 1000, cEnd / 1000 end
    if not e.provisional and e.appliedAt and GetTime() - e.appliedAt < 4 then P.fullBy[e.name] = math.max(P.fullBy[e.name] or 0, e.damage) end
    dots[#dots + 1] = d
  end end
  -- DoesItDie leaves a fresh DoT out until its first tick, so a first cast showed nothing (Joshua: "i didnt see precast").
  -- While you cast a DoT it doesn't list, show it at the size it last had when fresh.
  if cName and COLOR[cName] and cStart and cEnd and P.fullBy[cName] then
    local listed = false; for _, d in ipairs(dots) do if d.name == cName then listed = true end end
    if not listed then dots[#dots + 1] = { name = cName, damage = P.fullBy[cName], expires = cEnd / 1000 + 30, provisional = true, castStart = cStart / 1000, castEnd = cEnd / 1000 } end
  end
  -- and once it lands, keep it (solid) until DoesItDie lists it at its first tick, so it doesn't blink out for 3 s
  local ld = P.landed
  if ld and not cName then
    local listed = false; for _, d in ipairs(dots) do if d.name == ld.name then listed = true end end
    if listed or GetTime() - ld.at > 4.5 then P.landed = nil
    else dots[#dots + 1] = { name = ld.name, damage = ld.dmg, expires = ld.at + 30 } end
  end
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
  ev:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
  ev:RegisterEvent('PLAYER_TARGET_CHANGED'); ev:RegisterUnitEvent('UNIT_HEALTH', 'target'); ev:RegisterUnitEvent('UNIT_AURA', 'target')
  ev:SetScript('OnEvent', function(_, e, unit, _, spellID)
    if e == 'UNIT_SPELLCAST_SUCCEEDED' then
      local n = spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
      if n and COLOR[n] and P.fullBy[n] then P.landed = { name = n, at = GetTime(), dmg = P.fullBy[n] } end
      return
    end
    if e == 'UNIT_HEALTH' then pcall(P.onHealth) end; if e == 'PLAYER_TARGET_CHANGED' then wipe(last); wipe(P.bites); cur = nil; wipe(P.pred); wipe(P.predK); wipe(P.shownBy); wipe(P.wasPre); wipe(P.slotOf); P.landed = nil; for _, s in ipairs(segs) do s.owner = nil end; P.order = nil; for _, s in ipairs(segs) do s.shown = 0 end end; update() end)
  local acc = 0
  ev:SetScript('OnUpdate', function(_, dt) P.dt = math.min(dt, .05); P.clock = aclock() + math.min(dt, .05); local ok, err = pcall(render); if not ok then ns.say('Doomed stopped: ' .. tostring(err)); ns.db.doomed = false; hide(); cur = nil end; acc = acc + dt; if acc >= .1 then acc = 0; update() end end)
  if DoesItDie.RegisterCallback then DoesItDie.RegisterCallback(ADDON, function() update() end) end
end

-- /omadoomed            on/off
-- /omadoomed test       fake DoTs on your current target (live)   /omadoomed test die   (doomed)   ... test off
function P.slash(m)
  local j = m:match('^join (%a+)'); if j and JOIN[j] then ns.db.doomedJoin = j; ns.say('Doomed join: ' .. j); return update() end
  if m == 'test off' then test = nil; if built then P.lost:Hide(); P.hangOn(fill) end; ns.say('Doomed test off'); return update() end
  if m:match('^test') then
    test = {}; wipe(last); wipe(P.bites)
    ns.say('Doomed test on your target (Bujuju\'s real ticks, sheet 30). /omadoomed test off'); return update()
  end
  ns.db.doomed = not ns.db.doomed; quiet(ns.db.doomed); ns.say('Doomed ' .. (ns.db.doomed and 'on' or 'off (DoesItDie back after /reload)')); update()
end
