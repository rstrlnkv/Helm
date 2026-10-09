import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Draws one switcher in a page bar and throws it away before a reserve family takes its readings.**
///
/// Why it exists: in the reserve families (`ASegmentedEntrysReserveIsWhatItDrawsTests` and its two
/// neighbours) a switcher was once read at 24 pt high and 48 pt wide for `minus` / `ellipsis` in whichever
/// test ran first in its process, against 36 pt and 80 pt in the tests after it. That order effect was seen
/// in family runs and was not reproduced by `TheFirstGlassSwitcherIsDrawnAtTheBarsSizeTests`, which never
/// calls this helper: what that family measured before `HelmToolbarSwitcher` wore one cell under both looks and wrote the bar's size on every
/// pass was a switcher at the regular size (24 pt) at every mount of the tabs, and an action at 36 pt only
/// until its window turned key (24 pt after a settle) — not a first-of-process effect. That family is
/// green with the switcher as it is now, and no row has been run with this call and without it, so nothing
/// measured says what this call still guards; it draws one switcher and the readings after it are the ones
/// the families assert on.
///
/// A reading calls `assertDrawnAtTheBarsSize` as well: a switcher drawn at the regular size would leave a
/// reserve that is too wide looking as if it "covers" what is drawn.
@MainActor
enum TheGlassSwitcherWarmUp {
    private static var done = false

    /// Draws a segmented control once per process. Settings are the caller's to pin and put back; this
    /// sets the bar's look to glass and leaves it so.
    static func run() {
        guard !done else { return }
        done = true
        AppSettings.barAppearance = .liquidGlass
        let token = "test.glassWarmUp"
        let fx = LivePageToolbarFixture(Color.clear, selection: .module(token), width: 1060, height: 700)
        defer { fx.drop() }
        fx.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "viewMode", title: "View", options: [
                HelmToolbarTab(id: "first", title: "First", symbol: "minus"),
                HelmToolbarTab(id: "second", title: "Second", symbol: "ellipsis"),
            ], selection: .constant("first")),
        ]), token: token, generation: fx.channel.nextGeneration())
        fx.settle(10)
    }

    /// Fails when a drawn switcher is not as high as the capsule's own side, the bar's size.
    static func assertDrawnAtTheBarsSize(_ control: NSSegmentedControl, _ context: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(control.frame.height, HelmToolbarActionsCapsule.side, """
            \(context): precondition — the switcher was drawn \(control.frame.height) pt high, not at the bar's size
            """, file: file, line: line)
    }
}
