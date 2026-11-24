import XCTest
@testable import HelmRuntime

/// Every file the log can create is a file the log knows how to destroy.
///
/// The purge and the Clear button must remove the names rollover writes
/// (`helm.previous.log`), not a guessed `helm.log.1`, or the older half of a
/// log carrying names and paths survives both.
final class LogFileNamesTests: XCTestCase {

    func testTheRolloverIsOneOfTheFilesTheLogAccountsFor() {
        XCTAssertTrue(HelmLog.allFileURLs.contains(HelmLog.previousFileURL),
                      "rollover writes a file that nothing clears")
        XCTAssertTrue(HelmLog.allFileURLs.contains(HelmLog.fileURL))
        XCTAssertEqual(HelmLog.allFileURLs.count, 2)
    }

    /// The purge's latch is the one file the log must **not** clear.
    ///
    /// It records that the one-time purge already happened, so a purge that
    /// removed it would run again and wipe the fresh log. It is a file beside
    /// the log, not a `UserDefaults.standard` key, whose domain is the calling
    /// process's, so any tool linking HelmRuntime would purge on first run.
    func testTheResetMarkerIsNotSomethingClearingTheLogDestroys() {
        XCTAssertFalse(HelmLog.allFileURLs.contains(HelmLog.resetMarkerURL),
                       "clearing the log would delete the record that the purge already ran, "
                       + "which lets the purge run a second time and take a real log with it")
        XCTAssertEqual(HelmLog.resetMarkerURL.deletingLastPathComponent(), HelmLog.directory)
    }
}
