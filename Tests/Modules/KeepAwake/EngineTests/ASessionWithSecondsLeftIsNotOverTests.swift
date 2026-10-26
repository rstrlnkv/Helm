import Foundation
import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The line the owner's log actually printed, and what it is worth reading as.
///
///     22:12:05.916 [keep-awake] restored a session: 0 min left
///     22:12:05.923 [keep-awake] holding sleep: manual+timer, display too
///
/// Read as «a finished session was restored and took the assertion anyway»,
/// which is what it looks like. It is not: the same log has
/// `21:12:44 holding sleep: manual+timer`, so a sixty-minute session begun then
/// had 39 seconds of it left at 22:12:05, and `restoreSession` prints
/// `Int(left / 60)`. `SessionRestore.decide` refuses everything at or past the
/// deadline — `endDate > now`, then `bounded > 0`, both strict — and the first
/// case here is what says so rather than leaving it to be re-derived from a log.
final class ASessionWithSecondsLeftIsNotOverTests: XCTestCase {

    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var clock: FakeClock!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        clock = FakeClock()
    }

    override func tearDown() {
        backing = nil
        store = nil
        clock = nil
        super.tearDown()
    }

    private func engine(assertions: FakeAssertions = FakeAssertions()) -> KeepAwakeEngine {
        KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                        assertions: assertions,
                        displayInfo: FakeDisplayInfo(),
                        displayObserver: FakeDisplayObserver(),
                        power: FakePower(), apps: FakeApps(),
                        pointer: FakePointer(), clamshell: FakeClamshell(),
                        clock: clock)
    }

    /// A session with 39 seconds left is a session. It comes back, it holds the
    /// Mac, and it ends 39 seconds later — the three things «restored a session:
    /// 0 min left» has to mean if it is not a defect.
    func testASessionWithSecondsLeftComesBackAndThenEnds() {
        let before = engine()
        before.startSession(minutes: 60)
        clock.current = clock.current.addingTimeInterval(60 * 60 - 39)

        let assertions = FakeAssertions()
        let after = engine(assertions: assertions)
        after.activate()

        XCTAssertTrue(after.isActive, "the last 39 seconds of a session are still the session")
        XCTAssertTrue(assertions.held)

        clock.fire(after: 39)

        XCTAssertFalse(after.isActive, "and it ended when it was always going to end")
        XCTAssertFalse(assertions.held)
        XCTAssertNil(after.endDate)
    }

    /// The other side, so the case above cannot be satisfied by a module that
    /// restores anything at all: a deadline one second in the past stays over.
    func testASessionASecondPastItsDeadlineStaysOver() {
        let before = engine()
        before.startSession(minutes: 60)
        clock.current = clock.current.addingTimeInterval(60 * 60 + 1)

        let assertions = FakeAssertions()
        let after = engine(assertions: assertions)
        after.activate()

        XCTAssertFalse(after.isActive)
        XCTAssertFalse(assertions.held)
    }
}
