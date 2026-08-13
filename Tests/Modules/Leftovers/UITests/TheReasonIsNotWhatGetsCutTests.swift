import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// The strongest evidence a login item is dead is that it points at a program that
/// is gone — and that clause was the half of the line nobody ever saw.
///
/// The line was one `Text`, path first, truncated at the **tail**: measured, it
/// wants 687.9 pt in English, 763.5 in Russian and 739.5 in German, and it is given
/// 363.0 / 343.5 / 338.5 at the 606 pt pane and 602.0 / 582.5 / 577.5 at 845. At
/// both widths, in all three languages, «Points at a missing file: …» never drew at
/// all: the German row ended «…com.legacy.tool.pli…».
///
/// So the line is two `Text`s: the path at lower layout priority and cut in the
/// middle, where both its ends carry meaning, and the clause whole. Same row
/// height, same strings — the cut lands mid-path, which is where it belongs.
@MainActor
final class TheReasonIsNotWhatGetsCutTests: XCTestCase {

    /// Long enough to fill the detail column on its own at either pane width, which
    /// is the ordinary case: this is what `~/Library/Application Support` paths look
    /// like. With the tail cut, adding a clause to this row changed **nothing** on
    /// screen — measured below.
    private static let longPath = "/Users/somebody/Library/Application Support/com.vendor"
        + ".legacy.tool.helper/Contents/Resources/com.vendor.legacy.tool.plist"

    private static let gone = "/Applications/Gone.app/Contents/MacOS/helper"

    private func item(missingTarget: String?) -> StaleItem {
        StaleItem(path: Self.longPath, identifier: "com.legacy.tool", kind: .launchAgent,
                  sizeBytes: 4_096, missingTarget: missingTarget)
    }

    // MARK: - The two halves of the line

    /// The path and the reason are separate parts, because the row has to be able
    /// to cut one and keep the other. The separator belongs to the reason: a
    /// dangling middle dot with nothing after it is the same defect one character
    /// shorter.
    func testTheLineComesApartIntoThePathAndTheReason() throws {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let detail = try XCTUnwrap(LfStr.detail(for: item(missingTarget: Self.gone)))

            XCTAssertEqual(detail.path, Self.longPath)
            let reason = try XCTUnwrap(detail.reason, "\(language.rawValue): the reason is not a "
                                       + "part of its own, so nothing can keep it whole")
            XCTAssertTrue(reason.hasSuffix(LfStr.missingTarget(Self.gone)),
                          "\(language.rawValue): the reason lost its own words: \(reason)")
            XCTAssertNotEqual(reason, LfStr.missingTarget(Self.gone),
                              "\(language.rawValue): the separator was left on the path, where "
                              + "the truncation eats it: \(reason)")
        }
    }

    /// And a row with nothing wrong with it is a path and nothing else.
    func testARowWithNothingWrongWithItHasNoSecondPart() throws {
        let detail = try XCTUnwrap(LfStr.detail(for: item(missingTarget: nil)))

        XCTAssertEqual(detail.path, Self.longPath)
        XCTAssertNil(detail.reason)
    }

    // MARK: - What the row actually draws

    /// **Measured, because this is a claim about a drawing — and measured at the
    /// end of the clause, which is the part that was never there.**
    ///
    /// Two renders of one row, differing in nothing but *which* file the job points
    /// at: a short target and a long one. If the clause reaches the screen, the two
    /// are different pictures. If it is cut away, they are the same picture — the
    /// visible text ends inside the path in both, and what the row says about the
    /// missing program is the same nothing either way.
    ///
    /// The two rows are identical up to the **end** of the clause, and the path in
    /// front of it is longer than the column at either width — so with the line cut
    /// at the tail the cut falls inside the path and the two are the same picture,
    /// to the byte. That is what the shipped line drew: **0.00 %**, six readings out
    /// of six. Any difference at all is the clause reaching the screen.
    func testTheClauseReachesTheScreenAtBothPaneWidths() async throws {
        for width in [CGFloat(606), 845] {
            for language in [AppLanguage.en, .ru, .de] {
                let short = try await detailInk(missingTarget: "/opt/x", language: language,
                                                width: width)
                let long = try await detailInk(missingTarget: Self.gone, language: language,
                                               width: width)
                XCTAssertGreaterThan(short, 0, "precondition: the detail line drew at all")

                let moved = Double(abs(long - short)) / Double(short)
                XCTAssertGreaterThan(moved, 0.001, """
                    \(language.rawValue) at \(Int(width)) pt: a row pointing at \(Self.gone) and \
                    a row pointing at /opt/x are drawn \(String(format: "%.3f", moved * 100)) % \
                    apart — the same picture. What the clause names is not on the screen: the \
                    path has taken the width and «points at a missing file» is truncated away.
                    """)
            }
        }
    }

    /// The ink of the first row's detail line, in the page's own drawing.
    ///
    /// Light only, and deliberately: this is a comparison of two renders in one
    /// appearance, and `RenderedInk` measures a departure from the band's own
    /// background — which is what makes the two readings comparable at all.
    private func detailInk(missingTarget: String?, language: AppLanguage,
                           width: CGFloat) async throws -> Int {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        let (mount, _) = await LeftoversPageRender.page([item(missingTarget: missingTarget)],
                                                        language: language, width: width,
                                                        appearance: .aqua)
        defer { mount.drop() }
        // The first row's second line, in points from the top of the page: the
        // toolbar, the note about nothing being ticked, the section header and the
        // row's own name are all above it.
        return try XCTUnwrap(mount.ink(138...152), "the detail line's band was not drawn")
    }
}
