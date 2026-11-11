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
    func testAnUnknownDateIsTakenOutOfTheLadderBeforeTheDateItIsMissingFrom() {
        for policy in KeepPolicy.allCases {
            let copies = [file("/Users/r/Documents/Archive/2019/deep.jpg", added: day(10)),
                          file("/Users/r/Documents/shallow.jpg")]

            XCTAssertEqual(SurvivingCopy.order(copies, by: rule(policy)).first?.path,
                           "/Users/r/Documents/shallow.jpg",
                           "\(policy): the copy with no date on record is the one that stays")
            XCTAssertEqual(SurvivingCopy.reason(among: copies, by: rule(policy)), .undated, """
                \(policy): the dateless copy of this pair is also the shallower one, so \
                the assertion above is green whether `.undated` kept it or `.depth` did — \
                and which rung answered is what both ladders are being asked about here. \
                Asking `reason` is what tells «the missing date is a rung above the date» \
                from «the missing date is silence and the depth rung carried on».
                """)
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

    // MARK: - Which copy stays: the order the policy hands back
    //
    // Which copy stays is the one decision in this module that costs something to
    // get wrong: the rest are baskets in one click.
    //
    // It used to be the alphabetically first path, which is not a belief about
    // anything — it just happened to be how the list was sorted for display. So
    // `~/Desktop/photo.jpg` beat `~/Documents/Archive/2019/photo.jpg`, because D
    // sorts before A, and Helm offered to delete the filed copy and keep the
    // clutter. The page said so plainly, which only moved the work onto the reader.
    //
    // **What the policy owns and what this section owns.** The tests above cover
    // the two ladders and the tier they rest on; these are the rungs each policy
    // shares, exercised through `.standard`, plus the promises the ordering makes
    // whatever the policy is — every copy comes back, none is invented, and the
    // answer does not depend on the order the walk found them in.

    private func sizedFile(_ path: String, added: Date? = nil, bytes: Int = 1_000) -> FileFacts {
        FileFacts(path: path, bytes: bytes, fileID: UInt64(abs(path.hashValue)), added: added)
    }
    private let standardRule = KeepRule(.standard)

    private func order(_ files: [FileFacts]) -> [String] {
        SurvivingCopy.order(files, by: standardRule).map(\.path)
    }

    // MARK: - The older copy wins

    func testTheOldestCopyStaysEvenWhenItsPathSortsLast() {
        let ordered = order([
            sizedFile("/Users/r/Pictures/photo.jpg", added: day(500)),
            sizedFile("/Users/r/Documents/Archive/2019/photo.jpg", added: day(10)),
        ])
        XCTAssertEqual(ordered.first, "/Users/r/Documents/Archive/2019/photo.jpg",
                       "the filed original stays; the later copy is the extra")
    }

    func testTheRestFollowInTheSameOrderSoTheListIsStable() {
        let ordered = order([
            sizedFile("/b.jpg", added: day(30)),
            sizedFile("/a.jpg", added: day(10)),
            sizedFile("/c.jpg", added: day(20)),
        ])
        XCTAssertEqual(ordered, ["/a.jpg", "/c.jpg", "/b.jpg"])
    }

    // MARK: - Then the shallower path

    /// Same day, or a filesystem that reports the same second for a batch that
    /// arrived together. Depth is the next thing that means something: a file
    /// four folders down was put somewhere on purpose.
    func testWithEqualDatesTheShallowerPathStays() {
        let ordered = order([
            sizedFile("/Users/r/Documents/Projects/2019/Old/photo.jpg", added: day(10)),
            sizedFile("/Users/r/Documents/photo.jpg", added: day(10)),
        ])
        XCTAssertEqual(ordered.first, "/Users/r/Documents/photo.jpg")
    }

    func testWithEqualDatesAndDepthAlphabeticalDecides() {
        let ordered = order([
            sizedFile("/Users/r/b.jpg", added: day(10)),
            sizedFile("/Users/r/a.jpg", added: day(10)),
        ])
        XCTAssertEqual(ordered.first, "/Users/r/a.jpg")
    }

    // MARK: - When the date is not there

    /// **This test asserted the opposite twice, and the second time its fixture
    /// could not tell.** It first read a blank date as a *loss* for the copy it
    /// was missing from, so one blank settled a group outright and every rung
    /// below — where the file sits, how deep it is — was never asked. It was then
    /// rewritten as «silence settles nothing, the ladder carries on», and the
    /// copy without a date was also the shallower one: green whether the missing
    /// date decided or the depth below it did.
    ///
    /// Neither reading is the rule. `KeepReason.undated` is a rung of its own,
    /// above the date it is missing from, and the copy nothing records the
    /// arrival of is the copy that stays — because what this module does with the
    /// rest is offer them for the Trash. Which rung answered is a separate
    /// question from which copy stays, so it is asked separately: `reason` names
    /// it, and it is what the group header says out loud.
    func testAnUnknownDateIsARungOfItsOwnAndTheCopyItIsMissingFromStays() {
        let copies = [sizedFile("/Users/r/Documents/Archive/z.jpg", added: day(400)),
                      sizedFile("/Users/r/Documents/a.jpg")]

        XCTAssertEqual(order(copies).first, "/Users/r/Documents/a.jpg",
                       "the copy whose arrival nothing recorded is the one that stays")
        XCTAssertEqual(SurvivingCopy.reason(among: copies, by: standardRule), .undated, """
            and the rung that kept it is the missing date. This fixture's dateless copy \
            is also its shallower one, so «which copy stays» is green here whichever of \
            the two rungs decided — `.depth` would mean the group header says «kept: the \
            shorter path» about a copy that stays for a different reason entirely, and \
            `.date` would mean it says «arrived first» about a copy nothing on this Mac \
            knows the arrival of.
            """)
    }

    func testWithNoDatesAtAllTheShallowerPathStays() {
        let ordered = order([
            sizedFile("/Users/r/Documents/Projects/Old/photo.jpg"),
            sizedFile("/Users/r/Documents/photo.jpg"),
        ])
        XCTAssertEqual(ordered.first, "/Users/r/Documents/photo.jpg")
    }

    // MARK: - It always answers

    func testEveryPathSurvivesTheOrderingAndNoneIsInventedOrLost() {
        let paths = ["/a/b/c.jpg", "/a/c.jpg", "/z.jpg", "/a/b/a.jpg"]
        let ordered = order(paths.map { sizedFile($0, added: day(7)) })
        XCTAssertEqual(Set(ordered), Set(paths))
        XCTAssertEqual(ordered.count, paths.count)
    }

    /// Two files whose facts are identical in every way the rule reads must
    /// still come back in one fixed order, or the row moves between scans.
    func testTheOrderDoesNotDependOnTheInputOrder() {
        let files = [sizedFile("/a/x.jpg", added: day(3)), sizedFile("/b/x.jpg", added: day(3))]
        XCTAssertEqual(order(files), order(files.reversed()))
    }

    /// The copies come back whole, not as paths the caller has to look up again:
    /// the size, the clone family and the date travel with each one.
    func testTheOrderHandsBackTheCopiesThemselves() {
        let ordered = SurvivingCopy.order([sizedFile("/late.jpg", added: day(9), bytes: 20),
                                           sizedFile("/early.jpg", added: day(1), bytes: 10)],
                                          by: standardRule)
        XCTAssertEqual(ordered.map(\.bytes), [10, 20])
        XCTAssertEqual(ordered.first?.added, day(1))
    }

    func testOneFileIsItsOwnSurvivor() {
        XCTAssertEqual(order([sizedFile("/only.jpg")]), ["/only.jpg"])
    }

    func testNoFilesIsNoPaths() {
        XCTAssertTrue(order([]).isEmpty)
    }
}
