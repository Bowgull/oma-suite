-- Bug reports (2026-11-11: "build the bug report button"). OmaDoomed always keeps the last 15 seconds of what
-- it drew (a small ring buffer, never saved on its own). One press, a key binding (Options > Key Bindings > OmaDoomed,
-- bind it to a controller button) or /omadoomed report, saves a report with those 15 seconds, the settings, recent
-- errors and the game version, and takes a screenshot. Nothing personal goes in: no character, realm, guild, target
-- names or chat. WoW writes saved files on /reload or logout, so the chat line says so.
-- /omadoomed report show  opens the newest report, selected, ready for Ctrl+C.
local ADDON, ns = ...

local KEEP, MAXREPORTS = 60, 5   -- 60 s: long enough to open Options after seeing the bug
local buf, head, size = {}, 0, 600      -- 60 s at 10 rows a second

-- called by the kill bar 10 times a second with what it is about to draw
function ns.recordRow(cur, extra)
  local now = GetTime()
  local parts = { string.format('%.1f', now) }
  if cur and cur.dots then
    for _, d in ipairs(cur.dots) do
      local dmg = d.damage
      if issecretvalue and issecretvalue(dmg) then dmg = '?' else dmg = string.format('%.0f', dmg or 0) end
      parts[#parts + 1] = (d.name or '?'):sub(1, 4) .. '=' .. dmg .. (d.provisional and 'P' or '') .. (d.landed and 'L' or '') .. (d.ending and 'E' or '')
    end
  else parts[#parts + 1] = 'none' end
  if extra then parts[#parts + 1] = extra end
  parts[#parts + 1] = string.format('fps%.0f', GetFramerate and GetFramerate() or 0)
  head = head % size + 1; buf[head] = table.concat(parts, ' ')
end

local function lastRows()
  local out, now = {}, GetTime()
  for i = 1, size do
    local row = buf[(head + i - 1) % size + 1]
    if row then local t = tonumber(row:match('^(%S+)')); if t and now - t <= KEEP then out[#out + 1] = row end end
  end
  return out
end

local function copySettings(t)
  local o = {}
  for k, v in pairs(t or {}) do local tv = type(v); if tv == 'boolean' or tv == 'number' or tv == 'string' then o[k] = v end end
  return o
end

-- How heavy OmaDoomed is, next to a few well-known add-ons as a yardstick. Uses Blizzard's own add-on profiler
-- (C_AddOnProfiler: milliseconds of CPU per frame) and memory in KB. Every call is guarded: if Forever lacks a
-- piece, that line just says so.
local YARDSTICK = { 'OmaDoomed', 'DoesItDie', 'Details', 'Questie', 'RXPGuides', 'Plater', 'BigWigs' }
local function metric(get, name, key)
  local E = Enum and Enum.AddOnProfilerMetric; if not (E and E[key]) then return nil end
  local ok, v = pcall(get, name, E[key]); if ok and type(v) == 'number' then return v end
end
function ns.perf()
  local P = C_AddOnProfiler
  local out = { profiler = (P and P.GetAddOnMetric) and 'yes' or 'no', rows = {} }
  if P and P.IsEnabled then local ok, on = pcall(P.IsEnabled); out.profilerOn = ok and on and true or false end
  if P and P.GetOverallMetric then
    out.allRecent = metric(function(_, m) return P.GetOverallMetric(m) end, nil, 'RecentAverageTime')
    out.allSession = metric(function(_, m) return P.GetOverallMetric(m) end, nil, 'SessionAverageTime')
  end
  if UpdateAddOnMemoryUsage and not InCombatLockdown() then pcall(UpdateAddOnMemoryUsage) end
  for _, name in ipairs(YARDSTICK) do
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name)
    if loaded then
      local r = { name = name }
      if P and P.GetAddOnMetric then
        r.recent = metric(P.GetAddOnMetric, name, 'RecentAverageTime')
        r.session = metric(P.GetAddOnMetric, name, 'SessionAverageTime')
        r.peak = metric(P.GetAddOnMetric, name, 'PeakTime')
        r.over5 = metric(P.GetAddOnMetric, name, 'CountTimeOver5Ms')
      end
      if GetAddOnMemoryUsage then local ok, kb = pcall(GetAddOnMemoryUsage, name); if ok and type(kb) == 'number' then r.kb = kb end end
      out.rows[#out.rows + 1] = r
    end
  end
  return out
end
local function n(v, f) return v and (f or '%.3f'):format(v) or '-' end
function ns.perfLines(p)
  local L = { ('CPU (Blizzard profiler: %s%s), ms per frame and memory:'):format(p.profiler, p.profilerOn == false and ', switched off' or '') }
  if p.allRecent then L[#L + 1] = ('  all add-ons: recent %s, session %s'):format(n(p.allRecent), n(p.allSession)) end
  for _, r in ipairs(p.rows) do
    L[#L + 1] = ('  %-10s recent %s  session %s  peak %s  frames over 5 ms %s  memory %s KB'):format(r.name, n(r.recent), n(r.session), n(r.peak, '%.1f'), n(r.over5, '%d'), n(r.kb, '%d'))
  end
  return L
end

function ns.saveReport(how)
  local db = OmaDoomedDB; if not db then return end
  local version, build, _, iface = GetBuildInfo()
  local r = {
    at = date('%Y-%m-%d %H:%M:%S'), how = how or 'command',
    addon = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, 'Version')) or '?',
    game = ('%s (%s) %s'):format(tostring(version), tostring(build), tostring(iface)), locale = GetLocale and GetLocale() or '?',
    inCombat = InCombatLockdown() and true or false, inGroup = (IsInGroup and IsInGroup()) and true or false,
    doesItDie = (DoesItDie and DoesItDie.GetDoTs) and 'yes' or 'no',
    bar = copySettings(db), rings = copySettings(db.rings),
    errors = {}, rows = lastRows(), perf = ns.perf(),
    compare = db.compare and { checks = db.compare.checks, differ = db.compare.differ, log = { unpack(db.compare.log, 1, math.min(20, #db.compare.log)) } } or nil,
  }
  for i = 1, math.min(10, #(db.errs or {})) do r.errors[i] = db.errs[i] end
  db.reports = db.reports or {}
  table.insert(db.reports, 1, r); while #db.reports > MAXREPORTS do table.remove(db.reports) end
  local shot = pcall(Screenshot)
  ns.say(('bug report saved (%d rows%s). It reaches the disk on your next /reload or log out. /omadoomed report show to copy it.'):format(#r.rows, shot and ', screenshot taken' or ''))
end
_G.OmaDoomed_SaveReport = function() ns.saveReport('button') end   -- the key binding (Bindings.xml)
BINDING_HEADER_OMADOOMED = 'OmaDoomed'
_G['BINDING_NAME_OMADOOMED_REPORT'] = 'Save a bug report'

local function asText(r)
  local L = { 'OmaDoomed bug report', 'saved ' .. r.at .. ' by ' .. r.how, 'add-on ' .. r.addon .. ', game ' .. r.game .. ', language ' .. r.locale,
    'in combat: ' .. tostring(r.inCombat) .. ', in a group: ' .. tostring(r.inGroup) .. ', DoesItDie: ' .. r.doesItDie, '', 'kill bar settings:' }
  local function kv(t) local ks = {}; for k in pairs(t) do ks[#ks + 1] = k end; table.sort(ks); for _, k in ipairs(ks) do L[#L + 1] = '  ' .. k .. ' = ' .. tostring(t[k]) end end
  kv(r.bar); L[#L + 1] = 'ring settings:'; kv(r.rings)
  L[#L + 1] = ''; L[#L + 1] = 'recent errors:'; for _, e in ipairs(r.errors) do L[#L + 1] = '  ' .. e end
  if r.compare then
    L[#L + 1] = ''; L[#L + 1] = ('own tracking vs DoesItDie: %d checks, %d disagreements'):format(r.compare.checks or 0, r.compare.differ or 0)
    for _, line in ipairs(r.compare.log or {}) do L[#L + 1] = '  ' .. line end
  end
  if r.perf then L[#L + 1] = ''; for _, line in ipairs(ns.perfLines(r.perf)) do L[#L + 1] = line end end
  L[#L + 1] = ''; L[#L + 1] = 'last ' .. KEEP .. ' seconds (time, DoT=damage left, P casting, L landed, E ending, fps):'
  for _, row in ipairs(r.rows) do L[#L + 1] = '  ' .. row end
  return table.concat(L, '\n')
end

-- the copy box: Blizzard's own dialog frame and scroll box, the text selected
local box
function ns.showReport()
  local r = OmaDoomedDB and OmaDoomedDB.reports and OmaDoomedDB.reports[1]
  if not r then ns.say('no bug report saved yet.'); return end
  if not box then
    box = CreateFrame('Frame', 'OmaDoomedReportBox', UIParent, 'BasicFrameTemplateWithInset')
    box:SetSize(560, 420); box:SetPoint('CENTER'); box:SetFrameStrata('DIALOG'); box:EnableMouse(true); box:SetMovable(true)
    box:RegisterForDrag('LeftButton'); box:SetScript('OnDragStart', box.StartMoving); box:SetScript('OnDragStop', box.StopMovingOrSizing)
    if box.TitleText then box.TitleText:SetText('OmaDoomed bug report: press Ctrl+C to copy') end
    local sf = CreateFrame('ScrollFrame', nil, box, 'UIPanelScrollFrameTemplate')
    sf:SetPoint('TOPLEFT', 12, -30); sf:SetPoint('BOTTOMRIGHT', -30, 12)
    local eb = CreateFrame('EditBox', nil, sf); eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetWidth(500); eb:SetAutoFocus(false)
    eb:SetScript('OnEscapePressed', function() box:Hide() end)
    sf:SetScrollChild(eb); box.eb = eb
    tinsert(UISpecialFrames, 'OmaDoomedReportBox')   -- Escape closes it
  end
  box.eb:SetText(asText(r)); box:Show(); box.eb:SetFocus(); box.eb:HighlightText()
end
