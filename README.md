# I remember you!

**English** · [Русский](README.ru.md) · [Changelog](CHANGELOG.md)

An Elder Scrolls Online addon that remembers **players**, not just names.

In ESO a player can change their `@account` and every addon, friend list entry
and chat link suddenly shows a stranger. **I remember you!** keeps the player
you already know: it links the old and the new `@account` into one entity, shows
a stable name in the target frame and in chat, and tells you when an account
ID changes.

The addon never counts kills and never writes to chat for other players.
Everything it prints is local to your client.

---

## What you see in game

* **Target frame** — when you point at a player, the name line shows the stable
  name you know them by instead of the current `@account`. Difficulty icon and
  target marker stay where they were. The line under the name is rebuilt as
  `character name + title`.
* **Player icons** — one icon per player, chosen from a library shipped with the
  addon (a curated set plus a lore-friendly pack that reuses ESO's own UI art),
  on the target frame, in the friends list, guild roster, ignore list and
  player browser. With **OdySupportIcons** installed the same icon also floats
  above group members and appears in the Group Finder's group list; with or
  without it, group members also get the icon on the world map and on minimaps
  built on the game's pin manager (Votan's Minimap). Entries on the game's ignore
  list can get a marker icon automatically (a rooster by default); a manually
  assigned icon always wins.
* **Marker above the reticle** — an optional screen-space icon near the crosshair,
  so the target's icon is visible without looking at the target frame. Off by
  default; drag it with the left mouse button wherever it suits you and lock it
  in place. It has its own size (up to 128 px) and can be limited to hostile
  targets, living ones or PvP areas.
* **Chat** — player links get a suffix: `@NewName (OldName)`. The link itself is
  untouched, clicking it still works.
* **Friends, guild roster and group list** — the remembered name is appended to
  the account name in the social lists, `@NewName (OldName)`, and to the
  character name in the Group Finder's group list. The game's own name is never
  replaced, so the list stays sortable and searchable by the real name.
* **PvP kill feed** — messages about kills are annotated with the remembered
  names of both sides.
* **Notifications** — when a known player shows up under a new `@account`, you
  get one line in chat: `ID change: @Old -> @New is Vasya (#12, confirmed)`.

Only the reticle target frame is renamed. Group frames, nameplates and every
other window keep the game's own naming.

---

## Installation

1. Copy the folder `IRememberYou` into
   `Documents/Elder Scrolls Online/live/AddOns/`.
   The result must be `.../AddOns/IRememberYou/IRememberYou.txt`.
2. Start the game, open **Settings → Addons**, enable **I remember you!**.
3. Type `/reloadui`.

No required dependencies. **LibAddonMenu-2.0** adds the settings panel; without
it everything still works through slash commands. **OdySupportIcons** is
optional and is the only source of the 3D icons above group members and of the
player icon in the Group Finder's group list; this addon's own 2D icons, map pins
and remembered-name suffixes work without it.

---

## Opening the player list

The list is where you see and edit everything the addon learned:

* **Settings → Addons → I remember you! → “Open the player list”**;
* or bind a key: **Controls → General → I remember you! → Open the player list**
  (unbound by default);
* or type **`/pa browse`**.

In the list you can:

* search by name, `@account` or character name;
* **resize the window** by dragging its bottom-right corner — the list shows as
  many rows as fit, so a taller window means more players per page;
* click a player to open the **detail panel**: every remembered `@account` with
  when it was last seen, and every character with its alliance and level;
* rename a player to whatever you like (Enter or the button);
* reset the name back to the first remembered `@account`;
* merge two rows that are actually one person (pick the first, pick the second,
  press **Merge**);
* undo the last merge;
* confirm or reject likely links on the **Pending** tab;
* forget players whose retention period has expired.

The detail panel is a single window: clicking another player replaces its
contents, switching tabs or closing the list closes it. Scroll it with the mouse
wheel.

`Escape` closes the window. Its position **and size** are remembered.

---

## Commands

All commands start with `/pa` (alias `/iry`).

