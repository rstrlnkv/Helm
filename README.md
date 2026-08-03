# Helm

Tools for your Mac. A modular menu-bar utility suite for macOS 26+ (Apple Silicon),
in the spirit of PowerToys.

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
| **Keyboard** | Fixes a word typed in the wrong keyboard layout — `ghbdtn` becomes `привет` — and moves the input source with it. Only when the word is not a word as typed and is one once swapped; terminals and password managers are left alone. Abbreviations expand at the same boundary. Needs Accessibility. |

Everything is localized in eight languages: English, 中文, Español, Français,
Deutsch, 日本語, Русский, Português.

## Channels

Releases ship to the **Dev** channel first (`vX.Y.Z-dev.N` prereleases, always
logging to `~/Library/Logs/Helm/helm.log`) and graduate to **Beta** when the
known-problem count reaches zero. Switch channels in About. The slower channel
is Beta rather than Stable because Helm is before 1.0 and nothing here has
earned that word yet.

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

## Build from source

Requires Xcode (macOS 26 SDK) and Swift 6.

```bash
swift test                      # 1911 unit tests
bash Scripts/package-app.sh     # build + sign → $TMPDIR/helm-package/Helm.app
```

The signed bundle is assembled and signed in `$TMPDIR/helm-package`, outside the
checkout; the copy left in `build/` is for inspection only — install and package from
the staged path. **Keep the checkout out from under a file provider** (iCloud Drive,
Dropbox, and the like): a provider stamps `com.apple.FinderInfo` onto the bundles it
manages and `codesign` refuses a bundle carrying it, so signing succeeds or fails by
luck.

Release packaging: `Scripts/make-dmg.sh` (manual install) and `Scripts/make-zip.sh`
(the asset the in-app updater consumes).

Versioning is SemVer-shaped: MAJOR for a milestone, MINOR for new or polished
capability, PATCH for fixes only, and every release bumps the number — the
updater compares versions, so two releases sharing one are invisible to it.
Prereleases are the `-dev.N` lane and sort below their own release
(`0.7.0` > `0.7.0-dev.2` > `0.6.1`).

## Licence

GPL-3.0 — see [LICENSE](LICENSE). Third-party artwork and its terms are in
[NOTICE.md](NOTICE.md).
