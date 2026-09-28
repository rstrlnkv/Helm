import XCTest
import HelmTestSupport

/// **A page-bar style chosen for the toolbar has to give the page a new
/// identity, not just a new environment value.**
///
/// Measured on the dev build by 2026-09-17, while a page's controls were
/// bridged into the window's own AppKit toolbar: an environment change alone
/// did not republish them, and choosing another `PageBarStyle` left the bar
/// exactly as it was until the page was left and opened again. The tracker
/// keys the subtree on the style, and photographs of the same flip afterwards
/// showed the bar following it.
///
/// Read off the construction: the bridge needed a window with a toolbar, which
/// a page mounted in a hosting view does not have, so nothing offscreen can
/// see this. What a test can hold is that the tracker does not lose the `id`
/// again. The switcher style had a tracker of its own under the pane, held
/// here to the opposite; it went on 2026-09-28, when nothing under the pane
/// read the value any more — every switcher is built in the toolbar's own
/// hosting views and handed its style there.
final class AStyleChosenInTheBarReachesTheBarTests: XCTestCase {

    private func trackerBody(_ name: String, in file: String) throws -> String {
        let code = SwiftSource.code(try RepoSource.text(of: file))
        let start = try XCTUnwrap(code.range(of: "struct \(name)"), "\(file) no longer declares \(name)")
        let end = code.range(of: "\nstruct ", range: start.upperBound..<code.endIndex)?.lowerBound
            ?? code.endIndex
        return String(code[start.lowerBound..<end])
    }

    func testThePageBarStyleTrackerKeysItsSubtreeOnTheStyle() throws {
        let body = try trackerBody("HelmPageBarStyleTracker",
                                   in: "Sources/HelmUI/DesignSystem/PageBarStyle.swift")
        XCTAssertTrue(body.contains(".id(style ?? current())"), """
            the page-bar tracker hands the subtree a value and not an identity, so the header shape \
            chosen in Settings does not reach the window's toolbar until the page is reopened
            """)
    }
}
