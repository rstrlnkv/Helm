import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// Text that recedes takes `HelmText`'s ink, never the platform's `.secondary`.
///
/// `HelmText.quiet` exists because `.secondary` does not clear the body floor:
/// composited onto the window in light it measures **3,95:1** against a floor of
/// 4,5, and the token was solved to 4,92. That number is written down at
/// `HelmText.quiet` and in `LeftoversSettingsPage`, which is prose in two
/// places with nothing under it — and eight `Text`s in one module were drawing
/// `.secondary` all the while, every one of them a fact stated once and stated
/// under the floor.
///
/// **`.secondary` on a mark is a different question and is not asked here.** A
/// dot, a plate's default and a symbol beside a word answer to the 3:1 mark
/// floor, which `.secondary` clears; the defect is the *ink of a sentence*. The
/// two are told apart by the shape of the call rather than by a second scan of
/// the lines above: what paints a glyph in this tree is a ternary
/// (`basketed ? Color.accentColor : .secondary`) or a `.fill`, and the patterns
/// below match only a `foregroundStyle`/`foregroundColor` whose whole argument
/// is `.secondary` — the form that is only ever applied to a `Text`. A glyph
/// written that way would be reported, and would be a decision for whoever
/// wrote it rather than a false positive to filter out in advance.
final class QuietInkIsHelmsOwnTests: XCTestCase {

    /// The value is `UISources.sites`' second argument and means nothing here —
    /// that reader is built for a type scale, where the number is the size a
    /// style resolves to. What is wanted from it is the walk: the file list, the
    /// comment strip and the line number, compiled once rather than per line.
    private static let patterns: [String: Double] = [
        #"\.foregroundStyle\(\s*(?:Color)?\.secondary\s*\)"#: 0,
        #"\.foregroundColor\(\s*(?:Color)?\.secondary\s*\)"#: 0,
    ]

    func testNoTextTakesThePlatformsSecondaryInk() throws {
        let sites = try UISources.sites(matching: Self.patterns,
                                        in: UISources.everyDrawnFile())
        XCTAssertEqual(sites.map(\.where_), [], """
            These lines set text in the platform's `.secondary`, which measures 3,95:1 on \
            the window in light — under the 4,5:1 body floor `HelmText.quiet` (4,92:1) was \
            solved for. Use `HelmText.quiet`, or `HelmText.faint` for a caption that is \
            short and never the only place a fact appears.
            \(UISources.summary(sites))
            """)
    }

    /// **The floor this rule is built on, measured rather than remembered.**
    ///
    /// `.secondary` is a translucent ink, so it has to be composited onto the
    /// surface it lands on before it is read — the trap `Contrast` documents,
    /// where every opacity clears every threshold if you skip that step. If
    /// macOS ever darkens it past the floor this test goes red, and the rule
    /// above becomes a question about consistency alone rather than legibility.
    func testThePlatformsSecondaryIsUnderTheBodyFloor() {
        let window = Contrast.system(\.windowBackgroundColor, .aqua)
        let ink = Contrast.over(Contrast.resolved(.secondary, .aqua), window)
        let ratio = Contrast.ratio(ink, window)
        XCTAssertLessThan(ratio, Contrast.bodyFloor, """
            `.secondary` on the window now measures \(String(format: "%.2f", ratio)):1, \
            which clears the body floor. The reason this rule was written has changed.
            """)
        let quiet = Contrast.over(Contrast.resolved(HelmText.quiet, .aqua), window)
        XCTAssertGreaterThanOrEqual(Contrast.ratio(quiet, window), Contrast.bodyFloor,
                                    "`HelmText.quiet` is under the floor it was solved for; "
                                    + "the replacement this rule asks for is not a fix")
    }

    /// **The rule above is satisfied by finding nothing, and so is a scan that
    /// has stopped looking.** The floor cannot be «it still finds some», because
    /// the honest answer is zero — so the patterns are put through the same
    /// reader against a fixture instead, which is what `UISources.sites(_:in:)`'s
    /// string overload exists for.
    func testTheScanStillReadsTheTree() throws {
        XCTAssertGreaterThan(try UISources.everyDrawnFile().count, 50,
                             "the file list has collapsed; this check is idle")
        let caught = try UISources.sites(matching: Self.patterns, in: """
            Text(said).foregroundStyle(.secondary)
            Text(said).foregroundStyle(Color.secondary)
            Text(said).foregroundColor(.secondary)
            Text(said).foregroundStyle(HelmText.quiet)
            Image(systemName: s).foregroundStyle(basketed ? Color.accentColor : .secondary)
            """)
        let found = caught.map(\.text)
        XCTAssertEqual(caught.map(\.line), [1, 2, 3], """
            the patterns no longer catch the three shapes they are written for, or they \
            now catch the ink of a glyph as well: \(found)
            """)
    }
}
