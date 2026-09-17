import XCTest
import HelmTestSupport

/// **A style chosen for the toolbar has to give the page a new identity, not
/// just a new environment value.**
///
/// A page's controls are bridged into the window's own AppKit toolbar. An
/// environment change alone does not republish them: measured on the dev build
/// 2026-09-17, choosing another `ToolbarSwitcherStyle` — and, before it, another
/// `PageBarStyle` — left the bar exactly as it was until the page was left and
/// opened again. Both trackers key the subtree on the style, and photographs of
/// the same flip afterwards show the bar following it.
///
/// Read off the construction: the bridge needs a window with a toolbar, which a
/// page mounted in a hosting view does not have, so nothing offscreen can see
/// this. What a test can hold is that neither tracker loses the `id` again.
final class AStyleChosenInTheBarReachesTheBarTests: XCTestCase {

    private func trackerBody(_ name: String, in file: String) throws -> String {
        let code = SwiftSource.code(try RepoSource.text(of: file))
        let start = try XCTUnwrap(code.range(of: "struct \(name)"), "\(file) no longer declares \(name)")
        let end = code.range(of: "\nstruct ", range: start.upperBound..<code.endIndex)?.lowerBound
            ?? code.endIndex
        return String(code[start.lowerBound..<end])
    }

    /// **The switcher's own tracker must not.** Its control is one `NSView` that
    /// lives across the change and rewrites its segments from the environment,
    /// so a new identity only throws that view away: measured 2026-09-18, the
    /// bar's items jumped as the style was chosen, and the style reaches them
    /// without it.
    func testTheSwitcherStyleTrackerKeepsItsSubtree() throws {
        let body = try trackerBody("SwitcherStyleTracker",
                                   in: "Sources/HelmUI/DesignSystem/HelmToolbarSwitcher.swift")
        XCTAssertFalse(body.contains(".id(style"), """
            the switcher-style tracker gives its subtree a new identity on every style, which \
            throws away the control the toolbar is holding and makes the bar's items jump
            """)
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
