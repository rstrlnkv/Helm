# Helm — architecture

Helm is a menu-bar utility suite for macOS: one accessory application that hosts
its independent modules, which `ls Sources/Modules` lists. A module is a
headless engine and a settings page, and the two halves speak only over a
transport. Around them stand four foundation targets — `Sources/HelmContract`
for what crosses the engine/host boundary,
`Sources/HelmRuntime` for plumbing without UI, `Sources/HelmUI` for the design
system and the strings, and `Sources/HelmLaunch` for the one thing Swift cannot
express — plus `Sources/HelmApp`, the executable that owns the window, the panel
and the status item. The whole shape is declared in `Package.swift`, and the
boundaries in these pages are the ones the compiler enforces.

## How these pages are kept

A page holds one subject and the hub links it; a part of that subject is a heading on the
page, and a part pointed at as a subject of its own is a page. A page's H1 is its link text
here and its file name is that H1 in UpperCamelCase. Every heading is unique across the hub
and the pages, and a page's line below names every heading under its H1. Whatever names a
heading — a page, the hub, `README.md`, a doc comment — writes it the way
`ARCHITECTURE.md § Localization`, say, is written; "see X", a quoted heading, "above" and
"this document" are not addresses. A reason tied to one file lives in that file's doc
comment, not on a page.

## Where things are

| What a change touches | Where it lives |
|---|---|
| a module's pure logic | `Sources/Modules/<Module>/Engine/Logic/` |
| its engine, its command enum, its store | `Sources/Modules/<Module>/Engine/` |
| its screen | `Sources/Modules/<Module>/UI/` |
| its tests, both halves | `Tests/Modules/<Module>/EngineTests/`, `Tests/Modules/<Module>/UITests/` |
| what crosses the engine/host boundary | `Sources/HelmContract/` |
| plumbing two modules both want | `Sources/HelmRuntime/` |
| a string or a control two modules both draw | `Sources/HelmUI/` |
| a token — surface, motion, colour, radius | `Sources/HelmUI/DesignSystem/` |
| the translations | `Sources/HelmUI/Resources/` |
| the window, panel, status item, settings, changelog | `Sources/HelmApp/` |
| plumbing a test target wants | `Tests/Support/` |
| build, sign, package, disk image | `Scripts/` |

## Shape

- [Targets](Architecture/Targets.md) — the package's targets, what each one holds and which may see which, as the manifest declares them.
- [What is deliberately not here](Architecture/WhatIsDeliberatelyNotHere.md) — what Helm omits on purpose — an external dependency, a sandbox and privileged helper, a transport between host and modules, back-deployment — and why.
- [Module pattern](Architecture/ModulePattern.md) — how a module is built from four directories and what holds its parts apart; § The boundaries, § Ports and logic, § The transport and the store, § Bulk reads, § A value crossing to the main thread.

## UI shell

- [The menu-bar panel](Architecture/TheMenuBarPanel.md) — the window, chrome and card of the panel, and the pure grid and drag rules beneath them.
- [The status item](Architecture/TheStatusItem.md) — the rule that picks what the menu-bar item shows: a countdown, a spin, a tint or a title.
- [The Settings window](Architecture/TheSettingsWindow.md) — the split view, the full-height sidebar and the hosting controllers the window is built from.
- [The page header](Architecture/ThePageHeader.md) — the one-toolbar-per-page arrangement that carries a page's header and controls; § The bar's zones, § Toolbar actions, § The tabs and the search field, § The bar's menu and style, § The header strip.
- [The sidebar is an arrangement](Architecture/TheSidebarIsAnArrangement.md) — the sidebar as a stored value in which every module appears exactly once, shared with the status item's menu.
- [A window a module needs and the host owns](Architecture/AWindowAModuleNeedsAndTheHostOwns.md) — the base class for a host-owned window: activation policy, the closed flag and release on close.
- [Revealing a path](Architecture/RevealingAPath.md) — how a path is shown in Finder without launching or mounting a bundle.

## Subsystems

One page per module, in the order `ls Sources/Modules` prints.

