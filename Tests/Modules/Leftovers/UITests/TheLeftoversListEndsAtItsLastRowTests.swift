import AppKit
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// **Leftovers' list, scrolled to its end, stops at its last row** — the
/// reading `TheListEndsAtItsLastRowTests` takes on Homebrew, where the owner
/// saw three empty striped rows under the last package. Enough items to
/// scroll, the furthest offset the clip view allows (`StripedListEnd`), judged
/// against the list's own row step. Light and Dark.
@MainActor
final class TheLeftoversListEndsAtItsLastRowTests: XCTestCase {

    private var previous: AppLanguage?

    override func setUp() {
        super.setUp()
        previous = AppLanguage.override
    }

    override func tearDown() {
        AppLanguage.override = previous
        super.tearDown()
    }

    private static let count = 60

    private static var items: [StaleItem] {
        (0..<count).map {
            StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/com.vendor.\($0).plist",
                      identifier: "com.vendor.\($0)", kind: .launchAgent, sizeBytes: 4_096)
        }
    }

    private func read(_ appearance: NSAppearance.Name) async throws {
        let (mount, _) = await LeftoversPageRender.page(Self.items, language: .en,
                                                        width: 700, appearance: appearance)
        defer { mount.drop() }
        let name = "Leftovers \(appearance == .aqua ? "Light" : "Dark")"
        let table = try XCTUnwrap(StripedListEnd.table(in: mount.host), "\(name): no table")
        XCTAssertGreaterThanOrEqual(table.numberOfRows, Self.count, """
            \(name): \(table.numberOfRows) rows for \(Self.count) items — the subject never arrived
            """)
        let reading = try XCTUnwrap(StripedListEnd.read(table, host: mount.host), "\(name): no scroll view")
        print("[list-end] \(name): \(reading)")
        XCTAssertTrue(reading.scrollable, "\(name): the list did not scroll — \(reading)")
        XCTAssertLessThan(reading.overscroll, table.rowHeight / 2, """
            \(name): scrolled to its end the list shows \(reading.overscroll) pt of empty rows under \
            the last one — \(reading)
            """)
    }

    func testTheListEndsAtItsLastRowInLight() async throws { try await read(.aqua) }
    func testTheListEndsAtItsLastRowInDark() async throws { try await read(.darkAqua) }
}
