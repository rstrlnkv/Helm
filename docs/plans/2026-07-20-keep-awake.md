# Keep Awake + Package Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bootstrap the Helm SwiftPM package (Contract/Runtime/UI/App) and ship the first module, Keep Awake, as a running menu-bar app.

**Architecture:** Approach C from [architecture spec](../specs/2026-07-20-helm-architecture-design.md). Keep Awake runs `.inProcess` (LocalTransport). Pure logic is TDD'd headless; side effects (IOKit / pmset / CGEvent / power / display) sit behind injectable protocols. Module = headless `Engine` target (no SwiftUI) + `UI` target. See [Keep Awake spec](../specs/2026-07-20-keep-awake-design.md).

**Tech Stack:** Swift 6, SwiftPM (`swift build`/`swift test`), AppKit + SwiftUI, macOS 26 SDK, XCTest. App assembled into a `.app` bundle by a thin packaging script (LSUIElement / `.accessory`). XPC service target (`HelmModuleHostXPC`) is **deferred** — reserved by the contract, not built until the first `.xpc` module (YAGNI).

---

## File Structure

```
Helm/
  Package.swift
  Sources/
    HelmContract/            # Foundation-only. Frozen-ABI surface.
      ModuleID.swift, ModuleMetadata.swift, ModuleIsolation.swift,
      ModulePermission.swift, StatusAppearance.swift,
      EngineMessage.swift (Command/Event), EngineTransport.swift, ModuleEngine.swift
    HelmRuntime/             # Foundation. Headless infra.
      NamespacedStore.swift, Log.swift
    HelmUI/                  # SwiftUI. UI-part of contract + design system.
      ModuleDescriptor.swift, ModuleViewModel.swift, MenuBarContribution.swift,
      DesignSystem/PaletteColor.swift, DesignSystem/RingIcon.swift
    Modules/KeepAwake/
      Engine/                # Module_KeepAwake_Engine — NO SwiftUI
        Logic/ (pure): Conditions.swift, ExternalDisplaySupport.swift, PowerSupport.swift,
                       ClamshellRecovery.swift, BatteryGuard.swift, TimerPolicy.swift, JiggleTarget.swift
        Ports.swift (protocols for side effects), KeepAwakeEngine.swift, KeepAwakeSettings.swift
        SystemPorts.swift (real IOKit/pmset/CGEvent impls)
      UI/                    # Module_KeepAwake_UI
        KeepAwakeDescriptor.swift, KeepAwakePanelTile.swift, KeepAwakeSettingsPage.swift
    HelmApp/                 # executable
      main.swift, AppDelegate.swift, ModuleHost.swift, ModuleRegistry.swift,
      StatusItemController.swift, HelmPanel.swift, SettingsWindow.swift, AppSettings.swift
  Tests/
    HelmRuntimeTests/NamespacedStoreTests.swift
    Modules/KeepAwake/EngineTests/  (one test file per pure-logic unit)
  Scripts/package-app.sh     # assemble + sign Helm.app
  Resources/HelmApp/Info.plist
```

**Dependency rules (enforced by Package.swift):** `HelmContract` → nothing. `HelmRuntime` → nothing. `HelmUI` → HelmContract. `Module_KeepAwake_Engine` → HelmContract, HelmRuntime (NO SwiftUI/HelmUI). `Module_KeepAwake_UI` → HelmContract, HelmUI, Engine. `HelmApp` → everything. Nothing depends on HelmApp.

---

## Task 1: Package skeleton compiles

**Files:**
- Create: `Package.swift`
- Create: placeholder `Sources/HelmContract/Placeholder.swift`, `Sources/HelmRuntime/Placeholder.swift`, `Sources/HelmUI/Placeholder.swift`, `Sources/Modules/KeepAwake/Engine/Placeholder.swift`, `Sources/Modules/KeepAwake/UI/Placeholder.swift`, `Sources/HelmApp/main.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Helm",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "HelmContract"),
        .target(name: "HelmRuntime"),
        .target(name: "HelmUI", dependencies: ["HelmContract"]),
        .target(
            name: "Module_KeepAwake_Engine",
            dependencies: ["HelmContract", "HelmRuntime"],
            path: "Sources/Modules/KeepAwake/Engine"
        ),
        .target(
            name: "Module_KeepAwake_UI",
            dependencies: ["HelmContract", "HelmUI", "Module_KeepAwake_Engine"],
            path: "Sources/Modules/KeepAwake/UI"
        ),
        .executableTarget(
            name: "HelmApp",
            dependencies: ["HelmContract", "HelmRuntime", "HelmUI",
                           "Module_KeepAwake_Engine", "Module_KeepAwake_UI"]
        ),
        .testTarget(name: "HelmRuntimeTests", dependencies: ["HelmRuntime"]),
        .testTarget(
            name: "Module_KeepAwake_EngineTests",
            dependencies: ["Module_KeepAwake_Engine"],
            path: "Tests/Modules/KeepAwake/EngineTests"
        ),
    ]
)
```

