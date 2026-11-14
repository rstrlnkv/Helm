import Darwin
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// What a background scan announces for a family of clones is what removing them
/// would free, the figure the page shows.
///
/// On APFS a clone shares its blocks with the file it was made from, so with one
/// of them staying the others return nothing. The notification sums the items'
/// bytes (`ScanChange.appearedBytes`), and every item carried its copy's own size,
/// so three clones announced the two copies' full sizes where removing them
/// gives back nothing.
///
/// **The fixture lives in the home directory**, as `StoredFolderMustBeHelmsOwnTests`
/// explains: `ScanRoot` refuses a root outside it.
/// Past defect: backlog row bgscan-clones.
final class ABackgroundFindingCountsAClonesOnceTests: XCTestCase {

    private var fixture: URL!
    private let size = 1_200_000

    override func setUpWithError() throws {
        fixture = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".helm-clone-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
    }

    private func scan() async throws -> ScanReport {
        let store = NamespacedStore(namespace: "duplicates", backing: InMemoryKeyValueStore())
        store.set(fixture.path, for: "folder")
        let engine = DuplicatesEngine(store: store, settings: SettingGuard(keys: TestKey()),
                                      trashing: neverTrashes)
        let report = await engine.backgroundScan()
        return try XCTUnwrap(report)
    }

    private func write(_ name: String) throws -> URL {
        let url = fixture.appendingPathComponent(name)
        try Data(repeating: 0x41, count: size).write(to: url)
        return url
    }

    private func clone(_ url: URL, as name: String) throws {
        guard clonefile(url.path, fixture.appendingPathComponent(name).path, 0) == 0 else {
            throw XCTSkip("this volume does not clone: errno \(errno)")
        }
    }

    func testThreeClonesAnnounceWhatThePageShows() async throws {
        let first = try write("a.bin")
        try clone(first, as: "b.bin")
        try clone(first, as: "c.bin")
        let report = try await scan()
        XCTAssertEqual(report.count, 2, "precondition: the scan produced a finding")
        XCTAssertEqual(report.bytes, 0, "precondition: the survivor holds the family")
        XCTAssertEqual(report.items.reduce(0) { $0 + $1.bytes }, report.bytes,
                       "the notification sums the items: \(report.items)")
    }

    func testThreeIndependentCopiesAnnounceTwoOfThem() async throws {
        for name in ["a.bin", "b.bin", "c.bin"] { _ = try write(name) }
        let report = try await scan()
        XCTAssertEqual(report.count, 2, "precondition: the scan produced a finding")
        let one = report.items.first?.bytes ?? 0
        XCTAssertGreaterThanOrEqual(one, size, "precondition: a copy has blocks to give back")
        XCTAssertEqual(report.items.reduce(0) { $0 + $1.bytes }, 2 * one)
        XCTAssertEqual(report.bytes, 2 * one)
    }

    /// The journal stored full sizes before this. The same paths scanned again
    /// at the corrected figure are not news.
    func testAPreviousScanInTodaysFormIsNotAFindingAgainstTheCorrectedOne() async throws {
        let first = try write("a.bin")
        try clone(first, as: "b.bin")
        try clone(first, as: "c.bin")
        let report = try await scan()
        let old = report.items.map { ScanItem(path: $0.path, bytes: size) }
        let journal = ScanJournal(directory: scratchDirectory("dup-journal"))
        let entry = { ScanEntry(at: Date(), bytes: 0, count: 2, seconds: 1) }
        journal.record(entry(), items: old, module: "duplicates")
        journal.record(entry(), items: report.items, module: "duplicates")
        XCTAssertNil(ScanNews.finding(in: journal.change(module: "duplicates"), floor: 1),
                     "a clone announced as news by the change of its own figure")

        // A family whose paths appeared is announced at the corrected figure.
        let fresh = ScanJournal(directory: scratchDirectory("dup-journal-fresh"))
        fresh.record(entry(), items: [], module: "duplicates")
        fresh.record(entry(), items: [ScanItem(path: "/x", bytes: size)], module: "duplicates")
        XCTAssertEqual(ScanNews.finding(in: fresh.change(module: "duplicates"), floor: 1)?.bytes, size)
    }
}
