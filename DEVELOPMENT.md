# I remember you! — developer notes

Maintenance document for the **IRememberYou** addon. It describes how the addon
is put together, which invariants must hold when changing it, and what to check
before a release.

User-facing documentation lives in `README.md` (English) and `README.ru.md`
(Russian). This file is for whoever edits the code next.

---

## 1. Scope and hard rules

The addon answers one question: *"who is this player, even if they renamed their
account or character?"* Everything else exists to serve that.

Rules that the design depends on. Do not break them casually:

* **Never count kills.** The kill feed is only read as a name source.
* **Never write to other players' chat.** All output goes through
  `IRY:Print` → `CHAT_ROUTER:AddSystemMessage`, which is local to the client.
* **No import/export.** ESO addons have no filesystem access. The database is
  the account-wide SavedVariable `IRememberYouSV`.
* **Retention defaults to 0 (never forget).** Deleting data must always be an
  explicit user action.
* **Only the reticle target frame is restyled.** Group frames, nameplates and
  every other unit frame keep the game's naming (design decision "variant 2").
* **Render paths never mutate the store.** Drawing a name may read; it may not
  teach the addon anything.

---

## 2. File map and load order

`IRememberYou.txt` is the manifest and the load order. Order matters: constants
and strings first, the UI XML before the Lua that uses it, the bootstrap last.

| # | File | Role |
| --- | --- | --- |
| 1 | `core/constants.lua` | namespace `IRY`, version, sources, priorities, settings defaults, `BuildDefaults()` |
| 2 | `lang/en.lua` | `IRY.L` (English) + `ZO_CreateStringId` for the keybind |
| 3 | `lang/ru.lua` | overrides `IRY.L` when the client language is Russian |
| 4 | `bindings.xml` | keybind `IRY_TOGGLE_BROWSER` → `IRY.Browser:Toggle()` |
| 5 | `core/util.lua` | normalization, formatting, UTF-8-safe truncation |
| 6 | `core/store.lua` | entities, indices, merge/undo, pending, purge |
| 7 | `core/resolver.lua` | read-only lookups used by render paths |
| 8 | `core/print.lua` | chat output, notifications, `RefreshUI`, `PurgeOldPlayers` |
| 9 | `track/observer.lua` | the single write gate `Observer:Observe`, snapshots, guild scan |
| 10 | `track/rename.lua` | friend/group/character rename bridges |
| 11 | `track/poller.lua` | timer that re-reads the reticle target |
| 12 | `ui/targetframe.lua` | post-hooks on the reticle frame |
| 13 | `ui/chat.lua` | player-link and kill-feed wrappers |
| 14 | `ui/social.lua` | friends list and guild roster row decoration |
| 15 | `ui/browser.xml` | window, footer, detail panel, row and line templates |
| 16 | `ui/browser.lua` | list logic, paging, resize, detail panel, rename/merge/undo/pending/purge |
| 17 | `ui/settings.lua` | LibAddonMenu-2.0 panel |
| 18 | `ui/commands.lua` | `/pa` and `/iry` |
| 19 | `IRememberYou.lua` | `EVENT_ADD_ON_LOADED` bootstrap |

The manifest also declares `## OptionalDependsOn: LibAddonMenu-2.0`, so LAM is
guaranteed to be loaded before `ui/settings.lua` runs when it is installed.

---

## 3. Runtime lifecycle

```
EVENT_ADD_ON_LOADED (addon name matches)
  ZO_SavedVars:NewAccountWide(svName, schema, nil, IRY.BuildDefaults())
  IRY.Store:Initialize(sv)          -- EnsureSchema + RebuildIndices
  IRY.Store:PrunePending()          -- pending older than pendingTtlDays
  IRY:RegisterCommands()
  IRY.Observer:Initialize()         -- game events
  IRY.Rename:Initialize()           -- rename events
  IRY.Poller:Initialize()           -- timer + reset events
  IRY.TargetFrame:Initialize()      -- ZO_PostHook
  IRY.Chat:Initialize()             -- link + kill feed wrappers
  IRY.Social:Initialize()           -- friends/guild row hooks
  IRY.Browser:Initialize()          -- build rows, register top level
  IRY.Settings:Initialize()         -- LAM panel (may be a no-op)
  checkApiVersion()                 -- chat warning only, never blocks
```

`IRY.sv` is the SavedVariables table. Nothing may call `IRY.Store` methods
before it is initialized; all modules are loaded earlier but only *defined*
then.

---

## 4. Data model

```
IRememberYouSV
  schema          = 1
  nextId          = 1        -- never reused while data exists
  nextPendingId   = 1
  players         = { [id] = Player }
  pending         = { Pending, ... }   -- array, not a map
  stats           = { created, linked, merged }
  settings        = { ...see §11 }
```

```
Player
  id           number
  displayName  string       -- what the user sees
  isCustom     boolean      -- true when displayName came from the user
  createdAt    number       -- os.time(); drives merge order
  updatedAt    number       -- last touch; drives list order
  notes        string
  aliases      { [accountKey] = Alias }
  characters   { [characterName] = Character }
  mergedInto   number?      -- tombstone: absorbed by that id
  mergedAt     number?
  mergeReason  string?      -- conflict | conflict-approved | friend-rename |
                            -- group-rename | manual
```

