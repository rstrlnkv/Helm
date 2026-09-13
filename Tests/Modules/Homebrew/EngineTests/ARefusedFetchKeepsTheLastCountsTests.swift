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
    /// folder was cleared out.
    func testAMacWithNothingStoredHasNoReadingsRatherThanEmptyOnes() {
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

    /// A cache file cut off mid-write by a power failure, or one some other
    /// program wrote. Reading it is nil, and nil is not zero.
    func testACacheFileThisBuildCannotReadIsNoReadingAtAll() throws {
        let directory = scratchDirectory("counts-corrupt")
        try Data("{\"formulae\":{\"helm\":[{\"cou".utf8)
            .write(to: directory.appendingPathComponent(FilePopularityStore.formulae.file))

        let store = FilePopularityStore(directory: directory,
                                        transfer: PopularityWire.offline().transfer)
        XCTAssertEqual(store.readings(), PopularityReadings.none)
    }
}
