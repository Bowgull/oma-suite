-- Log: an add-on's error list. Each distinct message is recorded once per session (newest first, kept in the
-- add-on's saved table so bug reports carry it). Errors also go to the game's error handler once, so BugSack and
-- BugGrabber see them. A failure that switches a part off says one chat line, the first time only.
--   log = Core.NewLog{ store = function() return SavedTable end, say = function(msg) end, name = 'OmaDoomed',
--                      report = '/omadoomed report', keep = 30 }
--   log:Note(msg)        record only (diagnostics)
--   log:Error(msg)       record + error handler
--   log:Fail(msg, part)  record + error handler + one chat line ("<part> paused until /reload; ...")
local _, ns = ...
local Core = ns.omaCoreBuild
if not Core then return end

local Log = {}
Log.__index = Log
Core.LogMethods = Log
local SEEN_MAX = 200   -- distinct messages remembered per session; past that, new ones are dropped

function Core.NewLog(opts) return setmetatable({ opts = opts or {}, seen = {}, nSeen = 0, told = false }, Log) end

local function record(self, m)
  if self.seen[m] or self.nSeen >= SEEN_MAX then return false end
  self.seen[m] = true; self.nSeen = self.nSeen + 1
  local db = self.opts.store and self.opts.store()
  if type(db) == 'table' then
    local e = db.errs; if type(e) ~= 'table' then e = {}; db.errs = e end
    table.insert(e, 1, date('%H:%M:%S ') .. m)
    while #e > (self.opts.keep or 30) do table.remove(e) end
  end
  return true
end

function Log:Note(m) return record(self, tostring(m)) end

function Log:Error(m)
  m = tostring(m)
  if not record(self, m) then return false end
  local h = geterrorhandler and geterrorhandler()
  if h then pcall(h, (self.opts.name or 'Oma') .. ': ' .. m) end
  return true
end

function Log:Fail(m, part)
  local new = self:Error(m)
  if new and not self.told then
    self.told = true
    local line = (part and (part .. ' ') or '') .. 'paused until /reload; ' .. (self.opts.report or '/oma report') .. ' saves the details.'
    if self.opts.say then pcall(self.opts.say, line) end
  end
  return new
end

function Log:List() local db = self.opts.store and self.opts.store(); return type(db) == 'table' and db.errs or {} end
