import XCTest
import HelmTestSupport
@testable import HelmUI

/// **Each segment as wide as what it shows — narrower than the system control
/// that gave every segment the longest word's width.**
///
/// Asked for 2026-09-17: the toolbar's segmented control spent 4 × 122 pt on
/// Homebrew in Russian, «Поиск» sitting in a field three times its size. The
/// widths below are `HelmToolbarSwitcher.width`, the numbers the page decides
/// with and the drawing is laid out by.
final class TheToolbarSwitcherIsAsWideAsItsWordsTests: XCTestCase {

    private let homebrew = ["Installed", "Updates", "Search", "Health"]

    func testWordsAreNarrowerThanEqualSegmentsOfTheLongestWord() {
        AppLanguage.each { language in
            let labels = [L("Installed"), L("Updates"), L("Search"), L("Health")]
            let words = HelmToolbarSwitcher<Int>.width(of: labels, in: .text)
            let system = HelmPickerWidth.segmented(labels)
            XCTAssertLessThan(words, system, """
                \(language.rawValue): segments as wide as their words take \(words) pt, no less than \
                the system control's equal shares (\(system)) — nothing was saved by drawing our own
                """)
        }
    }

    /// The four styles in the order the mockup measured them, so a constant
    /// changed in one style shows up against the others.
    func testTheStylesOrderByWidth() {
        let icons = HelmToolbarSwitcher<Int>.width(of: homebrew, in: .icons)
        let naming = HelmToolbarSwitcher<Int>.width(of: homebrew, in: .iconsNamingSelected)
        let text = HelmToolbarSwitcher<Int>.width(of: homebrew, in: .text)
        let both = HelmToolbarSwitcher<Int>.width(of: homebrew, in: .iconsAndText)
        XCTAssertLessThan(icons, naming, "glyphs alone are not narrower than glyphs with one name")
        XCTAssertLessThan(naming, text, "one name is not narrower than every name")
        XCTAssertLessThan(text, both, "words alone are not narrower than words with glyphs")
        XCTAssertEqual(icons, 4 * 40 + 3 + 6, "four glyph segments, three dividers and the inset")
    }

    func testAnUnknownStoredStyleIsWords() {
        XCTAssertEqual(ToolbarSwitcherStyle(stored: ""), .text)
        XCTAssertEqual(ToolbarSwitcherStyle(stored: "nonsense"), .text)
        XCTAssertEqual(ToolbarSwitcherStyle(stored: "icons"), .icons)
    }
}
