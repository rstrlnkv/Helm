import AppKit
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// **Login Items is striped, and its list starts at the pane's own left edge.**
///
/// `helmStripedList(rowPitch:)` replaced `.listStyle(.inset)` and the removed
/// `.padding(.horizontal, 12)` — the padding pushed every row 12 pt inside the
/// pane, which is the treatment `HomebrewSettingsPage`'s own lists dropped for
/// the same reason. The second case guards that removal: without it the
/// stripe's own edge would be twelve points shy of the pane, unremarked by
/// anything else in this file.
@MainActor
final class TheLeftoversListIsStripedTests: XCTestCase {

    /// `LeftoversPageRender.page` sets `AppLanguage.override` and leaves its
    /// restoration to the caller; without this every later case in the process
    /// reads English whatever it asked for.
    private var previous: AppLanguage?

    override func setUp() {
        super.setUp()
        previous = AppLanguage.override
    }

    override func tearDown() {
        AppLanguage.override = previous
        super.tearDown()
    }

    private static func item(_ name: String) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: 4_096)
    }

    private static var items: [StaleItem] {
        [item("com.vendor.one"), item("com.vendor.two")]
    }

    func testTheListIsStriped() async throws {
        let (mount, _) = await LeftoversPageRender.page(Self.items, language: .en,
                                                        width: 700, appearance: .aqua)
        defer { mount.drop() }
        let tables = mount.host.everyView(ofType: NSTableView.self)
        XCTAssertFalse(tables.isEmpty, "no NSTableView under the mount")
        for table in tables {
            XCTAssertTrue(table.usesAlternatingRowBackgroundColors, "the list is not striped")
        }
    }

    /// **Below the last row, the stripe repeats at the pitch the page
    /// declares, and a row taller than it keeps its own height.** This
    /// page's rows draw 44 pt (measured 2026-09-29) against a `HelmSpace.s8`
    /// pitch of 40 — the ladder's nearest step, so the stripe under the list
    /// is 4 pt shorter than the rows above it by design, which is the only
    /// way to tell a floor from a ceiling here. The list opens on a `Section`
    /// header, which `StripedListPitch.realRowHeights` leaves out.
    func testTheEmptyAreaRepeatsAtTheDeclaredPitchAndTallRowsKeepTheirOwn() async throws {
        let (mount, _) = await LeftoversPageRender.page(Self.items, language: .en,
                                                        width: 700, appearance: .aqua)
        defer { mount.drop() }
        let tables = mount.host.everyView(ofType: NSTableView.self)
        XCTAssertFalse(tables.isEmpty, "no NSTableView under the mount")
        for table in tables {
            XCTAssertEqual(table.rowHeight, HelmSpace.s8, accuracy: 0.5, """
                the empty area repeats at \(table.rowHeight) pt where the page declared \
                \(HelmSpace.s8)
                """)
            let rows = StripedListPitch.realRowHeights(in: table)
            XCTAssertFalse(rows.isEmpty, "no non-header row to measure")
            for height in rows {
                XCTAssertGreaterThan(height, HelmSpace.s8 + 0.5, """
                    a row drew \(height) pt under a \(HelmSpace.s8) pt pitch — a row \
                    taller than the pitch must keep its own height
                    """)
            }
        }
    }

    /// `helmStripedList(rowPitch:)` replaced `.listStyle(.inset)` **and** the
    /// `List` lost the `.padding(.horizontal, 12)` that followed it — a bare
    /// stripe swap would still leave every row 12 pt inside the pane.
    func testTheListsLeftEdgeIsThePanesOwn() async throws {
        let (mount, _) = await LeftoversPageRender.page(Self.items, language: .en,
                                                        width: 700, appearance: .aqua)
        defer { mount.drop() }
        let list = try XCTUnwrap(
            mount.host.everyView.first { $0.appKitClassName.contains("ListCoreScrollView") },
            "no list drew at all")
        let frame = list.convert(list.bounds, to: mount.host)
        XCTAssertEqual(frame.minX, 0, accuracy: 0.5, """
            the list starts \(frame.minX) pt inside its pane, where the removed \
            `.padding(.horizontal, 12)` would put it back at 12
            """)
    }
}
