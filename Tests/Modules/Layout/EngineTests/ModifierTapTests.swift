import XCTest
@testable import Module_Layout_Engine

/// One key, pressed and released on its own, asks the module to act. Which
/// means the hard part is everything that must *not* count: the same key used
/// as a modifier, the same key held down, the same key in a chord with another
/// modifier. A false fire here rewrites a word the user was not talking about.
final class ModifierTapTests: XCTestCase {

    private let rightCommand = TapKey.rightCommand.keyCode!

    private func tap(_ key: TapKey = .rightCommand) -> ModifierTap { ModifierTap(key: key) }

    // MARK: - The gesture

    func testPressAndReleaseAloneFires() {
        var machine = tap()
        XCTAssertFalse(machine.feed(.down(rightCommand, at: 0, othersHeld: false)))
        XCTAssertTrue(machine.feed(.up(rightCommand, at: 0.1)))
    }

    func testItFiresAgainOnTheNextTap() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0, othersHeld: false))
        XCTAssertTrue(machine.feed(.up(rightCommand, at: 0.1)))
        _ = machine.feed(.down(rightCommand, at: 1, othersHeld: false))
        XCTAssertTrue(machine.feed(.up(rightCommand, at: 1.1)))
    }

    // MARK: - What must not fire

    /// The whole reason the key is usable at all: ⌘S must still be ⌘S.
    func testTheKeyUsedAsAModifierDoesNotFire() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0, othersHeld: false))
        _ = machine.feed(.otherInput)          // the S
        XCTAssertFalse(machine.feed(.up(rightCommand, at: 0.2)))
    }

    func testHoldingTheKeyDoesNotFire() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0, othersHeld: false))
        // Held past the limit: a hold is somebody waiting for a menu to appear,
        // not somebody asking for their last word back.
        XCTAssertFalse(machine.feed(.up(rightCommand, at: ModifierTap.maxHold + 0.01)))
    }

    func testTheEdgeOfTheHoldLimitStillFires() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0, othersHeld: false))
        XCTAssertTrue(machine.feed(.up(rightCommand, at: ModifierTap.maxHold)))
    }

    func testAnotherModifierHeldWithItDoesNotFire() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0, othersHeld: false))
        _ = machine.feed(.down(TapKey.rightShift.keyCode!, at: 0.05, othersHeld: false))
        XCTAssertFalse(machine.feed(.up(rightCommand, at: 0.2)))
    }

    /// Pressed before the watched key rather than after it — ⇧ then ⌘ then up.
    /// Nothing about the earlier press is remembered; the ⌘ event's own flags
    /// say the ⇧ is still down.
    func testAModifierAlreadyDownDoesNotFire() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0.05, othersHeld: true))
        XCTAssertFalse(machine.feed(.up(rightCommand, at: 0.2)))
    }

    func testAClickInTheMiddleDoesNotFire() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0, othersHeld: false))
        _ = machine.feed(.otherInput)
        XCTAssertFalse(machine.feed(.up(rightCommand, at: 0.1)))
    }

    func testAnotherKeysReleaseIsNotOurs() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0, othersHeld: false))
        XCTAssertFalse(machine.feed(.up(TapKey.rightOption.keyCode!, at: 0.1)))
        // Ours is still armed and still fires.
        XCTAssertTrue(machine.feed(.up(rightCommand, at: 0.2)))
    }

    func testAReleaseWithNoPressIsIgnored() {
        var machine = tap()
        XCTAssertFalse(machine.feed(.up(rightCommand, at: 0.1)))
    }

    /// The left key of the same pair is a different key. Someone who binds the
    /// right Command still has the left one to use as a modifier.
    func testTheLeftTwinDoesNotFire() {
        var machine = tap()
        let leftCommand: Int64 = 55
        _ = machine.feed(.down(leftCommand, at: 0, othersHeld: false))
        XCTAssertFalse(machine.feed(.up(leftCommand, at: 0.1)))
    }

    // MARK: - Off

    func testOffNeverFires() {
        var machine = tap(.off)
        _ = machine.feed(.down(rightCommand, at: 0, othersHeld: false))
        XCTAssertFalse(machine.feed(.up(rightCommand, at: 0.1)))
    }

    func testOffHasNoKeyCode() {
        XCTAssertNil(TapKey.off.keyCode)
        XCTAssertNil(TapKey.off.deviceMask)
    }

    // MARK: - The table

    func testEveryBindableKeyHasACodeAndAMaskOfItsOwn() {
        let bindable = TapKey.allCases.filter { $0 != .off }
        XCTAssertEqual(Set(bindable.compactMap(\.keyCode)).count, bindable.count)
        XCTAssertEqual(Set(bindable.compactMap(\.deviceMask)).count, bindable.count)
    }

    func testAnUnreadableSettingIsOffRatherThanSomeKey() {
        // Stored as a string. A binding nobody chose must not start rewriting
        // words because the value could not be parsed.
        // "leftCommand" used to belong in this list, back when only the right
        // keys existed. It parses now, which is the point of the second loop:
        // the fixture names things that are not keys, and every real case must
        // survive a round trip.
        for raw in [nil, "", "middleCommand", "⌘", "RightCommand"] {
            XCTAssertEqual(TapKey.from(raw), .off, String(describing: raw))
        }
        for key in TapKey.allCases {
            XCTAssertEqual(TapKey.from(key.rawValue), key)
        }
    }
}

