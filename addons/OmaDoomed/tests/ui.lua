-- A loose fake of WoW's UI objects, enough to load OmaDoomed's drawing files and run its start-up. Any method a
-- frame or texture doesn't have answers with a harmless default (Get* -> 0, Is*/Has* -> false, others -> nil),
-- so this checks wiring (files load, start-up runs, globals exist), not looks.
local W = require('fakewow')
local UI = {}
local function obj(kind)
  local o = { kind = kind, events = {}, scripts = {}, shown = true, children = {} }
  return setmetatable(o, { __index = function(t, k)
    if type(k) ~= 'string' then return nil end
    local f
    if k:match('^Get') then f = function() return 0 end
    elseif k:match('^Is') or k:match('^Has') or k:match('^Can') then f = function() return false end
    elseif k:match('^Create') then f = function(self) return obj(k) end
    else f = function() end end
    rawset(t, k, f); return f
  end })
end
UI.obj = obj
function UI.install()
  local realCreate = CreateFrame
  CreateFrame = function(kind, name, parent, template)
    local f = realCreate(kind, name, parent)   -- keeps events and scripts working
    local loose = obj(kind)
    setmetatable(f, { __index = function(t, k) local m = getmetatable(f).__fw[k]; if m then return m end; return loose[k] end, __fw = getmetatable(f).__index })
    return f
  end
  UIParent = obj('UIParent'); WorldFrame = obj('WorldFrame')
  TargetFrame = obj('TargetFrame'); TargetFrame.TargetFrameContent = obj('c'); TargetFrame.healthbar = obj('hb')
  C_Texture = { GetAtlasInfo = function() return { width = 1, height = 1 } end }
  C_AddOns = { GetAddOnMetadata = function() return '0.0.0-test' end }
  UnitClass = function() return 'Warlock', 'WARLOCK' end
  UnitCastingInfo = function() return nil end
  UnitChannelInfo = function() return nil end
  GetFramerate = function() return 60 end
  GetBuildInfo = function() return '1.60.1', '99999', 'Nov 1 2026', 16001 end
  Screenshot = function() end
  UISpecialFrames = {}
  ChatFontNormal = obj('font')
  Enum = Enum or {}
  for k, v in pairs({ STANDARD_TEXT_FONT = 'Fonts\\FRIZQT__.TTF', DEFAULT_CHAT_FRAME = obj('chat') }) do _G[k] = v end
end
return UI