- [ ] **Step 2: Add placeholder sources** so every target has ≥1 file. Each placeholder: `// placeholder` with an empty `enum <TargetName>Placeholder {}`. `HelmApp/main.swift`: `print("Helm")`. Add empty test files with one `import XCTest` + empty `final class SmokeTests: XCTestCase {}` in each test target dir so they compile.

- [ ] **Step 3: Verify build + test**

Run: `swift build`
Expected: builds all targets.
Run: `swift test`
Expected: passes (0 real tests).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: SwiftPM package skeleton (Contract/Runtime/UI/KeepAwake/App)"
```

---

## Task 2: HelmContract — engine/transport/metadata types

**Files:**
- Create: `Sources/HelmContract/ModuleID.swift`, `ModuleIsolation.swift`, `ModulePermission.swift`, `ModuleMetadata.swift`, `StatusAppearance.swift`, `EngineMessage.swift`, `EngineTransport.swift`, `ModuleEngine.swift`
- Delete: `Sources/HelmContract/Placeholder.swift`

- [ ] **Step 1: Core identity + metadata types**

`ModuleID.swift`:
```swift
public struct ModuleID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ raw: String) { self.rawValue = raw }
}
```

`ModuleIsolation.swift`:
```swift
public enum ModuleIsolation: Sendable { case inProcess, xpc }
```

`ModulePermission.swift`:
```swift
public enum ModulePermission: String, Codable, Sendable, CaseIterable {
    case accessibility, screenRecording, adminHelper  // adminHelper = sudoers/pmset
}
```

`ModuleMetadata.swift`:
```swift
public struct ModuleMetadata: Sendable {
    public let id: ModuleID
    public let name: String
    public let summary: String
    public let sfSymbol: String
    public let permissions: [ModulePermission]
    public init(id: ModuleID, name: String, summary: String,
                sfSymbol: String, permissions: [ModulePermission] = []) {
        self.id = id; self.name = name; self.summary = summary
        self.sfSymbol = sfSymbol; self.permissions = permissions
    }
}
```

`StatusAppearance.swift` (tint the host menu-bar icon; color is a palette token, not SwiftUI Color, to stay Foundation-only):
```swift
public struct StatusAppearance: Equatable, Sendable {
    public var tintToken: String?   // palette token, nil = default (white ring)
    public var badge: String?       // optional SF Symbol badge, unused in v1
    public init(tintToken: String? = nil, badge: String? = nil) {
        self.tintToken = tintToken; self.badge = badge
    }
    public static let inactive = StatusAppearance()
}
```

- [ ] **Step 2: Transport-neutral message channel**

`EngineMessage.swift`:
```swift
public struct EngineCommand: Codable, Sendable { public let name: String; public let payload: Data
    public init(name: String, payload: Data = Data()) { self.name = name; self.payload = payload } }
public struct EngineEvent: Codable, Sendable { public let name: String; public let payload: Data
    public init(name: String, payload: Data = Data()) { self.name = name; self.payload = payload } }
```

`EngineTransport.swift`:
```swift
public protocol EngineTransport: Sendable {
    func send(_ command: EngineCommand) async throws -> Data
    var events: AsyncStream<EngineEvent> { get }
}
```

- [ ] **Step 3: ModuleEngine protocol**

`ModuleEngine.swift`:
```swift
public protocol ModuleEngine: AnyObject {
    func activate()
    func deactivate()
    /// Module-specific commands are sent through the typed façade over this
    /// transport (LocalTransport in-process, XPCTransport out-of-process).
    var transport: EngineTransport { get }
}
```

- [ ] **Step 4: Build + commit**

Run: `swift build`
```bash
git add -A && git commit -m "feat(contract): module identity, transport, engine protocols"
```

---

## Task 3: HelmRuntime — NamespacedStore (TDD)

**Files:**
- Create: `Sources/HelmRuntime/NamespacedStore.swift`, `Sources/HelmRuntime/Log.swift`
- Create: `Tests/HelmRuntimeTests/NamespacedStoreTests.swift`
- Delete: `Sources/HelmRuntime/Placeholder.swift`

- [ ] **Step 1: Failing test**

`NamespacedStoreTests.swift`:
```swift
import XCTest
@testable import HelmRuntime

