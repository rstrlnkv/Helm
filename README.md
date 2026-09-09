# Helm

Tools for your Mac. A modular utility suite for macOS in the spirit of PowerToys —
a menu-bar panel, a settings window, and the modules you choose to keep.

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)
[![Release](https://img.shields.io/github/v/release/rstrlnkv/Helm?include_prereleases)](https://github.com/rstrlnkv/Helm/releases)
[![Downloads](https://img.shields.io/github/downloads/rstrlnkv/Helm/total)](https://github.com/rstrlnkv/Helm/releases)
[![Licence](https://img.shields.io/github/license/rstrlnkv/Helm)](LICENSE)

## Install

Grab the `.dmg` from the [latest release](https://github.com/rstrlnkv/Helm/releases),
drag Helm into Applications, then clear the quarantine once (the build is ad-hoc
signed):

```bash
xattr -dr com.apple.quarantine /Applications/Helm.app
```

From then on Helm updates itself: **About Helm → Update & Relaunch** verifies the
download against the SHA-256 the release publishes in its notes, swaps the bundle and
restarts — no Gatekeeper prompts, no manual steps. A release that publishes no digest,
or one that disagrees, is never installed silently: the release page opens instead.

## Modules

| Module | What it does |
|---|---|
| **Keep Awake** | Prevent sleep manually, by timer (menu-bar countdown ring + remaining time), or automatically (external display, power, chosen apps). Closed-lid mode, battery guard, pointer jiggle, global hotkey. |
| **VPN** | Connect/disconnect system VPNs, per-app auto-connect rules, silent L2TP/IPSec connect. |
| **Uninstaller** | Remove apps together with their leftovers (caches, preferences, containers, …) — everything goes to the Trash. A Leftovers tab finds files from apps that are already gone. |
| **Homebrew** | Installed formulae/casks with descriptions, updates (per-package and all), search & install, live console for long operations, in-app Homebrew installer. |
| **Login Items & Extensions** | Everything that loads with the system — launch agents, settings files, plug-ins — marked In use / System / Leftover; leftovers removable. |
| **Disk** | What is taking up room: a sunburst ring over the volume, firmlink-aware so an APFS volume group is not counted twice; folders open under the names Finder gives them, and anything you want gone collects in one list before it goes to the Trash. |
| **Duplicates** | Files that exist more than once, from 1 MB up, matched by content rather than by name. The copy that stays is the one that was there first — by the Date Added the Finder shows — not the one an alphabetical sort happened to put on top. Hard links are one file and are never offered. |
| **Autopilot** | Folders that keep themselves in order. Rules on name, extension, kind, size, dates, Finder tag and where a file was downloaded from; actions to move, sort into subfolders by kind or by month, rename by pattern, tag, or trash. A rule is shown against the folder's real files before it is switched on, nothing is ever overwritten, and no file is acted on twice. No script action, deliberately — the rules live in a plist any process can write. |
| **Hosts & Keys** | The SSH config as a list: hosts from `~/.ssh/config` with the identity each uses, keys with their type and fingerprint, and which of them the agent is holding. The file's own text stays canonical — anything Helm does not parse, comments and `Include` lines among it, is written back byte for byte. |
| **Keyboard** | Fixes a word typed in the wrong keyboard layout — `ghbdtn` becomes `привет` — and moves the input source with it. Only when the word is not a word as typed and is one once swapped; terminals and password managers are left alone. Abbreviations expand at the same boundary. Needs Accessibility. |

Everything is localized in eight languages: English, 中文, Español, Français,
Deutsch, 日本語, Русский, Português.

## Requirements

macOS 26 or later, on Apple Silicon: the package declares `.macOS("26.0")` and the
bundle a release ships is arm64 only. There is no Intel build and no back-deployment.

Permissions are asked for where they are turned on, not at first launch: Accessibility
for Keyboard and for Keep Awake's pointer jiggle, Full Disk Access for the modules that
read protected folders. Because the build is signed ad-hoc, macOS ties a grant to the
exact binary — every reinstall costs both toggles again.

Releases go to the **Dev** channel first and graduate to **Beta** once the count of
known problems reaches zero; the switch is About Helm → Update channel. The channels,
the version scheme and the shape of a tag are described in the Release section of
[ARCHITECTURE.md](ARCHITECTURE.md).

## Build from source

Requires Xcode with the macOS 26 SDK and a Swift 6 toolchain.

```bash
swift test                      # the unit suite; it prints its own count
bash Scripts/package-app.sh     # build + sign → $TMPDIR/helm-package/Helm.app
```

Install from the staged path the script prints, not from the copy it leaves in `build/`
for inspection, and keep the checkout out from under a file provider (iCloud Drive,
Dropbox, and the like): a provider stamps `com.apple.FinderInfo` onto the bundles it
manages and `codesign` refuses a bundle carrying it. Everything else about working in
this tree — release packaging, versioning, what a person does by hand — is in
[CLAUDE.md](CLAUDE.md).

## Licence

GPL-3.0 — see [LICENSE](LICENSE). Third-party artwork and its terms are in
[NOTICE.md](NOTICE.md).
