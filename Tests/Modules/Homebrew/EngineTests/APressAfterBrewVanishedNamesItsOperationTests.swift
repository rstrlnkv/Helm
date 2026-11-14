// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// brew can vanish between the status read and the press. Each of the four
/// package operations must then say a failed state labelled with *its own*
/// operation, reason `brewMissing`, and launch nothing. The label is what the
/// page prints next to the refusal.
final class APressAfterBrewVanishedNamesItsOperationTests: XCTestCase {

    private struct GoneBrew: BrewLocator {
        func brewPath() -> String? { nil }
    }
    private final class CountingRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var launches: Int { lock.withLock { n } }
        func run(_ l: String, _ a: [String], env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
        func runData(_ l: String, _ a: [String], env: [String: String]) -> (status: Int32, stdout: Data) { (0, Data()) }
        func runCapturingDiagnostics(_ l: String, _ a: [String], env: [String: String]) -> (status: Int32, output: String) { (0, "") }
        func stream(_ l: String, _ a: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            lock.withLock { n += 1 }
            return NoProcess()
        }
    }

    private func refusal(_ press: (HomebrewEngine) -> Void) async -> (OpState?, Int) {
        let news = EngineNews<HomebrewNews>()
        let runner = CountingRunner()
        let engine = HomebrewEngine(locator: GoneBrew(), runner: runner, privileged: NoPrivileges(),
                                    user: "tester", news: news)
        press(engine)
        news.say(.line("test.sentinel"), slot: "test.sentinel")
        var state: OpState?
        for await item in news.stream() {
            if case .line("test.sentinel") = item { break }
            if case .state(let s) = item { state = s }
        }
        return (state, runner.launches)
    }

    func testEachOperationRefusesUnderItsOwnLabel() async {
        let cases: [(String, (HomebrewEngine) -> Void)] = [
            ("install wget", { $0.install(name: "wget", isCask: false) }),
            ("uninstall wget", { $0.uninstall(name: "wget", isCask: false) }),
            ("upgrade wget", { $0.upgrade(name: "wget") }),
            ("upgrade all", { $0.upgradeAll() }),
        ]
        for (label, press) in cases {
            let (state, launches) = await refusal(press)
            XCTAssertEqual(state?.label, label)
            XCTAssertEqual(state?.phase, .failed, label)
            XCTAssertEqual(state?.reason, .brewMissing, label)
            XCTAssertEqual(launches, 0, label)
        }
    }
}
