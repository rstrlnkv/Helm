# Helm — architecture

Helm is a menu-bar utility suite for macOS: one accessory application that hosts its independent modules (the directories of `Sources/Modules`) and Tweaks, one more registered in `Sources/HelmApp`. A module is a headless engine and a settings page with its model, which calls the engine's methods. Around them stand four foundation targets: `Sources/HelmContract` for what crosses the engine/host boundary, `Sources/HelmRuntime` for plumbing without UI, `Sources/HelmUI` for the design system and the strings, and `Sources/HelmLaunch` for the one thing Swift cannot express. `Sources/HelmApp` is the executable that owns the window, the panel and the status item, with its words in `Sources/HelmAppStrings`. `Package.swift` declares the whole shape; the build holds the boundaries where it can, and `TheBoundariesTheBuildCannotHoldTests` holds the import lines it cannot.

## How these pages are kept

A page per subject, linked from the hub with one purpose line; a page's H1 is its link text and its file name is that H1 in UpperCamelCase. Every heading is unique across the hub and the pages, and is addressed as `ARCHITECTURE.md § Localization`, say (a bare `§ Localization`, inside these pages); "see X" and "above" are not addresses. A reason tied to one file lives in that file's doc comment, not on a page.

## Where things are

| What a change touches | Where it lives |
|---|---|
| a module's pure logic | a `Logic` folder under `Sources/Modules/<Module>/Engine/`, where it has any |
| its engine, its store | `Sources/Modules/<Module>/Engine/` |
| its screen, and its descriptor with the module's tint and glyph | `Sources/Modules/<Module>/UI/` |
| a tweak's engine, and its descriptor with the rows its card is made of | `Sources/Tweaks/<Tweak>/Engine/` and `Sources/Tweaks/<Tweak>/UI/` |
| a module's kept tests, each directory flagged on its row in `Package.swift` | `Tests/Modules/` |
| what crosses the engine/host boundary | `Sources/HelmContract/` |
| plumbing two modules both want | `Sources/HelmRuntime/` |
| a string or a control two modules both draw | `Sources/HelmUI/` |
| a token — surface, motion, colour, radius | `Sources/HelmUI/DesignSystem/` |
| the translations of the kit's shared words | `Sources/HelmUI/` |
| the host's words, the changelog's entries and their translations | `Sources/HelmAppStrings/` |
| the window, panel, status item, settings | `Sources/HelmApp/` |
| plumbing a test target wants | `Tests/Support/` |
| what a screen reads as, in numbers | `Sources/HelmReadout/` |
| the kit's components in every state, to look at | `Sources/HelmShowcase/` |
| build, sign, package, disk image, screen stills (`shoot.sh`) | `Scripts/` |

## The map

Six hubs follow, each a list of pages, and two tables after them that cross the modules.

### The shell

- [The menu-bar panel](Architecture/TheMenuBarPanel.md) — the window, chrome and card of the panel, the pure grid and drag rules beneath them, and the rule that picks what the status item shows.
- [The Settings window](Architecture/TheSettingsWindow.md) — the card shell, the sidebar as a stored arrangement, the hosting controllers, the base class of a host-owned window and how a path is revealed in Finder.
- [The page header](Architecture/ThePageHeader.md) — the header row in the card that carries a page's name and controls.

### The shared layers

- [Targets](Architecture/Targets.md) — the package's targets, what each holds and which may see which, and what Helm deliberately leaves out.
- [Localization](Architecture/Localization.md) — the catalogs and their keys, the shared words, the lookup, the guards, and the helpers that keep the language the app's own.
- [Design system](Architecture/DesignSystem.md) — what `Sources/HelmUI/DesignSystem/` holds and the rules for its tokens, surfaces, ladders, type, ink, motion and the showcase.
- [Stored settings](Architecture/StoredSettings.md) — a stored value nobody else may write, and a number that came from a file.
- [State and lifetime](Architecture/StateAndLifetime.md) — what outlives a page or a thing it points at, and a value read back whole.
- [Diagnostics log](Architecture/DiagnosticsLog.md) — the log file and its policy, the activity registry, the memory trail and the log pane.

### Gates and removal

