-- Every OmaDoomed setting, in one table (OmaCore Settings): its default, its control on the Options page
-- (Options > AddOns > Oma > OmaDoomed, sheet 37), its label and tip. Kill bar values live in OmaDoomedDB, ring values
-- in OmaDoomedDB.rings. A change fires 'SETTING' (key, store) on the bus so it shows at once.
-- MIGRATIONS: saved-data upgrade steps; OmaDoomedDB.v is the last one applied. Append only, never renumber.
local ADDON, ns = ...
local Core = ns.core

local pct = function(v) return ('%d%%'):format(v) end
local BAR, R = 'doomed', 'rings'

ns.settings = Core.NewSettings({
  prefix = 'OMADOOMED_',
  onChange = function(key, store) ns.bus:Fire('SETTING', key, store) end,
  onError = function(m) ns.error(m) end,
  items = {
    { element = function() return ns.previewInitializer and ns.previewInitializer() end },
    { header = 'Kill bar' },
    { key = 'doomed', default = true, control = 'check', label = 'Kill bar',
      tip = "Your DoTs' coming damage, in their own colours, inside the enemy's health bar." },
    { key = 'skull', default = true, control = 'check', label = 'Skull', parent = BAR,
      tip = 'A skull and bones on the portrait ring when your DoTs alone will finish the enemy.' },
    { key = 'cast', default = 'charging', control = 'dropdown', label = 'While you cast', parent = BAR,
      choices = { { 'charging', 'Charging' }, { 'smoulder', 'Smoulder' }, { 'stripes', 'Drifting stripes' }, { 'motes', 'Motes' }, { 'plain', 'Plain' } },
      tip = "Charging: the piece fills with your cast bar, an ember at its front. Smoulder: its colour rises out of the dark. Drifting stripes: stripes sliding toward the green. Motes: small pixels drifting through it. Plain: a dim piece that turns solid when the spell lands." },
    { key = 'tick', default = 'ember', control = 'dropdown', label = 'Tick light', parent = BAR,
      choices = { { 'ember', 'Ember' }, { 'cinders', 'Cinders' }, { 'essence', 'Essence' }, { 'plain', 'Plain' } },
      tip = "Ember: the bitten part glows in its own colour and settles. Cinders: the same glow, and small embers lift off it. Essence: a soft curl of shadow haze rises from it. Plain: it just slides shut." },
    { key = 'low', default = 3, control = 'slider', label = 'Ending soon', parent = BAR, min = 2, max = 5, step = 1,
      format = function(v) return ('%d s'):format(v) end,
      tip = "In a DoT's last seconds its piece on your target's kill bar, and its ring, turn gold." },
    { key = 'lowlook', default = 'breathe', control = 'dropdown', label = 'Ending soon look', parent = BAR,
      choices = { { 'breathe', 'Breathing gold' }, { 'steady', 'Steady gold' } },
      tip = "How the gold looks in a DoT's last seconds: breathing on the rings' beat, or steady." },
    { key = 'platebar', default = true, control = 'check', label = 'Over enemies', parent = BAR,
      tip = "The same kill bar inside the health bar over every enemy you DoT." },
    { key = 'targetPath', default = '' },   -- another add-on's target health bar, by frame name (/omadoomed frame)
    { button = 'Pick', name = 'Target health bar', click = function() if ns.startPick then ns.startPick() end end,
      tip = "Only if another add-on replaced your target frame: click Pick, close Options, then click its health bar (out of combat, with a mouse). Or type /omadoomed frame and the bar's name." },

    { header = 'Rings' },
    { key = 'enabled', store = R, default = true, control = 'check', label = 'Rings',
      tip = "Your DoTs as rings over enemies. Off: Blizzard's own debuff icons come back on nameplates, and on the target frame unless Blizzard's squares is set to Hide." },
    { key = 'where', store = R, default = 'enemy', control = 'dropdown', label = 'Where the rings show',
      choices = { { 'enemy', 'Above enemies' }, { 'frame', 'Target frame' }, { 'split', 'Haunt' } },
      tip = "Above enemies: rings over every enemy's head. Target frame: only on your target's frame. Haunt: over every enemy you're not targeting; the one you target shows its rings on its frame, with your curse, your channel and your crowd control still over its head." },
    { key = 'squares', store = R, default = 'notmine', control = 'dropdown', label = "Blizzard's squares",
      choices = { { 'notmine', 'All but my DoTs' }, { 'all', 'All' }, { 'hide', 'Hide' } },
      tip = "Blizzard's own buff and debuff squares on the target frame. All but my DoTs: on mobs the debuff squares go, stuns and the mob's own debuffs too (Blizzard can't hide only yours; the rings show yours), and buffs stay. On players everything stays." },
    { key = 'which', store = R, default = 'all', control = 'dropdown', label = 'Which enemies',
      choices = { { 'all', 'Every enemy' }, { 'target', 'Only your target' }, { 'combat', 'Only in combat' } },
      tip = "Rings on every enemy, only your target, or only while you're fighting." },
    { key = 'look', store = R, default = 'rich', control = 'dropdown', label = 'Ring look',
      choices = { { 'rich', 'Modern' }, { 'flat', 'Classic' } },   -- Joshua 2026-11-13: "The 2 ring settings are modern and classic"
      tip = "Modern: a lit ring with a bezel and a bold number. Classic: a plain ring, the spell's icon clear, a thin number. Shows after a /reload: type /reload, or pick Reload UI in the game menu (Esc, or Menu on a controller)." },
    { key = 'size', store = R, default = 40, control = 'slider', label = 'Ring size', min = 28, max = 60, step = 2, format = tostring,
      tip = "How big your rings are. 40 is Blizzard's own size." },
    { key = 'alpha', store = R, default = 100, control = 'slider', label = 'Ring opacity', min = 20, max = 100, step = 5, format = pct,
      tip = 'How solid your own rings are.' },
    { key = 'othersAlpha', store = R, default = 55, control = 'slider', label = "Other players' DoTs", min = 0, max = 100, step = 5,
      format = function(v) return v == 0 and 'Hidden' or ('%d%%'):format(v) end,
      tip = "How solid other warlocks' DoT rings are (theirs only, not every debuff). 0 hides them; another strength shows after a /reload." },
    { key = 'others', store = R, default = true },    -- /omadoomed rings others on|off
    { key = 'cc', store = R, default = true, control = 'check', label = 'Crowd-control timers',
      tip = "Your Fear, Banish, Howl of Terror and your Sayaad's Seduction as a teal ring over the mob. When it isn't your target or is off screen, the ring stands beside your target frame instead, so you always see how long is left." },

    { header = 'Help' },
    { button = 'Save a bug report', name = 'Bug report', click = function() if ns.saveReport then ns.saveReport('settings') end end,
      tip = 'Saves the last minute of what OmaDoomed drew, your settings, recent errors and a screenshot. No names or chat. You can also bind a key: Key Bindings > OmaDoomed.' },
    { button = 'Show last report', name = '', click = function() if ns.showReport then ns.showReport() end end,
      tip = 'Opens your last bug report, selected, ready to copy with Ctrl+C.' },
  },
})

