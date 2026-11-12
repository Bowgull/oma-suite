-- OmaCore (Libs/OmaCore) on its own: LibStub versioning, Bus, Anim, Log, Secret, Slash, the Settings schema.
local LIBS = { 'Libs/LibStub/LibStub.lua', 'Libs/OmaCore/OmaCore.lua', 'Libs/OmaCore/Bus.lua', 'Libs/OmaCore/Anim.lua',
  'Libs/OmaCore/Secret.lua', 'Libs/OmaCore/Log.lua', 'Libs/OmaCore/Settings.lua', 'Libs/OmaCore/Slash.lua' }

local function core(W) W.load('.', 'OmaTest', LIBS, {}); return LibStub('OmaCore-1.0') end
-- this copy of OmaCore with another minor version, loaded the way a second add-on would
local function loadCopy(W, minor, mark)
  local ns = {}
  for _, f in ipairs(LIBS) do
    local src = io.open(f):read('*a')
    if f:find('OmaCore.lua', 1, true) then src = src:gsub("'OmaCore%-1%.0', %d+", "'OmaCore-1.0', " .. minor) end
    if f:find('Bus.lua', 1, true) then src = src:gsub('function Core%.NewBus%(onError%)', 'Core.mark = "' .. mark .. '"\nfunction Core.NewBus(onError)') end
    assert(loadstring(src, f))('Other', ns)
  end
  return ns
end

