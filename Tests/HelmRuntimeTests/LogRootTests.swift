import Foundation
import XCTest
@testable import HelmRuntime

/// What a scan or search root may look like in `helm.log`.
///
/// `Redact.path` rewrites the home prefix and its `/System/Volumes/Data` twin,
/// and by design nothing else — so a scan of `/Volumes/Anna's Work Backup` or
/// of `/Users/<another account>` wrote a volume name or an account name into
/// the file whose whole purpose is being pasted into a bug report. That is the
/// class of fact ARCHITECTURE.md § Diagnostics log says must not reach it.
///
/// The shape is kept because it is what triage reads — an external volume and
/// another account are different stories — and the chosen name is replaced by
/// the stable tag `Redact` uses everywhere else.
final class LogRootTests: XCTestCase {
    private let home = "/Users/me"

    func testAHomeRootIsWrittenTheWayItAlwaysWas() {
        XCTAssertEqual(LogRoot.label("/Users/me/Downloads", home: home), "~/Downloads")
        XCTAssertEqual(LogRoot.label("/Users/me", home: home), "~")
        XCTAssertEqual(LogRoot.label("/System/Volumes/Data/Users/me/Movies", home: home),
                       "~/Movies")
    }

    func testAVolumeNameNeverReachesTheLog() {
        let label = LogRoot.label("/Volumes/Anna's Work Backup", home: home)
        XCTAssertFalse(label.contains("Anna"), "the volume name went into the log")
        XCTAssertTrue(label.hasPrefix("/Volumes/"), "which kind of place it was is the useful part")
    }

    /// Duplicates searches a folder inside the volume, so the tail is a name too.
    func testNothingBelowTheVolumeNameReachesTheLogEither() {
        let label = LogRoot.label("/Volumes/Anna's Work Backup/Photos", home: home)
        XCTAssertFalse(label.contains("Anna"), "the volume name went into the log")
        XCTAssertFalse(label.contains("Photos"))
        XCTAssertTrue(label.hasPrefix("/Volumes/"))
    }

    func testAnotherAccountsNameNeverReachesTheLog() {
        let label = LogRoot.label("/Users/anna/Documents", home: home)
        XCTAssertFalse(label.contains("anna"))
        XCTAssertFalse(label.contains("Documents"))
        XCTAssertTrue(label.hasPrefix("/Users/"))
    }

    /// A tag nobody can compare across lines answers no question at all.
    func testTheSameRootTagsTheSameAndDifferentRootsDiffer() {
        let once = LogRoot.label("/Volumes/Backup", home: home)
        XCTAssertEqual(once, LogRoot.label("/Volumes/Backup", home: home))
        XCTAssertNotEqual(once, LogRoot.label("/Volumes/Other", home: home))
    }

    /// Nothing is hidden that macOS itself named: these carry no user's word.
    func testPlacesMacOSNamedAreWrittenPlainly() {
        for root in ["/", "/Volumes", "/Applications", "/System/Volumes/Data"] {
            XCTAssertEqual(LogRoot.label(root, home: home), root)
        }
    }
}
