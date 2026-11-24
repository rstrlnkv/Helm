import XCTest
@testable import HelmRuntime

/// Tags of the form `vX.Y.Z.BETA.<build>` / `vX.Y.Z.DEV.<build>` (versioning
/// standard, rule 6) carry a build number, not a fifth version part. The
/// comparison must read the number against the RUNNING build.
///
/// `currentBuild: Int?`, nil = unknown: an old-form prerelease is then offered
/// the tag and a bare X.Y.Z is not; with a known build the build decides on an equal X.Y.Z.
/// Callers pass `AppBuild.buildNumber.flatMap { Int($0) }`.
private func newer(_ tag: String, _ version: String, _ build: Int?) -> Bool {
    UpdateVersion.isNewer(tag, than: version, currentBuild: build)
}

/// A releases list of bare tags, each a prerelease unless `prerelease` says otherwise.
private func list(_ tags: [String], prerelease: Bool? = true) -> Data {
    ReleaseJSON.list(tags.map {
        ReleaseJSON.release(tag: $0, page: "https://example.com/\($0)", prerelease: prerelease)
    })
}

final class UpdateBuildTagVersionTests: XCTestCase {
    func testTheTagOfTheRunningBuildIsNotNewer() {
        XCTAssertFalse(newer("v0.11.1.BETA.1620", "0.11.1", 1620))
    }
    func testTheSameTagIsNewerThanAnOldFormDevBuild() {
        XCTAssertTrue(newer("v0.11.1.BETA.1620", "0.11.1-dev.17", 1619))
    }
    func testALaterRunningBuildOfTheSameVersionIsNotOffered() {
        XCTAssertFalse(newer("v0.11.1.BETA.1620", "0.11.1", 1621))
    }
    func testOneBuildAboveTheRunningOneIsOffered() {
        XCTAssertTrue(newer("v0.11.1.BETA.1621", "0.11.1", 1620))
    }

    func testADevTagWithAHigherBuildIsNewer() {
        XCTAssertTrue(newer("v0.11.1.DEV.1700", "0.11.1", 1620))
        XCTAssertFalse(newer("v0.11.1.DEV.1500", "0.11.1", 1620))
    }
    func testAHigherVersionBeatsALowerBuildNumber() {
        XCTAssertTrue(newer("v0.11.2.BETA.1630", "0.11.1", 1700))
    }
    func testALowerVersionLosesToAHigherBuildNumber() {
        XCTAssertFalse(newer("v0.11.0.BETA.1900", "0.11.1", 1620))
    }
    func testAStableTagOfTheRunningVersionIsNotNewer() {
        XCTAssertFalse(newer("v0.11.1", "0.11.1", 1620))
        XCTAssertTrue(newer("v0.12.0", "0.11.1", 9999))
    }

    func testOldFormTagsIgnoreTheBuild() {
        XCTAssertTrue(newer("v0.7.0-dev.2", "0.7.0-dev.1", 5))
        XCTAssertFalse(newer("v0.7.0-dev.1", "0.7.0-dev.2", 9999))
        XCTAssertTrue(newer("v0.7.0", "0.7.0-dev.3", 1))
        XCTAssertFalse(newer("v0.6.1", "0.7.0-dev.1", 1))
    }
    func testAnUnknownBuildKeepsTodaysAnswers() {
        XCTAssertTrue(newer("v0.7.0", "0.6.1", nil))
        XCTAssertFalse(newer("v0.7.0", "0.7.0", nil))
        XCTAssertTrue(newer("v0.7.0-dev.2", "0.7.0-dev.1", nil))
    }
    func testAKnownBuildDecidesWhateverSuffixTheRunningVersionHas() {
        XCTAssertFalse(newer("v0.11.1.DEV.1500", "0.11.1-dev.17", 1700))
        XCTAssertFalse(newer("v0.11.1.BETA.1700", "0.11.1-dev.17", 1700))
    }
    func testTwoNewFormTagsOrderByBuild() {
        XCTAssertTrue(newer("v0.11.1.DEV.1700", "0.11.1-dev.17", 1619))
        XCTAssertTrue(newer("v0.11.1.BETA.1620", "0.11.1-dev.17", nil))
    }
}

