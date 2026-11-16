// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Homebrew_Engine

/// **A batch that spent exactly its allowance while asking every name is not a
/// batch that gave up.**
///
/// `DescriptionBudget.exhausted` is documented as «whether the split gave up with
/// names still unasked». It was once read as `remaining <= 0`, which is also true
/// of a split that used its last call on its last name: two names refused
/// allowance 3 and spend 3 (`[a b]`, `[a]`, `[b]`), three names 5 and 5. Nothing
/// was left unasked, yet `descriptions` logged «brew refused N names wholesale —
/// gave up after N calls» and stopped the batches after it. The tests pin that
/// such a split gives up on nothing.
///
/// Observed through the engine's log and the calls it makes, not through
/// `DescriptionBudget`, so a fix is free to say it another way.
///
/// Not kept (Architecture/TestsAndMeasurement.md § What proves what: "logic that
/// costs no data"): the class is in `Tests/optional-tests.txt`.
final class ABatchThatAskedEveryNameDidNotGiveUpTests: XCTestCase {

    /// A brew that refuses every call, and remembers each one.
    private final class RefusingBrew: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _descCalls: [[String]] = []
        var descCalls: [[String]] { lock.withLock { _descCalls } }

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            guard args.first == "desc", let terminator = args.firstIndex(of: "--") else { return (0, "") }
            lock.withLock { _descCalls.append(Array(args[args.index(after: terminator)...])) }
            return (1, "")
        }

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

    private struct Locator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }

    private struct NoAdmin: PrivilegedRunner {
        func runAdmin(_ script: String) -> PrivilegedOutcome { .declined }
    }

    private func gaveUpLines() -> [String] {
        HelmLog.shared.recentEntries().map(\.message).filter { $0.contains("gave up") }
    }

    private func describeAllRefused(_ count: Int) -> (calls: [[String]], gaveUp: [String]) {
        tailTheLog()
        let runner = RefusingBrew()
        let engine = HomebrewEngine(locator: Locator(), runner: runner, privileged: NoAdmin(),
                                    user: "tester", marker: InMemoryOpMarker())
        _ = engine.descriptions(names: (0..<count).map { "pkg-\($0)" }, isCask: false)
        return (runner.descCalls, gaveUpLines())
    }

    func testTwoNamesBothRefusedAreAllAskedAndNobodyGaveUp() {
        let (calls, gaveUp) = describeAllRefused(2)
        XCTAssertEqual(Set(calls.flatMap { $0 }), ["pkg-0", "pkg-1"], "control: every name was asked")
        XCTAssertEqual(calls.count, 3, "control: the batch spent its whole allowance of 3")
        XCTAssertTrue(gaveUp.isEmpty,
                      "a batch that asked all 2 names after \(calls.count) calls logged: \(gaveUp)")
    }

    func testThreeNamesAllRefusedAreAllAskedAndNobodyGaveUp() {
        let (calls, gaveUp) = describeAllRefused(3)
        XCTAssertEqual(Set(calls.flatMap { $0 }), ["pkg-0", "pkg-1", "pkg-2"], "control: every name was asked")
        XCTAssertEqual(calls.count, 5, "control: the batch spent its whole allowance of 5")
        XCTAssertTrue(gaveUp.isEmpty,
                      "a batch that asked all 3 names after \(calls.count) calls logged: \(gaveUp)")
    }

    /// The control that keeps the two above honest: a batch that really was cut
    /// off (32 names, allowance 33, a full split needs 63) still says so.
    func testABatchCutOffWithNamesUnaskedStillSaysItGaveUp() {
        let (calls, gaveUp) = describeAllRefused(32)
        XCTAssertLessThan(calls.filter { $0.count == 1 }.count, 32,
                          "control: some name was never asked on its own")
        XCTAssertEqual(calls.count, 33, "control: the allowance was spent")
        XCTAssertEqual(gaveUp.count, 1, "a batch cut off with names unasked said nothing: \(gaveUp)")
    }
}
