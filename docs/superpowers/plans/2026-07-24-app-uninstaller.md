# App Uninstaller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Helm module that lists installed macOS apps, finds each app's leftover files (caches, prefs, containers, …) by bundle id + name, and moves the app plus selected leftovers to the Trash (reversible).

**Architecture:** Descriptor/engine split like KeepAwake/VPN. `Module_Uninstaller_Engine` holds pure logic (`LeftoverMatcher`, `ByteFormat`) + ports (`AppLister`, `FileSystemPort`, `TrashPort`, `RunningAppsPort`) + `UninstallerEngine` (request/response over `transport.send`). `Module_Uninstaller_UI` holds the descriptor, a settings page (primary UI), a panel tile, and a `UninstallerViewModel`. New `ModuleCategory.maintenance`.

**Tech Stack:** Swift 6, SwiftPM, AppKit/SwiftUI, XCTest. brew not involved (that's a separate module).

---

## Task 1: SwiftPM targets + category, skeleton compiles

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/HelmUI/MenuBarContribution.swift:9` (add `.maintenance`)
- Modify: `Sources/HelmApp/SettingsWindow.swift` (`categoryColor`)
- Modify: `Sources/HelmApp/AppStrings.swift` (`categoryName` switch)
- Create: `Sources/Modules/Uninstaller/Engine/Placeholder.swift` (temporary, to make target non-empty)
- Create: `Sources/Modules/Uninstaller/UI/Placeholder.swift`
- Create: `Tests/Modules/Uninstaller/EngineTests/Placeholder.swift`

- [ ] **Step 1: Add `.maintenance` to ModuleCategory**

In `Sources/HelmUI/MenuBarContribution.swift:9`:
```swift
case power, network, clipboard, window, media, files, appearance, maintenance, misc
```

- [ ] **Step 2: Category color + name**

`Sources/HelmApp/SettingsWindow.swift` `categoryColor(_:)` — add before `.misc`:
```swift
case .maintenance: return .pink
```
`Sources/HelmApp/AppStrings.swift` `categoryName(_:)` — add:
```swift
case .maintenance: return L("Maintenance", [.ru: "Обслуживание", .es: "Mantenimiento", .fr: "Maintenance", .de: "Wartung", .ja: "メンテナンス", .zh: "维护", .pt: "Manutenção"])
```

- [ ] **Step 3: Add targets to Package.swift**

After the VPN targets in `targets:`:
```swift
.target(name: "Module_Uninstaller_Engine",
        dependencies: ["HelmContract", "HelmRuntime"],
        path: "Sources/Modules/Uninstaller/Engine"),
.target(name: "Module_Uninstaller_UI",
        dependencies: ["HelmContract", "HelmUI", "Module_Uninstaller_Engine"],
        path: "Sources/Modules/Uninstaller/UI"),
```
Add to `HelmApp` dependencies: `"Module_Uninstaller_Engine", "Module_Uninstaller_UI"`.
Add test target:
```swift
.testTarget(name: "Module_Uninstaller_EngineTests",
            dependencies: ["Module_Uninstaller_Engine"],
            path: "Tests/Modules/Uninstaller/EngineTests"),
```

- [ ] **Step 4: Placeholder files so targets compile**

Each placeholder: `enum _UninstallerPlaceholder {}`. Test placeholder: an XCTestCase with one `XCTAssertTrue(true)`.

- [ ] **Step 5: Build + test**

Run: `swift build && swift test`
Expected: builds; existing 68 tests still pass.

- [ ] **Step 6: Commit** — `feat(uninstaller): targets + .maintenance category skeleton`

---

## Task 2: Data model

**Files:**
- Create: `Sources/Modules/Uninstaller/Engine/Model.swift`
- Delete: engine `Placeholder.swift`

- [ ] **Step 1: Types**
```swift
import Foundation

public struct InstalledApp: Codable, Equatable, Sendable {
    public let name: String
    public let bundleID: String
    public let path: String
    public let sizeBytes: Int
    public init(name: String, bundleID: String, path: String, sizeBytes: Int) {
        self.name = name; self.bundleID = bundleID; self.path = path; self.sizeBytes = sizeBytes
    }
}

public enum LeftoverKind: String, Codable, Sendable, CaseIterable {
    case appSupport, caches, preferences, containers, groupContainers,
         savedState, logs, httpStorages, webKit, cookies, appScripts, launchAgent
}

public struct Leftover: Codable, Equatable, Sendable {
    public let path: String
    public let kind: LeftoverKind
    public let sizeBytes: Int
    public let matchedByName: Bool
    public init(path: String, kind: LeftoverKind, sizeBytes: Int, matchedByName: Bool) {
        self.path = path; self.kind = kind; self.sizeBytes = sizeBytes; self.matchedByName = matchedByName
    }
}

public struct ScanResult: Codable, Equatable, Sendable {
    public let bundleID: String
    public let appPath: String
    public let appSizeBytes: Int
    public let leftovers: [Leftover]
    public let runningNow: Bool
}

public struct UninstallResult: Codable, Equatable, Sendable {
    public let trashed: [String]
    public let failed: [String]
    public let freedBytes: Int
}
```

- [ ] **Step 2: Build.** Run `swift build`. Expected: OK.
- [ ] **Step 3: Commit** — `feat(uninstaller): data model`

---

## Task 3: LeftoverMatcher (pure, TDD)

`LeftoverMatcher` produces **candidate** paths (URLs) from a bundle id + app name + a `Library` dir. Pure — no existence checks. Each candidate carries `kind` + `matchedByName`.

**Files:**
- Create: `Sources/Modules/Uninstaller/Engine/Logic/LeftoverMatcher.swift`
- Create: `Tests/Modules/Uninstaller/EngineTests/LeftoverMatcherTests.swift`

- [ ] **Step 1: Failing test**
```swift
import XCTest
@testable import Module_Uninstaller_Engine

final class LeftoverMatcherTests: XCTestCase {
    let lib = URL(fileURLWithPath: "/Users/x/Library")

    func testBundleIdCandidatesCoverKnownDirs() {
        let c = LeftoverMatcher.candidates(bundleID: "com.acme.tool", appName: "Tool", library: lib)
        let paths = Set(c.map { $0.url.path })
        XCTAssertTrue(paths.contains("/Users/x/Library/Caches/com.acme.tool"))
        XCTAssertTrue(paths.contains("/Users/x/Library/Preferences/com.acme.tool.plist"))
        XCTAssertTrue(paths.contains("/Users/x/Library/Containers/com.acme.tool"))
        XCTAssertTrue(paths.contains("/Users/x/Library/Saved Application State/com.acme.tool.savedState"))
    }

    func testNameCandidatesFlaggedAndScopedToSupportAndLogs() {
        let c = LeftoverMatcher.candidates(bundleID: "com.acme.tool", appName: "Tool", library: lib)
        let named = c.filter { $0.matchedByName }
        XCTAssertTrue(named.allSatisfy { $0.kind == .appSupport || $0.kind == .logs })
        XCTAssertTrue(named.contains { $0.url.path == "/Users/x/Library/Application Support/Tool" })
    }

    func testGroupContainersIsSuffixGlob() {
        let c = LeftoverMatcher.candidates(bundleID: "com.acme.tool", appName: "Tool", library: lib)
        let gc = c.first { $0.kind == .groupContainers }
        XCTAssertNotNil(gc)
        XCTAssertTrue(gc!.isGlob)   // resolved against the FS by the engine
    }
}
```
Run: `swift test --filter LeftoverMatcherTests` → FAIL (no type).

- [ ] **Step 2: Implement**
```swift
import Foundation

public enum LeftoverMatcher {
    public struct Candidate: Equatable {
        public let url: URL
        public let kind: LeftoverKind
        public let matchedByName: Bool
        /// true → `url`'s last path component is a glob to match against siblings
        /// (Group Containers `*.<id>`, LaunchAgents `<id>*.plist`).
        public let isGlob: Bool
    }

    public static func candidates(bundleID id: String, appName name: String, library lib: URL) -> [Candidate] {
        func u(_ parts: String...) -> URL { parts.reduce(lib) { $0.appendingPathComponent($1) } }
        var out: [Candidate] = []
        func add(_ url: URL, _ kind: LeftoverKind, name byName: Bool = false, glob: Bool = false) {
            out.append(.init(url: url, kind: kind, matchedByName: byName, isGlob: glob))
        }
        add(u("Application Support", id), .appSupport)
        add(u("Application Support", name), .appSupport, name: true)
        add(u("Caches", id), .caches)
        add(u("Preferences", "\(id).plist"), .preferences)
        add(u("Preferences", "ByHost").appendingPathComponent("\(id)*.plist"), .preferences, glob: true)
        add(u("Containers", id), .containers)
        add(u("Group Containers").appendingPathComponent("*.\(id)"), .groupContainers, glob: true)
        add(u("Saved Application State", "\(id).savedState"), .savedState)
        add(u("Logs", id), .logs)
        add(u("Logs", name), .logs, name: true)
        add(u("HTTPStorages", id), .httpStorages)
        add(u("HTTPStorages", "\(id).binarycookies"), .httpStorages)
        add(u("WebKit", id), .webKit)
        add(u("Cookies", "\(id).binarycookies"), .cookies)
        add(u("Application Scripts", id), .appScripts)
        add(u("LaunchAgents").appendingPathComponent("\(id)*.plist"), .launchAgent, glob: true)
        return out
    }
}
```
Run test → PASS.

- [ ] **Step 3: Commit** — `feat(uninstaller): LeftoverMatcher candidate paths (TDD)`

---

## Task 4: ByteFormat (pure, TDD)

**Files:**
- Create: `Sources/Modules/Uninstaller/Engine/Logic/ByteFormat.swift`
- Create: `Tests/Modules/Uninstaller/EngineTests/ByteFormatTests.swift`

- [ ] **Step 1: Failing test**
```swift
import XCTest
@testable import Module_Uninstaller_Engine

final class ByteFormatTests: XCTestCase {
    func testUnits() {
        XCTAssertEqual(ByteFormat.string(512), "512 B")
        XCTAssertEqual(ByteFormat.string(2048), "2.0 KB")
        XCTAssertEqual(ByteFormat.string(5 * 1024 * 1024), "5.0 MB")
        XCTAssertEqual(ByteFormat.string(0), "0 B")
    }
}
```

- [ ] **Step 2: Implement**
```swift
import Foundation

public enum ByteFormat {
    public static func string(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(max(0, bytes)); var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(Int(v)) B" : String(format: "%.1f %@", v, units[i])
    }
}
```
Run → PASS.

- [ ] **Step 3: Commit** — `feat(uninstaller): ByteFormat (TDD)`

---

## Task 5: Ports + settings

**Files:**
- Create: `Sources/Modules/Uninstaller/Engine/Ports.swift`

- [ ] **Step 1: Port protocols**
```swift
import Foundation

public protocol AppLister: Sendable {
    /// Apps from /Applications, ~/Applications, and any Setapp folder.
    func installedApps() -> [InstalledApp]
}

public protocol FileSystemPort: Sendable {
    func exists(_ url: URL) -> Bool
    func size(_ url: URL) -> Int                 // recursive byte size; 0 if missing
    func glob(_ pattern: URL) -> [URL]           // resolve a `*` last-component pattern
}

public protocol TrashPort: Sendable {
    func trash(_ url: URL) -> Bool
}

public protocol RunningAppsPort: Sendable {
    func isRunning(bundleID: String) -> Bool
    func quit(bundleID: String)
}
```

- [ ] **Step 2: Build.** `swift build`. Commit — `feat(uninstaller): engine ports`.

---

## Task 6: UninstallerEngine (TDD with fakes)

Engine resolves candidates against the FS, scans sizes, trashes selections, and answers commands over `transport.send`.

**Files:**
- Create: `Sources/Modules/Uninstaller/Engine/UninstallerEngine.swift`
- Create: `Tests/Modules/Uninstaller/EngineTests/UninstallerEngineTests.swift`

- [ ] **Step 1: Failing tests** (fakes for all ports; assert scan filters to existing paths, resolves globs, flags running; uninstall trashes only selected + sums freedBytes + aggregates failures)
```swift
import XCTest
@testable import Module_Uninstaller_Engine

final class UninstallerEngineTests: XCTestCase {
    func testScanReturnsOnlyExistingCandidates() async throws {
        let fs = FakeFS(existing: [
            "/Users/x/Library/Caches/com.acme.tool": 100,
            "/Users/x/Library/Preferences/com.acme.tool.plist": 10,
        ])
        let e = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                  apps: FakeApps(), fs: fs, trash: FakeTrash(),
                                  running: FakeRunning(running: []))
        let r = try await e.scan(bundleID: "com.acme.tool", appPath: "/Applications/Tool.app", appName: "Tool")
        XCTAssertEqual(Set(r.leftovers.map(\.path)),
                       ["/Users/x/Library/Caches/com.acme.tool",
                        "/Users/x/Library/Preferences/com.acme.tool.plist"])
        XCTAssertEqual(r.leftovers.first { $0.kind == .caches }?.sizeBytes, 100)
    }

    func testUninstallTrashesSelectedAndSumsFreed() async throws {
        let trash = FakeTrash()
        let fs = FakeFS(existing: ["/a": 100, "/b": 50, "/Applications/Tool.app": 1000])
        let e = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                  apps: FakeApps(), fs: fs, trash: trash, running: FakeRunning(running: []))
        let r = try await e.uninstall(appPath: "/Applications/Tool.app", paths: ["/a", "/b"])
        XCTAssertEqual(r.freedBytes, 1150)
        XCTAssertEqual(Set(trash.trashed), ["/a", "/b", "/Applications/Tool.app"])
        XCTAssertTrue(r.failed.isEmpty)
    }

    func testUninstallReportsTrashFailures() async throws {
        let trash = FakeTrash(failing: ["/b"])
        let fs = FakeFS(existing: ["/a": 100, "/b": 50, "/Applications/Tool.app": 1000])
        let e = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                  apps: FakeApps(), fs: fs, trash: trash, running: FakeRunning(running: []))
        let r = try await e.uninstall(appPath: "/Applications/Tool.app", paths: ["/a", "/b"])
        XCTAssertEqual(r.failed, ["/b"])
        XCTAssertEqual(r.freedBytes, 1100)   // only successfully trashed counted
    }
}
```
Include fakes (`FakeFS`, `FakeApps`, `FakeTrash`, `FakeRunning`) in the test file.

- [ ] **Step 2: Implement engine** with:
  - `init(home:apps:fs:trash:running:transport:)`.
  - `scan(bundleID:appPath:appName:)`: `LeftoverMatcher.candidates(...)` → for each, if `isGlob` use `fs.glob`, else `fs.exists`; keep existing; `size` each; build `[Leftover]`; `runningNow = running.isRunning`. Sort leftovers by size desc.
  - `uninstall(appPath:paths:)`: for each selected path + the app path, `trash.trash`; sum `fs.size` of the successfully trashed; collect failures.
  - `activate()/deactivate()`: no observers needed.
  - `wireTransport()`: decode `"listApps"`/`"scan"`/`"uninstall"` payloads, return JSON-encoded results (request/response — the handler's return `Data` is delivered by `transport.send`). Do filesystem work on a background queue via `await`.
- [ ] **Step 3: Test.** `swift test --filter UninstallerEngineTests` → PASS.
- [ ] **Step 4: Commit** — `feat(uninstaller): engine scan/uninstall (TDD)`

---

## Task 7: Production ports (SystemPorts)

**Files:**
- Create: `Sources/Modules/Uninstaller/Engine/SystemPorts.swift`

- [ ] **Step 1: Implement**
  - `WorkspaceAppLister`: scan `/Applications`, `~/Applications`, `/Applications/Setapp` (+ `~/Applications/Setapp`) for `*.app`; read `CFBundleIdentifier` + `CFBundleName`/display name from each `Info.plist`; size via the FS port or `URL.fileAllocatedSize` accumulation.
  - `FMFileSystem`: `FileManager` existence; recursive size via `enumerator` summing `.totalFileAllocatedSizeKey`; `glob` via listing the parent dir and matching the `*` component with `fnmatch`/simple prefix-suffix.
  - `FMTrash`: `FileManager.default.trashItem(at:resultingItemURL:)` → bool.
  - `WorkspaceRunningApps`: `NSRunningApplication.runningApplications(withBundleIdentifier:)`; `quit` → `terminate()`.
  - `struct UninstallerSystemPorts { ... }` bundle.
- [ ] **Step 2: Build.** Commit — `feat(uninstaller): production ports`.

---

## Task 8: UninstallerViewModel

**Files:**
- Create: `Sources/Modules/Uninstaller/UI/UninstallerViewModel.swift`

- [ ] **Step 1: Implement** `@MainActor final class UninstallerViewModel: ObservableObject` wrapping `transport`:
  - `func listApps() async -> [InstalledApp]`
  - `func scan(_ app: InstalledApp) async -> ScanResult?`
  - `func uninstall(appPath: String, paths: [String]) async -> UninstallResult?`
  Each encodes a payload, `try? await transport.send(EngineCommand(...))`, decodes the JSON `Data` reply.
- [ ] **Step 2: Build.** Commit — `feat(uninstaller): view model`.

---

## Task 9: Settings page (primary UI)

**Files:**
- Create: `Sources/Modules/Uninstaller/UI/UninstallerSettingsPage.swift`
- Create: `Sources/Modules/Uninstaller/UI/UninstallerStrings.swift`

- [ ] **Step 1: Strings** (`UnStr`) — localized (8 langs): title, summary, searchApps, scanning, appItself, moveToTrash, confirmTrash(n, size), quitAndRemove(appName), freed(size), skipped, needsPrivileges, matchedByName, empty states, kind labels per `LeftoverKind`.

- [ ] **Step 2: Settings page**
  - Two-pane `HStack`: left = searchable `List` of apps (icon via `AppInfo.resolve`/`NSWorkspace.icon(forFile:)`, name, `ByteFormat`); right = selected app scan.
  - On select → `Task { scan = await vm.scan(app) }`; show `ProgressView` while scanning.
  - Right pane: app row (always checked, disabled checkbox) + leftovers grouped by `kind` (section headers = localized kind), each: checkbox (default on), path (truncated middle), size, "по имени" tag if `matchedByName`.
  - Footer: total selected size + `Button(UnStr.moveToTrash)` → confirmation sheet/alert. If `scan.runningNow`, alert offers "Quit & Remove".
  - On confirm → `Task { let r = await vm.uninstall(...); show result; refresh list }`.
- [ ] **Step 3: Build.** Commit — `feat(uninstaller): settings page + strings`.

---

## Task 10: Descriptor + panel tile + registry

**Files:**
- Create: `Sources/Modules/Uninstaller/UI/UninstallerDescriptor.swift`
- Create: `Sources/Modules/Uninstaller/UI/UninstallerPanelTile.swift`
- Delete: UI `Placeholder.swift`
- Modify: `Sources/HelmApp/ModuleRegistry.swift:8`

- [ ] **Step 1: Descriptor** — id `uninstaller`, category `.maintenance`, sfSymbol `trash`, `makeEngine` builds `UninstallerEngine` with `UninstallerSystemPorts` + `home = FileManager.default.homeDirectoryForCurrentUser`. `menuBar` → panel tile. `settingsPage` → the page. `statusAppearance` uses default (`.inactive`).
- [ ] **Step 2: Panel tile** — icon badge + name + "Открыть" button posting a notification / calling the settings-open path used elsewhere (mirror how VPN/KeepAwake open settings if present; otherwise a simple label with the module summary).
- [ ] **Step 3: Register** — `ModuleRegistry.swift:8`:
```swift
static let all: [any ModuleDescriptor] = [KeepAwakeDescriptor(), VPNDescriptor(), UninstallerDescriptor()]
```
- [ ] **Step 4: Build + test.** `swift build && swift test`. Expected: all green.
- [ ] **Step 5: Commit** — `feat(uninstaller): descriptor, panel tile, registry`

---

## Task 11: Package + live verify

- [ ] **Step 1:** `pkill -f 'Helm.app/Contents/MacOS/HelmApp'; bash Scripts/package-app.sh` (do NOT bump version; this is unreleased 0.6.0-dev work).
- [ ] **Step 2:** Install locally, open Settings → Обслуживание → app list loads, pick a small app, verify scan finds its files with sizes, verify checkboxes, and (on a throwaway app) verify Trash + result summary. Confirm nothing is trashed without confirmation.
- [ ] **Step 3:** Verify `/Library` / root-owned items are shown non-selectable (or absent in v1).
- [ ] **Step 4: Commit** any fixes.

---

## Notes

- Do not bump the app version or cut a release during this plan; that happens once
  both new modules (uninstaller + Homebrew) are ready, per the versioning rule.
- Keep filesystem work off the main actor in the engine (scans can be large).
- All destructive actions go through Trash + explicit confirmation.
