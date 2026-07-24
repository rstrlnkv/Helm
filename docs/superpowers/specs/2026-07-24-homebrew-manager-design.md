# Homebrew Manager — Design

**Status:** approved-pending-review
**Date:** 2026-07-24
**Module id:** `homebrew`

## Goal

A Helm module to manage Homebrew from inside the app: list installed packages
(formulae + casks), show and apply updates, search + install, and uninstall — with
a live console streaming `brew`'s output for the long operations. When Homebrew is
absent, offer to install it in-app from the official repository.

## Decisions (from brainstorming)

1. **Scope:** full — installed list (formulae+casks), outdated + upgrade (per-package
   and all), search + install, uninstall.
2. **brew missing:** offer in-app install of Homebrew from the official installer
   (`raw.githubusercontent.com/Homebrew/install/HEAD/install.sh`), run with
   `NONINTERACTIVE=1`, streamed to the console. Admin rights come from the native
   macOS password dialog via `osascript … with administrator privileges` (the user
   types the password in the system dialog — the app never handles it), reusing the
   privileged-helper pattern already used by Keep Awake's clamshell feature. No
   Terminal switch. (Cannot be fully live-tested here since brew is already present.)
3. **Long operations** (install/uninstall/upgrade/brew-install): a live console —
   `brew` stdout+stderr streamed line-by-line into an auto-scrolling monospaced view,
   with a status pill (running/done/failed) and buttons disabled while an op runs.
4. **UI:** in the Settings window, category `.maintenance` (shared with Uninstaller).

## Architecture

Follows the module pattern (descriptor/engine split, ports, transport channel).

### `Module_Homebrew_Engine`

Ports:

- `BrewLocator` — returns the `brew` path (`/opt/homebrew/bin/brew`, fallback
  `/usr/local/bin/brew`) or nil.
- `ProcessRunner`:
  - `run(_ args:[String], env:) -> (status: Int32, stdout: String)` — fast queries.
  - `stream(_ args:[String], env:, onLine:, onExit:)` — long ops; pipes stdout+stderr,
    invokes `onLine` per line, `onExit(code)` at the end. Returns a handle (unused v1;
    one op at a time).
- `PrivilegedRunner` — `runAdmin(script:) -> Bool` via `osascript -e 'do shell script … with administrator privileges'` (GUI password dialog). Used only to pre-create
  `/opt/homebrew` owned by the user before the (non-root) Homebrew installer runs.

Pure logic (TDD, no I/O — parse fixed `brew` output):

- `BrewListParser` — `brew list --versions` lines (`name 1.2.3`) → `[BrewPackage]`
  (a `--cask` flag from which list it came).
- `BrewOutdatedParser` — `brew outdated --json=v2` → `[OutdatedPackage]`
  (name, installed, latest/current, isCask) for both `formulae` and `casks` arrays.
- `BrewSearchParser` — `brew search <q>` sectioned output (`==> Formulae` / `==> Casks`)
  → `[SearchHit]` (name, isCask).

Engine (`HomebrewEngine: ModuleEngine`):

- Request/response over `transport.send` (returns `Data`):
  - `"status"` → `{ installed: Bool, brewPath: String? }`.
  - `"listInstalled"` → `[BrewPackage]` (formulae + casks, one `brew list --versions`
    per kind, merged).
  - `"outdated"` → `[OutdatedPackage]`.
  - `"search"` (payload query) → `[SearchHit]`.
- Long ops — fire command, stream events, one at a time (guarded by a `busy` flag):
  - `"install"` / `"uninstall"` (payload: name + isCask), `"upgrade"` (name), `"upgradeAll"`, `"installBrew"`.
  - Emits `EngineEvent(name:"opLog", payload: line)` per output line and
    `EngineEvent(name:"opState", payload: OpState)` where
    `OpState = { phase: idle|running|done|failed, label: String, exitCode: Int? }`.
  - On `done`, the UI re-queries the affected list.
- `activate()/deactivate()`: no observers.

`installBrew` flow:
1. `PrivilegedRunner.runAdmin`: `mkdir -p /opt/homebrew && chown -R <user>:admin /opt/homebrew`
   (one GUI password prompt).
2. `stream` the installer: `/bin/bash -c "$(curl -fsSL <official install.sh>)"` with
   `NONINTERACTIVE=1` in the environment, output to the console.
3. On exit 0 → re-check status; the module flips from the install screen to the manager.

### `Module_Homebrew_UI`

- `HomebrewDescriptor` — id `homebrew`, category `.maintenance`, SF symbol
  `shippingbox` (or `cube.box`). `statusAppearance` default (`.inactive`).
- `HomebrewViewModel` — typed async helpers over `transport.send` for the queries,
  plus subscription to `opLog`/`opState` events (accumulates console lines + op state,
  `@Published`). Sends the long-op commands.
- Settings page:
  - If `status.installed == false` → an install screen: short explanation + "Установить
    Homebrew" button (runs `installBrew`) + the console.
  - Else → a segmented control **Installed / Updates / Search**:
    - Installed: list (name, version, formula/cask tag) with an Uninstall button per row.
    - Updates: list (name, installed → latest) with Upgrade per row + "Upgrade all".
    - Search: a query field → results (name, tag) with Install per row.
  - A console section (shown while/after an op) with the streamed output + status pill;
    a "Clear" button; controls disabled while `phase == running`.
- Panel tile — compact: icon + name + "Open in Settings" (reuses `.helmOpenSettings`).

## Data model

```swift
struct BrewPackage: Codable, Equatable { let name: String; let version: String; let isCask: Bool }
struct OutdatedPackage: Codable, Equatable { let name: String; let installed: String; let latest: String; let isCask: Bool }
struct SearchHit: Codable, Equatable { let name: String; let isCask: Bool }
struct BrewStatus: Codable, Equatable { let installed: Bool; let brewPath: String? }
enum OpPhase: String, Codable { case idle, running, done, failed }
struct OpState: Codable, Equatable { let phase: OpPhase; let label: String; let exitCode: Int? }
```

## Testing (TDD)

- `BrewListParser`: `name version` lines; skips blanks; multiple versions → first.
- `BrewOutdatedParser`: real `--json=v2` sample (formulae + casks arrays; current vs
  installed_versions; cask `current_version`/`installed_versions`).
- `BrewSearchParser`: sectioned output → formula vs cask flag; no-results case.
- (Engine long ops are side-effecting; parsers carry the logic and are unit-tested.)

## Safety

- Only invokes the `brew` CLI and the official Homebrew installer. All install/
  uninstall/upgrade actions are explicit user actions.
- Homebrew is never run as root; the single privileged step only pre-creates and
  chowns `/opt/homebrew` to the user, via the native admin dialog (user-entered).
- One operation at a time.

## Out of scope (v1)

- `brew services`, taps management, package pinning, cleanup/autoremove.
- Rich package detail pages (`brew info` beyond name/version).
- Cancelling a running op mid-flight.
