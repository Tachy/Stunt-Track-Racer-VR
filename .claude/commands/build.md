---
description: Build the Windows release (exe, ZIP, installer) and publish it with release-please
---

Build Stunt Track Racer VR for Windows and publish it as the release that
release-please has prepared. Reply in German. Do the steps in order and stop
on any error (show the error, do not work around it).

## 1. Starting point

- `git status` must be clean and the branch `main`, up to date with
  `origin/main` (`git fetch` then compare). If not: say so and stop.
- Find the open release PR of release-please:
  `gh pr list --state open --label "autorelease: pending" --json number,title,headRefName`
  Its title is `chore(main): release X.Y.Z`; X.Y.Z is the version.

## 2. No release PR: a test build only

If there is no open release PR, nothing is to be released. Build a test
build with the current version plus `-dev` and stop after it:

`powershell -ExecutionPolicy Bypass -File tools/build.ps1 -Version <version from scripts/core/version.gd>-dev`

Report the files in `build/` and that no release was made.

## 3. Release PR: build on its state

- `gh pr checkout <number>` (the PR branch carries the new version in
  `scripts/core/version.gd` and `CHANGELOG.md`). Check that version.gd has
  X.Y.Z; if not, stop (release-please config is off).
- `powershell -ExecutionPolicy Bypass -File tools/build.ps1 -Version X.Y.Z`
  (tests, exe, ZIP, installer). Run it in the background if it takes long and
  report progress.
- `git checkout main`.
- Show the user the files (sizes) and the CHANGELOG section of X.Y.Z, and ask
  (AskUserQuestion) whether to publish: they may first want to try
  `build\StuntTrackRacerVR.exe` (VR and `--xr-mode off -- --no-xr`) or the
  installer. Without a yes: stop here, the build stays in `build/`.

## 4. Publish

- Merge the release PR: `gh pr merge <number> --squash` (release-please
  then tags `vX.Y.Z` and creates the release in its GitHub Action, which also
  attaches the Linux server binary).
- Wait for the release: poll `gh release view vX.Y.Z` (every 20 s, at most
  10 minutes; `gh run list --workflow release-please.yml --limit 1` shows the
  run).
- Attach the Windows files:
  `gh release upload vX.Y.Z build/StuntTrackRacerVR-X.Y.Z-setup.exe build/StuntTrackRacerVR-X.Y.Z-windows.zip --clobber`
- `git pull` on main (the release commit).
- Report the release URL (`gh release view vX.Y.Z --json url`) and its assets.