final class NamespacedStoreTests: XCTestCase {
    func makeStore() -> NamespacedStore {
        NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
    }
    func test_keys_are_namespaced() {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: "keep-awake", backing: backing)
        store.set(true, for: "clamshellEnabled")
        XCTAssertEqual(backing.raw["module.keep-awake.clamshellEnabled"] as? Bool, true)
    }
    func test_roundtrip_bool_int_string_array() {
        let s = makeStore()
        s.set(42, for: "n"); s.set(["a","b"], for: "apps"); s.set("x", for: "s")
        XCTAssertEqual(s.int("n", default: 0), 42)
        XCTAssertEqual(s.stringArray("apps"), ["a","b"])
        XCTAssertEqual(s.string("s", default: ""), "x")
    }
    func test_defaults_returned_when_missing() {
        XCTAssertEqual(makeStore().int("missing", default: 20), 20)
        XCTAssertFalse(makeStore().bool("missing", default: false))
    }
    func test_two_namespaces_do_not_collide() {
        let backing = InMemoryKeyValueStore()
        NamespacedStore(namespace: "a", backing: backing).set(1, for: "k")
        NamespacedStore(namespace: "b", backing: backing).set(2, for: "k")
        XCTAssertEqual(NamespacedStore(namespace: "a", backing: backing).int("k", default: 0), 1)
        XCTAssertEqual(NamespacedStore(namespace: "b", backing: backing).int("k", default: 0), 2)
    }
}
```

- [ ] **Step 2: Run — must fail** (`swift test` → NamespacedStore undefined).

- [ ] **Step 3: Implement**

`NamespacedStore.swift`:
```swift
import Foundation

public protocol KeyValueStore: AnyObject {
    func object(forKey: String) -> Any?
    func set(_ value: Any?, forKey: String)
}

public final class InMemoryKeyValueStore: KeyValueStore {
    public var raw: [String: Any] = [:]
    public init() {}
    public func object(forKey k: String) -> Any? { raw[k] }
    public func set(_ v: Any?, forKey k: String) { raw[k] = v }
}

extension UserDefaults: KeyValueStore {}

public final class NamespacedStore {
    private let prefix: String
    private let backing: KeyValueStore
    public init(namespace: String, backing: KeyValueStore) {
        self.prefix = "module.\(namespace)."
        self.backing = backing
    }
    private func k(_ key: String) -> String { prefix + key }
    public func set(_ value: Any?, for key: String) { backing.set(value, forKey: k(key)) }
    public func bool(_ key: String, default d: Bool) -> Bool { backing.object(forKey: k(key)) as? Bool ?? d }
    public func int(_ key: String, default d: Int) -> Int { backing.object(forKey: k(key)) as? Int ?? d }
    public func string(_ key: String, default d: String) -> String { backing.object(forKey: k(key)) as? String ?? d }
    public func stringArray(_ key: String) -> [String] { backing.object(forKey: k(key)) as? [String] ?? [] }
}
```

`Log.swift`:
```swift
import OSLog
public enum Log {
    public static func module(_ id: String) -> Logger { Logger(subsystem: "com.helm.app", category: id) }
}
```

- [ ] **Step 4: Run — must pass.** `swift test`
- [ ] **Step 5: Commit** — `git commit -am "feat(runtime): NamespacedStore + Log (TDD)"`

---

## Task 4: KeepAwake pure logic — Conditions (TDD)

**Files:**
- Create: `Sources/Modules/KeepAwake/Engine/Logic/Conditions.swift`
- Create: `Tests/Modules/KeepAwake/EngineTests/ConditionsTests.swift`
- Delete: `Sources/Modules/KeepAwake/Engine/Placeholder.swift` (in this task)

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import Module_KeepAwake_Engine

final class ConditionsTests: XCTestCase {
    func test_no_inputs_inactive() {
        XCTAssertEqual(Conditions.resolve(.init()), .inactive)
    }
    func test_manual_activates() {
        var i = Conditions.Inputs(); i.manual = true
        XCTAssertEqual(Conditions.resolve(i).isActive, true)
    }
    func test_any_auto_condition_activates_OR() {
        for kp in [\Conditions.Inputs.externalDisplay, \.onPower, \.appRunning, \.timerRunning] {
            var i = Conditions.Inputs(); i[keyPath: kp] = true
            XCTAssertTrue(Conditions.resolve(i).isActive, "\(kp) should activate")
        }
    }
    func test_active_conditions_reported() {
        var i = Conditions.Inputs(); i.externalDisplay = true; i.onPower = true
        XCTAssertEqual(Conditions.resolve(i).conditions, [.externalDisplay, .power])
    }
    func test_suppression_blocks_auto_but_not_manual() {
        var i = Conditions.Inputs(); i.onPower = true; i.suppressed = true
        XCTAssertFalse(Conditions.resolve(i).isActive)
        i.manual = true
        XCTAssertTrue(Conditions.resolve(i).isActive)
    }
}
```

