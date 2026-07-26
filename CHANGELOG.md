# Changelog

All notable changes to Helm are documented here. The format is loosely based on
[Keep a Changelog](https://keepachangelog.com/). Version-bump rules: see
[VERSIONING.md](VERSIONING.md) — MAJOR = global changes, MINOR = new/polished
features, PATCH = fixes.

## [0.7.1] — 2026-07-26

### Fixed
- The leftovers matcher pasted a bundle id or display name straight onto a
  shared `~/Library` folder. An empty `CFBundleDisplayName` — a free-form plist
  string — therefore claimed `Application Support` itself, an empty id collapsed
  every glob to `*`, and a name carrying `..` walked out of the folder entirely;
  all three arrived pre-ticked next to a Trash button. Candidates are now
  refused unless they sit strictly inside their own kind folder, and both
  engines re-check the scope before removing anything, rather than trusting the
  view model that built the list.
- Leftovers matched by display name are no longer pre-selected and carry a "by
  name" badge; a guess costs a click to accept instead of a click to refuse.
- The Keep Awake clamshell rule was written into `/etc/sudoers.d` through an
  AppleScript-quoted shell string built from the account name, was never checked
  with `visudo`, and was never removed. It is now staged from Swift, validated,
  installed with `install(1)`, and taken back out when the option is switched
  off.
- `helm.log` recorded VPN connection names, app names and absolute home paths.
  It uses stable short tags and `~`-relative paths now.
- Quitting an app disconnected whatever VPN its rule pointed at *now*, so a quit
  with no matching launch, a repeated quit, or a rule remapped under a running
  app tore down a connection Helm never raised.
- `brew search` no longer prints its `==> Casks` header, so every cask was
  labelled a formula and installed without `--cask`. Helm asks one kind at a
  time.
- An extension host was matched by prefix without a separator, blaming
  `at.obdev.littlesnitch`'s extension on `at.obdev.littlesnitchmini` and hiding
  the real reason.
- An incomplete IOKit power dictionary was reported as 0%, which the battery
  guard read as a critical charge and used to end the Keep Awake session.
- `package-app.sh` signed the bundle inside the repo, where a file provider
  re-stamps `com.apple.FinderInfo` faster than `xattr -c` clears it: signing
  succeeded or failed by luck, and an unsigned bundle has no cdhash for TCC to
  bind Full Disk Access to. The bundle is now assembled and signed outside the
  synced tree, and the signature is verified before the script reports success.
- The Homebrew installer ran as `eval "$(curl …)"`, which exits 0 on a failed
  download and reported a successful install of nothing.
- The disk confirmation listed localized folder names, which cannot tell
  `/Library` from `~/Library`; it lists paths. The scan cache directory is
  created 0700.
- Three screens announced "Removed — N freed" whether or not macOS had refused,
  and threw the failure list away. `HelmRemovalOutcome` names what stayed and
  why, with a way to reveal it and to grant the missing permission.
- "Select all" in Login Items & Extensions ticked rows hidden by the filter,
  and the counter counted them too; both now follow what is on screen, and
  hiding a kind drops its selections.
- The Disk Space basket was a count with no list: its contents can be opened
  and cleared item by item, and the confirmation names what it is about to
  remove.
- Homebrew removed a package — a whole app, for a cask — on a single click.
  It asks first, like every other destructive action in Helm.
- The permission notice was shown once ever: the "already shown" flag was set
  before the check, so a first launch that happened to have access silenced it
  for good. It is keyed to the version now, which is what an ad-hoc build
  needs, and every page re-reads permissions when Helm returns to the front.
- A VPN rule naming a connection that no longer exists says so instead of
  silently never firing.
- The icon menu listed disabled modules, whose pages only say they are disabled.
- Opening the Uninstaller sized every installed bundle — nine seconds of disk
  walking on this Mac — and the leftovers scan paid it again for data it threw
  away; it asks for bundle ids only.

### Added
- Each item in Login Items & Extensions offers what the system actually allows:
  turn off (any non-Apple agent), delete (only where the folder is writable —
  the user's own Library, not /Library), reveal, or a link to System Settings
  for extensions. Deleting something in use asks first and says the app may
  recreate it.
- Login items can be turned off rather than only deleted, through launchd's own
  disabled list (`launchctl disable gui/<uid>`) — no files are moved, the state
  survives reboots, needs no admin, and System Settings shows the same thing.
  Offered only for user-domain agents that are not Apple's.
- A kind filter in Login Items & Extensions, so system extensions (or anything
  else) can be hidden while reviewing.
- Login Items & Extensions lists system extensions themselves, with the status
  their host app implies. They are never selectable: Helm cannot remove an
  extension by moving a file, so the row opens the system pane instead.
- Keep Awake's per-app rules take conditions: an app can hold the Mac awake
  always, or only with an external display, only on power, or both. Existing
  app lists migrate to unconditional rules.
- `PermissionNeed` maps each gated feature to the grant it needs. The settings
  section is generated from it, and Disk Space, App Uninstaller and Login Items
  & Extensions warn in place when Full Disk Access is missing, the way Keep
  Awake does for the pointer nudge.

### Removed
- `module.app.panelLayout`, left in defaults by the removed grid layout, is
  purged at launch.
- Dead code: an unused centred-message modifier, the `contentFade` motion token,
  the scanner's superseded ResultBox, an Apple-bundle check the vendor rule
  replaced, and the About page's now-unused opener.

### Fixed
- The Uninstaller's leftovers scan listed the files of installed apps, with
  everything pre-selected. It decided "installed" from a listing of
  /Applications, which sees neither apps one folder down (Adobe Acrobat DC/)
  nor helpers nested inside other bundles (OneDrive.app carries the SharePoint
  helper). It now asks LaunchServices, and nothing is pre-selected: on this
  machine 112 entries belonged to apps the system does find.
- Keep Awake's status strip was static: the page held its view model in a plain
  property, so SwiftUI never saw the published state change and the figures
  froze at whatever they were when the page opened.
- "Leftovers" filters by status rather than by what Helm can delete, so an
  extension whose app is gone appears there too.
- Accessibility is now listed among the permissions, and Keep Awake flags it at
  the pointer-nudge setting. macOS drops synthetic mouse events from an
  untrusted app, so that switch could be on while nothing moved, with nothing
  in the app saying why.
- The module order is applied everywhere it should be. The sidebar and the
  icon's menu listed modules in registry order while the panel and the settings
  list used the arranged one; the sidebar now sorts each category by the same
  order. The setting is renamed to "Module order" to say so.
- An abandoned drag no longer strands the settings list. The order was written
  back only in `performDrop`, which never fires for a drag released outside the
  list — so the list kept showing an order nothing else knew about, and the
  dragged row stayed dimmed. The order is now persisted as it moves, and
  reopening the page re-reads it.

### Changed
- Per-app rules are one row each — the app, one menu for when the rule applies,
  and the remove button — in both Keep Awake and VPN. The two switches they
  replace were never independent: "display and power" means both, and a VPN
  rule with neither switch on does nothing, which the menu can now say.
- The system-extension count left the Permissions section. It was neither a
  permission nor Helm's, and a bare number could not tell you which app it
  meant; the module named after extensions lists them by name instead.
- Settings sections follow how often they are needed: general, module order,
  menu-bar icon and panel first; permissions and diagnostics last. They used to
  sit in the reverse order, with troubleshooting above appearance.
- Keep Awake gathers all four automatic rules — external display, power, closed
  lid, low battery — into one Automation section; they were spread across three
  sections with unrelated ones between them. The global shortcut, set once,
  moved to the end.
- One container treatment across the app. Helm's own cards dropped their border
  to match the macOS grouped-form sections that make up half the app's
  surfaces — the About page had been showing a bordered card and an unbordered
  one side by side.
- A module's metric strip now sits inside the form as its first section, so it
  shares the system's width instead of overhanging the rows below it at the
  window's own margin.

## [0.7.0] — 2026-07-26

### Added
- **Disk Space module** — a sunburst ring showing what filled the disk. Scans a
  whole volume or any folder with `getattrlistbulk` and a parallel walk (a
  310 GB volume in about a minute), draws the ring while the scan is still
  running, and drills in by clicking a wedge. Folders carry the names Finder
  gives them in the user's language. Anything to remove collects in one list
  and goes to the Trash together, and system paths can never be collected.
- **Disk Space recommendations** — known cache folders past 100 MB, Downloads
  items untouched for a month, and files over 1 GB untouched for half a year,
  ranked by size behind one toolbar button.
- **Disk Space remembers the last scan** — the tree is written to Application
  Support and restored on open, labelled with when it was measured; deleting
  updates the tree in place instead of re-walking the disk.
- **Login Items & Extensions module** — everything that loads with the Mac,
  marked in use, system, or leftover. Only leftovers can be selected.
- **App Uninstaller: two-step flow** — tick the apps, then review the files
  found for each before anything moves. Running apps are flagged and removed
  only with an explicit force quit.
- **Permissions section** — whether Helm has Full Disk Access, plus installed
  system extensions read from `systemextensionsctl`. When a file cannot be
  moved, Helm names the real reason and links to the right setting.
- **Module reordering** — drag modules into the order they take in the panel.
- **Diagnostics** — an optional log of what Helm does, reachable from Settings.
  Dev builds always log.
- Update channels (Stable / Dev), and a dev-first release flow: see
  [VERSIONING.md](VERSIONING.md).

### Changed
- Every screen leads with its icon and its own key figures, on one layout.
- Sizes are formatted once for the whole app: 1000 to the kilobyte as Finder
  counts, and in the user's own units — "432,95 ГБ", not "432,95 GB".
- Counted nouns follow each language's rules, including Russian's three forms.
- Wording reviewed across all 334 strings: shorter labels, one name per thing,
  duplicate labels split apart, explanations cut to their point.

### Fixed
- VPN rows no longer spin forever; the status is polled until it settles.
- Uninstalling reports what actually happened: real failure reasons instead of
  guesses, no duplicate paths queued twice, and Reveal falls back to the
  enclosing folder when the item is already gone.
- The Settings window no longer stretches to the height of the screen.
- Sections no longer flicker when a disclosure finishes opening.

## [0.6.3] — 2026-07-25

### Changed
- Redesigned About: the icon sits in a bezel that turns while updates are
  checked, version and build read as instrument dials, and the update controls
  live in one card.

### Fixed
- The update status no longer claims you are current when no check has run — it
  shows when the last check happened.

## [0.6.2] — 2026-07-25

### Added
- Update channels: stay on finished releases, or switch to Dev in About to get
  early builds.

## [0.6.1] — 2026-07-25

### Fixed
- VPN rows no longer show an endless spinner: the status is re-checked until the
  connection settles.

## [0.6.0] — 2026-07-25

### Added
- **App Uninstaller module** — list installed apps, scan their leftovers
  (caches, preferences, containers, logs, …) by bundle id and exact name, and
  move everything to the Trash; a Leftovers tab finds files from apps that are
  already gone. User-domain only, always reversible.
- **Homebrew module** — installed formulae and casks with one-line
  descriptions, updates with per-package and bulk upgrade, search and install,
  a live console for long operations, and an in-app Homebrew installer for
  machines without brew.
- **Menu-bar timer** — while a timer runs the ring empties clockwise, with an
  optional remaining-time label and a dedicated timer colour.
- **Panel** — utility modules collapse behind an animated Utilities row;
  optional Settings/Quit buttons; the icon's right-click menu jumps straight to
  any module's settings page.
- In-app changelog is now structured, localized in all eight languages, and
  badged New/Upd/Fix.

### Changed
- Keep Awake's ⋯ controls open inline in the card (custom timer with a
  durations menu and free-form entry, automation toggles, Stop button in the
  countdown row); the module toggle turns orange while an automation rule is
  holding the session.
- Settings window: the app pane is now Settings; utility pages get a larger
  window; module lists use the macOS 26 inset style; copy reviewed in all
  languages.
- Store writes now announce themselves, keeping the panel and the Settings
  window in sync in both directions.

### Fixed
- The panel no longer jumps or slides when disclosures open (window is sized
  once per open; content animates inside it).
- The menu-bar countdown ticks reliably (state was read before it landed).
- brew calls and filesystem scans no longer stall the app's async machinery.
- The updater's retry button works after a failed install.

## [0.5.1] — 2026-07-24

### Fixed
- Silent update now cleans up its temp files (downloaded zip, unzipped bundle,
  swap script) after installing, leaving nothing behind.

## [0.5.0] — 2026-07-24

### Added
- **Silent in-app updates** — "Update & Relaunch" downloads the new version,
  installs it into place, and relaunches, with no manual drag and no Gatekeeper
  prompt (the app downloads the release zip itself, so it isn't quarantined).

## [0.4.0] — 2026-07-24

### Added
- **Custom active icon for Keep Awake** — Settings → Keep Awake → Active icon lets
  you pick a shape shown in the menu bar (in the active tint) while Keep Awake is on.

### Changed
- **Reworked menu-bar icon pickers** — glyph-forward swatches with the selected
  option's name below the row; the size picker previews each shape at its real size.
  Preview glyphs are now theme-neutral (match the menu-bar icon) instead of blue.
- **Icon sizes** are now Tiny/Very small/Small/Medium/Large (9–18pt): dropped the
  largest sizes, added smaller ones, and replaced XS/S/M codes with words.

### Removed
- The "Helm" (ship's wheel) menu-bar glyph.

## [0.3.0] — 2026-07-24

### Changed
- **Update check moved into About** — the version status and "Check for Updates"
  button now live in Settings → About, next to the version, instead of a separate
  section under General.

### Fixed
- **Panel toggle stuck off while a module was active.** A module that turned on
  automatically at launch (e.g. Keep Awake on power) held correctly but its panel
  toggle read off, because the view model subscribed to the engine's event stream
  after the initial state was emitted. The transport now replays the last state to
  late subscribers.

## [0.2.0] — 2026-07-24

### Added
- **GitHub updates** — Helm checks the public repo's latest release once a day
  and from Settings → General → Updates, surfacing a download link when a newer
  version is out.
- **What's New** — About → "What's New" renders this changelog in-app; About now
  shows the version, build number, and enabled-module count.

## [0.1.0] — 2026-07-23

### Added
- **Keep Awake module** — prevent sleep manually, by timer (presets + custom
  minutes with a live countdown), or automatically when an external display or
  power is connected, or when chosen apps run. Optional "keep display on",
  pointer jiggle, closed-lid (clamshell) mode via `pmset`, battery guard, a
  global toggle hotkey, and a configurable menu-bar tint color.
- **VPN module** — connect/disconnect system VPNs (`scutil`), per-app
  auto-connect rules, and silent L2TP/IPSec connect via a one-time keychain
  read cached in Helm's own keychain.
- **Menu-bar panel** — Control Center-style, per-module tiles, screen-edge
  clamping, quick automation toggles in a popover.
- **Settings** — System Settings-style window (AppKit split view), per-module
  enable switches, menu-bar icon shape/size, launch at login.
- **Liquid Glass app icon** built with Icon Composer.
- **Localization** — English, 中文, Español, Français, Deutsch, 日本語,
  Русский, Português.

[0.6.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.6.0
[0.5.1]: https://github.com/rstrlnkv/Helm/releases/tag/v0.5.1
[0.5.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.5.0
[0.4.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.4.0
[0.3.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.3.0
[0.2.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.2.0
[0.1.0]: https://github.com/rstrlnkv/Helm
