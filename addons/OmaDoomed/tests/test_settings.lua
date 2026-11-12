-- The Options page (Settings.lua) on the strict fake Settings API: every control is built from Blizzard's own
-- controls with its default, and a change reaches the add-on at once.
local KEYS = { 'doomed', 'skull', 'cast', 'tick', 'low', 'lowlook', 'where', 'squares', 'which', 'size', 'alpha', 'othersAlpha' }
local KINDS = { doomed = 'checkbox', skull = 'checkbox', cast = 'dropdown', tick = 'dropdown', low = 'slider', lowlook = 'dropdown',
  where = 'dropdown', squares = 'dropdown', which = 'dropdown', size = 'slider', alpha = 'slider', othersAlpha = 'slider' }
local UNDER_BAR = { skull = true, cast = true, tick = true, low = true, lowlook = true }

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
      local want = ns.DEFAULTS[k]; if want == nil then want = ns.RING_DEFAULTS[k] end
      T.eq(c[k].setting.default, want, k .. ' default')
      T.eq(c[k].setting:GetValue(), want, k .. ' value on a fresh install')
      if UNDER_BAR[k] then T.ok(c[k].parentInit == c.doomed, k .. ' greys out with the kill bar') end
    end
    local cat = ns.settingsCategory
    T.eq(cat.name, 'OmaDoomed'); T.eq(cat.parent.name, 'Oma')
    T.eq(UI.S.addOnCategories[1], cat.parent, 'the Oma parent registered at login')
    local kinds = {}; for _, i in ipairs(cat.layout.inits) do kinds[#kinds + 1] = i.kind == 'header' and ('header:' .. i.text) or i.kind end
    T.eq(table.concat(kinds, ','), 'element,header:Kill bar,checkbox,checkbox,dropdown,dropdown,slider,dropdown,header:Rings,dropdown,dropdown,dropdown,slider,slider,slider,header:Help,button,button',
      'preview, headers, controls and the two report buttons')
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
    T.ok(frame.omaNotch and frame.omaNotch:IsShown(), 'notch made and shown')
    SlashCmdList.OMADOOMED('options')
    T.eq(UI.S.opened[1], ns.settingsCategory:GetID())
  end,
}