- [ ] **Step 2: Run — fail.**
- [ ] **Step 3: Implement**

```swift
public enum ActiveCondition: Hashable, Sendable { case manual, timer, externalDisplay, power, app }

public enum Conditions {
    public struct Inputs: Equatable {
        public var manual = false
        public var timerRunning = false
        public var externalDisplay = false
        public var onPower = false
        public var appRunning = false
        public var suppressed = false   // manual-off while an auto condition holds
        public init() {}
    }
    public struct Result: Equatable {
        public var isActive: Bool
        public var conditions: Set<ActiveCondition>
        public static let inactive = Result(isActive: false, conditions: [])
    }
    public static func resolve(_ i: Inputs) -> Result {
        if i.manual || i.timerRunning {
            var c: Set<ActiveCondition> = []
            if i.manual { c.insert(.manual) }; if i.timerRunning { c.insert(.timer) }
            if i.externalDisplay { c.insert(.externalDisplay) }
            if i.onPower { c.insert(.power) }; if i.appRunning { c.insert(.app) }
            return Result(isActive: true, conditions: c)
        }
        if i.suppressed { return .inactive }
        var c: Set<ActiveCondition> = []
        if i.externalDisplay { c.insert(.externalDisplay) }
        if i.onPower { c.insert(.power) }; if i.appRunning { c.insert(.app) }
        return Result(isActive: !c.isEmpty, conditions: c)
    }
}
```

- [ ] **Step 4: Run — pass. Step 5: Commit** `git commit -am "feat(keepawake): OR condition resolver (TDD)"`

---

## Task 5: KeepAwake pure logic — display/power/battery/timer/jiggle/clamshell (TDD)

One task, six small pure units, each with its own test file. Implement test→fail→code→pass per unit, then a single commit.

**Files (create each + matching `Tests/.../EngineTests/<Name>Tests.swift`):**
`ExternalDisplaySupport.swift`, `PowerSupport.swift`, `BatteryGuard.swift`, `TimerPolicy.swift`, `JiggleTarget.swift`, `ClamshellRecovery.swift`.

- [ ] **Step 1: ExternalDisplaySupport**
```swift
public enum ExternalDisplaySupport {
    /// External display present = any online display that is not built-in.
    public static func hasExternal(builtInFlags: [Bool]) -> Bool { builtInFlags.contains(false) }
}
```
Tests: `[]→false`, `[true]→false`, `[true,false]→true`, `[false]→true`.

- [ ] **Step 2: PowerSupport**
```swift
public enum PowerSupport {
    public static func isOnPower(powerSourceState: String?) -> Bool { powerSourceState == "AC Power" }
}
```
Tests: `"AC Power"→true`, `"Battery Power"→false`, `nil→false`.

- [ ] **Step 3: BatteryGuard**
```swift
public enum BatteryGuard {
    /// Deactivate when guard on, on battery, and at/below threshold.
    public static func shouldDeactivate(enabled: Bool, isOnBattery: Bool,
                                        percent: Int, threshold: Int) -> Bool {
        enabled && isOnBattery && percent <= threshold
    }
}
```
Tests: off→false; on-power(isOnBattery false)→false; battery 15≤20→true; battery 25>20→false.

