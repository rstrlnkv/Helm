import XCTest
import AppKit
import SwiftUI
import Foundation
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **A threshold is a claim about a layout, and `HomebrewSplitTests` pins the
/// number rather than the claim.**
///
/// Those four cases assert `HomebrewSplit(490/543/560/834).showsInspector`
/// against literal widths: a mutation of the constant goes red, and a constant
/// that is *wrong about the page* does not. The measurement that chose 560 —
/// 544 pt, "the master still crawling into the gutter at 543" — was taken on a
/// probe of two bare rectangles and a `Divider()`, and it is not in the tree;
/// nothing re-takes it, so the day `pkgRow` grows, the inspector's button gets a
/// longer word, or SwiftUI changes how it splits a shortfall between two ranged
/// children, 560 becomes a number with nothing behind it and no test notices.
///
/// So this asks the real page. It finds the threshold by asking `HomebrewSplit`
/// itself (the constant is private, and reading it twice would be an assertion
/// against its own declaration), mounts `HomebrewSettingsPage` there with a
/// package selected, and reads where the two columns actually land.
///
/// **What it measures, as measured on 2026-09-14, three consecutive runs.** The
/// master column is a `List` inset 12 pt inside its own frame; the inspector's
/// action is the page's only `_FocusRingView` while a package is selected — the
/// segmented picker and the borderless Refresh draw none. At the threshold the
/// button ends at x = 548 in a 560 pt pane. Below the real floor it does not:
/// with the threshold substituted for 460 the same button is drawn at
/// 437.5…513.0 in a 460 pt pane — 53 pt past the edge, clipped, in a page that
/// reports nothing wrong.
///
/// **And the floor of the shipping page is 521, not 544.** Swept one point at a
/// time with the threshold substituted low, the action first fits inside the
/// pane at 521 pt (520 draws it to 520.5) — which is the arithmetic floor
/// 240 + 12 + 1 + 12 + 260 = 525 rounded down by the button's own trailing
/// padding, not the 544 the doc comment records. 544 was measured on the probe
/// shape, whose master carried `idealWidth: 310, maxWidth: 310` with no content
/// of its own; the real master is a `List` that compresses, and the column that
/// gets squeezed first is the *inspector*, not the master. So 560 sits 39 pt
/// above the floor rather than 16.
@MainActor
final class TheSplitThresholdFitsThePageItGatesTests: XCTestCase {

