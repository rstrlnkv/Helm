import AppKit
import HelmContract
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI

/// **Hosts' tabs unfold across their fold point once, with nothing swapped on the way.** Hosts' own
/// declaration on its SSH tab — the same two tabs, the same two-option view switcher with its glyphs, `+`
/// declared and hidden — is mounted in the page bar the Settings window holds, and the bar is widened and
/// narrowed a point at a time through its fold point in Russian and
/// German, in the words-only label style.
///
/// The bar folds the tabs by `ShellBarLayout`'s verdict over the widths the zones measured, in the layout
/// pass itself; there is no trial that a toolbar can refuse, so what a blink would look like here is a fold
/// state that flips back and forth across the point, a tabs view that is replaced on the way, or a control
/// that draws the other form than the verdict says. Per language and direction the sweep asserts: folded at
/// one end and whole at the other (the sweep crosses a fold point at all), exactly one change of the fold
/// state along the way, the same tabs view at every width, and the strip drawn as one segment while
/// folded and two while whole. The ascending and the descending sweep change state at the same width.
/// `TheBarsTabsFoldByTheLayoutsVerdictTests` holds the verdict against the layout for a synthetic page at a
/// seven-point step; this is Hosts' real content at a one-point step.
///
/// The actions zone's reserve being a whole point is held in `TheBarsActionsKeepTheirReserveTests`.
@MainActor
final class HostsTabsUnfoldWithoutABlinkTests: XCTestCase {

    private struct Step {
        let width: CGFloat
        let folded: Bool
        let segments: Int
        let view: ObjectIdentifier?
    }

    private func hostsOnSSH() -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "keys", title: HostsStr.keysTab, symbol: "key"),
                   HelmToolbarTab(id: "ssh", title: HostsStr.sshHostsTab, symbol: "server.rack")],
            selectedTab: .constant("ssh"),
            actions: [
                HelmToolbarAction(id: "viewMode", title: HostsStr.viewGroup, isVisible: true, options: [
                    HelmToolbarTab(id: "table", title: HostsStr.tableView, symbol: "tablecells"),
                    HelmToolbarTab(id: "text", title: HostsStr.textView, symbol: "text.alignleft"),
                ], selection: .constant("table")),
                HelmToolbarAction(id: "newKey", title: HostsStr.newKey, symbol: "plus", isVisible: false) {},
            ])
    }

    private func sweep(_ fx: LivePageToolbarFixture, _ widths: [CGFloat]) -> [Step] {
        widths.map { width in
            fx.bar.view.place = ShellPageBarView.Place(cardMinX: 0, windowWidth: width, buttons: .null)
            fx.bar.view.frame = NSRect(x: 0, y: 0, width: width, height: ShellBarLayout.height)
            fx.bar.view.layoutSubtreeIfNeeded()
            let strip = fx.bar.view.view(for: .tabs)?.everyView(ofType: NSSegmentedControl.self).first
            return Step(width: width, folded: fx.pageBar.tabs.isFolded, segments: strip?.segmentCount ?? -1,
                        view: fx.bar.view.view(for: .tabs).map(ObjectIdentifier.init))
        }
    }

    /// The widths at which the fold state differs from the step before.
    private func changes(_ steps: [Step]) -> [CGFloat] {
        zip(steps, steps.dropFirst()).filter { $0.folded != $1.folded }.map { $1.width }
    }

    func testHostsTabsUnfoldAcrossTheirFoldPointWithoutABlink() {
        PinnedBarSettings.pin(in: self)
        let up = Array(stride(from: CGFloat(300), through: 1100, by: 1))
        for language: AppLanguage in [.ru, .de] {
            AppLanguage.only(language) {
                let fx = LivePageToolbarFixture(EmptyView(), selection: .module("test.hostsBlink"),
                                                width: 1060, height: 700)
                defer { fx.drop() }
                fx.channel.declare(hostsOnSSH(), token: "test.hostsBlink", generation: fx.channel.nextGeneration())
                fx.settle(10)
                XCTAssertEqual(fx.bar.presentation, .page(key: "test.hostsBlink", isLive: true, isDimmed: false),
                               "\(language) precondition: the bar does not show the declared page live")

                let ascending = sweep(fx, up)
                let descending = sweep(fx, up.reversed()).reversed() as [Step]
                for (direction, steps) in [("ascending", ascending), ("descending", descending)] {
                    XCTAssertEqual(steps.first?.folded, true, """
                        \(language) \(direction) precondition: Hosts' tabs are not folded at \(up.first ?? 0) pt, \
                        so a sweep upward from there crosses no fold point
                        """)
                    XCTAssertEqual(steps.last?.folded, false, """
                        \(language) \(direction) precondition: Hosts' tabs are still folded at \(up.last ?? 0) pt
                        """)
                    XCTAssertEqual(changes(steps).count, 1, """
                        \(language) \(direction): the fold state changed at \(changes(steps)) pt — the tabs blink \
                        before they stay
                        """)
                    XCTAssertEqual(Set(steps.map(\.view)).count, 1, """
                        \(language) \(direction): the tabs view was replaced on the way — \(Set(steps.map(\.view)).count) \
                        different views over the sweep
                        """)
                    XCTAssertNotNil(steps.first?.view, "\(language) \(direction) precondition: the bar held no tabs view")
                    let wrong = steps.filter { $0.segments != ($0.folded ? 1 : 2) }.map(\.width)
                    XCTAssertTrue(wrong.isEmpty, """
                        \(language) \(direction): the strip draws the other form than the fold says at \(wrong) pt
                        """)
                }
                XCTAssertEqual(changes(ascending), changes(descending), """
                    \(language): the tabs unfold at \(changes(ascending)) widening and fold at \(changes(descending)) \
                    narrowing
                    """)
            }
        }
    }
}