- [The gates](Architecture/TheGates.md) — the four types that answer where a path may be reached, how a walk asks them, and how Full Disk Access is probed.
- [Removal](Architecture/Removal.md) — the one batch every removal goes through and the refusals it reports.
- [Background scans](Architecture/BackgroundScans.md) — the modules that can measure unattended and how the list and the capability are tied together.
- [Giving everything back](Architecture/GivingEverythingBack.md) — what a reset hands back outside Helm's own folders, what it cannot, and the order of its steps.

### Running things

- [Running other programs](Architecture/RunningOtherPrograms.md) — launching a tool, bounding how many are out, reading what it prints, running one as root, and why running applications are read on the main thread only.

### The modules

- [Module pattern](Architecture/ModulePattern.md) — how a module is built from two source directories and the test directories it keeps, and what holds its parts apart.

A tweak is a second, smaller kind of part: `Sources/Tweaks/<Tweak>/Engine` and `UI`, declared by a `Tweak` row in `Package.swift`, with no menu-bar presence, hotkey, scan or panel widget. The same three holds keep it apart from every module and every other tweak (Architecture/ModulePattern.md § The boundaries), and `ls Sources/Tweaks` lists them. Every tweak lives under the one entry, Tweaks, a module whose descriptor and engine are in `Sources/HelmApp` and which has no page of its own; a tweak that holds reasons of its own has one:

- [Display Corners](Architecture/DisplayCorners.md) — the masks over a display's corners and the pointer held off them.

One page per directory of `Sources/Modules`, in the order `ls Sources/Modules` prints.

- [Autopilot](Architecture/Autopilot.md) — the refusals that bound acting on files unasked, starting with sealed rules.
- [Disk](Architecture/Disk.md) — reading where the space went on an APFS volume group without leaving the largest folder out.
- [Duplicates](Architecture/Duplicates.md) — the keep policies that decide which of several identical files is the extra one.
- [Homebrew](Architecture/Homebrew.md) — how another program's package manager is run, with read-only queries and other runs governed differently.
- [KeepAwake](Architecture/KeepAwake.md) — holding sleep off through pure logic units orchestrated by one engine.
- [Launchpad](Architecture/Launchpad.md) — the app launcher: its layout, window, grid, edit mode and optional trackpad pinch.
- [Layout](Architecture/Layout.md) — shown to the user as "Keyboard" (`LyStr.moduleName`); the four limits on a module that reads every keystroke and types into other applications.
- [Leftovers](Architecture/Leftovers.md) — what it will offer to remove: login items and plug-in files whose owner is gone.
- [Screenshots](Architecture/Screenshots.md) — freezing the displays and picking an area, a window, the Dock or the menu bar.
- [Screenshots editor](Architecture/ScreenshotsEditor.md) — the inline editor over the frozen picture: its layers, marks, palette, pop-overs and leaving.
- [Uninstaller](Architecture/Uninstaller.md) — deciding whether a path belongs to the application being removed.
- [VPN](Architecture/VPN.md) — raising and dropping tunnels from rules, and the books it keeps.

### Tests and release

- [Release](Architecture/Release.md) — where the version lives, how a build is numbered, signed and shipped, the updater and the disk image window.
- [Tests and measurement](Architecture/TestsAndMeasurement.md) — what makes a check a check, what proves which defect, what a removal takes with it, and how measuring tests are written.

### Who stores what

What each module keeps between launches, and where. A setting that steers unattended work is
sealed (§ Sealed settings); a number read from a file is bounded (§ A number that came from a file).

