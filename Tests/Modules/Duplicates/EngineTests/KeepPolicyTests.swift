import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// The two beliefs about what an extra copy *is*, and the one fact underneath
/// both of them.
///
/// Measured on a live engine before this existed: a file downloaded into
/// `~/Downloads` and then filed into `~/Pictures` came back with the download
/// as the copy that stays, because it arrived first — so Helm offered to delete
/// the copy somebody had deliberately put away. Дата решала, а не тайбрейк: on
/// APFS two copies never share a date added (0,29 ms apart on parallel `cp`),
/// so the depth rung below it was never reached.
final class KeepPolicyTests: XCTestCase {

    // MARK: - The stored spelling

    /// The raw values reach `com.helm.app.plist` and are sealed there, so they
    /// are stored data and not a name anybody may tidy. Recorded here the way
    /// `StoreNamespacesAreModuleIdsTests` records the module ids: a rename is a
    /// person's settings silently reverting to the default.
    func testTheStoredSpellingOfEachPolicyIsTheOneThatShipped() {
        XCTAssertEqual(KeepPolicy.byPlace.rawValue, "place")
        XCTAssertEqual(KeepPolicy.byDate.rawValue, "date")
        XCTAssertEqual(Set(KeepPolicy.allCases.map(\.rawValue)), ["place", "date"])
    }

    func testAMacThatWasNeverAskedGetsThePlacePolicy() {
        XCTAssertEqual(KeepPolicy.standard, .byPlace)
    }

    // MARK: - Which folders are transit

    private let transit = TransitFolders(roots: ["/Users/r/Downloads",
                                                 "/Users/r/Desktop"])

    func testAFileInsideATransitFolderIsInTransit() {
        XCTAssertTrue(transit.holds("/Users/r/Downloads/photo.jpg"))
        XCTAssertTrue(transit.holds("/Users/r/Desktop/Screenshots/one.png"))
    }

    func testAFileOutsideThemIsFiled() {
        XCTAssertFalse(transit.holds("/Users/r/Pictures/photo.jpg"))
        XCTAssertFalse(transit.holds("/Users/r/Documents/Downloads-notes.txt"))
    }

    /// A prefix is not a folder. `~/DownloadsArchive` is somewhere somebody
    /// files things, and it begins with the whole of `~/Downloads`.
    func testAFolderWhoseNameMerelyBeginsWithATransitFolderIsFiled() {
        XCTAssertFalse(transit.holds("/Users/r/DownloadsArchive/photo.jpg"))
    }

    /// The boot volume is case-insensitive, so the same folder has more than one
    /// spelling and a plain `hasPrefix` sees two different places.
    func testTheComparisonFoldsCaseTheWayTheVolumeDoes() {
        XCTAssertTrue(transit.holds("/Users/r/downloads/photo.jpg"))
    }

    /// **Downloads gets moved.** Somebody points it at an external drive and
    /// leaves a link behind, and `FileManager` still answers with the link —
    /// while the walk, which never follows one, answers with the real path.
    /// `ScanRoot.resolve` records what the two spellings cost when only one of
    /// them was judged.
    func testATransitFolderReachedThroughALinkIsStillTransit() throws {
        let scratch = scratchDirectory("keep-policy-link")
        let real = scratch.appendingPathComponent("Elsewhere")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = scratch.appendingPathComponent("Downloads")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let moved = TransitFolders(roots: [link.path])

        XCTAssertTrue(moved.holds(real.appendingPathComponent("photo.jpg").path),
                      "the walk reports the real path; the link is what FileManager answers")
        XCTAssertTrue(moved.holds(link.appendingPathComponent("photo.jpg").path))
    }

    /// The tier is macOS's answer, never a literal: `~/Downloads` is a name in
    /// English and a place this Mac may have moved.
    func testTheSystemTierIsTheFoldersMacOSNames() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let downloads = try FileManager.default.url(for: .downloadsDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil, create: false)
        let desktop = try FileManager.default.url(for: .desktopDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil, create: false)

