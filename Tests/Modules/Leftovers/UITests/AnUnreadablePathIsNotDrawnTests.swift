import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// The detail line under a dead login item holds two halves, and the reason is
/// the half that keeps its words. At the 540 pt pane a real reason left the
/// path **one glyph**: «/», still drawn, still read to VoiceOver, saying
/// nothing.
///
/// The rule this file guards: a path that cannot show at least its own last
/// component is not information, and is not drawn at all — the row falls back
/// to the reason alone, bare of its separator. The claims split the way
/// `TheReturnBannerFoldsItsButtonsTests` splits them: the hazard is real in
/// every language, the floor is the name and not a glyph, the narrow pane is
/// measured drawing no path, and the shipped row is built of the parts
/// measured here.
final class AnUnreadablePathIsNotDrawnTests: XCTestCase {

    /// A login item the way the defect arrives: a helper agent whose plist
    /// points into an application folder that is gone — vendor paths of this
    /// length are ordinary, not adversarial.
    private let item = StaleItem(
        path: "\(NSHomeDirectory())/Library/LaunchAgents/com.adobe.ccxprocess.plist",
        identifier: "com.adobe.ccxprocess",
        kind: .launchAgent,
        sizeBytes: 4_096,
        missingTarget: "/Applications/Adobe Creative Cloud/Adobe Creative Cloud Experience"
            + "/CCXProcess.app/Contents/MacOS/CCXProcess")

    /// The narrowest pane of the audit, as the other width guards spell it.
    private let narrowestPane: CGFloat = 540

    private func detailFont() -> NSFont {
        NSFont.systemFont(ofSize: HelmText.rowDetailSize)
    }

    /// The hazard is real: in every language the reason alone outgrows the
    /// whole pane — before any row chrome is subtracted — so the room it
    /// leaves the path is below the path's floor, and without the guard the
    /// path compresses to a glyph rather than yielding.
    func testTheReasonLeavesThePathLessThanItsFloor() throws {
        for language in AppLanguage.allCases {
            let detail = LfStr.detail(for: item, language: language)
            let reason = try XCTUnwrap(detail?.reason, language.rawValue)
            let room = narrowestPane - ControlMetrics.label(reason, font: detailFont())
            XCTAssertLessThan(room, LeftoverPathFloor.width(of: item.path),
                              "\(language.rawValue): the pane leaves the path room enough — "
                              + "the fallback this file guards would never be taken")
        }
    }

    /// The floor is the last component with its ellipsis, measured — never a
    /// glyph's worth. A floor of zero (or of one «/») re-admits the defect
    /// while the page still dutifully reads it.
    func testTheFloorIsTheNameNotAGlyph() {
        let floor = LeftoverPathFloor.width(of: item.path)
        let name = ControlMetrics.label("…com.adobe.ccxprocess.plist", font: detailFont())
        XCTAssertGreaterThanOrEqual(floor, name,
                                    "the floor admits a path too narrow for its own name")
        XCTAssertGreaterThan(name, ControlMetrics.label("/", font: detailFont()) * 4,
                             "precondition: the name is meaningfully wider than the glyph")
    }

    /// The fallback the narrow pane takes carries no separator: the dot
    /// belongs between the path and the reason, and with the path gone a line
    /// opening «· Points at…» is the dangling-dot defect at the other end —
    /// measured on the first render of the guard, before `clause` existed.
    func testTheFallbackHasNothingForTheSeparatorToSeparate() throws {
        for language in AppLanguage.allCases {
            let detail = try XCTUnwrap(LfStr.detail(for: item, language: language))
            let clause = try XCTUnwrap(detail.clause, language.rawValue)
            XCTAssertEqual(clause,
                           LfStr.missingTarget(item.missingTarget!, language: language),
                           "\(language.rawValue): the fallback is not the bare sentence")
            XCTAssertEqual(detail.reason, detail.separator + clause,
                           "\(language.rawValue): the two halves no longer agree")
        }
    }

    /// Measured, because «not drawn» is a claim about a drawing. Two rows
    /// differing only in their *path* — same name, same reason, and an
    /// identifier matching neither file name, or `LaunchLabel` gives one row a
    /// Turn off button the other lacks and the removability variant of the
    /// same trap follows (both were measured drowning this claim in a
    /// difference that was never the path's). At a wide pane they are two
    /// pictures, which is the path actually on the screen; at the narrow one
    /// they are the same picture to the byte, which is the path gone rather
    /// than compressed to a glyph. The wide reading is the precondition the
    /// absence claim needs — a band that was never drawn reads as equal too.
    @MainActor
    func testAtTheNarrowPaneThePathIsNotOnTheScreen() async throws {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        func agent(_ file: String) -> StaleItem {
            StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(file).plist",
                      identifier: "com.adobe.ccx", kind: .launchAgent,
                      sizeBytes: item.sizeBytes, missingTarget: item.missingTarget)
        }
        let long = agent("com.adobe.ccxprocess"), short = agent("x")

        let wide = (try await ink(of: long, at: 1_200), try await ink(of: short, at: 1_200))
        XCTAssertNotEqual(wide.0, wide.1,
                          "precondition: at a wide pane two paths are two pictures")

        let narrow = (try await ink(of: long, at: narrowestPane),
                      try await ink(of: short, at: narrowestPane))
        XCTAssertGreaterThan(narrow.0, 0, "precondition: the page drew at all")
        XCTAssertEqual(narrow.0, narrow.1, """
            two rows differing only in their path are drawn differently at \
            \(Int(narrowestPane)) pt — the path is still on the screen where \
            its floor does not fit
            """)
    }

    @MainActor
    private func ink(of item: StaleItem, at width: CGFloat) async throws -> Int {
        let (mount, _) = await LeftoversPageRender.page([item], language: .en,
                                                        width: width, appearance: .aqua)
        defer { mount.drop() }
        return try XCTUnwrap(mount.settledInk(), "the page never settled")
    }

    /// And the shipped row is built of the parts measured here: the detail line
    /// offers the path only above its floor, and the fallback the narrow pane
    /// takes holds the reason alone — so the path is neither drawn nor combined
    /// into the row's accessibility element. (`accessibilityChildren()` is
    /// empty under the suite, so the a11y half is held by structure: what
    /// `ViewThatFits` does not choose contributes no subview to combine.)
    func testTheShippedRowDropsAnUnreadablePath() throws {
        let page = try RepoSource.text(of:
            "Sources/Modules/Leftovers/UI/LeftoversSettingsPage.swift")
        XCTAssertTrue(page.contains("LeftoverDetailLine(detail: detail)"),
                      "the row no longer draws its detail through the guarded line")
        let line = try RepoSource.text(of:
            "Sources/Modules/Leftovers/UI/LeftoverDetailLine.swift")

        XCTAssertTrue(line.contains("ViewThatFits"), """
            The detail line has no fallback: the path is always drawn, and at \
            the narrow pane it compresses to a glyph instead of yielding.
            """)
        XCTAssertTrue(line.contains("LeftoverPathFloor.width"), """
            The detail line does not read the floor this file measures, so the \
            arithmetic above guards nothing the page draws.
            """)
        XCTAssertTrue(line.contains("Text(clause)"), """
            The fallback draws the reason with its separator — a line opening \
            «· Points at…» is the dangling dot with nothing before it.
            """)
    }
}
