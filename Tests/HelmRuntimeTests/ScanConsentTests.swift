import XCTest
@testable import HelmRuntime

/// The rows of the one screen that says Helm reads the disk on its own.
///
/// Nothing in `Sources/` ever wrote `disabledScans`, so this list existed with
/// no writer and no reader outside the coordinator: the person whose volume is
/// walked twice a day could learn it only from the log.
final class ScanConsentTests: XCTestCase {

    private let scannable = ["duplicates", "uninstaller", "disk"]

    func testEveryScannableModuleThatIsOnGetsARow() {
        let rows = ScanConsent.rows(scannable: scannable,
                                    enabled: ["duplicates", "uninstaller", "disk"],
                                    disabledScans: ["disk"],
                                    lastRun: [:])
        XCTAssertEqual(rows.map(\.id), scannable, "in the order the scans are listed in")
        XCTAssertEqual(rows.map(\.isOn), [true, true, false])
    }

    /// A switch for a scan that cannot run whatever it says is not consent.
    /// `ScanCoordinator.run` asks `host.liveModule(id)` and a module that is
    /// off has none.
    func testAModuleThatIsOffHasNoRow() {
        let rows = ScanConsent.rows(scannable: scannable,
                                    enabled: ["duplicates"],
                                    disabledScans: [],
                                    lastRun: [:])
        XCTAssertEqual(rows.map(\.id), ["duplicates"])
    }

    func testARowCarriesWhenThatScanLastFinished() {
        let when = Date(timeIntervalSince1970: 1_000_000)
        let rows = ScanConsent.rows(scannable: scannable,
                                    enabled: Set(scannable),
                                    disabledScans: [],
                                    lastRun: ["uninstaller": when])
        XCTAssertEqual(rows.first { $0.id == "uninstaller" }?.lastRun, when)
        XCTAssertNil(rows.first { $0.id == "disk" }?.lastRun)
    }

    func testSwitchingAScanOffAddsItToTheOffList() {
        XCTAssertEqual(ScanConsent.toggling("duplicates", to: false, in: ["disk"]),
                       ["disk", "duplicates"])
    }

    func testSwitchingAScanOnTakesItOutAndLeavesTheRestAlone() {
        XCTAssertEqual(ScanConsent.toggling("disk", to: true, in: ["disk", "duplicates"]),
                       ["duplicates"])
    }

    /// The off-list outlives the screen: a module switched off has no row, and
    /// pressing a row that *is* shown must not quietly switch that module's scan
    /// back on by writing a list the screen could see.
    func testAnAnswerAboutOneScanSaysNothingAboutAModuleWithNoRow() {
        let after = ScanConsent.toggling("duplicates", to: true, in: ["duplicates", "keepawake"])
        XCTAssertEqual(after, ["keepawake"])
    }
}
