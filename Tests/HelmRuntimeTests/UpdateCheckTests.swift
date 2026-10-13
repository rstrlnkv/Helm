import XCTest
@testable import HelmRuntime

final class UpdateCheckTests: XCTestCase {
    private func release(tag: String, assets: [(String, String)] = []) -> Data {
        let assetsJSON = assets.map {
            #"{"name":"\#($0.0)","browser_download_url":"\#($0.1)"}"#
        }.joined(separator: ",")
        return #"{"tag_name":"\#(tag)","html_url":"https://example.com/r","body":"notes","assets":[\#(assetsJSON)]}"#
            .data(using: .utf8)!
    }

    func testNoReleasesReadsAsUpToDate() {
        XCTAssertEqual(UpdateCheck.evaluate(statusCode: 404, data: Data(), currentVersion: "1.0.0"), .upToDate)
    }

    func testHTTPErrorIsError() {
        XCTAssertEqual(UpdateCheck.evaluate(statusCode: 500, data: Data(), currentVersion: "1.0.0"), .error)
    }

    func testGarbageBodyIsError() {
        XCTAssertEqual(UpdateCheck.evaluate(statusCode: 200, data: Data("nope".utf8), currentVersion: "1.0.0"), .error)
    }

    func testSameOrOlderVersionIsUpToDate() {
        XCTAssertEqual(UpdateCheck.evaluate(statusCode: 200, data: release(tag: "v1.0.0"), currentVersion: "1.0.0"), .upToDate)
        XCTAssertEqual(UpdateCheck.evaluate(statusCode: 200, data: release(tag: "v0.9.0"), currentVersion: "1.0.0"), .upToDate)
    }

    func testNewerVersionPicksZipAndDmgAssets() {
        let data = release(tag: "v1.1.0", assets: [
            ("Helm-1.1.0.dmg", "https://example.com/d.dmg"),
            ("Helm-1.1.0.zip", "https://example.com/d.zip"),
        ])
        guard case .available(let r) = UpdateCheck.evaluate(statusCode: 200, data: data, currentVersion: "1.0.0") else {
            return XCTFail("expected .available")
        }
        XCTAssertEqual(r.version, "v1.1.0")
        XCTAssertEqual(r.zipURL, "https://example.com/d.zip")
        XCTAssertEqual(r.downloadURL, "https://example.com/d.dmg")   // dmg preferred for manual
        XCTAssertEqual(r.notes, "notes")
    }

    func testNewerVersionWithoutZipFallsBackForManualDownload() {
        let data = release(tag: "v2.0.0", assets: [("Helm.dmg", "https://example.com/only.dmg")])
        guard case .available(let r) = UpdateCheck.evaluate(statusCode: 200, data: data, currentVersion: "1.0.0") else {
            return XCTFail("expected .available")
        }
        XCTAssertNil(r.zipURL)
        XCTAssertEqual(r.downloadURL, "https://example.com/only.dmg")
    }

    // MARK: which zip is the app

    /// The release script names the app's zip `Helm-<short version>.zip`, and the
    /// tag is that version behind a `v`. The updater installs whatever zip is
    /// answered here, so a release that carries a second zip must not be able
    /// to take its place by being listed first.
    private func offered(tag: String, assets: [String]) -> UpdateCheck.Release? {
        let data = release(tag: tag, assets: assets.map { ($0, "https://example.com/dl/\($0)") })
        guard case .available(let r) = UpdateCheck.evaluate(statusCode: 200, data: data,
                                                            currentVersion: "1.0.0")
        else { return nil }
        return r
    }

    func testTheZipWithTheAppsNameIsAnsweredWhenAnotherZipIsListedFirst() throws {
        let r = try XCTUnwrap(offered(tag: "v1.1.0",
                                      assets: ["Source.zip", "Helm-1.1.0.zip", "Helm-1.1.0.dmg"]))
        XCTAssertEqual(r.zipURL, "https://example.com/dl/Helm-1.1.0.zip")
        XCTAssertEqual(r.downloadURL, "https://example.com/dl/Helm-1.1.0.dmg")
    }

    /// The order the rule above must not depend on: the app's zip first is the
    /// same answer.
    func testTheZipWithTheAppsNameIsAnsweredWhenItIsListedFirst() throws {
        let r = try XCTUnwrap(offered(tag: "v1.1.0", assets: ["Helm-1.1.0.zip", "Source.zip"]))
        XCTAssertEqual(r.zipURL, "https://example.com/dl/Helm-1.1.0.zip")
    }

    /// A tag with no leading `v` names the same zip: the name is the tag with
    /// a leading `v` taken off, when it has one.
    func testATagWithoutALeadingVNamesTheSameZip() throws {
        let r = try XCTUnwrap(offered(tag: "1.1.0", assets: ["Source.zip", "Helm-1.1.0.zip"]))
        XCTAssertEqual(r.zipURL, "https://example.com/dl/Helm-1.1.0.zip")
    }

    /// A release with one zip answers that zip, whatever the zip is called: a
    /// release whose only zip has another name keeps its silent update.
    func testOneZipOfAnyNameIsTheAnswer() throws {
        let r = try XCTUnwrap(offered(tag: "v1.1.0", assets: ["Anything-at-all.zip", "Helm-1.1.0.dmg"]))
        XCTAssertEqual(r.zipURL, "https://example.com/dl/Anything-at-all.zip")
    }

