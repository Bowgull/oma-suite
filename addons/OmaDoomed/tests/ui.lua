-- A fake of WoW's UI objects, enough to load OmaDoomed's drawing files and watch what they draw.
--
-- UI.install()   frames, textures and font strings. Methods the fake knows remember what they were told (shown,
--                parent, colour, value, size, alpha, text...), so a test can read it back; any other method answers
--                with a harmless default (Get* -> 0, Is*/Has*/Can* -> false, Create* -> a new object, others -> nil).
--                Showing or hiding a frame fires OnShow/OnHide down its visible children, like the game.
--                Every widget call is counted (UI.calls) for the speed bench.
-- UI.plates()    a nameplate frame per nameplateN token (C_NamePlate.GetNamePlateForUnit), with Blizzard's
--                UnitFrame.HealthBarsContainer.healthBar and name.
-- UI.auras()     Blizzard's AuraContainer (CustomAuraContainerTemplate) and the client APIs the rings check for:
--                C_UnitAuras, C_CurveUtil, C_StringUtil, C_DurationUtil, C_CVar get/set and bitfields.
-- UI.settings()  Blizzard's Settings API, strict: a wrong call or a missing default raises, naming it.
local W = require('fakewow')
local UI = {}
local EMPTY = {}

-- ---------- counting widget calls ----------
UI.calls, UI.byName, UI.countNames = 0, {}, false
local function tally(k)
  UI.calls = UI.calls + 1
  if UI.countNames then UI.byName[k] = (UI.byName[k] or 0) + 1 end
end

-- ---------- parents, children, visibility ----------
local function isVisible(o)
  for _ = 1, 64 do
    if type(o) ~= 'table' then return true end
    if rawget(o, 'shown') == false then return false end
    o = rawget(o, '_parent')
  end
  return true
end
UI.isVisible = isVisible
local function fireVis(o, vis)
  local hook = rawget(o, '_onVis'); if hook then hook(o, vis) end      -- e.g. an aura container re-reading
  local s = rawget(o, 'scripts'); local fn = s and s[vis and 'OnShow' or 'OnHide']
  if fn then fn(o) end
  for _, k in ipairs(rawget(o, '_kids') or EMPTY) do if rawget(k, 'shown') ~= false then fireVis(k, vis) end end
end
local function setShown(o, v)
  v = v and true or false
  local before = isVisible(o)
  rawset(o, 'shown', v)
  local after = isVisible(o)
  if before ~= after then fireVis(o, after) end
