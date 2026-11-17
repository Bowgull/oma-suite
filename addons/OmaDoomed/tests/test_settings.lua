-- The Options page (Settings.lua) on the strict fake Settings API: every control is built from Blizzard's own
-- controls with its default, and a change reaches the add-on at once.
local KEYS = { 'doomed', 'skull', 'cast', 'tick', 'low', 'lowlook', 'platebar', 'enabled', 'which', 'othersMode', 'othersAlpha', 'recast', 'occ', 'odeb', 'cc', 'on', 'rows', 'scale', 'sort', 'threat', 'range', 'hp', 'fadeDone', 'casts', 'back', 'calm', 'where', 'look', 'size', 'alpha' }
local KINDS = { look = 'dropdown', doomed = 'checkbox', skull = 'checkbox', cast = 'dropdown', tick = 'dropdown', low = 'slider', lowlook = 'dropdown', platebar = 'checkbox', enabled = 'checkbox',
  where = 'dropdown', othersMode = 'dropdown', which = 'dropdown', size = 'slider', alpha = 'slider', othersAlpha = 'slider', cc = 'checkbox',
  recast = 'checkbox', occ = 'checkbox', odeb = 'checkbox', casts = 'checkbox', fadeDone = 'checkbox',
  on = 'checkbox', rows = 'slider', scale = 'slider', sort = 'dropdown', threat = 'checkbox', range = 'checkbox', hp = 'checkbox', back = 'slider', calm = 'checkbox' }
local UNDER_BAR = { skull = true, cast = true, tick = true, low = true, lowlook = true, platebar = true }

local function setup(W, opts)
  local ns, F, UI = require('load').addon(opts)
  return ns, F, UI
end
local function byKey(UI) local out = {}; for _, c in ipairs(UI.S.controls) do out[c.setting.key] = c end; return out end

