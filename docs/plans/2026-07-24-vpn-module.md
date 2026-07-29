# VPN Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port the fork's VPN (connect/disconnect system VPNs via `scutil --nc` + per-app auto-connect) into a Helm `vpn` module (Engine headless + UI, ports, TDD).

**Architecture:** Same pattern as Keep Awake. Pure logic TDD'd (XCTest, `swift test`), side effects behind ports, `.inProcess`. Source of truth for the port = fork files at `/Users/r.strlnkv/Documents/Claude/vorssaint-utils/Sources/HelmUtility/Services/VPN/`. See [VPN spec](../specs/2026-07-24-vpn-module-design.md).

> *Note added 2026-07-29:* that fork path no longer exists anywhere on disk — the plan is kept as the record of how the module was built, but the pointer is dead and the shipped module in `Sources/Modules/VPN/` is the only source of truth now.

**Tech Stack:** Swift 6, SwiftPM, AppKit+SwiftUI, macOS 26, XCTest. Same repo, same conventions as Keep Awake.

---

## Task VP1: Targets + HelmUI tweaks

**Files:** `Package.swift`; `Sources/HelmUI/MenuBarContribution.swift` (add category); `Sources/HelmUI/ModuleViewModel.swift` (expose transport); placeholders for the two new targets + a test file.

- [ ] **Step 1: Package.swift** — add after the KeepAwake targets:
```swift
        .target(
            name: "Module_VPN_Engine",
            dependencies: ["HelmContract", "HelmRuntime"],
            path: "Sources/Modules/VPN/Engine"
        ),
        .target(
            name: "Module_VPN_UI",
            dependencies: ["HelmContract", "HelmUI", "Module_VPN_Engine"],
            path: "Sources/Modules/VPN/UI"
        ),
```
Add `Module_VPN_Engine` + `Module_VPN_UI` to `HelmApp` dependencies. Add a test target:
```swift
        .testTarget(
            name: "Module_VPN_EngineTests",
            dependencies: ["Module_VPN_Engine"],
            path: "Tests/Modules/VPN/EngineTests"
        ),
```

- [ ] **Step 2:** In `ModuleCategory` (HelmUI/MenuBarContribution.swift) add `case network`. Put it in the enum (order: `power, network, clipboard, ...`).

- [ ] **Step 3:** In `ModuleViewModel` (HelmUI) make the transport reachable for module-specific view models:
```swift
    public let transport: EngineTransport
    public init(transport: EngineTransport) {
        self.transport = transport
        ...existing...
    }
```
(Change the stored `private let transport` to `public let transport`.)

- [ ] **Step 4:** Placeholder sources: `Sources/Modules/VPN/Engine/Placeholder.swift` (`enum VPNEnginePlaceholder {}`), `Sources/Modules/VPN/UI/Placeholder.swift` (`enum VPNUIPlaceholder {}`), and `Tests/Modules/VPN/EngineTests/SmokeTests.swift` (`import XCTest` / `final class VPNSmokeTests: XCTestCase { func test_smoke() { XCTAssertTrue(true) } }`).

- [ ] **Step 5:** `swift build` + `swift test` green. Commit `feat(vpn): targets + HelmUI category/transport tweaks`.

---

## Task VP2: VPNListParser (TDD) — port VPNSupport

**Files:** Create `Sources/Modules/VPN/Engine/Logic/VPNModels.swift`, `VPNListParser.swift`; `Tests/Modules/VPN/EngineTests/VPNListParserTests.swift`. Delete Engine/Placeholder.swift.

- [ ] **Step 1: Models** (`VPNModels.swift`) — public port:
```swift
public enum VPNStatus: String, Equatable, Sendable {
    case connected, connecting, disconnected, disconnecting, unknown
}
public struct VPNConnection: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public var status: VPNStatus
    public let kind: String?
    public init(id: String, name: String, status: VPNStatus, kind: String?) {
        self.id = id; self.name = name; self.status = status; self.kind = kind
    }
}
```