        XCTAssertTrue(TransitFolders.system
            .holds(downloads.appendingPathComponent("photo.jpg").path))
        XCTAssertTrue(TransitFolders.system
            .holds(desktop.appendingPathComponent("photo.jpg").path))
        XCTAssertTrue(TransitFolders.system.holds(
            home.appendingPathComponent("Public/Drop Box/photo.jpg").path),
            "what somebody else dropped on this Mac is in transit too")
        XCTAssertFalse(TransitFolders.system.holds(
            home.appendingPathComponent("Pictures/photo.jpg").path))
    }

    // MARK: - The two ladders

    private func file(_ path: String, added: Date? = nil) -> FileFacts {
        FileFacts(path: path, bytes: 1_000, fileID: UInt64(abs(path.hashValue)), added: added)
    }
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

    private func rule(_ policy: KeepPolicy) -> KeepRule {
        KeepRule(policy, transit: transit)
    }

    private let inTransit = "/Users/r/Downloads/photo.jpg"
    private let filedDeepAndLater = "/Users/r/Pictures/2019/Trips/photo.jpg"

    /// The measurement that started this: the download arrived first and is
    /// shallower, and under «по месту» it still loses to the copy somebody put
    /// away.
    func testUnderThePlacePolicyTheFiledCopyStaysHoweverEarlyTheDownloadArrived() {
        let ordered = SurvivingCopy.order([file(inTransit, added: day(10)),
                                           file(filedDeepAndLater, added: day(500))],
                                          by: rule(.byPlace))
        XCTAssertEqual(ordered.first?.path, filedDeepAndLater)
    }

    /// The same two files, the other belief: whoever got here first is the
    /// original, wherever it sits.
    func testUnderTheDatePolicyTheEarlierCopyStaysWhereverItSits() {
        let ordered = SurvivingCopy.order([file(filedDeepAndLater, added: day(500)),
                                           file(inTransit, added: day(10))],
                                          by: rule(.byDate))
        XCTAssertEqual(ordered.first?.path, inTransit)
    }

    /// Inside one tier the place rung says nothing, and the policies agree.
    func testWithinOneTierBothPoliciesKeepTheEarlierCopy() {
        for policy in KeepPolicy.allCases {
            let ordered = SurvivingCopy.order(
                [file("/Users/r/Pictures/late.jpg", added: day(500)),
                 file("/Users/r/Documents/early.jpg", added: day(10))],
                by: rule(policy))
            XCTAssertEqual(ordered.first?.path, "/Users/r/Documents/early.jpg",
                           "\(policy): nothing separates these two but the date")
        }
    }

    /// Two downloads of the same thing: the place rung cannot choose between
    /// them either, so the date decides under both policies.
    func testTwoCopiesInTransitAreSeparatedByTheDateUnderBothPolicies() {
        for policy in KeepPolicy.allCases {
            let ordered = SurvivingCopy.order(
                [file("/Users/r/Downloads/photo-1.jpg", added: day(500)),
                 file("/Users/r/Desktop/photo.jpg", added: day(10))],
                by: rule(policy))
            XCTAssertEqual(ordered.first?.path, "/Users/r/Desktop/photo.jpg",
                           "\(policy): both are in transit, so the tier is silent")
        }
    }

    // MARK: - An unknown date is neutral

    /// A volume that does not record when a file was added reports nothing, and
    /// nothing is not evidence either way. It used to be a win for the copy we
    /// knew something about — which handed the whole decision to a fact the
    /// filesystem happened to keep, and skipped every rung below it.
    func testAnUnknownDateDecidesNothingAndTheLadderCarriesOn() {
        for policy in KeepPolicy.allCases {
            let ordered = SurvivingCopy.order(
                [file("/Users/r/Documents/Archive/2019/deep.jpg", added: day(10)),
                 file("/Users/r/Documents/shallow.jpg")],
                by: rule(policy))
            XCTAssertEqual(ordered.first?.path, "/Users/r/Documents/shallow.jpg",
                           "\(policy): one date and one blank separate nothing, "
                           + "so the shallower path stays")
        }
    }

    /// And the tier still speaks over a copy whose date is unknown — the place
    /// rung reads the path, which is never missing.
    func testAnUnknownDateDoesNotStopThePlaceRung() {
        let ordered = SurvivingCopy.order([file(inTransit),
                                           file("/Users/r/Pictures/photo.jpg")],
                                          by: rule(.byPlace))
        XCTAssertEqual(ordered.first?.path, "/Users/r/Pictures/photo.jpg")
    }

    // MARK: - Why this copy stays

    /// The group header has to say what decided, because one of the answers is a
    /// coin toss and a person reading «this one stays» deserves to know when
    /// nothing but the alphabet chose it.
    func testTheReasonNamesTheRungThatSeparatedTheSurvivorFromTheNextBest() {
        XCTAssertEqual(SurvivingCopy.reason(among: [file(inTransit, added: day(10)),
                                                    file(filedDeepAndLater, added: day(500))],
                                            by: rule(.byPlace)), .place)
        XCTAssertEqual(SurvivingCopy.reason(among: [file(inTransit, added: day(10)),
                                                    file(filedDeepAndLater, added: day(500))],
                                            by: rule(.byDate)), .date)
        XCTAssertEqual(SurvivingCopy.reason(among: [file("/Users/r/a/deep/x.jpg", added: day(1)),
                                                    file("/Users/r/x.jpg", added: day(1))],
                                            by: rule(.byPlace)), .depth)
        XCTAssertEqual(SurvivingCopy.reason(among: [file("/Users/r/b.jpg", added: day(1)),
                                                    file("/Users/r/a.jpg", added: day(1))],
                                            by: rule(.byPlace)), .name,
                       "alike in every way the rule can see — the alphabet is a coin toss")
    }

    /// It is about the survivor and the copy that came closest, not about the
    /// weakest one in the group: three copies where the runner-up is separated
    /// by the alphabet and the third by its place.
    func testTheReasonIsAboutTheNextBestCopyRatherThanTheWholeGroup() {
        let reason = SurvivingCopy.reason(among: [file("/Users/r/b.jpg", added: day(1)),
                                                  file("/Users/r/a.jpg", added: day(1)),
                                                  file(inTransit, added: day(1))],
                                          by: rule(.byPlace))
        XCTAssertEqual(reason, .name)
    }

    func testACopyWithNothingToBeComparedAgainstHasNoReason() {
        XCTAssertNil(SurvivingCopy.reason(among: [file("/only.jpg")], by: rule(.byPlace)))
        XCTAssertNil(SurvivingCopy.reason(among: [FileFacts](), by: rule(.byPlace)))
    }
}
