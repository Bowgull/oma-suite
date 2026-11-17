-- OmaDemon: what it says in chat (sheet 51, 2026-11-17). Chat style Plain keeps the old lines; Funny picks one line
-- from the list each time, never the same one twice in a row. Written in Joshua's voice: lowercase, no full stop.
-- ns.line(kind, ...) returns the line with the name (or shard count) filled in. kinds: stone, summon, stones, shards.
local _, ns = ...

local PLAIN = {
  stone  = 'Soulstone on %s.',
  summon = 'summoning %s, click the portal pls',
  stones = 'healthstones ready, grab one',
  shards = '%d soul shards, over your %d. Clear some bag space when you can.',
}

local FUNNY = {
  stone = {
    'ss on %s, ur wipe insurance now',
    '%s got the ss, dont fumble it',
    'ss on %s, if we wipe its ur fault now',
    'ss on %s, if u still die thats a skill issue',
    'ss on %s, extra life unlocked',
    'ss on %s, checkpoint saved',
  },
  summon = {
    'lock taxi for %s, need 2 clicks pls',
    'summoning %s, only sigmas click the portal',
    '%s cant walk apparently, 2 clicks pls',
    'summoning %s, 2 clicks or we never leave',
    'summoning %s, 2 clicks pls, no tipping required',
  },
  stones = {
    'cookies are out, grab one',
    'free cookies, made from real souls, still bussin',
    'cookies up, if u die with one in ur bags thats on u',
    'cookies are out, the healer is begging u',
    'cookies are out, free heal no mana needed',
  },
  shards = {
    '%d souls in ur bags, thats a crowd. delete a few',
    'bro %d shards, ur a soul hoarder',
    '%d shards, thats a lot of dead ppl in ur bags',
    '%d shards, ur bags are cooked. delete some',
  },
}
ns.lines = { plain = PLAIN, funny = FUNNY }

local lastPick = {}
function ns.line(kind, ...)
  local style = ns.groupDB and ns.groupDB().chatStyle
  local list = style == 'funny' and FUNNY[kind]
  local fmt
  if list and #list > 0 then
    local i = math.random(#list)
    if #list > 1 and i == lastPick[kind] then i = i % #list + 1 end   -- never twice in a row
    lastPick[kind] = i
    fmt = list[i]
  else
    fmt = PLAIN[kind]
  end
  local ok, msg = pcall(string.format, fmt, ...)
  return ok and msg or fmt
end
