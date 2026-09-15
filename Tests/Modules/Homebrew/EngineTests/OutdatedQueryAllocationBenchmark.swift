import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Homebrew_Engine

/// What the `outdated` query path asks the allocator for, request by request.
///
/// The path used to be Data → String → Data: `HelmProcess.run` read the tool's
/// bytes and made a String of them, and `outdated()` immediately copied that
/// String back into `Data(out.utf8)` for the JSON decoder — two full extra
/// copies of the payload, bought and thrown away on every refresh. `runData`
/// hands the bytes through untouched now.
///
/// The payload's *shape* is brew's own `--json=v2`; the count is inflated far
/// past any real Cellar so a copy of it stands clear of everything else the
/// decode asks for. The guard is about proportion, not about a real machine:
/// the parse may ask for the decoded packages, and it must not also ask for the
/// raw bytes a second time.
///
/// **Why the requests and not a high-water.** This case used to sample
/// `AllocatorBooks.allocatedBytes()` — the whole process's books — across the
/// call and assert the smallest of three peaks over its start against 60 MB.
/// That reading is not a property of the parse. Measured on this payload, on
/// unchanged code: 50–51 MB a round, three runs of three, where this case is
/// the only one in its process, and 58, 58, 63 in one run and 63, 63, 63 in the
/// next where the other 235 cases in this bundle ran first. Against a ceiling
/// at 60 it passes alone and fails whenever all three rounds land at the top,
/// which a used process does about half the time. What the difference is
/// *not*: no other thread allocated a byte inside the measured window in either
/// condition (counted: zero requests), and no `realloc` moved (counted: zero,
/// this path reallocates nothing at all). What it is: 5 MB of it is the reading
/// rather than the call — the same request sequence, identical to the byte,
/// reads 58 MB in one round and 63 in the next, off books that are sampled
/// every 200 µs rather than watched — and the rest is Foundation's decoder
/// asking for one buffer of 8 387 584 bytes in the fresh process and
/// 13 106 176 in the used one. `ThreadAllocations` counts what this thread
/// asked for instead: three rounds identical to the byte in either condition,
/// and the whole difference between the two conditions is that one buffer of
/// Foundation's.
///
/// The measurements the ceiling sits between, for this 14 063 915-byte payload,
/// in bytes asked for in blocks of a megabyte or more, three rounds agreeing to
/// the byte in each condition:
///
/// * handing the bytes through — 68 952 048 (4.90 payloads) as the only case in
///   the process, 73 670 640 (5.24) after the other 235 in this bundle, 6 blocks
///   either way;
/// * the String round trip put back — 97 079 931 (6.90) and 101 798 523 (7.24),
///   8 blocks: the same 6 and two more, 28 127 883 bytes between them, one for
///   the String and one for the Data made back out of it.
final class OutdatedQueryAllocationBenchmark: XCTestCase {

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }

    /// Hands its bytes over the port the way the real runner does — without
    /// building a fresh copy per call, so whatever the engine asks for during
    /// the parse is the engine's own.
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
        /// Not `doctor`: no fake here needs to answer on the diagnostics stream.
        func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String) {
            (0, "")
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

    /// A copy of the payload cannot be asked for in small change: it is one
    /// request of the payload's own size. Counting only requests this large
    /// leaves out the per-package strings and arrays, which are the same either
    /// way and are where the small drift between processes lives.
    private let blockFloor = 1 << 20

    func testTheParseDoesNotHoldASecondCopyOfTheRawBytes() throws {
        let bytes = payload(entries: 150_000)
        let runner = CannedRunner(canned: bytes)
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester")

        // Warm once: lazy caches (decoder tables, log plumbing) must not be
        // billed to the measured run.
        XCTAssertEqual(engine.outdated()?.count, 150_000, "precondition: the parse works")
        XCTAssertGreaterThan(bytes.count, 8 * blockFloor,
                             "the fixture is \(bytes.count) bytes — a payload has to stand "
                             + "well clear of the \(blockFloor)-byte floor for a copy of it "
                             + "to be a block this counts")

        // Three rounds. The reading is deterministic, so the worst of them is
        // the one to judge: anything above the others is a request that was
        // really made, not a sample that landed badly.
        var readings: [ThreadAllocations.Reading] = []
        for _ in 0..<3 {
            let (parsed, reading) = try ThreadAllocations.during(countingBlocksOfAtLeast: blockFloor) {
                engine.outdated()
            }
            XCTAssertEqual(parsed?.count, 150_000)
            readings.append(reading)
        }

        let ceiling = 6.0
        let worst = readings.max { $0.requestedInBlocks < $1.requestedInBlocks }
        let payloads = worst.map { Double($0.requestedInBlocks) / Double(bytes.count) }
            ?? .infinity
        let rounds = readings.map {
            String(format: "%.2f payloads in %d blocks (%d bytes), %d bytes over %d "
                   + "requests in all, largest %d",
                   Double($0.requestedInBlocks) / Double(bytes.count), $0.blocks,
                   $0.requestedInBlocks, $0.requested, $0.requests, $0.largestRequest)
        }
        // Printed the way the sibling benchmarks print theirs: the number is
        // the thing to re-read when Foundation's decoder changes what it asks
        // for, and a ceiling nobody can see the distance to is a ceiling
        // nobody re-calibrates.
        print("outdated() over a \(bytes.count)-byte payload, blocks of "
              + "\(blockFloor) bytes or more: \(rounds.joined(separator: "; "))")
        XCTAssertLessThan(payloads, ceiling, """
            outdated() asked for \(String(format: "%.2f", payloads)) copies of its own \
            \(bytes.count)-byte payload in blocks of \((worst?.blockFloor ?? blockFloor) / 1_048_576) MB or more \
            (rounds: \(rounds.joined(separator: ", "))) — the parse is asking for a second \
            copy of the raw bytes again.
            """)
    }
}
