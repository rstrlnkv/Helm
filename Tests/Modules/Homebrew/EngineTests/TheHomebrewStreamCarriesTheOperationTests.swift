// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// The engine's `stream()` carries an operation to the model whole: the running
/// state, every line the tool printed, the ending, in the order they were said,
/// to a subscriber registered before `stream()` returns.
///
/// Activation says where brew is, first: the locator's path, or none, and the
/// model seeds its status from it. This test never draws a frame.
///
/// Lines are edges and states are levels. A stream that dropped a line, kept
/// only the newest of a burst, or took its subscription a moment after it was
/// asked for would show as a console with a hole in it or a page that never
/// leaves «running» — nothing throws. Over a runner whose output the test
/// feeds by hand, so the order is the test's and not a process's.
private final class HandFedRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var lineSink: (@Sendable (String) -> Void)?
    private var exitSink: (@Sendable (Int32) -> Void)?
    private var started = 0
    var launches: Int { lock.withLock { started } }

    func line(_ text: String) { lock.withLock { lineSink }?(text) }
    func exit(_ code: Int32) { lock.withLock { exitSink }?(code) }

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
    func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                 env: [String: String]) -> (status: Int32, output: String) { (0, "") }
    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        lock.withLock { lineSink = onLine; exitSink = onExit; started += 1 }
        return NoProcess()
    }
}

private struct FixtureBrew: BrewLocator {
    func brewPath() -> String? { "/opt/fixture/bin/brew" }
}
private struct NoBrew: BrewLocator {
    func brewPath() -> String? { nil }
}
private struct NoPrivileges: PrivilegedRunner {
    func runAdmin(_ script: String) -> PrivilegedOutcome { .declined }
}

final class TheHomebrewStreamCarriesTheOperationTests: XCTestCase {

    private func engine(_ runner: ProcessRunner, _ transport: LocalTransport = LocalTransport())
        -> HomebrewEngine {
        HomebrewEngine(locator: FixtureBrew(), runner: runner, privileged: NoPrivileges(),
                       user: "tester", transport: transport, marker: InMemoryOpMarker(),
                       popularity: NoPopularity(), weight: NoPackageWeight(),
                       tools: ToolsAlreadyInstalled(), ticker: NoWaitTicker())
    }

    /// Everything the stream says up to and including the first item `last`
    /// accepts. A watchdog cancels the read after ten seconds, so a stream that
    /// never says it fails the assertion instead of hanging the run.
    private func collect(_ news: AsyncStream<HomebrewNews>,
                         through last: @escaping @Sendable (HomebrewNews) -> Bool) async
        -> [HomebrewNews] {
        let reader = Task { () -> [HomebrewNews] in
            var got: [HomebrewNews] = []
            for await item in news {
                got.append(item)
                if last(item) { break }
            }
            return got
        }
        let watchdog = Task { try? await Task.sleep(for: .seconds(10)); reader.cancel() }
        let got = await reader.value
        watchdog.cancel()
        return got
    }

    private static func isEnding(_ news: HomebrewNews) -> Bool {
        if case .state(let s) = news { return s.phase == .done || s.phase == .failed }
        return false
    }

    func testLinesAndStatesArriveInTheOrderTheyWereSaid() async {
        let runner = HandFedRunner()
        let engine = self.engine(runner)
        let news = engine.stream()

        engine.install(name: "wget", isCask: false)
        XCTAssertEqual(runner.launches, 1, "control: the operation never started")
        let said = (0..<500).map { "==> line \($0)" }
        for line in said { runner.line(line) }
        runner.exit(0)

        let got = await collect(news, through: { item in
            if case .state(let s) = item { return s.phase == .done || s.phase == .failed }
            return false
        })
        XCTAssertEqual(got.count, 502, "a line or a state was lost on the way")
        XCTAssertEqual(got.first, .state(OpState(phase: .running, label: "install wget")))
        XCTAssertEqual(got.dropFirst().dropLast(), ArraySlice(said.map(HomebrewNews.line)),
                       "the lines arrived reordered or thinned")
        XCTAssertEqual(got.last,
                       .state(OpState(phase: .done, label: "install wget", exitCode: 0)))
    }

    func testTheRunningStateReachesAStreamTakenLate() async {
        let transport = LocalTransport()
        let runner = HandFedRunner()
        let engine = self.engine(runner, transport)
        engine.install(name: "wget", isCask: false)
        runner.line("==> fetching")
        XCTAssertEqual(transport.subscriberCount, 0, "control: nobody listened yet")

        let news = engine.stream()
        // Registered before `stream()` returns: an ending that lands now is
        // after the replay and not instead of it.
        XCTAssertEqual(transport.subscriberCount, 1,
                       "the subscription was not taken when the stream was asked for")
        runner.exit(0)

        let got = await collect(news, through: Self.isEnding)
        XCTAssertEqual(got, [
            .state(OpState(phase: .running, label: "install wget")),
            .line("==> fetching"),
            .state(OpState(phase: .done, label: "install wget", exitCode: 0)),
        ], "a page opened mid-operation did not hear it from the start")
    }

    func testActivationSaysWhereBrewIs() async {
        for (locator, expected) in [(FixtureBrew() as BrewLocator, "/opt/fixture/bin/brew" as String?),
                                    (NoBrew(), nil)] {
            let engine = HomebrewEngine(locator: locator, runner: HandFedRunner(),
                                        privileged: NoPrivileges(), user: "tester",
                                        transport: LocalTransport(), marker: InMemoryOpMarker(),
                                        popularity: NoPopularity(), weight: NoPackageWeight(),
                                        tools: ToolsAlreadyInstalled(), ticker: NoWaitTicker())
            let news = engine.stream()
            engine.activate()
            let got = await collect(news, through: { if case .brew = $0 { true } else { false } })
            XCTAssertEqual(got, [.brew(path: expected)],
                           "activation did not say where brew is (\(expected ?? "none"))")
            engine.deactivate()
        }
    }

    func testEndingTheIterationGivesTheSubscriberBack() async {
        let transport = LocalTransport()
        let engine = self.engine(HandFedRunner(), transport)
        XCTAssertEqual(transport.subscriberCount, 0, "control: nobody listened yet")

        let news = engine.stream()
        XCTAssertEqual(transport.subscriberCount, 1)
        let reader = Task { for await _ in news {} }
        // The reader is running, not merely made.
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(transport.subscriberCount, 1)

        reader.cancel()
        await reader.value
        let deadline = Date().addingTimeInterval(5)
        while transport.subscriberCount != 0, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(transport.subscriberCount, 0,
                       "a subscriber outlived the iteration that took it")
    }
}
