# Homebrew Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans / subagent-driven-development. Steps use `- [ ]`.

**Goal:** Manage Homebrew in-app — list installed (formulae+casks), outdated + upgrade, search + install, uninstall, with a live console; offer in-app Homebrew install when absent.

**Architecture:** See `docs/superpowers/specs/2026-07-24-homebrew-manager-design.md`. Descriptor/engine split. Engine: fast queries via `transport.send` (JSON), long ops stream `opLog`/`opState` events. Pure parsers (`BrewListParser`, `BrewOutdatedParser`, `BrewSearchParser`) are the tested logic.

**Tech Stack:** Swift 6, SwiftPM, AppKit/SwiftUI, XCTest, `brew` CLI.

---

## Task 1: Targets + skeleton

**Files:** `Package.swift` (+ `Module_Homebrew_Engine`, `Module_Homebrew_UI`, test target; add both to HelmApp deps); placeholders in `Sources/Modules/Homebrew/{Engine,UI}/` and `Tests/Modules/Homebrew/EngineTests/`.

- [ ] Add targets mirroring the Uninstaller ones (Engine deps HelmContract+HelmRuntime; UI deps HelmContract+HelmUI+Engine; testTarget deps Engine).
- [ ] Placeholder files so targets compile.
- [ ] `swift build && swift test` → green (77 tests).
- [ ] Commit: `feat(homebrew): targets skeleton`.

## Task 2: Data model

**Files:** Create `Sources/Modules/Homebrew/Engine/Model.swift`; delete engine placeholder.

- [ ] Types (all `Codable, Equatable, Sendable`): `BrewPackage{name,version,isCask}`, `OutdatedPackage{name,installed,latest,isCask}`, `SearchHit{name,isCask}`, `BrewStatus{installed,brewPath?}`, `OpPhase{idle,running,done,failed}`, `OpState{phase,label,exitCode?}`.
- [ ] Build. Commit: `feat(homebrew): data model`.

## Task 3: BrewListParser (TDD)

**Files:** `Sources/Modules/Homebrew/Engine/Logic/BrewListParser.swift`, `Tests/Modules/Homebrew/EngineTests/BrewListParserTests.swift`.

- [ ] **Failing test:** input `"ada-url 3.4.4\nbrotli 1.2.0\n\nc-ares 1.34.8\n"`, `isCask:false` → 3 packages; name/version parsed; `"foo 1.0 1.1"` (multiple versions) → version `"1.0"`; blank lines skipped; a line with no version → version `""`.
- [ ] **Implement:** `static func parse(_ output: String, isCask: Bool) -> [BrewPackage]` — split lines, trim, skip empty; split on whitespace; first token = name, second (if any) = version.
- [ ] Test passes. Commit: `feat(homebrew): BrewListParser (TDD)`.

## Task 4: BrewOutdatedParser (TDD)

**Files:** `.../Logic/BrewOutdatedParser.swift`, `.../BrewOutdatedParserTests.swift`.

- [ ] **Failing test** with a `--json=v2` fixture:
```json
{"formulae":[{"name":"deno","installed_versions":["2.9.3"],"current_version":"2.9.4"}],
 "casks":[{"name":"figma","installed_versions":["1.2.3"],"current_version":"1.2.4"}]}
```
→ 2 `OutdatedPackage`; deno `installed 2.9.3 → latest 2.9.4 isCask=false`; figma `isCask=true`. Empty arrays → `[]`. Missing installed_versions → installed `""`.
- [ ] **Implement:** `static func parse(_ data: Data) -> [OutdatedPackage]` — `JSONDecoder` into private DTOs for `formulae`/`casks`; map `installed = installed_versions.first ?? ""`, `latest = current_version`.
- [ ] Test passes. Commit: `feat(homebrew): BrewOutdatedParser (TDD)`.

## Task 5: BrewSearchParser (TDD)

**Files:** `.../Logic/BrewSearchParser.swift`, `.../BrewSearchParserTests.swift`.

- [ ] **Failing test:** input
```
==> Formulae
wget
wget2

==> Casks
wget-gui
```
→ `wget`,`wget2` isCask=false; `wget-gui` isCask=true. Plain list with no headers (older brew) → all formulae. Empty → `[]`. "No formulae or casks found" line ignored.
- [ ] **Implement:** `static func parse(_ output: String) -> [SearchHit]` — iterate lines; toggle current section on `==> Formulae` / `==> Casks`; default section = formula; skip blanks + headers + "No … found".
- [ ] Test passes. Commit: `feat(homebrew): BrewSearchParser (TDD)`.

## Task 6: Ports

**Files:** `Sources/Modules/Homebrew/Engine/Ports.swift`.

- [ ] `BrewLocator { func brewPath() -> String? }`.
- [ ] `ProcessRunner { func run(_ args:[String], env:[String:String]) -> (Int32,String); func stream(_ args:[String], env:[String:String], onLine:@escaping @Sendable (String)->Void, onExit:@escaping @Sendable (Int32)->Void) }`.
- [ ] `PrivilegedRunner { func runAdmin(_ script:String) -> Bool }`.
- [ ] Build. Commit: `feat(homebrew): engine ports`.

## Task 7: HomebrewEngine

**Files:** `Sources/Modules/Homebrew/Engine/HomebrewEngine.swift`.

