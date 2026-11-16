// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **One `brew desc` argv for a whole batch, and the system refuses more than
/// 4096 arguments.**
///
/// `NSTask` raises `NSInvalidArgumentException` ("too many arguments (8745) --
/// limit is 4096") when `arguments` holds more than 4096 strings; measured on
/// macOS 27.3 (one run, 2026-11-16, a Swift `Process` on `/usr/bin/true`: 4096
/// arguments launched, 4097 raised). `HelmLaunchTask` catches it and
/// `HelmProcess` answers status -1, which `describe` reads as brew refusing the
/// batch and bisects through more refused launches. `brew search` answers a
/// query like «яяйчнл» with every formula (8742) and every cask (7832), and the
/// page passes all of them to `descriptions(names:isCask:)` at once.
///
/// Where the figures come from: `brew search --formula -- яяйчнл | wc -l` gave
/// 8742 and `brew search --cask -- яяйчнл | wc -l` gave 7832 (Homebrew 7.0.14,
/// 2026-11-16 16:36, this Mac, one run each). The query is the search field's
/// value at 13:52 the same day, read through an accessibility readout; it is
/// not from the Helm Dev log.
///
/// The fake is that system: status -1 for any call whose argument count (the
/// launch path excluded, as `NSTask.arguments` counts) is over 4096, otherwise
/// a brew that describes every name it is given.
///
/// Not kept (Architecture/TestsAndMeasurement.md § What proves what: "logic that costs no data"):
/// the class is in `Tests/optional-tests.txt`.
final class ASearchThatMatchesEverythingStillGetsItsDescriptionsTests: XCTestCase {

    /// `NSTask`'s ceiling on `arguments.count`; the text of the exception names
    /// it ("limit is 4096"). Spelled here, not read from production code.
    private static let argumentLimit = 4096

    private final class LimitedBrew: ProcessRunner, @unchecked Sendable {
        /// What every `brew desc` call answers when `answer` is set (a refusal
        /// or a timeout); nil is the brew that describes every name.
        private let answer: Int32?
        init(answerEveryCallWith answer: Int32? = nil) { self.answer = answer }

        private let lock = NSLock()
        private var _argCounts: [Int] = []
        private var _askedNames: Set<String> = []
        var argCounts: [Int] { lock.lock(); defer { lock.unlock() }; return _argCounts }
        var askedNames: Set<String> { lock.lock(); defer { lock.unlock() }; return _askedNames }

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            guard args.first == "desc" else { return (0, "") }
            lock.lock()
            _argCounts.append(args.count)
            if let terminator = args.firstIndex(of: "--") {
                _askedNames.formUnion(args[args.index(after: terminator)...])
            }
            lock.unlock()
            if let answer { return (answer, "") }
            if args.count > ASearchThatMatchesEverythingStillGetsItsDescriptionsTests.argumentLimit {
                return (-1, "")
            }
            guard let terminator = args.firstIndex(of: "--") else { return (1, "") }
            let names = args[args.index(after: terminator)...]
            return (0, names.map { "\($0): description of \($0)" }.joined(separator: "\n") + "\n")
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

    func testEveryFormulaOfASearchThatMatchesEverythingIsDescribed() {
        let wanted = (0..<8742).map { "formula-\($0)" }
        let runner = LimitedBrew()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    marker: InMemoryOpMarker())

        let found = engine.descriptions(names: wanted, isCask: false)

        let widest = runner.argCounts.max() ?? 0
        XCTAssertLessThanOrEqual(widest, Self.argumentLimit, """
            a `brew desc` call carried \(widest) arguments; NSTask refuses more than \
            \(Self.argumentLimit) and answers status -1
            """)
        // At the limit, not one under it: 8742 names fill two calls of 4093
        // names (+ `desc`, `--formula`, `--` = 4096) and one of 556.
        XCTAssertEqual(widest, 4096, "the widest call should use the whole allowance")
        XCTAssertEqual(runner.argCounts.sorted(), [559, 4096, 4096])
        XCTAssertEqual(found.count, wanted.count, """
            \(wanted.count - found.count) of \(wanted.count) descriptions are missing \
            (\(runner.argCounts.count) `brew desc` calls were made)
            """)
    }

    /// A brew that times out on every call: the first batch says so, the
    /// others are not asked (each would hold the queue for a full deadline).
    func testATimeoutOnTheFirstBatchStopsTheBatchesAfterIt() {
        let wanted = (0..<8742).map { "formula-\($0)" }
        let runner = LimitedBrew(answerEveryCallWith: HelmProcess.timedOutStatus)
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    marker: InMemoryOpMarker())

        let found = engine.descriptions(names: wanted, isCask: false)

        XCTAssertTrue(found.isEmpty)
        XCTAssertEqual(runner.argCounts, [4096], "exactly one launch, not one per batch")
        XCTAssertFalse(runner.askedNames.contains("formula-4093"),
                       "a name of the second batch was asked")
    }

    /// A brew that refuses every call (exit 1, not a timeout): the first batch
    /// spends its allowance (max(4093 + 1, 2 * 12 + 1) = 4094 calls), is read as
    /// refused wholesale, and the second and third batches are never asked.
    func testAWholesaleRefusalOfTheFirstBatchStopsTheBatchesAfterIt() {
        let wanted = (0..<8742).map { "formula-\($0)" }
        let runner = LimitedBrew(answerEveryCallWith: 1)
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    marker: InMemoryOpMarker())

        let found = engine.descriptions(names: wanted, isCask: false)

        XCTAssertTrue(found.isEmpty)
        XCTAssertEqual(runner.argCounts.count, 4094,
                       "launches should stay within the first batch's allowance")
        XCTAssertFalse(runner.askedNames.contains("formula-4093"),
                       "a name of the second batch was asked")
        XCTAssertFalse(runner.askedNames.contains("formula-8741"),
                       "a name of the third batch was asked")
    }
}
