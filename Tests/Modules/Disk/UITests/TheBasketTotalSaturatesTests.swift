import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// Two rows in the basket that each weigh nearly an integer: `basketBytes` is the
/// bar's total and used to be a plain sum, which traps in release. A row can
/// weigh that much from a saved scan (8191 targets at `DiskEntry.byteCeiling`),
/// so the sum saturates rather than relying on the bound on each figure.
@MainActor
final class TheBasketTotalSaturatesTests: XCTestCase {
    func testTwoRowsNearAnIntegerSumToTheTopOfOne() {
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: AnsweringTransport(volumes: [])),
                                store: ScanStore(directory: scratchDirectory("disk-basket-total")))
        dvm.basket = [folder("/v/a", bytes: Int.max - 1), folder("/v/b", bytes: Int.max - 1)]
        XCTAssertEqual(dvm.basket.count, 2, "precondition: both rows are in the basket")
        XCTAssertEqual(dvm.basketBytes, Int.max)
    }
}