- [ ] Implement engine holding `locator, runner, privileged, user`. `transport` = LocalTransport.
  - `status()` → `BrewStatus(installed: locator.brewPath() != nil, brewPath:)`.
  - `listInstalled()` → run `brew list --versions --formula` + `brew list --versions --cask`; parse each with `BrewListParser`; concat.
  - `outdated()` → run `brew outdated --json=v2`; `BrewOutdatedParser.parse`.
  - `search(q)` → run `brew search q`; `BrewSearchParser.parse`.
  - Long ops set `busy`, emit `opState(running,label)`, `stream` the brew args (install: `["install", name]` or `["install","--cask",name]`; uninstall similar; upgrade: `["upgrade", name]` or `["upgrade"]` for all), forward each line as `opLog`, on exit emit `opState(done/failed, exitCode)` and clear `busy`. Reject a new long op while `busy` (emit failed "busy").
  - `installBrew()`: `privileged.runAdmin("mkdir -p /opt/homebrew && chown -R \(user):admin /opt/homebrew")`; then `stream` `["/bin/bash","-c","$(curl -fsSL <official>)"]`-equivalent with `NONINTERACTIVE=1`. (Implement by streaming `/bin/bash` with `-c` running the curl-piped installer.)
  - `wireTransport`: `status`/`listInstalled`/`outdated`/`search` return JSON `Data`; `install`/`uninstall`/`upgrade`/`upgradeAll`/`installBrew` kick off streaming, return empty `Data`.
  - Prefix all brew arg arrays with the resolved brew path in `run`/`stream` (ProcessRunner executes an absolute path).
- [ ] Build. Commit: `feat(homebrew): engine (queries + streaming long ops)`.

## Task 8: Production ports (SystemPorts)

**Files:** `Sources/Modules/Homebrew/Engine/SystemPorts.swift`.

- [ ] `FSBrewLocator`: check `/opt/homebrew/bin/brew`, then `/usr/local/bin/brew`; return first existing.
- [ ] `ShellProcessRunner`: `run` via `Process` (capture stdout); `stream` via `Process` with a `Pipe`, `readabilityHandler` splitting into lines → `onLine`, `terminationHandler` → `onExit`. stderr merged into stdout pipe. Runs off the main thread.
- [ ] `OSAPrivilegedRunner`: `osascript -e "do shell script \"…\" with administrator privileges"` (escape the script); return status==0. (Mirror `PmsetClamshellPort.installSudoers` escaping.)
- [ ] `struct HomebrewSystemPorts { locator, runner, privileged }`.
- [ ] Build. Commit: `feat(homebrew): production ports`.

## Task 9: HomebrewViewModel

**Files:** `Sources/Modules/Homebrew/UI/HomebrewViewModel.swift`.

- [ ] `@MainActor final class HomebrewViewModel: ObservableObject`. `@Published` `status`, `installed`, `outdated`, `searchHits`, `consoleLines:[String]`, `op:OpState`. Subscribes to `transport.events` for `opLog` (append) / `opState` (update `op`; on `.done` refresh the relevant list). Async helpers: `refreshStatus/refreshInstalled/refreshOutdated/search(q)`; fire-and-forget `install/uninstall/upgrade/upgradeAll/installBrew`; `clearConsole`.
- [ ] Build. Commit: `feat(homebrew): view model`.

## Task 10: Settings page + strings

**Files:** `Sources/Modules/Homebrew/UI/HomebrewSettingsPage.swift`, `HomebrewStrings.swift`.

- [ ] Strings (`HbStr`, 8 langs): module name/summary, install-brew screen text + button, segments (Installed/Updates/Search), search placeholder, actions (install/uninstall/upgrade/upgradeAll), states (running/done/failed), console clear, formula/cask tags, empty states, "brew not installed".
- [ ] Page:
  - `.task` → `refreshStatus`.
  - If `!status.installed`: install screen (explanation + "Установить Homebrew" → `installBrew`) + console.
  - Else: `Picker` segmented (Installed/Updates/Search). Installed → list + Uninstall; Updates → list + Upgrade + "Upgrade all"; Search → TextField + results + Install.
  - Console section: monospaced auto-scrolling `ScrollView` of `consoleLines`, status pill from `op`, disabled controls while `op.phase == .running`, "Clear".
- [ ] Build. Commit: `feat(homebrew): settings page + strings`.

## Task 11: Descriptor + panel tile + registry

**Files:** `HomebrewDescriptor.swift`, `HomebrewPanelTile.swift`; delete UI placeholder; `ModuleRegistry.swift` (+import, + `HomebrewDescriptor()`).

- [ ] Descriptor: id `homebrew`, category `.maintenance`, symbol `shippingbox`; `makeEngine` builds `HomebrewEngine` with `HomebrewSystemPorts` + current user name. Panel tile: icon + name + "Open in Settings" (`.helmOpenSettings`). `statusAppearance` default.
- [ ] Register in `ModuleRegistry.all`.
- [ ] `swift build && swift test` → all green.
- [ ] Commit: `feat(homebrew): descriptor, panel tile, registry`.

## Task 12: Package + live verify

- [ ] `pkill … ; bash Scripts/package-app.sh`, install locally, open Settings → Обслуживание → Homebrew.
- [ ] Verify: installed list loads (formulae+casks); Updates shows outdated; Search finds a package; run a safe op (e.g. `brew upgrade` of a tiny already-current package is a no-op; or install then uninstall a tiny formula like `hello`) and watch the console stream + list refresh.
- [ ] Do NOT exercise the install-Homebrew path (brew already present).
- [ ] Commit any fixes.

## Notes

- Do not bump version here; both modules release together after this plan (Uninstaller = pending). Then one MINOR bump (0.6.0) covering both, per the versioning rule.
- One brew op at a time; guard with `busy`.
- All brew invocations use the absolute brew path from `BrewLocator`.
