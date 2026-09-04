import HelmUI
import XCTest
@testable import Module_Layout_UI

/// The palette opener finds the Edit-menu item of *another* app by its title,
/// and that app speaks whatever language its user set — so the match set is
/// AppKit's own `InputManager.loctable` read whole, every language at once,
/// not Helm's eight.
///
/// The two sources must agree: Helm's `.strings` files spell the menu item the
/// way the system table does (§ read the system's spelling out of its bundle),
/// so every one of Helm's eight spellings must be in the set the opener
/// matches with. A retranslation creeping into a `.strings` file fails here;
/// so does the reader losing the table.
final class EmojiPaletteNamesTests: XCTestCase {

    func testEverySpellingHelmUsesIsInTheSystemsOwnTable() {
        let names = EmojiPalette.systemNames
        for language in AppLanguage.allCases {
            let ours = L("Emoji & Symbols", language: language)
            XCTAssertTrue(names.contains(ours), """
                \(language)'s «\(ours)» is not a spelling macOS itself uses for the \
                Edit-menu item (AppKit `InputManager.loctable`, key `Emoji & Symbols`). \
                Either the `.strings` entry was retranslated by hand, or the reader \
                stopped reading the table.
                """)
        }
    }

    /// The table carries a `LocProvenance` bookkeeping entry beside the
    /// languages; a reader that swallows dictionaries indiscriminately would
    /// admit its values as menu titles. Structure, not count: every name in the
    /// set must be a human spelling, and the provenance marker is not one.
    func testTheProvenanceEntryIsNotMistakenForALanguage() {
        for name in EmojiPalette.systemNames {
            XCTAssertFalse(name.isEmpty, "an empty title would match every separator")
            XCTAssertFalse(name.contains("Provenance"),
                           "«\(name)» looks like the table's bookkeeping, not a menu title")
        }
    }
}