| Module | What it keeps | Where |
|---|---|---|
| Autopilot | its rules and their seal, the history of what it did | the property list and two keychain items (`Sources/Modules/Autopilot/Engine/RuleKeychain.swift`); `Sources/Modules/Autopilot/Engine/Logic/ActionHistory.swift` |
| Disk | the last scan, one slot | `Sources/Modules/Disk/Engine/ScanStore.swift` |
| Duplicates | its sealed settings, the digests of files it has read | `Sources/Modules/Duplicates/Engine/Logic/DuplicatesSettings.swift`, `Sources/Modules/Duplicates/Engine/HashCache.swift` |
| Homebrew | its one setting (`module.homebrew.updateBeforeChecking`, default ON, not sealed), the install-count documents it downloads, each with its `.etag` file, and a file for the operation in progress; nothing about packages themselves, which are read from `brew` | `Sources/Modules/Homebrew/Engine/UpdateBeforeChecking.swift`, `Sources/Modules/Homebrew/Engine/SystemPorts.swift`; Architecture/Homebrew.md § The one setting, § Install counts |
| KeepAwake | its settings, and a session a person started, which outlives the process | `Sources/Modules/KeepAwake/Engine/KeepAwakeSettings.swift`, `Sources/Modules/KeepAwake/Engine/Logic/SessionRestore.swift` |
| Launchpad | the arrangement of apps: items, folders, hidden ids; by bundle id only | `Sources/Modules/Launchpad/Engine/LayoutStore.swift` (a private `layout.json` in a `Launchpad` folder of the Application Support directory); the grid's six plain keys `grid.automatic`, `grid.rows`, `grid.columns`, `grid.iconSize`, `grid.showNames`, `grid.sizeMultiplier` in the module's store, `Sources/Modules/Launchpad/UI/LaunchpadGridSettings.swift`; the pinch switch's plain key `gesture.pinch` (off), `Sources/Modules/Launchpad/UI/LaunchpadViewModel.swift` |
| Layout | its ledger of words put right | `Sources/Modules/Layout/Engine/LedgerStore.swift` |
| Leftovers | the login items Helm switched off, so a reset can give them back | a `NamespacedStore` over the property list (`Sources/Modules/Leftovers/Engine/LeftoversEngine.swift`) |
| Screenshots | where a capture goes, and the other settings of the page | `Sources/Modules/Screenshots/Engine/Logic/ScreenshotsSettings.swift` |
| Tweaks | whether each tweak is switched on, `module.tweak.<id>.enabled`, off until switched on | a `NamespacedStore` per tweak (`Sources/HelmApp/TweakHost.swift`) |
| Display Corners | its two switches, the radius in pixels, the built-in display's last scale, as `module.tweak.display-corners.<key>`, not sealed, with the host's `enabled` beside them (the switch above) | `Sources/Tweaks/DisplayCorners/Engine/StoredCornerSettings.swift` |
| Uninstaller | its settings | `Architecture/Uninstaller.md` § Keys, gates, guards and files |
| VPN | its rules, and the credentials it caches for a tunnel | `Sources/Modules/VPN/Engine/VPNSettings.swift`, `Sources/Modules/VPN/Engine/SystemPorts.swift` |
| the scan settings of every scannable module | one sealed value | `Sources/HelmRuntime/SettingGuard.swift` |

### Who runs what

Which program each module launches, through `Sources/HelmRuntime/HelmProcess.swift`; a command run
as root goes through `Sources/HelmRuntime/PrivilegedRun.swift`. How they are bounded and read is
Architecture/RunningOtherPrograms.md.

| Module | Launches |
|---|---|
| Homebrew | `/opt/homebrew/bin/brew`, `/usr/bin/git`, `/usr/bin/xcode-select`, `/bin/bash` (the installer) |
| KeepAwake | `/usr/bin/pmset`, and `/usr/bin/sudo` with `/bin/rm` for its one sudoers rule |
| Leftovers | `/bin/launchctl` |
| VPN | `/usr/sbin/scutil`, `/usr/bin/security`, `/usr/bin/networkQuality` |
| the host and the runtime | `/usr/bin/osascript` (`Sources/HelmRuntime/PrivilegedRun.swift`), `/usr/bin/systemextensionsctl` (`Sources/HelmRuntime/SystemExtensionParser.swift`), `/usr/bin/ditto` and `/bin/bash` (`Sources/HelmApp/Installer.swift`) |
| Autopilot, Disk, Duplicates, Launchpad, Layout, Screenshots, Uninstaller | no tool of their own; the Uninstaller reads the applications through `Sources/HelmRuntime/RunningApps.swift` |

## What else to read

`README.md` (what Helm is, the module table, how it is installed and built) and `CHANGELOG.md` (one section per release, the canonical English record) stand beside this file in the root of the tree. `NOTICE.md` names the third-party artwork Helm ships and its terms; `Sources/Modules/Layout/UI/Flags/` is the material it covers.

Helm keeps no specs or plans in the tree. A worktree sits inside the tree, under its own folder, so anything outside the tree is reached by its full path: one level up from a worktree is not where a sibling checkout is, and nothing links a worktree for you.
