// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// What opening the page starts, through the real model and the real engine over
/// a runner that only writes down what it was asked.
///
/// The model is built once for the life of the module and the page only reads
/// it, so the first open is the model's `loadIfNeeded` and a return visit is the
/// same call again. Opening must not add a reading
/// (`outdated` runs `brew update` first),
/// drop the environment that keeps the others from doing so, or make a return
/// visit pay for a list that has not changed. Never the real `brew`: the runner
/// answers from a table and the locator names a path that does not exist.
private final class RecordingBrew: ProcessRunner, @unchecked Sendable {
    struct Call: Equatable {
        let kind: String
        let launchPath: String
        let args: [String]
        let env: [String: String]
    }
    private let lock = NSLock()
    private var recorded: [Call] = []
    var calls: [Call] { lock.withLock { recorded } }

    private func note(_ kind: String, _ path: String, _ args: [String], _ env: [String: String]) {
        lock.withLock { recorded.append(Call(kind: kind, launchPath: path, args: args, env: env)) }
    }

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        note("run", launchPath, args, env)
        switch args.first {
        case "list":
            return (0, args.contains("--cask") ? "iterm2 3.5.0\n" : "wget 1.25.0\njq 1.8.1\n")
        case "desc":
            return (0, args.contains("--cask") ? "iterm2: Terminal emulator\n"
                                               : "wget: Internet file retriever\njq: JSON processor\n")
        default:
            return (0, "")
        }
    }

    func runData(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: Data) {
        note("runData", launchPath, args, env)
        return (0, Data())
    }

    func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                 env: [String: String]) -> (status: Int32, output: String) {
        note("runCapturingDiagnostics", launchPath, args, env)
        return (0, "")
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        note("stream", launchPath, args, env)
        onExit(0)
        return NoProcess()
    }
}

private struct FixtureBrew: BrewLocator {
    func brewPath() -> String? { "/opt/fixture/bin/brew" }
}

private struct NoPrivileges: PrivilegedRunner {
    func runAdmin(_ script: String) -> PrivilegedOutcome { .declined }
}

@MainActor
final class OpeningThePageAsksWhatItAlwaysAskedTests: XCTestCase {

    private func pair(_ runner: RecordingBrew) -> (HomebrewEngine, HomebrewViewModel) {
        let engine = HomebrewEngine(locator: FixtureBrew(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    transport: LocalTransport(), marker: InMemoryOpMarker(),
                                    popularity: NoPopularity(), weight: NoPackageWeight(),
                                    tools: ToolsAlreadyInstalled(), ticker: NoWaitTicker())
        return (engine, HomebrewViewModel(work: engine))
    }

    func testTheFirstOpenRunsTheTwoListsAndTheDescriptions() async {
        let runner = RecordingBrew()
        let (engine, model) = pair(runner)
        XCTAssertTrue(runner.calls.isEmpty, "building the model ran a tool")

        await model.loadIfNeeded()

        // The subject happened: the lists are on the model, the rows are named.
        XCTAssertEqual(model.installed.map(\.name).sorted(), ["iterm2", "jq", "wget"],
                       "control: the lists never reached the model")
        XCTAssertEqual(model.description(name: "wget", isCask: false), "Internet file retriever")
        XCTAssertEqual(model.description(name: "iterm2", isCask: true), "Terminal emulator")

        let quiet = ["HOMEBREW_NO_AUTO_UPDATE": "1"]
        XCTAssertEqual(runner.calls.map(\.args), [
            ["list", "--versions", "--formula"],
            ["list", "--versions", "--cask"],
            ["desc", "--formula", "--", "wget", "jq"],
            ["desc", "--cask", "--", "iterm2"],
        ], "opening the page ran something beside its two lists and their descriptions")
        XCTAssertEqual(runner.calls.map(\.kind), ["run", "run", "run", "run"])
        XCTAssertEqual(Set(runner.calls.map(\.launchPath)), ["/opt/fixture/bin/brew"])
        for call in runner.calls {
            XCTAssertEqual(call.env, quiet,
                           "\(call.args) ran without the variable that keeps brew from updating")
        }
        let words = runner.calls.flatMap(\.args)
        for forbidden in ["outdated", "search", "update", "upgrade", "info", "doctor", "config"] {
            XCTAssertFalse(words.contains(forbidden), "opening the page ran brew \(forbidden)")
        }
        withExtendedLifetime(engine) {}
    }

    func testAReturnVisitRunsNothing() async {
        let runner = RecordingBrew()
        let (engine, model) = pair(runner)
        await model.loadIfNeeded()
        let first = runner.calls.count
        XCTAssertEqual(first, 4, "control: the first open did not run its four readings")

        await model.loadIfNeeded()
        XCTAssertEqual(runner.calls.count, first,
                       "a return visit ran brew again for a list that had not changed")
        withExtendedLifetime(engine) {}
    }
}
