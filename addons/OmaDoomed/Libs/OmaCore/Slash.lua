-- Slash: one /command with sub-commands. The message is lower-cased; an exact match wins (e.g. 'report show'),
-- then the first word (the handler gets the rest), then the fallback (gets the whole message).
--   s = Core.NewSlash('OMADOOMED', '/omadoomed', fallback, onError)
--   s:Exact('report', fn)  s:Word('rings', fn)
local _, ns = ...
local Core = ns.omaCoreBuild
if not Core then return end

local Slash = {}
Slash.__index = Slash
Core.SlashMethods = Slash

function Core.NewSlash(id, command, fallback, onError)
  local s = setmetatable({ exact = {}, word = {}, fallback = fallback, onError = onError }, Slash)
  _G['SLASH_' .. id .. '1'] = command
  SlashCmdList[id] = function(msg) s:Run(msg) end
  return s
end
function Slash:Exact(text, fn) self.exact[text] = fn; return self end
function Slash:Word(word, fn) self.word[word] = fn; return self end

function Slash:Run(msg)
  local m = (msg or ''):lower()
  local fn, arg = self.exact[m], nil
  if not fn then
    local w, rest = m:match('^(%S+)%s*(.-)$')
    if w and self.word[w] then fn, arg = self.word[w], rest end
  end
  if not fn then fn, arg = self.fallback, m elseif arg == nil then arg = m end
  if not fn then return end
  if not self.onError then return fn(arg) end
  local ok, err = pcall(fn, arg)
  if not ok then self.onError(err) end
end
