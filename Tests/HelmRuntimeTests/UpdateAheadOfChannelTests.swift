import XCTest
@testable import HelmRuntime

/// Running a build the channel has not caught up with is not "up to date".
///
/// `isNewer` compares numeric cores, so 0.7.1 is not newer than 0.7.2-dev.34
/// and the check fell through to `.upToDate` — the About page then said
/// "You're on the latest version" to somebody running an unreleased dev build
/// on the Beta channel. That reading is worse than a wrong version number: it
/// tells the one person most likely to be testing something that there is
/// nothing to test.
///
/// The outcome is deliberately about *prereleases* being ahead. A final release
/// ahead of its own channel is a state the release flow does not produce
/// (VERSIONING.md: everything ships to dev first), and calling it out would put
/// a notice on the About page of every ordinary user the day a channel lags.
final class UpdateAheadOfChannelTests: XCTestCase {

    private func release(tag: String) -> Data {
        #"{"tag_name":"\#(tag)","html_url":"https://example.com/r","body":"","assets":[]}"#
            .data(using: .utf8)!
    }

    private func list(_ tags: [(String, Bool)]) -> Data {
        let items = tags.map { tag, pre in
            #"{"tag_name":"\#(tag)","html_url":"https://example.com/r","body":"","assets":[],"prerelease":\#(pre)}"#
        }.joined(separator: ",")
        return "[\(items)]".data(using: .utf8)!
    }

    func testADevBuildAheadOfTheBetaChannelSaysSo() {
        let outcome = UpdateCheck.evaluate(statusCode: 200, data: release(tag: "v0.7.1"),
                                           currentVersion: "0.7.2-dev.34")
        XCTAssertEqual(outcome, .ahead(newest: "v0.7.1"))
    }

    /// The case that made this visible: the same numeric family, where the
    /// channel's newest is the release this prerelease is working toward.
    func testTheChannelCatchingUpIsAnUpdateAgain() {
        let outcome = UpdateCheck.evaluate(statusCode: 200, data: release(tag: "v0.7.2"),
                                           currentVersion: "0.7.2-dev.34")
        guard case .available(let r) = outcome else { return XCTFail("expected .available, got \(outcome)") }
        XCTAssertEqual(r.version, "v0.7.2")
    }

    func testAPrereleaseTheChannelAlreadyCarriesIsUpToDate() {
        XCTAssertEqual(UpdateCheck.evaluate(statusCode: 200, data: release(tag: "v0.7.2-dev.34"),
                                            currentVersion: "0.7.2-dev.34"),
                       .upToDate)
    }

    /// A finished release ahead of its channel stays quiet — see the note above.
    func testAFinalReleaseAheadOfTheChannelIsStillUpToDate() {
        XCTAssertEqual(UpdateCheck.evaluate(statusCode: 200, data: release(tag: "v0.7.1"),
                                            currentVersion: "0.7.2"),
                       .upToDate)
    }

    func testTheListEndpointReadsItTheSameWay() {
        let data = list([("v0.7.1", false), ("v0.7.0", false)])
        XCTAssertEqual(UpdateCheck.evaluateList(statusCode: 200, data: data,
                                                currentVersion: "0.7.2-dev.34", channel: .beta),
                       .ahead(newest: "v0.7.1"))
    }

    /// On the dev channel a prerelease is eligible, so the same build finds
    /// itself and is simply current.
    func testTheDevChannelSeesItsOwnPrerelease() {
        let data = list([("v0.7.2-dev.34", true), ("v0.7.1", false)])
        XCTAssertEqual(UpdateCheck.evaluateList(statusCode: 200, data: data,
                                                currentVersion: "0.7.2-dev.34", channel: .dev),
                       .upToDate)
    }

    /// Nothing published at all is not being ahead of anything.
    func testNoReleasesIsStillUpToDate() {
        XCTAssertEqual(UpdateCheck.evaluate(statusCode: 404, data: Data(),
                                            currentVersion: "0.7.2-dev.34"),
                       .upToDate)
        XCTAssertEqual(UpdateCheck.evaluateList(statusCode: 200, data: Data("[]".utf8),
                                                currentVersion: "0.7.2-dev.34", channel: .beta),
                       .upToDate)
    }

    /// The outcome carries the version it is ahead of, because the sentence the
    /// About page draws names it.
    func testTheOutcomeNamesWhatTheChannelHas() {
        guard case .ahead(let newest) = UpdateCheck.evaluate(
            statusCode: 200, data: release(tag: "v0.6.9"), currentVersion: "0.7.0-dev.1")
        else { return XCTFail("expected .ahead") }
        XCTAssertEqual(newest, "v0.6.9")
    }
}
