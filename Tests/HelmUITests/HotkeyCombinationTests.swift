import XCTest
import Carbon.HIToolbox
@testable import HelmUI

/// Two `Int`s out of a plist, on their way into a Carbon call that takes
/// `UInt32`s.
///
/// A stored value outside `UInt32` must not reach a trapping conversion:
/// `HotkeyManager.reload()` runs at launch, so a bad value written with
/// `defaults write … -int -1` would end the app with no window to correct the
/// shortcut from. The bounds are Carbon's own (`HotkeyCombination`).
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

    // MARK: - What "no shortcut" looks like, and what a plist can hold

    func testWhatIsNoCombination() {
        let rows: [(why: String, key: Int, mods: Int)] = [
            // `HelmHotkeyRecorder.clear()` writes -1 and 0: the pair for every
            // module nobody has assigned a shortcut in.
            ("the cleared sentinel", -1, 0),
            // A key with no modifier swallows an ordinary letter everywhere in
            // the system, which is why the recorder refuses to write one.
            ("a key with no modifier", kVK_ANSI_B, 0),
            // `UInt32(-1)` traps, and a negative is what a stored `Int` can
            // most easily be.
            ("negative modifiers", kVK_ANSI_B, -1),
            // The other side of it. -1 is the sentinel; every other negative is
            // a number nobody wrote, and it traps identically.
            ("the sentinel key code with a modifier", -1, cmdKey),
            ("a negative key code", -2, cmdKey),
            ("the least key code", Int.min, cmdKey),
            ("a key code past what Carbon can hold", 0x100, cmdKey),
            ("the greatest key code", Int.max, cmdKey),
            ("modifiers past what Carbon can hold", kVK_ANSI_B, 0x1_0000),
            ("the greatest modifiers", kVK_ANSI_B, Int.max),
        ]
        for row in rows {
            XCTAssertNil(HotkeyCombination(keyCode: row.key, modifiers: row.mods), row.why)
        }
    }

    /// The upper bound on a stored modifier mask, proved on a mask that carries one
    /// of the four.
    ///
    /// `testWhatIsNoCombination` feeds `0x1_0000`, which holds none of ⌃⌥⇧⌘ and
    /// is refused by the four-bit test whatever the ceiling says. A bit past
    /// `EventModifiers` beside ⌘ is refused by the ceiling alone.
    func testABitPastCarbonsMaskBesideCommandIsNoCombination() {
        for past in [0x1_0000, 0x2_0000, 0x8000_0000] {
            XCTAssertNil(HotkeyCombination(keyCode: kVK_ANSI_B, modifiers: cmdKey | past),
                         "⌘ plus 0x\(String(past, radix: 16)): a bit Carbon's mask has no room for was accepted")
            XCTAssertFalse(HotkeyCombination.carriesAModifier(cmdKey | past),
                           "⌘ plus 0x\(String(past, radix: 16)): the recorder's predicate says yes")
        }
        // The control: the same ⌘ inside the ceiling stands.
        XCTAssertNotNil(HotkeyCombination(keyCode: kVK_ANSI_B, modifiers: cmdKey | rightControlKey))
    }

    /// The controls, so the refusals above are bounds and not a blanket: the
    /// last value on each side that Carbon has room for still passes.
    func testTheEdgeOfEachRangeIsInside() {
        XCTAssertNotNil(HotkeyCombination(keyCode: 0xFF, modifiers: cmdKey))
        XCTAssertNotNil(HotkeyCombination(keyCode: kVK_ANSI_B, modifiers: 0xFFFF))
        // The top bit of the mask, beside a modifier. On its own it is no
        // shortcut (`testAMaskHoldingNoneOfTheFourIsNotDrawnAsABareKey`, below).
        XCTAssertNotNil(HotkeyCombination(keyCode: kVK_ANSI_B, modifiers: cmdKey | rightControlKey))
    }

    // MARK: - A mask holding none of the four

    /// A mask whose bits are none of the four (the side-specific and lock bits
    /// `EventModifiers` also carries) is no combination: accepted, it would be
    /// spelled as a bare key, «A», which swallows an ordinary letter everywhere.
    func testAMaskHoldingNoneOfTheFourIsNotDrawnAsABareKey() {
        let others: [(String, Int)] = [
            ("rightShiftKey", rightShiftKey), ("rightOptionKey", rightOptionKey),
            ("rightControlKey", rightControlKey), ("alphaLock", alphaLock),
        ]
        for (name, mask) in others {
            XCTAssertNil(HotkeyCombination(keyCode: kVK_ANSI_A, modifiers: mask),
                         "\(name) alone: accepted as a shortcut, and drawn as the bare letter")
            XCTAssertFalse(HotkeyCombination.carriesAModifier(mask), "\(name) alone: the recorder's predicate says yes")
        }
        // Not a blanket refusal of the odd bits: beside one of the four they are
        // ignored by the label and the combination stands.
        let mixed = HotkeyCombination(keyCode: kVK_ANSI_A, modifiers: cmdKey | rightShiftKey | alphaLock)
        XCTAssertEqual(mixed?.label, "⌘A")
    }
}
