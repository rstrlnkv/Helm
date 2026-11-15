import AppKit
import SwiftUI
import HelmTestSupport
import HelmUI
import XCTest
@testable import HelmApp

/// **The Flat settle's room is the window's, not the plate's own.** `SettingsToolbar.settleFlat` must read the bar's
/// right end from the card's edge, `pane.leading + pane.width`, never from the plate's own trailing edge. Before
/// this fix it came from the plate's edge, which AppKit moves when the plate's width is set, so the plan moved the
/// room it was planned from and a shown window looped (before this fix, AX-frame widths 248, 84, 285, 275, 41 at a held
/// 1060, CPU 31 to 52 %).
/// Here one fixed window is reached from different starting widths (`widths(from:to:)`), and the width the settle
/// then plans must be the same from each start.
@MainActor
final class AFlatSearchRoomDoesNotFollowItsOwnPlateTests: XCTestCase {

    /// Builds the bar at `from`, lets it settle, resizes the window to `to` and returns the plate's width at every
    /// turn afterwards. Only the route differs between two calls with the same `to`.
    private func widths(from: CGFloat, to: CGFloat) throws -> [CGFloat] {
        PinnedBarSettings.pin(in: self, look: .flat)
        let fixture = LivePageInTheToolbarFixture(
            Text("the list").frame(maxWidth: .infinity, maxHeight: .infinity)
                .helmWindowToolbar(HelmPageToolbarContent(
                    tabs: ["Installed", "Outdated", "Search", "Taps"].map {
                        HelmToolbarTab(id: $0, title: $0, symbol: "shippingbox")
                    },
                    selectedTab: .constant("Installed"),
                    search: HelmToolbarSearch(
                    prompt: "Search", text: .constant(""), onSubmit: {})), token: "test.flatRoom"),
            selection: .module("test.flatRoom"), width: from, height: 400)
        defer { fixture.drop() }
        let window = try XCTUnwrap(fixture.mount.window)
        fixture.toolbar.paneMoved(leading: 56, width: from - 56)   // the settle reads no room without a pane told
        fixture.settle(40)
        let items = try XCTUnwrap(window.toolbar?.items)
        let plate = try XCTUnwrap(items.first { $0.itemIdentifier.rawValue == "helm.search" }?.view as? ShellBarPlate)
        let constraint = try XCTUnwrap(plate.constraints.first { $0.firstAttribute == .width && $0.secondItem == nil })
        window.setContentSize(NSSize(width: to, height: 400))
        fixture.toolbar.paneMoved(leading: 56, width: to - 56)
        var seen: [CGFloat] = []
        for _ in 0..<60 {
            fixture.settle(2)
            seen.append(constraint.constant)
        }
        return seen
    }

    func testAFixedWindowSettlesToOnePlanWhateverRouteItCameBy() throws {
        for to: CGFloat in [860, 940, 1060] {
            let routes = try [to + 300, to - 100, to].map { try widths(from: $0, to: to) }
            for (i, seen) in routes.enumerated() {
                let late = Set(seen.suffix(30))
                XCTAssertEqual(late.count, 1, "window \(to), route \(i): the plate never stands still: \(late.sorted())")
            }
            XCTAssertEqual(Set(routes.compactMap(\.last)).count, 1,
                           "window \(to): the plan depends on the route: \(routes.compactMap(\.last))")
        }
    }
}