- [ ] **Step 4: TimerPolicy**
```swift
public enum TimerPolicy {
    public enum Action: Equatable { case deactivate, continueAsAuto }
    /// On timer expiry: if an auto condition still holds and not suppressed, keep going as auto.
    public static func onExpiry(hasAutoCondition: Bool, suppressed: Bool) -> Action {
        (hasAutoCondition && !suppressed) ? .continueAsAuto : .deactivate
    }
}
```
Tests: no-auto→deactivate; auto & !suppressed→continueAsAuto; auto & suppressed→deactivate.

- [ ] **Step 5: JiggleTarget**
```swift
import CoreGraphics
public enum JiggleTarget {
    /// Point 1px from origin, kept inside bounds (inset 2). nil if bounds degenerate.
    public static func nudge(from p: CGPoint, in bounds: CGRect) -> CGPoint? {
        let f = bounds.insetBy(dx: 2, dy: 2)
        guard f.width > 0, f.height > 0 else { return nil }
        let x = min(max(p.x, f.minX), f.maxX), y = min(max(p.y, f.minY), f.maxY)
        if x + 1 <= f.maxX { return CGPoint(x: x + 1, y: y) }
        if x - 1 >= f.minX { return CGPoint(x: x - 1, y: y) }
        return nil
    }
}
```
Tests: center point → x+1; degenerate bounds → nil; point at right edge → x-1.

- [ ] **Step 6: ClamshellRecovery**
```swift
public enum ClamshellRecovery {
    /// On launch, restore sleep if we recorded disabling it and pmset still shows it disabled.
    public static func shouldRestoreSleep(guardFlagSet: Bool, pmsetShowsDisabled: Bool) -> Bool {
        guardFlagSet && pmsetShowsDisabled
    }
    /// Parse `pmset -g` output for the "SleepDisabled 1" state.
    public static func sleepDisabled(inPmsetOutput out: String) -> Bool {
        out.split(separator: "\n").contains { line in
            let l = line.lowercased()
            return l.contains("sleepdisabled") && l.contains("1")
        }
    }
}
```
Tests: flag+disabled→true; !flag→false; parse `" SleepDisabled\t\t1"`→true; parse `"SleepDisabled 0"`→false.

- [ ] **Step 7: Run all — pass. Commit** `git commit -am "feat(keepawake): pure logic units display/power/battery/timer/jiggle/clamshell (TDD)"`

---

## Task 6: KeepAwake engine ports (protocols for side effects)

**Files:** Create `Sources/Modules/KeepAwake/Engine/Ports.swift`, `KeepAwakeSettings.swift`

- [ ] **Step 1: Ports** — every OS side effect behind a protocol so the engine is testable and the real impls are swappable.

```swift
import CoreGraphics
public protocol SleepAssertions: AnyObject {   // IOKit
    func preventSleep(display: Bool)
    func release()
}
public protocol DisplayInfoPort: AnyObject { func builtInFlags() -> [Bool] }
public protocol PowerInfoPort: AnyObject {
    func snapshot() -> (onBattery: Bool, percent: Int)?
    func startObserving(_ onChange: @escaping () -> Void)
}
public protocol DisplayObserverPort: AnyObject { func startObserving(_ onChange: @escaping () -> Void) }
public protocol AppRunningPort: AnyObject {
    func runningBundleIDs() -> Set<String>
    func startObserving(_ onChange: @escaping () -> Void)
}
public protocol PointerPort: AnyObject { func location() -> CGPoint?; func move(to: CGPoint); func displayBounds(containing: CGPoint) -> CGRect? }
public protocol ClamshellPort: AnyObject {
    func isSudoersInstalled() -> Bool
    func installSudoers(_ done: @escaping (Bool) -> Void)   // admin prompt once
    func setDisableSleep(_ on: Bool) -> Bool                // pmset (passwordless)
    func pmsetReport() -> String
}
public protocol Clock: AnyObject { func schedule(after: TimeInterval, _ block: @escaping () -> Void) -> AnyObject; func now() -> Date }
```

- [ ] **Step 2: Settings reader** over NamespacedStore (typed accessors matching the spec table).