    /// Answers the list query and nothing else; the page needs a Cellar to draw
    /// rows from and a status saying brew is here, and no more than that.
    private final class TwoPackages: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        static let wget = BrewPackage(name: "wget", version: "1.25.0", isCask: false)
        static let openssl = BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false)

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode([Self.wget, Self.openssl])
            case .descriptions:
                return try JSONEncoder().encode(["wget": "retrieve files from the web"])
            default:
                return Data()
            }
        }
    }

    /// The narrowest width `HomebrewSplit` answers `true` for, asked of the type
    /// rather than read off its private constant.
    ///
    /// A sweep and not a bisection on purpose: a bisection assumes the answer is
    /// monotone, which is the property being taken on trust everywhere else here.
    private var threshold: CGFloat {
        var found: CGFloat?
        for width in stride(from: CGFloat(200), through: 1200, by: 1) {
            let shows = HomebrewSplit(availableWidth: width).showsInspector
            if shows, found == nil { found = width }
            // Monotone: once it shows, it must keep showing.
            if let found, width > found { XCTAssertTrue(shows, "the split is not monotone in width") }
        }
        return found ?? 0
    }

    private struct Reading {
        let rings: [CGRect]
        let lists: [CGRect]
    }

    private func draw(at width: CGFloat, selecting id: String?) async -> Reading {
        let transport = TwoPackages()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        hb.select(id)
        // Light, named: `RenderedInk`'s reason — an unnamed appearance is a
        // reading of whatever this Mac is set to at this hour. Geometry is not
        // ink, but a control's metrics are not guaranteed to be either.
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 700, appearance: .aqua)
        mount.settle(30)
        // **Below the segment bar.** The inspector's action was "the page's only
        // focus ring" while the bar drew a segmented control, which draws none —
        // and the bar draws a *menu* wherever the segments do not fit the pane,
        // which at this very threshold is what several languages get. That
        // picker carries a ring of its own, so an unbanded count reads two
        // controls where the claim is about one. 48 pt is the bar and its
        // divider: `HelmSpace.s5` of padding around a 24 pt control.
        let belowTheBar: CGFloat = 48
        let rings = mount.host.everyView(named: "_FocusRingView")
            .map { $0.convert($0.bounds, to: mount.host) }
            .filter { $0.minY >= belowTheBar }
        let lists = mount.host.everyView
            .filter { $0.appKitClassName.contains("ListCoreScrollView") }
            .map { $0.convert($0.bounds, to: mount.host) }
        mount.drop()
        withExtendedLifetime(transport) {}
        return Reading(rings: rings, lists: lists)
    }

    /// **The pane at the threshold holds everything the split branch draws.**
    ///
    /// The subject is asserted before the absence: the button has to be in the
    /// tree at all, or "nothing is outside the pane" is true of a page that drew
    /// nothing.
    ///
    /// **Asked in English, named rather than inherited.** The page's shape is
    /// one boundary now — `headerBar` folds this file's threshold into the
    /// segmented bar's own ideal width, so the columns appear exactly where the
    /// switcher fits — and that width is a fact about the language's strings:
    /// swept 2026-09-16, ru needs 566 pt and ja 572 against `HomebrewSplit`'s
    /// own 560. This Mac runs in Russian, so a bare mount at 560 draws the
    /// one-column page and nothing here would be measuring the split at all.
    /// English is the language whose bar fits under every reachable pane, which
    /// makes 560 this file's subject again; `ThePageReorganisesOnceTests` is
    /// what checks the boundary in all eight.
    func testTheInspectorsActionIsInsideThePaneAtTheThreshold() async {
        await AppLanguage.only(.en) { await theInspectorsActionIsInsideThePane() }
    }

    private func theInspectorsActionIsInsideThePane() async {
        let width = threshold
        XCTAssertGreaterThan(width, 0, "no width in 200…1200 shows the inspector")

        let quiet = await draw(at: width, selecting: nil)
        XCTAssertEqual(quiet.rings.count, 0, """
            \(quiet.rings.count) control(s) on the page with nothing selected, where the \
            inspector's action is the only one — the reading below cannot tell that action \
            from whatever else has grown a focus ring
            """)

        let picked = await draw(at: width, selecting: TwoPackages.wget.id)
        XCTAssertEqual(picked.rings.count, 1, """
            selecting a package added \(picked.rings.count) control(s) at \(width) pt, where the \
            inspector offers exactly one action — nothing below is a measurement of the button
            """)
        guard let button = picked.rings.first else { return }
        XCTAssertLessThanOrEqual(button.maxX, width, """
            the inspector's action is drawn to x = \(button.maxX) in a \(width) pt pane — past \
            the edge, so it is clipped on the very width `HomebrewSplit` chose as wide enough \
            for two columns. The threshold is a claim about this layout and the layout has \
            moved under it.
            """)
        XCTAssertGreaterThanOrEqual(button.minX, 0,
                                    "the inspector's action begins at x = \(button.minX)")

        guard let list = picked.lists.first else {
            return XCTFail("no master list drew at \(width) pt, so no column was measured")
        }
        XCTAssertGreaterThanOrEqual(list.minX, 0, """
            the master column begins at x = \(list.minX) in a \(width) pt pane: it has crawled \
            into the gutter, which is the failure the 544 pt measurement was taken against
            """)
        XCTAssertLessThan(list.maxX, button.minX, """
            the master list runs to x = \(list.maxX) and the inspector's action begins at \
            x = \(button.minX) — the two columns overlap
            """)
    }

    /// **And one point below it the other branch really is the one drawing.**
    ///
    /// A threshold that gates nothing would pass the test above at every width.
    /// Below it and with nothing selected there is one column, so the list runs
    /// to the pane's own trailing edge rather than stopping at a 310 pt master.
    ///
    /// **It read `width - 12` until 2026-09-16**, and the 12 was this page's own
    /// extra `.padding(.horizontal, HelmSpace.s5)` on top of `.listStyle(.inset)`
    /// — an inset no other list in the app had, which put these rows 28 pt from
    /// the pane where every other list screen's sit at 16. The list is flush with
    /// its pane now, and the reading discriminates exactly as it did: above the
    /// threshold the master stops at `HomebrewSplit.masterWidth`, which is
    /// nowhere near the pane's edge.
    ///
    /// **Nothing selected, unlike the test above.** Below the threshold a
    /// selection now replaces the list with the package screen rather than
    /// sitting beside it — that shape is `TheNarrowPaneCanStillActOnAPackage-
    /// Tests`' subject — so the list is the pane's one column only while there
    /// is nothing to select into, which is what this test is actually about.
    ///
    /// **Asked in English, named rather than inherited.** The page's shape is
    /// one boundary now — `headerBar` folds this file's threshold into the
    /// segmented bar's own ideal width, so the columns appear exactly where the
    /// switcher fits — and that width is a fact about the language's strings:
    /// swept 2026-09-16, ru needs 566 pt and ja 572 against `HomebrewSplit`'s
    /// own 560. This Mac runs in Russian, so a bare mount at 560 draws the
    /// one-column page and nothing here would be measuring the split at all.
    /// English is the language whose bar fits under every reachable pane, which
    /// makes 560 this file's subject again; `ThePageReorganisesOnceTests` is
    /// what checks the boundary in all eight.
    func testOnePointBelowTheThresholdOneColumnFillsThePane() async {
        await AppLanguage.only(.en) { await onePointBelowTheThresholdOneColumnFillsThePane() }
    }

    private func onePointBelowTheThresholdOneColumnFillsThePane() async {
        let width = threshold - 1
        let picked = await draw(at: width, selecting: nil)
        guard let list = picked.lists.first else {
            return XCTFail("no list drew at \(width) pt, so no column was measured")
        }
        XCTAssertEqual(list.maxX, width, accuracy: 1, """
            at \(width) pt the list runs to x = \(list.maxX) where a single column flush with \
            its pane ends at \(width) — the split branch is still the one drawing below its own \
            threshold, or the list has taken an inset of its own again and the reading above is \
            measuring something else
            """)
    }
}
