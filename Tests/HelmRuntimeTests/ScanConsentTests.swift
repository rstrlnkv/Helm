import XCTest
@testable import HelmRuntime

/// The rows of the one screen that says Helm reads the disk on its own.
///
/// Nothing in `Sources/` ever wrote `disabledScans`, so this list existed with
/// no writer and no reader outside the coordinator: the person whose volume is
/// walked twice a day could learn it only from the log.
final class ScanConsentTests: XCTestCase {

    private let scannable = ["duplicates", "uninstaller", "disk"]

    func testEveryScannableModuleThatIsOnGetsARow() throws {
        let rows = try XCTUnwrap(ScanConsent.rows(scannable: scannable,
                                                  enabled: ["duplicates", "uninstaller", "disk"],
                                                  disabledScans: ["disk"],
                                                  lastRun: [:]))
        XCTAssertEqual(rows.map(\.id), scannable, "in the order the scans are listed in")
        XCTAssertEqual(rows.map(\.isOn), [true, true, false])
    }

    /// A switch for a scan that cannot run whatever it says is not consent.
    /// `ScanCoordinator.run` asks `host.liveModule(id)` and a module that is
    /// off has none.
    func testAModuleThatIsOffHasNoRow() throws {
        let rows = try XCTUnwrap(ScanConsent.rows(scannable: scannable,
                                                  enabled: ["duplicates"],
                                                  disabledScans: [],
                                                  lastRun: [:]))
        XCTAssertEqual(rows.map(\.id), ["duplicates"])
    }

    func testARowCarriesWhenThatScanLastFinished() throws {
        let when = Date(timeIntervalSince1970: 1_000_000)
        let rows = try XCTUnwrap(ScanConsent.rows(scannable: scannable,
                                                  enabled: Set(scannable),
                                                  disabledScans: [],
                                                  lastRun: ["uninstaller": when]))
        XCTAssertEqual(rows.first { $0.id == "uninstaller" }?.lastRun, when)
        XCTAssertNil(rows.first { $0.id == "disk" }?.lastRun)
    }

    /// **«Not read yet» is a third answer, and it is not «nothing is off».**
    /// The off-list is sealed, so reading it can reach the login keychain — a
    /// modal dialog on an ad-hoc build — and it therefore cannot be read on the
    /// path that builds the screen. Until the answer arrives there is nothing to
    /// draw: an empty off-list would draw every switch on, which is the reading
    /// that turns a whole-volume walk on for somebody who never said so.
    func testAnUnreadOffListIsNoRowsRatherThanEveryScanOn() throws {
        XCTAssertNil(ScanConsent.rows(scannable: scannable, enabled: Set(scannable),
                                      disabledScans: nil, lastRun: [:]))
        let read = try XCTUnwrap(ScanConsent.rows(scannable: scannable,
                                                  enabled: Set(scannable),
                                                  disabledScans: [], lastRun: [:]))
        XCTAssertEqual(read.map(\.id), scannable,
                       "or «unread» and «read, nothing off» are the same value and this "
                       + "assertion is empty")
    }

    /// A scannable list with nothing enabled is empty rows, and that is a
    /// different sentence from «not read yet» — the screen knows the answer and
    /// the answer is that there is nothing to ask about.
    func testNoEnabledModulesIsAnEmptyListAndNotAnUnreadOne() {
        XCTAssertEqual(ScanConsent.rows(scannable: scannable, enabled: [],
                                        disabledScans: [], lastRun: [:]), [])
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
