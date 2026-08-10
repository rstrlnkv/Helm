import XCTest
import HelmContract
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The one invariant this module exists to keep, asserted after every move
/// rather than at the end of one story.
///
/// `isActive` is what every screen draws and what the store, the menu bar and
/// the panel all read. The IOKit assertion is what the Mac actually obeys. They
/// are set in two different branches of `recompute`, taken back in a third
/// place by `reconcileActiveSettings` and a fourth by `deactivate`, and the two
/// failures they can have are not symmetrical: an assertion held past the end
/// of a session is a Mac that never sleeps while every screen says the module
/// is idle — which is the exact shape of the clamshell defect this module has
/// already had once, and the reason `IOKitSleepAssertions` carries a `deinit`
/// backstop.
///
/// A walk rather than one path: the interesting states are the orderings nobody
/// draws — a module switched off mid-session, a display arriving while a timer
/// runs, a settings change during a suppression, a relaunch on top of all of it.
@MainActor
final class TheAssertionNeverOutlivesTheSessionTests: XCTestCase {

    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!
    private var assertions: FakeAssertions!
    private var displayInfo: FakeDisplayInfo!
    private var displayObserver: FakeDisplayObserver!
    private var power: FakePower!
    private var apps: FakeApps!
    private var clock: FakeClock!
    private var engine: KeepAwakeEngine!

    private let render = "com.example.render"

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        settings = KeepAwakeSettings(store: store)
        settings.setAppTriggers([AppTrigger(bundleID: render)])
        store.set(true, for: KeepAwakeSettings.Key.autoExternalDisplay)
        assertions = FakeAssertions()
        displayInfo = FakeDisplayInfo()
        displayObserver = FakeDisplayObserver()
        power = FakePower()
        apps = FakeApps()
        clock = FakeClock()
        engine = KeepAwakeEngine(settings: settings, store: store, assertions: assertions,
                                 displayInfo: displayInfo, displayObserver: displayObserver,
                                 power: power, apps: apps, pointer: FakePointer(),
                                 clamshell: FakeClamshell(), clock: clock)
    }

    private func settingsChanged() async {
        _ = try? await engine.transport.send(
            EngineCommand(name: KeepAwakeCommand.settingsChanged.rawValue))
    }

    func testTheAssertionAndTheStateAgreeAfterEveryMove() async {
        let steps: [(String, () async -> Void)] = [
            ("the module is switched on", { self.engine.activate() }),
            ("a display arrives", { self.displayInfo.flags = [true, false]
                                    self.displayObserver.fire() }),
            ("a session by hand on top of it", { self.engine.startSession(minutes: 30) }),
            ("the display goes", { self.displayInfo.flags = [true]
                                   self.displayObserver.fire() }),
            ("the app the rule names starts", { self.apps.ids = [self.render]
                                                self.apps.fire() }),
            ("the timer runs out", { self.clock.fire(after: 30 * 60) }),
            ("stop, which silences the rule", { self.engine.stopSession() }),
            ("a settings change while it is silenced", { await self.settingsChanged() }),
            ("keep the display on", { self.store.set(true, for: KeepAwakeSettings.Key.keepDisplayOn)
                                      await self.settingsChanged() }),
            ("resume", { self.engine.resumeAutomation() }),
            ("keep the display on, off again",
             { self.store.set(false, for: KeepAwakeSettings.Key.keepDisplayOn)
               await self.settingsChanged() }),
            ("a session with no deadline", { self.engine.startSession(minutes: 0) }),
            ("the module is switched off", { self.engine.deactivate() }),
            ("and on again, on top of the stored session", { self.engine.activate() }),
            ("the app quits", { self.apps.ids = []; self.apps.fire() }),
            ("toggle", { self.engine.toggleSession() }),
            ("toggle again", { self.engine.toggleSession() }),
            ("stop", { self.engine.stopSession() }),
        ]

        var sawHeld = false
        var sawReleased = false
        for (name, step) in steps {
            await step()

            XCTAssertEqual(assertions.held, engine.isActive,
                           "after «\(name)»: the module says \(engine.isActive) and the Mac "
                           + "is being held \(assertions.held) — one of the two is what "
                           + "somebody reads and the other is what their Mac obeys")
            XCTAssertEqual(engine.activeConditions.isEmpty, !engine.isActive,
                           "after «\(name)»: \(engine.activeConditions) with isActive "
                           + "\(engine.isActive)")
            XCTAssertEqual(assertions.displayHeld,
                           engine.isActive && settings.keepDisplayOn,
                           "after «\(name)»: the display assertion does not match the setting")
            sawHeld = sawHeld || assertions.held
            sawReleased = sawReleased || (!assertions.held && !engine.isActive)
        }

        XCTAssertTrue(sawHeld, "the walk never held the Mac awake at all")
        XCTAssertTrue(sawReleased, "the walk never let it go")
        XCTAssertFalse(assertions.held, "it ends stopped, and the assertion ends with it")
    }

    /// The end of the process, which is the one exit `deactivate` is called on
    /// for every live engine: whatever was held has to be given back, or the
    /// assertion outlives the app that took it.
    func testSwitchingTheModuleOffDuringASessionGivesTheAssertionBack() {
        engine.activate()
        engine.startSession(minutes: 30)
        XCTAssertTrue(assertions.held, "precondition")

        engine.deactivate()

        XCTAssertFalse(assertions.held)
        XCTAssertFalse(engine.isActive)
        XCTAssertTrue(engine.activeConditions.isEmpty)
    }

    /// And the same with the session held by a rule rather than by hand, which
    /// takes the other branch entirely.
    func testSwitchingTheModuleOffDuringARuleGivesTheAssertionBack() {
        apps.ids = [render]
        engine.activate()
        XCTAssertTrue(assertions.held, "precondition: the rule is holding it")

        engine.deactivate()

        XCTAssertFalse(assertions.held)
    }

    /// Reconciling settings mid-session releases and re-takes the assertion.
    /// The count is the point: a release with no matching prevent leaves the
    /// Mac free to sleep in the middle of a session, and this is the one place
    /// in the module where the two are spelled as a pair by hand.
    func testASettingsChangeDoesNotLeaveTheAssertionDown() async {
        engine.startSession(minutes: 0)
        XCTAssertTrue(assertions.held, "precondition")

        for _ in 0..<3 { await settingsChanged() }

        XCTAssertTrue(assertions.held, "a settings change ended the hold on the Mac")
        XCTAssertEqual(assertions.preventCount, assertions.releaseCount + 1,
                       "every release inside a session is answered by a prevent")
    }
}