```
Alias
  firstSeen, lastSeen  number
  source               target | killfeed | guild | group | friend | manual
  confidence           confirmed | probable | manual

Character
  firstSeen, lastSeen  number
  classId, alliance, level, zoneId  number (0 = unknown)
  consoleId            string
```

Character info is observational, not permanent: `Reconcile` re-attaches a
**known** character on every observation and `AttachCharacter` overwrites only
non-`nil`, non-empty, non-zero values. That is how a rare alliance change or a
level-up lands without any extra event, and why an observation with no info
(kill feed, a partial guild row) cannot erase what is already known. `0` is
"unknown", never "no alliance".

### Keys

* **Account keys are stored undecorated.** `@Name` and `Name` both normalize to
  `Name`, so one person has one key regardless of which API produced the string.
  `Util.FormatAccount` puts the `@` back for display.
* **Character keys keep their exact name** (trimmed, markup stripped).
* Keys are case-sensitive in the store and compared case-insensitively only
  where the game does (`Util.SameName`).

### Indices

`account → id` and `character → id` live in memory only. They are **rebuilt from
`players`** after every structural change (`RebuildIndices`), and tombstoned
players are skipped. Never mutate an entity's aliases/characters without
updating the indices or rebuilding them.

---

## 5. Store invariants

These are load-bearing; violations show up as duplicate entities or lost names.

1. **One key → one entity.** An account or character belongs to exactly one
   non-tombstoned entity. `AttachAccount` / `AttachCharacter` refuse to steal a
   key owned by another id and return `false`; the caller must merge instead.
2. **`nextId` only grows.** Ids are never recycled while the SV exists. `Wipe`
   is the only place that resets counters, and it erases everything.
3. **Tombstones are permanent.** `Merge` never deletes the absorbed entity; it
   sets `mergedInto`, `mergedAt`, `mergeReason`. That is what makes undo exact.
4. **All ids entering the API are resolved** through `Store:ResolveFinal`, which
   follows `mergedInto` chains with a cycle guard.
5. **`displayName` is not recomputed on merge** unless the surviving entity was
   not custom and the absorbed one was. `ResetDisplayName` recomputes from
   history instead.
6. **Defaults are copied, not shared.** `ZO_SavedVars` may deep-copy, but
   `IRY.BuildDefaults()` always hands out a fresh `settings` table. Never pass
   `IRY.SettingsDefaults` itself to anything that writes.

### Key methods

| Method | Returns / effect |
| --- | --- |
| `Initialize(sv)` | schema repair, indices |
| `EnsureSchema()` | fills missing top-level fields and settings keys from defaults (forward-compatible) |
| `Reconcile(account, character, source, info, confidence)` | the generic upsert; returns `id, action, extra...` where action is `created`, `linked`, `same`, `merged`, `invalid` |
| `AttachAccount` / `AttachCharacter` | `true` when a key was added to this entity |
| `Touch` | updates `updatedAt` and `lastSeen` for known keys |
| `Merge(srcId, dstId, reason)` | copies aliases/characters/notes, keeps the custom name if needed, tombstones `src`, rebuilds indices |
| `UndoMerge(srcId)` | `srcId` must be the tombstone id; removes from `dst` only keys whose index still points at `dst` |
| `Forget(id)` | deletes one standalone entity and drops pending entries that reference it; refuses tombstones and entities with tombstones pointing at them |
| `OrderForMerge(a, b)` | `keep, drop`: older `createdAt` wins, tie broken by lower id |
| `DefaultDisplayName(player)` | earliest alias `firstSeen`, else earliest character, else `?` |
| `SetDisplayName` / `ResetDisplayName` | custom name handling; sanitized, max 32 bytes, UTF-8 safe |
| `List(limit)` | non-tombstoned players, newest `updatedAt` first |
| `Dump(id)` | array of debug lines |
| `AddPending` / `GetPending` / `FindBridgePending` / `RemovePending` / `PrunePending` | pending queue |
| `Purge(days)` | removes only non-custom, non-tombstoned entities whose **newest** `lastSeen` is older than the cutoff; `days <= 0` is a no-op |
| `Wipe()` | erases players, pending, counters, stats; settings survive |

`Reconcile` contains a conflict branch of its own (merge when one character maps
to two accounts). In normal play `Observer:Observe` intercepts that case first,
so the branch is defence in depth; keep the two consistent if you touch either.

---

## 6. Observation pipeline

Every write goes through a single gate:

```
Observer:Observe(account, character, source, info, opts)
```

Inputs must already be normalized (`Util.NormalizeAccount`,
`Util.NormalizeCharacter`). Options:

* `create` — may a new entity be created (default `true`),
* `quiet` — suppress the chat notification,
* `confidence` — override the confidence implied by the source.

### Confidence

| Source | Implied confidence | May create? |
| --- | --- | --- |
| `friend` | confirmed | yes, including offline (last known character) |
| `group` | confirmed | yes |
| `target` (reticle) | probable | yes |
| `killfeed` | probable | yes (see note) |
| `guild` | probable | **no** — `create = false` |
| `manual` | manual | only through explicit API use |

