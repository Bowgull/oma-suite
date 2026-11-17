-- OmaDemon: extra Soul Shards are deleted when you open your bags (decided 2026-11-13; Forever allows it, tested
-- 2026-11-17: 4 -> 3 and 3 -> 2). Blizzard only lets DeleteCursorItem run inside a real key press or click, so the
-- bag-open is the press: each open deletes ONE shard while you carry more than "Shards to keep", never in a fight,
-- never while something is on your cursor, then one line in chat. Switch: Extra Shards > Delete extras on bag open.
-- /omademon shards deltest still arms ONE delete regardless of the limit (the Forever check), and prints the result.
local _, ns = ...
local ITEM = 6265
local armed = false
local lastAt = -math.huge     -- several bag hooks fire for one press: only the first one counts

local function count()
  local ok, n = pcall(function() return (C_Item and C_Item.GetItemCount or GetItemCount)(ITEM) end)
  return ok and n or nil
end
local function findShard()
  local C = C_Container
  local slots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
  local itemID = (C and C.GetContainerItemID) or GetContainerItemID
  if not (slots and itemID) then return end
  local fb, fs
  for bag = 0, 4 do
    for slot = 1, (slots(bag) or 0) do
      if itemID(bag, slot) == ITEM then fb, fs = bag, slot end   -- the last one found: the newest, at the back
    end
  end
  return fb, fs
end
local function cursorBusy() local ok, v = pcall(function() return CursorHasItem and CursorHasItem() end); return ok and v end

-- one shard off: pick it up and delete it; never leaves anything on the cursor. Returns okPick, okDel, errPick, errDel
local function deleteOne()
  local bag, slot = findShard()
  if not bag then return nil end
  local pick = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
  local okPick, ePick = pcall(pick, bag, slot)
  local okDel, eDel = pcall(DeleteCursorItem)
  if cursorBusy() then pcall(ClearCursor) end
  return okPick, okDel, ePick, eDel
end

local function trim(source)
  local db = ns.shardsDB()
  if db.trim == false or InCombatLockdown() or cursorBusy() then return end
  local keep, before = db.keep or 6, count()
  if not before or before <= keep then return end
  local okPick, okDel = deleteOne()
  if not (okPick and okDel) then return end
  C_Timer.After(.3, function()
    local after = count()
    if after and after < before and db.chat ~= false then ns.say(ns.line('trim', after, keep)) end
  end)
end

local function test(source)
  armed = false
  if InCombatLockdown() then ns.say('delete test: in combat, skipped (arm it again out of combat)'); return end
  local before = count()
  if not findShard() then ns.say('delete test: no Soul Shard in your bags'); return end
  local okPick, okDel, ePick, eDel = deleteOne()
  C_Timer.After(.5, function()
    local after = count()
    local deleted = before and after and after < before
    ns.say(('delete test from %s: pick %s, delete %s, shards %s -> %s: %s'):format(source,
      okPick and 'ok' or ('error ' .. tostring(ePick)), okDel and 'ok' or ('error ' .. tostring(eDel)),
      tostring(before), tostring(after), deleted and 'FOREVER ALLOWS IT' or 'NOT deleted (blocked)'))
    local db = ns.shardsDB(); db.deltest = { at = date('%Y-%m-%d %H:%M'), source = source, before = before, after = after,
      pick = okPick and 'ok' or tostring(ePick), del = okDel and 'ok' or tostring(eDel), deleted = deleted and true or false }
  end)
end

local function onOpen(source)
  local now = GetTime()
  if now - lastAt < .5 then return end
  lastAt = now
  if armed then test(source) else trim(source) end
end

-- every way the bags open from a key press (Blizzard's and Bagnon's both go through these)
for _, fn in ipairs({ 'ToggleBackpack', 'ToggleAllBags', 'OpenAllBags', 'OpenBackpack' }) do
  if type(_G[fn]) == 'function' then hooksecurefunc(fn, function() onOpen(fn) end) end
end

function ns.shardDelTest()
  if InCombatLockdown() then ns.say('not in combat'); return end
  local n = count() or 0
  if n < 1 then ns.say('delete test: you have no Soul Shards; get at least one first'); return end
  armed = true
  ns.say(('delete test armed: open your bags (B) and ONE Soul Shard will be deleted (you have %d)'):format(n))
end
