import AppKit
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Leftovers_UI

/// **The floor is an AppKit measurement of a line SwiftUI draws, and the two have
/// to be the same face.**
///
/// `LeftoverPathFloor.width` asks `NSString.size(withAttributes:)` with
/// `HelmText.rowDetailNSFont`; the line it is holding up is a `Text` with
/// `.font(HelmText.rowDetail)` (`LeftoversSettingsPage.row`). Those are two
/// spellings — `NSFont.preferredFont(forTextStyle: .subheadline)` and
/// `Font.subheadline` — of what has to be one font, and they became two spellings
/// on 2026-08-20, when the type scale went from `.system(size: 11)` to named
/// styles. Before that the mismatch was a number against a `Font`; now it is a
/// text style against a text style, which is closer and still not the same
/// object.
///
/// If AppKit measures narrower than SwiftUI draws, the floor sits *under* the
/// thing it holds up: `ViewThatFits` takes the arrangement whose ideal width is
/// the floor, the `Text` is then given less room than its own last component
/// needs, and the path truncates to a glyph again — the defect
/// `AnUnreadablePathIsNotDrawnTests` was written for, back through a measurement
/// that says it is fine.
///
/// So the reading is taken off a real render rather than off a second copy of the
/// arithmetic, and the inputs are the ones a Mac really has in it: a vendor's
/// reverse-DNS name, a name in Cyrillic, one with a space, one with an emoji in
/// it — the last because emoji do not come from the system face at all, and a
/// measurement taken with one font of a string drawn in two is the shape this
/// file exists to check.
@MainActor
final class TheFloorIsTheFaceThatDrawsItTests: XCTestCase {

    /// Last components of paths, each in `~/Library/LaunchAgents`.
    private let names = [
        "com.adobe.ccxprocess.plist",
        "ru.яндекс.помощник.plist",
        "com.vendor.Some Helper.plist",
        "com.vendor.🙂.plist",
        "com.vendor.tab\tname.plist",
        "x.plist",
    ]

    /// What SwiftUI actually lays the line out as, at the page's own detail font.
    ///
    /// `fittingSize` of a hosting view holding one `Text` is the width the layout
    /// would give it — the same quantity `ViewThatFits` compares against, and the
    /// only one that answers for the face SwiftUI resolves rather than the one a
    /// test names.
    private func drawnWidth(_ string: String) -> CGFloat {
        let host = NSHostingView(rootView: Text(string).font(HelmText.rowDetail).fixedSize())
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.width
    }

    /// **The claim.** The floor is at least as wide as the line it is holding up.
    ///
    /// One-sided on purpose: a floor wider than the drawing costs a few points of
    /// room, and a floor narrower than it re-admits the defect. Rounded up at the
    /// source, so equality is the expected answer and no tolerance is invented
    /// here to hide a difference.
    func testTheFloorIsNeverNarrowerThanWhatSwiftUIDraws() {
        for name in names {
            let path = "/Users/x/Library/LaunchAgents/\(name)"
            let floor = LeftoverPathFloor.width(of: path)
            let drawn = drawnWidth("…\(name)")

            XCTAssertGreaterThan(drawn, 0, "precondition: \(name) was drawn at all")
            XCTAssertGreaterThanOrEqual(floor, drawn, """
                «…\(name)» is drawn \(drawn) pt wide and the floor under it is \
                \(floor) pt. The floor is measured with \
                `HelmText.rowDetailNSFont` and the line is drawn with \
                `HelmText.rowDetail`; where the two disagree, `ViewThatFits` \
                takes an arrangement that cannot show the file's own name and the \
                path truncates to a glyph — with the arithmetic saying it fits.
                """)
        }
    }

    /// And the two faces are the same face, said directly, so a failure above can
    /// be read as «these fonts differ» rather than as «this string measured odd».
    ///
    /// Measured rather than compared as objects: `Font` is opaque and answers no
    /// questions, which is why the guard above is a render.
    func testTheDetailFontMeasuresTheSameOnBothSides() {
        let sample = "…com.adobe.ccxprocess.plist"
        let appKit = ControlMetrics.label(sample, font: HelmText.rowDetailNSFont)
        let swiftUI = drawnWidth(sample)

        XCTAssertGreaterThan(appKit, 0, "precondition: the AppKit side measured something")
        XCTAssertEqual(appKit, swiftUI, accuracy: 1, """
            The one place in this app that measures text rather than drawing it \
            reads \(appKit) pt where SwiftUI draws \(swiftUI) pt. \
            `HelmText.rowDetailNSFont` exists to be `rowDetail` as AppKit sees \
            it, and a point of drift here is the floor of `LeftoverPathFloor` \
            sitting under the line it holds up.
            """)
    }
}
