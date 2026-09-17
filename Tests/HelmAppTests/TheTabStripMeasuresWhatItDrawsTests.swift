import XCTest
import HelmTestSupport
@testable import HelmUI

/// **`TabStripFit` decides names-or-glyphs from numbers `PanelTabStrip` draws,
/// and the two live in different targets.**
///
/// The fit answers «do these names fit 296 pt» with a tab's padding, the gap
/// between tabs and the «+»'s width; the strip spells each of them as a
/// literal in the app target, which cannot see the fit's constants. When the
/// Liquid Glass pass (2026-09-17) widened a tab's padding from 8 to 10 and
/// narrowed the gap from 4 to 2, nothing but this would have noticed one half
/// changing without the other — and the symptom is names set in a strip with
/// no room for them, or glyphs where names would have fitted.
final class TheTabStripMeasuresWhatItDrawsTests: XCTestCase {

    private let bars = "Sources/HelmApp/PanelBars.swift"

    private func strip() throws -> String {
        let code = SwiftSource.code(try RepoSource.text(of: bars))
        let start = try XCTUnwrap(code.range(of: "struct PanelTabStrip"),
                                  "\(bars) no longer declares PanelTabStrip")
        let end = code.range(of: "struct PanelGallery", range: start.upperBound..<code.endIndex)
        return String(code[start.lowerBound..<(end?.lowerBound ?? code.endIndex)])
    }

    func testTheTabsPaddingIsTheFitsPadding() throws {
        let side = Int(TabStripFit.padding / 2)
        XCTAssertTrue(try strip().contains(".padding(.horizontal, \(side))"), """
            the fit measures a tab with \(side) pt either side and the strip draws something else
            """)
    }

    func testTheGapBetweenTabsIsTheFitsGap() throws {
        XCTAssertTrue(try strip().contains("HStack(spacing: \(Int(TabStripFit.gap)))"), """
            the fit counts \(Int(TabStripFit.gap)) pt between tabs and the strip's row is spaced \
            by something else
            """)
    }

    func testThePlusIsTheWidthTheFitCounts() throws {
        XCTAssertTrue(try strip().contains(".frame(width: \(Int(TabStripFit.addButton)), "), """
            the fit counts a \(Int(TabStripFit.addButton)) pt «+» and the strip draws it at \
            another width
            """)
    }
}
