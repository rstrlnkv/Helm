import AppKit
import HelmTestSupport
import SwiftUI
import XCTest

/// The app's heading is one weight, and `.headline` is the other one.
///
/// `HelmText.sectionHeading` is `.body.weight(.semibold)`; `.headline` on macOS
/// is **bold** at the same size. The declaration of that token already says so
/// — «mapping `sectionHeading` onto it would have weighted every heading in the
/// app a step heavier with the size unchanged — which no test could have
/// caught, because the size is what a layout measures». That was a promise
/// written in prose with nothing under it, and nine headings across four
/// modules were already drawing `.headline` beside eleven drawing the token.
///
/// **The type-scale ratchets cannot see this and never could.** Both of them
/// judge a *size*: one counts hand-typed points off the ladder, the other counts
/// styles macOS resolves to a size the ladder does not have. `.headline` is 13,
/// which is on the ladder, so it passes both — the difference is entirely in the
/// weight, which is why it needs a check of its own rather than another entry in
/// a table over there.
///
/// The floor is 0. `HelmText.sectionHeading` is the heading over a card, and
/// there is no site in this app where a heavier one has been argued for; if one
/// ever is, it is a token in `HelmText` and not a style typed at a call site.
final class AHeadingIsOneWeightTests: XCTestCase {

    /// The style, and the token that replaces it.
    private static let banned = #"\.font\(\.headline\b"#

    func testNoHeadingIsSetInAWeightTheAppDoesNotUse() throws {
        let sites = try UISources.sites(matching: [Self.banned: 13],
                                        in: UISources.everyDrawnFile())
        XCTAssertEqual(sites.count, 0, """
            \(sites.count) headings are set in `.headline`, which macOS draws bold at 13 \
            where this app's heading is semibold at 13. The two are the same size, so \
            nothing that measures a layout will ever tell you they differ.
            Use `HelmText.sectionHeading`.
            \(UISources.summary(sites))
            """)
    }

    /// **The two really are one size and two weights**, measured off `NSFont`
    /// rather than remembered — the same discipline the style ratchet applies to
    /// what macOS resolves a name to. Without this the rule above could be a
    /// rule about nothing on a macOS that had made them identical.
    func testTheTwoFacesAreOneSizeAndTwoWeights() {
        let headline = NSFont.preferredFont(forTextStyle: .headline)
        let body = NSFont.preferredFont(forTextStyle: .body)
        XCTAssertEqual(headline.pointSize, body.pointSize, accuracy: 0.01,
                       "`.headline` is no longer the size of `.body`; the rule above is "
                       + "about a size difference now and has to be re-argued")
        XCTAssertNotEqual(headline.fontName, body.fontName, """
            `.headline` and `.body` now resolve to the same face, so swapping one for \
            the other changes nothing and this rule is guarding nothing
            """)
    }

    /// The scan reads the whole app, not the two files somebody edited.
    func testTheScanStillReadsTheApp() throws {
        XCTAssertGreaterThan(try UISources.everyDrawnFile().count, 50,
                             "the file list has collapsed; this check is idle")
        // A style the app really does use, so the walk is proven to see one.
        let alive = try UISources.sites(matching: [#"HelmText\.sectionHeading"#: 13],
                                        in: UISources.everyDrawnFile())
        XCTAssertGreaterThan(alive.count, 10, """
            the scan finds \(alive.count) uses of the heading token in the whole app; \
            either the tree has lost them or the walk is not reading files
            """)
    }
}
