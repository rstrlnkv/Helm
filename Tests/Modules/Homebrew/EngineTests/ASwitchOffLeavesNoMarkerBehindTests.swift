// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **A module switched off during any `brew` operation leaves no marker
/// behind: it goes when the child does, and not before.**
///
/// `deactivate()` ends the install of Homebrew (terminated, as Stop does). A
/// package operation or a doctor fix is **not** terminated — a half-built
/// `brew` run is how a broken Cellar is made — it finishes on its own. Its exit
/// used to be heard by a weak reference to an engine the host had already
/// dropped: nobody cleared the marker, so the next enable reported "running at
/// quit" for a child that was still running, and a fresh engine's `busy` was
/// false beside it. The gate is shut meanwhile: nothing launches for a module
/// that is off.
///
/// **The runner never exits until told** (a `brew` that has run for the seconds
/// that matter), and its handle records a TERM without ending the stream, as
/// the real one does: the child dies, then EOF, then `onExit`.
final class ASwitchOffLeavesNoMarkerBehindTests: XCTestCase {

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct AllowingPrivileged: PrivilegedRunner {
        func runAdmin(_ script: String) -> PrivilegedOutcome { .done }
    }

    private final class Handle: RunningProcess, @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var terminations: Int { lock.lock(); defer { lock.unlock() }; return n }
        func terminate() { lock.lock(); n += 1; lock.unlock() }
    }

    private final class Runner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _handles: [Handle] = []
        private var _exits: [@Sendable (Int32) -> Void] = []
        var handles: [Handle] { lock.lock(); defer { lock.unlock() }; return _handles }
        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            // The Cellar a doctor fix is judged against.
            if args.first == "list" { return (0, args.contains("--cask") ? "" : "wget 1.25.0\n") }
            return (0, "")
        }
        func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                     env: [String: String]) -> (status: Int32, output: String) { (0, "") }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            let handle = Handle()
            lock.lock(); _handles.append(handle); _exits.append(onExit); lock.unlock()
            return handle
        }
        func exitAll(code: Int32) {
            lock.lock(); let exits = _exits; _exits = []; lock.unlock()
            for exit in exits { exit(code) }
        }
    }

    /// Reports what is written *now*, without taking it the way `status()` does.
    private final class SpyMarker: OpMarker, @unchecked Sendable {
        private let lock = NSLock()
        private var label: String?
        var written: String? { lock.lock(); defer { lock.unlock() }; return label }
        func write(_ label: String) { lock.lock(); self.label = label; lock.unlock() }
        func clear() { lock.lock(); label = nil; lock.unlock() }
        func take() -> String? { lock.lock(); defer { lock.unlock() }; defer { label = nil }; return label }
    }

    private enum Kind: CaseIterable {
        case installHomebrew, install, upgradeAll, doctorFix
        /// Only the install of Homebrew itself is ended by a switch-off.
        var terminated: Int { self == .installHomebrew ? 1 : 0 }
        var label: String {
            switch self {
            case .installHomebrew: return HomebrewEngine.installBrewLabel
            case .install: return "install wget"
            case .upgradeAll: return "upgrade all"
            case .doctorFix: return "uninstall wget"
            }
        }
        func start(_ engine: HomebrewEngine) {
            switch self {
            case .installHomebrew: engine.installBrew()
            case .install: engine.install(name: "wget", isCask: false)
            case .upgradeAll: engine.upgradeAll()
            case .doctorFix: engine.runDoctorFix(["uninstall", "wget"])
            }
        }
    }

    private func engine(_ runner: ProcessRunner, _ marker: OpMarker, news: EngineNews<HomebrewNews> = EngineNews()) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner, privileged: AllowingPrivileged(),
                       user: "tester", news: news, marker: marker)
    }

    func testASwitchOffTerminatesOnlyTheInstallAndTheMarkerGoesWhenTheChildDoes() {
        for kind in Kind.allCases {
            let runner = Runner()
            let marker = SpyMarker()
            let news = EngineNews<HomebrewNews>()
            let running = engine(runner, marker, news: news)
            kind.start(running)
            XCTAssertEqual(runner.handles.count, 1, "\(kind): precondition — the child runs")
            XCTAssertEqual(marker.written, kind.label, "\(kind): precondition — the marker is written")

            running.deactivate()

            XCTAssertEqual(runner.handles.first?.terminations, kind.terminated,
                           "\(kind): the switch-off sent the wrong number of TERMs to the child")
            XCTAssertEqual(marker.written, kind.label, "\(kind): the marker went before the child did")
            XCTAssertNil(running.status().interruptedOp, "\(kind): busy was false while the child still ran")
            XCTAssertEqual(marker.written, kind.label, "\(kind): a status read took the marker of a running child")

            runner.exitAll(code: kind.terminated == 1 ? 143 : 0)

            XCTAssertNil(marker.written, "\(kind): the child is gone and the marker stayed")
            XCTAssertNil(engine(Runner(), marker).status().interruptedOp,
                         "\(kind): the next enable reported a ghost \"running at quit\"")
        }
    }

    /// The host drops the engine after `deactivate()`: the exit must still be
    /// heard, which a weak capture of the engine could not do.
    func testTheExitOfADroppedEnginesChildStillClearsTheMarker() {
        for kind in Kind.allCases {
            let runner = Runner()
            let marker = SpyMarker()
            autoreleasepool {
                let dropped = engine(runner, marker)
                kind.start(dropped)
                dropped.deactivate()
            }
            XCTAssertEqual(marker.written, kind.label, "\(kind): the marker went before the child did")

            runner.exitAll(code: 0)

            XCTAssertNil(marker.written, "\(kind): nobody cleared the marker after the engine was dropped")
        }
    }

    func testAnOperationSwitchedOffIsSaidOnce() async {
        for kind in Kind.allCases {
            let runner = Runner()
            let news = EngineNews<HomebrewNews>()
            let running = engine(runner, SpyMarker(), news: news)
            let tape = news.stream()
            kind.start(running)
            running.deactivate()
            runner.exitAll(code: kind.terminated == 1 ? 143 : 0)

            news.say(.line("test.sentinel"), slot: "test.sentinel")
            var terminal: [OpState] = []
            for await item in tape {
                if case .line("test.sentinel") = item { break }
                if case .state(let s) = item, s.phase != .running { terminal.append(s) }
            }
            XCTAssertEqual(terminal.count, 1, "\(kind): ended \(terminal.count) times: \(terminal)")
            // The install is the person's stop; the others end as they ended.
            XCTAssertEqual(terminal.first?.reason == .stopped, kind.terminated == 1,
                           "\(kind): the ending is worded wrongly: \(terminal)")
        }
    }

    /// Nothing launches for a module that is off — idle or not, whichever
    /// door the operation comes through — until it is activated again.
    func testNothingLaunchesAfterTheSwitchOffUntilItIsEnabledAgain() {
        for kind in Kind.allCases {
            let runner = Runner()
            let marker = SpyMarker()
            let off = engine(runner, marker)
            off.deactivate()

            kind.start(off)

            XCTAssertTrue(runner.handles.isEmpty, "\(kind): a child was launched for a module that is off")
            XCTAssertNil(marker.written, "\(kind): a marker was written for a child that never ran")

            off.activate()
            kind.start(off)
            XCTAssertEqual(runner.handles.count, 1, "\(kind): the gate stayed shut after the module came back")
            runner.exitAll(code: 0)
        }
    }

    /// A doctor fix whose Cellar read is still out when the switch-off lands:
    /// the launch behind that read is refused.
    func testASwitchOffDuringTheFixsCellarReadLaunchesNothing() {
        let runner = Runner()
        let marker = SpyMarker()
        let hook = HookedRunner(runner)
        let off = engine(hook, marker)
        hook.onList = { [weak off] in off?.deactivate() }

        off.runDoctorFix(["uninstall", "wget"])

        XCTAssertTrue(runner.handles.isEmpty, "a fix launched for a module switched off while it was judged")
        XCTAssertNil(marker.written)
    }

    // MARK: - A fresh engine beside the one still running

    /// The host builds a new engine on every enable, and a package operation
    /// runs to its end after a switch-off: the two engines share one gate and
    /// one marker. Nothing the new one does may read as, or touch, the old one's
    /// operation — a second `brew` on the same Cellar, a "running at quit" about
    /// an operation that is running now, or the old exit deleting the new marker.
    func testAFreshEngineBesideARunningOneLaunchesNothingAndTakesNoMarker() {
        let runner = Runner()
        let marker = SpyMarker()
        let gate = OperationGate()
        let old = HomebrewEngine(locator: FixedLocator(), runner: runner, privileged: AllowingPrivileged(),
                                 user: "tester", marker: marker, gate: gate)
        old.upgradeAll()
        old.deactivate()

        let fresh = HomebrewEngine(locator: FixedLocator(), runner: runner, privileged: AllowingPrivileged(),
                                   user: "tester", marker: marker, gate: gate)
        fresh.activate()

        fresh.uninstall(name: "wget", isCask: false)
        XCTAssertEqual(runner.handles.count, 1, "a second brew started against the Cellar the first is changing")
        XCTAssertNil(fresh.status().interruptedOp, "a running operation was reported as left by a quit")
        XCTAssertEqual(marker.written, "upgrade all", "the new engine took the running operation's marker")

        runner.exitAll(code: 0)                    // the old operation ends
        XCTAssertNil(marker.written)
        fresh.uninstall(name: "wget", isCask: false)
        XCTAssertEqual(runner.handles.count, 2, "the gate stayed shut after the old operation ended")
        XCTAssertEqual(marker.written, "uninstall wget")

        runner.exitAll(code: 0)
        XCTAssertNil(marker.written)
    }

    /// The order that keeps a late exit from deleting a newer marker: the old
    /// operation clears its marker **before** it gives the gate back, so the new
    /// one cannot have written by then.
    func testTheOldExitClearsBeforeTheGateOpensForTheNextOperation() {
        let runner = Runner()
        let marker = SpyMarker()
        let gate = OperationGate()
        let old = HomebrewEngine(locator: FixedLocator(), runner: runner, privileged: AllowingPrivileged(),
                                 user: "tester", marker: marker, gate: gate)
        let fresh = HomebrewEngine(locator: FixedLocator(), runner: runner, privileged: AllowingPrivileged(),
                                   user: "tester", marker: marker, gate: gate)
        old.upgradeAll()
        old.deactivate()
        runner.exitAll(code: 0)
        fresh.install(name: "jq", isCask: false)
        XCTAssertEqual(marker.written, "install jq")

        runner.exitAll(code: 0)                    // nothing of the old operation is left to exit
        XCTAssertNil(marker.written)
        XCTAssertEqual(runner.handles.count, 2)
    }

    private final class HookedRunner: ProcessRunner, @unchecked Sendable {
        let inner: Runner
        var onList: (@Sendable () -> Void)?
        init(_ inner: Runner) { self.inner = inner }
        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            let answer = inner.run(launchPath, args, env: env)
            if args.first == "list" { onList?() }
            return answer
        }
        func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                     env: [String: String]) -> (status: Int32, output: String) { (0, "") }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            inner.stream(launchPath, args, env: env, onLine: onLine, onExit: onExit)
        }
    }
}
