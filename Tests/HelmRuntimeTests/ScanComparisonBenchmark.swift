import XCTest
@testable import HelmRuntime

/// `ScanComparison.between` builds two `Set<ScanItem>` before it can answer
/// "what changed" — asked whether that is worth worrying about at the sizes a
/// real journal holds. `~/Documents` measured 6900 entries (see
/// `ScanFootprintTests` and this file's home-directory line); this also checks
/// ten times that, since a duplicates root or a whole-disk uninstaller list can
/// run larger than one person's Documents folder.
///
/// Report only — this runs in milliseconds at both sizes, nowhere near the
/// seconds a person waits for, so there is nothing here worth gating.
///
/// `HELM_BENCH=1 swift test --filter ScanComparisonBenchmark`
final class ScanComparisonBenchmark: XCTestCase {

    private func items(_ n: Int) -> [ScanItem] {
        (0..<n).map { i in
            ScanItem(path: "/Users/person/Documents/Project\(i % 200)/file-\(i).dat",
                     bytes: 1000 + i)
        }
    }

    private func run(_ n: Int) {
        let previous = items(n)
        // A realistic second scan: most items unchanged, a handful appeared,
        // a handful went — never the identical list, which would let the `Set`
        // short-circuit in ways a real re-scan does not.
        var current = Array(previous.dropFirst(n / 20))
        current.append(contentsOf: items(n / 20).map {
            ScanItem(path: $0.path + "-new", bytes: $0.bytes)
        })

        let start = Date()
        let change = ScanComparison.between(previous: previous, current: current)
        let elapsed = Date().timeIntervalSince(start)
        print(String(format: "ScanComparison.between at %d items: %.4f s "
                     + "(appeared %d, went %d, stayed %d)",
                     n, elapsed, change.appeared.count, change.went.count, change.stayed.count))
    }

    func testAtDocumentsScale() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        run(6900)
    }

    func testAtTenTimesDocumentsScale() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        run(69_000)
    }
}
