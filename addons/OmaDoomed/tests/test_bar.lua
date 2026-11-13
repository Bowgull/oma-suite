-- The kill bar on the target frame (Doomed.lua): what it draws for a list of DoTs. These lock in today's behaviour
-- before the rebuild: piece order, precast (Charging), landing, the instant-cast "landed" piece, ending gold,
-- the skull, a tick's bite, and a target switch wiping everything. The DoT list is fed straight in (the model's
-- source), so only the model's and the bar's own logic is tested. Per-DoT state lives in the model's snapshot
-- (DotModel.lua): M.peek(name) is that DoT's record (slot, shown, bite, pred, wasPre).
local A, B = 'Creature-0-1-0-1-100-AAAA', 'Creature-0-1-0-1-101-BBBB'
local FRAME = 1 / 30
local COLOR = {   -- Doomed.lua's piece colours (sheet 34 B)
  Corruption = { 41 / 255, 40 / 255, 136 / 255 }, Immolate = { 160 / 255, 66 / 255, 22 / 255 },
  ['Bane of Agony'] = { 128 / 255, 30 / 255, 97 / 255 },
}
local GOLD = { 206 / 255, 160 / 255, 44 / 255 }
local function full(c) return { math.min(1, c[1] * 1.15), math.min(1, c[2] * 1.15), math.min(1, c[3] * 1.15) } end

local function setup(W)
  local ns, F, UI = require('load').addon()
  local M = ns.model
  F.mob('nameplate1', A, 'Kobold', 100); F.mob('nameplate2', B, 'Gnoll', 100)
  local DOTS = { [A] = {}, [B] = {} }
  M.source = function(u) local t = W.units[u]; return t and DOTS[t.guid] or {} end
  F.target(A)
  return ns, F, UI, M, DOTS
end
local function rec(M, name) return M.peek(name) or {} end
local function slot(M, name) return rec(M, name).slot end
local function anySlot(M) for _, r in pairs(M.snap().per) do if r.slot then return true end end return false end
local function anyOf(M, field) for _, r in pairs(M.snap().per) do if r[field] ~= nil then return true end end return false end
local function dot(W, name, damage, lasts, o)
  o = o or {}
  return { name = name, damage = damage, expiresAt = W.now + lasts, appliedAt = o.appliedAt or (W.now - 1), provisional = o.provisional or false }
end
local function colorIs(T, tex, want, msg)
  T.near(tex._r, want[1], 1e-6, msg .. ' (red)'); T.near(tex._g, want[2], 1e-6, msg .. ' (green)'); T.near(tex._b, want[3], 1e-6, msg .. ' (blue)')
end
local function noErrors(T) T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1])) end
-- the skull's window and its long bar (Doomed.lua build(): a HIGH-strata frame on the portrait's parent)
local function skull(UI)
  for _, k in ipairs(UI.kids(TargetFrame.TargetFrameContainer)) do
    if rawget(k, '_strata') == 'HIGH' then return k, UI.kids(k)[1] end
  end
end

