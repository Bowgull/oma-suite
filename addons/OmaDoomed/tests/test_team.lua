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
  ['team row: the squares take the mouse (the game shows their tooltip); the class dots do not'] = function(W, T)
    local ns, F, UI = setup(W)
    F.mob('nameplate1', A, 'Skum', 300); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); F.target(A); W.advance(.5)
    local c = ns.team.c
    T.ok(UI.group(c, 'full_warrior').buttons[1]:IsMouseEnabled(), 'a class square takes the mouse')
    T.ok(UI.group(c, 'other').buttons[1]:IsMouseEnabled(), 'the neutral line too')
    T.ok(not UI.group(c, 'dot_warrior').buttons[1]:IsMouseEnabled(), 'a small class dot stays click-through')
    noErrors(T)
  end,
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
  ['team row: the slide works even when the client never passes the cast bar\'s OnShow (21:07 screenshot)'] = function(W, T)
    local bar
    local ns, F, UI = setup(W, { where = 'both' }, function()
      bar = CreateFrame('StatusBar', 'TargetFrameSpellBar', UIParent); bar:Hide()
      bar.HookScript = function(_, what) error("Button:HookScript(): Cannot assign script handler for '" .. tostring(what):lower() .. "' (blocked)", 2) end
    end)
    F.mob('nameplate1', A, 'Skum', 300); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); F.target(A); W.advance(.5)
    local fp = ns.rings.framePair; T.ok(fp, 'rings on the target frame')
    local function y() local pts = rawget(fp.anchor, '_pts'); return pts and pts.BOTTOMLEFT and pts.BOTTOMLEFT[4] end
    local tight = y()
    W.combat = true; bar:Show(); W.advance(.15)
    T.ok(y() < tight, 'the watch sees the cast bar and slides the rings down')
    bar:Hide(); W.advance(.15)
    T.eq(y(), tight, 'and back up when it goes')
    noErrors(T)
  end,
  ['team row: the slide works when the cast bar\'s state is secret, from the target\'s own cast (2026-11-19)'] = function(W, T)
    local bar
    local ns, F, UI = setup(W, { where = 'both' }, function()
      bar = CreateFrame('StatusBar', 'TargetFrameSpellBar', UIParent); bar:Hide()
      bar.IsVisible = function() return W.secret(true) end   -- Forever: the bar's shown state is secret in a fight
    end)
    F.mob('nameplate1', A, 'Skum', 300); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); F.target(A); W.advance(.5)
    local fp = ns.rings.framePair; T.ok(fp, 'rings on the target frame')
    local function y() local pts = rawget(fp.anchor, '_pts'); return pts and pts.BOTTOMLEFT and pts.BOTTOMLEFT[4] end
    local tight = y()
    local casting = false
    UnitCastingInfo = function(u) if u == 'target' and casting then return W.secret('Healing Touch') end end
    UnitChannelInfo = function() return nil end
    W.combat = true; casting = true; W.advance(.15)
    T.ok(y() < tight, 'the target casts (a secret name): the rings slide down')
    T.eq(rawget(ns.team.holder, '_pts').TOPLEFT[1], fp.anchor, 'the team row follows them')
    casting = false; W.advance(.15)
    T.eq(y(), tight, 'the cast ends: back up tight')
    noErrors(T)
  end,
  -- 2026-11-24 screenshots: BetterBlizzFrames had already moved the cast bar below the rings; sliding them too put
  -- them under it. Where the bar really is decides (edges in screen px; the row is S + gap tall, here 45 px at scale 1).
  ['team row: a cast bar another add-on already moved below the rings leaves them tight'] = function(W, T)
    local bar
    local ns, F, UI = setup(W, { where = 'both' }, function()
      bar = CreateFrame('StatusBar', 'TargetFrameSpellBar', UIParent); bar:Hide()
    end)
    F.mob('nameplate1', A, 'Skum', 300); W.fire('NAME_PLATE_UNIT_ADDED', 'nameplate1'); F.target(A); W.advance(.5)
    local fp = ns.rings.framePair; T.ok(fp, 'rings on the target frame')
    local main = TargetFrame.TargetFrameContent.TargetFrameContentMain
    local low = main.ManaBar or main.HealthBarsContainer.HealthBar
    rawset(low, 'GetBottom', function() return 928 end)
    local barTop = 875
    rawset(bar, 'GetTop', function() return barTop end)
    local function y() local pts = rawget(fp.anchor, '_pts'); return pts and pts.BOTTOMLEFT and pts.BOTTOMLEFT[4] end
    local tight = y()
    W.combat = true; bar:Show()
    T.eq(y(), tight, 'the bar sits 53 px down, under the 45 px row: the rings stay tight')
    barTop = 918; bar:SetPoint('TOP', TargetFrame, 'BOTTOM', 0, -10)
    T.ok(y() < tight, 'the bar moved up into the row: now they slide')
    barTop = 875; bar:SetPoint('TOP', TargetFrame, 'BOTTOM', 0, -53)
    T.eq(y(), tight, 'and back up when it moves away')
    rawset(bar, 'GetTop', function() return W.secret(900) end); bar:Hide(); bar:Show()
    T.ok(y() < tight, 'a hidden position: the old slide stands')
    bar:Hide(); T.eq(y(), tight, 'the cast ends: tight')
    noErrors(T)
  end,
  ['team row: off in settings, nothing is built'] = function(W, T)
    local ns, F, UI = setup(W, { team = false })
    T.eq(ns.team.c, nil, 'no team row'); noErrors(T)
  end,
}