-- Chat lines that aren't settings, kept here beside the settings text so a translation has one place to look.
ns.text = {
  plates = "using %s's nameplates: the kill bar and rings go on its health bars.",
  frame = "your target frame comes from %s: the kill bar goes on its health bar. /omadoomed frame if it looks wrong.",
  doesItDie = "Does It Die is also on: you'll see both markers. OmaDoomed doesn't need it.",
}
ns.hello = {
  new = "rings over every enemy you DoT, and on your target's health bar, what your DoTs will still take. Settings: /omadoomed options.",
  upgrade = "1.0: no longer needs Does It Die, finds the health bars of Plater and other nameplate add-ons, and works on non-English clients. Settings: /omadoomed options.",
}

ns.MIGRATIONS = {
  -- 1: the first numbered version. Earlier saves need no change (defaults fill whatever is missing).
  function(db) end,
  -- 2: standalone (phase 3): the engine choice, the side-by-side log and Does It Die's saved look are gone; the
  -- tracking's trace log is off by default, so its old lines go too
  function(db)
    db.engine, db.compare, db.didSaved = nil, nil, nil
    if type(db.track) == 'table' then db.track.log = nil end
  end,
  -- 3: tidy up for release. Debug leftovers of earlier builds go; so do the ~90 Does It Die look settings older
  -- builds copied into db.track (the tracking keeps only what it reads: Track/Engine.lua DEFAULTS and what it
  -- learns); the error list keeps its newest 20 lines.
  function(db)
    db.tfdump, db.plateGeo = nil, nil
    local keep = { ticks = true, tickWeights = true, omaRatio = true, intervals = true, log = true, omaTrace = true, version = true,
      showMarkers = true, debug = true, waitFirstTick = true, estimateDuringCast = true, uiLanguage = true }
    if type(db.track) == 'table' then
      for k in pairs(db.track) do if not keep[k] then db.track[k] = nil end end
    end
    if type(db.errs) == 'table' then
      local n = #db.errs
      if n > 20 then local t = {}; for i = n - 19, n do t[#t + 1] = db.errs[i] end; db.errs = t end
    end
  end,
}

function ns.buildSettings() ns.settingsCategory = ns.settings:Build(ns.db, 'OmaDoomed') end

-- /omadoomed options
function ns.openSettings() ns.settings:Open() end
