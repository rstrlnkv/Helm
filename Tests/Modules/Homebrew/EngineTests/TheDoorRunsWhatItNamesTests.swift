// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// The engine's door for the model (`perform(_:)` and the `read…` members) runs
/// what an act names, judges a fix again at the press, and never runs on the
/// caller's thread.
///
/// Three things the door could get wrong without any other test noticing:
/// `uninstall` wired to `install`'s arm (every other test calls the sync
/// methods directly); `runDoctorFix` bypassed by the door
/// (`AFixIsJudgedAgainstTheCellarAtThePressTests` calls it directly); and a press
/// that runs where it was made — `runOp` writes a file and launches a child, on
/// the main actor if it was pressed there. An `async` requirement is satisfied by
/// a sync method of the same name, so the last one compiles either way and is
/// only visible from the thread the runner sees.
private final class DoorRunner: ProcessRunner, @unchecked Sendable {
    struct Seen: Equatable {
        let kind: String
        let args: [String]
        let onMain: Bool
        let queue: String
    }
    private let lock = NSLock()
    private var recorded: [Seen] = []
    var seen: [Seen] { lock.withLock { recorded } }
    var streams: [[String]] { seen.filter { $0.kind == "stream" }.map(\.args) }
    /// What `brew list --versions --formula` prints: the Cellar as the fix is judged.
    var cellar = "wget 1.25.0\n"

    private func note(_ kind: String, _ args: [String]) {
        let seen = Seen(kind: kind, args: args, onMain: Thread.isMainThread,
                        queue: String(cString: __dispatch_queue_get_label(nil)))
        lock.withLock { recorded.append(seen) }
    }

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        note("run", args)
        if args.first == "list" { return (0, args.contains("--cask") ? "" : cellar) }
        return (0, "")
    }
    func runData(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: Data) {
        note("runData", args)
        return (0, Data())
    }
    func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                 env: [String: String]) -> (status: Int32, output: String) {
        note("runCapturingDiagnostics", args)
        return (0, "")
    }
    /// Never exits: an operation that is still out, as a real `brew install` is.
    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        note("stream", args)
        return NoProcess()
    }
}

private struct FixtureBrew: BrewLocator {
    func brewPath() -> String? { "/opt/fixture/bin/brew" }
}
private struct NoPrivileges: PrivilegedRunner {
    func runAdmin(_ script: String) -> PrivilegedOutcome { .declined }
}

final class TheDoorRunsWhatItNamesTests: XCTestCase {

    private func engine(_ runner: ProcessRunner) -> HomebrewEngine {
        HomebrewEngine(locator: FixtureBrew(), runner: runner, privileged: NoPrivileges(),
                       user: "tester", transport: LocalTransport(), marker: InMemoryOpMarker(),
                       popularity: NoPopularity(), weight: NoPackageWeight(),
                       tools: ToolsAlreadyInstalled(), ticker: NoWaitTicker())
    }

    private func until(_ what: String, timeout: TimeInterval = 5,
                       file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertTrue(condition(), "never reached: \(what)", file: file, line: line)
    }

    func testEachActStartsItsOwnCommand() {
        let wget = PackageRef(name: "wget", isCask: false)
        let iterm = PackageRef(name: "iterm2", isCask: true)
        let table: [(HomebrewAct, [String])] = [
            (.install(wget), ["install", "--", "wget"]),
            (.install(iterm), ["install", "--cask", "--", "iterm2"]),
            (.uninstall(wget), ["uninstall", "--", "wget"]),
            (.uninstall(iterm), ["uninstall", "--cask", "--", "iterm2"]),
            (.upgrade(name: "wget"), ["upgrade", "--", "wget"]),
            (.upgradeAll, ["upgrade"]),
            (.doctorFix(argv: ["cleanup"]), ["cleanup"]),
            (.doctorFix(argv: ["uninstall", "wget"]), ["uninstall", "--", "wget"]),
        ]
        for (act, argv) in table {
            let runner = DoorRunner()
            let engine = self.engine(runner)
            engine.perform(act)
            until("\(act) launches") { !runner.streams.isEmpty }
            XCTAssertEqual(runner.streams, [argv], "\(act) started another command")
        }
    }

    func testAFixThroughTheDoorIsStillJudged() async {
        // Control: a fix the Cellar admits launches through the door.
        let admitted = DoorRunner()
        self.engine(admitted).perform(.doctorFix(argv: ["uninstall", "wget"]))
        until("the admitted fix launches") { !admitted.streams.isEmpty }
        XCTAssertEqual(admitted.streams, [["uninstall", "--", "wget"]])

        // A name the Cellar does not hold: refused with its reason, nothing launched.
        let runner = DoorRunner()
        let engine = self.engine(runner)
        let news = engine.stream()
        engine.perform(.doctorFix(argv: ["uninstall", "not-installed"]))
        let reader = Task { () -> OpState? in
            for await item in news {
                if case .state(let s) = item, s.phase == .failed { return s }
            }
            return nil
        }
        let watchdog = Task { try? await Task.sleep(for: .seconds(10)); reader.cancel() }
        let refusal = await reader.value
        watchdog.cancel()
        XCTAssertEqual(refusal?.reason, .fixRefused,
                       "the door ran, or failed, a fix without judging it against the Cellar")
        XCTAssertEqual(refusal?.label, "uninstall not-installed")
        XCTAssertTrue(runner.streams.isEmpty, "a fix the Cellar does not admit was launched")
        // The judgement read the Cellar: the refusal is of this reading, not a default.
        XCTAssertTrue(runner.seen.contains { $0.kind == "run" && $0.args.first == "list" })
    }

    @MainActor
    func testAPressAndAReadLeaveTheCallersThread() async {
        XCTAssertTrue(Thread.isMainThread, "control: the test itself runs on the main thread, where a press must not run")

        let pressed = DoorRunner()
        let engine = self.engine(pressed)
        engine.perform(.install(PackageRef(name: "wget", isCask: false)))
        until("the press launches") { !pressed.streams.isEmpty }

        let fixed = DoorRunner()
        let fixEngine = self.engine(fixed)
        fixEngine.perform(.doctorFix(argv: ["cleanup"]))
        until("the fix launches") { !fixed.streams.isEmpty }

        let read = DoorRunner()
        let readEngine = self.engine(read)
        _ = await readEngine.readInstalled()
        _ = await readEngine.readOutdated()
        _ = await readEngine.find("wget")
        _ = await readEngine.readDescriptions(of: ["wget"], isCask: false)
        _ = await readEngine.readDoctor()
        _ = await readEngine.readConfig()

        let all = pressed.seen + fixed.seen + read.seen
        XCTAssertTrue(all.contains { $0.kind == "stream" } && all.contains { $0.kind == "run" },
                      "control: the runners saw no launch and no read")
        for seen in all {
            XCTAssertFalse(seen.onMain, "\(seen.kind) \(seen.args) ran on the main thread")
            XCTAssertFalse(seen.queue.contains("cooperative"),
                           "\(seen.kind) \(seen.args) parked a thread of the cooperative pool "
                           + "(\(seen.queue))")
        }
    }
}
