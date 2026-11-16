-- The rings' fade (sheet 38 'Fade': "rich and smooth for both"): leave quick, arrive soft.
-- Leaving: lifts 6 px and fades out over 0.2 s (ease-in). Arriving: starts 0.06 s later, rises 8 px into place and
-- fades in over 0.25 s (ease-out). Driven per frame from GetTime, so it's the same at any frame rate. The fader runs
-- only while something fades. Only our own anchors and containers move (allowed in combat).
local ADDON, ns = ...
local R = ns.rings
local Anim = ns.core.Anim

local LEAVE, ARRIVE, ARRIVE_DELAY, LIFT, RISE = .2, .25, .06, 6, 8
local fading = {}
local fader                         -- made at start
local easeIn, easeOut = Anim.easeIn, Anim.easeOut

local function fadeStep(p, now)
  local a = now - p.fadeAt
  local base = (R.db and R.db.alpha or 100) / 100
  local alpha, dy, done
  if p.want then
    local k = math.max(0, math.min(1, (a - ARRIVE_DELAY) / ARRIVE)); local e = easeOut(k)
    alpha = p.fromA + (1 - p.fromA) * e; dy = -RISE * (1 - e); done = k >= 1
  else
    local k = math.max(0, math.min(1, a / LEAVE))
    alpha = p.fromA * (1 - easeIn(k)); dy = LIFT * easeOut(k); done = k >= 1
  end
  p.curA = alpha
  p.anchor:SetAlpha(alpha * base)
  local pt = p.pt or 'BOTTOM'; p.ring:ClearAllPoints(); p.ring:SetPoint(pt, p.anchor, pt, 0, (p.up or 0) + dy)   -- up: a plate row's flow sits above its seats
  return done
end
local function fadeAll()
  local now, any = GetTime(), false
  for p in pairs(fading) do if fadeStep(p, now) then fading[p] = nil; if not p.want then p.anchor:Hide() end else any = true end end
  if not any then fader:Hide() end
end

-- show or hide a row, fading
function R.setVis(p, show)
  show = show and true or false
  if p.want == show then return end
  if p.want == nil then   -- first time: start from where it should be, no motion
    p.want, p.curA = show, show and 1 or 0
    p.anchor:SetAlpha((show and 1 or 0) * (R.db and R.db.alpha or 100) / 100); p.anchor:SetShown(show); return
  end
  p.fromA = p.curA or (p.want and 1 or 0); p.want = show; p.fadeAt = GetTime()
  if show then p.anchor:Show() end
  fading[p] = true; fader:Show()
end
ns.ringsSetVis = R.setVis
-- a row going back to the pool: no fade left over
function R.unfade(p) fading[p] = nil; p.want = nil; p.curA = nil; local pt = p.pt or 'BOTTOM'; p.ring:ClearAllPoints(); p.ring:SetPoint(pt, p.anchor, pt, 0, p.up or 0) end
ns.ringsUnfade = R.unfade

function R.fadeStart()
  fader = CreateFrame('Frame'); fader:SetScript('OnUpdate', fadeAll); fader:Hide()
end
