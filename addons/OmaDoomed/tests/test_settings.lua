-- The Options page (Settings.lua) on the strict fake Settings API: every control is built from Blizzard's own
-- controls with its default, and a change reaches the add-on at once.
local KEYS = { 'doomed', 'skull', 'cast', 'tick', 'low', 'lowlook', 'platebar', 'enabled', 'where', 'squares', 'which', 'size', 'alpha', 'othersAlpha' }
local KINDS = { doomed = 'checkbox', skull = 'checkbox', cast = 'dropdown', tick = 'dropdown', low = 'slider', lowlook = 'dropdown', platebar = 'checkbox', enabled = 'checkbox',
  where = 'dropdown', squares = 'dropdown', which = 'dropdown', size = 'slider', alpha = 'slider', othersAlpha = 'slider' }
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
    T.eq(table.concat(kinds, ','), 'element,header:Kill bar,checkbox,checkbox,dropdown,dropdown,slider,dropdown,checkbox,button,header:Rings,checkbox,dropdown,dropdown,dropdown,slider,slider,slider,header:Help,button,button',
      'preview, headers, controls, the Pick button and the two report buttons')
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
  ['preview: a pooled row is shown and recycled with no error, and nothing is written or hooked onto it'] = function(W, T)
    local ns, F, UI = setup(W)
    local init = ns.settingsCategory.layout.inits[1]
    T.eq(init.kind, 'element', 'the preview is the first row')
    local row = UI.S.row()
    local before = {}; for k in pairs(row) do before[k] = true end
    UI.S.show(init, row)
    T.ok(UI.isVisible(row) and #UI.kids(row) == 1, 'our preview sits in the row')
    local ok, err = pcall(ns.previewDraw); T.ok(ok, 'draws: ' .. tostring(err))
    for k in pairs(row) do if not before[k] and k ~= '_kids' then T.ok(false, 'wrote ' .. tostring(k) .. ' onto the row') end end
    T.eq(row.scripts.OnHide, nil, 'no script hooked on the row')
    local okR, errR = pcall(UI.S.recycle, init, row)
    T.ok(okR, 'recycling the row: ' .. tostring(errR))
    local P = UI.kids(row)[1]
    T.ok(P == nil or not P:IsShown(), 'the preview went away with the row')
    -- the same pooled row reused for us again
    T.ok(pcall(UI.S.show, init, UI.S.row()), 'shown again in another pooled row')
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
    local init = ns.settingsCategory.layout.inits[1]
    local ok, err = pcall(UI.S.show, init, UI.S.row()); T.ok(ok, 'builds: ' .. tostring(err))
    local okD, errD = pcall(ns.previewDraw); T.ok(okD, 'draws: ' .. tostring(errD))
    T.eq(#touched, 0, 'no size or position read off TargetFrame: ' .. table.concat(touched, ','))
  end,
}