final class UpdateBuildTagOutcomeTests: XCTestCase {
    private func one(_ tag: String) -> Data {
        ReleaseJSON.releaseData(tag: tag)
    }
    private func evaluate(_ tag: String, _ version: String, _ build: Int?) -> UpdateCheck.Outcome {
        UpdateCheck.evaluate(statusCode: 200, data: one(tag), currentVersion: version, currentBuild: build)
    }
    private func evaluateList(_ tags: [String], _ version: String, _ build: Int?) -> UpdateCheck.Outcome {
        UpdateCheck.evaluateList(statusCode: 200, data: list(tags), currentVersion: version,
                                 currentBuild: build, channel: .dev)
    }

    func testTheRunningBuildsOwnTagIsUpToDate() {
        XCTAssertEqual(evaluate("v0.11.1.BETA.1620", "0.11.1", 1620), .upToDate)
    }
    func testALaterRunningBuildIsUpToDateNotAhead() {
        XCTAssertEqual(evaluate("v0.11.1.BETA.1620", "0.11.1", 1621), .upToDate)
    }
    func testTheTagIsOfferedToTheOldFormDevBuild() {
        guard case .available(let r) = evaluate("v0.11.1.BETA.1620", "0.11.1-dev.17", 1619)
        else { return XCTFail("expected .available") }
        XCTAssertEqual(r.version, "v0.11.1.BETA.1620")
    }
    func testAHigherBuildOfTheSameVersionIsOffered() {
        guard case .available(let r) = evaluate("v0.11.1.DEV.1700", "0.11.1", 1620)
        else { return XCTFail("expected .available") }
        XCTAssertEqual(r.version, "v0.11.1.DEV.1700")
    }
    /// `.ahead` still fires when the running prerelease has a higher core than the newest tag.
    func testAheadStillFiresForAPrereleaseOfAHigherVersion() {
        XCTAssertEqual(evaluate("v0.11.1.BETA.1620", "0.11.2-dev.3", 1700),
                       .ahead(newest: "v0.11.1.BETA.1620"))
    }

    // Dev channel list.
    func testTheNewFormTagBeatsTheOldDevTagInTheList() {
        guard case .available(let r) = evaluateList(["v0.11.1-dev.17", "v0.11.1.BETA.1620"],
                                                    "0.11.1-dev.16", 1600)
        else { return XCTFail("expected .available") }
        XCTAssertEqual(r.version, "v0.11.1.BETA.1620")
        // Order of the list does not decide.
        guard case .available(let r2) = evaluateList(["v0.11.1.BETA.1620", "v0.11.1-dev.17"],
                                                     "0.11.1-dev.16", 1600)
        else { return XCTFail("expected .available") }
        XCTAssertEqual(r2.version, "v0.11.1.BETA.1620")
    }
    func testTheListNewestIsTheRunningBuildsTagSoNothingIsOffered() {
        XCTAssertEqual(evaluateList(["v0.11.1-dev.17", "v0.11.1.BETA.1620"], "0.11.1", 1620), .upToDate)
    }
    func testTheListPicksTheHighestBuildOfTheNewestVersion() {
        guard case .available(let r) = evaluateList(
            ["v0.11.1.BETA.1620", "v0.11.2.DEV.1650", "v0.11.2.DEV.1640", "v0.11.1-dev.17"],
            "0.11.1", 1620)
        else { return XCTFail("expected .available") }
        XCTAssertEqual(r.version, "v0.11.2.DEV.1650")
    }
}

/// The nil build against a final version, a build tag against a build tag,
/// and the order the list picker itself uses.
final class UpdateBuildTagGapTests: XCTestCase {
    /// An unknown build must not offer the tag of the running final version:
    /// that tag may be the running build, and every check would offer it again.
    func testAnUnknownBuildNeverOffersABuildTagOfTheRunningFinalVersion() {
        XCTAssertFalse(newer("v0.11.1.BETA.1620", "0.11.1", nil))
        XCTAssertFalse(newer("v0.11.1.DEV.1700", "0.11.1", nil))
        // Another core is still decided by the version alone.
        XCTAssertTrue(newer("v0.11.2.BETA.1620", "0.11.1", nil))
        XCTAssertFalse(newer("v0.11.0.BETA.1900", "0.11.1", nil))
    }

