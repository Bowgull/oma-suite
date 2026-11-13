-- Kill bar style: a DoT's state in, its colours and looks out. Pure: no frames, no settings read, no tables made
-- (the caller hands in a reused output table). The target bar (Doomed.lua), the plate bars (KillPlates.lua) and the
-- preview (Preview.lua) all draw from it, so a cast look or a tick light has one definition.
local _, ns = ...
local Anim = ns.core.Anim
local S = {}
ns.killStyle = S

S.GOLD = { 206 / 255, 160 / 255, 44 / 255 }   -- the old 'ending soon' gold (kept for reference; no longer drawn)
-- Sheet 59 B (approved 2026-11-13, "b"): an ending piece flares in its DoT's OWN colour, the ring colour lifted 22%
-- towards white, exactly as its ring does (RingsLook.lua, sheet 58 C). One language for bar and rings.
S.LIT = 0.22
function S.lit(c, k) k = k or S.LIT; return c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k end
S.OTHER = { .55, .45, .65 }                    -- a DoT with no entry in Spells.lua
local DIM, FULL, LIFT = .45, 1.15, .7          -- precast dim, the landed piece's strength, the additive lift
local LOW_TONE, SPARK = 1.3, .45               -- the tick light in gold time, the ember's strength
S.STRIPES_A, S.MOTES_K = .55, .8               -- drifting stripes' alpha, motes' strength
S.LAND_CHARGE, S.LAND_EASE = .35, .3           -- seconds: the ember fades as a Charging cast lands; other looks ease up

local min = math.min
local function set(t, r, g, b) t[1], t[2], t[3] = r, g, b; return t end
local function mix(t, a, b, k) return set(t, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k) end
S.mix = mix

-- the 'ending soon' breath: 1 at `low` seconds left, 0.3 halfway, 1 every 1.5 s; steady: always 1
function S.breath(left, low, steady) if steady then return 1 end; return Anim.breath(left, low, 1.5, .3) end
-- where drifting stripes and motes are at clock t (0..1, they repeat)
function S.stripesAt(t) return (t * .35) % 1 end
function S.motesAt(t) return (t * .08) % 1 end
-- a tick's light: how far into its life and how bright (flare 0..1, from DotModel.bite)
function S.lightA(flare) return flare * .55 end

-- One particle of Cinders or Essence, k = 1..5, age = seconds since the bite: l (0..1 of its life), fade, rise
-- (0..1), or nil when it isn't alive.
function S.particle(k, age)
  local life = age / .7
  local l = math.max(0, min(1, (life - (k - 1) * .04) / .9))
  if l <= 0 or l >= 1 then return nil end
  return l, math.sin(math.pi * min(1, l * 1.15)), 1 - (1 - l) ^ 2
end

local function new() return { c = {}, tn = {}, glow = {}, full = {}, base = {}, lift = {}, fill = {}, fillLift = {}, tone = {}, ghost = {}, haze = {} } end
S.new = new

