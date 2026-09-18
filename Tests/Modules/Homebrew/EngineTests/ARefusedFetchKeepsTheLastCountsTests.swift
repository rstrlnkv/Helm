import XCTest
import HelmTestSupport
@testable import Module_Homebrew_Engine

/// **Everything here fails towards the order search already draws.** A refusal
/// is not a reading, and the one way to get that wrong is to record it as an
/// empty one: `[:]` is a perfectly well-formed answer meaning nobody installs
/// anything, and the ranking would believe it.
///
/// The other half is the clock. A fetch that did not complete must not stamp
/// one, or the next launch reads a refusal as a fresh reading and stops
/// retrying — and `deactivate()` runs on every route out of the app,
/// `applicationWillTerminate` included, so being cancelled mid-fetch is an
/// ordinary Tuesday rather than an edge case.
final class ARefusedFetchKeepsTheLastCountsTests: XCTestCase {

    private func directoryWithADayOldReading(_ label: String) throws -> URL {
        let directory = scratchDirectory(label)
        let url = directory.appendingPathComponent(FilePopularityStore.formulae.file)
        try countsDocument(["helm": 900]).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-90_000)],
                                              ofItemAtPath: url.path)
        // Fresh, so the only ask in these tests is the one they are about.
        try countsDocument(["figma": 40])
            .write(to: directory.appendingPathComponent(FilePopularityStore.casks.file))
        return directory
    }

    private func assertTheLastReadingStands(_ wire: PopularityWire, _ directory: URL,
                                            file: StaticString = #filePath,
                                            line: UInt = #line) async throws {
        let store = FilePopularityStore(directory: directory, transfer: wire.transfer)
        await store.refreshIfDue()

        XCTAssertEqual(store.readings().formulae.counts, ["helm": 900],
                       "a refusal replaced the reading it should have left alone",
                       file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(
            FilePopularityStore.formulae.file)), countsDocument(["helm": 900]),
                       "a refusal was written over the stored document",
                       file: file, line: line)

        let asked = wire.asked.count
        await store.refreshIfDue()
        XCTAssertEqual(wire.asked.count, asked * 2,
                       "a refusal stamped the clock, so the next launch will not try again",
                       file: file, line: line)
    }

    func testAServerErrorLeavesBothTheReadingAndTheClock() async throws {
        try await assertTheLastReadingStands(PopularityWire(status: 503, body: Data()),
                                             try directoryWithADayOldReading("counts-503"))
    }

    /// The endpoint moved and what answers now is a sign-in page: 200, and not
    /// a document this build can read.
    func testAShapeThisBuildCannotReadLeavesBothTheReadingAndTheClock() async throws {
        try await assertTheLastReadingStands(
            PopularityWire(status: 200, body: Data("<html>Sign in</html>".utf8)),
            try directoryWithADayOldReading("counts-html"))
    }

    func testSomethingFarTooLargeLeavesBothTheReadingAndTheClock() async throws {
        var huge = countsDocument(["helm": 1])
        huge.append(Data(repeating: 0x20, count: PopularityRefresh.sizeCeiling))
        try await assertTheLastReadingStands(PopularityWire(status: 200, body: huge),
                                             try directoryWithADayOldReading("counts-huge"))
    }

    /// No network, a refused connection, a deadline — and the cancellation that
    /// arrives when the app is quitting, which throws out of the same call and
    /// is the one this store meets most often.
    func testATransportFailureLeavesBothTheReadingAndTheClock() async throws {
        try await assertTheLastReadingStands(PopularityWire.offline(),
                                             try directoryWithADayOldReading("counts-offline"))
    }

    /// The first launch on every Mac, and every launch on one whose support
    /// folder was cleared out: it answers, it does not crash, and it invents no
    /// counts.
    ///
    /// **It does not pin nil against empty, and cannot.** `InstallCounts.none`
    /// *is* `InstallCounts(counts: [:])`, so at this layer the two are one
    /// value and this assertion would still pass if `load` started answering an
    /// empty reading instead of nil. The guard that really holds that
    /// distinction is `assertTheLastReadingStands` above, where a refusal
    /// turning into `[:]` replaces a stored reading and fails three ways.
    func testAMacWithNothingStoredAnswersWithoutInventingCounts() {
        let store = FilePopularityStore(directory: scratchDirectory("counts-empty"),
                                        transfer: PopularityWire.offline().transfer)
        XCTAssertEqual(store.readings(), PopularityReadings.none)
    }

    /// **The disk is read on the first ask and not in `init`.** The two
    /// documents are 850 KB of JSON — 30 ms of parse, measured — and `init`
    /// runs inside `makeEngine`, which the host calls on the main thread at
    /// launch for every module that is switched on. Reading a file that only
    /// appears after construction is the observable form of that claim.
    func testTheDocumentsAreNotParsedUntilSomebodyAsks() throws {
        let directory = scratchDirectory("counts-lazy")
        let store = FilePopularityStore(directory: directory,
                                        transfer: PopularityWire.offline().transfer)

        try countsDocument(["helm": 900])
            .write(to: directory.appendingPathComponent(FilePopularityStore.formulae.file))

        XCTAssertEqual(store.readings().formulae.counts, ["helm": 900],
                       "the store read the disk before anybody asked it for a reading")
    }

    /// **And a refresh with nothing due is not somebody asking.**
    ///
    /// This is the ordinary launch of an enabled module: `activate()` starts
    /// the refresh, both documents were cached this morning, and there is
    /// nothing to fetch. `refreshIfDue` used to open with one unconditional
    /// `readings()` — 850 KB of JSON parsed and 2.84 MiB of dictionary resident
    /// from that moment on, every launch, for a figure nobody had asked for.
    /// The only thing in there that wants a stored reading is the ETag gate,
    /// which is reached on a day a document is due.
    ///
    /// Observable the same way its sibling above is: a document rewritten
    /// afterwards is still the one the store answers with, which it could not
    /// be if the refresh had read and cached the earlier bytes.
    func testARefreshWithNothingDueParsesNothing() async throws {
        let directory = scratchDirectory("counts-not-parsed")
        for (endpoint, counts) in [(FilePopularityStore.formulae, ["helm": 900]),
                                   (FilePopularityStore.casks, ["figma": 40])] {
            try countsDocument(counts).write(to: directory.appendingPathComponent(endpoint.file))
        }
        let wire = PopularityWire.offline()
        let store = FilePopularityStore(directory: directory, transfer: wire.transfer)

        await store.refreshIfDue()

        // The subject first: a refresh that found something due would have
        // reached the disk for its own reasons and this would prove nothing.
        XCTAssertEqual(wire.asked.count, 0,
                       "something was due, so this test is not the ordinary launch it describes")

        try countsDocument(["helm": 1])
            .write(to: directory.appendingPathComponent(FilePopularityStore.formulae.file))
        XCTAssertEqual(store.readings().formulae.counts, ["helm": 1],
                       "refreshIfDue read and parsed both documents on a launch with nothing "
                       + "due — the cost the lazy load exists to avoid, paid anyway")
    }

    /// **The line drawn from the other side.** Everything above is a refusal
    /// that must not become `[:]`; this is `[:]` arriving as an answer, which
    /// must not be read as a refusal. `{"formulae":{}}` is Homebrew saying
    /// nobody installed anything over the window — a thing it is entitled to
    /// say — so it replaces the stored reading and is cached like any other
    /// document. Read it as a refusal instead and the store never writes it,
    /// so every launch from then on re-fetches the same document for ever.
    ///
    /// What it costs the person is nothing: search ranks against an empty
    /// reading exactly as it ranks with no reading at all, which is brew's own
    /// order.
    func testAnEmptyDocumentOffTheWireReplacesTheStoredReading() async throws {
        let directory = try directoryWithADayOldReading("counts-empty-document")
        let wire = PopularityWire(status: 200, body: countsDocument([:]))
        let store = FilePopularityStore(directory: directory, transfer: wire.transfer)

        await store.refreshIfDue()

        XCTAssertEqual(wire.asked.count, 1,
                       "the formula document was not fetched, so this case is not about what "
                       + "came back")
        XCTAssertEqual(store.readings().formulae.counts, [:],
                       "an empty document was treated as a refusal and the day-old reading "
                       + "kept — the store now believes counts it was told are gone")
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(
            FilePopularityStore.formulae.file)), countsDocument([:]),
                       "the empty document was not cached, so every launch from here re-fetches "
                       + "the same answer")
    }

    /// A cache file cut off mid-write by a power failure, or one some other
    /// program wrote: the store answers, does not crash, and invents no counts
    /// out of the wreckage.
    ///
    /// Same caveat as the case above — `PopularityReadings.none` is a reading
    /// with empty halves, so this cannot tell nil from `[:]`. What it does hold
    /// is that an unreadable file reaches nothing: no partial dictionary, no
    /// throw out of `readings()`. The nil-against-empty distinction is
    /// `assertTheLastReadingStands`'s, and the tag gate's own half of it is
    /// `testATagIsNotOfferedWhenTheDocumentItDescribesCannotBeRead`.
    func testACacheFileThisBuildCannotReadInventsNoCounts() throws {
        let directory = scratchDirectory("counts-corrupt")
        try Data("{\"formulae\":{\"helm\":[{\"cou".utf8)
            .write(to: directory.appendingPathComponent(FilePopularityStore.formulae.file))

        let store = FilePopularityStore(directory: directory,
                                        transfer: PopularityWire.offline().transfer)
        XCTAssertEqual(store.readings(), PopularityReadings.none)
    }
}
