-- How heavy OmaDoomed is (Report.lua ns.perf): read from Blizzard's add-on profiler and memory, guarded so a
-- missing piece never errors, and carried in every bug report.
local function tocFiles()
  local files = {}
  for line in io.lines('OmaDoomed.toc') do
    if not line:match('^##') and line:match('%S') and not line:match('%.xml%s*$') then files[#files + 1] = (line:gsub('\\', '/'):gsub('%s+$', '')) end
  end
  return files
end
local function load(W)
  local F = require('fight'); F.start({ compare = false })
  require('ui').install()
  local ns = W.load('.', 'OmaDoomed', tocFiles(), {})
  W.fire('ADDON_LOADED', 'OmaDoomed'); W.fire('PLAYER_LOGIN'); W.fire('PLAYER_ENTERING_WORLD')
  return ns
end
return {
  ['with the profiler: numbers for OmaDoomed and the yardstick add-ons, in the report too'] = function(W, T)
    local ns = load(W)
    Enum.AddOnProfilerMetric = { SessionAverageTime = 0, RecentAverageTime = 1, PeakTime = 4, CountTimeOver5Ms = 7 }
    local vals = { OmaDoomed = .04, Details = .2 }
    C_AddOnProfiler = { IsEnabled = function() return true end,
      GetAddOnMetric = function(name, m) return (vals[name] or 0) * (m + 1) end,
      GetOverallMetric = function(m) return 1.5 end }
    C_AddOns = C_AddOns or {}; C_AddOns.IsAddOnLoaded = function(n) return n == 'OmaDoomed' or n == 'Details' end
    GetAddOnMemoryUsage = function(n) return n == 'OmaDoomed' and 812 or 9000 end; UpdateAddOnMemoryUsage = function() end
    local p = ns.perf()
    T.eq(p.profiler, 'yes'); T.eq(#p.rows, 2, 'only loaded add-ons')
    T.near(p.rows[1].recent, .08, 1e-9, 'recent average'); T.eq(p.rows[1].kb, 812, 'memory')
    local text = table.concat(ns.perfLines(p), '\n')
    T.ok(text:find('OmaDoomed') and text:find('Details') and text:find('all add%-ons'), 'lines name each add-on and the total')
    ns.saveReport('command')
    T.ok(OmaDoomedDB.reports[1].perf and #OmaDoomedDB.reports[1].perf.rows == 2, 'the bug report carries it')
  end,
  ['without the profiler: no errors, memory still there'] = function(W, T)
    local ns = load(W)
    C_AddOnProfiler = nil
    C_AddOns = C_AddOns or {}; C_AddOns.IsAddOnLoaded = function(n) return n == 'OmaDoomed' end
    GetAddOnMemoryUsage = function() return 640 end; UpdateAddOnMemoryUsage = function() end
    local ok, p = pcall(ns.perf)
    T.ok(ok, 'no error: ' .. tostring(p))
    T.eq(p.profiler, 'no'); T.eq(p.rows[1].kb, 640)
    T.ok(table.concat(ns.perfLines(p), '\n'):find('profiler: no'), 'says the profiler is missing')
  end,
}
