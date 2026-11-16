-- Loads the whole add-on in TOC order, runs its start-up, and checks the bar reads its own tracking.
local function tocFiles()
  local files = {}
  for line in io.lines('OmaDoomed.toc') do
    if not line:match('^##') and line:match('%S') and not line:match('%.xml%s*$') then files[#files + 1] = (line:gsub('\\', '/'):gsub('%s+$', '')) end
  end
  return files
end
return {
  ['the whole add-on loads and starts'] = function(W, T)
    local F = require('fight'); F.start({ compare = false })   -- sets spells and stubs; loads Track alone first
    local UI = require('ui'); UI.install()
    -- now the real load, in TOC order, into a fresh namespace
    local ns = W.load('.', 'OmaDoomed', tocFiles(), {})
    W.fire('ADDON_LOADED', 'OmaDoomed'); W.fire('PLAYER_LOGIN'); W.fire('PLAYER_ENTERING_WORLD')
    T.ok(ns.db == OmaDoomedDB, 'settings ready')
    T.ok(type(ns.dotsFor) == 'function', 'own tracking present')
    W.advance(1)
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,
}
