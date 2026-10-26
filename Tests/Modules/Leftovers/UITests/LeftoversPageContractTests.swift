import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// What the bottom bar counts: its count and its size are both about the selection.
@MainActor
final class LeftoversPageContractTests: XCTestCase {

    private func agent(_ name: String, bytes: Int, status: ItemStatus = .orphaned) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: bytes, status: status)
    }

    // MARK: - The bottom bar's two quantities

    /// The bar read "1 объект · 0 Б" with nothing ticked, above a visible row
    /// saying 4 КБ: the count was everything found and removable, the size was
    /// the selection, and the middle dot made them look like one measurement.
    func testTheBarsCountAndSizeAreBothAboutTheSelection() async {
        let transport = LeftoversWire(items: [agent("one", bytes: 4_096),
                                              agent("two", bytes: 8_192)])
        let lvm = LeftoversViewModel(vm: ModuleViewModel(transport: transport))
        await lvm.scan()
        XCTAssertEqual(lvm.leftoverCount, 2, "precondition: two removable rows were found")

        XCTAssertEqual(lvm.selectedCount, 0, "nothing is ticked, so the bar counts nothing")
        XCTAssertEqual(lvm.selectedBytes, 0)

        lvm.selected.insert(lvm.visibleItems[0].path)

        XCTAssertEqual(lvm.selectedCount, 1)
        XCTAssertEqual(lvm.selectedBytes, 4_096)
    }

    /// A tick on a row that is no longer shown counts for neither figure — the
    /// same rule `removeSelected` follows when it decides what may go.
    func testAHiddenTickIsCountedByNeitherFigure() async {
        let transport = LeftoversWire(items: [agent("kept", bytes: 4_096),
                                              agent("busy", bytes: 8_192, status: .inUse)])
        let lvm = LeftoversViewModel(vm: ModuleViewModel(transport: transport))
        lvm.showAll = true
        await lvm.scan()
        lvm.selected = Set(lvm.visibleItems.map(\.path))
        XCTAssertEqual(lvm.selectedCount, 2, "precondition: both rows are shown and ticked")

        lvm.showAll = false     // back to leftovers only

        XCTAssertEqual(lvm.selectedCount, 1,
                       "a row the list no longer shows was still counted in the bar")
        XCTAssertEqual(lvm.selectedBytes, 4_096)
    }
}
