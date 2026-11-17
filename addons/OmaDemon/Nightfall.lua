-- OmaDemon: Nightfall (sheet 78, approved 2026-11-16; plan phase 7).
-- When Nightfall procs, Shadow Trance (your next Shadow Bolt is instant) shows the way Blizzard shows it in later games
-- (sheet 97, 2026-11-17 "Yes, build it"): Blizzard's own Nightfall art, two thorned violet crescents either side of your
-- character, placed, sized and pulsing exactly as Blizzard's SpellActivationOverlay code does it (256 x 0.8 UI units
-- square at the screen's centre, the crescents 0.4 x 0.8 of it outside its left and right edges, 0.2 s fade in, a
-- 1.08 / 0.926 pulse each second), with Blizzard's proc chime (SOUNDKIT.UI_POWER_AURA_GENERIC) once. Forever doesn't
-- show these overlays itself (other Forever add-ons rebuild them); if it ever does for Shadow Trance, ours stands down.
-- The art: the game's own file when the client has it, else the copy in art\nightfall_overlay (captured 2026-11-17).
-- Blizzard's own AuraContainer reads the buff: ONE aura slot on 'player', HELPFUL, allowed only Shadow Trance's spell
-- IDs. The game shows the slot's button while the buff is up and hides it when it goes; the glow is that button, so
-- nothing here ever reads an aura or watches a timer.
-- Shadow Bolt's button: Blizzard's own proc glow (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW) may already light it on
-- Forever. Until that event has been seen once for Shadow Bolt, the same slot button also carries a violet glow over
-- your Shadow Bolt action button (a child frame pinned to our own anchor, which we move over the button out of
-- combat). Once Blizzard's glow is seen, ours shrinks to nothing for good (saved), so there are never two.
-- To check in game: /omademon nightfall shows it for 4 s with its chime; a real proc needs the talent (level 25).
local _, ns = ...

