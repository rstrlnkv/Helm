import XCTest
@testable import HelmRuntime

final class UpdateVersionPrereleaseTests: XCTestCase {
    func testPrereleaseOrdersBelowItsRelease() {
        XCTAssertTrue(UpdateVersion.isNewer("0.7.0", than: "0.7.0-dev.3"))
        XCTAssertFalse(UpdateVersion.isNewer("0.7.0-dev.3", than: "0.7.0"))
    }

    func testPrereleasesOrderAmongThemselves() {
        XCTAssertTrue(UpdateVersion.isNewer("0.7.0-dev.2", than: "0.7.0-dev.1"))
        XCTAssertFalse(UpdateVersion.isNewer("0.7.0-dev.1", than: "0.7.0-dev.2"))
        XCTAssertTrue(UpdateVersion.isNewer("v0.7.0-dev.10", than: "0.7.0-dev.9"))
    }

    func testPrereleaseStillBeatsOlderRelease() {
        XCTAssertTrue(UpdateVersion.isNewer("0.7.0-dev.1", than: "0.6.1"))
        XCTAssertFalse(UpdateVersion.isNewer("0.6.1", than: "0.7.0-dev.1"))
    }

    func testEqualVersionsAreNotNewer() {
        XCTAssertFalse(UpdateVersion.isNewer("0.6.1", than: "0.6.1"))
        XCTAssertFalse(UpdateVersion.isNewer("0.7.0-dev.1", than: "0.7.0-dev.1"))
    }
}

final class UpdateChannelSelectionTests: XCTestCase {
    private func releaseJSON(tag: String, prerelease: Bool, draft: Bool = false) -> String {
        """
        {"tag_name":"\(tag)","html_url":"https://x/\(tag)","body":"notes",
         "prerelease":\(prerelease),"draft":\(draft),
         "assets":[{"name":"Helm-\(tag).zip","browser_download_url":"https://x/\(tag).zip"}]}
        """
    }

    /// The dev channel reads the releases LIST and must pick the newest entry
    /// regardless of prerelease status, skipping drafts.
    func testDevChannelPicksNewestIncludingPrerelease() {
        let json = "[\(releaseJSON(tag: "v0.7.0-dev.2", prerelease: true)),"
            + "\(releaseJSON(tag: "v0.6.1", prerelease: false))]"
        let outcome = UpdateCheck.evaluateList(statusCode: 200,
                                               data: Data(json.utf8),
                                               currentVersion: "0.6.1",
                                               channel: .dev)
        guard case .available(let r) = outcome else { return XCTFail("expected update, got \(outcome)") }
        XCTAssertEqual(r.version, "v0.7.0-dev.2")
        XCTAssertEqual(r.zipURL, "https://x/v0.7.0-dev.2.zip")
    }

    func testStableChannelIgnoresPrereleasesInTheList() {
        let json = "[\(releaseJSON(tag: "v0.7.0-dev.2", prerelease: true)),"
            + "\(releaseJSON(tag: "v0.6.1", prerelease: false))]"
        let outcome = UpdateCheck.evaluateList(statusCode: 200,
                                               data: Data(json.utf8),
                                               currentVersion: "0.6.1",
                                               channel: .stable)
        XCTAssertEqual(outcome, .upToDate)
    }

    func testDraftsAreSkipped() {
        let json = "[\(releaseJSON(tag: "v0.9.0-dev.1", prerelease: true, draft: true)),"
            + "\(releaseJSON(tag: "v0.7.0-dev.1", prerelease: true))]"
        let outcome = UpdateCheck.evaluateList(statusCode: 200,
                                               data: Data(json.utf8),
                                               currentVersion: "0.6.1",
                                               channel: .dev)
        guard case .available(let r) = outcome else { return XCTFail("expected update") }
        XCTAssertEqual(r.version, "v0.7.0-dev.1")
    }

    /// A dev user who already runs the newest prerelease gets nothing.
    func testDevChannelUpToDate() {
        let json = "[\(releaseJSON(tag: "v0.7.0-dev.2", prerelease: true))]"
        XCTAssertEqual(UpdateCheck.evaluateList(statusCode: 200,
                                                data: Data(json.utf8),
                                                currentVersion: "0.7.0-dev.2",
                                                channel: .dev), .upToDate)
    }

    func testEmptyListIsUpToDateAndBadStatusIsError() {
        XCTAssertEqual(UpdateCheck.evaluateList(statusCode: 200, data: Data("[]".utf8),
                                                currentVersion: "0.6.1", channel: .dev), .upToDate)
        XCTAssertEqual(UpdateCheck.evaluateList(statusCode: 500, data: Data(),
                                                currentVersion: "0.6.1", channel: .dev), .error)
    }
}
