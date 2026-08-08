import XCTest
import Carbon.HIToolbox
@testable import HelmUI

/// Two `Int`s out of a plist, on their way into a Carbon call that takes
/// `UInt32`s.
///
/// `HotkeyManager.reload()` converted them with `UInt32(keyCode)` and
/// `UInt32(modifiers)` behind a guard that asked only `keyCode >= 0,
/// modifiers != 0` — which admits `Int.max` and admits every *negative*
/// modifier, and both of those conversions **trap**. The keys live in
/// `UserDefaults.standard` under `module.keep-awake.hotkey*` and
/// `module.layout.convertHotkey*`, so `defaults write … -int -1` reaches them,
/// and `reload()` runs from `applicationDidFinishLaunching`: the app terminates
/// at launch with no window to correct the shortcut from.
///
/// The bounds are Carbon's own rather than a guess. `EventModifiers` is a
/// `UInt16` (`Events.h:105`) and the whole documented mask fits in it, up to
/// `rightControlKey` at 0x8000; a key code occupies one byte of the classic
/// event message (`keyCodeMask = 0x0000FF00`), and the defined `kVK_` constants
/// stop at 0x7E.
final class HotkeyCombinationTests: XCTestCase {

    // MARK: - What the recorder writes

    /// ⌘⇧B, as `HelmHotkeyRecorder.capture` stores it.
    func testAPairTheRecorderWroteIsACombination() throws {
        let combination = try XCTUnwrap(HotkeyCombination(keyCode: kVK_ANSI_B,
                                                          modifiers: cmdKey | shiftKey))
        XCTAssertEqual(combination.code, UInt32(kVK_ANSI_B))
        XCTAssertEqual(combination.modifiers, UInt32(cmdKey | shiftKey))
    }

    /// `kVK_ANSI_A` is **0**, so a zero key code is a real shortcut and not an
    /// empty field. Nothing here may treat it as one.
    func testKeyCodeZeroIsARealKey() {
        XCTAssertNotNil(HotkeyCombination(keyCode: kVK_ANSI_A, modifiers: cmdKey))
    }

    // MARK: - What "no shortcut" looks like

    /// `HelmHotkeyRecorder.clear()` writes -1 and 0, and that pair is the one
    /// `reload()` sees for every module nobody has assigned a shortcut in.
    func testTheClearedSentinelIsNoCombination() {
        XCTAssertNil(HotkeyCombination(keyCode: -1, modifiers: 0))
    }

    /// A key with no modifier swallows an ordinary letter everywhere in the
    /// system, which is why the recorder refuses to write one.
    func testAKeyWithNoModifierIsNoCombination() {
        XCTAssertNil(HotkeyCombination(keyCode: kVK_ANSI_B, modifiers: 0))
    }

    // MARK: - What a plist can hold

    /// The crash the guard admitted: `UInt32(-1)` traps, and a negative is
    /// what a stored `Int` can most easily be.
    func testNegativeModifiersAreNoCombination() {
        XCTAssertNil(HotkeyCombination(keyCode: kVK_ANSI_B, modifiers: -1))
    }

    /// The other side of it. -1 is the sentinel; every other negative is a
    /// number nobody wrote, and it traps identically.
    func testANegativeKeyCodeIsNoCombination() {
        XCTAssertNil(HotkeyCombination(keyCode: -2, modifiers: cmdKey))
        XCTAssertNil(HotkeyCombination(keyCode: Int.min, modifiers: cmdKey))
    }

    func testAKeyCodePastWhatCarbonCanHoldIsNoCombination() {
        XCTAssertNil(HotkeyCombination(keyCode: 0x100, modifiers: cmdKey))
        XCTAssertNil(HotkeyCombination(keyCode: Int.max, modifiers: cmdKey))
    }

    func testModifiersPastWhatCarbonCanHoldAreNoCombination() {
        XCTAssertNil(HotkeyCombination(keyCode: kVK_ANSI_B, modifiers: 0x1_0000))
        XCTAssertNil(HotkeyCombination(keyCode: kVK_ANSI_B, modifiers: Int.max))
    }

    /// The controls, so the refusals above are bounds and not a blanket: the
    /// last value on each side that Carbon has room for still passes.
    func testTheEdgeOfEachRangeIsInside() {
        XCTAssertNotNil(HotkeyCombination(keyCode: 0xFF, modifiers: cmdKey))
        XCTAssertNotNil(HotkeyCombination(keyCode: kVK_ANSI_B, modifiers: 0xFFFF))
        XCTAssertNotNil(HotkeyCombination(keyCode: kVK_ANSI_B, modifiers: rightControlKey))
    }
}