- [Autopilot](Architecture/Autopilot.md) — the refusals that bound acting on files unasked, starting with sealed rules.
- [Disk](Architecture/Disk.md) — reading where the space went on an APFS volume group without leaving the largest folder out.
- [Duplicates](Architecture/Duplicates.md) — the keep policies that decide which of several identical files is the extra one.
- [Homebrew](Architecture/Homebrew.md) — how another program's package manager is run, with read-only queries and other runs governed differently; § Operations, § Installing Homebrew, § Install counts, § Searching for a package, § The Health tab.
- [Hosts](Architecture/Hosts.md) — editing `/etc/hosts` and managing SSH keys with the bytes as the canonical form.
- [KeepAwake](Architecture/KeepAwake.md) — holding sleep off through pure logic units orchestrated by one engine; § The closed lid, § Vetoes and the notice, § State a person asked for outlives the process.
- [Layout](Architecture/Layout.md) — the four limits on a module that reads every keystroke and types into other applications.
- [Leftovers](Architecture/Leftovers.md) — what it will offer to remove: login items and plug-in files whose owner is gone.
- [Uninstaller](Architecture/Uninstaller.md) — deciding whether a path belongs to the application being removed.
- [VPN](Architecture/VPN.md) — raising and dropping tunnels from rules, and the books it keeps, keyed by configuration id or, where `scutil` takes a name, by name.

## Across modules

- [Permissions](Architecture/Permissions.md) — how Full Disk Access is probed.
- [The gates](Architecture/TheGates.md) — the five types that answer where a path may be reached, read or written, and how a walk asks them.
- [Removal](Architecture/Removal.md) — the one batch every removal goes through and the refusals it reports; § One removal at a time.
- [Giving everything back](Architecture/GivingEverythingBack.md) — what a reset hands back outside Helm's own folders, what it cannot, and the order of its steps.
- [Running other programs](Architecture/RunningOtherPrograms.md) — launching a tool, bounding how many are out, reading what it prints, and running one as root.
- [Running applications](Architecture/RunningApplications.md) — why the running and frontmost applications are read on the main thread only, and the snapshot every other thread gets.
- [Background scans](Architecture/BackgroundScans.md) — the modules that can measure unattended and how the list and the capability are tied together.
- [Diagnostics log](Architecture/DiagnosticsLog.md) — the log file and its policy, the activity registry, the memory trail and the log pane; § The activity registry, § The memory trail, § The log pane.
- [Localization](Architecture/Localization.md) — the English key, the eight tables, the guards that watch them, and the helpers that keep the language the app's own.
- [State and lifetime](Architecture/StateAndLifetime.md) — what outlives a page or a thing it points at, and a value read back whole; § State that outlives a page and ends with its module, § An observer outlives the thing it points at, § A value read back whole.
- [Stored settings](Architecture/StoredSettings.md) — a stored value nobody else may write, and a number that came from a file; § Sealed settings, § A number that came from a file.
- [Design system](Architecture/DesignSystem.md) — what `Sources/HelmUI/DesignSystem/` holds and the rules for its surfaces, ladders, type, ink and motion; § Surfaces, § Ladders, § Type, § Ink and contrast, § Motion, § The visual language, § The record, § Widths.

## Shipping and checking

- [Release](Architecture/Release.md) — where the version lives, how a build is numbered, signed and shipped, the updater and the disk image window; § Channels and publishing, § Signing and grants, § The updater, § What shipped, § The disk image window.
- [Tests and measurement](Architecture/TestsAndMeasurement.md) — what makes a check a check, and how measuring tests are written; § What makes a check, § Readings and mutants, § Fakes, § Shared test plumbing, § Harnesses, § Measuring motion, § Why the commands are run.

## What else to read

Three documents stand beside `ARCHITECTURE.md` in the root of the tree:

- `README.md` — what Helm is, the module table, how it is installed and built.
- `CLAUDE.md` — the commands, the traps and what a session does before it changes
  anything: the orders whose reasons are on these pages.
- `CHANGELOG.md` — one section per release, for the person who updated.

One addition is declared:

- `NOTICE.md` — the third-party artwork Helm ships and the terms it carries.
  `Sources/Modules/Layout/UI/Flags/` is the material it covers.

Work on this tree goes through the crew's lead role. A plan carried out by a skill's own
implementers commits on its own and goes round the engineer, tester and verifier roles, so
the crew's journal records none of it, and a spec or plan such a skill writes has nowhere
to live here: Helm keeps no specs in the tree. A worktree sits inside the tree, under its
own folder, so anything outside the tree is reached by its full path — one level up from a
worktree is not where a sibling checkout is, and nothing links a worktree for you.
