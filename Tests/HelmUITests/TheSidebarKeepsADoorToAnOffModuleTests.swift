import XCTest
@testable import HelmUI

/// A module you switch off had no page, and a page had been written for it.
///
/// All four routes to a module's own page refuse a switched-off module: the
/// sidebar filtered by `isEnabled`, the status item's menu filters and says why,
/// the panel's utility rows are built from live modules only, and the panel
/// footer opens the settings page rather than a module. So `ModuleDetailView`'s
/// else-branch — the module's symbol, its name, its summary and a «Turn on»
/// button, written after what its own comment calls «the app's poorest screen» —
/// could not be reached in the shipping app. What a person got instead, having
/// switched Disk off and later wondered what it did, was one row in the composer
/// whose summary is a tooltip.
///
/// This is the arithmetic of the door: which modules the sidebar lists where.
final class TheSidebarKeepsADoorToAnOffModuleTests: XCTestCase {

    private let layout = SidebarLayout(sections: [
        .init(id: "seed.files", seed: "files", name: nil,
              modules: ["duplicates", "disk", "leftovers"]),
        .init(id: "seed.utilities", seed: "utilities", name: nil,
              modules: ["vpn", "keepawake"]),
    ])

    func testASectionListsOnlyWhatIsOnAndKeepsItsOrder() {
        let section = layout.sections[0]
        XCTAssertEqual(layout.live(in: section, enabled: ["duplicates", "leftovers", "vpn"]),
                       ["duplicates", "leftovers"])
    }

    /// The door itself: a module that is off is still listed, so `.module(id)`
    /// is still a selection somebody can make — which is what makes the page
    /// written for that case reachable at all.
    func testASwitchedOffModuleIsStillSomewhereToGo() {
        XCTAssertEqual(layout.off(enabled: ["duplicates", "vpn"]),
                       ["disk", "leftovers", "keepawake"],
                       "in layout order, across sections: the off rows are one list at the foot")
    }

    /// Once, and in one of the two places. A module drawn in its section *and*
    /// under «Switched off» is the sidebar disagreeing with itself.
    func testNoModuleIsDrawnTwice() {
        let enabled: Set<String> = ["disk", "keepawake"]
        let listed = layout.sections.flatMap { layout.live(in: $0, enabled: enabled) }
            + layout.off(enabled: enabled)
        XCTAssertEqual(Set(listed).count, listed.count)
        XCTAssertEqual(Set(listed), Set(layout.sections.flatMap(\.modules)),
                       "every module the layout knows is reachable from the sidebar, on or off")
    }

    /// With everything on there is nothing to draw, and a heading over an empty
    /// list is the gap the settings page's Permissions section documents.
    func testWithEverythingOnThereIsNoSuchSection() {
        XCTAssertTrue(layout.off(enabled: Set(layout.sections.flatMap(\.modules))).isEmpty)
    }
}
