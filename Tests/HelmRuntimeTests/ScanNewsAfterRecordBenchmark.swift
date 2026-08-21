import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// What the unattended path actually pays on every tick, now that it has a
/// second reader.
///
/// `ScanJournalRecordBenchmark` prices `journal.record(...)` alone. Since
/// `ScanCoordinator.run` gained `tellSomebodyWhatAppeared(in:)`
/// (`ScanCoordinator.swift`), every finished background scan follows that write
/// with `journal.change(module:)` — which reads `current.json` and
/// `previous.json` straight back off disk and decodes both, immediately after
/// `record` wrote (and rotated) the very same two files. This prices that
/// second half beside the first, so the two together are what a tick actually
/// costs rather than only the half that already had a bench.
///
/// Report only — timing depends on the machine, the house rule for anything
/// gated behind `HELM_BENCH=1`.
///
/// `HELM_BENCH=1 swift test --filter ScanNewsAfterRecordBenchmark`
final class ScanNewsAfterRecordBenchmark: XCTestCase {

    private var directory: URL!
    private var journal: ScanJournal!

    override func setUp() {
        super.setUp()
        directory = scratchDirectory("scan-news-bench")
        journal = ScanJournal(directory: directory)
    }

    private func items(_ n: Int) -> [ScanItem] {
        (0..<n).map {
            ScanItem(path: "/Users/person/Documents/Project\($0 % 200)/file-\($0).dat",
                     bytes: 1000 + $0)
        }
    }

    private func entry(_ seconds: TimeInterval) -> ScanEntry {
        ScanEntry(at: Date(timeIntervalSince1970: 1_785_600_000 + seconds),
                  bytes: 12_000_000, count: 6900, seconds: 10.1)
    }

    private func bench(itemCount: Int, calls: Int) throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let list = items(itemCount)
        journal.record(entry(0), items: list, module: "bench")

        var recordTotal: TimeInterval = 0
        var changeTotal: TimeInterval = 0
        for i in 1...calls {
            let recordStart = Date()
            // A tick brings a slightly different list each time — an unchanged
            // list is the case `ScanNews.finding` refuses on `isSomething`, and
            // that refusal must not be what makes this reading look cheap.
            let next = list.map { ScanItem(path: $0.path, bytes: $0.bytes + i) }
            journal.record(entry(TimeInterval(i) * 60), items: next, module: "bench")
            recordTotal += Date().timeIntervalSince(recordStart)

            let changeStart = Date()
            _ = ScanNews.finding(in: journal.change(module: "bench"))
            changeTotal += Date().timeIntervalSince(changeStart)
        }

        print(String(format: "%d items: record %.4f s/call, change+finding %.4f s/call "
                     + "(the second reads back what the first just wrote), combined tick "
                     + "%.4f s/call, over %d calls",
                     itemCount, recordTotal / Double(calls), changeTotal / Double(calls),
                     (recordTotal + changeTotal) / Double(calls), calls))
    }

    func testAtDocumentsScale() throws {
        try bench(itemCount: 6900, calls: 10)
    }

    func testAtTenTimesDocumentsScale() throws {
        try bench(itemCount: 69_000, calls: 5)
    }
}