Note: `ui/chat.lua` calls `Observe` without a `create` flag, so the kill feed can
create entities when both names are new.

### Decision order

```
both names missing                   -> nil, "invalid"
self and ignoreSelf on               -> nil, "self"
no account match, no character match
    and create == false              -> nil, "unknown"
account -> A, character -> B, A ~= B (conflict)
    autoMergeOnConflict off          -> queue conflict pending, nil, "pending"
    otherwise                        -> merge older into survivor, notify, "merged"
account unknown, character -> B, probable confidence
    and autoAcceptProbable off       -> queue bridge pending, nil, "pending"
    otherwise                        -> normal reconcile
normal reconcile                     -> created | linked | same
    (linked account)                 -> notify account changed
```

A **bridge** pending is the "probable rename" case: a new `@account` seen
together with an already known character. The pairing comes from the client and
is trustworthy; the inference "same person" is not, so it waits for the user.

`Observer:IsSelf` compares normalized keys with `GetUnitDisplayName("player")` /
`GetUnitName("player")`. With `ignoreSelf` on (default) it short-circuits before
any index lookup. This is not cosmetic: `EVENT_UNIT_CHARACTER_NAME_CHANGED` also
fires for the `player` unit on zoning and reload, and the kill feed reports your
own kills and deaths. `track/rename.lua` additionally ignores unit tags that are
neither `reticleover` nor `groupN`.

Friend snapshots create entities for every friend in the list, online or offline.
Offline friends contribute their last known character; when the client returns no
character info, the entity is created from the account alone.

`Observer:ApplyPending` merges conflicts (re-ordering first) or replays bridges
through `Reconcile`; `RejectPending` just removes the entry.

### Snapshots and events

| Trigger | Call | Notes |
| --- | --- | --- |
| `EVENT_RETICLE_TARGET_CHANGED` | `SnapshotTarget` | main source |
| `EVENT_GROUP_MEMBER_JOINED` | `SnapshotGroup(quiet)` + target | |
| `EVENT_GROUP_MEMBER_LEFT` | `SnapshotGroup(quiet)` | |
| `EVENT_FRIEND_ADDED` | `SnapshotFriends(quiet)` | |
| `EVENT_PLAYER_ACTIVATED` | group + friends + guild scan | once per login/zone load |
| `EVENT_GUILD_DATA_LOADED` | `StartGuildScan` | roster is lazy |
| `EVENT_GUILD_MEMBER_CHARACTER_UPDATED` | `GuildMember` | one row |
| poller tick | `KeepUnit("reticleover", target)` | only on changed names |

Guild scanning is chunked (`GUILD_SCAN_CHUNK = 100` members per step,
`GUILD_SCAN_DELAY = 100 ms`) to avoid a frame spike on large accounts.

`Observer.unitAccounts[unitTag]` remembers the last account seen on a group unit;
it is the bridge that makes `EVENT_GROUP_MEMBER_ACCOUNT_NAME_UPDATED` usable.

### Rename bridges (`track/rename.lua`)

1. **Friend account rename** — `OnFriendRenamed(old, new)`: merge if both ids
   exist, otherwise attach the new alias to the old id (confirmed). If only the
   new id is known, the old alias is kept for history.
2. **Group account rename** — `OnGroupAccountUpdated(unitTag, accountName)`:
   tolerant about argument order; merges two known ids or attaches the new alias
   to the id of the previous account.
3. **Friend logs in / changes character** — `OnFriendCharacterUpdated` adds the
   character to the known account (`create = false`).
4. **Character rename** — `OnUnitCharacterRenamed` re-snapshots the unit with
   confirmed confidence, so the entity gains another character alias.

### Target poll (`track/poller.lua`)

The client fires `EVENT_RETICLE_TARGET_CHANGED` when the target object changes,
not when the same target silently changes `@account`. The poller re-reads
`reticleover` every `pollIntervalMs` (clamped to a minimum of 250 ms) and calls
`KeepUnit` only when the normalized account/character pair differs from the last
one. It runs only when both `pollTarget` and `captureTarget` are on; changing
either setting calls `Poller:Apply()` from the settings panel.

---

## 7. Display surfaces

### 7.1 Reticle target frame (`ui/targetframe.lua`)

* Only `reticleover` and `reticleovertarget` are touched.
* `ZO_PostHook(ZO_UnitFrameObject, "UpdateName")` and `"UpdateCaption"`.
* `ApplyName`: if `replaceTargetName`, resolve the unit through
  `Resolver:ForUnit`, then rebuild the text: stable name + difficulty icon
  (`GetUnitOverlandDifficulty`, `ZO_CHALLENGE_DIFFICULTY_ICONS_GAMEPAD`) +
  target marker (`GetUnitTargetMarkerType`, `ZO_GetPlatformTargetMarkerIcon`).
* `ApplyCaption`: `hideTargetCaption` hides and clears the label;
  `replaceTargetCaption` rebuilds it as character name + title.
* Hook bodies run inside `pcall`; a failure is only reported through `IRY:Debug`.
* `Refresh()` calls `ZO_UnitFrames_UpdateWindow` for the two reticle tags, used
  after a rename/merge/undo so the change is visible without re-targeting.

