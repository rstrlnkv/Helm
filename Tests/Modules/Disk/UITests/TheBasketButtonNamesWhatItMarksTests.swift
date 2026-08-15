import XCTest
import HelmUI
@testable import Module_Disk_UI

/// «Mark for removal», said once per row down a list of two hundred.
///
/// `DkStr.markForRemoval`'s own doc records why the previous name was wrong —
/// "'Add' has no object, and a screen reader says it once per row down a list
/// of two hundred" — and the fix changed the *verb* only. The object was still
/// missing: every `+` on the ring's list and in the Recommendations popover
/// announced the same four words, with the row's identity coming from a
/// separate combined element beside it. The Uninstaller puts the app's own name
/// on its checkbox.
///
/// So the name carries the row's, and it is one interpolated key rather than a
/// sentence assembled at the call site — which is what keeps it in eight
/// languages: an interpolation runs before the lookup, so the table is inline
/// and the language has to be nameable.
final class TheBasketButtonNamesWhatItMarksTests: XCTestCase {

    private let row = "Downloads"

    func testEveryLanguageNamesTheRowInBothStates() {
        for language in AppLanguage.allCases {
            for basketed in [true, false] {
                let name = DkStr.basketAction(name: row, basketed: basketed, language: language)
                XCTAssertTrue(name.contains(row), """
                    \(language.rawValue) announces \(Quoted(name, language: .en)) for a row \
                    called \(row) (marked: \(basketed)) — the same words as every other row on \
                    the screen, so the one thing a screen reader needs from this button is the \
                    one thing it does not say.
                    """)
            }
        }
    }

    /// The name is quoted the way that language quotes a name, rather than with
    /// English's pair or with none: `Quoted` exists because three of the eight
    /// had been translated rather than read.
    func testTheRowsNameIsQuotedTheWayTheLanguageQuotesAName() {
        for language in AppLanguage.allCases {
            XCTAssertTrue(
                DkStr.basketAction(name: row, basketed: false, language: language)
                    .contains(Quoted(row, language: language)),
                "\(language.rawValue) quotes a file name with somebody else's marks")
        }
    }

    /// Two rows, two names — the property the whole finding is about, and one an
    /// assertion about a single string cannot make.
    func testTwoRowsDoNotShareOneName() {
        for language in AppLanguage.allCases {
            XCTAssertNotEqual(DkStr.basketAction(name: "Downloads", basketed: false,
                                                 language: language),
                              DkStr.basketAction(name: "Movies", basketed: false,
                                                 language: language),
                              "\(language.rawValue) gives two different rows one name")
        }
    }

    /// And the two states still differ, in every language: the button toggles, so
    /// a name that did not would announce the opposite of what pressing it does.
    func testTheTwoStatesStillDiffer() {
        for language in AppLanguage.allCases {
            XCTAssertNotEqual(DkStr.basketAction(name: row, basketed: true, language: language),
                              DkStr.basketAction(name: row, basketed: false, language: language),
                              "\(language.rawValue) has one name for two opposite actions")
        }
    }
}
