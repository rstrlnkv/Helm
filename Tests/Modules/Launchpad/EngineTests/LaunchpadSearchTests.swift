import XCTest
@testable import Module_Launchpad_Engine

final class LaunchpadSearchTests: XCTestCase {
    private func snapshot(_ layout: LaunchpadLayout) -> LaunchpadSnapshot {
        let apps = ["a": "Mail", "b": "Maps", "c": "Notes", "h": "Magnet"].map { CatalogApp(id: $0.key, name: $0.value, path: "/\($0.key)") }
        return LaunchpadSnapshot(apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }), order: ["a", "b", "c", "h"],
                                 layout: layout, catalogComplete: true, layoutRead: .absent)
    }

    func testABlankQueryIsNotASearch() {
        XCTAssertNil(snapshot(.empty).search("   "))
    }

    func testSearchLooksIntoFoldersSkipsHiddenAndKeepsLayoutOrder() {
        var layout = LaunchpadLayout(items: [.app("c"), .folder(.init(id: UUID(), name: "F", apps: ["b", "a"]))])
        layout.hidden = ["h"]
        XCTAssertEqual(snapshot(layout).search("ma"), ["b", "a"])
        XCTAssertEqual(snapshot(layout).search("MAIL"), ["a"])
    }

    func testAHiddenAppIsNotFoundEvenIfALayoutStillPlacesIt() {
        var layout = LaunchpadLayout(items: [.app("h"), .folder(.init(id: UUID(), name: "F", apps: ["h", "a"]))])
        layout.hidden = ["h"]
        XCTAssertEqual(snapshot(layout).search("mag"), [])
        XCTAssertEqual(snapshot(layout).search("ma"), ["a"])
    }
}