/// The Globe key as a tap key.
///
/// It cannot be a chord: Carbon's hotkey modifiers are ⌘⇧⌥⌃ and a right-shift
/// bit documented "Not supported on Mac OS X" (Events.h), with no bit for fn at
/// all. So the only rail it can ride is this one.
final class GlobeTapKeyTests: XCTestCase {

    /// `kVK_Function` in Events.h, and `NX_SECONDARYFNMASK` in IOLLEvent.h.
    /// Written down because both are magic numbers with no symbol in Swift.
    func testGlobeIsTheKeyCodeAndMaskTheSystemUses() {
        XCTAssertEqual(TapKey.globe.keyCode, 63)
        XCTAssertEqual(TapKey.globe.deviceMask, 0x800000)
    }

    /// It taps like every other key: press, release, nothing in between.
    func testATapFires() {
        var tap = ModifierTap(key: .globe)
        XCTAssertFalse(tap.feed(.down(63, at: 0, othersHeld: false)))
        XCTAssertTrue(tap.feed(.up(63, at: 0.1)))
    }

    /// And it refuses like every other key, which is what makes 🌐 usable at
    /// all — held or combined it stays the system's key.
    func testHoldingOrCombiningIsNotATap() {
        var held = ModifierTap(key: .globe)
        _ = held.feed(.down(63, at: 0, othersHeld: false))
        XCTAssertFalse(held.feed(.up(63, at: 0.9)))

        var combined = ModifierTap(key: .globe)
        _ = combined.feed(.down(63, at: 0, othersHeld: false))
        _ = combined.feed(.otherInput)
        XCTAssertFalse(combined.feed(.up(63, at: 0.1)))
    }
}

/// Both sides of the keyboard.
///
/// The left keys were withheld at first, on the reasoning that the right one of
/// a pair is a spare while the left is the key the hand rests on. That is still
/// true and is why the page says so — but it is the person's keyboard.
final class LeftTapKeyTests: XCTestCase {

    /// Every key must name its own side. `.maskCommand` cannot tell left from
    /// right, so releasing the left ⌘ while the right is held would read as the
    /// key still being down.
    func testEverySideHasItsOwnCodeAndBit() {
        let expected: [TapKey: (Int64, UInt64)] = [
            .rightCommand: (54, 0x000010), .leftCommand: (55, 0x000008),
            .rightOption: (61, 0x000040), .leftOption: (58, 0x000020),
            .rightControl: (62, 0x002000), .leftControl: (59, 0x000001),
            .rightShift: (60, 0x000004), .leftShift: (56, 0x000002),
        ]
        for (key, (code, mask)) in expected {
            XCTAssertEqual(key.keyCode, code, "\(key)")
            XCTAssertEqual(key.deviceMask, mask, "\(key)")
        }
    }

    /// No two keys may share a code or a bit, or one would fire for the other.
    func testNoTwoKeysCollide() {
        let keys = TapKey.allCases.filter { $0 != .off }
        XCTAssertEqual(Set(keys.compactMap(\.keyCode)).count, keys.count)
        XCTAssertEqual(Set(keys.compactMap(\.deviceMask)).count, keys.count)
    }

    /// A left key taps and refuses exactly like a right one — the difference is
    /// how often it is touched, not how it behaves.
    func testALeftKeyTapsAndRefusesLikeAnyOther() {
        var tap = ModifierTap(key: .leftOption)
        XCTAssertFalse(tap.feed(.down(58, at: 0, othersHeld: false)))
        XCTAssertTrue(tap.feed(.up(58, at: 0.1)))

        var combined = ModifierTap(key: .leftOption)
        _ = combined.feed(.down(58, at: 0, othersHeld: false))
        _ = combined.feed(.otherInput)
        XCTAssertFalse(combined.feed(.up(58, at: 0.1)))
    }

    /// The page shows a note for the keys people type with, and only those.
    func testOnlyTheLeftKeysAreMarkedAsFrequentlyUsed() {
        XCTAssertTrue(TapKey.leftShift.isFrequentlyUsed)
        XCTAssertTrue(TapKey.leftCommand.isFrequentlyUsed)
        XCTAssertFalse(TapKey.rightCommand.isFrequentlyUsed)
        XCTAssertFalse(TapKey.globe.isFrequentlyUsed)
        XCTAssertFalse(TapKey.off.isFrequentlyUsed)
    }
}

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
