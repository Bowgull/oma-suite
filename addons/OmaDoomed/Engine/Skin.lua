-- Skin engine: every texture, font and colour the frames draw with, in one place, so a look is one table and nothing
-- else changes (Rich / Classic rings: R.flat in RingsLook.lua). Pieces of Blizzard's own art are named here by path
-- and texture coordinates (from the Forever client's files), so the list matches the nameplates exactly.
local ADDON, ns = ...
local K = {}; ns.skin = K
local ART = 'Interface\\AddOns\\OmaDoomed\\Art\\'
K.ART = ART

K.font = STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'

-- Blizzard's Forever nameplate atlas (Interface\HUD\UINamePlates, 256 x 256): the bar frame, and the target outline's
-- straight part (its white end caps left out: at row size they read as sparks)
K.plateTex = 'Interface\\HUD\\UINamePlates'
K.plateFrame = { 0 / 256, 212 / 256, 121 / 256, 135 / 256 }
K.plateTarget = { 18 / 256, 232 / 256, 85 / 256, 99 / 256 }
K.statusbar = 'Interface\\TargetingFrame\\UI-StatusBar'
K.sizeGrip = 'Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up'
K.sizeGripHi = 'Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight'
K.sizeGripDown = 'Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down'

-- our own soft shapes (Art\list_*.tga, white, tinted in game)
K.listBack = ART .. 'list_back'        -- the one soft dark backing behind the whole list (9-slice, margins 48)
K.rowGlow = ART .. 'list_rowglow'      -- a soft horizontal swell of light, rounded both ends (threat, hover)
K.portraitRing = ART .. 'list_ring'    -- a thin ring round the portrait (threat rim)
K.mark = ART .. 'doomed-mark'

K.white = { 1, 1, 1 }
K.gold = { 1, .82, 0 }
K.healthRed = { .77, .07, .07 }
K.teal = { .18, .72, .65 }
K.empty = { .07, .03, .03, 1 }
-- Blizzard's threat colours: 1 yellow (above the tank), 2 orange (about to pull), 3 red (it's on you)
K.threat = { [1] = { 1, .82, 0 }, [2] = { 1, .5, .02 }, [3] = { .95, .12, .12 } }
-- how strong each threat level's breath is (its top; the bottom is a third of it)
K.threatGlow = { [1] = .45, [2] = .65, [3] = .85 }
K.petRim = { .71, .55, 1 }