### 7.2 Chat links (`ui/chat.lua`)

`ZO_LinkHandler_CreatePlayerLink` is replaced once with a wrapper. The suffix
`" (Name)"` is inserted **inside** `|h...|h`; the link payload is untouched, so
clicking still resolves the real account.

`Chat:Suffix(account, character, shownName)` returns `nil` when:

* `annotateChat` is off;
* the entity is unknown;
* the stable name equals the shown name (nothing to add);
* `annotateSelf` is off and the name is the player themself.

Both suffixes (`Chat:Suffix` and `Chat:SocialSuffix`) are built by one shared
helper, `buildSuffix`, so the "unknown / same name / self" rules cannot drift
apart. They differ only in which setting gates them (`annotateChat` versus
`annotateSocial`).

A bare name from a link is treated as a decorated `@account` if the client says
so, otherwise as a character name.

### 7.3 Kill feed (`ui/chat.lua`)

`CHAT_ROUTER:GetRegisteredMessageFormatters()[EVENT_PVP_KILL_FEED_DEATH]` is
wrapped once. The wrapper:

1. calls the original formatter;
2. feeds both combatants to `Observer:Observe` (data source, regardless of
   whether the line is displayed);
3. if `annotateKillFeed`, inserts the suffix after the colorized killer and
   victim names in both `message` and `narration`.

Re-installation is retried on `EVENT_PLAYER_ACTIVATED`, because the chat router
may finish registering formatters after addons load, or another addon may
replace the entry (`pChat` is the usual suspect).

### 7.4 Friends list and guild roster (`ui/social.lua`)

These rows are drawn by the game, so this is display only. Two `ZO_PostHook`s —
`FRIENDS_LIST_MANAGER:SetupEntry` and `GUILD_ROSTER_MANAGER:SetupEntry` — append
` |c8F8F8F (Name)|r` to the `DisplayName` label. The real account name stays in
front and in the sort key; nothing is replaced.

* The hook body reads the freshly set text and appends once. `SetupEntry`
  rewrites the label on every refresh, so no reset is needed; the colour marker
  guards against a double install.
* Nothing is resized. In both lists the `Zone` label is anchored to the right
  end of `DisplayName`, so widening the name pushed the location column to the
  right, and shrinking `Zone` afterwards clipped the location text: that is why
  the columns drifted between rows. `AppendSuffix` instead measures
  `DisplayName:GetTextWidth()` against the label's own width. The whole
  `" (Name)"` suffix is used when it fits; otherwise only the remembered name is
  shortened, character by character (`utf8Prefix` never splits a UTF-8
  character) until `" (Nam...)"` fits. With less than ~60 px of extra room the
  suffix is dropped rather than shown as one letter.
* `GetTextWidth` is used for measuring only; if the method is missing, the
  suffix is appended as is and the game ellipsizes the label itself.
* Keyboard UI only: `IsInGamepadPreferredMode()` skips the console layout.
* Hooks are installed once and re-checked on `EVENT_PLAYER_ACTIVATED` so a late
  replacement by another addon is still covered.
* The suffix comes from `Chat:SocialSuffix` (gated by `annotateSocial`), not from
  a second implementation.

### 7.5 Output helpers (`core/print.lua`)

* `IRY:Print` — prefixed system line.
* `IRY:Debug` — gray, only with `settings.debug`.
* `IRY:NotifyAccountLinked` — "ID changed" line, filtered by `notifyLevel`
  (`off` / `confirmed` / `all`).
* `IRY:NotifyMerged` — automatic merge line; uses raw entity names on purpose,
  because the absorbed name must be shown as it was *before* the merge.
* `IRY:NotifyPending` — one line with the id and both `/pa yes|no` hints.
* `IRY:RefreshUI` — the only "redraw everything" entry point.
* `IRY:PurgeOldPlayers(days)` — shared by the settings button, the browser and
  `/pa purge`; reports the result and returns the removed count.

---

## 8. Browser window

No `ZO_ScrollList`: a fixed pool of **40** row buttons (`MAX_ROWS`), filled from
a paged snapshot. That keeps the window cheap and immune to scroll-list API
churn. Only the rows that fit into the current height are filled and shown.

### Layout

`ui/browser.xml` defines `IRY_Browser`, a resizable `TopLevelControl`
(`movable`, `clampedToScreen`, `mouseEnabled`, `resizeHandleSize="16"`), plus two
virtual templates: `IRY_BrowserRow` (`Id`, `Name`, `Meta`, `Seen` labels and a
hidden `Highlight` backdrop) and `IRY_DetailLine` (`Name`, `Meta`).

Default size is **660 × 680**; constraints are **660 × 420** minimum and
**1600 × 1200** maximum. Rows are anchored `TOPLEFT 124` / `BOTTOMRIGHT -112`, so
they stretch with the window. The footer is a 96 px control anchored to the
bottom edge; its children use their own top-left offsets.

Groups of controls:

* header: `Title`, `Close`, `SearchBGEdit`, `TabPlayers`, `TabPending`, `Count`,
  `HeadId/Name/Meta/Seen`;
