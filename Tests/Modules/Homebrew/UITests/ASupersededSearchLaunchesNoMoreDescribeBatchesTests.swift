// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **A search nobody is waiting for any more launches no further `brew desc`.**
///
/// `HomebrewViewModel.search` drops the older *answer* (`LatestRequest`), and the
/// engine's `descriptions` once walked every batch of 4093 names to the end
/// whatever the page had moved on to: a query that matches everything (8742
/// formulae) is three `brew desc` runs, and typing another word while the first
/// was out did not stop the second and third. The tests pin that it now does.
/// Driven over the real engine and a fake `brew`, so
/// the test names no seam the fix could choose (a token handed down, a task
/// cancelled, a closure asked between batches).
///
/// The hand-off is a semaphore: the fake holds the first `desc` call of the first
/// search until the test has typed and asked the second word, then releases it.
///
/// Not kept (Architecture/TestsAndMeasurement.md § What proves what: "logic that
/// costs no data"): the class is in `Tests/optional-tests.txt`.
@MainActor
final class ASupersededSearchLaunchesNoMoreDescribeBatchesTests: XCTestCase {

    /// `brew search` answers `big-0…big-8741` to the word «big» and one name to
    /// «small»; `brew desc` describes every name it is given, and the first call
    /// that carries a «big-» name waits on `gate` after saying it is out.
    private final class HeldBrew: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private let gate = DispatchSemaphore(value: 0)
        private var held = false
        private var _entered = false
        private var _descCalls: [[String]] = []

        var entered: Bool { lock.withLock { _entered } }
        var descCalls: [[String]] { lock.withLock { _descCalls } }
        func release() { gate.signal() }

        static let bigNames = (0..<8742).map { "big-\($0)" }

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            if args.first == "search" {
                let query = args.last ?? ""
                if args.contains("--cask") { return (0, "") }
                switch query {
                case "big": return (0, Self.bigNames.joined(separator: "\n") + "\n")
                case "small": return (0, "small-one\n")
                default: return (0, "")
                }
            }
            guard args.first == "desc", let terminator = args.firstIndex(of: "--") else { return (0, "") }
            let names = Array(args[args.index(after: terminator)...])
            let holdThis: Bool = lock.withLock {
                _descCalls.append(names)
                guard !held, names.first?.hasPrefix("big-") == true else { return false }
                held = true
                _entered = true
                return true
            }
            if holdThis { gate.wait() }
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

    private struct Locator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }

    private struct NoAdmin: PrivilegedRunner {
        func runAdmin(_ script: String) -> PrivilegedOutcome { .declined }
    }

    func testASearchTypedOverStopsAskingForDescriptions() async {
        let runner = HeldBrew()
        let engine = HomebrewEngine(locator: Locator(), runner: runner,
                                    privileged: NoAdmin(), user: "tester",
                                    marker: InMemoryOpMarker())
        let model = HomebrewViewModel(work: engine)
        model.searchPause = .seconds(3600)
        defer { model.stop() }

        model.query = "big"
        model.searchNow()
        await waitUntil("the first search's first `brew desc` is out") { runner.entered }

        model.query = "small"
        model.searchNow()
        runner.release()

        await waitUntil("the second search's description arrives") {
            model.description(name: "small-one", isCask: false) != nil
        }
        await grace()

        let bigCalls = runner.descCalls.filter { $0.first?.hasPrefix("big-") == true }.count
        XCTAssertLessThanOrEqual(bigCalls, 1, """
            the superseded search launched \(bigCalls) `brew desc` batches of \
            \(runner.descCalls.filter { $0.first?.hasPrefix("big-") == true }.map(\.count)) names; \
            only the one in flight when it was typed over may finish
            """)
        XCTAssertNotNil(model.description(name: "small-one", isCask: false))
    }
}
