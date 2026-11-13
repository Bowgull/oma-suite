#!/usr/bin/env python3
"""Builds OmaDoomed's DoT tracking (Track/) from DoesItDie's engine (tools/upstream/), MIT (see Track/LICENSE-DoesItDie).

Run from the OmaDoomed folder:  python3 -I tools/import_doesitdie.py
Safe to run again: it rewrites Track/Engine.lua and Track/Locale*.lua from upstream every time.

To take a newer DoesItDie: copy its DoesItDie.lua, Locale*.lua, LICENSE into tools/upstream/, run this, then
`luajit tests/run.lua`. Each edit below names what it changes; if an anchor no longer matches, the script stops and
says which one, so a changed upstream is never patched blindly.

The engine is kept almost verbatim (warlock-only by a gate, not by deleting other classes' code) so upstream fixes
diff cleanly. Every edit is marked "-- OMA" in the output.
"""
import os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
UP = os.path.join(HERE, 'upstream')
OUT = os.path.join(HERE, '..', 'Track')

def edit(text, old, new, what):
    n = text.count(old)
    if n != 1:
        sys.exit(f'import_doesitdie: anchor for "{what}" found {n} times (expected 1). Upstream changed: check it by hand.')
    return text.replace(old, new)

NS_LINE_LOCALE = 'local _, ns = ...'
NS_SHIM = 'local _, OMA = ... -- OMA: DoesItDie\'s namespace lives in OMA.track, apart from OmaDoomed\'s (Track/Shim.lua)\nlocal ns = OMA.track'

def locale_files():
    for f in sorted(os.listdir(UP)):
        if f.startswith('Locale') and f.endswith('.lua'):
            src = open(os.path.join(UP, f), encoding='utf-8').read()
            src = edit(src, NS_LINE_LOCALE, NS_SHIM, f + ': namespace')
            if f == 'Locale.lua':
                # Immolate was missing, so no client in another language ever tracked it.
                src = edit(src, '    ["Serpent Sting"] = 1978, ["Pyroblast"] = 11366, ["Corruption"] = 172,\n}\n',
                    '    ["Serpent Sting"] = 1978, ["Pyroblast"] = 11366, ["Corruption"] = 172,\n}\n'
                    'L.SPELL_IDS["Immolate"] = 348 -- OMA: missing upstream, so other languages never tracked it\n',
                    'Locale.lua: Immolate id')
            open(os.path.join(OUT, f), 'w', encoding='utf-8').write(src)

