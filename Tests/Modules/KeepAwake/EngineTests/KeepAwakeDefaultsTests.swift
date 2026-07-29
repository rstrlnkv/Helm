import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The defaults a fresh install starts from. They are read here rather than
/// eyeballed in the struct because one of them decides whether an unattended
/// Mac on battery runs itself flat: `defaultDurationMinutes` is 0, which is
/// "indefinitely", so nothing else in the module ever ends that session.
final class KeepAwakeDefaultsTests: XCTestCase {
    private var backing: InMemoryKeyValueStore!
    private var settings: KeepAwakeSettings!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        settings = KeepAwakeSettings(store: NamespacedStore(namespace: "keep-awake", backing: backing))
    }

    /// The pairing is the point: an indefinite session with no guard has no
    /// stopping condition at all. Asserted together so that changing either one
    /// alone has to face this test.
    func test_an_indefinite_default_session_ships_with_the_battery_guard_on() {
        XCTAssertEqual(settings.defaultDurationMinutes, 0, "not indefinite any more — re-read this test")
        XCTAssertTrue(settings.batteryGuardEnabled)
        XCTAssertEqual(settings.batteryGuardPercent, 20)
    }

    /// A default is not a migration. Someone who switched the guard off keeps it
    /// off; flipping the default must not reach into a store that has an answer.
    func test_a_stored_choice_survives_the_default() {
        for stored in [true, false] {
            let backing = InMemoryKeyValueStore()
            backing.raw["module.keep-awake.batteryGuardEnabled"] = stored
            let settings = KeepAwakeSettings(store: NamespacedStore(namespace: "keep-awake",
                                                                    backing: backing))
            XCTAssertEqual(settings.batteryGuardEnabled, stored)
        }
    }
}
