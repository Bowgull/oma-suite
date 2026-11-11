-- OmaDemon's saved settings: OmaDemonDB = { glow = {...}, shards = {...} }.
-- WoW fills OmaDemonDB in after the files run, so everything reads it through ns.glowDB() / ns.shardsDB().
-- Until OmaCore exists this add-on keeps its own settings (decided 2026-11-11); later they move into OmaCore.
local _, ns = ...
local function db()
  OmaDemonDB = OmaDemonDB or {}
  OmaDemonDB.glow = OmaDemonDB.glow or {}
  OmaDemonDB.shards = OmaDemonDB.shards or {}
  return OmaDemonDB
end
function ns.glowDB() return db().glow end
function ns.shardsDB() return db().shards end
function ns.say(m) print('|cffc08cffOmaDemon:|r ' .. m) end

-- One slash command for both halves: /omademon test | motion on|off | shards ...
SLASH_OMADEMON1 = '/omademon'
SlashCmdList.OMADEMON = function(msg)
  msg = msg or ''
  local cmd, rest = msg:match('^(%S*)%s*(.-)$'); cmd = cmd:lower()
  if cmd == 'shards' then return ns.shardsSlash and ns.shardsSlash(rest) end
  if cmd == 'motion' then
    local off = rest:lower() == 'off'
    ns.glowDB().reduced = off; ns.shardsDB().reduced = off
    if ns.glowMotion then ns.glowMotion() end
    return ns.say('motion ' .. (off and 'reduced (steady glow)' or 'full'))
  end
  if ns.glowSlash then return ns.glowSlash(msg) end
end
