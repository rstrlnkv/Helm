# VPN automation feedback — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a VPN rule connects or disconnects a tunnel by itself, the menu-bar ring spins twice and — at the user's choice — the connection is named, either beside the icon or as a macOS banner.

**Architecture:** The engine records the last automation in the `state` payload it already emits. `StatusAppearance` gains a level-triggered `spinUntil: Date?`, so the host animates while that moment is in the future rather than reacting to an event it might miss. All decisions (is this an automation, what phase is the spin in, which module drives the icon, what does the notice mode produce) are pure functions with tests; the frame timer, the drawing and the banner are thin shells around them.

**Tech stack:** Swift 6, SwiftPM, AppKit + SwiftUI, `UNUserNotificationCenter`, no external dependencies. Read `ARCHITECTURE.md` § Status item, § Motion and § Permissions, and `CLAUDE.md`, before Task 6.

**Spec:** `docs/superpowers/specs/2026-07-29-vpn-automation-feedback-design.md`

**Baseline:** `swift test` is **1462 tests, 0 failures**. Every task ends green.

**Status: complete.** All ten tasks are done, and both defects Task 10's
measurements found are **fixed** (2026-07-29):

1. **A countdown did not suppress the spin** (spec Risk 4). `StatusPlan.choose`
   now ranks a live `timerProgress` above a live spin, which is what makes
   `StatusPlan.spins`'s existing guard reachable — it was inert because no
   descriptor produces one appearance carrying both fields, and the only test
   that covered it built that shape by hand. The test is now over two
   appearances, the composition the app actually has.
2. **A revocation was only heard when the VPN settings page appeared** (spec
   Risk 1, last bullet). The firing asks: `AutomationNotice.announce` reads
   `authorizationState()` — a read that prompts nobody — and returns it, and the
   label decision is judged against that instead of the stored mirror. The
   mirror stays as what the settings page displays.
   `testEveryModeThatSpeaksAtAllSpeaksExactlyOnce` now covers every mode against
   every answer macOS can give, with the mirror deliberately holding the
   opposite.

One thing Task 10 found is **not a defect and is now written down as behaviour**
(spec Risk 5): while another module owns the icon a firing is not announced in
the menu bar at all — with a countdown, neither the spin nor the name; with a
plain tint, the spin only. There is one status item and one title slot. The
banner is the mode that survives contention, and the spec's table is marked as
the uncontended case.

Not part of this plan, found while running it: **an ad-hoc rebuild makes every
launch raise a modal keychain prompt, and Helm's launch blocks behind it.**
`AutopilotEngine.init` reads the rule-seal key synchronously from
`ModuleHost.bootstrap`, on the main thread, inside
`applicationDidFinishLaunching` — so until the panel is answered there is no
status item and no app. Previously recorded as something a second instance
caused; a single installed instance reproduces it after any rebuild, because the
designated requirement of an ad-hoc build is the cdhash alone.

---

## File structure

| File | Responsibility |
|---|---|
| `Sources/Modules/VPN/Engine/Logic/VPNAutomation.swift` | **Create.** The value describing one firing, and the windows that decide how long it is shown. Pure. |
| `Sources/Modules/VPN/Engine/Logic/VPNNotice.swift` | **Create.** The three notice modes and what each produces. Pure. |
| `Sources/Modules/VPN/Engine/VPNEngine.swift` | **Modify.** Record an automation on the auto-connect and auto-drop paths; carry it in `StatePayload`. |
| `Sources/Modules/VPN/Engine/VPNSettings.swift` | **Modify.** Read and write the notice mode. |
| `Sources/Modules/VPN/Engine/Ports.swift` | **Modify.** `AutomationNoticePort`. |
| `Sources/Modules/VPN/Engine/SystemPorts.swift` | **Modify.** `UNUserNotificationCenter` implementation. |
| `Sources/Modules/VPN/UI/VPNViewModel.swift` | **Modify.** Expose the last automation; post the banner. |
| `Sources/Modules/VPN/UI/VPNDescriptor.swift` | **Modify.** `statusAppearance` and `statusChanges`. |
| `Sources/Modules/VPN/UI/VPNSettingsPage.swift` | **Modify.** The picker and the authorization note. |
| `Sources/Modules/VPN/UI/VPNStrings.swift` | **Modify.** Eight languages for every new string. |
| `Sources/HelmContract/StatusAppearance.swift` | **Modify.** `spinUntil`. |
| `Sources/HelmApp/StatusPlan.swift` | **Create.** Which appearance drives the icon. Pure, so it is testable without a status bar. |
| `Sources/HelmApp/StatusItemController.swift` | **Modify.** The frame timer and the Reduce Motion check. |
| `Sources/HelmUI/DesignSystem/RingIcon.swift` | **Modify.** `makeSpinner` and the frame cache. |

---

### Task 1: The automation value and its two windows

**Files:**
- Create: `Sources/Modules/VPN/Engine/Logic/VPNAutomation.swift`
- Test: `Tests/Modules/VPN/EngineTests/VPNAutomationTests.swift`

- [x] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Module_VPN_Engine

/// Two windows, one firing. The ring spins for a moment; the name stays long
/// enough to be read. Both are measured from an injected `now`, never the
/// machine's clock — a test that asks what time it is asks a different question
/// on every run.
final class VPNAutomationTests: XCTestCase {
    private let fired = Date(timeIntervalSince1970: 1_000_000)
    private func automation(_ kind: VPNAutomation.Kind = .connected) -> VPNAutomation {
        VPNAutomation(at: fired, name: "work", kind: kind)
    }

    func testTheSpinRunsForItsWindowAndThenStops() {
        XCTAssertEqual(VPNAutomation.spinPhase(automation(), now: fired), 0)
        let mid = VPNAutomation.spinPhase(automation(), now: fired.addingTimeInterval(0.6))
        XCTAssertEqual(try XCTUnwrap(mid), 0.5, accuracy: 0.001)
        XCTAssertNil(VPNAutomation.spinPhase(automation(), now: fired.addingTimeInterval(1.2)),
                     "the spin outlived its window")
        XCTAssertNil(VPNAutomation.spinPhase(automation(), now: fired.addingTimeInterval(9)))
    }

    func testTheNameOutlivesTheSpin() {
        XCTAssertTrue(VPNAutomation.showsName(automation(), now: fired.addingTimeInterval(1.5)),
                      "the name should still be readable after the ring settles")
        XCTAssertFalse(VPNAutomation.showsName(automation(), now: fired.addingTimeInterval(3.1)))
    }

    /// A clock that has gone backwards (NTP, sleep) must not produce an
    /// animation that never ends.
    func testAFiringInTheFutureIsNotAnimated() {
        XCTAssertNil(VPNAutomation.spinPhase(automation(), now: fired.addingTimeInterval(-5)))
        XCTAssertFalse(VPNAutomation.showsName(automation(), now: fired.addingTimeInterval(-5)))
    }