return {
  ['the page builds every control, in order, with its default, under Oma > OmaDoomed'] = function(W, T)
    local ns, F, UI = setup(W)
    for _, p in ipairs(W.printed) do T.ok(not p:find('settings page failed', 1, true), p) end
    local keys = {}; for _, c in ipairs(UI.S.controls) do keys[#keys + 1] = c.setting.key end
    T.eq(table.concat(keys, ','), table.concat(KEYS, ','), 'every setting, in order')
    local c = byKey(UI)
    for _, k in ipairs(KEYS) do
      T.eq(c[k].kind, KINDS[k], k .. ' control')
      local want = ns.settings:Default(k)
      T.eq(c[k].setting.default, want, k .. ' default')
      T.eq(c[k].setting:GetValue(), want, k .. ' value on a fresh install')
      if UNDER_BAR[k] then T.ok(c[k].parentInit == c.doomed, k .. ' greys out with the kill bar') end
    end
    local cat = ns.settingsCategory
    T.eq(cat.name, 'OmaDoomed'); T.eq(cat.parent.name, 'Oma')
    T.eq(UI.S.addOnCategories[1], cat.parent, 'the Oma parent registered at login')
    local kinds = {}; for _, i in ipairs(cat.layout.inits) do kinds[#kinds + 1] = i.kind == 'header' and ('header:' .. i.text) or i.kind end
    T.eq(table.concat(kinds, ','), "header:Your target frame,checkbox,checkbox,dropdown,dropdown,slider,dropdown,button,header:Over enemies,checkbox,checkbox,dropdown,dropdown,slider,checkbox,checkbox,checkbox,checkbox,header:Mob list,checkbox,slider,slider,dropdown,checkbox,checkbox,checkbox,checkbox,checkbox,slider,button,checkbox,header:Where the rings go,dropdown,header:Ring look,dropdown,slider,slider,header:Help,button,button,button",
      'grouped by place on screen (sheet 60): headers, controls, Pick, the preview button and the two report buttons')
  end,
  ['saved values are kept, not reset to defaults'] = function(W, T)
    local ns, F, UI = setup(W, { before = function() OmaDoomedDB = { cast = 'motes', rings = { size = 52 } } end })
    local c = byKey(UI)
    T.eq(c.cast.setting:GetValue(), 'motes'); T.eq(c.size.setting:GetValue(), 52)
  end,
  ['a change reaches the add-on at once (rings size, kill bar off)'] = function(W, T)
    local ns, F, UI = setup(W, { rings = true }); W.advance(3)
    local c = byKey(UI)
    c.size.setting:SetValue(60)
    T.eq(OmaDoomedDB.rings.size, 60)
    local ring = UI.ringContainers()[1]
    T.near(ring:GetParent():GetScale(), 60 / 40, 1e-9, 'every row rescaled')
    c.doomed.setting:SetValue(false)
    T.eq(ns.db.doomed, false)
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,
  ['sliders: the default notch is drawn on the real slider frame; /omadoomed options opens the page'] = function(W, T)
    local ns, F, UI = setup(W)
    local frame = { SliderWithSteppers = { Slider = UI.obj('Slider') } }   -- a plain table: unknown fields read nil, as on a real frame
    frame.SliderWithSteppers.Slider._w = 200
    byKey(UI).size:InitFrame(frame)
    local n = ns.settings:NotchOf(frame)
    T.ok(n and n:IsShown(), 'notch made and shown')
    T.eq(rawget(frame, 'omaNotch'), nil, "nothing written onto Blizzard's frame")
    SlashCmdList.OMADOOMED('options')
    T.eq(UI.S.opened[1], ns.settingsCategory:GetID())
  end,
  ['phase 6: the plate bar and the rings switch off from Options'] = function(W, T)
    local ns, F, UI = setup(W, { rings = true })
    W.advance(3)
    local c = byKey(UI)
    c.platebar.setting:SetValue(false); T.eq(ns.db.platebar, false, 'plate bar off')
    c.enabled.setting:SetValue(false); W.advance(.1)
    T.eq(ns.db.rings.enabled, false, 'rings off')
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
    c.enabled.setting:SetValue(true); W.advance(.1)
    T.eq(ns.db.rings.enabled, true, 'and back on')
  end,
  ['phase 6: one hello per account, never twice'] = function(W, T)
    local ns = setup(W)
    local n = 0; for _, p in ipairs(W.printed) do if p:find('/omadoomed options', 1, true) then n = n + 1 end end
    T.eq(n, 1, 'the hello said once')
    T.ok(OmaDoomedDB.told and OmaDoomedDB.told.hello1, 'remembered for the account')
  end,

  -- 2026-11-13 BugSack: 'Blizzard_SettingControls.lua:382: attempt to index field 'cbrHandles' (a nil value)' in
  -- Release when switching categories, and 'Preview.lua:84 copyRegion: SetSize (Secret values...)'
  ['preview window: opens beside Options, draws, and lives in no settings row'] = function(W, T)
    local ns, F, UI = setup(W)
    for _, i in ipairs(ns.settingsCategory.layout.inits) do T.ok(i.kind ~= 'element', 'no preview row in the list any more') end
    local ok, err = pcall(ns.previewOpen); T.ok(ok, 'opens: ' .. tostring(err))
    local win = ns.previewWindow(); T.ok(win and win:IsShown(), 'the window shows')
    local okD, errD = pcall(ns.previewDraw); T.ok(okD, 'draws: ' .. tostring(errD))
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,

  ['preview: never reads the live target frame (its sizes are hidden on Forever)'] = function(W, T)
    local ns, F, UI = setup(W)
    -- every size and position on the real target frame comes back hidden
    local touched = {}
    local function hide(o, depth)
      if type(o) ~= 'table' or depth > 6 then return end
      for _, m in ipairs({ 'GetWidth', 'GetHeight', 'GetLeft', 'GetTop', 'GetSize' }) do
        rawset(o, m, function() touched[#touched + 1] = m; return W.secret(100), W.secret(100) end)
      end
      for _, k in ipairs(UI.kids(o)) do hide(k, depth + 1) end
    end
    hide(TargetFrame, 0)
    local ok, err = pcall(ns.previewOpen); T.ok(ok, 'builds: ' .. tostring(err))
    local okD, errD = pcall(ns.previewDraw); T.ok(okD, 'draws: ' .. tostring(errD))
    T.eq(#touched, 0, 'no size or position read off TargetFrame: ' .. table.concat(touched, ','))
  end,

  -- release tidy-up (migration 3): the shape of a real saved file from the Shadow, 2026-11-13
  ['upgrade: Blizzard squares All becomes Blizzard default, anything else As rings (migration 4)'] = function(W, T)
    local ns = setup(W, { before = function() OmaDoomedDB = { v = 3, rings = { squares = 'all' } } end })
    T.eq(OmaDoomedDB.rings.othersMode, 'blizzard'); T.eq(OmaDoomedDB.rings.squares, 'all')
  end,
  ['upgrade: default squares stay As rings (migration 4)'] = function(W, T)
    local ns = setup(W, { before = function() OmaDoomedDB = { v = 3, rings = { squares = 'notmine', othersAlpha = 40 } } end })
    T.eq(OmaDoomedDB.rings.othersMode, 'rings'); T.eq(OmaDoomedDB.rings.squares, 'notmine'); T.eq(OmaDoomedDB.rings.othersAlpha, 40)
  end,

  ['upgrade: debug leftovers and Does It Die look settings are removed, learned ticks and settings kept'] = function(W, T)
    local errs = {}; for i = 1, 30 do errs[i] = 'old error ' .. i end
    local ns, F, UI = setup(W, { before = function()
      OmaDoomedDB = { v = 2, doomed = true, cast = 'motes', low = 4, tfdump = { 'TF Button shown=true' }, plateGeo = { w = 1 }, errs = errs,
        told = { hello1 = true }, rings = { where = 'split', size = 44 },
        track = { ticks = { [172] = 16.3 }, tickWeights = { [172] = 29 }, omaRatio = { Corruption = 1.09 }, version = 5,
          plateFillOpacity = 40, skullIcon = 'cross', focusOutlineColor = 'gold', nameplateMode = 'markerIcon', waitFirstTick = 'off' } }
    end })
    local db = OmaDoomedDB
    T.eq(db.v, 4, 'saved-data version 4')
    T.eq(db.tfdump, nil, 'the target-frame debug dump is gone'); T.eq(db.plateGeo, nil)
    T.eq(#db.errs, 20, 'the error list keeps its newest 20'); T.eq(db.errs[20], 'old error 30'); T.eq(db.errs[1], 'old error 11')
    T.eq(db.track.ticks[172], 16.3, 'learned tick sizes kept'); T.eq(db.track.tickWeights[172], 29); T.eq(db.track.omaRatio.Corruption, 1.09)
    for _, k in ipairs({ 'plateFillOpacity', 'skullIcon', 'focusOutlineColor', 'nameplateMode' }) do T.eq(db.track[k], nil, k .. ' (a Does It Die look setting) removed') end
    T.eq(db.track.waitFirstTick, 'off', 'a tracking setting kept')
    T.eq(db.cast, 'motes', 'his own settings untouched'); T.eq(db.low, 4); T.eq(db.rings.where, 'split'); T.eq(db.rings.size, 44); T.eq(db.told.hello1, true)
    local n = 0; for _ in pairs(db.track) do n = n + 1 end
    T.ok(n <= 12, 'nothing put back by the engine: ' .. n .. ' keys in db.track')
  end,
  ['preview: the mob list block follows the list settings (rows, sort, cast lines, range)'] = function(W, T)
    local ns, F, UI = setup(W)
    T.ok(pcall(ns.previewOpen), 'opens')
    OmaDoomedDB.list = OmaDoomedDB.list or {}
    OmaDoomedDB.list.casts = true; OmaDoomedDB.list.range = true
    local ok, err = pcall(ns.previewDrawList, .5); T.ok(ok, 'draws the list: ' .. tostring(err))
    OmaDoomedDB.list.sort = 'soonest'; OmaDoomedDB.list.casts = false
    ok, err = pcall(ns.previewDrawList, 1); T.ok(ok, 'and again with other settings: ' .. tostring(err))
    T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1]))
  end,
}