```swift
import HelmRuntime
public struct KeepAwakeSettings {
    let store: NamespacedStore
    public init(store: NamespacedStore) { self.store = store }
    public var autoExternalDisplay: Bool { store.bool("autoExternalDisplay", default: false) }
    public var autoPower: Bool { store.bool("autoPower", default: false) }
    public var autoApps: [String] { store.stringArray("autoApps") }
    public var keepDisplayOn: Bool { store.bool("keepDisplayOn", default: false) }
    public var jiggleEnabled: Bool { store.bool("jiggleEnabled", default: false) }
    public var jiggleIntervalMinutes: Int { max(1, store.int("jiggleIntervalMinutes", default: 5)) }
    public var clamshellEnabled: Bool { store.bool("clamshellEnabled", default: false) }
    public var batteryGuardEnabled: Bool { store.bool("batteryGuardEnabled", default: false) }
    public var batteryGuardPercent: Int { store.int("batteryGuardPercent", default: 20) }
    public var defaultDurationMinutes: Int { store.int("defaultDurationMinutes", default: 0) }
    public var activeTintColor: String { store.string("activeTintColor", default: "green") }
}
```

- [ ] **Step 3: Build. Commit** `git commit -am "feat(keepawake): side-effect ports + settings reader"`

---

## Task 7: KeepAwakeEngine (orchestration, in-process)

**Files:** Create `Sources/Modules/KeepAwake/Engine/KeepAwakeEngine.swift`. Add a test `KeepAwakeEngineTests.swift` driving it with fake ports.

The engine composes the pure units + ports. It conforms to `ModuleEngine`, holds a `LocalTransport` (define a minimal LocalTransport in HelmContract in this task), publishes `EngineEvent`s (`active`, `conditions`, `clamshellActive`, `endDate`), and exposes commands (`activate(minutes:)`, `deactivate`, `toggle`, `setClamshell`).

- [ ] **Step 1: Add `LocalTransport` to HelmContract** (`Sources/HelmContract/LocalTransport.swift`):

```swift
import Foundation
public final class LocalTransport: EngineTransport, @unchecked Sendable {
    public typealias Handler = (EngineCommand) async throws -> Data
    private var handler: Handler = { _ in Data() }
    private let (stream, continuation) = AsyncStream<EngineEvent>.makeStream()
    public init() {}
    public var events: AsyncStream<EngineEvent> { stream }
    public func setHandler(_ h: @escaping Handler) { handler = h }
    public func emit(_ e: EngineEvent) { continuation.yield(e) }
    public func send(_ c: EngineCommand) async throws -> Data { try await handler(c) }
}
```
Commit contract change with this task.

- [ ] **Step 2: Engine tests (fakes)** — cover: activate holds assertion; deactivate releases; battery guard deactivates; auto-condition (fake display) activates then clears; clamshell engaged only when enabled + active; manual-off suppresses auto until condition clears. (Write these against injected fake ports; assert on emitted events + fake state.)

- [ ] **Step 3: Implement `KeepAwakeEngine`** composing Tasks 4–6. Key behaviors (from spec): recompute `Conditions.Inputs` on any port change (debounced), apply/release `SleepAssertions`, engage/disengage clamshell via `ClamshellPort` (+ guard flag in store for recovery), battery timer via `Clock`, jiggle timer via `Clock`, timer expiry via `TimerPolicy`. `activate()`/`deactivate()` from `ModuleEngine` map to enable/disable of monitoring. On init call `ClamshellRecovery` path.

- [ ] **Step 4: Run tests — pass. Commit** `git commit -am "feat(keepawake): engine orchestration + LocalTransport (TDD)"`

---

## Task 8: Real SystemPorts (IOKit / pmset / CGEvent / power / display)

**Files:** Create `Sources/Modules/KeepAwake/Engine/SystemPorts.swift` — production conformances to the Task 6 protocols. No unit tests (hardware side effects); verified live in Task 12.

- [ ] **Step 1:** Implement `IOKitSleepAssertions` (`IOPMAssertionCreateWithName` for `PreventUserIdleSystemSleep` + optional `PreventUserIdleDisplaySleep`, release on `release()`).
- [ ] **Step 2:** `CGDisplayInfo` (`CGGetOnlineDisplayList` + `CGDisplayIsBuiltin`), `IOPSPowerInfo` (`IOPSCopyPowerSourcesInfo` + `IOPSNotificationCreateRunLoopSource`), `WorkspaceAppPort` (KVO on `NSWorkspace.shared.runningApplications`), `CGEventPointer` (`CGEvent` location/move + `CGDisplayBounds`).
- [ ] **Step 3:** `PmsetClamshellPort` — sudoers install (admin prompt via `osascript`/AuthorizationServices), `pmset disablesleep 0/1` via passwordless sudo, `pmset -g` report. Reuse ClamshellRecovery parser. **Guarantee**: never leave sleep disabled — engine writes guard flag before disabling; recovery restores.
- [ ] **Step 4:** Build. Commit `git commit -am "feat(keepawake): production system ports"`

