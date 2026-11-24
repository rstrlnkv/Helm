import XCTest
import HelmTestSupport
@testable import Module_Homebrew_Engine

/// **Everything here fails towards the order search already draws.** A refusal
/// is not a reading, and the one way to get that wrong is to record it as an
/// empty one: `[:]` is a perfectly well-formed answer meaning nobody installs
/// anything, and the ranking would believe it.
///
/// A fetch that did not complete stamps no clock, or the next launch reads a
/// refusal as a fresh reading and stops retrying. `deactivate()` runs on every
/// route out of the app, so a cancellation mid-fetch is ordinary.
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

    /// No network, a refused connection, a deadline, and the cancellation that
    /// arrives when the app quits, the one this store meets most often.
    func testATransportFailureLeavesBothTheReadingAndTheClock() async throws {
        try await assertTheLastReadingStands(PopularityWire.offline(),
                                             try directoryWithADayOldReading("counts-offline"))
    }

    /// The first launch on every Mac: it answers, does not crash, and invents
    /// no counts. `InstallCounts.none` *is* `InstallCounts(counts: [:])`, so this
    /// cannot tell nil from empty; `assertTheLastReadingStands` holds that.
    func testAMacWithNothingStoredAnswersWithoutInventingCounts() {
        let store = FilePopularityStore(directory: scratchDirectory("counts-empty"),
                                        transfer: PopularityWire.offline().transfer)
        XCTAssertEqual(store.readings(), PopularityReadings.none)
    }

    /// **The disk is read on the first ask and not in `init`.** The two
    /// documents are 850 KB of JSON, and `init` runs inside `makeModule` on the
    /// main thread at launch. A file that only appears after construction is
    /// read: the observable form of that.
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
    /// The ordinary launch of an enabled module: `activate()` starts the
    /// refresh, both documents are cached, nothing is due. Only the ETag gate
    /// wants a stored reading, and it is reached only on a day a document is
    /// due. A document rewritten afterwards is still the one the store answers
    /// with, which it could not be had the refresh read the earlier bytes.
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

    /// **`[:]` arriving as an answer is not a refusal.** `{"formulae":{}}` is
    /// Homebrew saying nobody installed anything over the window, so it replaces
    /// the stored reading and is cached. Read as a refusal it is never written,
    /// and every launch re-fetches it. Search ranks against an empty reading as
    /// with none, in brew's own order.
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
    /// `PopularityReadings.none` has empty halves, so this cannot tell nil from
    /// `[:]`; it holds that an unreadable file reaches nothing: no partial
    /// dictionary, no throw out of `readings()`.
    func testACacheFileThisBuildCannotReadInventsNoCounts() throws {
        let directory = scratchDirectory("counts-corrupt")
        try Data("{\"formulae\":{\"helm\":[{\"cou".utf8)
            .write(to: directory.appendingPathComponent(FilePopularityStore.formulae.file))

        let store = FilePopularityStore(directory: directory,
                                        transfer: PopularityWire.offline().transfer)
        XCTAssertEqual(store.readings(), PopularityReadings.none)
    }
}
