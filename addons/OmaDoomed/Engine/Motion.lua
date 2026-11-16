-- Motion engine: one clock and one set of easings for every animation in OmaDoomed, so they all feel the same.
--   M.tween(key, from, to, dur, set[, ease, done])  eases a value over dur seconds; a new tween on the same key
--                                                    takes over from where the old one is
--   M.breathe(key, period, lo, hi, set)             a soft, endless rise and fall (sine, ease in and out)
--   M.flash(key, dur, set)                          one swell up and back down (a mob turning to you)
--   M.stop(key)                                      ends a tween or breath where it is
-- 'Calm motion' (setting): tweens jump to their end and breaths hold steady at their top.
local ADDON, ns = ...
local M = {}; ns.motion = M
local A = ns.core.Anim
local sin, pi = math.sin, math.pi

local live = {}          -- key -> { kind, t0, ... }
local clock

M.ease = { out = A.easeOut, inOut = A.smootherstep, smooth = A.smoothstep }

local function calm() return ns.db and ns.db.calm == true end

local function step(now)
  local any = false
  for key, m in pairs(live) do
    any = true
    local ok, err = pcall(function()
      if m.kind == 'tween' then
        local k = m.dur > 0 and math.min(1, (now - m.t0) / m.dur) or 1
        m.cur = m.from + (m.to - m.from) * m.ease(k)
        m.set(m.cur)
        if k >= 1 then live[key] = nil; if m.done then m.done() end end
      elseif m.kind == 'breathe' then
        local v = (sin((now - m.t0) / m.period * 2 * pi - pi / 2) + 1) / 2     -- 0 -> 1 -> 0, eased at both ends
        m.cur = m.lo + (m.hi - m.lo) * v
        m.set(m.cur)
      elseif m.kind == 'flash' then
        local k = math.min(1, (now - m.t0) / m.dur)
        m.cur = k < .2 and A.easeOut(k / .2) or 1 - A.smoothstep((k - .2) / .8)
        m.set(m.cur)
        if k >= 1 then live[key] = nil end
      end
    end)
    if not ok then live[key] = nil; if ns.error then ns.error('motion: ' .. tostring(err)) end end
  end
  if not any and clock then clock:Hide() end
end

local function ensure()
  if not clock then clock = CreateFrame('Frame'); clock:SetScript('OnUpdate', function() step(GetTime()) end) end
  clock:Show()
end

function M.tween(key, from, to, dur, set, ease, done)
  local old = live[key]
  if old and old.kind == 'tween' and old.cur then from = old.cur end
  if calm() or dur <= 0 then live[key] = nil; set(to); if done then done() end; return end
  live[key] = { kind = 'tween', t0 = GetTime(), from = from, to = to, dur = dur, set = set, ease = ease or A.easeOut, done = done, cur = from }
  ensure()
end
function M.breathe(key, period, lo, hi, set)
  if calm() then live[key] = nil; set(hi); return end
  local old = live[key]
  if old and old.kind == 'breathe' and old.period == period and old.lo == lo and old.hi == hi then old.set = set; return end
  live[key] = { kind = 'breathe', t0 = GetTime(), period = period, lo = lo, hi = hi, set = set }
  ensure()
end
function M.flash(key, dur, set)
  if calm() then set(0); return end
  live[key] = { kind = 'flash', t0 = GetTime(), dur = dur, set = set }
  ensure()
end
function M.stop(key) live[key] = nil end
function M.running(key) return live[key] ~= nil end
M.step = step   -- tests