-- S.piece(o, sp, s): what one piece looks like now, into o (made by S.new, reused).
--   sp: the DoT's Spells.lua entry (deep: piece colour, color: ring tone), or nil
--   s.left: seconds left (nil: never gold, the plate bars), s.low, s.steady: the 'Ending soon' settings
--   s.provisional: still being cast; s.look: the 'While you cast' look now; s.pr: cast progress 0..1
--   s.landAge, s.landLook: a cast that landed, seconds ago and in which look (nil: not a landing)
--   s.light: the 'Tick light' setting (nil: no bite closing); s.quiet: removed early, no light
--   s.rawTone: the tick light's gold-time tone is not capped at 1 (the preview's own numbers)
-- Out: o.c piece colour, o.tn ring tone, o.glow (the ember's colour), o.full, o.base, o.lift (the two layers of a
-- piece; a plate bar draws o.base), o.fill + o.fillLift (Charging's fill) and o.cpr (its progress) or nil, o.spark
-- (the ember's strength) or nil, o.stripes / o.motes (true when that look shows), o.lowNow, o.animating (it changes
-- with time alone), o.light (kind), o.tone (tick light), o.ghost (the bite's colour), o.haze (Essence's colour).
function S.piece(o, sp, s)
  local deep = sp and sp.deep or S.OTHER
  local left = s.left
  local lowNow = left and left <= s.low or false
  local c = o.c
  if lowNow then
    -- a piece is drawn as base (c x FULL) plus an additive lift (c x LIFT), so c is the lit colour over their sum:
    -- what reaches the screen is the ring's lit colour itself, dimmed by the breath, never blown out to white
    local b = (.6 + .4 * S.breath(left, s.low, s.steady)) / (FULL + LIFT)
    local r, g, bl = S.lit(sp and sp.color or S.OTHER)
    set(c, r * b, g * b, bl * b)
  else set(c, deep[1], deep[2], deep[3]) end
  local tn = sp and sp.color or c
  set(o.tn, tn[1], tn[2], tn[3])
  mix(o.glow, c, o.tn, .7)   -- the glow: its own colour, low (no white: warlock light)
  local full = set(o.full, min(1, c[1] * FULL), min(1, c[2] * FULL), min(1, c[3] * FULL))
  o.lowNow = lowNow
  o.animating = lowNow and not s.steady
  o.cpr, o.spark, o.stripes, o.motes = nil, nil, false, false
  if s.provisional then
    o.animating = true
    local pr, look = s.pr or 1, s.look
    set(o.base, c[1] * DIM, c[2] * DIM, c[3] * DIM); set(o.lift, 0, 0, 0)
    if look == 'charging' then   -- fills with your cast bar in its landed colour, an ember at the front
      o.cpr = pr
      set(o.fill, full[1], full[2], full[3]); set(o.fillLift, c[1] * LIFT, c[2] * LIFT, c[3] * LIFT)
      o.spark = SPARK
    elseif look == 'smoulder' then   -- its colour rises out of the dark as you cast
      local k = pr ^ 1.6
      set(o.base, c[1] * (.3 + .85 * k), c[2] * (.3 + .85 * k), c[3] * (.3 + .85 * k)); set(o.lift, c[1] * LIFT * k, c[2] * LIFT * k, c[3] * LIFT * k)
    elseif look == 'stripes' then o.stripes = true   -- Blizzard's shield stripes in its ring colour (o.tn, S.STRIPES_A)
    elseif look == 'motes' then o.motes = true end    -- small pixels drifting through it (o.tn x S.MOTES_K)
  else
    local la, ll = s.landAge or 9, s.landLook
    if ll == 'charging' and la < S.LAND_CHARGE then
      o.cpr = 1; o.spark = SPARK * (1 - la / S.LAND_CHARGE) ^ 2; o.animating = true
    end
    local k = 1   -- the other looks ease from dim to full colour as they land (no snap)
    if ll and ll ~= 'charging' and ll ~= 'smoulder' and la < S.LAND_EASE then k = .4 + .6 * Anim.smoothstep(la / S.LAND_EASE); o.animating = true end
    set(o.base, full[1] * k, full[2] * k, full[3] * k)
    set(o.lift, c[1] * LIFT * k, c[2] * LIFT * k, c[3] * LIFT * k)
  end
  -- a tick's light: the bitten part keeps its piece's colour; the light washes up out of it and settles
  local light = s.light
  if light and s.quiet then light = 'plain' end   -- removed early: no light
  o.light = light
  if light then
    if lowNow then
      if s.rawTone then set(o.tone, c[1] * LOW_TONE, c[2] * LOW_TONE, c[3] * LOW_TONE)
      else set(o.tone, min(1, c[1] * LOW_TONE), min(1, c[2] * LOW_TONE), min(1, c[3] * LOW_TONE)) end
    else set(o.tone, tn[1], tn[2], tn[3]) end
    set(o.ghost, full[1] + c[1] * LIFT, full[2] + c[2] * LIFT, full[3] + c[3] * LIFT)
    mix(o.haze, c, o.tone, .45)
  end
  return o
end
