import XCTest
@testable import HelmRuntime

/// `ScanJournal.record` on a realistic list — `~/Documents` measured 6900
/// items. Each call rotates `current.json` to `previous.json`, writes a fresh
/// `current.json`, and rewrites the (30-entry, bounded) `journal.json`. The
/// concern this answers: is the per-write cost dominated by the bounded
/// journal list, or by the unbounded item lists — because only one of those
/// grows with the size of what was scanned.
///
/// Report only, gated because it does real file I/O whose timing is
/// machine-dependent — `HELM_BENCH=1 swift test --filter ScanJournalRecordBenchmark`.
final class ScanJournalRecordBenchmark: XCTestCase {

    private var directory: URL!
    private var journal: ScanJournal!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("scan-journal-bench-\(UUID().uuidString)", isDirectory: true)
        journal = ScanJournal(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func items(_ n: Int) -> [ScanItem] {
        (0..<n).map {
            ScanItem(path: "/Users/person/Documents/Project\($0 % 200)/file-\($0).dat",
                     bytes: 1000 + $0)
        }
    }

    private func entry(_ seconds: TimeInterval) -> ScanEntry {
        ScanEntry(at: Date(timeIntervalSince1970: 1_785_600_000 + seconds),
                  bytes: 12_000_000, count: 6900, seconds: 10.1, startedByHand: false)
    }

    private func bench(itemCount: Int, calls: Int) throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let list = items(itemCount)
        // One call to establish `current.json` before timing starts, so the
        // measured calls all pay the realistic steady-state cost — rotating an
        // existing file rather than writing the first one from nothing.
        journal.record(entry(0), items: list, module: "bench")

        var total: TimeInterval = 0
        for i in 1...calls {
            let start = Date()
            journal.record(entry(TimeInterval(i) * 60), items: list, module: "bench")
            total += Date().timeIntervalSince(start)
        }
        let currentSize = (try? FileManager.default
            .attributesOfItem(atPath: journal.listURL(module: "bench", .current).path)[.size]
            as? Int) ?? nil

        print(String(format: "ScanJournal.record at %d items: %.4f s/call average over %d calls "
                     + "(current.json = %@ KB)",
                     itemCount, total / Double(calls), calls,
                     currentSize.map { String($0 / 1024) } ?? "?"))
    }

    func testAtDocumentsScale() throws {
        try bench(itemCount: 6900, calls: 10)
    }

    func testAtTenTimesDocumentsScale() throws {
        try bench(itemCount: 69_000, calls: 5)
    }
}