    func testTheEndOfTheSpinIsTheEndOfTheWindow() {
        XCTAssertEqual(VPNAutomation.spinEnd(automation()), fired.addingTimeInterval(1.2))
    }
}
```

- [x] **Step 2: Run it and watch it fail**

Run: `swift test --filter VPNAutomationTests`
Expected: FAIL — `cannot find 'VPNAutomation' in scope`.

- [x] **Step 3: Write the implementation**

```swift
import Foundation

/// One firing of a VPN rule: Helm raised or dropped a tunnel by itself.
///
/// A tunnel the person started from Helm's panel, from the macOS menu bar or
/// from System Settings is deliberately not one of these. An indicator that
/// fires for everything indicates nothing.
public struct VPNAutomation: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case connected, disconnected }
    public let at: Date
    public let name: String
    public let kind: Kind

    public init(at: Date, name: String, kind: Kind) {
        self.at = at
        self.name = name
        self.kind = kind
    }

    /// How long the ring turns. Two revolutions at 0.6 s each — long enough to
    /// register as movement, short enough that it cannot be mistaken for a
    /// progress indicator.
    public static let spinDuration: TimeInterval = 1.2
    /// How long the name stays. It outlives the ring on purpose: the movement
    /// catches the eye, the word answers what caught it.
    public static let nameDuration: TimeInterval = 3.0

    /// 0…1 through the spin, or nil when there is nothing to draw.
    public static func spinPhase(_ automation: VPNAutomation, now: Date) -> Double? {
        let elapsed = now.timeIntervalSince(automation.at)
        guard elapsed >= 0, elapsed < spinDuration else { return nil }
        return elapsed / spinDuration
    }

    public static func showsName(_ automation: VPNAutomation, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(automation.at)
        return elapsed >= 0 && elapsed < nameDuration
    }

    /// The moment the ring stops — what the host is told to spin until.
    public static func spinEnd(_ automation: VPNAutomation) -> Date {
        automation.at.addingTimeInterval(spinDuration)
    }
}
```

- [x] **Step 4: Run it and watch it pass**

Run: `swift test --filter VPNAutomationTests`
Expected: PASS, 4 tests.

- [x] **Step 5: Commit**

```bash
git add Sources/Modules/VPN/Engine/Logic/VPNAutomation.swift Tests/Modules/VPN/EngineTests/VPNAutomationTests.swift
git commit -m "feat(vpn): the value for one automation firing, and its two windows"
```

---

### Task 2: The engine records a firing — and only a real one

**Files:**
- Modify: `Sources/Modules/VPN/Engine/VPNEngine.swift`
- Test: `Tests/Modules/VPN/EngineTests/VPNAutomationRecordingTests.swift`

This is the test that makes the feature mean anything. Write it first and do not weaken it.

- [x] **Step 1: Write the failing test**

Read the existing `Tests/Modules/VPN/EngineTests/` fakes before writing this — reuse the fake runner and ports already there rather than inventing a second set. The test below names them as `FakeVPNRunner` and `makeEngine`; if the existing helpers are called something else, use those names and keep the assertions.

```swift
import XCTest
import HelmContract
@testable import Module_VPN_Engine

/// The engine must be able to tell its own work from the user's. Everything
/// this feature shows rests on that distinction, so it is asserted directly
/// rather than through the UI.
final class VPNAutomationRecordingTests: XCTestCase {

    func testAnAutomaticConnectIsRecorded() throws {
        let engine = makeEngine(listing: [("work", .disconnected)])
        engine.connect("work", auto: true)
        let automation = try XCTUnwrap(engine.lastAutomation, "an automatic connect recorded nothing")
        XCTAssertEqual(automation.name, "work")
        XCTAssertEqual(automation.kind, .connected)
    }

    func testAManualConnectIsNotRecorded() {
        let engine = makeEngine(listing: [("work", .disconnected)])
        engine.connect("work")
        XCTAssertNil(engine.lastAutomation,
                     "a connection the person started was reported as an automation")
    }

    func testAManualDisconnectIsNotRecorded() {
        let engine = makeEngine(listing: [("work", .connected)])
        engine.connect("work", auto: true)
        engine.clearLastAutomationForTesting()
        engine.disconnect("work")
        XCTAssertNil(engine.lastAutomation,
                     "a disconnect the person asked for was reported as an automation")
    }

    /// The rule's app closed, so the tunnel Helm raised went away by itself.
    func testATunnelDroppingOutOfAutomationIsRecorded() throws {
        let engine = makeEngine(listing: [("work", .connected)])
        engine.connect("work", auto: true)
        engine.refreshNowForTesting()          // sees it up: remembers it came up
        engine.setListingForTesting([("work", .disconnected)])
        engine.clearLastAutomationForTesting()
        engine.refreshNowForTesting()          // sees it gone: that is the drop

        let automation = try XCTUnwrap(engine.lastAutomation, "the drop recorded nothing")
        XCTAssertEqual(automation.kind, .disconnected)
        XCTAssertEqual(automation.name, "work")
    }

    func testTheStatePayloadCarriesIt() throws {
        let engine = makeEngine(listing: [("work", .disconnected)])
        var received: Data?
        let transport = engine.transport as! LocalTransport
        let events = transport.events
        let task = Task { for await event in events where event.name == "state" { received = event.payload; break } }
        engine.connect("work", auto: true)
        for _ in 0..<200 where received == nil { await Task.yield() }
        task.cancel()

        let payload = try JSONDecoder().decode(VPNEngine.StatePayload.self,
                                               from: try XCTUnwrap(received))
        XCTAssertEqual(payload.lastAutomation?.name, "work")
    }
}
```

- [x] **Step 2: Run it and watch it fail**

Run: `swift test --filter VPNAutomationRecordingTests`
Expected: FAIL — `value of type 'VPNEngine' has no member 'lastAutomation'`.

- [x] **Step 3: Add the recording to the engine**

In `VPNEngine`, beside `_autoConnected` (around line 58), add the storage and the accessors. `_lastAutomation` goes under the same `lock` as everything else in this class — the drop path runs on the refresh thread and `connectNow` on the work queue.

```swift
    private var _lastAutomation: VPNAutomation?
    /// The last firing Helm itself caused. Read by the descriptor, so it is
    /// public; written only through `recordAutomation`.
    public var lastAutomation: VPNAutomation? {
        lock.lock(); defer { lock.unlock() }; return _lastAutomation
    }

    private func recordAutomation(_ name: String, _ kind: VPNAutomation.Kind) {
        lock.lock()
        _lastAutomation = VPNAutomation(at: clock(), name: name, kind: kind)
        lock.unlock()
    }
```

`clock` is an injectable `() -> Date` defaulting to `Date.init`, added to the initializer beside the other ports so the tests are not at the mercy of the machine's clock. If `VPNEngine` already takes a clock, use that one.

Test-only seams, `internal` so `@testable` reaches them and production cannot:

```swift
    func clearLastAutomationForTesting() {
        lock.lock(); _lastAutomation = nil; lock.unlock()
    }