local ART = 'Interface\\AddOns\\OmaDemon\\art\\'
local VIOLET = { .66, .38, 1 }
-- Shadow Trance, the Nightfall proc (Classic 17941; Forever keeps Classic's IDs for Classic spells). The name is
-- looked up as well, in case Forever gave it a new ID.
local IDS = { 17941 }
local NAMES = { 'Shadow Trance' }       -- never 'Nightfall': that's the talent, a passive that would light it for good
local N = { ids = IDS }
ns.nightfall = N

local function idSet()
  local set = {}
  for _, id in ipairs(IDS) do set[id] = true end
  for _, n in ipairs(NAMES) do
    local ok, id = pcall(function()
      if C_Spell and C_Spell.GetSpellInfo then local i = C_Spell.GetSpellInfo(n); return i and i.spellID end
      return GetSpellInfo and select(7, GetSpellInfo(n))
    end)
    if ok and type(id) == 'number' then set[id] = true end
  end
  return set
end

-- our own anchor for the Shadow Bolt glow: moved over the button out of combat, size 0 when there's nothing to light
local sb = CreateFrame('Frame', 'OmaDemonNightfallAnchor', UIParent); sb:SetSize(0.001, 0.001); sb:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', -50, -50)
N.anchor = sb

-- Blizzard's numbers (SpellActivationOverlay.lua, Classic Era): sizeScale 0.8 of 256 / 128
local LONG, SHORT = 256 * .8, 128 * .8
local GAME_ART = 'Textures\\SpellActivationOverlays\\Nightfall'
local function artPath()
  local ok, id = pcall(function() return GetFileIDFromPath and GetFileIDFromPath(GAME_ART) end)
  if ok and id then N.artFrom = 'game'; return id end
  N.artFrom = 'add-on'; return ART .. 'nightfall_overlay'
end
local function opacity()
  local ok, v = pcall(function() return Settings and Settings.GetValue and Settings.GetValue('spellActivationOverlayOpacity') end)
  return (ok and type(v) == 'number') and v or 1
end
-- colours (setting 'Colour'): Blizzard's art as made, or recoloured the way Blizzard tints proc art (SetVertexColor),
-- on the art made grey first so the colour comes through clean; a second, added copy keeps the core bright
local TINTS = { fel = { .42, 1, .3 }, ember = { 1, .52, .16 }, blood = { 1, .16, .14 } }
local function paint(f)
  local c = TINTS[ns.groupDB().nfColour or 'violet']
  for _, sd in ipairs(f.sides) do
    sd.tex:SetDesaturated(c and true or false); sd.glow:SetDesaturated(true)
    if c then sd.tex:SetVertexColor(c[1], c[2], c[3]); sd.glow:SetVertexColor(c[1] * .7, c[2] * .7, c[3] * .7); sd.glow:Show()
    else sd.tex:SetVertexColor(1, 1, 1); sd.glow:Hide() end
  end
end
N.paint = paint
local lastChime = -math.huge
local function chime()
  if ns.groupDB().nfSound == false or ns.groupDB().nfOn == false or not PlaySound then return end
  local now = GetTime and GetTime() or 0
  if now - lastChime < 2 then return end   -- a flicker of the buff never chimes twice
  lastChime = now
  N.chimed = (N.chimed or 0) + 1
  pcall(PlaySound, (SOUNDKIT and SOUNDKIT.UI_POWER_AURA_GENERIC) or 23287, 'SFX')
end
-- the two crescents, on a frame of their own under `parent` (the game's aura button, or UIParent for the preview).
-- Under the game's button no OnShow/OnHide is allowed, not even on our own frame (BugSack 2026-11-17: "blocked by
-- secret aspects"; whether it shows is the secret). So there the pulse just loops from the start and the game's
-- showing the button is the whole effect: no fade-in and no chime on a real proc. The preview keeps both.
local function settle(f)
  local off = ns.groupDB().nfOverlayBlizz or ns.groupDB().nfOn == false
  f:SetAlpha(off and 0 or opacity())
end
N.settle = settle
function N.crescents(parent)
  local f = CreateFrame('Frame', nil, parent); f:SetSize(LONG, LONG); f:ClearAllPoints(); f:SetPoint('CENTER', UIParent, 'CENTER')
  pcall(f.SetFrameStrata, f, 'BACKGROUND')
  local art, sides = artPath(), {}
  for i, where in ipairs({ 'LEFT', 'RIGHT' }) do
    local o = CreateFrame('Frame', nil, f); o:SetSize(SHORT, LONG)
    if where == 'LEFT' then o:SetPoint('RIGHT', f, 'LEFT') else o:SetPoint('LEFT', f, 'RIGHT') end
    local t = o:CreateTexture(nil, 'ARTWORK'); t:SetAllPoints(o); t:SetTexture(art)
    local gl = o:CreateTexture(nil, 'ARTWORK', nil, 1); gl:SetAllPoints(o); gl:SetTexture(art); gl:SetBlendMode('ADD'); gl:Hide()
    if where == 'RIGHT' then t:SetTexCoord(1, 0, 0, 1); gl:SetTexCoord(1, 0, 0, 1) end   -- mirrored, as Blizzard flips the right one
    local ag = o:CreateAnimationGroup(); ag:SetLooping('REPEAT')
    local up = ag:CreateAnimation('Scale'); up:SetScale(1.08, 1.08); up:SetDuration(.5); up:SetSmoothing('IN_OUT'); up:SetOrder(1)
    local down = ag:CreateAnimation('Scale'); down:SetScale(.9259, .9259); down:SetDuration(.5); down:SetSmoothing('IN_OUT'); down:SetOrder(2)
    sides[i] = { frame = o, tex = t, glow = gl, pulse = ag }
  end
  local fade = f:CreateAnimationGroup()
  local a = fade:CreateAnimation('Alpha'); a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(.2)
  f.sides, f.fade = sides, fade
  paint(f)
  if parent ~= UIParent then
    settle(f)
    if not (ns.reduced and ns.reduced()) then for _, sd in ipairs(sides) do sd.pulse:Play() end end
    return f
  end
  f:SetScript('OnShow', function(self)
    if ns.groupDB().nfOverlayBlizz or ns.groupDB().nfOn == false then self:SetAlpha(0); return end
    paint(self)
    self:SetAlpha(opacity())
    chime()
    if not (ns.reduced and ns.reduced()) then
      self.fade:Play()
      for _, sd in ipairs(self.sides) do sd.pulse:Play() end
    end
  end)
  f:SetScript('OnHide', function(self) for _, sd in ipairs(self.sides) do sd.pulse:Stop() end end)
  return f
end

-- out of a fight: show it for a few seconds, with its chime (you can't proc it until the talent, level 25)
function N.preview(secs)
  if not N.previewFrame then N.previewFrame = N.crescents(UIParent); N.previewFrame:Hide() end
  local f = N.previewFrame
  lastChime = -math.huge; f:Hide(); f:Show()
  if C_Timer then C_Timer.After(secs or 4, function() f:Hide() end) end
  return f
end

local function breathe(tex, from, to)
  local ag = tex:CreateAnimationGroup(); ag:SetLooping('BOUNCE')
  local a = ag:CreateAnimation('Alpha'); a:SetFromAlpha(from); a:SetToAlpha(to); a:SetDuration(.9); a:SetSmoothing('IN_OUT')
  return ag
end

function N.button(b)
  pcall(b.EnableMouse, b, false)
  -- the button itself is invisible and tiny; what shows is the crescents and the Shadow Bolt glow, both frames of it
  -- (the portrait glow of sheet 78 is gone: 2026-11-17 "visually this is awful")
  b:SetSize(1, 1); b:ClearAllPoints(); b:SetPoint('CENTER', UIParent, 'CENTER')
  for _, k in ipairs({ 'Icon', 'icon', 'Count', 'count', 'Duration', 'duration', 'Cooldown', 'cooldown', 'Border', 'border' }) do
    local r = b[k]; if type(r) == 'table' and r.SetAlpha then pcall(r.SetAlpha, r, 0) end
  end
  N.live = N.crescents(b)
  local anims = {}
  -- Shadow Bolt's button: a frame of this button (so the game shows and hides it), pinned to our anchor
  local hold = CreateFrame('Frame', nil, b); hold:SetAllPoints(sb)
  local g = hold:CreateTexture(nil, 'OVERLAY'); g:SetTexture(ART .. 'armorglow'); g:SetAllPoints(hold)
  g:SetVertexColor(VIOLET[1], VIOLET[2], VIOLET[3]); g:SetBlendMode('ADD')
  anims[#anims + 1] = breathe(g, .4, 1)
  N.hold = hold
  local function play() if ns.reduced and ns.reduced() then return end; for _, ag in ipairs(anims) do ag:Play() end end
  play()   -- looping: keeps going while hidden; no OnShow hook (Forever blocks it on aura buttons)
end

local function blizzGlowSeen() return ns.groupDB().nfBlizz == true end

-- out of combat: put the anchor over the first Shadow Bolt button showing (unless Blizzard's own glow does it)
function N.placeButton()
  if InCombatLockdown() then return end
  sb:ClearAllPoints(); sb:SetSize(0.001, 0.001); sb:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', -50, -50)
  N.on = nil
  if blizzGlowSeen() or not ns.actionButtons then return end
  for _, btn in ipairs(ns.actionButtons()) do
    local ok, yes = pcall(function()
      if not btn:IsVisible() then return false end
      local slot = btn.action or (btn.GetAttribute and btn:GetAttribute('action'))
      if not slot or not GetActionInfo then return false end
      local kind, id = GetActionInfo(slot)
      return kind == 'spell' and ns.spellName(id) == 'Shadow Bolt'
    end)
    if ok and yes then
      local icon = btn.icon or btn.Icon or _G[(btn:GetName() or '') .. 'Icon'] or btn
      sb:ClearAllPoints(); sb:SetPoint('TOPLEFT', icon, 'TOPLEFT'); sb:SetPoint('BOTTOMRIGHT', icon, 'BOTTOMRIGHT')
      N.on = btn; return
    end
  end
end

function N.build()
  if N.container or InCombatLockdown() then return N.container end
  local ok, c = pcall(CreateFrame, 'AuraContainer', 'OmaDemonNightfall', UIParent, 'CustomAuraContainerTemplate')
  if not ok or not c then N.failed = tostring(c); return nil end
  pcall(c.SetEditModePreviewEnabled, c, false)
  c:SetSize(1, 1); c:SetPoint('CENTER', UIParent, 'CENTER')
  local okS, err = pcall(c.AddAuraSlot, c, 'nightfall', 'HELPFUL', { initializeFrame = N.button, candidateFilters = { includeSpellIDs = idSet() } })
  if not okS then N.failed = tostring(err); c:Hide(); return nil end
  N.container = c
  c:SetUnit('player')
  N.placeButton()
  return c
end

-- a setting change shows at once on whatever is up
ns.onSetting[#ns.onSetting + 1] = function(key)
  if key ~= 'nfColour' and key ~= 'nfOn' then return end
  for _, f in ipairs({ N.live, N.previewFrame }) do
    if f then paint(f); if key == 'nfOn' then if f == N.live then settle(f) elseif ns.groupDB().nfOn == false then f:SetAlpha(0) end end end
  end
end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'PLAYER_REGEN_ENABLED', 'ACTIONBAR_SLOT_CHANGED',
  'ACTIONBAR_PAGE_CHANGED', 'UPDATE_BONUS_ACTIONBAR', 'SPELLS_CHANGED', 'SPELL_ACTIVATION_OVERLAY_GLOW_SHOW', 'SPELL_ACTIVATION_OVERLAY_SHOW' }) do pcall(ev.RegisterEvent, ev, e) end
local pending = false
local function soon() if pending then return end; pending = true; C_Timer.After(.2, function() pending = false; N.placeButton() end) end
ev:SetScript('OnEvent', function(_, e, id)
  if e == 'PLAYER_LOGIN' then
    if select(2, UnitClass('player')) ~= 'WARLOCK' then ev:UnregisterAllEvents(); return end
    N.build()
  elseif e == 'SPELL_ACTIVATION_OVERLAY_GLOW_SHOW' then
    -- Blizzard lights Shadow Bolt itself on Forever: ours stands down for good (shrinks out of combat)
    if ns.spellName and ns.spellName(id) == 'Shadow Bolt' and not blizzGlowSeen() then
      ns.groupDB().nfBlizz = true; N.blizzSeenAt = GetTime(); soon()
    end
  elseif e == 'SPELL_ACTIVATION_OVERLAY_SHOW' then
    -- Blizzard draws its own overlay for Shadow Trance on Forever after all: ours stands down for good
    if idSet()[id] and not ns.groupDB().nfOverlayBlizz then
      ns.groupDB().nfOverlayBlizz = true
      if N.live then N.live:SetAlpha(0) end
    end
  elseif not N.container then N.build()
  else soon() end
end)