---

## Task 9: HelmUI — contract UI types + design system

**Files:** Create `Sources/HelmUI/ModuleDescriptor.swift`, `ModuleViewModel.swift`, `MenuBarContribution.swift`, `DesignSystem/PaletteColor.swift`, `DesignSystem/RingIcon.swift`. Delete `HelmUI/Placeholder.swift`.

- [ ] **Step 1: PaletteColor** — map palette tokens ↔ SwiftUI `Color` (white/red/orange/yellow/green/mint/cyan/blue/purple/pink). Include `Color(token:)` and an ordered `all` for the picker.
- [ ] **Step 2: RingIcon** — draws the menu-bar ring as an `NSImage` template; a tinted variant given a palette token (white when inactive). Used by the host status item.
- [ ] **Step 3: ModuleViewModel** — `@MainActor` `ObservableObject` subscribing to `engine.transport.events`, decoding known events into `@Published` state (`isActive`, `activeConditions`, `clamshellActive`, `endDate`, `statusAppearance`, `lifecycle`). Generic enough for any module.
- [ ] **Step 4: MenuBarContribution + ModuleDescriptor**

```swift
import SwiftUI
import HelmContract
public struct MenuBarContribution { public var panelTile: AnyView?; public var statusItem: StatusItemSpec?
    public init(panelTile: AnyView? = nil, statusItem: StatusItemSpec? = nil) { self.panelTile = panelTile; self.statusItem = statusItem } }
public struct StatusItemSpec { /* reserved v1: unused */ public init() {} }

public enum ModuleCategory: String, CaseIterable { case power, clipboard, window, media, files, appearance, misc }

@MainActor public protocol ModuleDescriptor {
    static var id: ModuleID { get }
    static var metadata: ModuleMetadata { get }
    static var isolation: ModuleIsolation { get }
    static var category: ModuleCategory { get }
    func makeEngine(store: Any) -> any ModuleEngine   // store = NamespacedStore, kept Any to avoid HelmRuntime dep in HelmUI
    func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution?
    func settingsPage(_ vm: ModuleViewModel) -> AnyView
}
```
(If the `Any` store feels loose, an alternative is a small `ModuleStore` protocol in HelmContract that NamespacedStore conforms to; note as a possible refinement, not required for v1.)

- [ ] **Step 5: Build. Commit** `git commit -am "feat(ui): module descriptor, view model, palette + ring icon"`

---

## Task 10: KeepAwake UI (descriptor, panel tile, settings page)

**Files:** Create `Sources/Modules/KeepAwake/UI/KeepAwakeDescriptor.swift`, `KeepAwakePanelTile.swift`, `KeepAwakeSettingsPage.swift`. Delete `UI/Placeholder.swift`.

- [ ] **Step 1: KeepAwakeDescriptor** — `id = ModuleID("keep-awake")`, metadata (name "Keep Awake", SF symbol "moon.zzz.fill", permissions `[.adminHelper]`), `isolation = .inProcess`, `category = .power`. `makeEngine(store:)` builds `KeepAwakeEngine` with `SystemPorts` + `KeepAwakeSettings`. `menuBar` returns `panelTile`. `settingsPage` returns the page.
- [ ] **Step 2: KeepAwakePanelTile** — toggle on/off (sends `toggle`/`activate(minutes:)`), timer preset row (15m/1h/2h/∞), active-condition indicator text from `vm.activeConditions`. Bind to `ModuleViewModel`.
- [ ] **Step 3: KeepAwakeSettingsPage** — sections per spec (Автоматизация: monitor/charger toggles + app picker; Поведение: keep-display-on, jiggle+interval, default timer; Закрытая крышка: clamshell toggle + sudoers status; Батарея: guard+percent; Вид: active color palette picker). Writes to `NamespacedStore`; engine observes via `UserDefaults.didChange` or an explicit `settingsChanged` command. App picker: minimal installed-apps list (bundleID) — a simple NSOpenPanel-to-/Applications or `NSWorkspace` enumeration; keep basic in v1.
- [ ] **Step 4: Build. Commit** `git commit -am "feat(keepawake): panel tile + settings page + descriptor"`

