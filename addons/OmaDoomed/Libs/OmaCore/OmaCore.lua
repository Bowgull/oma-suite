-- OmaCore: shared code for the Oma add-ons, embedded in each one's Libs/OmaCore (never a separate download).
-- Versioned with LibStub: the newest loaded copy wins. Every OmaCore file checks ns.omaCoreBuild and only
-- (re)defines its piece when this copy is the one being installed; the host add-on reads LibStub('OmaCore-1.0').
-- Pieces: Bus, Anim, Log, Secret, Settings (schema + page + migrations), Slash.
-- OmaCore holds code only; each add-on keeps its own saved data.
local _, ns = ...
local MAJOR, MINOR = 'OmaCore-1.0', 2   -- 2: Slash words can keep the case of what follows
local Core = LibStub:NewLibrary(MAJOR, MINOR)
ns.omaCoreBuild = Core   -- nil when an equal or newer copy is already loaded
if not Core then return end
Core.MAJOR, Core.MINOR = MAJOR, MINOR
