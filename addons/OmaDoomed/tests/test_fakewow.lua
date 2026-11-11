-- Checks the fake itself, so later failures are about the add-on, not the harness.
return {
  ['clock moves and OnUpdate runs'] = function(W, T)
    local f = CreateFrame('Frame'); local n = 0
    f:SetScript('OnUpdate', function() n = n + 1 end)
    W.advance(1, 0.1); T.eq(n, 10); T.near(GetTime(), 1001, 1e-9)
  end,
  ['unit events only reach the units asked for'] = function(W, T)
    local f = CreateFrame('Frame'); local got = {}
    f:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
    f:SetScript('OnEvent', function(_, e, unit) got[#got + 1] = unit end)
    W.fire('UNIT_SPELLCAST_SUCCEEDED', 'target'); W.fire('UNIT_SPELLCAST_SUCCEEDED', 'player')
    T.eq(#got, 1); T.eq(got[1], 'player')
  end,
  ['health is secret in combat and maths on it raises'] = function(W, T)
    W.units.target = { guid = 'Creature-1', hp = 50, maxhp = 100, enemy = true }
    T.eq(UnitHealth('target'), 50)
    W.combat = true
    local h = UnitHealth('target'); T.ok(issecretvalue(h))
    T.ok(not pcall(function() return h + 1 end), 'secret maths must raise')
    T.ok(not pcall(function() return h < 3 end), 'secret compare must raise')
  end,
  ['timers fire on the clock'] = function(W, T)
    local fired = false; C_Timer.After(0.5, function() fired = true end)
    W.advance(0.4); T.ok(not fired); W.advance(0.2); T.ok(fired)
  end,
}
