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
    -- 2026-11-13 (sheet 60, Joshua: "I agree this is right"): grouped by WHERE each setting shows on your screen. The
    -- preview window docked beside Options (Preview.lua) lights the part of the scene a group controls.
    { header = 'Your target frame' },
    { key = 'doomed', default = true, control = 'check', label = 'Kill bar',
      tip = "Your DoTs' coming damage, in their own colours, inside the enemy's health bar." },
    { key = 'skull', default = true, control = 'check', label = 'Skull', parent = BAR,
      tip = 'A skull and bones on the portrait ring when your DoTs alone will finish the enemy.' },
    { key = 'cast', default = 'charging', control = 'dropdown', label = 'While you cast', parent = BAR,
      choices = { { 'charging', 'Charging' }, { 'smoulder', 'Smoulder' }, { 'stripes', 'Drifting stripes' }, { 'motes', 'Motes' }, { 'plain', 'Plain' } },
      tip = "How a DoT's piece looks while you cast it:\n|cffffd100Charging:|r fills with your cast bar, an ember at its front.\n|cffffd100Smoulder:|r its colour rises out of the dark.\n|cffffd100Drifting stripes:|r stripes slide toward the green.\n|cffffd100Motes:|r small pixels drift through it.\n|cffffd100Plain:|r dim, then solid when the spell lands." },
    { key = 'tick', default = 'ember', control = 'dropdown', label = 'Tick light', parent = BAR,
      choices = { { 'ember', 'Ember' }, { 'cinders', 'Cinders' }, { 'essence', 'Essence' }, { 'plain', 'Plain' } },
      tip = "What happens when a DoT ticks:\n|cffffd100Ember:|r the bitten part glows in its own colour and settles.\n|cffffd100Cinders:|r the same glow, and small embers lift off it.\n|cffffd100Essence:|r a soft curl of shadow haze rises from it.\n|cffffd100Plain:|r it just slides shut." },
    { key = 'low', default = 3, control = 'slider', label = 'Ending soon', parent = BAR, min = 2, max = 5, step = 1,
      format = function(v) return ('%d s'):format(v) end,
      tip = "In a DoT's last seconds its piece on your target's kill bar, and its ring, turn gold." },
    { key = 'lowlook', default = 'breathe', control = 'dropdown', label = 'Ending soon look', parent = BAR,
      choices = { { 'breathe', 'Breathing gold' }, { 'steady', 'Steady gold' } },
      tip = "How the gold looks in a DoT's last seconds: breathing on the rings' beat, or steady." },
    { key = 'targetPath', default = '' },   -- another add-on's target health bar, by frame name (/omadoomed frame)
    { button = 'Pick', name = 'Target health bar', click = function() if ns.startPick then ns.startPick() end end,
      tip = "Only if another add-on replaced your target frame: click Pick, close Options, then click its health bar (out of combat, with a mouse). Or type /omadoomed frame and the bar's name." },

    { header = 'Over enemies' },
    { key = 'platebar', default = true, control = 'check', label = 'Kill bar over enemies', parent = BAR,
      tip = "The same kill bar inside the health bar over every enemy you DoT." },
    { key = 'enabled', store = R, default = true, control = 'check', label = 'Rings',
      tip = "Your DoTs as rings over enemies. Off: Blizzard's own debuff icons come back on nameplates, and on the target frame unless Blizzard's squares is set to Hide." },
    { key = 'which', store = R, default = 'all', control = 'dropdown', label = 'Which enemies',
      choices = { { 'all', 'Every enemy' }, { 'target', 'Only your target' }, { 'combat', 'Only in combat' } },
      tip = "Which enemies get rings:\n|cffffd100Every enemy:|r every enemy you DoT.\n|cffffd100Only your target:|r just the one you target.\n|cffffd100Only in combat:|r every enemy, only while you're fighting." },
    -- 2026-11-13 (Joshua: "a toggle to show other enemies Dots like this or just track it regularly with the blizz default"):
    -- one toggle replaces 'Blizzard's squares'. As rings: theirs are faint rings, Blizzard's debuff squares on mobs go.
    -- Blizzard default: OmaDoomed draws only yours; Blizzard's squares stay as Blizzard draws them.
    { key = 'othersMode', store = R, default = 'rings', control = 'dropdown', label = "Other players' DoTs",
      choices = { { 'rings', 'As rings' }, { 'blizzard', 'Blizzard default' } },
      tip = "Other players' DoTs on the enemies you fight:\n|cffffd100As rings:|r faint rings beside yours, and Blizzard's debuff squares on mobs are hidden.\n|cffffd100Blizzard default:|r OmaDoomed shows only your DoTs; Blizzard's own squares stay just as Blizzard draws them." },
    { key = 'othersAlpha', store = R, default = 55, control = 'slider', label = "Their rings' strength", min = 10, max = 100, step = 5, format = pct,
      tip = "How solid other players' rings are, when they show as rings. A new strength shows after a /reload." },
    { key = 'others', store = R, default = true },    -- /omadoomed rings others on|off
    { key = 'cc', store = R, default = true, control = 'check', label = 'Crowd-control timers',
      tip = "Your Fear, Banish, Howl of Terror and your Sayaad's Seduction as a teal ring over the mob. When it isn't your target or is off screen, the ring stands beside your target frame instead, so you always see how long is left." },

    { header = 'Where the rings go' },
    { key = 'where', store = R, default = 'enemy', control = 'dropdown', label = 'Where the rings show',
      choices = { { 'enemy', 'Above enemies' }, { 'frame', 'Target frame' }, { 'split', 'Haunt' } },
      tip = "Where your rings show:\n|cffffd100Above enemies:|r over every enemy's head.\n|cffffd100Target frame:|r only on your target's frame.\n|cffffd100Haunt:|r over every enemy you're not targeting. Your target's rings sit on its frame; your curse, channel and crowd control stay over its head." },

    { header = 'Ring look' },
    { key = 'look', store = R, default = 'rich', control = 'dropdown', label = 'Ring look',
      choices = { { 'rich', 'Modern' }, { 'flat', 'Classic' } },   -- Joshua 2026-11-13: "The 2 ring settings are modern and classic"
      tip = "How your rings look:\n|cffffd100Modern:|r a lit ring with a bezel and a bold number.\n|cffffd100Classic:|r a plain ring, the spell's icon clear, a thin number.\nShows after a /reload (type /reload, or Reload UI in the game menu: Esc, or Menu on a controller)." },
    { key = 'size', store = R, default = 40, control = 'slider', label = 'Ring size', min = 28, max = 60, step = 2, format = tostring,
      tip = "How big your rings are. 40 is Blizzard's own size." },
    { key = 'alpha', store = R, default = 100, control = 'slider', label = 'Ring opacity', min = 20, max = 100, step = 5, format = pct,
      tip = 'How solid your own rings are.' },

    { key = 'squares', store = R, default = 'notmine' },   -- set by othersMode (As rings: notmine; Blizzard default: all)

    { header = 'Help' },
    { button = 'Show', name = 'Preview window', click = function() if ns.previewOpen then ns.previewOpen(true) end end,
      tip = 'Opens the preview beside this page again if you closed it.' },
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
  -- 4: 'Blizzard's squares' and the strength slider's 0 become one toggle (2026-11-13): squares All, theirs hidden,
  -- or strength 0 mean Blizzard default; anything else stays As rings
  function(db)
    local r = db.rings; if type(r) ~= 'table' then return end
    if r.othersMode == nil then
      r.othersMode = (r.squares == 'all' or r.others == false or r.othersAlpha == 0) and 'blizzard' or 'rings'
    end
    r.squares = r.othersMode == 'blizzard' and 'all' or 'notmine'
    if r.othersAlpha == 0 then r.othersAlpha = 55 end
  end,
}

function ns.buildSettings() ns.settingsCategory = ns.settings:Build(ns.db, 'OmaDoomed') end

-- /omadoomed options
function ns.openSettings() ns.settings:Open() end