```

In `connectNow(_:auto:)`, immediately after the existing `if auto { lock.lock(); _autoConnected.insert(name); lock.unlock() }`:

```swift
        if auto { recordAutomation(name, .connected) }
```

In the refresh path, where `dropped` is computed (around line 164) — inside the existing lock, after `_cameUp.subtract(dropped)`, capture the names, and record **after** `lock.unlock()` so the recursive lock is not taken twice:

```swift
        let droppedNames = dropped.sorted()
        lock.unlock()
        for name in droppedNames { recordAutomation(name, .disconnected) }
        emitState()
```

- [x] **Step 4: Carry it in the payload**

In `StatePayload` add the field, and in `emitState()` pass it:

```swift
    public struct StatePayload: Codable {
        public let connections: [VPNConnection]
        public let autoConnected: [String]
        public let defaultName: String?
        /// nil until a rule has fired in this session.
        public let lastAutomation: VPNAutomation?
    }
```

```swift
        let payload = StatePayload(connections: connections,
                                    autoConnected: autoConnected.sorted(),
                                    defaultName: defaultConnection?.name,
                                    lastAutomation: lastAutomation)
```

Decoding an older payload without the field would fail, so `lastAutomation` must be decoded with `decodeIfPresent`. `StatePayload` is encoded and decoded in the same process within one run, so this cannot actually bite — but `ActionRecord` in Autopilot carries the same note for the same reason, and the cost of matching it is one line. Write the explicit `init(from:)` if the synthesised one does not already tolerate a missing key.

- [x] **Step 5: Run the tests**

Run: `swift test --filter "VPNAutomation"`
Expected: PASS, 9 tests across both files.

- [x] **Step 6: Run the whole VPN module**

Run: `swift test --filter Module_VPN`
Expected: PASS, 0 failures. If `VPNAutoConnectDriftTests` fails, stop — it guards the stranded-VPN defect and this change touches the same bookkeeping.

- [x] **Step 7: Commit**

```bash
git add Sources/Modules/VPN/Engine/VPNEngine.swift Tests/Modules/VPN/EngineTests/VPNAutomationRecordingTests.swift
git commit -m "feat(vpn): record the firings Helm caused, and only those"
```

---

### Task 3: The three notice modes

**Files:**
- Create: `Sources/Modules/VPN/Engine/Logic/VPNNotice.swift`
- Modify: `Sources/Modules/VPN/Engine/VPNSettings.swift`
- Test: `Tests/Modules/VPN/EngineTests/VPNNoticeTests.swift`

- [x] **Step 1: Write the failing test**

```swift
import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

final class VPNNoticeTests: XCTestCase {
    private func settings() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn-test-\(UUID().uuidString)",
                                            backing: InMemoryKeyValueStore()))
    }

    /// A module that acts on its own should say what it did, and the label is
    /// the only mode that needs no new permission.
    func testTheDefaultIsTheMenuBarLabel() {
        XCTAssertEqual(settings().notice, .menuBar)
    }

    func testTheChoiceRoundTrips() {
        let s = settings()
        s.setNotice(.system)
        XCTAssertEqual(s.notice, .system)
        s.setNotice(.silent)
        XCTAssertEqual(s.notice, .silent)
    }

    func testAnUnknownStoredValueFallsBackToTheDefault() {
        let store = NamespacedStore(namespace: "vpn-test-\(UUID().uuidString)",
                                    backing: InMemoryKeyValueStore())
        store.set("shout", for: "automationNotice")
        XCTAssertEqual(VPNSettings(store: store).notice, .menuBar)
    }

    /// The name is shown beside the icon in exactly one mode.
    func testOnlyTheMenuBarModeNamesTheConnectionInTheMenuBar() {
        XCTAssertTrue(VPNNotice.menuBar.showsMenuBarName)
        XCTAssertFalse(VPNNotice.silent.showsMenuBarName)
        XCTAssertFalse(VPNNotice.system.showsMenuBarName)
    }

    /// Authorization refused: the loud mode becomes the quiet one, never
    /// silence. The person asked to be told.
    func testADeniedBannerFallsBackToTheLabelAndNotToSilence() {
        XCTAssertTrue(VPNNotice.system.effective(bannerAuthorized: false).showsMenuBarName)
        XCTAssertEqual(VPNNotice.system.effective(bannerAuthorized: false), .menuBar)
        XCTAssertEqual(VPNNotice.system.effective(bannerAuthorized: true), .system)
        XCTAssertEqual(VPNNotice.silent.effective(bannerAuthorized: false), .silent)
    }
}
```

- [x] **Step 2: Run it and watch it fail**

Run: `swift test --filter VPNNoticeTests`
Expected: FAIL — `cannot find 'VPNNotice' in scope`.

- [x] **Step 3: Write the mode**

```swift
import Foundation

/// How loudly the module says that a rule fired.
///
/// The ring spins in all three: that is feedback that the app did something,
/// not a notification, and switching it off would leave the quietest mode with
/// no way to tell an automation from a tunnel that simply changed.
public enum VPNNotice: String, CaseIterable, Codable, Sendable {
    case silent, menuBar, system

    public var showsMenuBarName: Bool { self == .menuBar }
    public var postsBanner: Bool { self == .system }

    /// What actually happens, given whether macOS let us post banners.
    ///
    /// A refused banner becomes the label, never silence: the person chose to
    /// be told loudly, and the one outcome the app must not produce is quietly
    /// not telling them. The settings row says the same thing in words.
    public func effective(bannerAuthorized: Bool) -> VPNNotice {
        self == .system && !bannerAuthorized ? .menuBar : self
    }
}
```

- [x] **Step 4: Store it**

In `VPNSettings`, beside `rulesJSON`:

```swift
    public var notice: VPNNotice {
        VPNNotice(rawValue: store.string("automationNotice", default: "")) ?? .menuBar
    }
    public func setNotice(_ notice: VPNNotice) {
        store.set(notice.rawValue, for: "automationNotice")
    }
```

- [x] **Step 5: Run the tests**

Run: `swift test --filter VPNNoticeTests`
Expected: PASS, 5 tests.

- [x] **Step 6: Commit**

```bash
git add Sources/Modules/VPN/Engine/Logic/VPNNotice.swift Sources/Modules/VPN/Engine/VPNSettings.swift Tests/Modules/VPN/EngineTests/VPNNoticeTests.swift
git commit -m "feat(vpn): three notice modes, and a refused banner that says so"
```

---

### Task 4: The status item learns what "spinning" means

**Files:**
- Modify: `Sources/HelmContract/StatusAppearance.swift`
- Create: `Sources/HelmApp/StatusPlan.swift`
- Test: `Tests/HelmAppTests/StatusPlanTests.swift` — **check whether a `HelmAppTests` target exists in `Package.swift` first.** If it does not, put `StatusPlan.swift` in `Sources/HelmRuntime/` and its test in `Tests/HelmRuntimeTests/` instead: the rule is pure and has no AppKit in it, and inventing a test target for one file is not worth a manifest edit (CLAUDE.md's warning about a target whose directory holds no tracked file applies).

- [x] **Step 1: Write the failing test**

```swift
import XCTest
import HelmContract
@testable import HelmRuntime     // or HelmApp, per the note above

