-- Anim: the easing curves and the "ending soon" breath, one copy for every Oma view. Pure functions.
local _, ns = ...
local Core = ns.omaCoreBuild
if not Core then return end

local A = {}
Core.Anim = A
local cos, pi = math.cos, math.pi

function A.clamp(v) if v < 0 then return 0 elseif v > 1 then return 1 end return v end
-- smoothstep: 3v^2 - 2v^3, clamped
function A.smoothstep(v) v = A.clamp(v); return v * v * (3 - 2 * v) end
-- smootherstep: 6v^5 - 15v^4 + 10v^3, clamped (starts and ends at rest)
function A.smootherstep(v) v = A.clamp(v); return v * v * v * (v * (v * 6 - 15) + 10) end
-- quadratic in, cubic out (unclamped: callers pass 0..1)
function A.easeIn(v) return v * v end
function A.easeOut(v) return 1 - (1 - v) ^ 3 end

-- The breath of a DoT's last seconds: 1 at `low` seconds left, `floor` half a `period` later, 1 again every period.
-- left: seconds left. Defaults: low 3, period 1.5, floor 0.3 (the rings' and the kill bar's breath).
function A.breath(left, low, period, floor)
  low, period, floor = low or 3, period or 1.5, floor or .3
  local ph = (low - left) / period % 1
  return floor + (1 - floor) * (cos(ph * 2 * pi) * .5 + .5)
end
