# oma suite 🐉

my world of warcraft addons. built for warlock life in WoW Forever, mostly so i can play from the couch with a controller.

🚧 still building. rough edges are mine 🙂

## the addons

| addon | what it does |
|---|---|
| **[OmaDoomed](addons/OmaDoomed)** | DoT rings over every enemy, a kill bar showing the health your DoTs will still take, a skull on mobs they'll finish, and crowd-control timers you can always see |
| **[OmaDemon](addons/OmaDemon)** | your demon, readable from across the room: low-health glow, soul shards as gems under the pet frame, and your Soulstone, summons, Healthstones and armor looked after |
| **[OmaPad](addons/OmaPad)** | a warlock controller layout that fills empty pad slots as you learn spells, and never replaces a button you changed |
| **[OmaPointer](addons/OmaPointer)** | a mouse pointer for the controller: right stick moves, d-pad steps between buttons, A clicks (test build) |
| **[OmaGuide](addons/OmaGuide)** | lets the controller reach the RestedXP guide box: tick steps with the pad |
| **[OmaChat](addons/OmaChat)** | keeps WoW's chat log on so a phone remote can show chat |

`dev/` holds test and mock addons used while building. `tools/` has the install scripts and helpers.

## install

copy an addon folder from `addons/` into `World of Warcraft\_forever_\Interface\AddOns\`, then restart the game.

or on windows, with WoW closed:

```powershell
.\tools\install-omadoomed-shadow.ps1 -WhatIf   # see what it would do
.\tools\install-omadoomed-shadow.ps1
```

the scripts back up your old copy first and check every file after.

## tests

OmaDoomed and OmaDemon run offline against a fake WoW:

```bash
cd addons/OmaDoomed && luajit tests/run.lua
```

**what i did:** designed every addon, how it looks and when it speaks up, and tested it in real fights. ai tools wrote the code, i was the very picky boss 🙂

MIT licensed.
