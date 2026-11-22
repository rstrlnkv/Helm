import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A menu built before the catalog changed: the app was removed, or found at another path. Copy Path and Show in Finder name the app's
/// path as the snapshot holds it when pressed, not the one the menu was built with.
@MainActor final class AFileActionNamesThePathTheCatalogHoldsNowTests: XCTestCase {
    private let hiddenApp = HiddenRig.unreconciled().apps[HiddenRig.hidden]!

    private func wired(_ rig: HiddenRig) -> (copied: () -> [String], revealed: () -> [String]) {
        var copied: [String] = [], revealed: [String] = []
        rig.state.onCopyPath = { path, _ in copied.append(path) }
        rig.state.onRevealApp = { revealed.append($0) }
        return ({ copied }, { revealed })
    }

    private func snapshot(_ apps: [CatalogApp], hidden: Set<AppID>) -> LaunchpadSnapshot {
        var layout = LaunchpadLayout(items: apps.map { .app($0.id) })
        layout.hidden = hidden
        return LaunchpadSnapshot(apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }), order: apps.map(\.id),
                                 layout: layout, catalogComplete: true, layoutRead: .absent)
    }

    func testAnAppRemovedOrMovedAfterTheMenuWasBuiltHandsNoStalePath() {
        let rig = HiddenRig(.immediate(.success))
        let seen = wired(rig)
        let visible = HiddenRig.unreconciled().apps["a"]!
        let files = rig.state.fileActions(for: visible)

        // Moved: the catalog reads the app at another path.
        rig.state.update(snapshot: snapshot([CatalogApp(id: "a", name: "Alpha", path: "/Applications/Utilities/a.app")], hidden: []))
        files?.copyPath(); files?.reveal()
        XCTAssertEqual(seen.copied(), ["/Applications/Utilities/a.app"], "the path the catalog holds now is copied, not the old one")
        XCTAssertEqual(seen.revealed(), ["/Applications/Utilities/a.app"], "and the same path is shown")

        // Removed.
        rig.state.update(snapshot: snapshot([hiddenApp], hidden: [HiddenRig.hidden]))
        files?.copyPath(); files?.reveal()
        XCTAssertEqual(seen.copied(), ["/Applications/Utilities/a.app"], "a removed app has no path to copy: nothing more was copied")
        XCTAssertEqual(seen.revealed(), ["/Applications/Utilities/a.app"], "or to show")
    }
}
