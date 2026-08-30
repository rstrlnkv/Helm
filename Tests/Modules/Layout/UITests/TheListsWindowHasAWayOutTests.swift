import XCTest
import HelmTestSupport

/// **A window with no keyboard exit, in an app with no menu bar.**
///
/// `LayoutLists` is presented by `HostWindow` with `[.titled, .closable,
/// .resizable]`, and `HostWindow` supplies no Escape handling of its own — that
/// is the content's job, which is why `TrashedLeftoversView`, the other
/// `HostWindow` in the app, carries `.keyboardShortcut(.cancelAction)` on its
/// footer button. This window carried nothing.
///
/// That is unreachable rather than merely awkward. Helm builds no `NSMenu`
/// anywhere — `grep -rn "NSMenu()\\|mainMenu" Sources/HelmApp` is empty — so ⌘W
/// is bound to nothing, and macOS's default Full Keyboard Access («Text boxes
/// and lists only») leaves the traffic lights out of the Tab order. A
/// keyboard-only reader on default settings had no way to close it short of
/// leaving Helm.
///
/// A source scan, because the defect is in what the view *does not* declare,
/// and an offscreen render exposes no accessibility tree to ask.
final class TheListsWindowHasAWayOutTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        SwiftSource.uncommented(
            try String(contentsOf: RepoSource.root.appendingPathComponent(path), encoding: .utf8))
    }

    func testTheListsCarryTheirOwnEscape() throws {
        let text = try source("Sources/Modules/Layout/UI/LayoutLists.swift")
        XCTAssertTrue(text.contains(".keyboardShortcut(.cancelAction)"),
                      "LayoutLists has no Escape binding, and nothing else in the app gives it "
                      + "one — no NSMenu means ⌘W is bound to nothing")
        XCTAssertTrue(text.contains("close()"),
                      "the Escape binding reaches no action that closes the window")
    }

    /// The premise, asserted rather than assumed: the day Helm grows a menu bar
    /// this test's reasoning changes, and it should say so out loud rather than
    /// keep guarding a hazard that has gone.
    func testTheAppStillHasNoMenuBarToBindCommandWTo() throws {
        let app = try RepoSource.swiftFiles(under: "Sources/HelmApp")
        XCTAssertGreaterThan(app.count, 10, "the scan found \(app.count) files in HelmApp")
        for path in app {
            let text = try source(path)
            XCTAssertFalse(text.contains("NSMenu()") || text.contains("mainMenu ="),
                           "\(path) builds a menu — Helm has a menu bar now, so ⌘W may close "
                           + "windows on its own and this guard's reasoning needs re-reading")
        }
    }
}
