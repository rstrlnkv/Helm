import XCTest
import Carbon.HIToolbox
@testable import HelmUI

/// The upper bound on a stored modifier mask, proved on a mask that carries one
/// of the four.
///
/// `HotkeyCombinationTests.testModifiersPastWhatCarbonCanHoldAreNoCombination`
/// feeds `0x1_0000`, which holds none of ⌃⌥⇧⌘: since `carriesAModifier` asks for
/// one of the four, that value is refused by the four-bit test whatever the
/// ceiling says, and widening the ceiling left the whole family green. A bit
/// past `EventModifiers` **beside** ⌘ is refused by the ceiling alone.
final class TheModifierCeilingHoldsBesideAModifierTests: XCTestCase {

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
}
