import XCTest
@testable import Module_Launchpad_Engine

/// What the Hidden block and the settings page list once unlocked: the hidden apps that are installed, in the catalog's order.
final class TheHiddenAppsOfASnapshotTests: XCTestCase {
    private func snapshot(order: [String], installed: [String], hidden: Set<String>) -> LaunchpadSnapshot {
        let apps = installed.map { CatalogApp(id: $0, name: $0.uppercased(), path: "/Applications/\($0).app") }
        var layout = LaunchpadLayout(items: order.map { .app($0) })
        layout.hidden = hidden
        return LaunchpadSnapshot(apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }), order: order,
                                 layout: layout, catalogComplete: true, layoutRead: .absent)
    }

    func testTheCatalogsOrderNotTheOrderTheyWereHiddenIn() {
        let s = snapshot(order: ["a", "b", "c", "d"], installed: ["a", "b", "c", "d"], hidden: ["d", "b"])
        XCTAssertEqual(s.hiddenApps.map(\.id), ["b", "d"])
    }

    func testOnlyInstalledAppsAndEveryOneOnce() {
        let s = snapshot(order: ["a", "b"], installed: ["a", "b"], hidden: ["gone", "b"])
        XCTAssertEqual(s.hiddenApps.map(\.id), ["b"], "an id of an app that is not installed is no name to show")
        XCTAssertTrue(snapshot(order: ["a"], installed: ["a"], hidden: []).hiddenApps.isEmpty, "the control: nothing hidden, nothing listed")
        XCTAssertEqual(snapshot(order: ["a", "b"], installed: ["a"], hidden: ["a", "b"]).hiddenApps.map(\.id), ["a"], "listed in the order but not installed")
    }
}
