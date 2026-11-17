-- OmaDemon: what it says in chat (sheet 51, 2026-11-17). Chat style Plain keeps the old lines; Funny picks one line
-- from the list each time, never the same one twice in a row. Written in Joshua's voice: lowercase, no full stop.
-- ns.line(kind, ...) returns the line with the name (or shard count) filled in. kinds: stone, summon, stones, shards.
local _, ns = ...

local PLAIN = {
  stone  = 'Soulstone on %s.',
  summon = 'summoning %s, click the portal pls',
  stones = 'healthstones ready, grab one',
  shards = '%d soul shards, over your %d. Clear some bag space when you can.',
  trim   = 'Deleted an extra Soul Shard: %d left (keeping %d).',
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
  trim = {
    'yeeted a soul, %d left',
    'ate a shard, %d left',
    'one soul deleted, %d left. rip bozo',
    'shard gone, %d left. nobody will miss him',
  },
}
ns.lines = { plain = PLAIN, funny = FUNNY }

-- Asking for help (sheet 101 lines): click your debuff, the line names the groupmate who can remove it (class and
-- level, both plain), or says so cheekily when nobody can. Forever's dispel levels match Classic's (checked 2026-11-17).
local CAN = {
  curse = { { 'MAGE', 18 }, { 'DRUID', 24 } },
  poison = { { 'DRUID', 14 }, { 'SHAMAN', 16 }, { 'PALADIN', 8 } },
  magic = { { 'PRIEST', 18 }, { 'PALADIN', 42 } },
  disease = { { 'PRIEST', 14 }, { 'PALADIN', 8 }, { 'SHAMAN', 22 } },
}
local HELP = {
  magic = { 'magic debuff, %s dispel pls ^_^', 'magic debuff, no dispel here. pray for me T_T' },
  curse = { 'cursed, %s decurse pls <3', 'cursed, no decurse here. its fine T_T' },
  poison = { 'poisoned, %s cleanse pls :3', 'poisoned, no cleanse here. ill tough it out o7' },
  disease = { 'diseased, %s cure pls ^-^', 'diseased, no cure here. stay back lol >_<' },
}
ns.lines.help, ns.lines.can = HELP, CAN
function ns.helper(kind)
  local can = CAN[kind]; if not can then return end
  local units = {}
  if IsInRaid and IsInRaid() then for i = 1, 40 do units[#units + 1] = 'raid' .. i end else for i = 1, 4 do units[#units + 1] = 'party' .. i end end
  for _, u in ipairs(units) do
    local ok, name, cls, lv = pcall(function() local _, c = UnitClass(u); return UnitName(u), c, UnitLevel(u) end)
    if ok and name and not (UnitIsUnit and UnitIsUnit(u, 'player')) then
      for _, need in ipairs(can) do
        if cls == need[1] and type(lv) == 'number' and lv >= need[2] then
          local short = (Ambiguate and select(2, pcall(Ambiguate, name, 'short'))) or name
          return type(short) == 'string' and short or name
        end
      end
    end
  end
end
function ns.helpLine(kind)
  local h = HELP[kind]; if not h then return end
  local who = ns.helper(kind)
  return who and h[1]:format(who) or h[2]
end
function ns.askHelp(kind)
  if ns.groupDB().askHelp == false then return end
  local m = ns.helpLine(kind); if m and ns.groupSay then ns.groupSay(m, true) end
end

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