- [ ] **Step 2: Failing test** — port the parser cases. Real `scutil --nc list` line shape:
`* (Disconnected)   <UUID>  IPSec  "NBCom VPN"  [...]`. Tests:
```swift
import XCTest
@testable import Module_VPN_Engine

final class VPNListParserTests: XCTestCase {
    func test_parseStatus() {
        XCTAssertEqual(VPNListParser.parseStatus("Connected"), .connected)
        XCTAssertEqual(VPNListParser.parseStatus(" disconnected "), .disconnected)
        XCTAssertEqual(VPNListParser.parseStatus("bogus"), .unknown)
    }
    func test_parseList_name_status_id() {
        let out = "* (Connected)   1B2C3D4E-0000-0000-0000-000000000000  IPSec  \"NBCom VPN\"  [foo]"
        let list = VPNListParser.parseList(out)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].name, "NBCom VPN")
        XCTAssertEqual(list[0].status, .connected)
        XCTAssertEqual(list[0].id, "1B2C3D4E-0000-0000-0000-000000000000")
    }
    func test_parseList_skips_garbage_lines() {
        XCTAssertTrue(VPNListParser.parseList("garbage\nno match here").isEmpty)
    }
    func test_defaultConnection_sole() {
        let c = [VPNConnection(id: "a", name: "A", status: .disconnected, kind: nil)]
        XCTAssertEqual(VPNListParser.defaultConnection(from: c, lastUsedName: nil)?.name, "A")
    }
    func test_defaultConnection_prefers_lastUsed() {
        let c = [VPNConnection(id: "a", name: "A", status: .disconnected, kind: nil),
                 VPNConnection(id: "b", name: "B", status: .disconnected, kind: nil)]
        XCTAssertEqual(VPNListParser.defaultConnection(from: c, lastUsedName: "B")?.name, "B")
        XCTAssertEqual(VPNListParser.defaultConnection(from: c, lastUsedName: nil)?.name, "A")
    }
}
```

- [ ] **Step 3: Implement** `VPNListParser` — port `VPNSupport` verbatim (rename enum → `VPNListParser`, make `static` methods `public`; keep the private `between`/`uuidLike`/`kindBeforeQuote` helpers). Copy from fork `Services/VPN/VPNSupport.swift`.

- [ ] **Step 4:** `swift test` green. Commit `feat(vpn): scutil list parser (TDD, port)`.

---

## Task VP3: VPNRules (TDD) — port VPNRulesSupport

**Files:** `Sources/Modules/VPN/Engine/Logic/VPNRules.swift`; `Tests/Modules/VPN/EngineTests/VPNRulesTests.swift`.

- [ ] **Step 1: Failing test:**
```swift
import XCTest
@testable import Module_VPN_Engine

final class VPNRulesTests: XCTestCase {
    func test_encode_decode_roundtrip() {
        let rules = ["com.x": VPNAppRule(vpnName: "A", connectOnLaunch: true, disconnectOnQuit: false)]
        XCTAssertEqual(VPNRules.decode(VPNRules.encode(rules)), rules)
    }
    func test_decode_legacy_string_map() {
        let decoded = VPNRules.decode("{\"com.x\":\"A\"}")
        XCTAssertEqual(decoded["com.x"], VPNAppRule(vpnName: "A"))  // both flags default true
    }
    func test_decode_garbage_is_empty() {
        XCTAssertTrue(VPNRules.decode("not json").isEmpty)
    }
    func test_valid_drops_unknown_vpn() {
        let rules = ["com.x": VPNAppRule(vpnName: "A"), "com.y": VPNAppRule(vpnName: "GONE")]
        let conns = [VPNConnection(id: "1", name: "A", status: .disconnected, kind: nil)]
        XCTAssertEqual(VPNRules.valid(rules, against: conns).keys.sorted(), ["com.x"])
    }
}
```

- [ ] **Step 2: Implement** — port fork `VPNRulesSupport.swift`: `VPNAppRule` (public Codable, default init flags true) + `VPNRules` (public `encode`/`decode`(+legacy)/`valid`). Rename `VPNRulesSupport`→`VPNRules`.

- [ ] **Step 3:** `swift test` green. Commit `feat(vpn): rules codec + validation (TDD, port)`.

