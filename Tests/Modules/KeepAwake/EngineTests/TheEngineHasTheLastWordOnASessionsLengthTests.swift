import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// How long a session may be is the engine's question, not the picker's.
///
/// Every number a person can choose is already bounded where they choose it —
/// the settings stepper, the panel tile's presets, `TimerPolicy.extendedMinutes`
/// for the "+15" button. `startSession` itself took the number on trust and
/// multiplied it:
///
///     endDate = clock.now().addingTimeInterval(TimeInterval(minutes * 60))
///
/// `Int` multiplication traps on overflow in Swift, in release as well as
/// debug. And one caller is not a picker at all: `wireTransport` decodes
/// `KeepAwakeStart` from a JSON payload and passes `payload.minutes` straight
/// in, with nothing between the wire and the multiply that says how large a
/// number may be. A clamp in every view is a clamp in no engine.
final class TheEngineHasTheLastWordOnASessionsLengthTests: XCTestCase {

    private var store: NamespacedStore!
    private var clock: FakeClock!
    private var assertions: FakeAssertions!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        clock = FakeClock()
        assertions = FakeAssertions()
    }

    private func engine() -> KeepAwakeEngine {
        KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                        assertions: assertions,
                        displayInfo: FakeDisplayInfo(),
                        displayObserver: FakeDisplayObserver(),
                        power: FakePower(), apps: FakeApps(),
                        pointer: FakePointer(), clamshell: FakeClamshell(),
                        clock: clock)
    }

    /// Asserted as the property the arithmetic needs rather than as a
    /// particular ceiling, so a fix may choose any bound it likes.
    func testAStartAskingForEveryMinuteThereIsStillEndsWithinADay() throws {
        let module = engine()

        module.startSession(minutes: .max)

        let end = try XCTUnwrap(module.endDate, "an absurd request became a session with no end")
        XCTAssertLessThanOrEqual(end.timeIntervalSince(clock.current), TimeInterval(24 * 60 * 60),
                                 "the ceiling this module already keeps for every other number")
        XCTAssertTrue(module.isActive)
    }

    /// The other end of the same multiply, and the worse answer of the two.
    /// `minutes > 0` is false for a negative, which is how this module spells
    /// **"until I say stop"** — so a session of minus a minute became one with
    /// no deadline at all, holding the assertion until somebody noticed. A
    /// negative duration is not a session.
    func testAStartAskingForANegativeSessionStartsNothing() {
        let module = engine()

        module.startSession(minutes: -1)

        XCTAssertFalse(module.isActive, "a negative duration held the Mac awake indefinitely")
        XCTAssertFalse(assertions.held)
        XCTAssertNil(module.endDate)
    }

    func testTheSameForTheNumberThatOverflowsTheMultiplyDownwards() {
        let module = engine()

        module.startSession(minutes: .min)

        XCTAssertFalse(module.isActive)
        XCTAssertFalse(assertions.held)
    }

    // MARK: - The controls

    func testAnOrdinarySessionIsStillExactlyWhatWasAskedFor() {
        let module = engine()

        module.startSession(minutes: 30)

        XCTAssertEqual(module.endDate, clock.current.addingTimeInterval(1800))
        XCTAssertTrue(assertions.held)
    }

    /// Zero is the module's own spelling of "until I say stop", and it stays
    /// that: the refusal above is about a number below it, not about it.
    func testZeroIsStillASessionWithNoDeadline() {
        let module = engine()

        module.startSession(minutes: 0)

        XCTAssertTrue(module.isActive)
        XCTAssertNil(module.endDate)
        XCTAssertTrue(assertions.held)
    }
}