return {
  ['pieces: the DoT that ends first sits nearest the green, each stacked on the last'] = function(W, T)
    local ns, F, UI, M, DOTS = setup(W)
    DOTS[A] = { dot(W, 'Bane of Agony', 84, 24), dot(W, 'Corruption', 47, 12), dot(W, 'Immolate', 20, 15) }
    W.advance(2, FRAME)
    T.eq(table.concat(M.snap().order, ','), 'Corruption,Immolate,Bane of Agony', 'order by expiry')
    local c, i, a = slot(M, 'Corruption'), slot(M, 'Immolate'), slot(M, 'Bane of Agony')
    T.ok(c and i and a and c ~= i and i ~= a, 'each DoT owns its own slot')
    T.ok(c.right == ns.parts.doomed.E[0].f and i.right == c.edge and a.right == i.edge, 'each piece hangs on the one before it')
    T.near(rec(M, 'Corruption').shown, 47, 1, 'grown to full size')
    T.near(c.mark.L:GetValue(), 47, 1, 'Corruption ends 47 into the green')
    T.near(i.mark.L:GetValue(), 67, 1, 'Immolate stacked after it')
    T.near(a.mark.L:GetValue(), 151, 1, 'Agony last')
    T.ok(c.base:IsShown() and i.base:IsShown() and a.base:IsShown(), 'all three drawn')
    colorIs(T, c.base, full(COLOR.Corruption), "Corruption's colour")
    colorIs(T, i.base, full(COLOR.Immolate), "Immolate's colour")
    noErrors(T)
  end,
  ['precast (Charging): the piece sits dim and fills with the cast bar, then lands at full colour'] = function(W, T)
    local ns, F, UI, M, DOTS = setup(W)
    T.eq(ns.db.cast, 'charging', 'the default look')
    local t0 = W.now
    UnitCastingInfo = function() return 'Corruption', nil, nil, t0 * 1000, (t0 + 2) * 1000 end
    DOTS[A] = { dot(W, 'Corruption', 47, 14, { provisional = true }) }
    W.advance(1, FRAME)
    local s = slot(M, 'Corruption')
    T.eq(rec(M, 'Corruption').wasPre, 'charging')
    T.near(s.cpr, .5, .05, 'filled as far as the cast')
    T.ok(s.cbase:IsShown(), 'the fill is drawn')
    colorIs(T, s.base, { COLOR.Corruption[1] * .45, COLOR.Corruption[2] * .45, COLOR.Corruption[3] * .45 }, 'the piece under it is dim')
    colorIs(T, s.cbase, full(COLOR.Corruption), 'the fill is the landed colour')
    UnitCastingInfo = function() return nil end
    DOTS[A][1].provisional = false
    W.advance(.1, FRAME)
    T.eq(rec(M, 'Corruption').wasPre, nil); T.ok(M.landAt.Corruption, 'landing noted')
    T.ok(not s.cbase:IsShown(), 'fill gone')
    colorIs(T, s.base, full(COLOR.Corruption), 'full colour at once')
    T.ok(s.spark:IsShown(), 'the ember fades out after landing')
    W.advance(.5, FRAME)
    T.ok(not s.spark:IsShown(), 'and is gone after 0.35 s')
    noErrors(T)
  end,
  ['an instant cast it has seen before shows a solid "landed" piece until the engine lists it, never in the skull'] = function(W, T)
    local ns, F, UI, M, DOTS = setup(W)
    DOTS[A] = { dot(W, 'Corruption', 47, 12, { appliedAt = W.now }) }
    W.advance(.3, FRAME)
    T.eq(M.fullBy.Corruption, 47, 'its fresh size is remembered')
    DOTS[A] = {}
    W.advance(1.5, FRAME)
    T.ok(not anySlot(M), 'gone from the bar')
    W.fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-1', 172)
    W.advance(.2, FRAME)
    T.ok(M.snap().landed and M.snap().landed.name == 'Corruption', 'landed piece held')
    T.eq(table.concat(M.snap().order, ','), 'Corruption')
    local _, long = skull(UI)
    T.eq(long:GetValue(), 0, 'not counted toward the skull')
    W.advance(5, FRAME)
    T.eq(M.snap().landed, nil, 'dropped after 4.5 s unlisted'); T.ok(not anySlot(M))
    noErrors(T)
  end,
  ['ending: the last 3 seconds turn gold (steady look), before that its own colour'] = function(W, T)
    local ns, F, UI, M, DOTS = setup(W)
    ns.db.lowlook = 'steady'
    DOTS[A] = { dot(W, 'Corruption', 20, 10) }
    W.advance(.5, FRAME)
    local s = slot(M, 'Corruption')
    colorIs(T, s.base, full(COLOR.Corruption), 'own colour with 9.5 s left')
    DOTS[A][1].expiresAt = W.now + 2
    W.advance(.2, FRAME)
    colorIs(T, s.base, full(GOLD), 'gold in the last 3 s')
    ns.db.lowlook = 'breathe'
    W.advance(.4, FRAME)
    T.near(s.base._r / s.base._g, full(GOLD)[1] / full(GOLD)[2], 1e-3, 'breathing gold: same hue')
    T.ok(s.base._r <= full(GOLD)[1] + 1e-9, 'never brighter than steady gold')
    noErrors(T)
  end,
  ['skull: shows when confirmed DoTs reach the health; off with the setting or a raid mark'] = function(W, T)
    local ns, F, UI, M, DOTS = setup(W)
    local win, long = skull(UI)
    T.ok(win and long, 'the skull window exists')
    DOTS[A] = { dot(W, 'Corruption', 60, 12), dot(W, 'Immolate', 50, 15), dot(W, 'Bane of Agony', 500, 24, { provisional = true }) }
    W.advance(.3, FRAME)
    T.ok(win:IsShown(), 'window shown')
    T.eq(select(2, long:GetMinMaxValues()), 100, 'scaled to the health')
    T.eq(long:GetValue(), 110, 'only confirmed DoTs count (the precast Agony does not)')
    DOTS[A] = { dot(W, 'Corruption', 30, 12) }
    W.advance(.3, FRAME)
    T.eq(long:GetValue(), 30, 'short of the health: the skull sits outside its window')
    ns.db.skull = false; W.advance(.2, FRAME)
    T.ok(not win:IsShown(), 'setting off: hidden')
    ns.db.skull = true; W.raidMarks.target = 8; W.advance(.2, FRAME)
    T.ok(not win:IsShown(), 'a real raid mark wins')
    W.raidMarks.target = nil; W.advance(.2, FRAME)
    T.ok(win:IsShown(), 'back')
    noErrors(T)
  end,
  ['a tick: the drop becomes a bite that glows and closes over 0.7 s'] = function(W, T)
    local ns, F, UI, M, DOTS = setup(W)
    DOTS[A] = { dot(W, 'Corruption', 47, 12) }
    W.advance(1, FRAME)
    DOTS[A][1].damage = 35
    W.advance(4 * FRAME, FRAME)
    T.ok(M.biteOf('Corruption'), 'a bite'); T.near(M.biteOf('Corruption').amt, 12, 1e-6, 'the size of the drop')
    T.ok(slot(M, 'Corruption').ghost:IsShown(), 'the bitten part is drawn')
    W.advance(1, FRAME)
    T.eq(M.biteOf('Corruption'), nil, 'closed'); T.ok(not slot(M, 'Corruption').ghost:IsShown())
    noErrors(T)
  end,
  ['a target switch wipes every bit of state from the last mob'] = function(W, T)
    local ns, F, UI, M, DOTS = setup(W)
    DOTS[A] = { dot(W, 'Corruption', 47, 12, { appliedAt = W.now }), dot(W, 'Immolate', 20, 15) }
    W.advance(1, FRAME)
    DOTS[A][1].damage = 35; W.advance(4 * FRAME, FRAME)
    W.fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-1', 172)
    T.ok(anyOf(M, 'bite') and M.snap().landed, 'state to wipe: a bite and a landed piece')
    local old = M.snap()
    DOTS[B] = { dot(W, 'Bane of Agony', 84, 24) }
    F.target(B)
    T.ok(M.snap() ~= old, 'a fresh snapshot')
    T.ok(not anyOf(M, 'bite'), 'bites'); T.ok(not anyOf(M, 'pred'), 'predictions'); T.eq(M.snap().landed, nil, 'landed piece')
    T.ok(not anyOf(M, 'shown'), 'sizes'); T.ok(not anyOf(M, 'wasPre'), 'precast looks'); T.ok(not anySlot(M), 'slots')
    T.eq(table.concat(M.snap().order, ','), 'Bane of Agony', 'only the new mob')
    W.advance(FRAME, FRAME)
    T.ok(rec(M, 'Bane of Agony').shown < 84 * .5, 'the new piece grows in from nothing')
    T.eq(slot(M, 'Corruption'), nil); T.eq(slot(M, 'Immolate'), nil)
    noErrors(T)
  end,

  -- 2026-11-13 'the mob target health was spilling over into the frame': the green is drawn through Blizzard's mask
  -- (BetterBlizzFrames' big health bar makes the bar's box taller than what shows); every piece uses the same mask
  ['spill: every piece, the shine and the empty bar are shaped by the green\'s own mask'] = function(W, T)
    local ns, F, UI, M, DOTS = setup(W)
    DOTS[A] = { dot(W, 'Corruption', 47, 12), dot(W, 'Immolate', 20, 15) }
    W.advance(1, FRAME)
    local P = ns.parts.doomed
    local hbMask = TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBarMask
    T.eq(#P.masks, 1, 'found the one mask on the green'); T.eq(P.masks[1], hbMask, "it is Blizzard's HealthBarMask")
    T.eq(P.barMask, nil, 'no box-shaped mask of our own')
    T.eq(P.margin, 0, 'no left margin: the mask is the shape (a margin left a red strip on BetterBlizzFrames)')
    local s = slot(M, 'Corruption')
    for _, k in ipairs({ 'base', 'lift', 'creaseL', 'creaseR', 'ghost', 'spillC', 'pre', 'cbase', 'clift', 'spark', 'wash', 'motes' }) do
      local ms = rawget(s[k], '_masks') or {}
      local has = false; for _, m in ipairs(ms) do if m == hbMask then has = true end end
      T.ok(has, k .. ' carries the green\'s mask')
    end
    for k = 1, 5 do T.ok((rawget(s.parts[k], '_masks') or {})[1] == hbMask, 'particle ' .. k .. ' carries it') end
    local function hasMask(t) for _, m in ipairs(rawget(t, '_masks') or {}) do if m == hbMask then return true end end end
    T.ok(hasMask(P.lost), 'the empty bar carries it')
    -- 'do you not see this gap?': a piece uses only the solid middle band of the bar art, top to bottom
    local tc = rawget(s.base, '_tc')
    T.ok(tc and tc[3] > 0 and tc[4] < 1, "the piece skips the art's faded top and bottom rows")
    T.near(tc[3], .2, 1e-9); T.near(tc[4], .8, 1e-9)
    noErrors(T)
  end,

  ['spill: a bar with no mask of its own still gets the bar\'s shape'] = function(W, T)
    local ns, F, UI = require('load').addon()
    -- strip Blizzard's mask: the fill now has none (another add-on's plain bar)
    local hb = TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
    rawset(hb:GetStatusBarTexture(), '_masks', nil)
    F.mob('nameplate1', A, 'Kobold', 100); F.target(A)
    local M = ns.model; local DOTS = { [A] = { dot(W, 'Corruption', 47, 12) } }
    M.source = function(u) local t = W.units[u]; return t and DOTS[t.guid] or {} end
    W.advance(1, FRAME)
    local P = ns.parts.doomed
    T.eq(#P.masks, 0, 'no mask on the green'); T.ok(P.barMask ~= nil, 'our own bar-shaped mask instead')
    T.ok(P.margin > 0, "Blizzard's bar without a mask keeps its 5 px left margin")
    T.eq((rawget(slot(M, 'Corruption').base, '_masks') or {})[1], P.barMask, 'the piece uses it')
    noErrors(T)
  end,

  ['spill: when the bar is resized after we are built, the pieces follow; a hidden size is skipped'] = function(W, T)
    local ns, F, UI, M, DOTS = setup(W)
    DOTS[A] = { dot(W, 'Corruption', 47, 12) }
    W.advance(1, FRAME)
    local P = ns.parts.doomed
    T.eq(P.base:GetWidth(), 124, 'built at the bar\'s width')
    local onSize = P.sizer.scripts.OnSizeChanged
    T.ok(type(onSize) == 'function', 'our own frame listens for the bar\'s size')
    onSize(P.sizer, 180, 30)
    T.eq(P.base:GetWidth(), 180, 'the health copy follows')
    for _, m in ipairs(P.marks) do T.eq(m.L:GetWidth(), 180); T.eq(m.R:GetWidth(), 180) end
    onSize(P.sizer, W.secret(90), 30)
    T.eq(P.base:GetWidth(), 180, 'a hidden width changes nothing')
    for _, m in ipairs(P.marks) do T.eq(m.L:GetWidth(), 180, 'marks keep the last real width') end
    noErrors(T)
  end,

  ['spill: a hidden bar width at build time is never handed to SetWidth'] = function(W, T)
    local ns, F, UI = require('load').addon()
    local hb = TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
    hb._w = W.secret(124)
    F.mob('nameplate1', A, 'Kobold', 100); F.target(A)
    local M = ns.model; local DOTS = { [A] = { dot(W, 'Corruption', 47, 12) } }
    M.source = function(u) local t = W.units[u]; return t and DOTS[t.guid] or {} end
    W.advance(1, FRAME)
    local P = ns.parts.doomed
    T.ok(P.base and type(P.base:GetWidth()) == 'number', 'a plain stand-in width')
    for _, m in ipairs(P.marks) do T.ok(not issecretvalue(m.L:GetWidth()), 'no mark got a hidden width') end
    T.ok(slot(M, 'Corruption') ~= nil, 'the piece still drew')
    noErrors(T)
  end,
}
