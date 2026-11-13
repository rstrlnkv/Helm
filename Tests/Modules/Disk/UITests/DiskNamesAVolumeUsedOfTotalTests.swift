import HelmUI
import XCTest
@testable import Module_Disk_UI
import Module_Disk_Engine

/// `DkStr.usedOfTotal` and `freeAmount` feed the sidebar widget, the settings
/// page and the ring tooltip. The figure order is the whole meaning: used first,
/// total second; a swap reads as a nearly full disk on an empty one.
final class DiskNamesAVolumeUsedOfTotalTests: XCTestCase {
    func testUsedComesBeforeTotal() {
        let volume = VolumeInfo(name: "V", path: "/", totalBytes: 500_000_000_000, freeBytes: 380_000_000_000)
        let text = DkStr.usedOfTotal(volume)
        XCTAssertEqual(text, Bytes(120_000_000_000) + " / " + Bytes(500_000_000_000))
        XCTAssertNotEqual(Bytes(120_000_000_000), Bytes(500_000_000_000))
    }

    func testFreeAmountCarriesTheFigure() {
        let text = DkStr.freeAmount(380_000_000_000)
        XCTAssertTrue(text.contains(Bytes(380_000_000_000)), text)
        XCTAssertNotEqual(text, Bytes(380_000_000_000))
    }
}
