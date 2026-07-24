# Changelog

All notable changes to Helm are documented here. The format is loosely based on
[Keep a Changelog](https://keepachangelog.com/). Version-bump rules: see
[VERSIONING.md](VERSIONING.md) — MAJOR = global changes, MINOR = new/polished
features, PATCH = fixes.

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

[0.3.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.3.0
[0.2.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.2.0
