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
        XCTAssertFalse(machine.feed(.down(rightCommand, at: 0)))
        XCTAssertTrue(machine.feed(.up(rightCommand, at: 0.1)))
    }

    func testItFiresAgainOnTheNextTap() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0))
        XCTAssertTrue(machine.feed(.up(rightCommand, at: 0.1)))
        _ = machine.feed(.down(rightCommand, at: 1))
        XCTAssertTrue(machine.feed(.up(rightCommand, at: 1.1)))
    }

    // MARK: - What must not fire

    /// The whole reason the key is usable at all: ⌘S must still be ⌘S.
    func testTheKeyUsedAsAModifierDoesNotFire() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0))
        _ = machine.feed(.otherInput)          // the S
        XCTAssertFalse(machine.feed(.up(rightCommand, at: 0.2)))
    }

    func testHoldingTheKeyDoesNotFire() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0))
        // Held past the limit: a hold is somebody waiting for a menu to appear,
        // not somebody asking for their last word back.
        XCTAssertFalse(machine.feed(.up(rightCommand, at: ModifierTap.maxHold + 0.01)))
    }

    func testTheEdgeOfTheHoldLimitStillFires() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0))
        XCTAssertTrue(machine.feed(.up(rightCommand, at: ModifierTap.maxHold)))
    }

    func testAnotherModifierHeldWithItDoesNotFire() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0))
        _ = machine.feed(.down(TapKey.rightShift.keyCode!, at: 0.05))
        XCTAssertFalse(machine.feed(.up(rightCommand, at: 0.2)))
    }

    /// Pressed before the watched key rather than after it — ⇧ then ⌘ then up.
    func testAModifierAlreadyDownDoesNotFire() {
        var machine = tap()
        _ = machine.feed(.down(TapKey.rightShift.keyCode!, at: 0))
        _ = machine.feed(.down(rightCommand, at: 0.05))
        XCTAssertFalse(machine.feed(.up(rightCommand, at: 0.2)))
    }

    func testAClickInTheMiddleDoesNotFire() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0))
        _ = machine.feed(.otherInput)
        XCTAssertFalse(machine.feed(.up(rightCommand, at: 0.1)))
    }

    func testAnotherKeysReleaseIsNotOurs() {
        var machine = tap()
        _ = machine.feed(.down(rightCommand, at: 0))
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
        _ = machine.feed(.down(leftCommand, at: 0))
        XCTAssertFalse(machine.feed(.up(leftCommand, at: 0.1)))
    }

    // MARK: - Off

    func testOffNeverFires() {
        var machine = tap(.off)
        _ = machine.feed(.down(rightCommand, at: 0))
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
        for raw in [nil, "", "leftCommand", "⌘"] {
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
        XCTAssertFalse(tap.feed(.down(63, at: 0)))
        XCTAssertTrue(tap.feed(.up(63, at: 0.1)))
    }

    /// And it refuses like every other key, which is what makes 🌐 usable at
    /// all — held or combined it stays the system's key.
    func testHoldingOrCombiningIsNotATap() {
        var held = ModifierTap(key: .globe)
        _ = held.feed(.down(63, at: 0))
        XCTAssertFalse(held.feed(.up(63, at: 0.9)))

        var combined = ModifierTap(key: .globe)
        _ = combined.feed(.down(63, at: 0))
        _ = combined.feed(.otherInput)
        XCTAssertFalse(combined.feed(.up(63, at: 0.1)))
    }
}
