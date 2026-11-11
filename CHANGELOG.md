# Changelog

Notable changes to **I remember you!** are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

The version itself has a single source of truth: the git tag. `build.ps1`
writes it into `IRememberYou.txt` and `core/constants.lua`, and the GitHub
release body is extracted from the matching section below — so a release is
described here once and nowhere else.

## [Unreleased]

## [0.3.1] - 2026-11-11

No addon behaviour changed: this release exists to fix the release pipeline.

### Fixed

- GitHub Actions builds the zip from the tag and publishes it with notes from
  this file. The first attempt failed while installing Lua through `apt-get`;
  the workflow now compiles Lua 5.1 from source, so the checks no longer depend
  on the runner's apt mirrors.
- `build.ps1` names the resolved `luac` in its output, which makes a failed
  syntax check easier to diagnose from the CI log.

## [0.3.0] - 2026-11-11

First documented release. Versions 0.2.0 and 0.2.1 predate this changelog;
their archives are kept next to the addon folder.

### Added

- Stable display name in the reticle target frame. The name line is rebuilt
  around the remembered player while the difficulty icon and target marker stay
  untouched; the caption can be rebuilt as character name + title or hidden.
- Chat annotations: player links get a ` (Name)` suffix inside the link text,
  so clicking still resolves the real account.
- Friends list and guild roster rows append the remembered name in grey without
  resizing the row or clipping the location column; long names are shortened on
  a UTF-8 boundary.
- PvP kill feed annotation for both combatants, and kill feed names are used as
  a data source for new players.
- One chat notification when a known player appears under a new `@account`,
  with a configurable noise level (`off` / `confirmed` / `all`).
- Resizable player browser: search over display names, accounts and
  characters; players and pending tabs; paging with buttons and the mouse
  wheel; two-click merge; undo of the last merge; purge; a detail panel listing
  every remembered account with its last-seen date and every character with
  alliance and level.
- Manual rename (custom display name) and reset to the first remembered
  account, from the browser and from slash commands.
- Pending queue for probable renames and account conflicts, applied or rejected
  from the browser or with `/pa yes` / `/pa no`.
- Capture from reticle target, group, friends, guild roster and kill feed, each
  with its own toggle; a poller re-reads the current target when the client does
  not fire a change event.
- Account-wide SavedVariables database with forward-compatible schema repair and
  tombstoned merges, so undoing a merge restores both entities exactly.
- Optional retention purge; the default of `0` means names are never forgotten.
- LibAddonMenu-2.0 settings panel (optional dependency), a keybind to open the
  player list, and the `/pa` / `/iry` command set.
- English and Russian localization, including the keybind label and localized
  alliance names.
