import XCTest
@testable import HelmUI

/// **A `.segmented` action is a second set of tabs, so it takes the tabs'
/// label style.** The owner asked for Hosts' Table / Plain-text pair to look
/// like the tabs (2026-09-25); drawn at the environment's `.text` default it
/// kept words even when the centre tabs had switched to icons. The reserve is
/// what this reads, because it is measured in the same style the switcher is
/// drawn in — a capsule that ignored the style would reserve the same width
/// for both.
@MainActor
final class ASegmentedActionFollowsTheTabsLabelStyleTests: XCTestCase {

    private func segmented() -> HelmToolbarActionsModel.Entry {
        HelmToolbarActionsModel.Entry(
            id: "viewMode", title: "View", symbol: "", isEnabled: true,
            kind: .segmented([
                .init(id: "table", title: "Table", symbol: "tablecells"),
                .init(id: "text", title: "Plain text", symbol: "text.alignleft"),
            ], selectedID: "table"))
    }

    func testTheReserveIsMeasuredInTheStyleTheTabsUse() {
        let model = HelmToolbarActionsModel()
        let entry = segmented()
        let words = HelmToolbarActionsCapsule(model, switcherStyle: .text).reserveWidth(entry)
        let icons = HelmToolbarActionsCapsule(model, switcherStyle: .icons).reserveWidth(entry)
        XCTAssertGreaterThan(words, 0, "precondition: the text-style reserve measured nothing")
        XCTAssertLessThan(icons, words, """
            an icons-only switcher reserved as much as a worded one — the capsule is not \
            measuring in the style it was handed
            """)
    }
}
