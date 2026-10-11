---
description: Release the version release-please has prepared - build the game, installer and server, then publish them as one GitHub release
---

Release Stunt Track Racer VR: build the Windows game (exe, ZIP, installer)
and the Linux online server for the version release-please has prepared,
then publish everything as one GitHub release. Reply in German. Do the steps
in order and stop on any error (show the error, do not work around it).

How the pieces fit: the GitHub Action (`.github/workflows/release-please.yml`)
only keeps a release PR up to date (version in `scripts/core/version.gd`,
`CHANGELOG.md`, manifest) from the Conventional Commits on main. It never
publishes (`skip-github-release`). A release exists only through this
command, and it appears with all its files at once. Between two releases the
repository itself is the nightly state: there are no other builds.

## 1. Starting point

- `git status` must be clean and the branch `main`, up to date with
  `origin/main` (`git fetch` then compare). If not: say so and stop.
- Find the open release PR of release-please:
  `gh pr list --state open --label "autorelease: pending" --json number,title,headRefName`
  Its title is `chore(main): release X.Y.Z`; X.Y.Z is the version.
- No release PR: nothing to release (no new feat:/fix: commits since the
  last release). Say so and stop - no build.

## 2. Build on the release PR's state

- `gh pr checkout <number>` (the PR branch carries X.Y.Z in
  `scripts/core/version.gd` and `CHANGELOG.md`). Check that version.gd has
  X.Y.Z; if not, stop (release-please config is off).
- `powershell -ExecutionPolicy Bypass -File tools/build.ps1 -Version X.Y.Z`
  (game tests, exe, ZIP, installer, server tests, Linux server). Run it in
  the background if it takes long and report progress.
- Write the release notes: the section `## [X.Y.Z]...` of `CHANGELOG.md` up
  to the next `## [` heading, into `build/release-notes-X.Y.Z.md`.
- `git checkout main`.
- Show the user the files (sizes) - `build/StuntTrackRacerVR-X.Y.Z-setup.exe`,
  `build/StuntTrackRacerVR-X.Y.Z-windows.zip`,
  `build/stunt-racer-server-linux-amd64` - and the release notes, and ask
  (AskUserQuestion) whether to publish: they may first want to try
  `build\StuntTrackRacerVR.exe` (VR and `--xr-mode off -- --no-xr`) or the
  installer. Without a yes: stop here, the build stays in `build/`.

## 3. Publish

- Merge the release PR: `gh pr merge <number> --squash`. Its merge commit:
  `gh pr view <number> --json mergeCommit -q .mergeCommit.oid`.
- Create tag and release with all files in one step (gh uploads the files
  to a draft and publishes it only then, so the release never shows up
  without them):
  `gh release create vX.Y.Z --target <merge commit> --title vX.Y.Z --notes-file build/release-notes-X.Y.Z.md --latest build/StuntTrackRacerVR-X.Y.Z-setup.exe build/StuntTrackRacerVR-X.Y.Z-windows.zip build/stunt-racer-server-linux-amd64`
- Mark the PR as released, as release-please itself would (otherwise it
  stops preparing the next release PR: "untagged, merged release PRs
  outstanding"):
  `gh pr edit <number> --remove-label "autorelease: pending" --add-label "autorelease: tagged"`
- `git pull` on main (the release commit).
- Report the release URL (`gh release view vX.Y.Z --json url`) and its
  assets. If the server's protocol differs from the one the running server
  speaks (or the server code changed since the last deploy), remind the user
  that `/deploy-server` puts the new server online - the release itself
  deploys nothing.
