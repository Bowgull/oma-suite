-- Secret: safe handling of Forever's secret values (numbers the game hides in combat). Add-on code may pass a secret
-- along but must not compare it or do maths on it; these helpers never do either.
local _, ns = ...
local Core = ns.omaCoreBuild
if not Core then return end

local S = {}
Core.Secret = S

function S.is(v) return issecretvalue ~= nil and issecretvalue(v) or false end
-- a plain value that can be read: not nil and not secret
function S.readable(v) return v ~= nil and not S.is(v) end
-- a == b, or nil when either side is secret (cannot tell)
function S.eq(a, b) if S.is(a) or S.is(b) then return nil end return a == b end
-- true only for a plain true
function S.isTrue(v) return S.eq(v, true) == true end
-- string.format for a plain number; `hidden` ('?') for a secret or nil
function S.fmt(pattern, v, hidden)
  if v == nil or S.is(v) then return hidden or '?' end
  return pattern:format(v)
end
-- calls fn(...) guarded; its first result, or nil when it failed or came back secret
function S.call(fn, ...)
  local ok, v = pcall(fn, ...)
  if ok and not S.is(v) then return v end
end
