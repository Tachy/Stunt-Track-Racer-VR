---
description: Build a local test installer of the current state (no release, nothing published)
---

Build a Windows test installer of the current working state so the user can
try installing it. Reply in German. Nothing is merged, tagged, uploaded or
committed - this is not a release (that is /build). Stop on any error and
show it, do not work around it.

1. Version: read it from `scripts/core/version.gd` (`const VERSION := "x.y.z"`)
   and append `-local`, e.g. `0.1.0-local` (the exe's file version takes the
   numbers only).
2. Build without the online server:
   `powershell -ExecutionPolicy Bypass -File tools/build.ps1 -Version <x.y.z>-local -NoServer`
   (game tests, exe, ZIP, installer). If the user passed `fast` as an
   argument, add `-SkipTests`. Run it in the background if it takes long and
   report progress.
3. Report:
   - the installer `build\StuntTrackRacerVR-<x.y.z>-local-setup.exe` with its
     size (and the ZIP next to it),
   - whether the working tree had uncommitted changes (`git status --short`):
     they are in this build,
   - how to test: run the installer (per user, no admin rights; it installs
     to `%LOCALAPPDATA%\Programs\Stunt Track Racer VR`), start it from the
     start menu ("Stunt Track Racer VR" = VR, "... (Desktop ...)" = desktop),
     uninstall via Windows "Apps" (Installierte Apps). Settings, saves and
     own tracks stay in `%APPDATA%` either way.

`build/` is in `.gitignore`: the files are never committed.