end
local function link(o, p)   -- parent without firing anything (at creation)
  rawset(o, '_parent', p)
  if type(p) == 'table' then
    local ks = rawget(p, '_kids'); if not ks then ks = {}; rawset(p, '_kids', ks) end
    ks[#ks + 1] = o
  end
end
local function setParent(o, p)
  local old = rawget(o, '_parent'); if old == p then return end
  local before = isVisible(o)
  local ks = type(old) == 'table' and rawget(old, '_kids')
  if ks then for i, k in ipairs(ks) do if k == o then table.remove(ks, i) break end end end
  link(o, p)
  local after = isVisible(o)
  if before ~= after then fireVis(o, after) end
end
-- true when o sits somewhere under anc
function UI.under(o, anc)
  for _ = 1, 64 do
    o = type(o) == 'table' and rawget(o, '_parent') or nil
    if o == nil then return false end
    if o == anc then return true end
  end
  return false
end
function UI.kids(o) return rawget(o, '_kids') or {} end

-- ---------- what the known methods do ----------
local M = {}
local obj
function M.Show(self) setShown(self, true) end
function M.Hide(self) setShown(self, false) end
function M.SetShown(self, v) setShown(self, v) end
function M.IsShown(self) return rawget(self, 'shown') ~= false end
function M.IsVisible(self) return isVisible(self) end
function M.SetParent(self, p) setParent(self, p) end
function M.GetParent(self) return rawget(self, '_parent') end
function M.GetChildren(self) local ks = rawget(self, '_kids'); if ks then return unpack(ks) end end
function M.SetAlpha(self, a) rawset(self, '_alpha', a) end
function M.GetAlpha(self) return rawget(self, '_alpha') or 1 end
function M.SetScale(self, s) rawset(self, '_scale', s) end
function M.GetScale(self) return rawget(self, '_scale') or 1 end
function M.GetEffectiveScale() return 1 end
function M.SetVertexColor(self, r, g, b, a) rawset(self, '_r', r); rawset(self, '_g', g); rawset(self, '_b', b); rawset(self, '_a', a) end
function M.GetVertexColor(self) return rawget(self, '_r') or 1, rawget(self, '_g') or 1, rawget(self, '_b') or 1, rawget(self, '_a') or 1 end
M.SetStatusBarColor = M.SetVertexColor
function M.SetTextColor(self, r, g, b, a) rawset(self, '_tr', r); rawset(self, '_tg', g); rawset(self, '_tb', b); rawset(self, '_ta', a) end
function M.SetValue(self, v) rawset(self, '_value', v) end
function M.GetValue(self) return rawget(self, '_value') or 0 end
function M.SetMinMaxValues(self, lo, hi) rawset(self, '_min', lo); rawset(self, '_max', hi) end
function M.GetMinMaxValues(self) return rawget(self, '_min') or 0, rawget(self, '_max') or 1 end
function M.SetWidth(self, w) rawset(self, '_w', w) end
function M.SetHeight(self, h) rawset(self, '_h', h) end
function M.SetSize(self, w, h) rawset(self, '_w', w); rawset(self, '_h', h) end
function M.GetWidth(self) return rawget(self, '_w') or 0 end
function M.GetHeight(self) return rawget(self, '_h') or 0 end
function M.GetSize(self) return rawget(self, '_w') or 0, rawget(self, '_h') or 0 end
function M.SetFrameLevel(self, l) rawset(self, '_level', l) end
function M.GetFrameLevel(self) return rawget(self, '_level') or 0 end
function M.SetFrameStrata(self, s) rawset(self, '_strata', s) end
function M.GetFrameStrata(self) return rawget(self, '_strata') or 'MEDIUM' end
function M.SetPoint(self, _, rel) rawset(self, '_anchor', rel) end
function M.SetText(self, t) rawset(self, '_text', t) end
function M.GetText(self) return rawget(self, '_text') end
function M.SetTexture(self, t) rawset(self, '_texture', t) end
function M.SetFont(self, f) rawset(self, '_font', f); return true end   -- the game answers true when the font loads
function M.GetStatusBarTexture(self)
  local t = rawget(self, '_tex'); if not t then t = obj('Texture'); link(t, self); rawset(self, '_tex', t) end
  return t
end
function M.Play(self) rawset(self, '_plays', (rawget(self, '_plays') or 0) + 1); rawset(self, '_playing', true) end
function M.Stop(self) rawset(self, '_playing', false) end
function M.IsPlaying(self) return rawget(self, '_playing') or false end
function M.SetMaxDebuffs(self, n) rawset(self, '_maxDebuffs', n) end
function M.GetMaxDebuffs(self) return rawget(self, '_maxDebuffs') or 16 end
function M.SetMaxBuffs(self, n) rawset(self, '_maxBuffs', n) end
function M.GetMaxBuffs(self) return rawget(self, '_maxBuffs') or 32 end

-- One counting wrapper per method name, shared by every object.
local wrapped = {}
local function methodFor(k)
  local f = wrapped[k]; if f then return f end
  local impl = M[k]
  if not impl then
    if k:match('^Get') then impl = function() return 0 end
    elseif k:match('^Is') or k:match('^Has') or k:match('^Can') then impl = function() return false end
    elseif k:match('^Create') then impl = function(self) local o = obj(k:sub(7)); rawset(o, '_parent', self); return o end
    else impl = function() end end
  end
  f = function(...) tally(k); return impl(...) end
  wrapped[k] = f
  return f
end
local LOOSE = setmetatable({}, { __index = function(t, k)
  if type(k) ~= 'string' then return nil end
  local f = methodFor(k); rawset(t, k, f); return f
end })
local OBJMT = { __index = LOOSE }
obj = function(kind) return setmetatable({ kind = kind, events = {}, scripts = {}, shown = true }, OBJMT) end
UI.obj = obj

-- A colour, as CreateColor gives one (a ColorMixin table)
local function color(r, g, b, a) return { r = r, g = g, b = b, a = a or 1, GetRGBA = function(c) return c.r, c.g, c.b, c.a end, GetRGB = function(c) return c.r, c.g, c.b end } end

function UI.install()
  local realCreate = CreateFrame
  local FW = W.Frame
  -- frames: the UI methods for showing and parenting, then the fake's own (events, scripts), then the loose rest
  local FRAMEIDX = setmetatable({ Show = methodFor('Show'), Hide = methodFor('Hide'), SetShown = methodFor('SetShown'),
    IsShown = methodFor('IsShown'), GetParent = methodFor('GetParent'), SetParent = methodFor('SetParent') },
    { __index = function(t, k) local m = FW[k] or LOOSE[k]; rawset(t, k, m); return m end })
  UI.FRAMEMT = { __index = FRAMEIDX }
  UI.made = {}
  CreateFrame = function(kind, name, parent, template)
    tally('CreateFrame')
    local f = realCreate(kind, name, parent)
    setmetatable(f, kind == 'AuraContainer' and UI.CONTMT or UI.FRAMEMT)
    if parent ~= nil then link(f, parent) end
    if kind == 'AuraContainer' then UI.newContainer(f, template) end
    UI.made[#UI.made + 1] = f
    return f
  end
  UIParent = obj('UIParent'); WorldFrame = obj('WorldFrame')
  -- the target frame, as far as the add-on reaches into it (Blizzard_UnitFrame, Mainline TargetFrame)
  TargetFrame = obj('TargetFrame')
  local content, main = obj('TargetFrameContent'), obj('TargetFrameContentMain')
  local hbc, hb = obj('HealthBarsContainer'), obj('HealthBar')
  local ctx, container, portrait = obj('TargetFrameContentContextual'), obj('TargetFrameContainer'), obj('Portrait')
  link(content, TargetFrame); link(main, content); link(hbc, main); link(hb, hbc); link(ctx, content)
  link(container, TargetFrame); link(portrait, container)
  hb._w, hb._h = 124, 19
  TargetFrame.TargetFrameContent = content; content.TargetFrameContentMain = main; main.HealthBarsContainer = hbc
  hbc.HealthBar = hb; main.ManaBar = obj('ManaBar'); link(main.ManaBar, main)
  content.TargetFrameContentContextual = ctx; ctx.Auras = obj('TargetFrameAuras'); link(ctx.Auras, ctx)
  TargetFrame.TargetFrameContainer = container; container.Portrait = portrait
  TargetFrame.healthbar = hb
  C_Texture = { GetAtlasInfo = function() return { width = 1, height = 1, file = 'atlas', leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 } end }
  C_AddOns = { GetAddOnMetadata = function() return '0.0.0-test' end, IsAddOnLoaded = function() return false end }
  UnitClass = function() return 'Warlock', 'WARLOCK' end
  UnitCastingInfo = function() return nil end
  UnitChannelInfo = function() return nil end
  GetFramerate = function() return 60 end
  GetBuildInfo = function() return '1.60.1', '99999', 'Nov 1 2026', 16001 end
  GetPhysicalScreenSize = function() return 1920, 1080 end
  W.raidMarks = {}
  GetRaidTargetIndex = function(u) return W.raidMarks[u] end
  CreateColor = color
  Screenshot = function() end
  UISpecialFrames = {}
  ChatFontNormal = obj('font')
  MAX_TARGET_DEBUFFS, MAX_TARGET_BUFFS = 16, 32
  Enum = Enum or {}
  for k, v in pairs({ STANDARD_TEXT_FONT = 'Fonts\\FRIZQT__.TTF', DEFAULT_CHAT_FRAME = obj('chat') }) do _G[k] = v end
end

-- ---------- nameplates ----------
function UI.plates()
  UI.plate = {}
  local function plateFor(token)
    local p = UI.plate[token]
    if p then return p end
    p = obj('NamePlate'); p.namePlateUnitToken = token
    local uf, hbc, hb, name = obj('UnitFrame'), obj('HealthBarsContainer'), obj('HealthBar'), obj('FontString')
    link(uf, p); link(hbc, uf); link(hb, hbc); link(name, uf)
    hb._w, hb._h = 120, 10
    p.UnitFrame = uf; uf.HealthBarsContainer = hbc; hbc.healthBar = hb; uf.name = name
    UI.plate[token] = p
    return p
  end
  C_NamePlate = C_NamePlate or {}
  C_NamePlate.GetNamePlateForUnit = function(unit)
    local u = W.units[unit]; if not u then return nil end
    if unit:match('^nameplate%d+$') then return plateFor(unit) end
    for k, v in pairs(W.units) do if v == u and k:match('^nameplate%d+$') then return plateFor(k) end end
  end
end

-- ---------- Blizzard's AuraContainer ----------
-- Behaviour copied from Blizzard_AuraContainer (forever branch), as far as the rings use it:
--   * SetUnit does nothing for the same token; a new token re-reads every aura.
--   * UpdateAllAuras re-reads; so do SetAuraGroupEnabled and SetAuraGroupCandidateFilters.
--   * OnShow and OnHide re-read (and showing a parent shows its children, so they re-read too).
--   * AddAuraGroup builds FrameCreationBatchSize (10) buttons at once, whatever maxFrameCount says, and runs
--     initializeFrame on each.
--   * It listens for UNIT_AURA on its unit while it is visible.
-- What it shows comes from the unit table: W.units[token].auras = { spellID, ... } (yours),
-- .otherAuras = { spellID, ... } (other players'). A group shows one button per matching aura, up to its max.
local BATCH = 10
UI.aura = { containers = {}, buttons = 0 }
local C = {}
local function reread(c, why)
  local r = rawget(c, 'rereads'); r[why] = (r[why] or 0) + 1
  local u = c.unit and W.units[c.unit]
  for _, g in ipairs(c.groups) do
    local mine = g.filter:find('PLAYER', 1, true) and not g.filter:find('!PLAYER', 1, true)
    local list = u and g.enabled and (mine and u.auras or (not mine and u.otherAuras)) or EMPTY
    local f, n = g.filters or EMPTY, 0
    for _, id in ipairs(list) do
      local ok = true
      if f.includeSpellIDs and not f.includeSpellIDs[id] then ok = false end
      if f.excludeSpellIDs and f.excludeSpellIDs[id] then ok = false end
      if ok and n < g.max then n = n + 1; g.buttons[n].shown = true; g.buttons[n]._spell = id end
    end
    for i = n + 1, #g.buttons do g.buttons[i].shown = false; g.buttons[i]._spell = nil end
  end
end
-- How many times a container re-read its auras for a reason that takes effect (a new unit, an explicit
-- UpdateAllAuras, being shown).
function UI.reads(c) local r = c.rereads; return (r.SetUnit or 0) + (r.UpdateAllAuras or 0) + (r.OnShow or 0) end
-- What a container shows: group key -> list of spell IDs on shown buttons
function UI.showing(c)
  local out = {}
  for _, g in ipairs(c.groups) do
    local ids = {}; for _, b in ipairs(g.buttons) do if b.shown then ids[#ids + 1] = b._spell end end
    out[g.key] = ids
  end
  return out
end
function UI.group(c, key) return c.groupByKey[key] end
local function group(c, key)
  local g = c.groupByKey[key]
  if not g then error('AuraContainer: no aura group "' .. tostring(key) .. '"', 3) end
  return g
end
function C.SetUnit(self, unit)
  if unit ~= nil and type(unit) ~= 'string' then error('AuraContainer:SetUnit wants a unit token', 2) end
  if self.unit ~= unit then self.unit = unit; reread(self, 'SetUnit') end
end
function C.GetUnit(self) return self.unit end
function C.UpdateAllAuras(self) reread(self, 'UpdateAllAuras') end
function C.AddAuraGroup(self, key, filter, opts)
  if type(key) ~= 'string' or self.groupByKey[key] then error('AuraContainer:AddAuraGroup: bad or repeated key ' .. tostring(key), 2) end
  if type(filter) ~= 'string' then error('AuraContainer:AddAuraGroup: filter must be a string', 2) end
  if type(opts) ~= 'table' or type(opts.initializeFrame) ~= 'function' then error('AuraContainer:AddAuraGroup: needs initializeFrame', 2) end
  local g = { key = key, filter = filter, opts = opts, enabled = true, filters = opts.candidateFilters,
    max = math.min(opts.maxFrameCount or BATCH, BATCH), buttons = {} }
  for i = 1, BATCH do
    local b = obj('AuraButton'); b.shown = false; link(b, self)
    opts.initializeFrame(b)
    g.buttons[i] = b
  end
  self.built = self.built + BATCH; UI.aura.buttons = UI.aura.buttons + BATCH
  self.groups[#self.groups + 1] = g; self.groupByKey[key] = g
end
function C.SetAuraGroupEnabled(self, key, on) group(self, key).enabled = on and true or false; reread(self, 'SetAuraGroupEnabled') end
function C.SetAuraGroupCandidateFilters(self, key, filters)
  if type(filters) ~= 'table' then error('AuraContainer:SetAuraGroupCandidateFilters wants a table', 2) end
  group(self, key).filters = filters; reread(self, 'SetAuraGroupCandidateFilters')
end
function C.SetEditModePreviewEnabled(self, on) self.preview = on end
function C.SetFlowLayoutAnchorPoint(self, p) if type(p) ~= 'string' then error('SetFlowLayoutAnchorPoint wants a point', 2) end; self.flowPoint = p end
function C.SetFlowLayoutGrowthDirection(self, h, v) self.flowDir = { h, v } end
function C.SetFlowLayoutMaximumLineSize(self, n) if type(n) ~= 'number' then error('SetFlowLayoutMaximumLineSize wants a number', 2) end; self.lineSize = n end
local CONTIDX = setmetatable({}, { __index = function(t, k)
  local m = C[k] and function(...) tally(k); return C[k](...) end or UI.FRAMEMT.__index[k]
  rawset(t, k, m); return m
end })
UI.CONTMT = { __index = CONTIDX }
function UI.newContainer(f, template)
  if template ~= 'CustomAuraContainerTemplate' then error('AuraContainer needs the CustomAuraContainerTemplate template', 3) end
  f.groups, f.groupByKey, f.rereads, f.built = {}, {}, {}, 0
  f._onVis = function(c, vis) reread(c, vis and 'OnShow' or 'OnHide') end
  f:RegisterEvent('UNIT_AURA')
  f:SetScript('OnEvent', function(c, _, unit) if unit == c.unit and isVisible(c) then reread(c, 'UNIT_AURA') end end)
  UI.aura.containers[#UI.aura.containers + 1] = f
end
-- Row helpers: a "pair" is a ring container with its main container as a child
function UI.ringContainers()
  local out = {}
  for _, c in ipairs(UI.aura.containers) do
    for _, k in ipairs(UI.kids(c)) do if rawget(k, 'groups') then out[#out + 1] = c; break end end
  end
  return out
end
function UI.mainOf(ring) for _, k in ipairs(UI.kids(ring)) do if rawget(k, 'groups') then return k end end end
-- the ring container showing a row on this nameplate token's plate, or nil
function UI.rowOn(token)
  local plate = UI.plate and UI.plate[token]; if not plate then return nil end
  for _, c in ipairs(UI.ringContainers()) do if c.unit == token and UI.under(c, plate) then return c end end
end

function UI.auras()
  C_UnitAuras = {}
  -- numeric formatter: the breakpoint with the highest threshold at or under the number wins
  C_StringUtil = { CreateNumericRuleFormatter = function()
    local f = { rules = {} }
    function f:AddBreakpoint(r) if type(r) ~= 'table' or type(r.threshold) ~= 'number' then error('AddBreakpoint wants a rule', 2) end; self.rules[#self.rules + 1] = r end
    function f:FormatNumber(n)
      local best; for _, r in ipairs(self.rules) do if n >= r.threshold and (not best or r.threshold > best.threshold) then best = r end end
      if not best then return '' end
      if not best.format:find('%', 1, true) then return best.format end
      local div = best.components and best.components[1] and best.components[1].div or 1
      return best.format:format(math.ceil(n / div))
    end
    return f
  end }
  C_CurveUtil = { CreateColorCurve = function()
    local c = { pts = {} }
    function c:SetType(t) self.type = t end
    function c:AddPoint(x, col) self.pts[#self.pts + 1] = { x = x, c = col } end
    function c:Evaluate(x)
      local p = self.pts; if #p == 0 then return nil end
      if x <= p[1].x then return p[1].c end
      for i = 2, #p do
        if x <= p[i].x then
          local a, b = p[i - 1], p[i]; local k = (x - a.x) / (b.x - a.x)
          return color(a.c.r + (b.c.r - a.c.r) * k, a.c.g + (b.c.g - a.c.g) * k, a.c.b + (b.c.b - a.c.b) * k, a.c.a + (b.c.a - a.c.a) * k)
        end
      end
      return p[#p].c
    end
    return c
  end }
  C_DurationUtil = { CreateDurationTextBinding = function() local b = obj('DurationTextBinding'); return b end }
  -- CVars: strings, as the game stores them; bitfields read and write bit `bit` of the number
  W.cvars = W.cvars or {}
  for k, v in pairs({ nameplateEnemyNpcAuraDisplay = '7', nameplateEnemyPlayerAuraDisplay = '7', nameplateStyle = '0', nameplateDebuffPadding = '0' }) do
    if W.cvars[k] == nil then W.cvars[k] = v end
  end
  C_CVar = C_CVar or {}
  C_CVar.GetCVar = function(n) return W.cvars[n] end
  C_CVar.SetCVar = function(n, v) W.cvars[n] = tostring(v) end
  C_CVar.GetCVarBitfield = function(n, bit) local v = tonumber(W.cvars[n] or '0') or 0; return math.floor(v / 2 ^ bit) % 2 == 1 end
  C_CVar.SetCVarBitfield = function(n, bit, on)
    if InCombatLockdown() then error('SetCVarBitfield: secure CVar in combat', 2) end
    local v = tonumber(W.cvars[n] or '0') or 0; local has = math.floor(v / 2 ^ bit) % 2 == 1
    if on and not has then v = v + 2 ^ bit elseif not on and has then v = v - 2 ^ bit end
    W.cvars[n] = tostring(v)
  end
end

-- ---------- Blizzard's Settings API ----------
-- Strict: every call checks what Blizzard's own code relies on, so a broken Options page fails a test instead of
-- printing one line in game. UI.S keeps what was built: categories, settings (by variable), controls in order.
function UI.settings()
  local S = { categories = {}, settings = {}, controls = {}, opened = {}, addOnCategories = {} }
  UI.S = S
  local function bad(msg) error('Settings: ' .. msg, 3) end
  local VT = { Boolean = 'boolean', Number = 'number', String = 'string' }
  local isVT = { boolean = true, number = true, string = true }
  local function isCat(c) for _, x in ipairs(S.categories) do if x == c then return true end end; return false end
  local function category(name, parent)
    if type(name) ~= 'string' or name == '' then bad('a category needs a name') end
    local cat = { name = name, parent = parent, id = #S.categories + 1 }
    function cat:GetID() return self.id end
    function cat:GetName() return self.name end
    local layout = { inits = {}, category = cat }
    function layout:AddInitializer(init)
      if type(init) ~= 'table' or not init.kind then bad('AddInitializer wants an initializer') end
      self.inits[#self.inits + 1] = init
    end
    cat.layout = layout
    S.categories[#S.categories + 1] = cat
    return cat, layout
  end
  local function initializer(kind, fields)
    local init = fields or {}
    init.kind = kind
    function init:InitFrame(frame) self.frames = (self.frames or 0) + 1 end
    function init:SetParentInitializer(parent, pred)
      if type(parent) ~= 'table' or not parent.kind then bad('SetParentInitializer wants an initializer') end
      if pred ~= nil and type(pred) ~= 'function' then bad('SetParentInitializer: the predicate must be a function') end
      self.parentInit, self.pred = parent, pred
    end
    function init:GetSetting() return self.setting end
    return init
  end
  local function control(kind, want, cat, setting, tip)
    if not isCat(cat) then bad(kind .. ': not a registered category') end
    if type(setting) ~= 'table' or S.settings[setting.variable] ~= setting then bad(kind .. ': not a registered setting') end
    if setting.cat ~= cat then bad(kind .. ': setting ' .. setting.variable .. ' belongs to another category') end
    if setting.type ~= want then bad(kind .. ': setting ' .. setting.variable .. ' is ' .. setting.type .. ', not ' .. want) end
    if tip ~= nil and type(tip) ~= 'string' then bad(kind .. ': the tooltip must be a string') end
    local init = initializer(kind, { setting = setting, tooltip = tip })
    cat.layout:AddInitializer(init)
    S.controls[#S.controls + 1] = init
    return init
  end
  Settings = {
    VarType = VT,
    RegisterVerticalLayoutCategory = function(name) return category(name) end,
    RegisterVerticalLayoutSubcategory = function(parent, name)
      if not isCat(parent) then bad('RegisterVerticalLayoutSubcategory: the parent is not a category') end
      return category(name, parent)
    end,
    RegisterAddOnCategory = function(cat)
      if not isCat(cat) then bad('RegisterAddOnCategory: not a category') end
      S.addOnCategories[#S.addOnCategories + 1] = cat
    end,
    RegisterAddOnSetting = function(cat, variable, key, tbl, vartype, name, default)
      if not isCat(cat) then bad('RegisterAddOnSetting: not a category') end
      if type(variable) ~= 'string' or variable == '' then bad('RegisterAddOnSetting: the variable must be a string') end
      if S.settings[variable] then bad('RegisterAddOnSetting: ' .. variable .. ' is registered twice') end
      if type(key) ~= 'string' or type(tbl) ~= 'table' then bad('RegisterAddOnSetting: ' .. variable .. ' needs a key and a saved table') end
      if not isVT[vartype] then bad('RegisterAddOnSetting: ' .. variable .. ' has no valid Settings.VarType') end
      if type(name) ~= 'string' or name == '' then bad('RegisterAddOnSetting: ' .. variable .. ' needs a label') end
      if default == nil then bad('RegisterAddOnSetting: ' .. variable .. ' has no default') end
      if type(default) ~= vartype then bad('RegisterAddOnSetting: ' .. variable .. ' default is a ' .. type(default) .. ', not ' .. vartype) end
      if tbl[key] ~= nil and type(tbl[key]) ~= vartype then bad('RegisterAddOnSetting: saved ' .. key .. ' is a ' .. type(tbl[key])) end
      local s = { cat = cat, variable = variable, key = key, tbl = tbl, type = vartype, name = name, default = default, callbacks = {} }
      function s:GetValue() local v = self.tbl[self.key]; if v == nil then return self.default end; return v end
      function s:SetValue(v)
        if type(v) ~= self.type then error('Settings: ' .. self.variable .. ' set to a ' .. type(v), 2) end
        self.tbl[self.key] = v
        for _, cb in ipairs(self.callbacks) do cb(self, v) end
      end
      function s:GetDefaultValue() return self.default end
      function s:GetVariable() return self.variable end
      function s:GetName() return self.name end
      S.settings[variable] = s
      return s
    end,
    SetOnValueChangedCallback = function(variable, cb)
      if not S.settings[variable] then bad('SetOnValueChangedCallback: unknown setting ' .. tostring(variable)) end
      if type(cb) ~= 'function' then bad('SetOnValueChangedCallback wants a function') end
      table.insert(S.settings[variable].callbacks, cb)
    end,
    CreateCheckbox = function(cat, setting, tip) return control('checkbox', 'boolean', cat, setting, tip) end,
    CreateSliderOptions = function(lo, hi, step)
      if type(lo) ~= 'number' or type(hi) ~= 'number' or lo >= hi then bad('CreateSliderOptions wants min < max') end
      if step ~= nil and (type(step) ~= 'number' or step <= 0) then bad('CreateSliderOptions: bad step') end
      local o = { min = lo, max = hi, step = step }
      function o:SetLabelFormatter(where, fmt)
        if where == nil then bad('SetLabelFormatter: no label position') end
        if type(fmt) ~= 'function' then bad('SetLabelFormatter wants a function') end
        self.formatter = fmt
      end
      return o
    end,
    CreateSlider = function(cat, setting, opts, tip)
      local init = control('slider', 'number', cat, setting, tip)
      if type(opts) ~= 'table' or not opts.min then bad('CreateSlider: no slider options') end
      local d = setting.default
      if d < opts.min or d > opts.max then bad('CreateSlider: ' .. setting.variable .. ' default ' .. d .. ' is off the slider') end
      if opts.step and math.abs((d - opts.min) / opts.step - math.floor((d - opts.min) / opts.step + .5)) > 1e-9 then bad('CreateSlider: ' .. setting.variable .. ' default is between steps') end
      init.options = opts
      return init
    end,
    CreateDropdown = function(cat, setting, optionsFn, tip)
      local init = control('dropdown', setting and setting.type or '?', cat, setting, tip)
      if type(optionsFn) ~= 'function' then bad('CreateDropdown wants an options function') end
      local data = optionsFn()
      if type(data) ~= 'table' or #data == 0 then bad('CreateDropdown: ' .. setting.variable .. ' has no options') end
      local found = false
      for _, o in ipairs(data) do
        if type(o.label) ~= 'string' then bad('CreateDropdown: an option has no label') end
        if o.value == setting.default then found = true end
      end
      if not found then bad('CreateDropdown: ' .. setting.variable .. ' default ' .. tostring(setting.default) .. ' is not an option') end
      init.options = data
      return init
    end,
    CreateControlTextContainer = function()
      local c = { data = {} }
      function c:Add(value, label)
        if value == nil or type(label) ~= 'string' then bad('ControlTextContainer:Add wants a value and a label') end
        self.data[#self.data + 1] = { value = value, label = label, text = label }
      end
      function c:GetData() return self.data end
      return c
    end,
    CreateElementInitializer = function(template, data)
      if type(template) ~= 'string' then bad('CreateElementInitializer wants a template name') end
      return initializer('element', { template = template, data = data })
    end,
    OpenToCategory = function(id)
      if type(id) ~= 'number' then bad('OpenToCategory wants a category ID') end
      S.opened[#S.opened + 1] = id
    end,
  }
  Settings.CreateDropDown = nil   -- the old spelling is gone on Forever; the add-on must use CreateDropdown
  MinimalSliderWithSteppersMixin = { Label = { Left = 'Left', Right = 'Right', Top = 'Top', Min = 'Min', Max = 'Max' } }
  SettingsSliderControlMixin = { Init = function() end }
  CreateSettingsListSectionHeaderInitializer = function(text)
    if type(text) ~= 'string' then bad('a section header needs text') end
    return initializer('header', { text = text })
  end
  CreateSettingsButtonInitializer = function(name, buttonText, click, tip)
    if type(buttonText) ~= 'string' or type(click) ~= 'function' then bad('a button needs text and a click function') end
    return initializer('button', { name = name, buttonText = buttonText, click = click, tooltip = tip })
  end
end

return UI
