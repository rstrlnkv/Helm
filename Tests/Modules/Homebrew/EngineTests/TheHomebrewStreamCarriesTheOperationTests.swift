// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmTestSupport
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
/// feeds by hand, so the order is the test's and not a process's
/// (`ScriptedRunner` holding its child: `line` and `exit` are the test's).
private struct FixtureBrew: BrewLocator {
    func brewPath() -> String? { "/opt/fixture/bin/brew" }
}
/// Kept: the only test that the engine's stream delivers lines and states whole and in order, and to a late subscriber; the model-side class reads a fake stream, not the engine's.
final class TheHomebrewStreamCarriesTheOperationTests: XCTestCase {

    private func engine(_ runner: ProcessRunner, _ news: EngineNews<HomebrewNews> = EngineNews())
        -> HomebrewEngine {
        brewEngine(runner, locator: FixtureBrew(), news: news)
    }

    private static func isEnding(_ news: HomebrewNews) -> Bool {
        if case .state(let s) = news { return s.phase == .done || s.phase == .failed }
        return false
    }

    func testLinesAndStatesArriveInTheOrderTheyWereSaid() async {
        let runner = ScriptedRunner(streams: .hold)
        let engine = self.engine(runner)
        let news = engine.stream()

        engine.install(name: "wget", isCask: false)
        XCTAssertEqual(runner.streamCalls.count, 1, "control: the operation never started")
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
        let news = EngineNews<HomebrewNews>()
        let runner = ScriptedRunner(streams: .hold)
        let engine = self.engine(runner, news)
        engine.install(name: "wget", isCask: false)
        runner.line("==> fetching")
        XCTAssertEqual(news.subscriberCount, 0, "control: nobody listened yet")

        let tape = engine.stream()
        // Registered before `stream()` returns: an ending that lands now is
        // after the replay and not instead of it.
        XCTAssertEqual(news.subscriberCount, 1,
                       "the subscription was not taken when the stream was asked for")
        runner.exit(0)

        let got = await collect(tape, through: Self.isEnding)
        XCTAssertEqual(got, [
            .state(OpState(phase: .running, label: "install wget")),
            .line("==> fetching"),
            .state(OpState(phase: .done, label: "install wget", exitCode: 0)),
        ], "a page opened mid-operation did not hear it from the start")
    }

    func testActivationSaysWhereBrewIs() async {
        for (locator, expected) in [(FixtureBrew() as BrewLocator, "/opt/fixture/bin/brew" as String?),
                                    (NoBrew(), nil)] {
            let engine = HomebrewEngine(locator: locator, runner: ScriptedRunner(streams: .hold),
                                        privileged: NoPrivileges(), user: "tester",
                                        news: EngineNews(), marker: InMemoryOpMarker(),
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
        let news = EngineNews<HomebrewNews>()
        let engine = self.engine(ScriptedRunner(streams: .hold), news)
        XCTAssertEqual(news.subscriberCount, 0, "control: nobody listened yet")

        let tape = engine.stream()
        XCTAssertEqual(news.subscriberCount, 1)
        let reading = Locked(false)
        let reader = Task { reading.withLock { $0 = true }; for await _ in tape {} }
        // The reader is running, not merely made.
        await waitUntilReached("the reader is running") { reading.value }
        XCTAssertEqual(news.subscriberCount, 1)

        reader.cancel()
        await reader.value
        await waitUntilReached("the subscriber is given back", within: .seconds(5)) { news.subscriberCount == 0 }
        XCTAssertEqual(news.subscriberCount, 0,
                       "a subscriber outlived the iteration that took it")
    }
}