    /// Several zips and none of them the app's: nothing is installed silently.
    /// The answer is no zip, which sends the person to the release page.
    func testSeveralZipsNoneWithTheAppsNameAnswerNoZip() throws {
        let withDmg = try XCTUnwrap(offered(tag: "v1.1.0",
                                            assets: ["Source.zip", "Docs.zip", "Helm-1.1.0.dmg"]))
        XCTAssertNil(withDmg.zipURL)
        XCTAssertEqual(withDmg.downloadURL, "https://example.com/dl/Helm-1.1.0.dmg",
                       "the manual download is still the dmg")

        let withoutDmg = try XCTUnwrap(offered(tag: "v1.1.0", assets: ["Source.zip", "Docs.zip"]))
        XCTAssertNil(withoutDmg.zipURL)
        XCTAssertNil(withoutDmg.downloadURL)
    }

    /// Exact, not a prefix: another version's zip and a prerelease's zip are
    /// not this release's.
    func testAZipNamedForAnotherVersionIsNotTheAppsZip() throws {
        let r = try XCTUnwrap(offered(tag: "v1.1.0",
                                      assets: ["Helm-1.1.0-dev.1.zip", "Helm-1.1.1.zip"]))
        XCTAssertNil(r.zipURL)
    }

    /// The prerelease the dev channel reads carries its suffix in the zip's
    /// name, because the version is the whole short version string.
    func testTheDevChannelFindsTheZipNamedForItsPrerelease() throws {
        let json = #"""
        [{"tag_name":"v0.7.1-dev.10","html_url":"https://example.com/r","body":"n","prerelease":true,
          "assets":[{"name":"Source.zip","browser_download_url":"https://example.com/dl/Source.zip"},
                    {"name":"Helm-0.7.1-dev.10.zip","browser_download_url":"https://example.com/dl/Helm-0.7.1-dev.10.zip"}]}]
        """#
        guard case .available(let r) = UpdateCheck.evaluateList(
            statusCode: 200, data: Data(json.utf8), currentVersion: "0.7.1-dev.9", channel: .dev)
        else { return XCTFail("expected .available") }
        XCTAssertEqual(r.zipURL, "https://example.com/dl/Helm-0.7.1-dev.10.zip")
    }
}

/// A release with the given tag, no assets and nothing else of interest.
private func aReleaseWithOnlyATag(_ tag: String) -> Data {
    Data(#"{"tag_name":"\#(tag)","html_url":"https://example.com/r","body":"n","assets":[]}"#.utf8)
}

/// A tag that reaches `evaluate` with nothing in it to read as a version is not
/// an update. A published tag is never deleted, so the answer to it is the
/// answer at every later check.
///
/// Its own class, and no row of `UpdateCheckTests`: a parser that stops the
/// process on such a tag ends the whole test process, so a filter that selects
/// this class alone is how the outcome is read.
final class ABadTagReachesEvaluateTests: XCTestCase {
    private func check(_ tag: String, file: StaticString = #filePath, line: UInt = #line) {
        let outcome = UpdateCheck.evaluate(statusCode: 200, data: aReleaseWithOnlyATag(tag),
                                           currentVersion: "1.0.0")
        XCTAssertEqual(outcome, .upToDate, "tag \(tag.debugDescription)", file: file, line: line)
    }

    func testLowercaseV() { check("v") }
    func testUppercaseV() { check("V") }
    func testDash() { check("-") }
    func testEmpty() { check("") }
}

/// The same tags met by a prerelease build. A prerelease build reports being
/// ahead of an older release, and such a tag compares as a final 0.0.0, older
/// than the build, so it must not be named as something the build is ahead of:
/// the About page would name `v`, `-` or nothing at all as the channel's latest.
///
/// Its own class, for the reason the class above is.
final class ABadTagMeetsAPrereleaseBuildTests: XCTestCase {
    private let running = "0.7.2-dev.34"

    private func evaluate(_ tag: String, channel: UpdateCheck.Channel) -> UpdateCheck.Outcome {
        UpdateCheck.evaluate(statusCode: 200, data: aReleaseWithOnlyATag(tag),
                             currentVersion: running, channel: channel)
    }

    private func check(_ tag: String, file: StaticString = #filePath, line: UInt = #line) {
        for channel in UpdateCheck.Channel.allCases {
            XCTAssertEqual(evaluate(tag, channel: channel), .upToDate,
                           "tag \(tag.debugDescription), \(channel)", file: file, line: line)
        }
    }

    func testLowercaseV() { check("v") }
    func testUppercaseV() { check("V") }
    func testDash() { check("-") }
    func testEmpty() { check("") }

    /// The control: the same build meeting an older tag that has a version in it
    /// does report being ahead, so the rows above are about the tag and not about
    /// a build that can never report it.
    func testAnOlderTagWithAVersionIsStillSomethingTheBuildIsAheadOf() {
        for channel in UpdateCheck.Channel.allCases {
            XCTAssertEqual(evaluate("v0.7.1", channel: channel), .ahead(newest: "v0.7.1"),
                           "\(channel)")
        }
    }
}
