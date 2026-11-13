-- OmaDemon: shard trim TEST (2026-11-13, Joshua: "test the shard delete now"). Decided 2026-11-13: extra shards are
-- deleted when you open your bags, one per real open. Blizzard only lets DeleteCursorItem run inside a real key press
-- or click, so this checks whether Forever allows it from the bag-open hook before the feature is built.
-- /omademon shards deltest arms ONE delete: the next time you open your bags (out of combat), one Soul Shard is
-- deleted and the result is printed (count before and after, and any error). Nothing happens until it is armed.
local _, ns = ...
local ITEM = 6265
local armed = false

local function count()
  local ok, n = pcall(function() return (C_Item and C_Item.GetItemCount or GetItemCount)(ITEM) end)
  return ok and n or nil
end
local function findShard()
  local C = C_Container
  local slots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
  local itemID = (C and C.GetContainerItemID) or GetContainerItemID
  if not (slots and itemID) then return end
  for bag = 0, 4 do
    for slot = 1, (slots(bag) or 0) do
      if itemID(bag, slot) == ITEM then return bag, slot end
    end
  end
end

local function tryDelete(source)
  if not armed then return end
  armed = false
  if InCombatLockdown() then ns.say('delete test: in combat, skipped (arm it again out of combat)'); return end
  local before = count()
  local bag, slot = findShard()
  if not bag then ns.say('delete test: no Soul Shard in your bags'); return end
  local pick = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
  local okPick, ePick = pcall(pick, bag, slot)
  local okDel, eDel = pcall(DeleteCursorItem)
  if CursorHasItem and CursorHasItem() then ClearCursor() end      -- never leave a shard on the cursor
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

-- every way the bags open from a key press (Blizzard's and Bagnon's both go through these)
for _, fn in ipairs({ 'ToggleBackpack', 'ToggleAllBags', 'OpenAllBags', 'OpenBackpack' }) do
  if type(_G[fn]) == 'function' then hooksecurefunc(fn, function() tryDelete(fn) end) end
end

function ns.shardDelTest()
  if InCombatLockdown() then ns.say('not in combat'); return end
  local n = count() or 0
  if n < 1 then ns.say('delete test: you have no Soul Shards; get at least one first'); return end
  armed = true
  ns.say(('delete test armed: open your bags (B) and ONE Soul Shard will be deleted (you have %d)'):format(n))
end
