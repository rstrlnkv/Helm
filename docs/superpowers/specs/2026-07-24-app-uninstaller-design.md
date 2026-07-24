# App Uninstaller — Design

**Status:** approved-pending-review
**Date:** 2026-07-24
**Module id:** `uninstaller`

## Goal

A Helm module that lists installed macOS apps and, for a chosen app, finds every
associated file (caches, preferences, containers, logs, launch agents, …) and
moves the app plus the selected leftovers to the **Trash** (reversible). Modelled
on AppCleaner, scoped to the user domain so it needs no admin password.

## Decisions (from brainstorming)

1. **Matching:** by `bundleID` (primary, safe) **plus** an exact folder-name match
   where a folder is named exactly the app's display name (secondary — covers apps
   that store data under `Application Support/<AppName>` instead of the bundle id).
   Name-matched items are labelled distinctly so the user can uncheck them. All
   removals go to Trash, so a false positive is recoverable.
2. **Category:** a new `ModuleCategory.maintenance` ("Обслуживание"), shared with
   the future Homebrew module.
3. **App sources:** `/Applications` and `~/Applications` (plus a Setapp subfolder
   if present). System apps in `/System/Applications` are excluded (SIP-protected).
4. **Deletion:** move to Trash via `FileManager.trashItem` (reversible). Never `rm`.

## Architecture

Follows the established module pattern (descriptor/engine split, ports, namespaced
store, transport channel). Two SwiftPM targets:

### `Module_Uninstaller_Engine` (logic + ports)

Ports (protocols, with production + test implementations):

- `AppLister` — enumerate installed apps → `[InstalledApp]`.
- `FileSystemPort` — existence, size (recursive), and directory listing for scans.
- `TrashPort` — move a URL to the Trash; returns success/failure per item.
- `RunningAppsPort` — is a bundle id currently running; terminate it.

Pure logic (TDD, no I/O — takes data, returns paths/decisions):

- `LeftoverMatcher` — given `bundleID` + app `name` + a home dir, produces the list
  of **candidate** paths (see "Scan locations"). Pure: returns URLs; the engine
  filters to those that exist via `FileSystemPort`. Marks each candidate with its
  `kind` and whether it was matched by id or by name.
- `ByteFormat` — humanize sizes ("128 MB").

Engine (`UninstallerEngine: ModuleEngine`):

- Commands over `transport.send` (request/response — `send` returns `Data`):
  - `"listApps"` → `[InstalledApp]` (JSON).
  - `"scan"` (payload: bundleID) → `ScanResult { app, leftovers: [Leftover], runningNow: Bool }`.
  - `"uninstall"` (payload: bundleID + selected paths) → `UninstallResult { trashed: [String], failed: [String], freedBytes: Int }`.
- Filesystem work runs off the main actor (scans can walk large dirs).

### `Module_Uninstaller_UI`

- `UninstallerDescriptor: ModuleDescriptor` — id `uninstaller`, category `.maintenance`,
  SF symbol e.g. `trash`. `statusAppearance` stays `.inactive` (not a toggle, never
  tints the menu bar). Registered in `ModuleRegistry.all`.
- Settings page (`UninstallerSettingsPage`) — the primary UI:
  1. Left: searchable list of installed apps (icon, name, size).
  2. Select an app → engine scans → right: the app row (always checked) + leftovers
     grouped by `kind`, each with path, size, checkbox (all checked by default;
     name-matched items flagged with a subtle "по имени" tag).
  3. "Move to Trash" button → confirmation ("Переместить N объектов (X МБ) в Корзину?")
     → if the app is running, offer to quit it first → trash → result summary
     ("Освобождено X МБ", plus any skipped items with reasons).
- Panel tile (`UninstallerPanelTile`) — compact: icon + name + "Открыть" button that
  opens Settings focused on this module (no heavy UI in the menu-bar panel).
- A dedicated `UninstallerViewModel` wraps `transport.send` with typed async helpers
  (`listApps()`, `scan()`, `uninstall()`), decoding the JSON responses.

## Data model

```swift
struct InstalledApp: Codable, Equatable {
    let name: String
    let bundleID: String
    let path: String        // .app bundle path
    let sizeBytes: Int
}

enum LeftoverKind: String, Codable {   // drives grouping + labels
    case appSupport, caches, preferences, containers, groupContainers,
         savedState, logs, httpStorages, webKit, cookies, appScripts, launchAgent
}

struct Leftover: Codable, Equatable {
    let path: String
    let kind: LeftoverKind
    let sizeBytes: Int
    let matchedByName: Bool   // true = matched by folder name, not bundle id
}
```

## Scan locations (user domain — no admin)

Relative to `~/Library`, matched by `bundleID` unless noted:

| Kind | Path pattern |
|------|--------------|
| appSupport | `Application Support/<bundleID>`, `Application Support/<AppName>` (name) |
| caches | `Caches/<bundleID>` |
| preferences | `Preferences/<bundleID>.plist`, `Preferences/ByHost/<bundleID>.*.plist` |
| containers | `Containers/<bundleID>` |
| groupContainers | `Group Containers/*.<bundleID>` (suffix match) |
| savedState | `Saved Application State/<bundleID>.savedState` |
| logs | `Logs/<bundleID>`, `Logs/<AppName>` (name) |
| httpStorages | `HTTPStorages/<bundleID>`, `HTTPStorages/<bundleID>.binarycookies` |
| webKit | `WebKit/<bundleID>` |
| cookies | `Cookies/<bundleID>.binarycookies` |
| appScripts | `Application Scripts/<bundleID>` |
| launchAgent | `LaunchAgents/<bundleID>*.plist` |

`/Library/...` and `/var/db/receipts` are **out of scope for v1** (root-owned →
would need a privileged helper). If encountered they are shown greyed with a
"нужны права" note but not selectable.

## Safety

- Reversible: Trash only.
- No name-only matching except exact folder name == app display name, in
  `Application Support` / `Logs` only, and always labelled.
- The `.app` itself is always in the removal set (checked, not removable from set).
- Running target app → prompt to quit before trashing (can't trash a running app cleanly).
- Per-item failures (permission, in-use) are collected and reported, never fatal.

## Testing (TDD)

- `LeftoverMatcher`: produces the correct candidate URLs from a bundleID + name +
  home dir; suffix match for Group Containers; name-vs-id flag set correctly; does
  not emit paths for unrelated ids.
- `ByteFormat`: rounding/units.
- Engine scan/uninstall tested against in-memory `FileSystemPort` / `TrashPort`
  fakes (exists → included; trash success/failure aggregation; freedBytes sum).

## Out of scope (v1)

- Root-owned/system files (needs privileged helper).
- Homebrew casks (handled by the Homebrew module).
- "Reset" (delete data but keep app).
