import XCTest
@testable import HelmUI

/// The point of the table: after correction, every symbol Helm draws paints
/// the same amount of ink.
final class SymbolInkTests: XCTestCase {

    /// Uncorrected, the set spans 0.99 to 1.27 — 28% of visual size between the
    /// largest symbol and the smallest, at one point size.
    func testTheProblemIsRealAndThisIsItsSize() {
        let values = SymbolInk.ratios.values
        let spread = values.max()! / values.min()!
        XCTAssertGreaterThan(spread, 1.25, "the table no longer describes a problem")
    }

    /// Corrected, they land within a couple of percent of each other. This is
    /// the assertion the whole file exists for.
    func testCorrectionBringsThemTogether() {
        let corrected = SymbolInk.ratios.map { symbol, ratio in
            ratio * SymbolInk.correction(for: symbol)
        }
        let spread = corrected.max()! / corrected.min()!
        XCTAssertLessThan(spread, 1.02, "corrected sizes still differ: \(corrected)")
    }

    /// A symbol nobody measured is left alone rather than guessed at.
    func testAnUnmeasuredSymbolIsUnchanged() {
        XCTAssertEqual(SymbolInk.correction(for: "sparkles"), 1)
    }

    /// The correction goes the way it should: the crowded symbols shrink.
    func testTheCrowdedSymbolsShrink() {
        XCTAssertLessThan(SymbolInk.correction(for: "keyboard"), 0.9)
        XCTAssertLessThan(SymbolInk.correction(for: "doc.on.doc"), 0.9)
        XCTAssertGreaterThan(SymbolInk.correction(for: "lock.shield"), 1.1)
    }
}