---

## Task 11: HelmApp — host, registry, status item, panel, settings window

**Files:** Create `Sources/HelmApp/{main.swift,AppDelegate.swift,ModuleHost.swift,ModuleRegistry.swift,StatusItemController.swift,HelmPanel.swift,SettingsWindow.swift,AppSettings.swift}`. Replace placeholder `main.swift`.

- [ ] **Step 1: ModuleHost + ModuleRegistry** — registry = static `[any ModuleDescriptor]` (KeepAwakeDescriptor). Host: `bootstrap()` reads `module.<id>.enabled`, lazily `makeEngine` + `activate` for enabled; `setEnabled`; `engine(for:)`; per-id `NamespacedStore(backing: .standard)`; `lifecycle`. XPC branch stubbed (no `.xpc` module yet) — assert/log if encountered.
- [ ] **Step 2: StatusItemController** — one `NSStatusItem` with `RingIcon` (white template). Observes each enabled module's `ModuleViewModel.statusAppearance`; tints ring to the active module's palette token (Keep Awake active → its color). Left click → toggle `HelmPanel`.
- [ ] **Step 3: HelmPanel** — borderless `NSPanel` hosting a SwiftUI list of enabled modules' `panelTile`s (Keep Awake tile). Non-activating (Control-Center-like). (Design-system polish deferred; functional first.)
- [ ] **Step 4: SettingsWindow** — standard window, sidebar of modules grouped by `category` with an enable toggle per row, detail = selected module's `settingsPage`. Plus an "About"/app section.
- [ ] **Step 5: AppDelegate + main** — `NSApplication`, `setActivationPolicy(.accessory)`, build host, bootstrap, install status item. `main.swift` boots `NSApplication` with the delegate.
- [ ] **Step 6: Build (`swift build`). Commit** `git commit -am "feat(app): module host, registry, status item, panel, settings window"`

---

## Task 12: Package into runnable Helm.app + live verification

**Files:** Create `Scripts/package-app.sh`, `Resources/HelmApp/Info.plist`.

- [ ] **Step 1: Info.plist** — `LSUIElement = true`, bundle id `com.helm.app` (placeholder; final id is an open item), `CFBundleName Helm`, `LSMinimumSystemVersion 26.0`, usage strings if needed.
- [ ] **Step 2: package-app.sh** — `swift build -c release`, assemble `build/Helm.app` (Contents/MacOS/HelmApp, Info.plist, ring asset if any), ad-hoc `codesign --deep`. Print the path.
- [ ] **Step 3: Run** `bash Scripts/package-app.sh` then `open build/Helm.app`. Menu-bar ring appears.
- [ ] **Step 4: Live checks (manual, user-assisted for hardware):**
  - Toggle on from panel → ring tints to chosen color; `pmset -g assertions` shows `PreventUserIdleSystemSleep` owned by Helm.
  - Toggle off → assertion released, ring white.
  - Enable "at external display" / "on power" → connect/disconnect flips state.
  - Clamshell toggle → one admin prompt; with lid closed on external display the Mac stays awake (`pmset -g` shows `SleepDisabled 1`); disabling / quitting restores `0`.
  - Jiggle on → pointer nudges each interval.
  - Battery guard → on battery below threshold auto-off.
- [ ] **Step 5: Commit** `git commit -am "build: package Helm.app + Info.plist; keep-awake live-verified"`

---

## Notes for the implementer

- **TDD is mandatory for pure logic (Tasks 3–7).** Side-effect ports (Task 8) and UI/app (9–12) are integration — no forced unit tests, verified by build + Task 12 live checks.
- **Never leave sleep disabled.** The clamshell guard-flag + recovery path is a correctness requirement, not a nicety (the exact bug that motivated this module in the fork).
- **Keep `Module_KeepAwake_Engine` free of SwiftUI** — if an import creeps in, the headless/XPC guarantee breaks. Package.swift has no UI dep on it; keep it that way.
- **Deferred (not this plan):** XPC transport + `HelmModuleHostXPC` target, external-module manifest/SDK, additional icon shapes, global hotkey. Contract reserves the seams.
- Final bundle id + app name confirmation are open items from the architecture spec.
```
