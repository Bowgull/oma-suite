-- Layout engine: one grid for a frame. Every size is a whole number of grid units, a frame's look is sized once at
-- scale 1, and resizing changes one number (the frame's scale), so spacing never drifts. Sizes snap to whole screen
-- pixels so lines stay crisp at any scale.
--   local g = ns.layout.grid(u)    g(n) = n units     ns.layout.snap(frame, v)    nearest whole physical pixel
local ADDON, ns = ...
local Lt = {}; ns.layout = Lt

function Lt.grid(u) return function(n) return n * u end end

function Lt.snap(frame, v)
  if PixelUtil and PixelUtil.GetNearestPixelSize and frame and frame.GetEffectiveScale then
    local ok, r = pcall(PixelUtil.GetNearestPixelSize, v, frame:GetEffectiveScale())
    if ok and type(r) == 'number' then return r end
  end
  return math.floor(v + .5)
end

-- the list's grid (sheet 83): u = 2 px at scale 1
Lt.LIST = {
  u = 2,
  row = 24,          -- 48 px a row
  portrait = 19,     -- 38 px (sheet 86: 34 px read as a dark smudge)
  gapPortrait = 5,   -- portrait -> name
  bar = 92,          -- 184 px
  barH = 8,          -- 16 px
  name = 7,          -- 14 px text
  gapRings = 6,      -- bar -> first ring
  ring = 17,         -- 34 px
  ringGap = 3,       -- 6 px between rings
  padX = 10, padY = 6,
}
