import XCTest
@testable import HelmRuntime

/// The About page shows the version as an instrument figure in a fixed cell.
/// "0.7.1-dev.1" runs into the divider, so the release number stays the figure
/// and the prerelease part moves to the caption underneath.
final class VersionLabelTests: XCTestCase {
    func testFinalReleaseHasNoCaptionSuffix() {
        let split = VersionLabel.split("0.7.1")
        XCTAssertEqual(split.figure, "0.7.1")
        XCTAssertNil(split.suffix)
    }

    func testDevBuildMovesToTheCaption() {
        let split = VersionLabel.split("0.7.1-dev.1")
        XCTAssertEqual(split.figure, "0.7.1")
        XCTAssertEqual(split.suffix, "DEV 1")
    }

    func testTwoDigitDevBuild() {
        XCTAssertEqual(VersionLabel.split("0.7.0-dev.23").suffix, "DEV 23")
    }

    /// Any other prerelease spelling still reads as a caption rather than
    /// overflowing the cell.
    func testUnknownPrereleaseIsUppercased() {
        let split = VersionLabel.split("1.0.0-beta.2")
        XCTAssertEqual(split.figure, "1.0.0")
        XCTAssertEqual(split.suffix, "BETA 2")
    }

    func testSuffixWithoutAnOrdinal() {
        XCTAssertEqual(VersionLabel.split("1.0.0-rc").suffix, "RC")
    }

    func testEmptyVersionIsLeftAlone() {
        XCTAssertEqual(VersionLabel.split("").figure, "")
        XCTAssertNil(VersionLabel.split("").suffix)
    }

    // MARK: - Caption assembly

    func testCaptionJoinsTheLabelAndTheSuffix() {
        XCTAssertEqual(VersionLabel.caption("ВЕРСИЯ", for: "0.7.1-dev.1"), "ВЕРСИЯ · DEV 1")
        XCTAssertEqual(VersionLabel.caption("ВЕРСИЯ", for: "0.7.1"), "ВЕРСИЯ")
    }
}