| Command | What it does |
| --- | --- |
| `/pa browse` | open the player list |
| `/pa who [name\|id]` | show one player in detail (no argument: current target) |
| `/pa list [n]` | list known players |
| `/pa count` | how many players are remembered |
| `/pa rename <id> <name>` | set your own display name |
| `/pa reset <id>` | back to the first `@account` |
| `/pa forget <id>` | delete one player entity |
| `/pa merge <id> <id>` | merge two entities |
| `/pa undo <id>` | undo a merge (id of the absorbed entity) |
| `/pa pending` | links waiting for confirmation |
| `/pa yes [n]` / `/pa no [n]` | confirm / reject a pending link |
| `/pa purge [days] [confirm]` | preview forgetting old players; add `confirm` to delete |
| `/pa icons [on\|off]` | show or hide every player icon |
| `/pa icon <id> [path\|clear]` | show, set or clear one player's icon |
| `/pa marker [test]` | report the reticle marker, or draw a test picture |
| `/pa debug on\|off` | debug output in chat |

IDs are shown as `#12`; `12`, `#12`, `@Account` and a character name all work
wherever an id is expected.

---

## Where names come from

The addon only learns what the game shows or tells it:

* the reticle target — `@account` and character name together (the main source);
* the group, the friend list, the guild roster and PvP kill feed — as extra
  sources;
* friend and group notifications when the game reports an account rename.

A **new `@account` on a character that is already known** is treated as a
*probable* link: it lands on the **Pending** tab and waits for `/pa yes`, so a
stranger who happens to use a familiar character name cannot silently take over
a record. You can change that with “Accept probable links without asking”.

---

## Settings

**Settings → Addons → I remember you!** (needs LibAddonMenu-2.0)

* **Target frame** — replace name, replace caption, hide caption.
* **Chat** — add the remembered name to player links, annotate PvP kills, and
  append the remembered name in the friends list, guild roster and the Group
  Finder's group list.
* **Data collection** — which sources may teach the addon anything, whether you
  yourself may be recorded (off by default), plus the target polling interval
  (default 1000 ms).
* **Linking** — how loudly to report ID changes, whether probable links are
  accepted automatically, whether conflicts are merged automatically.
* **Player icons** — the master switch, the UI icon size, icons on the world map
  and minimap, the optional marker above the reticle (its own size, drag-and-lock
  placement, dead/hostile/PvP filters), the ignore-list marker and its icon. The
  3D part and the group-list icon are drawn by OdySupportIcons, if it is
  installed.
* **Maintenance** — retention period (`0` = never forget), a “forget old players
  now” button (it only previews until you confirm with a typed word in chat),
  and debug output.

Defaults keep all display features on, accept nothing silently, and never
delete anything by itself.

---

## Limitations

* ESO addons cannot read or write files. There is no import/export; the database
  is the account-wide SavedVariable `IRememberYouSV`.
* A player can only be recognised if the game ever told the addon both their
  account and their character at the same time.
* Friends from your friend list are added even while offline; the character
  shown is their last known one. A friend without character data is stored by
  account name alone.
* The guild roster is loaded lazily by the game, so guild data appears some
  seconds after login.
* Renaming a character does not rename the player: the entity keeps its stable
  name and gains one more character alias.
* In the friends list, guild roster and group list the remembered name shares
  the name column with the game's name: a long one is shortened with an
  ellipsis. Nothing is resized, so the location column never shifts.
* 3D icons above group members and the player icon in the Group Finder's group
  list are drawn by **OdySupportIcons**; without it every 2D icon drawn by this
  addon and the remembered-name suffix still work. OSI's group-window icons are
  enabled by default. The icon library ships with the addon: 81 icons in
  `icons/base`, plus a lore-friendly pack of 82 textures that ESO already ships
  in its own UI art. Both are listed in `core/iconpacks.lua` and chosen in the
  detail panel or with `/pa icon`; the picker pages through them.