---

## Task VP4: VPNAutoConnectCore (TDD) — port as-is

**Files:** `Sources/Modules/VPN/Engine/Logic/VPNAutoConnectCore.swift`; `Tests/Modules/VPN/EngineTests/VPNAutoConnectCoreTests.swift`.

- [ ] **Step 1: Failing test:**
```swift
import XCTest
@testable import Module_VPN_Engine

final class VPNAutoConnectCoreTests: XCTestCase {
    func test_launch_connects_on_first_and_not_again() {
        var core = VPNAutoConnectCore(rules: ["a": VPNAppRule(vpnName: "V"), "b": VPNAppRule(vpnName: "V")])
        var connects: [String] = []
        core.appLaunched("a", connect: { connects.append($0) }, disconnect: { _ in })
        core.appLaunched("b", connect: { connects.append($0) }, disconnect: { _ in })
        XCTAssertEqual(connects, ["V"])  // second app: already connected
    }
    func test_quit_disconnects_only_when_last_leaves() {
        var core = VPNAutoConnectCore(rules: ["a": VPNAppRule(vpnName: "V"), "b": VPNAppRule(vpnName: "V")])
        core.appLaunched("a", connect: { _ in }, disconnect: { _ in })
        core.appLaunched("b", connect: { _ in }, disconnect: { _ in })
        var disc: [String] = []
        core.appTerminated("a", connect: { _ in }, disconnect: { disc.append($0) })
        XCTAssertEqual(disc, [])       // b still running
        core.appTerminated("b", connect: { _ in }, disconnect: { disc.append($0) })
        XCTAssertEqual(disc, ["V"])    // last one gone
    }
    func test_flags_respected() {
        var core = VPNAutoConnectCore(rules: ["a": VPNAppRule(vpnName: "V", connectOnLaunch: false, disconnectOnQuit: false)])
        var connects: [String] = [], disc: [String] = []
        core.appLaunched("a", connect: { connects.append($0) }, disconnect: { _ in })
        core.appTerminated("a", connect: { _ in }, disconnect: { disc.append($0) })
        XCTAssertEqual(connects, []); XCTAssertEqual(disc, [])
    }
    func test_unmapped_app_ignored() {
        var core = VPNAutoConnectCore(rules: [:])
        var n = 0
        core.appLaunched("x", connect: { _ in n += 1 }, disconnect: { _ in n += 1 })
        XCTAssertEqual(n, 0)
    }
}
```

- [ ] **Step 2: Implement** — port fork `VPNAutoConnectCore.swift` verbatim (make `struct`, `init`, `appLaunched`, `appTerminated`, `activeVPNs` `public`; `VPNAppRule` already public from VP3).

- [ ] **Step 3:** `swift test` green. Commit `feat(vpn): per-app auto-connect ref-counting (TDD, port)`.

---

## Task VP5: Ports + settings reader

**Files:** `Sources/Modules/VPN/Engine/Ports.swift`, `VPNSettings.swift`.

- [ ] **Step 1: Ports:**
```swift
import Foundation
public struct VPNCredentials: Sendable {
    public var user: String?; public var password: String?; public var secret: String?
    public init(user: String? = nil, password: String? = nil, secret: String? = nil) {
        self.user = user; self.password = password; self.secret = secret
    }
}
public protocol VPNRunnerPort: AnyObject { func run(_ args: [String]) -> String }
public protocol VPNCredentialsPort: AnyObject { func credentials(for name: String) -> VPNCredentials? }
public protocol AppObserverPort: AnyObject {
    func runningBundleIDs() -> Set<String>
    func startObserving(_ onChange: @escaping @Sendable () -> Void)
}
```

- [ ] **Step 2: Settings reader:**
```swift
import HelmRuntime
public struct VPNSettings {
    let store: NamespacedStore
    public init(store: NamespacedStore) { self.store = store }
    public var rulesJSON: String { store.string("vpnAppRules", default: "{}") }
    public var lastUsedName: String? {
        let s = store.string("lastUsedName", default: ""); return s.isEmpty ? nil : s
    }
    public func setLastUsed(_ name: String) { store.set(name, for: "lastUsedName") }
}
```

