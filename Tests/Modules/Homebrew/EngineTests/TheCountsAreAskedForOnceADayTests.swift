import XCTest
import HelmTestSupport
@testable import Module_Homebrew_Engine

/// **`activate()` runs at launch for every module that is switched on**, so the
/// gate is the whole difference between two public documents a day and two on
/// every launch — and a person who opens Helm six times in a morning is not
/// unusual.
///
/// The clock is the cache file's own modification date. Nothing else is kept:
/// a separate "last refreshed" note would be a second fact to keep true, and
/// the file is already stamped by the write that made it.
final class TheCountsAreAskedForOnceADayTests: XCTestCase {

    private func madeOn(_ directory: URL, _ wire: PopularityWire) -> FilePopularityStore {
        FilePopularityStore(directory: directory, transfer: wire.transfer)
    }

    /// A cached document with a modification date `age` in the past.
    @discardableResult
    private func cache(_ endpoint: FilePopularityStore.Endpoint, in directory: URL,
                       counts: [String: Int], age: TimeInterval) throws -> URL {
        let url = directory.appendingPathComponent(endpoint.file)
        try countsDocument(counts).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)],
                                              ofItemAtPath: url.path)
        return url
    }

    func testAReadingFromThisMorningIsNotAskedAboutAgain() async throws {
        let directory = scratchDirectory("counts-fresh")
        try cache(FilePopularityStore.formulae, in: directory, counts: ["helm": 900], age: 3600)
        try cache(FilePopularityStore.casks, in: directory, counts: ["figma": 40], age: 3600)
        let wire = PopularityWire(status: 200, body: countsDocument(["other": 1]))

        let store = madeOn(directory, wire)
        await store.refreshIfDue()

        XCTAssertEqual(wire.asked.count, 0,
                       "a reading an hour old was asked about again — the daily gate is not holding")
        XCTAssertEqual(store.readings().formulae.counts, ["helm": 900])
        XCTAssertEqual(store.readings().casks.counts, ["figma": 40])
    }

    func testADayOldReadingIsReplacedAndBothHalvesLandTogether() async throws {
        let directory = scratchDirectory("counts-due")
        try cache(FilePopularityStore.formulae, in: directory, counts: ["helm": 900], age: 90_000)
        try cache(FilePopularityStore.casks, in: directory, counts: ["figma": 40], age: 90_000)
        let wire = PopularityWire { request in
            let cask = request.url!.absoluteString.contains("cask")
            return (200, countsDocument(cask ? ["figma": 99] : ["helm": 1000]), ["ETag": "\"v2\""])
        }

        let store = madeOn(directory, wire)
        await store.refreshIfDue()

        XCTAssertEqual(wire.asked.count, 2)
        // One call, both halves — a search ranks two result lists against one
        // reading or against two, and there is no way to tell afterwards which
        // it had.
        let readings = store.readings()
        XCTAssertEqual(readings.formulae.counts, ["helm": 1000])
        XCTAssertEqual(readings.casks.counts, ["figma": 99])
        // And the next launch reads them without waiting for a network.
        XCTAssertEqual(madeOn(directory, PopularityWire.offline()).readings().formulae.counts,
                       ["helm": 1000])
    }

    func testTheTagIsStoredAndOfferedBackOnTheNextAsk() async throws {
        let directory = scratchDirectory("counts-tag")
        try cache(FilePopularityStore.formulae, in: directory, counts: ["helm": 900], age: 90_000)
        // Fresh, so the only ask in this test is the one it is about.
        try cache(FilePopularityStore.casks, in: directory, counts: ["figma": 40], age: 0)
        let first = PopularityWire(status: 200, body: countsDocument(["helm": 1000]), etag: "\"v2\"")
        await madeOn(directory, first).refreshIfDue()

        XCTAssertNil(first.asked.first?.value(forHTTPHeaderField: "If-None-Match"),
                     "a tag was offered before one had ever been stored")

        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-90_000)],
            ofItemAtPath: directory.appendingPathComponent(FilePopularityStore.formulae.file).path)
        let second = PopularityWire(status: 304, body: Data())
        await madeOn(directory, second).refreshIfDue()

        XCTAssertEqual(second.asked.first?.value(forHTTPHeaderField: "If-None-Match"), "\"v2\"")
    }

    /// **A tag is a claim about a body this Mac still has.** With the document
    /// gone and the tag left behind, offering it earns a 304 — "what you have
    /// is current" — about nothing at all, and the readings would stay empty
    /// with the store believing itself up to date.
    func testATagIsNotOfferedWhenTheDocumentItDescribesIsGone() async throws {
        let directory = scratchDirectory("counts-orphan-tag")
        try cache(FilePopularityStore.casks, in: directory, counts: ["figma": 40], age: 0)
        try Data("\"v2\"".utf8)
            .write(to: directory.appendingPathComponent(FilePopularityStore.formulae.file + ".etag"))
        let wire = PopularityWire(status: 200, body: countsDocument(["helm": 1000]))

        let store = madeOn(directory, wire)
        await store.refreshIfDue()

        XCTAssertNil(wire.asked.first?.value(forHTTPHeaderField: "If-None-Match"),
                     "a tag was offered for a document that is not on this Mac any more")
        XCTAssertEqual(store.readings().formulae.counts, ["helm": 1000])
    }

    /// A 304 is the ordinary answer on the second day, and it is the one answer
    /// that keeps the reading *and* spends the day: nothing has changed, so
    /// asking again this afternoon would learn nothing.
    func testAnUnchangedAnswerKeepsTheReadingAndStillSpendsTheDay() async throws {
        let directory = scratchDirectory("counts-304")
        try cache(FilePopularityStore.formulae, in: directory, counts: ["helm": 900], age: 90_000)
        try cache(FilePopularityStore.casks, in: directory, counts: ["figma": 40], age: 0)
        let wire = PopularityWire(status: 304, body: Data())

        let store = madeOn(directory, wire)
        await store.refreshIfDue()
        XCTAssertEqual(store.readings().formulae.counts, ["helm": 900],
                       "a 304 emptied the reading it exists to confirm")

        await store.refreshIfDue()
        XCTAssertEqual(wire.asked.count, 1,
                       "the unchanged answer did not stamp the clock, so the next ask came straight away")
    }
}
