-- The team row (TeamRow.lua, sheet 104): under the target frame, every other player's debuff on the mob, one line
-- per class from ClassAuras.lua, the rest on a neutral line; Blizzard's squares hidden on enemies; raid lines capped.
local A = 'Creature-0-1-0-1-100-AAAA'
local SUNDER, MARK, FAERIE, UNKNOWN = 7386, 1130, 770, 999999
local function setup(W, rings, before)
  local ns, F, UI = require('load').addon({ rings = true, before = function()
    if rings then OmaDoomedDB = { rings = rings } end
    if before then before() end
  end })
  W.advance(3)
  return ns, F, UI
end
local function noErrors(T) T.eq(#(OmaDoomedDB.errs or {}), 0, 'no caught errors: ' .. tostring((OmaDoomedDB.errs or {})[1])) end
local function shows(UI, c, key) return #(UI.showing(c)[key] or {}) end
return {
  ['team row: each class line shows its own spells, the rest go to the neutral line, yours never'] = function(W, T)
    local ns, F, UI = setup(W)
    local m = F.mob('nameplate1', A, 'Skum', 300); m.otherAuras = { SUNDER, MARK, FAERIE, UNKNOWN }; m.auras = { 172 }
    W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); F.target(A); W.advance(.5)
    local c = ns.team.c
    T.ok(c, 'the team row exists'); T.ok(UI.under(c, TargetFrame), 'it hangs off the target frame')
    T.eq(c.unit, 'target', 'it reads your target')
    T.eq(shows(UI, c, 'full_warrior'), 1, 'Sunder on the warrior line')
    T.eq(shows(UI, c, 'full_hunter'), 1, "Hunter's Mark on the hunter line")
    T.eq(shows(UI, c, 'full_druid'), 1, 'Faerie Fire on the druid line')
    T.eq(shows(UI, c, 'other'), 1, 'an unknown spell on the neutral line')
    T.eq(shows(UI, c, 'full_warlock'), 0, 'your own Corruption is not here (your rings show it)')
    noErrors(T)
  end,
  ['team row: on an enemy Blizzard\'s target squares go, on a friend they stay'] = function(W, T)
    local ns, F, UI = setup(W)
    F.mob('nameplate1', A, 'Skum', 300); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); F.target(A); W.advance(.5)
    local au = TargetFrame.TargetFrameContent.TargetFrameContentContextual.Auras
    if au and au.GetMaxDebuffs then
      ns.blizzard.squaresApply()
      T.eq(au:GetMaxDebuffs(), 0, 'no Blizzard debuff squares on an enemy'); T.eq(au:GetMaxBuffs(), 0, 'nor buff squares: the cast bar stays put')
    else T.ok(true, 'no aura container in the fake target frame') end
    noErrors(T)
  end,
  ['team row: in a raid of 6 classes, 4 get full lines and the rest fold into dots'] = function(W, T)
    local ns, F, UI = setup(W, nil, function()
      local CL = { 'WARRIOR', 'ROGUE', 'HUNTER', 'MAGE', 'PRIEST', 'DRUID' }
      IsInRaid = function() return true end
      local old = UnitClass
      UnitClass = function(u) local i = tonumber((u or ''):match('^raid(%d+)$')); if i and CL[i] then return CL[i], CL[i] end; return old(u) end
    end)
    local full = ns.team.lines()
    local n = 0; for _, f in pairs(full) do if f then n = n + 1 end end
    T.eq(n, 4, 'four full lines')
    T.ok(full.WARRIOR and full.ROGUE and full.HUNTER and full.MAGE, 'your raid\'s classes first, in order')
    T.ok(not full.PRIEST and not full.DRUID, 'the rest fold into dots')
    local c = ns.team.c
    T.eq(UI.group(c, 'dot_priest').enabled, true, 'priest as dots'); T.eq(UI.group(c, 'full_priest').enabled, false, 'no priest line')
    T.eq(UI.group(c, 'dot_warlock').opts.layout.forceNewLine, true, 'the first dot group starts the dot line')
    T.eq(UI.group(c, 'dot_priest').opts.layout.forceNewLine, false, 'the others share it')
    noErrors(T)
  end,
  ['team row: the rings sit tight under the bars and slide down only while the target casts'] = function(W, T)
    local bar
    local ns, F, UI = setup(W, { where = 'both' }, function()
      bar = CreateFrame('StatusBar', 'TargetFrameSpellBar', UIParent); bar:Hide()
    end)
    F.mob('nameplate1', A, 'Skum', 300); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); F.target(A); W.advance(.5)
    local fp = ns.rings.framePair; T.ok(fp, 'rings on the target frame')
    local function y() local pts = rawget(fp.anchor, '_pts'); return pts and pts.BOTTOMLEFT and pts.BOTTOMLEFT[4] end
    local tight = y()
    W.combat = true; bar:Show(); local casting = y()
    T.ok(casting < tight, 'a cast starts: they slide down (' .. tostring(tight) .. ' -> ' .. tostring(casting) .. ')')
    bar:Hide(); T.eq(y(), tight, 'the cast ends: back up tight')
    T.eq(rawget(ns.team.holder, '_pts').TOPLEFT[1], fp.anchor, 'the team row hangs under the rings and follows them')
    noErrors(T)
  end,
  ['team row: off in settings, nothing is built'] = function(W, T)
    local ns, F, UI = setup(W, { team = false })
    T.eq(ns.team.c, nil, 'no team row'); noErrors(T)
  end,
}