- [ ] **Step 3:** build green. Commit `feat(vpn): ports + settings reader`.

---

## Task VP6: VPNEngine (orchestration, TDD with fakes)

**Files:** `Sources/Modules/VPN/Engine/VPNEngine.swift`; `Tests/Modules/VPN/EngineTests/{Fakes,VPNEngineTests}.swift`.

`VPNEngine: ModuleEngine` (uses `LocalTransport` from HelmContract). Ported behavior from fork `VPNService` + `VPNAutoConnectService`, adapted to headless engine:

- Init injects: `settings: VPNSettings`, `runner: VPNRunnerPort`, `credentials: VPNCredentialsPort?`, `apps: AppObserverPort`, `transport: LocalTransport = LocalTransport()`.
- Sync state getters for tests: `public private(set) var connections`, `autoConnected`, `runState`.
- `refresh()`: `connections = VPNListParser.parseList(runner.run(["--nc","list"]))`.
- `defaultConnection`: connected/connecting first, else `VPNListParser.defaultConnection(from:lastUsedName:)`.
- `toggleDefault()`, `connect(name, auto:)`, `disconnect(name)`, `status(name)` — port from `VPNService` (creds path: if `credentials?.credentials(for:)` has non-empty secret, append `--user/--password/--secret`; the fork ran that off-main — in tests keep it synchronous by injecting a runner; production runner may dispatch). `scheduleRefresh` after 0.6s (emit state after).
- Auto layer: hold a `VPNAutoConnectCore`. `reloadRules()`: `core.rules = VPNRules.valid(VPNRules.decode(settings.rulesJSON), against: connections)`.
- `activate()`: `refresh()` → `reloadRules()` → seed running apps (`for id in apps.runningBundleIDs(): core.appLaunched(id, connect: { connect($0, auto:true) }, disconnect: { _ in })`) → `apps.startObserving { self.appsChanged() }` (store previous bundleID set; diff launched/quit; call `core.appLaunched/appTerminated` with connect=`{connect($0,auto:true)}`, disconnect=`{disconnect($0)}`).
- `deactivate()`: stop observing (AppObserverPort has no stop in v1 — acceptable; guard a `running` flag so callbacks no-op after deactivate).
- Command handler: `toggle`→toggleDefault; `connect{name}`→connect; `disconnect{name}`→disconnect; `refresh`→refresh+emit; `reloadRules`→reloadRules. Emit `state {connections, autoConnected, runState, defaultName}` after changes.

- [ ] **Step 1:** Fakes: `FakeVPNRunner` (records issued arg-arrays; returns a canned `--nc list` output settable per test), `FakeCreds`, `FakeApps` (settable running set + captured onChange).
- [ ] **Step 2:** Tests: toggle connects the default when disconnected / disconnects when connected (assert issued `["--nc","start","A"]` / `["--nc","stop","A"]`); connect with creds appends `--user/--password/--secret`; auto: rule for bundle "a"→"V", fire FakeApps launch of "a" → issued start "V" and `autoConnected` contains "V"; quit "a" → issued stop "V"; manual connections not torn down. Write red→green.
- [ ] **Step 3:** Implement engine. `swift test` green (all prior + new). Commit `feat(vpn): engine orchestration + auto-connect wiring (TDD)`.

---

## Task VP7: SystemPorts (scutil + keychain)

**Files:** `Sources/Modules/VPN/Engine/SystemPorts.swift` — production ports. No unit tests.