return {
  ['LibStub: the newest OmaCore copy wins, an older or equal one changes nothing'] = function(W, T)
    loadCopy(W, 1, 'one')
    local C = LibStub('OmaCore-1.0'); T.eq(C.mark, 'one'); T.eq(C.MINOR, 1)
    local ns = loadCopy(W, 1, 'same'); T.eq(C.mark, 'one', 'equal minor: skipped'); T.eq(ns.omaCoreBuild, nil)
    loadCopy(W, 0, 'old'); T.eq(C.mark, 'one', 'older: skipped')
    loadCopy(W, 2, 'new'); T.eq(LibStub('OmaCore-1.0'), C, 'same table, upgraded in place'); T.eq(C.mark, 'new'); T.eq(C.MINOR, 2)
  end,

  ['Bus: listeners in order, one error does not stop the rest, Off during Fire is safe'] = function(W, T)
    local C = core(W)
    local errs, got = {}, {}
    local bus = C.NewBus(function(ev, err) errs[#errs + 1] = ev .. ':' .. tostring(err) end)
    local second
    bus:On('X', function(a, b) got[#got + 1] = 'a' .. a .. b; bus:Off('X', second) end)
    bus:On('X', function() error('boom', 0) end)
    second = bus:On('X', function(a) got[#got + 1] = 'c' .. a end)
    bus:Fire('X', 1, 2)
    T.eq(table.concat(got, ','), 'a12,c1', 'all three ran in order (the Off applies to the next Fire)')
    T.eq(#errs, 1); T.eq(errs[1], 'X:boom')
    got = {}; bus:Fire('X', 3, 4); T.eq(table.concat(got, ','), 'a34', 'removed for the next Fire')
    bus:Fire('nobody'); T.ok(not bus:Has('nobody'))
  end,

  ['Anim: the same numbers as the copies it replaces (Doomed, Rings, Preview, KillPlates)'] = function(W, T)
    local A = core(W).Anim
    -- the old copies, verbatim
    local function oldDoomedBreath(low, x) local ph = (low - x) / 1.5 % 1; return .3 + .7 * (math.cos(ph * 2 * math.pi) * .5 + .5) end
    local function oldRingsBreath(x) local t = 3 - x; return 0.3 + (1 - 0.3) * (0.5 + 0.5 * math.cos(2 * math.pi * t / 1.5)) end
    local function oldSmoother(a) local k = math.max(0, math.min(1, a)); return k * k * k * (k * (k * 6 - 15) + 10) end
    local function oldSS(v) v = math.max(0, math.min(1, v)); return v * v * (3 - 2 * v) end
    local function oldEaseIn(x) return x * x end
    local function oldEaseOut(x) return 1 - (1 - x) ^ 3 end
    for i = -20, 140 do
      local x = i / 20
      for _, low in ipairs({ 2, 3, 4, 5 }) do T.near(A.breath(x, low, 1.5, .3), oldDoomedBreath(low, x), 1e-12, 'kill bar breath at ' .. x) end
      T.near(A.breath(x, 3, 1.5, .3), oldRingsBreath(x), 1e-12, 'ring breath at ' .. x)
      T.near(A.breath(x), oldRingsBreath(x), 1e-12, 'defaults are the rings\' breath')
      T.near(A.smootherstep(x), oldSmoother(x), 1e-15, 'smootherstep')
      T.near(A.smoothstep(x), oldSS(x), 1e-15, 'smoothstep')
      if x >= 0 and x <= 1 then T.near(A.easeIn(x), oldEaseIn(x), 1e-15); T.near(A.easeOut(x), oldEaseOut(x), 1e-15) end
    end
    T.eq(A.breath(3, 3), 1, '1 at the start'); T.near(A.breath(2.25, 3), .3, 1e-12, '0.3 halfway')
  end,

  ['Log: once per message, error handler sees errors, one chat line on the first failure'] = function(W, T)
    local C = core(W)
    local handled, said = {}, {}
    geterrorhandler = function() return function(m) handled[#handled + 1] = m end end
    local saved = {}
    local log = C.NewLog({ name = 'OmaTest', store = function() return saved end, say = function(m) said[#said + 1] = m end, report = '/omatest report' })
    log:Note('learned x'); log:Note('learned x')
    T.eq(#saved.errs, 1, 'a repeat is not stored again'); T.eq(#handled, 0, 'notes stay out of the error handler')
    log:Error('bad thing'); log:Error('bad thing')
    T.eq(#saved.errs, 2); T.eq(#handled, 1, 'the error handler sees it once'); T.eq(handled[1], 'OmaTest: bad thing')
    T.eq(#said, 0, 'a plain error says nothing in chat')
    log:Fail('render: boom', 'the kill bar'); log:Fail('update: other', 'the kill bar'); log:Fail('render: boom', 'the kill bar')
    T.eq(#said, 1, 'one chat line per session')
    T.eq(said[1], 'the kill bar paused until /reload; /omatest report saves the details.')
    T.eq(#handled, 3)
    T.ok(saved.errs[1]:find('update: other', 1, true), 'newest first')
    for i = 1, 40 do log:Note('n' .. i) end
    T.eq(#saved.errs, 30, 'keeps the last 30')
  end,

  ['Secret: never compares or formats a secret'] = function(W, T)
    local S = core(W).Secret
    local s = W.secret(5)
    T.ok(S.is(s)); T.ok(not S.is(5)); T.ok(not S.readable(s)); T.ok(not S.readable(nil)); T.ok(S.readable(0))
    T.eq(S.eq(s, 5), nil, 'cannot tell'); T.eq(S.eq(5, 5), true); T.eq(S.eq(4, 5), false)
    T.eq(S.isTrue(W.secret(true)), false); T.eq(S.isTrue(true), true); T.eq(S.isTrue(1), false)
    T.eq(S.fmt('%.0f', s), '?'); T.eq(S.fmt('%.0f', nil), '?'); T.eq(S.fmt('%.0f', 4.6), '5')
    T.eq(S.call(function() return s end), nil); T.eq(S.call(function() error('x') end), nil); T.eq(S.call(function(a) return a end, 3), 3)
  end,

  ['Slash: exact first, then the first word, then the fallback; lower-cased; errors caught'] = function(W, T)
    local C = core(W)
    local got, errs = {}, {}
    local s = C.NewSlash('OMATEST', '/omatest', function(m) got[#got + 1] = 'fallback:' .. m end, function(e) errs[#errs + 1] = e end)
    s:Exact('report', function() got[#got + 1] = 'report' end)
    s:Exact('report show', function() got[#got + 1] = 'show' end)
    s:Word('rings', function(rest) got[#got + 1] = 'rings:' .. rest end)
    s:Exact('bad', function() error('oops', 0) end)
    T.eq(SLASH_OMATEST1, '/omatest')
    for _, m in ipairs({ 'Report', 'report show', 'rings Others ON', 'rings', 'TEST off', '', 'bad' }) do SlashCmdList.OMATEST(m) end
    T.eq(table.concat(got, '|'), 'report|show|rings:others on|rings:|fallback:test off|fallback:')
    T.eq(errs[1], 'oops')
    -- a word can keep the case of what follows (a frame name)
    s:Word('frame', function(rest) got[#got + 1] = 'frame:' .. rest end, true)
    got = {}; SlashCmdList.OMATEST('Frame  MyFrame.Health'); SlashCmdList.OMATEST('frame')
    T.eq(table.concat(got, '|'), 'frame:MyFrame.Health|frame:')
  end,

  ['Settings schema: defaults, fill keeps saved values, numbered migrations, dump'] = function(W, T)
    local C = core(W)
    local s = C.NewSettings({ items = {
      { header = 'A' },
      { key = 'a', default = true, control = 'check', label = 'A' },
      { key = 'b', default = 3, store = 'sub' },
      { key = 'c', default = 'x', store = 'sub' },
    } })
    T.eq(s:Default('a'), true); T.eq(s:Default('b'), 3); T.eq(s:Store('b'), 'sub'); T.eq(s:Store('a'), nil)
    local db = { sub = { c = 'kept' }, other = 1 }
    s:Fill(db)
    T.eq(db.a, true); T.eq(db.sub.b, 3); T.eq(db.sub.c, 'kept', 'saved values are kept')
    -- migrations: each step once, in order; a failing step stops the run and is reported
    local ran, errs = {}, {}
    local steps = { function(d) ran[#ran + 1] = 1 end, function(d) ran[#ran + 1] = 2; d.sub.b = 4 end }
    T.ok(s:Migrate(db, steps)); T.eq(db.v, 2); T.eq(table.concat(ran, ','), '1,2'); T.eq(db.sub.b, 4)
    T.ok(s:Migrate(db, steps)); T.eq(table.concat(ran, ','), '1,2', 'nothing runs twice')
    steps[3] = function() error('broken', 0) end; steps[4] = function() ran[#ran + 1] = 4 end
    T.eq(s:Migrate(db, steps, function(m) errs[#errs + 1] = m end), false)
    T.eq(db.v, 2, 'stays at the last good step'); T.eq(errs[1], 'saved data upgrade 3: broken'); T.eq(#ran, 2, 'later steps wait')
    local fresh = {}; s:Migrate(fresh, { function() end }); T.eq(fresh.v, 1, 'a fresh install gets the newest version')
    local d = s:Dump({ a = false, other = 'x', t = {}, sub = { c = 'y' } })
    T.eq(d.main.a, false); T.eq(d.main.other, 'x'); T.eq(d.main.t, nil, 'only plain values')
    T.eq(d.sub.c, 'y'); T.eq(d.sub.b, 3, 'a missing value shows its default')
    T.ok(not pcall(C.NewSettings, { items = { { key = 'z' } } }), 'a setting with no default is refused')
  end,
}