* list: `Rows` and the 40 generated `IRY_BrowserRowN`;
* footer: `Detail` summary label, `RenameBGEdit`, `Rename`, `Reset`, `Merge`,
  `Undo`, `Yes`, `No`, `Prev`, `PageLabel`, `Purge`, `Next`;
* detail panel: `IRY_BrowserDetailPanel` with `…Title`, `…Lines` (holds the
  generated `IRY_DetailLineN`), `…Hint`, `…Close`, `…BG`.

Footer buttons and detail-panel children have explicit global names instead of
`$(parent)…`. The page-size check script in the release notes assumes
`$(parent)` is the window, and the detail panel is not.

### State

```lua
state = {
  tab, page, search, selected, mergeFirst, data,
  left, top, width, height, rowsPerPage,
  detailOpen, detailPlayerId, detailOffset, detailVisible, detailItems,
}
```

* `data` is a flat array of `{ kind = "player", player = ... }` or
  `{ kind = "pending", entry = ... }`, rebuilt on every `Refresh`.
* `Collect` filters: lower-case substring over display name, every account key
  and every character; a leading `@` in the query is stripped because accounts
  are stored undecorated. Players keep `Store:List` order (newest first);
  pending entries are sorted by id.
* `selected` is a player id on the players tab and a pending id on the pending
  tab. The counters are independent — never look a pending id up as a player.
* `mergeFirst` holds the first id of a two-click merge.
* `rowsPerPage` is derived, never configured: `UpdatePageSize` divides
  `IRY_BrowserRows:GetHeight()` by `ROW_HEIGHT` (26), clamped to 5..`MAX_ROWS`.
  It falls back to the window height minus the fixed offsets when the control
  has not been laid out yet.

### Behaviour

* Rows are created in `Initialize` via `CreateControlFromVirtual` and carry
  `row.index` (1..`MAX_ROWS`); the click handler maps it to
  `data[(page-1)*rowsPerPage + index]`.
* `Refresh` recomputes the page size first, so resizing immediately changes how
  many players are visible and how many pages exist.
* Two-click merge: first press stores `mergeFirst`, second press merges
  `OrderForMerge(first, selected)`. `UndoLastMerge` scans for the tombstone with
  the newest `mergedAt`.
* Rename commits on Enter, on the button, and on focus loss — but focus loss
  only commits when the text really differs, so clicking around stays quiet.
* `Purge` calls `IRY:PurgeOldPlayers()` with the stored retention period.
* Mouse wheel pages (`TurnPage(-delta)`); Prev/Next buttons do the same.
* Geometry is saved on `OnMoveStop` **and** `OnResizeStop` into
  `settings.browserLeft/browserTop/browserWidth/browserHeight` (deliberately not
  part of the defaults; `nil` means "centred, default size"). `Show` clamps the
  saved size to the constraints and to the current screen size.

### Detail panel

The panel is a **child** control of `IRY_Browser`, not a second top-level window.
That single choice gives the required behaviour for free:

* hiding the list hides the panel;
* switching tabs, closing the window, `Escape`, rejecting/approving a pending
  entry and forgetting a player all call `CloseDetail`;
* selecting another player only replaces the contents (`OpenDetail` resets the
  scroll offset), so there is never more than one panel.