final class StatusPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private func spinning(_ seconds: TimeInterval) -> StatusAppearance {
        StatusAppearance(tintToken: "green", spinUntil: now.addingTimeInterval(seconds))
    }

    func testAModuleThatIsSpinningTakesTheIcon() {
        let quiet = StatusAppearance(tintToken: "orange")
        let chosen = StatusPlan.choose([quiet, spinning(0.5)], now: now)
        XCTAssertEqual(chosen.spinUntil, spinning(0.5).spinUntil,
                       "a spin was invisible because another module sorted first")
    }

    func testWithoutASpinTheFirstTintedModuleStillWins() {
        let first = StatusAppearance(tintToken: "orange")
        let second = StatusAppearance(tintToken: "green")
        XCTAssertEqual(StatusPlan.choose([first, second], now: now).tintToken, "orange")
    }

    func testAnExpiredSpinIsNotASpin() {
        let stale = StatusAppearance(tintToken: "green", spinUntil: now.addingTimeInterval(-1))
        let active = StatusAppearance(tintToken: "orange")
        XCTAssertEqual(StatusPlan.choose([active, stale], now: now).tintToken, "orange")
    }

    func testNothingActiveIsInactive() {
        XCTAssertEqual(StatusPlan.choose([StatusAppearance()], now: now), .inactive)
    }

    /// A countdown is continuous state; a spin is a moment. The moment must not
    /// interrupt the state — a countdown arc that jumped backwards for a second
    /// reads as a bug.
    func testACountdownSuppressesTheSpin() {
        let counting = StatusAppearance(tintToken: "green", timerProgress: 0.5,
                                        spinUntil: now.addingTimeInterval(1))
        XCTAssertFalse(StatusPlan.spins(counting, now: now, reduceMotion: false))
    }

    /// Reduce Motion removes the movement and keeps the information.
    func testReduceMotionSuppressesTheSpin() {
        XCTAssertFalse(StatusPlan.spins(spinning(1), now: now, reduceMotion: true))
        XCTAssertTrue(StatusPlan.spins(spinning(1), now: now, reduceMotion: false))
    }
}
```

- [x] **Step 2: Run it and watch it fail**

Run: `swift test --filter StatusPlanTests`
Expected: FAIL — `cannot find 'StatusPlan' in scope`.

- [x] **Step 3: Add the field**

In `StatusAppearance`, after `title`:

```swift
    /// Spin the ring until this moment. nil = still.
    ///
    /// Level-triggered, like everything else here: the host reads this struct
    /// when it redraws and receives no events, so "a thing just happened" would
    /// be missed or replayed depending on timing. "Spin until T" answers
    /// correctly however often it is asked.
    public var spinUntil: Date?
```

Add it to the memberwise initializer with a `nil` default, **after** the existing parameters, so the eight other descriptors keep compiling untouched.

- [x] **Step 4: Write the rule**

```swift
import Foundation
import HelmContract

/// Which module's appearance the menu bar draws, and whether it moves.
///
/// Pulled out of `StatusItemController` so it can be asked questions without a
/// status bar, a run loop or a real module.
public enum StatusPlan {
    /// A module whose spin is still running takes the icon; otherwise the first
    /// module that tints it, which is the rule that was always here. A spin
    /// lasts about a second and ends by itself, so the borrow is brief.
    public static func choose(_ appearances: [StatusAppearance], now: Date) -> StatusAppearance {
        if let spinning = appearances.first(where: { ($0.spinUntil ?? .distantPast) > now }) {
            return spinning
        }
        return appearances.first { $0.tintToken != nil } ?? .inactive
    }

    /// Whether the chosen appearance should actually move right now.
    public static func spins(_ appearance: StatusAppearance,
                             now: Date, reduceMotion: Bool) -> Bool {
        guard !reduceMotion else { return false }
        // A countdown owns this ring while it runs.
        guard appearance.timerProgress == nil else { return false }
        return (appearance.spinUntil ?? .distantPast) > now
    }
}
```

- [x] **Step 5: Run the tests**

Run: `swift test --filter StatusPlanTests`
Expected: PASS, 6 tests.

- [x] **Step 6: Run the whole suite** — the contract changed.

Run: `swift test`
Expected: **1462 + 20 tests, 0 failures.**

- [x] **Step 7: Commit**

```bash
git add Sources/HelmContract/StatusAppearance.swift Sources/HelmRuntime/StatusPlan.swift Tests/HelmRuntimeTests/StatusPlanTests.swift
git commit -m "feat: a status appearance can ask to spin, and one rule decides who draws"
```

---

### Task 5: Drawing the spinner

**Files:**
- Modify: `Sources/HelmUI/DesignSystem/RingIcon.swift`
- Test: `Tests/HelmUITests/RingSpinnerTests.swift`

- [x] **Step 1: Write the failing test**

```swift
import XCTest
import AppKit
@testable import HelmUI

