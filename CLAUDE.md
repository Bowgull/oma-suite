# oma-suite

Bowgull's World of Warcraft addons (WoW Forever, Lua). This repo is **public**: never commit secrets, real
machine names, IPs, keys, or anything about the Omashu laptop's setup (that lives in the private `omashu` repo).

## Layout
- `addons/<Name>/`: the shipped addons. Each has its own `.toc`. OmaDoomed and OmaDemon carry a copy of the
  shared `Libs/OmaCore`.
- `dev/`: mock and test addons, never shipped.
- `tools/`: install scripts (Windows PowerShell) and `strip_decode.py`.
- `art/`: shared source art.

## Working
- Tests run offline: `cd addons/OmaDoomed && luajit tests/run.lua [pattern]` (same for OmaDemon). Run them
  before every commit that touches an addon.
- Install to a PC: `tools/install-omadoomed-shadow.ps1` / `tools/install-omademon-folder.ps1` (WoW must be
  closed; `-WhatIf` first). They back up the old folder and hash-check the new one.
- Mockups go through Samara's `show_mockup`, never into this repo.
- Commit as `Bowgull <256685449+Bowgull@users.noreply.github.com>`.
- Nothing goes to CurseForge without Joshua's go.
