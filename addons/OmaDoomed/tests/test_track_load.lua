return {
  ['tracking loads and starts with nothing'] = function(W, T)
    local L = require('load')
    L.spells({})
    local OMA = L.oma()
    T.ok(OMA.track.tracking, 'engine exported its tracking')
    T.eq(#OMA.dotsFor('target'), 0)
    T.ok(type(OmaDoomedDB.track) == 'table', 'saved data in OmaDoomedDB.track')
  end,
  ['both engines load side by side'] = function(W, T)
    local L = require('load')
    L.spells({})
    local OMA = L.oma(); local did = L.did()
    T.ok(OMA.track ~= did, 'separate namespaces')
    T.ok(DoesItDieDB ~= OmaDoomedDB.track, 'separate saved data')
  end,
}