- [ ] **Step 1:** `ScutilRunner: VPNRunnerPort` — `Shell`-style Process wrapper: `run(args)` = `/usr/sbin/scutil` + args → stdout. (Add a small `Shell` helper local to this file, or reuse one if present.)
- [ ] **Step 2:** `WorkspaceAppObserver: AppObserverPort` — `runningBundleIDs()` from `NSWorkspace.shared.runningApplications`; `startObserving` via KVO on `\.runningApplications` (fork used KVO — more reliable than notifications for Catalyst apps).
- [ ] **Step 3:** `KeychainCredentials: VPNCredentialsPort` — port fork `VPNService+System.systemKeychainCredentials`: `scutil --nc show name` → `AuthPassword`(uuid)/`AuthName`; read Helm login-keychain cache (`com.helm.vpn`) first (no prompt); else read System.keychain (`security find-generic-password -w -s <uuid>.SS ... /Library/Keychains/System.keychain`, prompts once) and cache via `security add-generic-password -U -T /usr/bin/security`. nil when no shared secret. Never log secrets.
- [ ] **Step 4:** Factory `VPNSystemPorts { runner, credentials, apps }`. Build green. Commit `feat(vpn): production scutil + keychain ports`.

---

## Task VP8: VPN UI + registry

**Files:** `Sources/Modules/VPN/UI/{VPNDescriptor,VPNViewModel,VPNPanelTile,VPNSettingsPage}.swift`; register in `Sources/HelmApp/ModuleRegistry.swift`. Delete UI/Placeholder.swift.

- [ ] **Step 1: VPNViewModel** — `@MainActor ObservableObject` subscribing to `transport.events`, decode `state` → `@Published connections:[VPNConnection]`, `autoConnected:Set<String>`, `defaultName:String?`, `runState`. (State payload Codable mirror; `VPNConnection`/`VPNStatus` need Codable for the wire — add `Codable` to them in the engine models, or send a lightweight DTO. Simplest: make `VPNConnection`/`VPNStatus` `Codable` in VPNModels.swift.)
- [ ] **Step 2: VPNDescriptor** — `ModuleDescriptor`: id `vpn`, metadata (name "VPN", sfSymbol "lock.shield", permissions []), isolation `.inProcess`, category `.network`. `makeEngine(store:)` = VPNEngine + VPNSystemPorts + VPNSettings. `menuBar` → panelTile built with `VPNViewModel(transport: vm.transport)`. `settingsPage` similarly.
- [ ] **Step 3: VPNPanelTile** — default VPN row (name + status dot + tap toggles via `send("toggle")`); if `connections.count > 1`, a disclosure list of all, tapping a row sends `connect`/`disconnect {name}` per current status. Port `VPNSection` layout.
- [ ] **Step 4: VPNSettingsPage** — Section "Connections": list connections + status. Section "Per-app automation": each rule row = app icon+name (resolve via NSWorkspace), VPN Picker (from connections), toggles connectOnLaunch/disconnectOnQuit, delete; an "Add app…" button (NSOpenPanel → bundleID → default rule to the default VPN). Writes `vpnAppRules` JSON via `VPNRules.encode` → `send("reloadRules")`. Reuse the KeepAwake app-picker pattern.
- [ ] **Step 5: Register** — `ModuleRegistry.all = [KeepAwakeDescriptor(), VPNDescriptor()]`.
- [ ] **Step 6:** build + `swift test` green. Commit `feat(vpn): panel tile, settings, descriptor + registry`.

---

## Task VP9: Package + live verify

- [ ] **Step 1:** `bash Scripts/package-app.sh`; relaunch. VPN appears in Settings sidebar under "Network" with an enable switch; panel shows a VPN tile.
- [ ] **Step 2: Live checks (user-assisted):** toggle connects/disconnects the system VPN (verify in System Settings › Network); a per-app rule connects on app launch and disconnects on quit; L2TP/IPSec (NBCom) connects silently after the one-time keychain prompt.
- [ ] **Step 3:** Commit any fixes. Done.

---

## Notes for the implementer

- Port faithfully from the fork files; adjust only: make types `public`, drop the fork's `AppFeature.vpn.isAvailable` gate (the host owns enable/disable now), drop `DefaultsKey.*` in favor of the `VPNSettings`/NamespacedStore, replace the ObservableObject `@Published` push with `EngineEvent` "state" emission.
- Keep `Module_VPN_Engine` free of SwiftUI (SystemPorts may import AppKit for NSWorkspace, like KeepAwake).
- Secrets: never log; keychain reads via `security` CLI exactly as the fork.
- The credential-bearing `scutil --nc start` can block — production runner should run those off the main thread (fork did); keep tests synchronous via the injected fake runner.
