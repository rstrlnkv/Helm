# Changelog

All notable changes to Helm are documented here. The format is loosely based on
[Keep a Changelog](https://keepachangelog.com/). Version-bump rules: see
[VERSIONING.md](VERSIONING.md) — MAJOR = global changes, MINOR = new/polished
features, PATCH = fixes.

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
