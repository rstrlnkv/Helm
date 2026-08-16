import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Homebrew_Engine

/// What the `outdated` query path holds at its worst, against the allocator's
/// own books — `phys_footprint` has already lied to a benchmark in this
/// repository, reading flat across a fill that really allocated.
///
/// The path used to be Data → String → Data: `HelmProcess.run` read the tool's
/// bytes and made a String of them, and `outdated()` immediately copied that
/// String back into `Data(out.utf8)` for the JSON decoder — a full extra copy
/// of the payload held for the whole parse, bought and thrown away on every
/// refresh. `runData` hands the bytes through untouched now.
///
/// The payload's *shape* is brew's own `--json=v2`; the count is inflated far
/// past any real Cellar so the copy stands clear of allocator noise. The guard
/// is about proportion, not about a real machine: the parse may hold the
/// decoded packages, and it must not also hold a second copy of the raw bytes.
final class OutdatedQueryAllocationBenchmark: XCTestCase {

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }

    /// Hands its bytes over the port the way the real runner does — without
    /// building a fresh copy per call, so whatever extra the engine holds
    /// during the parse is the engine's own.
    private final class CannedRunner: ProcessRunner, @unchecked Sendable {
        let canned: Data
        init(canned: Data) { self.canned = canned }
        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            (0, String(bytes: canned, encoding: .utf8) ?? "")
        }
        func runData(_ launchPath: String, _ args: [String],
                     env: [String: String]) -> (status: Int32, stdout: Data) {
            (0, canned)
        }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            onExit(0)
            return NoProcess()
        }
    }

    /// brew's own v2 shape, entry by entry.
    private func payload(entries: Int) -> Data {
        var json = #"{"formulae":["#
        json.reserveCapacity(entries * 110)
        for i in 0..<entries {
            if i > 0 { json += "," }
            json += #"{"name":"pkg\#(i)","installed_versions":["1.2.\#(i % 40)"],"current_version":"1.3.\#(i % 40)","pinned":false}"#
        }
        json += #"],"casks":[]}"#
        return Data(json.utf8)
    }

    func testTheParseDoesNotHoldASecondCopyOfTheRawBytes() {
        let bytes = payload(entries: 150_000)
        let runner = CannedRunner(canned: bytes)
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester")

        // Warm once: lazy caches (decoder tables, log plumbing) must not be
        // billed to the measured run.
        XCTAssertEqual(engine.outdated()?.count, 150_000, "precondition: the parse works")

        // Three runs; the guard takes the smallest, because a transient peak
        // can only be over-read by a sample landing beside unrelated noise,
        // never under-read below what the path itself holds.
        var peaks: [Int] = []
        for _ in 0..<3 {
            let (parsed, peak) = AllocatorPeak.during { engine.outdated() }
            XCTAssertEqual(parsed?.count, 150_000)
            peaks.append(peak)
        }
        let best = peaks.min() ?? .max
        // The decoded packages cost what they cost; the copies were the
        // difference. Measured on this 13 MB payload, three converging suite
        // runs each: 79–80 MB at peak through the String round-trip, 50–51 MB
        // handing the bytes through. The ceiling sits between the two
        // measurements, ~9 MB from either.
        let ceiling = 60 * 1024 * 1024
        XCTAssertLessThan(best, ceiling, """
            outdated() held \(best / 1_048_576) MB over baseline for a \
            \(bytes.count / 1_048_576) MB payload (peaks: \
            \(peaks.map { "\($0 / 1_048_576)" .appending(" MB") }.joined(separator: ", "))) \
            — the parse is holding a second copy of the raw bytes again.
            """)
    }
}
