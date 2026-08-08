import XCTest
import HelmContract
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// Turning "keep the display on" off during a session puts the display
/// assertion down.
///
/// `reconcileActiveSettings` carries the promise in prose — "so toggling
/// keepDisplayOn / clamshell / jiggle takes effect now (not only on the next
/// session)" — and nothing held it. The failure has no error and no crash: the
/// display simply never sleeps, on a Mac whose owner has just told it to.
///
/// **The fake could not have seen it either.** `FakeAssertions` was one `held`
/// flag and a record of the last `display:` argument, while
/// `IOKitSleepAssertions` holds an IOKit assertion per kind. A display
/// assertion outliving the setting that asked for it was unrepresentable in the
/// fake, so no test in this module could fail on it, and the one test that
/// touched `display` asked only whether the argument had been passed.
///
/// The port used to make that easy to get wrong: `preventSleep(display: false)`
/// created nothing and released nothing, so the call added and never subtracted
/// and only `release()` could put the display assertion down. It matches its
/// argument now. What is **not** machine-checked is that half — creating real
/// IOKit assertions inside the suite is exactly the thing this module exists to
/// avoid doing by accident.
final class TheDisplayAssertionFollowsItsSettingTests: XCTestCase {

    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!
    private var assertions: FakeAssertions!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        settings = KeepAwakeSettings(store: store)
        assertions = FakeAssertions()
        engine = KeepAwakeEngine(settings: settings, store: store, assertions: assertions,
                                 displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(),
                                 power: FakePower(), apps: FakeApps(),
                                 pointer: FakePointer(), clamshell: FakeClamshell(),
                                 clock: FakeClock())
    }

    /// What the settings page does: write the store, then send the command.
    private func setKeepDisplayOn(_ on: Bool) { store.set(on, for: "keepDisplayOn") }

    /// The command the settings page sends when anything on it moves.
    private func settingsChanged() async {
        _ = try? await engine.transport.send(
            EngineCommand(name: KeepAwakeCommand.settingsChanged.rawValue))
    }

    func testSwitchingItOffDuringASessionPutsTheDisplayAssertionDown() async {
        setKeepDisplayOn(true)
        engine.startSession(minutes: 0)
        XCTAssertTrue(assertions.displayHeld,
                      "precondition: the session took the display assertion")

        setKeepDisplayOn(false)
        await settingsChanged()

        XCTAssertFalse(assertions.displayHeld,
                       "the display assertion outlived the setting that asked for it — "
                       + "the display never sleeps, and nothing says so")
        XCTAssertTrue(assertions.held,
                      "the session itself was ended by a change to one of its settings")
    }

    /// And the other way, or the switch is one-directional: a person who turns
    /// it back on mid-session is told it takes effect now.
    func testSwitchingItOnDuringASessionTakesTheAssertion() async {
        setKeepDisplayOn(false)
        engine.startSession(minutes: 0)
        XCTAssertFalse(assertions.displayHeld, "precondition: no display assertion yet")

        setKeepDisplayOn(true)
        await settingsChanged()

        XCTAssertTrue(assertions.displayHeld, "the switch did not take effect until the next session")
    }

    /// With no session running there is nothing to reconcile, and a settings
    /// change must not quietly take an assertion nobody asked for.
    func testChangingItWithNoSessionTakesNothing() async {
        setKeepDisplayOn(true)
        await settingsChanged()

        XCTAssertFalse(assertions.held, "a settings change started keeping the Mac awake")
        XCTAssertFalse(assertions.displayHeld)
    }
}
