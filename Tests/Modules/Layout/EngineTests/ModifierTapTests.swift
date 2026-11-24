import XCTest
@testable import Module_Layout_Engine

/// A modifier whose release never arrived must not disable the gesture forever.
///
/// Nothing guarantees a release arrives: the tap starts while a key is held, an
/// event is dropped while the tap is re-enabled, or a key reports its press and
/// release under different codes. Remembered between events, the code would
/// spoil every later tap with nothing in the log. Reading the flags off each
/// event leaves no state to get stuck.
final class StuckModifierTests: XCTestCase {

    func testATapStillFiresAfterAModifierThatNeverReleased() {
        var tap = ModifierTap(key: .rightCommand)

        // Something else goes down and is never seen coming back up.
        _ = tap.feed(.down(TapKey.globe.keyCode!, at: 0, othersHeld: false))

        // A clean tap, much later. It must still count.
        XCTAssertFalse(tap.feed(.down(TapKey.rightCommand.keyCode!, at: 10, othersHeld: false)))
        XCTAssertTrue(tap.feed(.up(TapKey.rightCommand.keyCode!, at: 10.1)),
                      "a stale key from ten seconds ago cannot spoil this tap")
    }
}

/// The tap says why it refused, so a gesture that silently never fires leaves
/// something behind to read.
final class RefusalReasonTests: XCTestCase {

    private let rightCommand = TapKey.rightCommand.keyCode!

    func testEachRefusalNamesItself() {
        var chord = ModifierTap(key: .rightCommand)
        _ = chord.feed(.down(rightCommand, at: 0, othersHeld: true))
        _ = chord.feed(.up(rightCommand, at: 0.1))
        XCTAssertEqual(chord.lastRefusal, .chord)

        var held = ModifierTap(key: .rightCommand)
        _ = held.feed(.down(rightCommand, at: 0, othersHeld: false))
        _ = held.feed(.up(rightCommand, at: 0.9))
        XCTAssertEqual(held.lastRefusal, .held)

        var unarmed = ModifierTap(key: .rightCommand)
        _ = unarmed.feed(.up(rightCommand, at: 0.1))
        XCTAssertEqual(unarmed.lastRefusal, .unarmed)
    }

    /// A tap that works says nothing — the reason is cleared, not left over
    /// from whatever the key did last time.
    func testASuccessfulTapLeavesNoReason() {
        var tap = ModifierTap(key: .rightCommand)
        _ = tap.feed(.down(rightCommand, at: 0, othersHeld: true))
        _ = tap.feed(.up(rightCommand, at: 0.1))
        XCTAssertEqual(tap.lastRefusal, .chord)

        _ = tap.feed(.down(rightCommand, at: 1, othersHeld: false))
        XCTAssertTrue(tap.feed(.up(rightCommand, at: 1.1)))
        XCTAssertNil(tap.lastRefusal)
    }
}
