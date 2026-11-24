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

-- the list's grid (sheet 83, resized by sheet 108 v2, 2026-11-17): u = 2 px at scale 1. The list is exactly as wide as
-- his Details meter (348 px measured on the 21:07 screenshot), so the two stack edge to edge; nothing is reserved on
-- the right any more (the shield badge sits on the portrait), and the rings end at the right edge.
Lt.LIST = {
  u = 2,
  width = 174,       -- 348 px: the Details meter's width
  row = 22,          -- 44 px a row (even, so 1 px lines land on whole pixels)
  portrait = 20,     -- 40 px
  gapPortrait = 11,  -- portrait -> name (sheet 118 v6, 2026-11-18: room for the elite dragon, see MobList's r.drag:
                     -- 3 units + 8 so the dragon clears the portrait ring and the demon mark; 22 px)
  bar = 70,          -- 140 px
  barH = 7,          -- 14 px
  name = 6,          -- 12 px text
  gapRings = 3,      -- bar -> first ring (at least)
  ring = 15,         -- 30 px
  ringGap = 2,       -- 4 px between rings
  padX = 3, padY = 6,
}