    /// Both sides build tags, same core: the build decides, strictly.
    func testTwoBuildTagsOfOneVersionCompareByBuildStrictly() {
        XCTAssertTrue(newer("v0.11.1.BETA.1620", "0.11.1.DEV.1619", 1))
        XCTAssertFalse(newer("v0.11.1.BETA.1620", "0.11.1.DEV.1620", 1))
        XCTAssertFalse(newer("v0.11.1.BETA.1620", "0.11.1.DEV.1621", 1))
    }

    /// Both sides build tags: the version decides before the build.
    func testTwoBuildTagsOfDifferentVersionsCompareByVersionFirst() {
        XCTAssertTrue(newer("v0.11.2.BETA.1500", "0.11.1.BETA.1600", 1))
        XCTAssertFalse(newer("v0.11.0.BETA.1900", "0.11.1.BETA.1600", 1))
    }

    private func picked(_ tags: [String]) -> String? {
        // A running version far below every tag, so the pick is offered.
        guard case .available(let r) = UpdateCheck.evaluateList(
            statusCode: 200, data: list(tags), currentVersion: "0.1.0", currentBuild: 1, channel: .dev)
        else { return nil }
        return r.version
    }

    /// The picker orders old-form prereleases of one core by ordinal, in both
    /// list orders (a picker that sees only the numeric core keeps the first).
    func testThePickerOrdersOldFormPrereleasesOfOneVersionByOrdinal() {
        XCTAssertEqual(picked(["v0.11.1-dev.9", "v0.11.1-dev.17"]), "v0.11.1-dev.17")
        XCTAssertEqual(picked(["v0.11.1-dev.17", "v0.11.1-dev.9"]), "v0.11.1-dev.17")
    }
    /// The picker orders build tags of one version by build, in both orders.
    func testThePickerOrdersBuildTagsOfOneVersionByBuildInBothListOrders() {
        XCTAssertEqual(picked(["v0.11.1.BETA.1620", "v0.11.1.BETA.1700"]), "v0.11.1.BETA.1700")
        XCTAssertEqual(picked(["v0.11.1.BETA.1700", "v0.11.1.BETA.1620"]), "v0.11.1.BETA.1700")
    }
}

/// Tags that split into nothing, a bare tag against a build tag in either list
/// order, and a signed build number.
final class UpdateBuildTagEdgeTests: XCTestCase {
    func testAnEmptyTagIsNoOfferAndNoCrash() {
        for tag in ["", "v", "-"] {
            let one = #"{"tag_name":"\#(tag)","html_url":"https://example.com/r","assets":[]}"#.data(using: .utf8)!
            XCTAssertEqual(UpdateCheck.evaluate(statusCode: 200, data: one, currentVersion: "0.11.1",
                                                currentBuild: 1620), .upToDate, tag)
            XCTAssertEqual(UpdateCheck.evaluateList(statusCode: 200, data: list([tag], prerelease: nil),
                                                    currentVersion: "0.11.1", currentBuild: 1620,
                                                    channel: .dev), .upToDate, tag)
        }
    }

    func testABuildTagBeatsABareTagOfTheSameCoreInBothListOrders() {
        for tags in [["v0.11.1.BETA.1700", "v0.11.1"], ["v0.11.1", "v0.11.1.BETA.1700"]] {
            guard case .available(let r) = UpdateCheck.evaluateList(
                statusCode: 200, data: list(tags, prerelease: nil), currentVersion: "0.11.1", currentBuild: 1620,
                channel: .dev)
            else { return XCTFail("expected .available for \(tags)") }
            XCTAssertEqual(r.version, "v0.11.1.BETA.1700")
        }
    }

    func testASignedBuildNumberIsNotABuildTag() {
        XCTAssertNil(UpdateVersion.buildTag("v0.11.1.BETA.-5"))
        XCTAssertNil(UpdateVersion.buildTag("v0.11.1.BETA.+5"))
        XCTAssertNil(UpdateVersion.buildTag("v+0.11.1.BETA.5"))
        XCTAssertEqual(UpdateVersion.buildTag("v0.11.1.BETA.5")?.build, 5)
    }
}