* Map icons are available only for **group members**: ESO creates no pins for
  other players. They appear on the world map and on minimaps that use the
  game's own pin manager (Votan's Minimap); minimaps with their own pin system
  (Fyrakin's) are not covered. OdySupportIcons is not required.
* The marker above the reticle is a screen-space overlay, not a 3D icon: it does
  not follow the distance to the target. A close target appears as a picture at
  chest height, a distant one as a picture above the head. Drag it to the spot
  that matches the range you care about; ESO has no distance-to-unit function to
  compute that automatically.
* System messages about a player entering or leaving the area are built by the
  game without player links, so they keep the original `@account` without the
  remembered-name suffix. The PvP kill feed is annotated.

---

## Troubleshooting

* **Nothing changes on the target frame** — check that “Replace the target name”
  is on, and that the addon is enabled after the latest patch.
* **“API version … is outside the supported list”** — the game was updated. The
  addon still tries to work; check for a newer release.
* **No settings panel** — LibAddonMenu-2.0 is not installed. Use the slash
  commands instead.
* **No player icon in the Group Finder's group list** — that icon is drawn by
  OdySupportIcons, not by this addon. The remembered-name suffix works without
  it; check OSI's group-window icon options.
* **A stranger is showing my friend's name** — open the list, select the wrong
  row and use **Reset**, or `/pa undo` the merge the addon made.
* **You are in the list yourself** — from 0.2.1 on the addon ignores you. An old
  row is not deleted automatically: remove it with `/pa forget <id>`.
* **The reticle marker floats beside the head** — it is a fixed screen picture, not
  a 3D icon. Check “Move the marker”, drag it to where you expect it at
  your usual fighting distance, then clear the checkbox.
* **The marker is gone while unlocked** — check the icon master switch; the drag
  mode ignores the display filters and the hidden reticle but not `showIcons`.
* **Kill feed names are not annotated** — check “Annotate PvP kill messages” in
  the Chat section and that the player is already remembered. System enter/leave
  messages are never annotated: the game gives them no player link.

---

## Changelog

**0.5.1**
* six new icons in the shipped library: `doge-smile`, `horse`,
  `imperial-soldier`, `risitas-form`, `templar` and `zmeigorinich` (81 icons in
  `icons/base`);
* the doge and horse pictures were cut out, so their background is transparent;
  the rest keep the transparency of the source PNGs.

**0.5.0**
* player icons on the world map and on minimaps built on the game's pin manager
  (Votan's Minimap); only group members have pins, so only they are covered;
* the remembered name is appended in the Group Finder's group list, after the
  numbered character name; the group index and the game's own name stay where
  they were;
* the group-list player icon is drawn by OdySupportIcons when it is installed;
  without it the suffix, the map pins and every 2D icon drawn by this addon
  still work;
* OdySupportIcons and LibAddonMenu-2.0 remain optional.

**0.4.0**
* one icon per player across the target frame, friends list, guild roster,
  ignore list and player browser;
* icons are assigned manually from the detail panel or `/pa icon`, and the
  whole set can be switched off with `/pa icons off` or the settings;
* entries on the game's ignore list can be marked with a dedicated icon;
* an optional marker above the reticle, disabled by the same master switch: its
  own size, drag-and-lock placement, and filters for dead, hostile and PvP-only
  targets; group members keep only their 3D OSI icon, without a second screen
  copy;
* the PvP kill feed annotates both names even when a chat addon re-registers the
  formatter or the line is coloured by the battleground team;
* forgetting old players needs a typed confirmation (`/pa purge <days> confirm`);
  the settings and browser buttons only preview what would be deleted;
* 3D icons above group members through **OdySupportIcons**, including its own
  settings and saved icons being preserved. Players outside the group get their
  icon in the UI only: ESO does not expose their world position, so no addon can
  draw a 3D icon over them.

**0.3.0**
* the player list is resizable; the number of rows follows the window height;
* the list comes up in the foreground instead of behind other windows;
* clicking a player opens one reusable detail panel with all accounts and all
  characters, including alliance and level;
* each character's alliance is stored and updated from later observations;
* the remembered name is appended in the friends list and the guild roster
  (new setting, on by default).

**0.2.1**
* yourself is no longer recorded (toggle in the settings panel);
* friends are remembered even while offline;
* `/pa forget <id>` removes a single player.

**0.2.0**
* browsable player list (search, rename, merge, undo, pending, purge);
* settings panel (LibAddonMenu-2.0);
* keybind to open the list;
* retention is off by default;
* Escape closes the list.

**0.1.0**
* first working version: entity store, target frame, chat links, kill feed,
  rename detection, notifications, slash commands.

---

## Files

```
IRememberYou/
  IRememberYou.txt        manifest
  IRememberYou.lua        bootstrap
  bindings.xml            keybind to open the list
  README.md               this file (English)
  README.ru.md            this file (Russian)
  DEVELOPMENT.md          internals (English)
  DEVELOPMENT.ru.md       internals (Russian)
  core/                   constants, store, resolver, printing, icons, blacklist
  icons/                  the curated DDS icon library (listed in core/iconpacks.lua)
  track/                  observation, rename detection, target poll
  ui/                     target frame, chat, friends/guild/group lists, map, browser, icon picker, settings, commands
  lang/                   English and Russian strings
```

Russian localization is automatic: the addon uses `lang/ru.lua` when the game
client language is Russian.
