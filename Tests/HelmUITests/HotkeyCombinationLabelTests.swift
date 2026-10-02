import XCTest
import Carbon.HIToolbox
@testable import HelmUI

/// `HotkeyCombination.label` is what a row draws for a pair that has no label
/// on file, and it is shared: Keep Awake's and Layout's rows reach it through
/// the same recorder as Screenshots'. These are the inputs the first tests did
/// not feed it — every subset of the four modifiers, and a mask that
/// `HotkeyCombination` accepts while holding none of the four.
final class HotkeyCombinationLabelTests: XCTestCase {

    private let four: [(mask: Int, glyph: String)] = [
        (controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘"),
    ]

    /// All fifteen non-empty subsets, spelled in the order the recorder's
    /// `modifierSymbols` writes them (⌃⌥⇧⌘), so a pair spelled from the store
    /// reads the same as one the recorder captured.
    func testEverySubsetOfTheFourIsSpelledInTheRecordersOrder() throws {
        for subset in 1..<16 {
            let chosen = four.enumerated().filter { subset & (1 << $0.offset) != 0 }.map(\.element)
            let mask = chosen.reduce(0) { $0 | $1.mask }
            let combination = try XCTUnwrap(HotkeyCombination(keyCode: kVK_ANSI_K, modifiers: mask))
            XCTAssertEqual(combination.label, chosen.map(\.glyph).joined() + "K", "mask \(String(mask, radix: 16))")
        }
    }

    /// A mask with bits set and none of them one of the four — the side-specific
    /// and lock bits Carbon's `EventModifiers` also carries — is accepted as a
    /// combination (`modifiers != 0`), handed to the manager, and spelled as a
    /// bare key: the row then draws «A», the one shape the recorder refuses to
    /// write because it reads as an ordinary letter.
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
