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
  addon, on the target frame, in the friends list, guild roster, ignore list and
  player browser. With **OdySupportIcons** installed the same icon also floats
  above group members and the reticle target. Entries on the game's ignore list
  can get a marker icon automatically (a rooster by default); a manually assigned
  icon always wins.
* **Chat** — player links get a suffix: `@NewName (OldName)`. The link itself is
  untouched, clicking it still works.
* **Friends and guild roster** — the remembered name is appended to the account
  name, `@NewName (OldName)`. The account name itself is never replaced, so the
  list stays sortable and searchable by the real name.
* **PvP kill feed** — messages about kills are annotated with the remembered
  names of both sides.
* **Notifications** — when a known player shows up under a new `@account`, you
  get one line in chat: `ID change: @Old -> @New is Vasya (#12, confirmed)`.

Only the reticle target frame is touched. Group frames, nameplates and every
other window keep the game's own naming.

---

## Installation

1. Copy the folder `IRememberYou` into
   `Documents/Elder Scrolls Online/live/AddOns/`.
   The result must be `.../AddOns/IRememberYou/IRememberYou.txt`.
2. Start the game, open **Settings → Addons**, enable **I remember you!**.
3. Type `/reloadui`.

No dependencies. If **LibAddonMenu-2.0** is installed, the addon also gets a
settings panel; without it everything still works through slash commands.

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
| `/pa purge [days]` | forget old players without custom names |
| `/pa icons [on\|off]` | show or hide every player icon |
| `/pa icon <id> [path\|clear]` | show, set or clear one player's icon |
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
  append the remembered name in the friends list and guild roster.
* **Data collection** — which sources may teach the addon anything, whether you
  yourself may be recorded (off by default), plus the target polling interval
  (default 1000 ms).
* **Linking** — how loudly to report ID changes, whether probable links are
  accepted automatically, whether conflicts are merged automatically.
* **Player icons** — the master switch, the UI icon size, the ignore-list marker
  and its icon. The 3D part is drawn by OdySupportIcons, if it is installed.
* **Maintenance** — retention period (`0` = never forget), a “forget old players
  now” button, and debug output.

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
* In the friends list and guild roster the remembered name shares the name
  column with the account: a long one is shortened with an ellipsis. Nothing is
  resized, so the location column never shifts.
* 3D icons need **OdySupportIcons**; without it every 2D surface still works.
  The icon library ships with the addon: 75 icons in `icons/base`, listed in
  `core/iconpacks.lua` and chosen in the detail panel or with `/pa icon`.

---

## Troubleshooting

* **Nothing changes on the target frame** — check that “Replace the target name”
  is on, and that the addon is enabled after the latest patch.
* **“API version … is outside the supported list”** — the game was updated. The
  addon still tries to work; check for a newer release.
* **No settings panel** — LibAddonMenu-2.0 is not installed. Use the slash
  commands instead.
* **A stranger is showing my friend's name** — open the list, select the wrong
  row and use **Reset**, or `/pa undo` the merge the addon made.
* **You are in the list yourself** — from 0.2.1 on the addon ignores you. An old
  row is not deleted automatically: remove it with `/pa forget <id>`.

---

## Changelog

**0.4.0**
* one icon per player across the target frame, friends list, guild roster,
  ignore list and player browser;
* icons are assigned manually from the detail panel or `/pa icon`, and the
  whole set can be switched off with `/pa icons off` or the settings;
* entries on the game's ignore list can be marked with a dedicated icon;
* 3D icons above group members and the reticle target through
  **OdySupportIcons**, including its own settings and saved icons being
  preserved.

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
  ui/                     target frame, chat, friends/guild list, browser, icon picker, settings, commands
  lang/                   English and Russian strings
```

Russian localization is automatic: the addon uses `lang/ru.lua` when the game
client language is Russian.
