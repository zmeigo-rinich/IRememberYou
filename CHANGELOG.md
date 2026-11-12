# Changelog

Notable changes to **I remember you!** are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

The version lives in `IRememberYou.txt`; `IRY.version` in
`core/constants.lua` and `## AddOnVersion:` must match it, and the release
workflow publishes the zip when `main` is pushed. Add an entry here for every
user-visible change.

## [Unreleased]

## [0.4.0] - 2026-11-12

### Added

- One icon per player, taken from a curated DDS library shipped inside the
  addon (75 icons in `icons/base`). The same texture appears in the reticle
  target frame, the friends list, the guild roster, the ignore list and the
  player browser.
- A manual assignment flow: the browser detail panel shows the current icon and
  opens an 8 x 5 picker; `/pa icon <id> [path|clear]` does the same from chat.
  The chosen icon survives merges and is removed with the merge when undone.
- Ignore-list marking: every character on the game's Ignore list can get a
  dedicated marker icon, a rooster by default. A manually assigned icon always
  wins, and the marker is rebuilt from the live ignore list rather than stored
  in SavedVariables.
- A master switch (`showIcons`, `/pa icons on|off`) that removes every picture
  from every surface at once.
- 3D icons through **OdySupportIcons**: group members get the icon above their
  heads. Icons assigned in OSI are snapshotted and restored, and OSI's
  SavedVariables are never touched.
- An "Icons" settings section: master switch, UI icon size, ignore-list marking,
  the blacklist icon picker and a short note about the 3D dependency.

### Notes

- There is no 3D icon over players outside the group. ESO does not expose their
  world position — `GetUnitRawWorldPosition("reticleover")` answers `0, 0, 0` for
  every unit that is not grouped and not a pet — so nothing can be anchored above
  them. The reticle target keeps its icon in the target frame, which is drawn in
  the UI layer and works for every player.

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
