import XCTest
import Foundation
import HelmTestSupport
@testable import Module_Disk_Engine

/// What reading the last scan back actually costs, and what it is allowed to
/// keep.
///
/// `ScanStore.loadDetached` decodes `last-scan.json` with `JSONDecoder` on a
/// detached task — **no phase names it**, so in `helm.log` its cost appears as
/// a footprint jump beside «no phases running». Measured against the owner's
/// real file (8 723 079 bytes, 45 081 nodes, probe of 2026-08-16, three rounds
/// agreeing): the decode holds a transient peak of 39.6–39.8 MB over start on
/// the allocator's books — ≈ 4.5 bytes per byte of file — and keeps ~12 MB of
/// tree. Every launch that restores the ring pays the transient; a page visit
/// does not (the view model is cached per process).
///
/// Two numbers, two different guards:
///
/// * **Kept bytes per node** asserts in the ordinary suite discipline — it is
///   deterministic, and the plausible regression is exactly the one this
///   measures: a restore that keeps a second copy (the raw `Data`, an
///   intermediate array) doubles it. Healthy reading ~280 B/node; a doubled
///   keep reads ~560+. The bound sits between: 480.
/// * **Transient peak per file byte** is a property of `JSONDecoder` and of
///   nothing in this repository, so it is recorded, with a ceiling loose
///   enough to hold only against a blow-up (10×, against 4.5× measured) —
///   the number to re-read if the store ever changes format.
///
/// Both run under `HELM_BENCH=1` because building the 45 000-node fixture and
/// decoding it three times is seconds, not milliseconds.
///
/// `HELM_BENCH=1 swift test --filter SavedScanRestoreCostBenchmark`
final class SavedScanRestoreCostBenchmark: XCTestCase {

    /// A tree the shape of the owner's saved scan: ~45 000 nodes, fanout close
    /// to what `DiskEntry(_:depth:path:)` writes (≤200 children a node, depth
    /// ≤4), path and name strings of realistic length. Invented content — the
    /// suite must never read this Mac's own `last-scan.json`
    /// (`TheSuiteDoesNotReadTheUsersLastScanTests` is the standing rule).
    private static func fixture() -> ScanResult {
        var counter = 0
        func node(_ depth: Int, _ path: String) -> DiskEntry {
            counter += 1
            let children: [DiskEntry]
            if depth > 0 && counter < 46_000 {
                children = (0..<15).map {
                    node(depth - 1, path + "/bench-folder-\(counter)-\($0)")
                }
            } else {
                children = []
            }
            return DiskEntry(name: (path as NSString).lastPathComponent,
                             path: path,
                             bytes: 4096 * counter,
                             isDirectory: !children.isEmpty,
                             noAccess: false,
                             children: children)
        }
        let root = node(4, "/bench-volume/Users/somebody")
        return ScanResult(root: root, freeBytes: 1 << 36,
                          filesScanned: counter, seconds: 61.5)
    }

    private static func countNodes(_ e: DiskEntry) -> Int {
        1 + e.children.reduce(0) { $0 + countNodes($1) }
    }

    func testRestoreTransientAndKeptCost() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let dir = scratchDirectory("disk-restore-bench")
        let store = ScanStore(directory: dir)
        store.save(Self.fixture())
        let fileBytes = (try? Data(contentsOf: store.fileURL).count) ?? 0
        XCTAssertGreaterThan(fileBytes, 4_000_000,
                             "the fixture wrote \(fileBytes) bytes; too small to stand for the real file")

        // Three rounds, because one reading is not a measurement. The first
        // may include allocator warm-up; the assertion reads the last two.
        var results: [(peak: Int, kept: Int, nodes: Int)] = []
        for _ in 0..<3 {
            let before = AllocatorBooks.allocatedBytes()
            let (cached, peak) = AllocatorPeak.during { store.load() }
            let kept = AllocatorBooks.allocatedBytes() - before
            let nodes = cached.map { Self.countNodes($0.result.root) } ?? 0
            XCTAssertGreaterThan(nodes, 40_000, "the decode came back with \(nodes) nodes")
            results.append((peak, kept, nodes))
            // The kept tree must not accumulate across rounds; dropping it
            // here is what lets round 2 measure the same thing as round 1.
            withExtendedLifetime(cached) {}
        }

        let nodes = results[0].nodes
        let lines = results.map {
            String(format: "peak %+.1f MB (%.1f B per file byte), kept %+.1f MB (%.0f B/node)",
                   Double($0.peak) / 1_048_576, Double($0.peak) / Double(fileBytes),
                   Double($0.kept) / 1_048_576, Double($0.kept) / Double(nodes))
        }
        print("saved-scan restore, \(nodes) nodes, \(fileBytes) file bytes: "
              + lines.joined(separator: "; "))

        // Kept: the tree and only the tree. ~280 B/node healthy; a restore
        // that keeps a second copy reads ~560+. Read from the later rounds —
        // and each round's keep is measured from its own `before`, so a leak
        // across rounds also fails here, as growth.
        for round in results.dropFirst() {
            let perNode = Double(round.kept) / Double(nodes)
            XCTAssertLessThan(perNode, 480,
                String(format: "a restore kept %.0f B/node — about two copies of the tree "
                       + "where one is the answer", perNode))
        }

        // Transient: JSONDecoder's own bill, ~4.5 B per file byte measured.
        // The ceiling only catches a blow-up.
        for round in results.dropFirst() {
            let perByte = Double(round.peak) / Double(fileBytes)
            XCTAssertLessThan(perByte, 10.0,
                String(format: "the decode held %.1f bytes per file byte at peak — "
                       + "the transient the log shows beside «no phases running» has grown "
                       + "past anything JSONDecoder charges today", perByte))
        }
    }

    /// The write side of the same file. `saveDetached` runs on a detached task
    /// after every finished scan and every basket emptying — also with no
    /// phase — so its transient lands in the same no-phase window the samples
    /// show. Recorded here so the encode has a number beside the decode's.
    func testSaveTransientCost() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let dir = scratchDirectory("disk-save-bench")
        let store = ScanStore(directory: dir)
        let result = Self.fixture()

        var peaks: [Int] = []
        for _ in 0..<3 {
            let (_, peak) = AllocatorPeak.during { store.save(result) }
            peaks.append(peak)
        }
        let fileBytes = (try? Data(contentsOf: store.fileURL).count) ?? 0
        print("saved-scan save, \(fileBytes) file bytes: peaks "
              + peaks.map { String(format: "%.1f MB", Double($0) / 1_048_576) }
                  .joined(separator: ", "))
        for peak in peaks.dropFirst() {
            XCTAssertLessThan(Double(peak) / Double(max(fileBytes, 1)), 10.0,
                              "the encode's transient outgrew anything JSONEncoder charges today")
        }
    }
}
