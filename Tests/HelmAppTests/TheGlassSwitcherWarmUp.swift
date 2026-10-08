import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Draws one Liquid Glass switcher in a page bar and throws it away, so that the next one a process
/// draws is the one a reading is about.**
///
/// Seen in the reserve families (`ASegmentedEntrysReserveIsWhatItDrawsTests` and its two neighbours), by
/// the order the tests ran in and not by an isolated run: in whichever test was the first of its process to
/// put a glass-look switcher in a page bar, that switcher was 24 pt high and 48 pt wide for `minus` /
/// `ellipsis`, and stayed so through later layout turns and through the page re-declaring its options,
/// while the reserve beside it, measured on a switcher mounted alone, said 80 pt; in every later test it
/// was 36 pt high and 80 pt wide. 24 pt is AppKit's regular control size and 36 pt the one
/// `HelmToolbarSwitcher.updateNSView` pins (`.extraLarge`). Why the first one keeps the regular size was
/// not established: the reserve's own measuring switcher is made before it in the same process and
/// answers the wide figure, and the comment in `updateNSView` is about a control AppKit's toolbar
/// promotes, which this bar has none of. That the readings after this call agree is all it is known to
/// do. Which test of a family is that first one depends on the order the runner picks, so a reading of
/// the glass look without this call reads a different state on one run than on the next.
///
/// A reading calls `assertDrawnAtTheBarsSize` as well: a warm-up that stopped working would leave the
/// first reading at the regular size, where a reserve that is too wide still "covers" what is drawn.
@MainActor
enum TheGlassSwitcherWarmUp {
    private static var done = false

    /// Draws the glass look's segmented control once per process. Settings are the caller's to pin and
    /// put back; this sets the bar's look to glass and leaves it so.
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

    /// Fails when a drawn switcher is not as high as the capsule's own side, the size every control after the
    /// first is drawn at in both looks.
    static func assertDrawnAtTheBarsSize(_ control: NSSegmentedControl, _ context: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(control.frame.height, HelmToolbarActionsCapsule.side, """
            \(context): precondition — the switcher was drawn \(control.frame.height) pt high, not at the bar's size
            """, file: file, line: line)
    }
}