/// The spinner is a fixed segment at a rotating angle. These assert the two
/// things a cache depends on: the same phase draws the same image, and
/// different phases do not.
final class RingSpinnerTests: XCTestCase {
    private func png(_ phase: Double) throws -> Data {
        let image = RingIcon.makeSpinner(style: .ring, size: .medium,
                                          tintToken: "green", phase: phase)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    func testThePhaseChangesThePicture() throws {
        XCTAssertNotEqual(try png(0), try png(0.25), "the segment did not move")
        XCTAssertNotEqual(try png(0.25), try png(0.5))
    }

    func testTheSamePhaseDrawsTheSamePicture() throws {
        XCTAssertEqual(try png(0.4), try png(0.4),
                       "the drawing is not deterministic, so it cannot be cached")
    }

    /// Two revolutions across the window means phase 0.5 is one full turn: the
    /// segment is back where it started.
    func testHalfWayIsAWholeRevolution() throws {
        XCTAssertEqual(try png(0), try png(0.5))
    }

    func testTheIconKeepsItsFootprint() {
        let still = RingIcon.make(style: .ring, size: .medium, tintToken: "green")
        let spinning = RingIcon.makeSpinner(style: .ring, size: .medium,
                                             tintToken: "green", phase: 0.3)
        XCTAssertEqual(still.size, spinning.size, "the menu bar would jump")
    }

    /// Thirty-six images, not one per frame at 30 Hz in the menu bar.
    func testFramesAreBuiltOnceAndReused() {
        let first = RingIcon.spinnerFrames(style: .ring, size: .medium, tintToken: "green")
        let second = RingIcon.spinnerFrames(style: .ring, size: .medium, tintToken: "green")
        XCTAssertEqual(first.count, 36)
        XCTAssertTrue(first[10] === second[10], "the frame cache is not returning the same objects")
    }
}
```

- [x] **Step 2: Run it and watch it fail**

Run: `swift test --filter RingSpinnerTests`
Expected: FAIL — `type 'RingIcon' has no member 'makeSpinner'`.

- [x] **Step 3: Write the drawing**

Add to `RingIcon`, modelled on `makeArc` directly above it:

```swift
    /// The ring as a moving segment: a quarter of the circle whose start angle
    /// turns twice across `phase` 0…1. Drawn over the same faint track the
    /// countdown uses, so the icon keeps its footprint and the menu bar does
    /// not jump when the movement starts.
    public static func makeSpinner(style: MenuBarIconStyle, size: MenuBarIconSize,
                                   tintToken: String?, phase: Double) -> NSImage {
        let s = size.points
        let lineWidth = max(1.5, s * 0.12)
        let radius = (s - lineWidth) / 2
        let center = CGPoint(x: s / 2, y: s / 2)
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        let color = nsColor(tintToken: tintToken)

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        color.withAlphaComponent(0.25).setStroke()
        track.stroke()

        // Two revolutions across the whole window. AppKit angles run
        // counter-clockwise from 3 o'clock, so a clockwise sweep starts high
        // and ends lower, the same way `makeArc` does it.
        let start = 90 - 720 * phase
        let segment = NSBezierPath()
        segment.appendArc(withCenter: center, radius: radius,
                          startAngle: start, endAngle: start - 90, clockwise: true)
        segment.lineWidth = lineWidth
        segment.lineCapStyle = .round
        color.setStroke()
        segment.stroke()

        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    /// The frames of one full animation, built once per look and kept.
    ///
    /// Thirty-six frames is 30 per second across the 1.2 s window. Building an
    /// `NSImage` per frame in the menu bar would be thirty allocations a second
    /// for as long as the movement lasts; this is thirty-six, once.
    public static func spinnerFrames(style: MenuBarIconStyle, size: MenuBarIconSize,
                                     tintToken: String?) -> [NSImage] {
        let key = "\(style.rawValue)|\(size.rawValue)|\(tintToken ?? "")"
        if let cached = spinnerCache.frames(key) { return cached }
        let frames = (0..<36).map {
            makeSpinner(style: style, size: size, tintToken: tintToken,
                        phase: Double($0) / 36)
        }
        spinnerCache.store(key, frames)
        return frames
    }

    private static let spinnerCache = SpinnerCache()

    private final class SpinnerCache: @unchecked Sendable {
        private let lock = NSLock()
        private var byKey: [String: [NSImage]] = [:]
        func frames(_ key: String) -> [NSImage]? {
            lock.lock(); defer { lock.unlock() }; return byKey[key]
        }
        func store(_ key: String, _ frames: [NSImage]) {
            lock.lock(); byKey[key] = frames; lock.unlock()
        }
    }
```

`isTemplate` matches whatever `makeArc` sets — read it and copy, do not guess: a template image is tinted by AppKit and would throw the module's colour away.

- [x] **Step 4: Run the tests**

Run: `swift test --filter RingSpinnerTests`
Expected: PASS, 5 tests. If `testHalfWayIsAWholeRevolution` fails, the sweep is not 720°.

- [x] **Step 5: Commit**

```bash
git add Sources/HelmUI/DesignSystem/RingIcon.swift Tests/HelmUITests/RingSpinnerTests.swift
git commit -m "feat(ui): a menu-bar ring that turns, with its frames built once"
```

---

### Task 6: The host runs the frames

**Files:**
- Modify: `Sources/HelmApp/StatusItemController.swift`

Read `ARCHITECTURE.md` § Status item and § "An observer outlives the thing it points at" before this task.

- [x] **Step 1: Replace the module choice with the rule**

In `refreshIcon()`, the current three lines

```swift
        let appearance = host.enabledModules
            .map { $0.descriptor.statusAppearance($0.vm) }
            .first { $0.tintToken != nil } ?? .inactive
```

become

```swift
        let now = Date()
        let appearances = host.enabledModules.map { $0.descriptor.statusAppearance($0.vm) }
        let appearance = StatusPlan.choose(appearances, now: now)
        // Read fresh, the way HelmMotion reads it: the setting can change while
        // the app is running and a cached answer would keep moving.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let spinning = StatusPlan.spins(appearance, now: now, reduceMotion: reduceMotion)
```

- [x] **Step 2: Drive the frames**

Add beside `timerTick`:

```swift
    /// Drives the spin. Separate from the countdown's 1 Hz tick because it runs
    /// at 30 Hz for about a second and must stop the moment it is done — a
    /// timer left armed here would redraw the menu bar forever.
    private var spinTick: Timer?

    private func scheduleSpinTick(active: Bool) {
        if active, spinTick == nil {
            spinTick = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshIcon() }
            }
        } else if !active, spinTick != nil {
            spinTick?.invalidate()
            spinTick = nil
        }
    }
```

Call `scheduleSpinTick(active: spinning)` beside the existing `scheduleTimerTick(active: progress != nil)`.

- [x] **Step 3: Pick the image, and let the key see the frame**

The redraw key exists to suppress redundant work and will suppress the animation itself unless the frame is part of it. Replace the key and the image line:

```swift
        let frameIndex: Int? = spinning ? spinFrameIndex(appearance, now: now) : nil
        let key = "\(style.rawValue)|\(size.rawValue)|\(token ?? "")|\(bucket.map(String.init) ?? "-")|\(title ?? "")|\(frameIndex.map(String.init) ?? "-")"
        guard key != lastIconKey else { return }
        lastIconKey = key
        if let frameIndex {
            button.image = RingIcon.spinnerFrames(style: style, size: size, tintToken: token)[frameIndex]
        } else {
            button.image = RingIcon.make(style: style, size: size, tintToken: token, progress: progress)
        }
```

and add the helper:

```swift
    /// Which of the 36 frames belongs to this instant.
    private func spinFrameIndex(_ appearance: StatusAppearance, now: Date) -> Int? {
        guard let until = appearance.spinUntil else { return nil }
        let remaining = until.timeIntervalSince(now)
        guard remaining > 0, remaining <= VPNAutomationWindow.spinDuration else { return nil }
        let phase = 1 - remaining / VPNAutomationWindow.spinDuration
        return min(35, max(0, Int(phase * 36)))
    }
```

`HelmApp` must not import a module's engine to learn a duration. Put the constant where the host can see it — add to `StatusPlan`:

```swift
    /// How long a spin lasts. The module that asks for one uses the same value
    /// to compute `spinUntil`; the host needs it to know which frame is now.
    public static let spinDuration: TimeInterval = 1.2
