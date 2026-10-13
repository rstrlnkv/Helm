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
         "assets":[{"name":"\(appZipName(forTag: tag))","browser_download_url":"https://x/\(tag).zip"}]}
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

    /// Beta reads one release, the one GitHub calls latest, and a prerelease is
    /// not offered to it even when that release is the one handed over.
    func testBetaIsNotOfferedAPrerelease() {
        let outcome = UpdateCheck.evaluate(
            statusCode: 200,
            data: Data(releaseJSON(tag: "v0.7.0-dev.2", prerelease: true).utf8),
            currentVersion: "0.6.1")
        XCTAssertEqual(outcome, .upToDate)
    }

    /// The app's Beta does not read the list; `evaluateList` takes a channel,
    /// and a channel that is not dev drops the prereleases from it.
    func testTheListReadingForBetaDropsPrereleases() {
        let json = "[\(releaseJSON(tag: "v0.7.0-dev.2", prerelease: true)),"
            + "\(releaseJSON(tag: "v0.6.1", prerelease: false))]"
        let outcome = UpdateCheck.evaluateList(statusCode: 200,
                                               data: Data(json.utf8),
                                               currentVersion: "0.6.1",
                                               channel: .beta)
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

/// The name the release script gives the app's zip: `Helm-`, the tag without
/// its leading `v`, and `.zip`.
private func appZipName(forTag tag: String) -> String {
    "Helm-\(tag.hasPrefix("v") ? String(tag.dropFirst()) : tag).zip"
}

/// One release as the API writes it, with the `prerelease` key present as
/// true, present as false, or absent.
private func releaseWithFlag(tag: String, prerelease: Bool?) -> String {
    let flag = prerelease.map { #""prerelease":\#($0),"# } ?? ""
    return """
    {"tag_name":"\(tag)","html_url":"https://x/\(tag)","body":"notes",\(flag)
     "assets":[{"name":"\(appZipName(forTag: tag))","browser_download_url":"https://x/\(tag).zip"}]}
    """
}

/// A list as the API writes it: the releases in the order given.
private func releaseList(_ releases: [(tag: String, prerelease: Bool?)]) -> Data {
    let items = releases.map { releaseWithFlag(tag: $0.tag, prerelease: $0.prerelease) }
    return Data("[\(items.joined(separator: ","))]".utf8)
}

/// What Beta is offered, called the way the app calls it: `evaluate`, with the
/// one release the latest endpoint returned.
///
/// A prerelease published without its flag is the case that matters. The tag
/// is the other place a release says what it is, so Beta reads both: a tag with
/// a suffix is not offered, and a release flagged as a prerelease is not
/// offered, whichever of the two the release forgot.
final class BetaRefusesAPrereleaseTests: XCTestCase {
    private func offer(tag: String, prerelease: Bool?) -> UpdateCheck.Outcome {
        UpdateCheck.evaluate(statusCode: 200,
                             data: Data(releaseWithFlag(tag: tag, prerelease: prerelease).utf8),
                             currentVersion: "0.6.1")
    }

    func testASuffixedTagWithTheFlagFalseIsNotOffered() {
        XCTAssertEqual(offer(tag: "v0.7.0-dev.2", prerelease: false), .upToDate)
    }

    func testASuffixedTagWithTheFlagAbsentIsNotOffered() {
        XCTAssertEqual(offer(tag: "v0.7.0-dev.2", prerelease: nil), .upToDate)
    }

    func testASuffixedTagWithTheFlagTrueIsNotOffered() {
        XCTAssertEqual(offer(tag: "v0.7.0-dev.2", prerelease: true), .upToDate)
    }

    func testATagWithoutASuffixWithTheFlagTrueIsNotOffered() {
        XCTAssertEqual(offer(tag: "v0.7.0", prerelease: true), .upToDate)
    }

    /// Any suffix is a prerelease, not only the dev one.
    func testAnotherSuffixIsNotOfferedEither() {
        XCTAssertEqual(offer(tag: "v0.7.0-rc.1", prerelease: false), .upToDate)
    }

    /// The positive control: without it every row above is satisfied by a Beta
    /// that offers nothing at all.
    func testAFinalReleaseIsStillOfferedWhetherTheFlagIsFalseOrAbsent() {
        for flag in [false, nil] as [Bool?] {
            guard case .available(let r) = offer(tag: "v0.7.0", prerelease: flag) else {
                return XCTFail("a final release with the flag \(String(describing: flag)) was not offered")
            }
            XCTAssertEqual(r.version, "v0.7.0")
        }
    }
}

/// The refusal above, in the list reading: Beta is handed a list, a release whose
/// tag carries a suffix is not offered whatever its flag says, and the final
/// release beside it still is.
final class TheListReadingForBetaRefusesAPrereleaseTests: XCTestCase {
    private func offer(_ releases: [(tag: String, prerelease: Bool?)]) -> UpdateCheck.Outcome {
        UpdateCheck.evaluateList(statusCode: 200, data: releaseList(releases),
                                 currentVersion: "0.6.1", channel: .beta)
    }

    func testASuffixedTagWithTheFlagFalseOrAbsentIsNotOffered() {
        for flag in [false, nil] as [Bool?] {
            XCTAssertEqual(offer([("v0.7.0-dev.2", flag)]), .upToDate,
                           "flag \(String(describing: flag))")
        }
    }

    func testAFinalReleaseBesideASuffixedTagIsTheOneOffered() {
        for flag in [false, nil] as [Bool?] {
            guard case .available(let r) = offer([("v0.7.0-dev.2", flag), ("v0.6.5", false)]) else {
                return XCTFail("the final release was not offered, flag \(String(describing: flag))")
            }
            XCTAssertEqual(r.version, "v0.6.5", "flag \(String(describing: flag))")
        }
    }
}

/// The dev channel reads the list and goes on being offered a `-dev.N` release
/// however the release is flagged: a refusal written for Beta must not be
/// written into the part of the check the two share.
final class DevKeepsItsPrereleasesTests: XCTestCase {
    private func offered(tag: String, prerelease: Bool?) -> UpdateCheck.Outcome {
        UpdateCheck.evaluateList(statusCode: 200,
                                 data: releaseList([(tag, prerelease)]),
                                 currentVersion: "0.6.1", channel: .dev)
    }

    func testASuffixedTagIsOfferedWhateverTheFlagSays() {
        for flag in [false, nil, true] as [Bool?] {
            guard case .available(let r) = offered(tag: "v0.7.0-dev.2", prerelease: flag) else {
                return XCTFail("a dev release with the flag \(String(describing: flag)) was not offered")
            }
            XCTAssertEqual(r.version, "v0.7.0-dev.2")
        }
    }

    func testAFlaggedPrereleaseWithoutASuffixIsOffered() {
        guard case .available(let r) = offered(tag: "v0.7.0", prerelease: true) else {
            return XCTFail("a flagged release without a suffix was not offered")
        }
        XCTAssertEqual(r.version, "v0.7.0")
    }
}

/// A tag with nothing in it to read as a version, inside a list. A published tag
/// is never deleted, so it sits in the list at every later check: alone it is
/// not an update, and beside a good release it must not stop that release from
/// being offered.
///
/// Its own class, apart from the rows above: a parser that stops the process on
/// such a tag ends the whole test process, so a filter that selects this class
/// alone is how the outcome is read.
final class ABadTagReachesEvaluateListTests: XCTestCase {
    private func check(_ bad: String, file: StaticString = #filePath, line: UInt = #line) {
        for channel in UpdateCheck.Channel.allCases {
            let alone = UpdateCheck.evaluateList(statusCode: 200, data: releaseList([(bad, false)]),
                                                 currentVersion: "1.0.0", channel: channel)
            XCTAssertEqual(alone, .upToDate, "\(bad.debugDescription) alone, \(channel)",
                           file: file, line: line)

            let orders: [[(tag: String, prerelease: Bool?)]] = [
                [(bad, false), ("v1.1.0", false)],
                [("v1.1.0", false), (bad, false)],
            ]
            for releases in orders {
                let beside = UpdateCheck.evaluateList(statusCode: 200, data: releaseList(releases),
                                                      currentVersion: "1.0.0", channel: channel)
                guard case .available(let r) = beside else {
                    XCTFail("\(bad.debugDescription) beside a good release, \(channel): \(beside)",
                            file: file, line: line)
                    continue
                }
                XCTAssertEqual(r.version, "v1.1.0",
                               "\(bad.debugDescription) beside a good release, \(channel)",
                               file: file, line: line)
            }
        }
    }

    func testLowercaseV() { check("v") }
    func testUppercaseV() { check("V") }
    func testDash() { check("-") }
    func testEmpty() { check("") }
}

/// The same tags in a list, met by a prerelease build. Such a build reports being
/// ahead of an older release; a tag with no version in it is not something to be
/// ahead of, alone or as the newest the list holds.
///
/// Its own class, for the reason the class above is.
final class ABadTagMeetsAPrereleaseBuildInAListTests: XCTestCase {
    private let running = "0.7.2-dev.34"

    private func answer(_ tag: String, channel: UpdateCheck.Channel) -> UpdateCheck.Outcome {
        UpdateCheck.evaluateList(statusCode: 200,
                                 data: releaseList([(tag, false)]),
                                 currentVersion: running, channel: channel)
    }

    private func check(_ tag: String, file: StaticString = #filePath, line: UInt = #line) {
        for channel in UpdateCheck.Channel.allCases {
            XCTAssertEqual(answer(tag, channel: channel), .upToDate,
                           "tag \(tag.debugDescription), \(channel)", file: file, line: line)
        }
    }

    func testLowercaseV() { check("v") }
    func testUppercaseV() { check("V") }
    func testDash() { check("-") }
    func testEmpty() { check("") }

    /// The control: an older tag with a version in it is what the build is ahead
    /// of, so the rows above are about the tag.
    func testAnOlderTagWithAVersionIsStillSomethingTheBuildIsAheadOf() {
        for channel in UpdateCheck.Channel.allCases {
            XCTAssertEqual(answer("v0.7.1", channel: channel), .ahead(newest: "v0.7.1"),
                           "\(channel)")
        }
    }
}

/// The channel was called "stable" in 0.7.0 and earlier, and that string is
/// sitting in the defaults of every installed copy. Reading it must not throw
/// those users onto the dev channel, and must not silently reset them either.
final class UpdateChannelMigrationTests: XCTestCase {
    func testLegacyStableReadsAsBeta() {
        XCTAssertEqual(UpdateCheck.Channel.stored("stable"), .beta)
    }

    func testBetaAndDevRoundTrip() {
        XCTAssertEqual(UpdateCheck.Channel.stored("beta"), .beta)
        XCTAssertEqual(UpdateCheck.Channel.stored("dev"), .dev)
    }

    func testUnsetOrUnknownIsTheSaferChannel() {
        XCTAssertEqual(UpdateCheck.Channel.stored(nil), .beta)
        XCTAssertEqual(UpdateCheck.Channel.stored("nightly"), .beta)
    }
}
