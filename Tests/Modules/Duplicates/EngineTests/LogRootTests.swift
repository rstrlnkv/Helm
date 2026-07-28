import Foundation
import XCTest
@testable import Module_Duplicates_Engine

/// The search root as `helm.log` may carry it. The rule and its reasons live
/// beside the Disk module's identical copy; what this pins is that this
/// module's copy has not drifted from it.
final class LogRootTests: XCTestCase {
    private let home = "/Users/me"

    func testASearchInsideTheHomeIsWrittenTheWayItAlwaysWas() {
        XCTAssertEqual(LogRoot.label("/Users/me/Downloads", home: home), "~/Downloads")
        XCTAssertEqual(LogRoot.label("/System/Volumes/Data/Users/me/Movies", home: home),
                       "~/Movies")
    }

    func testAVolumeNameNeverReachesTheLog() {
        let label = LogRoot.label("/Volumes/Anna's Work Backup/Photos", home: home)
        XCTAssertFalse(label.contains("Anna"), "the volume name went into the log")
        XCTAssertFalse(label.contains("Photos"))
        XCTAssertTrue(label.hasPrefix("/Volumes/"))
    }

    func testAnotherAccountsNameNeverReachesTheLog() {
        let label = LogRoot.label("/Users/anna/Documents", home: home)
        XCTAssertFalse(label.contains("anna"))
        XCTAssertTrue(label.hasPrefix("/Users/"))
    }

    func testTheSameRootTagsTheSameAndDifferentRootsDiffer() {
        let once = LogRoot.label("/Volumes/Backup", home: home)
        XCTAssertEqual(once, LogRoot.label("/Volumes/Backup", home: home))
        XCTAssertNotEqual(once, LogRoot.label("/Volumes/Other", home: home))
    }

    func testPlacesMacOSNamedAreWrittenPlainly() {
        for root in ["/", "/Volumes", "/System/Volumes/Data"] {
            XCTAssertEqual(LogRoot.label(root, home: home), root)
        }
    }
}