```

and use `StatusPlan.spinDuration` in the helper. Then change `VPNAutomation.spinDuration` (Task 1) to read `StatusPlan.spinDuration` so there is one number rather than two that can drift. If `Module_VPN_Engine` cannot import the target `StatusPlan` lives in, put the constant in `HelmContract` beside `StatusAppearance` instead and have both read it from there.

- [x] **Step 4: Build and run the whole suite**

Run: `swift build && swift test`
Expected: 0 failures.

- [x] **Step 5: Prove the timer stops**

Add to `Tests/HelmRuntimeTests/StatusPlanTests.swift`:

```swift
    /// The spin is over the moment its window closes — nothing keeps asking.
    func testASpinThatHasEndedIsNotSpinning() {
        let ended = StatusAppearance(tintToken: "green",
                                     spinUntil: now.addingTimeInterval(-0.01))
        XCTAssertFalse(StatusPlan.spins(ended, now: now, reduceMotion: false))
        XCTAssertEqual(StatusPlan.choose([ended], now: now).tintToken, "green",
                       "an ended spin should still be an ordinary tinted module")
    }
```

Run: `swift test --filter StatusPlanTests`
Expected: PASS, 7 tests.

- [x] **Step 6: Commit**

```bash
git add Sources/HelmApp/StatusItemController.swift Sources/HelmRuntime/StatusPlan.swift Tests/HelmRuntimeTests/StatusPlanTests.swift
git commit -m "feat(app): run the spin frames, and stop the moment the window closes"
```

---

### Task 7: The descriptor asks for the spin

**Files:**
- Modify: `Sources/Modules/VPN/UI/VPNViewModel.swift`
- Modify: `Sources/Modules/VPN/UI/VPNDescriptor.swift`
- Test: `Tests/Modules/VPN/UITests/VPNStatusAppearanceTests.swift` — **`Module_VPN_UITests` does not exist yet.** Add it to `Package.swift` following the `Module_Layout_UITests` shape, and `git add` the test file in the same commit: a declared target over untracked files breaks the manifest for every checkout but this one (CLAUDE.md).

- [x] **Step 1: Write the failing test**

```swift
import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_VPN_Engine
@testable import Module_VPN_UI

@MainActor
final class VPNStatusAppearanceTests: XCTestCase {
    private func descriptor() -> VPNDescriptor { VPNDescriptor() }

    func testAFreshFiringAsksForASpinAndNamesTheConnection() {
        let d = descriptor()
        let vm = ModuleViewModel(transport: LocalTransport())
        let model = d.viewModel(vm)
        model.applyAutomationForTesting(VPNAutomation(at: Date(), name: "work", kind: .connected),
                                        notice: .menuBar)

        let appearance = d.statusAppearance(vm)
        XCTAssertNotNil(appearance.spinUntil, "no spin was asked for")
        XCTAssertEqual(appearance.title, "work")
    }

    func testTheSilentModeStillSpinsButNamesNothing() {
        let d = descriptor()
        let vm = ModuleViewModel(transport: LocalTransport())
        let model = d.viewModel(vm)
        model.applyAutomationForTesting(VPNAutomation(at: Date(), name: "work", kind: .connected),
                                        notice: .silent)

        let appearance = d.statusAppearance(vm)
        XCTAssertNotNil(appearance.spinUntil, "the animation is feedback and belongs to every mode")
        XCTAssertNil(appearance.title, "the silent mode named the connection")
    }

    func testAnOldFiringAsksForNothing() {
        let d = descriptor()
        let vm = ModuleViewModel(transport: LocalTransport())
        let model = d.viewModel(vm)
        model.applyAutomationForTesting(
            VPNAutomation(at: Date().addingTimeInterval(-60), name: "work", kind: .connected),
            notice: .menuBar)

        let appearance = d.statusAppearance(vm)
        XCTAssertNil(appearance.spinUntil)
        XCTAssertNil(appearance.title)
    }
}
```

- [x] **Step 2: Run it and watch it fail**

Run: `swift test --filter VPNStatusAppearanceTests`
Expected: FAIL — the target does not exist, then `has no member 'applyAutomationForTesting'`.

- [x] **Step 3: Hold the firing in the view model**

In `VPNViewModel`, add the published state and the seam, and decode the new payload field in `handle(_:)` beside the existing `connections` / `autoConnected` handling:

```swift
    @Published public private(set) var lastAutomation: VPNAutomation?
    /// Read from the module's own store, not from the host: this is the
    /// module's setting.
    @Published public private(set) var notice: VPNNotice = .menuBar

    func applyAutomationForTesting(_ automation: VPNAutomation, notice: VPNNotice) {
        lastAutomation = automation
        self.notice = notice
    }
```

In `handle(_:)`, after the existing assignments from `StatePayload`:

```swift
        // A firing older than its window is not news; dropping it here keeps
        // the descriptor from having to know about time twice.
        if let automation = payload.lastAutomation,
           VPNAutomation.showsName(automation, now: Date()) {
            lastAutomation = automation
        }
```

- [x] **Step 4: Report it from the descriptor**

`VPNDescriptor` currently has no `statusAppearance`. Add both it and `statusChanges` — without the second, the host never learns a firing happened until something else redraws the icon:

```swift
    public func statusAppearance(_ vm: ModuleViewModel) -> StatusAppearance {
        let model = viewModel(vm)
        let now = Date()
        // The tint is the module's existing answer: a tunnel is up or it is not.
        let tint = model.connections.contains(where: \.status.isUp) ? "green" : nil
        guard let automation = model.lastAutomation else {
            return StatusAppearance(tintToken: tint)
        }
        let spinUntil = VPNAutomation.spinPhase(automation, now: now) == nil
            ? nil : VPNAutomation.spinEnd(automation)
        let title = model.notice.showsMenuBarName
            && VPNAutomation.showsName(automation, now: now) ? automation.name : nil
        return StatusAppearance(tintToken: tint, title: title, spinUntil: spinUntil)
    }

    public func statusChanges(_ vm: ModuleViewModel) -> AnyPublisher<Void, Never>? {
        viewModel(vm).objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }
```

**Check the existing tint token against `RingIcon.nsColor(tintToken:)` before writing `"green"`** — use whatever token the palette actually defines, and if the module already tints the icon elsewhere, use that same expression rather than a second opinion.

`import Combine` is needed for `AnyPublisher`.

- [x] **Step 5: Run the tests**

Run: `swift test --filter VPNStatusAppearanceTests`
Expected: PASS, 3 tests.

- [x] **Step 6: Run everything**

Run: `swift test`
Expected: 0 failures.

- [x] **Step 7: Commit**

```bash
git add Package.swift Sources/Modules/VPN/UI/VPNViewModel.swift Sources/Modules/VPN/UI/VPNDescriptor.swift Tests/Modules/VPN/UITests/
git commit -m "feat(vpn): the module asks the menu bar to spin, and names the connection"
```

---

### Task 8: The macOS banner, behind a port

**Files:**
- Modify: `Sources/Modules/VPN/Engine/Ports.swift`
- Modify: `Sources/Modules/VPN/Engine/SystemPorts.swift`
- Test: `Tests/Modules/VPN/EngineTests/AutomationNoticeTests.swift`

- [x] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Module_VPN_Engine

private final class FakeNotice: AutomationNoticePort, @unchecked Sendable {
    var state: NoticeAuthorization = .notDetermined
    var requested = 0
    var posted: [(String, String)] = []
    func authorizationState() async -> NoticeAuthorization { state }
    func requestAuthorization() async -> NoticeAuthorization { requested += 1; return state }
    func post(title: String, body: String) async { posted.append((title, body)) }
}

final class AutomationNoticeTests: XCTestCase {

    /// Asking for a notification permission before anyone wants notifications
    /// is how people learn to deny them.
    func testAuthorizationIsAskedForOnlyWhenTheBannerIsChosen() async {
        let port = FakeNotice()
        _ = await AutomationNotice.prepare(for: .menuBar, port: port)
        XCTAssertEqual(port.requested, 0)
        _ = await AutomationNotice.prepare(for: .system, port: port)
        XCTAssertEqual(port.requested, 1)
    }

    func testADeniedBannerReportsItselfAsDenied() async {
        let port = FakeNotice()
        port.state = .denied
        let outcome = await AutomationNotice.prepare(for: .system, port: port)
        XCTAssertEqual(outcome, .denied)
    }

    func testTheBannerIsPostedOnlyInTheBannerMode() async {
        let port = FakeNotice()
        port.state = .authorized
        await AutomationNotice.announce(VPNAutomation(at: Date(), name: "work", kind: .connected),
                                        notice: .system, authorized: true, port: port)
        XCTAssertEqual(port.posted.count, 1)
        XCTAssertTrue(port.posted[0].1.contains("work"), "the banner did not name the connection")

        await AutomationNotice.announce(VPNAutomation(at: Date(), name: "work", kind: .connected),
                                        notice: .menuBar, authorized: true, port: port)
        await AutomationNotice.announce(VPNAutomation(at: Date(), name: "work", kind: .connected),
                                        notice: .silent, authorized: true, port: port)
        XCTAssertEqual(port.posted.count, 1, "a quiet mode posted a banner")
    }

    func testNothingIsPostedWhenAuthorizationWasRefused() async {
        let port = FakeNotice()
        await AutomationNotice.announce(VPNAutomation(at: Date(), name: "work", kind: .connected),
                                        notice: .system, authorized: false, port: port)
        XCTAssertTrue(port.posted.isEmpty)
    }
}
```

- [x] **Step 2: Run it and watch it fail**

Run: `swift test --filter AutomationNoticeTests`
Expected: FAIL — `cannot find type 'AutomationNoticePort' in scope`.

- [x] **Step 3: Write the port and the decision**

In `Ports.swift`:

```swift
public enum NoticeAuthorization: String, Sendable {
    case notDetermined, authorized, denied
}

/// Posting a banner, behind a protocol so the decision above it is testable
/// without asking macOS for permission in a test run.
public protocol AutomationNoticePort: Sendable {
    func authorizationState() async -> NoticeAuthorization
    func requestAuthorization() async -> NoticeAuthorization
    func post(title: String, body: String) async
}

public enum AutomationNotice {
    /// Asked when the user picks the banner mode, and only then.
    public static func prepare(for notice: VPNNotice,
                               port: AutomationNoticePort) async -> NoticeAuthorization {
        guard notice.postsBanner else { return await port.authorizationState() }
        return await port.requestAuthorization()
    }

    public static func announce(_ automation: VPNAutomation, notice: VPNNotice,
                                authorized: Bool, port: AutomationNoticePort) async {
        guard notice.effective(bannerAuthorized: authorized).postsBanner else { return }
        await port.post(title: VPNBannerText.title(automation.kind),
                        body: VPNBannerText.body(automation))
    }
}
```

`VPNBannerText` lives in the UI layer with the other strings (Task 9); until then, use a plain string so the test compiles, and replace it in Task 9. The engine target must not import `Module_VPN_UI` — if that ordering is awkward, move `announce` into the view model and keep only the port here, and say so in the commit message.

- [x] **Step 4: Write the system implementation**

In `SystemPorts.swift`:

```swift
import UserNotifications

/// The real banner.
///
/// These builds are ad-hoc signed, and ARCHITECTURE.md § Permissions records
/// that macOS ties such a grant to the exact binary — every rebuild invalidates
/// it while the checkbox stays ticked. Whether that applies to notification
/// authorization is measured on a real build in Task 10, not assumed here.
public struct SystemAutomationNotice: AutomationNoticePort {
    public init() {}

    public func authorizationState() async -> NoticeAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    public func requestAuthorization() async -> NoticeAuthorization {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert])) ?? false
        return granted ? .authorized : .denied
    }

    public func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
```

- [x] **Step 5: Run the tests**

Run: `swift test --filter AutomationNoticeTests`
Expected: PASS, 4 tests.

- [x] **Step 6: Commit**

```bash
git add Sources/Modules/VPN/Engine/Ports.swift Sources/Modules/VPN/Engine/SystemPorts.swift Tests/Modules/VPN/EngineTests/AutomationNoticeTests.swift
git commit -m "feat(vpn): the banner behind a port, and the decision above it in tests"
```

---

### Task 9: The setting on screen

**Files:**
- Modify: `Sources/Modules/VPN/UI/VPNSettingsPage.swift`
- Modify: `Sources/Modules/VPN/UI/VPNStrings.swift`

Every string here needs all eight languages (en, ru, es, fr, de, ja, zh, pt). Where a string names something macOS also names — "Notifications", the System Settings pane — read the system's own spelling out of its `.loctable` rather than translating afresh; `ARCHITECTURE.md` § Localization says where the tables are.

- [x] **Step 1: Add the strings**

In `VPNStrings.swift`. The English is given; look the other seven up rather than inventing them.

```swift
    static var automationNotice: String { L("When a rule fires", [...]) }
    static var noticeSilent: String { L("No notice", [...]) }
    static var noticeMenuBar: String { L("Name it in the menu bar", [...]) }
    static var noticeSystem: String { L("macOS notification", [...]) }
    /// Said in the row, not in a log line nobody reads: the person chose the
    /// loud option and is owed the news that macOS refused it.
    static var noticeDenied: String { L("macOS is not allowing notifications from Helm. The name is shown in the menu bar instead.", [...]) }
    static var openNotificationSettings: String { L("Open Notifications…", [...]) }
    static func bannerConnected(_ name: String) -> String { L("Connected \(name)", [...]) }
    static func bannerDisconnected(_ name: String) -> String { L("Disconnected \(name)", [...]) }
```

- [x] **Step 2: Add the section**

In `vpnForm`, after the `Section(VPNStr.perAppAutomation)` block:

```swift
            Section(VPNStr.automationNotice) {
                Picker(VPNStr.automationNotice, selection: noticeBinding) {
                    Text(VPNStr.noticeSilent).tag(VPNNotice.silent)
                    Text(VPNStr.noticeMenuBar).tag(VPNNotice.menuBar)
                    Text(VPNStr.noticeSystem).tag(VPNNotice.system)
                }
                if notice == .system, authorization == .denied {
                    HelmPermissionNote(message: VPNStr.noticeDenied,
                                       action: VPNStr.openNotificationSettings) {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
            }
```

Read `HelmPermissionNote`'s real initializer before writing this — match it exactly rather than the shape sketched here, and use `HelmPickerWidth` if the picker needs a measured width, the way the Autopilot pickers do.

The binding writes through the store and, on selecting `.system`, asks for authorization:

```swift
    private var noticeBinding: Binding<VPNNotice> {
        Binding(get: { notice },
                set: { chosen in
                    settings.setNotice(chosen)
                    notice = chosen
                    Task { authorization = await AutomationNotice.prepare(for: chosen, port: noticePort) }
                })
    }
```

- [x] **Step 3: Build and check the eight languages**

Run: `swift build && swift test`
Expected: 0 failures. If a localization guard test exists for missing tables, it will name any language you skipped — do not silence it.

- [x] **Step 4: Commit**

```bash
git add Sources/Modules/VPN/UI/VPNSettingsPage.swift Sources/Modules/VPN/UI/VPNStrings.swift
git commit -m "feat(vpn): choose how loudly a rule announces itself"
```

---

### Task 10: Verify it in the running app, then measure it

Nothing above proves the feature works. Tests prove the decisions; this proves the app.

**How it was actually run, and why.** Step 2 below says to launch and quit the
app a rule covers. On this machine that rule's app was running a full-screen
remote-desktop session over the very tunnel the rule manages, and both of the
Mac's configured VPNs were up — so every firing available through the rules path
would have taken down a connection somebody was working over, and the rebuild had
already invalidated the keychain ACL Helm reads the L2TP shared secret through,
which made a reconnect something only the user's password could do. The firings
were therefore driven through the engine's own `connect(name, auto: true)` from a
temporary `HELM_DEBUG_VPN_FIRING` harness in `AppDelegate`, naming a connection
that is not configured: that path records the automation, emits the state
payload, and drives the view model, the descriptor, `StatusPlan`, the frame cache
and the notice port exactly as a rule does, while `scutil --nc start` fails
harmlessly and the credential lookup returns before it touches the keychain. What
it does **not** exercise is `VPNAutoConnectCore` deciding to call `connect` —
covered by its unit tests, and observed in the log at every launch of the real
build (`connect vpn#73af (auto)`). The harness is gone; `grep -r HELM_DEBUG
Sources/` is clean and `git status` shows no trace of it.

- [x] **Step 1: Build, sign and install**

```bash
pkill -f 'MacOS/HelmApp'; bash Scripts/package-app.sh
rm -rf /Applications/Helm.app
ditto "$TMPDIR/helm-package/Helm.app" /Applications/Helm.app
codesign --verify --deep --strict /Applications/Helm.app
xattr -dr com.apple.quarantine /Applications/Helm.app && open /Applications/Helm.app
```

- [x] **Step 2: Watch a real firing**

Set a per-app rule for an application you can launch and quit. Launch it, and watch the menu bar: the ring should turn twice, and the connection's name should appear beside it and fade after three seconds. Then check the log names the firing without naming the connection:

```bash
grep -E "vpn|automation" ~/Library/Logs/Helm/helm.log | tail -20
```

Expected: the line carries `vpn#<tag>`, **not** the connection's name. If the name is in the log, stop and fix it — `Redact.vpn` exists for this.

- [x] **Step 3: Answer the question the design could not**

Switch the notice to **macOS notification**. Record what happens:

- Does the authorization prompt appear at all for an ad-hoc-signed build?
- If granted, does a banner actually arrive on the next firing?
- Quit, rebuild, reinstall, and check whether the grant survived — this is the behaviour ARCHITECTURE.md § Permissions describes for other grants, and whether it applies here is the open question.

Write the answer into the spec's Risks section as measured fact. If banners do not work under ad-hoc signing, the mode still ships — the denied path is already designed and the row already says so — but the spec must record it rather than leaving the next person to rediscover it.

- [x] **Step 4: Measure the redraw**

The spin redraws the menu bar 30 times a second for 1.2 s. Trigger ten firings in a row and read the footprint:

```bash
grep memory ~/Library/Logs/Helm/helm.log | tail -20
```

Expected: no growth across the ten. If it grows, the frame cache is not being hit — check that the key in `spinnerFrames` matches on every call.

- [x] **Step 5: Check the two suppression rules on screen**

- Start a Keep Awake timed session so the countdown arc is drawn, then trigger a firing: the ring must **not** spin, and the name must still appear.
- Turn on System Settings → Accessibility → Display → Reduce motion, trigger a firing: no spin, name still appears.

- [x] **Step 6: Leave nothing behind**

```bash
grep -rn HELM_DEBUG Sources/    # must print nothing
ls ~/Library/Application\ Support/Helm/
```

Remove any state a test rule created, and delete the per-app rule you added.

- [x] **Step 7: Changelog and commit**

`CHANGELOG.md` gets the full entry. `Sources/HelmApp/ChangelogData.swift` gets the user-facing one in eight languages — this is a new feature a stable user has never seen, so it belongs there, badged as a feature.

```bash
git add CHANGELOG.md Sources/HelmApp/ChangelogData.swift docs/superpowers/specs/2026-07-29-vpn-automation-feedback-design.md
git commit -m "docs(vpn): what the banner does under ad-hoc signing, measured"
```

---

## Self-review

**Spec coverage.** Firing definition → Task 2. `spinUntil` → Task 4. Countdown and Reduce Motion suppression → Tasks 4 and 6, checked on screen in Task 10. Module selection → Task 4. Drawing and the frame cache → Task 5. Three modes → Task 3. Denied fallback → Tasks 3, 8, 9. Name kept out of the log → Task 10 step 2. Redraw cost → Task 10 step 4. Every "does not do" in the spec has no task, correctly.

**Names.** `VPNAutomation` (value) with `spinPhase`/`showsName`/`spinEnd`; `VPNNotice` with `showsMenuBarName`/`postsBanner`/`effective(bannerAuthorized:)`; `StatusPlan.choose`/`spins`/`spinDuration`; `RingIcon.makeSpinner`/`spinnerFrames`; `AutomationNoticePort` with `authorizationState`/`requestAuthorization`/`post`; `AutomationNotice.prepare`/`announce`. These are the names used in every task.

**One number, not two.** `spinDuration` is defined once (Task 6, Step 3) and read by both the module and the host.

**Two places the plan tells the implementer to look rather than trust it:** the tint token in Task 7 and `HelmPermissionNote`'s initializer in Task 9. Both are existing code this plan describes from memory of a grep, and guessing them would produce a compile error at best and a second opinion at worst.