`PlaceDetailPanel` anchors it to the right of the window (`TOPLEFT`/`BOTTOMRIGHT`
relative to the window's right edge) and falls back to the left side when the
right edge would leave the screen. It is re-placed after a resize.

`BuildDetailItems` produces a flat list rendered into `MAX_DETAIL_LINES` (40)
template lines of 18 px:

```
header   Accounts
account  @Name                         last seen
blank
header   Characters
character Name                         alliance · level
muted    no accounts recorded / no characters recorded
```

Alliance text comes from `Util.FormatAlliance` (`GetAllianceName` +
`ZO_CachedStrFormat(SI_ALLIANCE_NAME, …)`), so it follows the client language.
Scroll with the wheel: `ScrollDetail` clamps the offset to `#items - visible`.

### Scene integration

`Initialize` registers the window with `SCENE_MANAGER:RegisterTopLevel(window,
false)`. `Show`/`Hide` then go through `ShowTopLevel`/`HideTopLevel`, which keeps
the scene manager's `numTopLevelShown` bookkeeping correct and makes the first
`Escape` close the window instead of opening the game menu. If the API is
missing, the code falls back to `SetHidden`. Do not bypass these calls with raw
`SetHidden(false/true)` once `usesTopLevel` is true.

`SetDimensionConstraints` is applied in `Initialize` when available; without it
the window still resizes, just without the game-side clamps — `Show` clamps the
saved size itself.

After showing, `Show` calls `IRY_Browser:BringWindowToTop()` (guarded by a
`nil` check). ESO stacks visible top-level windows in registration order, so a
window opened from a slash command can otherwise sit under a window that was
registered later and only come forward on the first mouse click.

---

## 9. Settings panel

`ui/settings.lua` uses LibAddonMenu-2.0. `local LAM = LibAddonMenu2` is captured
at file load; with `OptionalDependsOn` this is safe. Without LAM,
`Settings:Initialize` returns `false` and nothing else changes — the addon is
fully usable through commands and the keybind.

* Panel id: `IRememberYouOptions`; slash command: `/iryoptions`.
* `registerForRefresh` and `registerForDefaults` are on, so the panel re-reads
  values and the "Defaults" button resets to `IRY.SettingsDefaults` (through the
  same setters, so side effects run).
* Getters read `sv.settings` on every call; setters write directly to it.
* Side effects: target-frame checkboxes call `IRY:RefreshUI()`; `captureTarget`,
  `pollTarget` and `pollIntervalMs` call `IRY.Poller:Apply()`.

Sections: target frame, chat, data collection, linking, maintenance. The first
widget is the "open the player list" button.

---

## 10. Commands

`ui/commands.lua` registers `/pa` and `/iry` in `SLASH_COMMANDS`. Dispatch is a
plain `if/elseif` chain on the lower-cased first word.

* `resolveId` accepts `#12`, `12`, `@Account`, `Account` or a character name and
  resolves through `Resolver:ForName`.
* `resolveRawId` first tries an exact player id (needed for tombstones, which the
  index does not contain), then falls back to `resolveId`.
* `/pa purge [days]`: a non-numeric argument prints the usage line; `0` (or no
  argument with the setting at 0) prints "disabled"; only a positive number
  deletes.
* `/pa forget <id>`: deletes one entity. It refuses a tombstone and an entity
  with tombstones pointing at it, so undo chains stay valid; remove pending
  entries that reference the deleted entity.
* `/pa yes|no [n]` default to the first pending entry.
* `IRY.Commands.Handle` / `ResolveId` are exposed so the browser and tests can
  reuse the same parsing.

Debug subcommands: `on|off`, `fake <acc> <char>`, `bridge <acc> <char>`,
`conflict`, `dump <id>`, `wipe confirm`. `fake` and `bridge` both call
`Observe` and differ only in the printed wording; `conflict` simulates the
A/B → C/D → C/B merge case; `wipe confirm` erases the database and resets ids.

---

## 11. Settings keys and defaults

`IRY.SettingsDefaults` (in `core/constants.lua`) is the single source. Every key
here is also filled in by `Store:EnsureSchema` for existing saves.

| Key | Default | Type | LAM control | Effect |
| --- | --- | --- | --- | --- |
| `replaceTargetName` | `true` | bool | checkbox | rebuild reticle name |
| `replaceTargetCaption` | `true` | bool | checkbox | rebuild caption |
| `hideTargetCaption` | `false` | bool | checkbox | hide caption entirely |
| `annotateChat` | `true` | bool | checkbox | suffix in player links |
| `annotateKillFeed` | `true` | bool | checkbox | annotate kill feed |
| `annotateSocial` | `true` | bool | checkbox | append remembered name in friends/guild rows |
| `annotateSelf` | `false` | bool | — | allow suffix on yourself (code only) |
| `captureTarget` | `true` | bool | checkbox | learn from reticle |
| `captureGroup` | `true` | bool | checkbox | learn from group |
| `captureFriends` | `true` | bool | checkbox | learn from friends |
| `captureGuild` | `true` | bool | checkbox | enrich from guild roster |
| `captureKillFeed` | `true` | bool | checkbox | learn from kill feed |
| `ignoreSelf` | `true` | bool | checkbox | never record your own account/character |
| `pollTarget` | `true` | bool | checkbox | timer re-read |
| `pollIntervalMs` | `1000` | number | slider 250–5000, step 250 | timer interval |
| `notifyLevel` | `"confirmed"` | enum | dropdown | `off` / `confirmed` / `all` |
| `autoAcceptProbable` | `false` | bool | checkbox | bridges apply immediately |
| `autoMergeOnConflict` | `true` | bool | checkbox | merge conflicts immediately |
| `pendingTtlDays` | `30` | number | — | pending expiry on login (code only) |
| `purgeAfterDays` | `0` | number | slider 0–3650, step 30 | retention, 0 = never |
| `debug` | `false` | bool | checkbox | debug lines |
| `browserLeft`, `browserTop` | absent | number | — | saved window position |
| `browserWidth`, `browserHeight` | absent | number | — | saved window size |

`annotateSelf` and `pendingTtlDays` intentionally have no widget; they are
advanced/code-only knobs. If you expose them, add a LAM control and a user string
in both languages.

---

## 12. Localization

* `lang/en.lua` always defines `IRY.L`.
* `lang/ru.lua` replaces `IRY.L` when `GetCVar("language.2") == "ru"` (wrapped
  in `pcall`, so a missing CVar cannot break loading).
* Both tables must have **exactly the same keys**. `HELP` is an array of lines;
  keep the same number of lines in both languages.
* The keybind label is a game string, not an `IRY.L` entry:
  `ZO_CreateStringId("SI_BINDING_NAME_IRY_TOGGLE_BROWSER", ...)`. The English
  value is created in `lang/en.lua`; the Russian file overrides it inside the
  language check, so the Controls menu shows the client language.
* User-facing text never lives in Lua logic; commands, settings, row headers and
  messages all go through `IRY.L`.
* Files are UTF-8 **without BOM** (the game's Lua parser is not happy about a
  BOM). Cyrillic user names are truncated on a UTF-8 boundary by
  `Util.SanitizeDisplayName`.

---

## 13. Conventions and gotchas

* One global: `IRY`. Everything hangs off it; files do not create other globals
  (XML control names are the exception and are prefixed `IRY_Browser...`).
* File headers explain *why*, not *what*. Keep that style.
* Any new hook into game code goes through `ZO_PostHook` or a guarded wrapper
  and is installed exactly once (compare against the stored wrapper).
* Hooks and post-hooks are wrapped in `pcall` where a failure could break the
  target frame.
* Normalize names before they touch the store; the store assumes canonical keys.
* Resolve every id through `ResolveFinal` before reading fields.
* Never index `IRY.Store` methods during file load; the SV does not exist yet.
* Do not add a dependency on LAM for core features.
* `ZO_SavedVars` deep-copies defaults; still, never hand the same settings table
  to two owners.
* Adding a page row no longer means changing a constant: the page size comes from
  the window height. Do not reintroduce a fixed `PAGE_SIZE`. If you change
  `ROW_HEIGHT` in `ui/browser.lua`, keep it in sync with the row template's
  height in `ui/browser.xml`, and keep `ROWS_TOP_OFFSET` / `ROWS_BOTTOM_OFFSET`
  in sync with the anchors of `Rows`.

### Known inconsistencies worth knowing

* `Store:Reconcile` duplicates the conflict merge that `Observer:Observe`
  normally performs first. Both paths must stay behaviourally identical.
* `/pa debug fake` and `/pa debug bridge` are functionally the same call with
  different output strings.
* `ui/commands.lua`'s header still mentions "Phase 1"; the UI exists now.

---

## 14. Limitations

* A player is only recognisable if the client once exposed account and character
  together (target, group, friend, kill feed). Guild data enriches only known
  accounts.
* Friends are taken from the friend list even while offline, so they can appear
  with a stale last-known character.
* Yourself is not recorded while `ignoreSelf` is on (default). A row created by
  an older version has to be removed with `/pa forget <id>`.
* The guild roster is lazy; data arrives seconds after login, chunked.
* Cross-realm / console name decoration differs; normalization and
  `FormatAccount` handle the common cases but this is the least tested area.
* Pending entries are pruned on login only (`pendingTtlDays`), not on a timer.
* There is no import/export and no backup; `IRememberYouSV` is the only copy.

---

## 15. Test checklist

Before a release, in a live client:

1. `/reloadui` on a fresh character: no Lua errors, "loaded" line, correct
   version.
2. Point at a player: name and caption replaced; difficulty icon and target
   marker preserved; group frames untouched.
3. Rename via `/pa rename <id> <name>` and through the browser (Enter, button,
   focus loss); `/pa reset <id>` restores the first account.
4. Account change: `/pa debug bridge <newAcc> <knownChar>` → pending entry, one
   chat line, `/pa yes` applies, `/pa no` drops.
5. Conflict: `/pa debug conflict` → automatic merge (default) and
   `autoMergeOnConflict` off → conflict pending.
6. `/pa undo <id>` restores both entities exactly (aliases and characters).
7. Browser: search with and without `@`, both tabs, paging and mouse wheel,
   merge two rows, undo last merge, purge with 0 and with a positive value,
   hover highlight, `Escape` closes and does not open the game menu.
8. Resize the browser: drag the bottom-right corner, check the min/max clamps,
   that the visible row count changes immediately, and that size and position
   survive a `/reloadui`. Shrink it until the list shows only a few rows.
9. Detail panel: click a player, check every account and character with alliance
   and level; click another player — the same panel changes contents; switch
   tabs, close the list and press `Escape` — it disappears; open it while the
   window sits at the right screen edge — it flips to the left; scroll it with
   the wheel until the hint shows the last position.
10. Settings panel: every control changes behaviour immediately; "Defaults"
    restores all values and side effects (poller restart) still happen.
11. Russian client: all strings, button widths, keybind name; no overflow.
12. Without LibAddonMenu: addon loads, no panel, commands and keybind work.
13. With `pChat` (if available): kill feed annotation and links still render.
14. Chat suffix: not applied to yourself, not duplicated when the stable name
    equals the shown name.
15. Self: change location, reload and join a group — you must not appear in the
    list. Turn `ignoreSelf` off and confirm an observation can create you again;
    turn it back on.
16. `/pa forget <id>` removes a standalone row; it refuses a tombstone and an
    entity with merged players inside, with a readable message.
17. Offline friend: with a friend offline, `/reloadui` must create a row with
    their last known character (or account only, if no character is known).
18. Friends list and guild roster: the remembered name is appended in grey, the
    account name is unchanged and still sorted first; the location column starts
    at the same x on every row, whether or not that row has a remembered name,
    and no location text is clipped; a long remembered name is shortened with
    "...", not pushed into the next column; turning `annotateSocial` off removes
    the suffix on the next refresh; rows that refresh repeatedly never gain a
    second suffix.
19. Alliance: target a player, note the alliance in the detail panel, then meet
    them in a different alliance (campaign guest, group) — the value updates on
    the next observation and does not reset to "unknown" after a kill-feed line
    without info.

Items that are not yet verified in a live client (treat as first suspects if
something looks wrong): `GetAPIVersion()` versus the manifest's
`101050 101051`, the group account-name event argument order, offline-friend
rename events, guild roster timing, kill feed when the UI setting is off,
`pChat` compatibility, Russian label widths, `Label:GetTextWidth()` on the
social row templates (the suffix fitting relies on it), the resize handle on
every UI scale, detail-panel anchoring at the screen edges, `FRIENDS_LIST_MANAGER` /
`GUILD_ROSTER_MANAGER` `SetupEntry` argument order, localized alliance names,
and `BringWindowToTop` actually raising the list (it is a C-side control method,
so it cannot be checked statically).

---

## 16. Release checklist

The version has a single source of truth: the git tag. `build.ps1` writes it
into `core/constants.lua` and `IRememberYou.txt`; `.github/workflows/release.yml`
re-runs the same script in `-VerifyOnly` mode and publishes the zip when a `v*`
tag is pushed.

1. Describe the release under a new `## [<version>]` heading in `CHANGELOG.md`.
   The GitHub release body is extracted from that section, so a tag without it
   fails the workflow. Do not edit the version anywhere else by hand.
2. Run `.\build.ps1 -Version <version>`. It writes `IRY.version`,
   `## Version:` and `## AddOnVersion:` (`major*10000 + minor*100 + patch`;
   `0.3.0` becomes `300`), runs every static check below, and writes the zip
   next to the addon folder (`..\IRememberYou-<version>.zip`; in this project
   that is `Output\`).
3. Commit the changelog entry and the version bump together, then create the
   tag: `git tag v<version> && git push origin main --tags`.
4. CI verifies that the tag matches the committed files, rebuilds the zip and
   attaches it to a GitHub release named after the tag.
5. Upload the same zip to ESOUI by hand — the site has no public upload API.
6. Run the live-client checklist above (§15) against that zip before announcing
   it.

`build.ps1` flags: `-Version` (default: the exact tag on `HEAD`, else the
manifest version), `-VerifyOnly` (never write; fail on any mismatch), `-NoZip`,
`-OutputPath <dir>` (default: the addon folder's parent, `Output\` here),
`-ReleaseNotesPath <file>`, `-LuacPath <exe>`, `-SkipLuaCheck`.

Static checks, run locally and in CI:

* `luac -p` on every `.lua` file (bundled `Input/lua-5.1.5_Win64_bin/luac5.1.exe`
  locally, `lua5.1` from apt in CI; set `LUAC` to override);
* every `.xml` parses as XML;
* every `.lua`/`.xml`/`.txt`/`.md` is valid UTF-8 without BOM;
* EN and RU define exactly the same `IRY.L` keys, `HELP` has the same line
  count, and every `IRY.L.*` used in code exists;
* every path listed in `IRememberYou.txt` exists;
* the zip has `IRememberYou/IRememberYou.txt` at its root and contains none of
  `.git`, `.github`, `.gitignore`, `.gitattributes` or `build.ps1`.

`build.ps1` and `.github/` are excluded from the zip automatically, so the
archive can be uploaded as is.

---

## 17. Recipes

**Add a data source**

1. Add `IRY.SOURCE.X` and its priority in `core/constants.lua`.
2. Call `IRY.Observer:Observe(account, character, IRY.SOURCE.X, info, opts)`
   with normalized keys. Decide explicitly on `create`, `quiet` and
   `confidence`.
3. If it needs a toggle, add a default in `SettingsDefaults`, a LAM checkbox,
   and strings in both languages.
4. Document the trust level in the header of `observer.lua`.

**Add a setting**

1. Add the key and default to `IRY.SettingsDefaults`.
2. Add a control in `ui/settings.lua`; wire a side effect if the value is read
   at start-up (poller, hooks, layout).
3. Add `OPT_*` strings to both language files.
4. Mention it in both READMEs if it is user-visible.

**Add a command**

1. Add a branch to `handle` in `ui/commands.lua`.
2. Add the usage line to `HELP` in both languages.
3. Expose the logic as a method if the browser should reuse it.
4. Update the command table in both READMEs.

**Add a string**

1. Add it to `lang/en.lua` and `lang/ru.lua` with the same key.
2. Use `IRY.L.KEY` at the call site; never inline user text.

---

## 18. Potential tasks

Not bugs yet — ideas and rough edges recorded so they are not lost.

* **Diagonal resize of the browser.** Dragging the corner currently stretches
  the window by one axis at a time; a drag that moves both `dx` and `dy` does not
  resize both together. Suspects: the 16 px resize handle of `IRY_Browser` is
  partly covered by the footer (anchored `BOTTOMRIGHT -8,-8`, 96 px high) or by
  the `Next` button in its top-right corner, so the pointer leaves the handle
  once the drag starts; or the handle only tracks one axis when the cursor
  leaves the 16 px box. Try a larger `resizeHandleSize`, moving the footer up a
  few pixels, and checking behaviour at 100 % and scaled UI, with the detail
  panel both open and closed.
* **Bring-to-front on open** was fixed with `BringWindowToTop`; if it ever
  regresses, check that the call still happens before the first refresh.
* **Sort the browser by name** as an alternative to newest-first.
* **Per-guild capture toggles** instead of one global `captureGuild`.
* **Detail panel on the pending tab** (currently only the players tab has one).
