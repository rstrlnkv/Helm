# Helm

Tools for your Mac. A modular menu-bar utility suite for macOS 26+ (Apple Silicon),
in the spirit of PowerToys.

## Modules

| Module | What it does |
|---|---|
| **Keep Awake** | Prevent sleep manually, by timer (menu-bar countdown ring + remaining time), or automatically (external display, power, chosen apps). Closed-lid mode, battery guard, pointer jiggle, global hotkey. |
| **VPN** | Connect/disconnect system VPNs, per-app auto-connect rules, silent L2TP/IPSec connect. |
| **App Uninstaller** | Remove apps together with their leftovers (caches, preferences, containers, …) — everything goes to the Trash. A Leftovers tab finds files from apps that are already gone. |
| **Homebrew** | Installed formulae/casks with descriptions, updates (per-package and all), search & install, live console for long operations, in-app Homebrew installer. |
| **Login Items & Extensions** | Everything that loads with the system — launch agents, settings files, plug-ins — marked In use / System / Leftover; leftovers removable. |

Everything is localized in eight languages: English, 中文, Español, Français,
Deutsch, 日本語, Русский, Português.

## Channels

Releases ship to the **Dev** channel first (`vX.Y.Z-dev.N` prereleases, always
logging to `~/Library/Logs/Helm/helm.log`) and graduate to **Stable** when the
known-problem count reaches zero. Switch channels in About.

## Install

Grab the `.dmg` from the [latest release](https://github.com/rstrlnkv/Helm/releases),
drag Helm into Applications, then clear the quarantine once (the build is ad-hoc
signed):

```bash
xattr -dr com.apple.quarantine /Applications/Helm.app
```

From then on Helm updates itself: **About Helm → Update & Relaunch** downloads the
release, swaps the bundle and restarts — no Gatekeeper prompts, no manual steps.

## Build from source

Requires Xcode (macOS 26 SDK) and Swift 6.

```bash
swift test                      # 108 unit tests
bash Scripts/package-app.sh     # build → build/Helm.app (ad-hoc signed)
```

Release packaging: `Scripts/make-dmg.sh` (manual install) and `Scripts/make-zip.sh`
(the asset the in-app updater consumes). Versioning rules: [VERSIONING.md](VERSIONING.md).

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) — the module system (descriptor/engine
split, ports, transport), the UI shell, and the hard-won platform notes.