def engine():
    s = open(os.path.join(UP, 'DoesItDie.lua'), encoding='utf-8').read()
    s = edit(s, '-- DoesItDie\n-- Tracks your DoTs',
        '-- OMA: OmaDoomed\'s DoT tracking, built from DoesItDie v0.9.4 by Joe Greive (MIT, see Track/LICENSE-DoesItDie)\n'
        '-- by tools/import_doesitdie.py. Do not edit by hand: change the script. Every change is marked OMA.\n'
        '--\n-- DoesItDie\n-- Tracks your DoTs', 'header')
    s = edit(s, 'local ADDON_NAME, ns = ... -- ns is shared with Options.lua',
        'local ADDON_NAME, OMA = ... -- OMA: DoesItDie\'s namespace lives in OMA.track (Track/Shim.lua)\nlocal ns = OMA.track',
        'namespace')
    # Warlock only: other classes' DoTs are never tracked (their code stays, inert, for clean upstream diffs).
    s = edit(s, 'local NAME_TABLES = { KNOWN_TICK_INTERVALS, TICK_SHAPES, SCHOOL_BY_NAME, IGNORED_SPELLS, PROJECTILE_DOTS, TRAP_DOTS }',
        '-- OMA: the only DoTs OmaDoomed tracks (warlock). Other names are ignored before any parsing.\n'
        'local OMA_TRACKED = { ["Corruption"] = true, ["Curse of Agony"] = true, ["Bane of Agony"] = true,\n'
        '    ["Immolate"] = true, ["Siphon Life"] = true }\n'
        '-- OMA: Wrack (Forever warlock channel, 1316697) speeds up other DoTs; it is not a DoT itself.\n'
        'IGNORED_SPELLS["Wrack"] = true\n'
        'local NAME_TABLES = { KNOWN_TICK_INTERVALS, TICK_SHAPES, SCHOOL_BY_NAME, IGNORED_SPELLS, PROJECTILE_DOTS, TRAP_DOTS, OMA_TRACKED }\n'
        '-- OMA: by spell ID first (OmaDoomed\'s Spells.lua, every rank), so any client language counts; else by name\n'
        'local function omaTracked(name, spellID)\n'
        '    local sp = OMA.spells and OMA.spells.ofID(spellID)\n'
        '    if sp then return sp.kind == "dot" end\n'
        '    return OMA_TRACKED[name] == true\n'
        'end',
        'warlock gate table')
    s = edit(s, '    if IGNORED_SPELLS[name] then return end\n    local isFinisher',
        '    if IGNORED_SPELLS[name] or not omaTracked(name, spellID) then return end -- OMA: warlock DoTs only\n    local isFinisher',
        'warlock gate on cast')
    s = edit(s, 'if not ok or not name or isSecret(name) or IGNORED_SPELLS[name] or isFinisherDescription(desc) then return end',
        'if not ok or not name or isSecret(name) or IGNORED_SPELLS[name] or not omaTracked(name, spellID) or isFinisherDescription(desc) then return end -- OMA: warlock only',
        'warlock gate on cast start')
    s = edit(s, 'DEFAULT_CHAT_FRAME:AddMessage("|cffff6666DoesItDie|r " .. msg)',
        'DEFAULT_CHAT_FRAME:AddMessage("|cffb48cffOmaDoomed:|r " .. msg) -- OMA', 'chat prefix')
    # Saved data: OmaDoomedDB.track. Standalone: nothing is read from DoesItDie's saved data. Other classes: off.
    s = edit(s, '        DoesItDieDB = DoesItDieDB or {}\n        db = DoesItDieDB\n',
        '        -- OMA: warlocks only (Core.lua also switches every tracking frame off for other classes)\n'
        '        if OMA.isWarlock and not OMA.isWarlock() then self:UnregisterAllEvents(); return end\n'
        '        -- OMA: saved in OmaDoomedDB.track (standalone: nothing is taken from DoesItDie)\n'
        '        OmaDoomedDB = OmaDoomedDB or {}\n'
        '        if type(OmaDoomedDB.track) ~= "table" then OmaDoomedDB.track = {} end\n'
        '        db = OmaDoomedDB.track\n', 'saved variables')
    # The trace log costs a string and a 500-line shift per unmatched hit: off unless asked for (/omadoomed trace on).
    s = edit(s, 'local function trace(msg)\n    if not db then return end\n',
        'local function trace(msg)\n    if not db or not (db.omaTrace or db.debug) then return end -- OMA: off unless asked for\n',
        'trace off by default')
    # UNIT_COMBAT fires for party and raid members, the player and pets too: none carry your DoTs.
    s = edit(s, 'local function onUnitCombat(unit, action, flag, amount, school)\n    if isSecret(action) then return end\n',
        '-- OMA: only the units a mob of yours can be seen on\n'
        'local OMA_UNITS = { target = true, focus = true, softenemy = true, mouseover = true }\n'
        'local function omaWatched(unit)\n'
        '    return type(unit) == "string" and not isSecret(unit) and (OMA_UNITS[unit] or unit:sub(1, 9) == "nameplate")\n'
        'end\n'
        'ns.omaWatched = omaWatched\n'
        'local function onUnitCombat(unit, action, flag, amount, school)\n'
        '    if not omaWatched(unit) then return end -- OMA\n'
        '    if isSecret(action) then return end\n',
        'watched units only')
    # A DoT that ticked and then misses two ticks in a row is gone: a decurse, the mob resetting, Conflagrate eating
    # Immolate, Bane of Doom/Havoc replacing Agony... (DoesItDie only drops DoTs that never ticked.)
    s = edit(s, '                if dot.ticksSeen == 0 and isObservable(key) then dot.missed = dot.missed + 1 end',
        '                if isObservable(key) then dot.missed = dot.missed + 1 end -- OMA: misses after ticking count too',
        'count misses after ticking')
    s = edit(s, '            elseif dot.ticksSeen == 0 and dot.missed >= MISSED_TICKS_BEFORE_DROP then\n                dots[name] = nil\n                trace("DROP " .. name .. " never ticked (resisted or immune?)")',
        '            elseif dot.missed >= MISSED_TICKS_BEFORE_DROP then -- OMA: also after ticking\n                dots[name] = nil\n'
        '                trace("DROP " .. name .. (dot.ticksSeen == 0 and " never ticked (resisted or immune?)" or " stopped ticking (dispelled, replaced or mob reset?)"))',
        'drop after missed ticks')
    # The first guess for a rank never fought with: the tooltip times what this spell really did on other ranks
    # (gear and spell power), instead of the bare tooltip. And a per-DoT scale for known buffs (Amplify Curse).
    s = edit(s, '    return dot.learnedAtApply or (dot.tickKey and db.ticks[dot.tickKey]) or (dot.total / dot.totalTicks)',
        '    return (dot.learnedAtApply or (dot.tickKey and db.ticks[dot.tickKey]) or dot.omaGuess or (dot.total / dot.totalTicks))\n'
        '        * (dot.omaScale or 1) -- OMA: guess from other ranks; known buffs',
        'expected tick: guess and scale')
    s = edit(s, '        learnedAtApply = tickKey and db.ticks[tickKey] or nil,\n',
        '        learnedAtApply = tickKey and db.ticks[tickKey] or nil,\n'
        '        -- OMA: no size learned for this rank yet: the tooltip times how much harder this spell really hit on ranks fought with\n'
        '        omaGuess = not (tickKey and db.ticks[tickKey]) and db.omaRatio and db.omaRatio[name] and total\n'
        '            and total / math.max(1, math.floor(duration / (statedInterval or KNOWN_TICK_INTERVALS[name] or DEFAULT_TICK_INTERVAL) + 0.5))\n'
        '            * db.omaRatio[name] or nil,\n',
        'new dot guess')
    s = edit(s, '        db.ticks[dot.tickKey] = math.floor(dot.tickSum / dot.normalTicks * 10 + 0.5) / 10\n',
        '        db.ticks[dot.tickKey] = math.floor(dot.tickSum / dot.normalTicks * 10 + 0.5) / 10\n'
        '        if dot.name and dot.total and dot.totalTicks and dot.total > 0 then -- OMA: how much harder than its tooltip\n'
        '            db.omaRatio = db.omaRatio or {}\n'
        '            db.omaRatio[dot.name] = db.ticks[dot.tickKey] / (dot.total / dot.totalTicks)\n'
        '        end\n',
        'ratio from readable ticks')
    s = edit(s, '                db.tickWeights[key] = weight + t.factors\n',
        '                db.tickWeights[key] = weight + t.factors\n'
        '                if t.name and t.descTick and t.descTick > 0 then -- OMA: how much harder than its tooltip\n'
        '                    db.omaRatio = db.omaRatio or {}\n'
        '                    db.omaRatio[t.name] = db.ticks[key] / t.descTick\n'
        '                end\n',
        'ratio from the meter')
    # Timed boosts (Curse of the Elements on a mob, Shadow and Flame after Conflagrate...) only count for the ticks
    # that land while they last: remaining damage is summed tick by tick with OmaDoomed's multiplier (Track/Forever.lua).
    s = edit(s, """local function remainingDamage(dot)
    if dot.nextTickAt > dot.expiresAt + dot.interval / 2 then return 0 end
    local ticksLeft = math.floor((dot.expiresAt - dot.nextTickAt) / dot.interval + 0.5) + 1
    if not dot.shape then return ticksLeft * expectedTick(dot) end
    local average, total = expectedTick(dot), 0
    for number = math.max(1, dot.totalTicks - ticksLeft + 1), dot.totalTicks do
        total = total + average * tickShape(dot, number)
    end
    return total
end""", """local function remainingDamage(dot, key) -- OMA: key, and timed boosts per tick (ns.omaTickMult)
    if dot.nextTickAt > dot.expiresAt + dot.interval / 2 then return 0 end
    local ticksLeft = math.floor((dot.expiresAt - dot.nextTickAt) / dot.interval + 0.5) + 1
    local mult = ns.omaTickMult
    if not dot.shape and not mult then return ticksLeft * expectedTick(dot) end
    local average, total = expectedTick(dot), 0
    local first = math.max(1, dot.totalTicks - ticksLeft + 1)
    if not dot.shape then first = 1 end
    for number = first, dot.shape and dot.totalTicks or ticksLeft do
        local at = dot.nextTickAt + (number - first) * dot.interval
        total = total + average * (dot.shape and tickShape(dot, number) or 1) * (mult and mult(dot, at, key) or 1)
    end
    return total
end""", 'remaining damage per tick')
    s = edit(s, "expiresAt = dot.expiresAt, damage = remainingDamage(dot) })", "expiresAt = dot.expiresAt, damage = remainingDamage(dot, key) }) -- OMA: key", 'breakdown key')
    s = edit(s, "damage = remainingDamage(cast.dot),", "damage = remainingDamage(cast.dot, key), -- OMA: key", 'breakdown key (cast)')
    # Where each cast's DoT went (by cast ID), so the kill bar's "landed" piece shows on that mob only (DotModel.lua).
    s = edit(s, '        local appliedTo, waiting = onPlayerCast(spellID, castGUID)\n',
        '        local appliedTo, waiting = onPlayerCast(spellID, castGUID)\n'
        '        ns.tracking.omaLastCast = { guid = castGUID, key = appliedTo } -- OMA: for DotModel.lua\n',
        'where a cast went')
    # Hits OmaDoomed knows aren't DoT ticks (your own channel's ticks, your Imp's Firebolt) are claimed before
    # tick matching, so they can't keep a finished DoT alive (Track/Forever.lua, ns.omaClaim).
    s = edit(s, '    if action == "WOUND" or absorbed then onHit(key, school) end\n',
        '    if action == "WOUND" or absorbed then onHit(key, school) end\n'
        '    if ns.omaClaim and not isSecret(school) and ns.omaClaim(unit, key, school, GetTime()) then return end -- OMA\n',
        'claim known hits')
    # Saved settings: DoesItDie keeps ~90 look settings for its own display (skull, markers, focus, nameplates).
    # OmaDoomed draws its own, so only what the tracking itself reads is kept; the rest never reaches
    # OmaDoomedDB.track (Settings.lua migration 3 removes what older builds already saved).
    a = s.find('local DEFAULTS = {\n'); b = s.find('\n}\n', a)
    if a < 0 or b < 0 or 'waitFirstTick = "off"' not in s[a:b] or 'plateOutlineOpacity' not in s[a:b]:
        sys.exit('import_doesitdie: the DEFAULTS block was not found as expected. Upstream changed: check it by hand.')
    s = s[:a] + ('local DEFAULTS = { -- OMA: only the settings the tracking reads (DoesItDie\'s display settings are left out)\n'
        '    showMarkers = true,\n    debug = false,\n    waitFirstTick = "off",\n    estimateDuringCast = true,\n    uiLanguage = "auto",') + s[b:]
    # No slash commands: /did belongs to DoesItDie (both can be installed).
    cut = s.find('---------------------------------------------------------------------------\n-- Slash commands')
    if cut < 0: sys.exit('import_doesitdie: slash command block not found')
    s = s[:cut] + ('-- OMA: DoesItDie\'s /did slash commands are left out (DoesItDie keeps them when it is installed too).\n'
        '-- OMA: what OmaDoomed\'s own additions (Track/Wrack.lua) need from the engine.\n'
        'ns.tracking.dotsByTarget = dotsByTarget\n'
        'ns.tracking.castTargetKey = castTargetKey\n'
        'ns.tracking.trace = trace\n'
        '-- OMA: other classes: the engine stops listening (Core.lua, through Track/Shim.lua)\n'
        'function ns.tracking.off()\n'
        '    frame:UnregisterAllEvents(); frame:SetScript("OnUpdate", nil); meterFrame:UnregisterAllEvents()\n'
        'end\n')
    open(os.path.join(OUT, 'Engine.lua'), 'w', encoding='utf-8').write(s)

os.makedirs(OUT, exist_ok=True)
locale_files()
engine()
shutil.copy(os.path.join(UP, 'LICENSE'), os.path.join(OUT, 'LICENSE-DoesItDie'))
print('Track/ rebuilt from', open(os.path.join(UP, 'SOURCE.txt')).read().strip())
