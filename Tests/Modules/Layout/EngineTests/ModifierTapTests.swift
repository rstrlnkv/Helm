import XCTest
@testable import Module_Layout_Engine

/// A modifier whose release never arrived must not disable the gesture forever.
///
/// The tap used to remember other held modifiers in a set: a code went in on
/// its press and came out on its release. Nothing guarantees the release ever
/// arrives — the tap starts while a key is held, an event is dropped while the
/// tap is re-enabled, or a key reports its press and its release under
/// different codes. Whatever the cause, the code stayed in the set and every
/// tap from then on was spoiled: the gesture stopped working with the tap
/// running, the events flowing and nothing in the log. Reading the flags off
/// each event instead means there is no state left to get stuck.
///
/// Shipped broken in 0.7.2-dev.21, which put the 🌐 key into that set.
///
/// Guards a past defect: the tap remembered a modifier that never came back up (fix commit `7abc76f3`).
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
///
/// Guards a past defect: the tap remembered a modifier that never came back up (fix commit `7abc76f3`).
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
