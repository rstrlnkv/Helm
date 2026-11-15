// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime
import XCTest
@testable import Module_VPN_Engine

/// **A `scutil` read that never answers must not park `VPNWorkQueue` for the
/// life of the process.**
///
/// The defect this class was written for: `scutil --nc list` and `--nc status`
/// were run through `ScutilRunner.run`, which is `HelmProcess.run` without a
/// `timeout:`, and `refreshNow` / `readInterfaces` blocked on it on the module's
/// one serial queue. A wedged `scutil` (an `NEVPNManager` daemon that does not
/// reply is the usual cause) then stopped every later refresh, connect, stop and
/// poll behind it, and the page kept drawing the last state with no line in the
/// log saying why.
///
/// What it guards now: the queries (`--nc list`, `--nc status`, `--nc show`) go
/// through `VPNRunnerPort.read(_:timeout:)`, which the engine calls with
/// `vpnReadDeadline` and `ScutilRunner.read` passes on as `timeout:`, so a read
/// that runs out of time comes back as `HelmProcess.timedOutStatus`, the last
/// answer is kept, and a log line names the timeout. Only the commands
/// (`--nc start` / `stop`) still go through the unbounded `run`.
///
/// **The seam.** The runner is a port (`VPNRunnerPort`), so «a tool that never
/// answers» can be written down; the deadline itself lives in the production
/// `ScutilRunner`, whose path is a literal and which a test may not take
/// (`NoTestTakesAProductionPortTests`). So what is asserted here is the
/// engine's side of the contract, from both ends: a call that never returns
/// must not park the module (the engine, not only the runner, bounds it), and a
/// call that comes back `timedOutStatus` must be told apart from silence.
///
/// The fake finishes its prompt: every hang is released in `tearDown`, and every
/// wait in a test is an expectation with its own bound, so a regression costs
/// seconds and never the suite.
///
/// Past defect: commit ed737900, «fix: scutil reads have a deadline and read the exit status» and backlog rows M104/M278.
final class AHungScutilDoesNotParkTheModuleTests: XCTestCase {

    private static let header = "Available network connection services in the current set (*=enabled):"
    private static let uuid = "11111111-1111-1111-1111-111111111111"
    private static func list(_ status: String) -> String {
        "\(header)\n* (\(status)) \(uuid) PPP --> L2TP \"A\" [PPP:L2TP]\n"
    }
    private static let tunnelIsUp = "Connected\nExtended Status <dictionary> {\n  IPv4 : <dictionary> {\n"
        + "    InterfaceName : utun3\n  }\n}\n"

    /// How long a refresh may take before it counts as parked. Far above any
    /// deadline a `scutil` read could sensibly carry, far below the suite.
    private let bound: TimeInterval = 3

    private enum Step { case answer(HelmProcess.Result), hang }

    /// A tool scripted per command, that can be made to never answer.
    private final class Runner: VPNRunnerPort, @unchecked Sendable {
        private let lock = NSLock()
        private var _issued: [[String]] = []
        private let release = DispatchSemaphore(value: 0)
        var handler: (@Sendable (_ args: [String], _ nth: Int) -> Step)?

        var issued: [[String]] { lock.lock(); defer { lock.unlock() }; return _issued }
        func count(of args: [String]) -> Int { issued.filter { $0 == args }.count }

        /// A command: unbounded, so a scripted hang really parks the caller.
        func run(_ args: [String]) -> HelmProcess.Result { answer(args, bounded: false) }

        /// A query: bounded, like `ScutilRunner.read`. A scripted hang comes back
        /// at once with what the real runner answers once its deadline has
        /// passed — `timedOutStatus` and no output — so the engine is tested on
        /// what it does with that answer, and a test never waits out a clock.
        func read(_ args: [String], timeout: TimeInterval) -> HelmProcess.Result {
            answer(args, bounded: true)
        }

        private func answer(_ args: [String], bounded: Bool) -> HelmProcess.Result {
            lock.lock()
            let nth = _issued.filter { $0 == args }.count
            _issued.append(args)
            lock.unlock()
            switch handler?(args, nth) ?? .answer(.init(status: 0, output: "")) {
            case .answer(let result): return result
            case .hang:
                if bounded { return .init(status: HelmProcess.timedOutStatus, output: "") }
                _ = release.wait(timeout: .now() + 120)
                return .init(status: -1, output: "")
            }
        }
        func start(_ name: String, supplying credentials: VPNCredentials) -> VPNStartAnswer { .started }
        /// Lets every parked call go, so no thread outlives its test.
        func releaseAll() { for _ in 0..<16 { release.signal() } }
    }

    private var runner: Runner!

    override func setUp() {
        super.setUp()
        runner = Runner()
        tailTheLog()
    }

    override func tearDown() {
        runner.releaseAll()
        super.tearDown()
    }

    private func makeEngine() -> VPNEngine {
        VPNEngine(settings: VPNSettings(store: NamespacedStore(namespace: "vpn",
                                                               backing: InMemoryKeyValueStore())),
                  runner: runner, apps: FakeApps(),
                  interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                  work: .inline)
    }

    /// Runs `body` off the test's thread and says whether it came back in time.
    /// A parked body is left parked (and released at teardown); the test goes on.
    private func finishes(_ what: String, within seconds: TimeInterval = 3,
                          _ body: @escaping @Sendable () -> Void) -> Bool {
        let done = expectation(description: what)
        DispatchQueue.global().async { body(); done.fulfill() }
        return XCTWaiter().wait(for: [done], timeout: seconds) == .completed
    }

    private func vpnLog() -> [String] {
        loggedLines("vpn").map { $0.lowercased() }
    }

    private func namesATimeout(_ lines: [String]) -> Bool {
        lines.contains { $0.contains("timed out") || $0.contains("timeout") || $0.contains("did not answer") }
    }

    // MARK: - 1. `--nc list`

    func testAListReadThatNeverAnswersDoesNotParkTheRefresh() {
        runner.handler = { args, nth in
            guard args == ["--nc", "list"] else { return .answer(.init(status: 0, output: "")) }
            return nth == 0 ? .answer(.init(status: 0, output: Self.list("Connected"))) : .hang
        }
        let e = makeEngine()
        e.refresh()
        XCTAssertEqual(e.connections.map(\.name), ["A"], "precondition: the first read gave a list")

        XCTAssertTrue(finishes("a refresh whose list read never answers") { e.refresh() },
                      "`refreshNow` is still waiting on `scutil --nc list` after \(Int(bound)) s: "
                      + "no deadline, so the module's queue is parked")
        XCTAssertEqual(runner.count(of: ["--nc", "list"]), 2, "precondition: the hanging read was reached")
        XCTAssertEqual(e.connections.map(\.name), ["A"],
                       "the previous answer was not kept across a read that never came")
        XCTAssertTrue(namesATimeout(vpnLog()), "no log line names the timeout: \(vpnLog())")
    }

    func testTheQueueStillRunsWorkAfterAListReadThatNeverAnswered() {
        runner.handler = { args, nth in
            guard args == ["--nc", "list"] else { return .answer(.init(status: 0, output: "")) }
            return nth == 0 ? .hang : .answer(.init(status: 0, output: Self.list("Connected")))
        }
        let e = makeEngine()
        _ = finishes("the hung refresh") { e.refresh() }

        XCTAssertTrue(finishes("the next refresh") { e.refresh() },
                      "work offered after a hung `scutil` never ran: the queue is parked")
        XCTAssertEqual(e.connections.map(\.name), ["A"],
                       "the refresh after the hang did not publish its answer")
    }

    /// The port's own word for a read that ran out of time is not silence.
    func testAListReadThatTimedOutIsNamedAsATimeoutAndKeepsTheLastAnswer() {
        runner.handler = { args, nth in
            guard args == ["--nc", "list"] else { return .answer(.init(status: 0, output: "")) }
            return nth == 0 ? .answer(.init(status: 0, output: Self.list("Connected")))
                : .answer(.init(status: HelmProcess.timedOutStatus, output: ""))
        }
        let e = makeEngine()
        e.refresh()
        e.refresh()
        XCTAssertEqual(runner.count(of: ["--nc", "list"]), 2, "precondition: both reads happened")
        XCTAssertEqual(e.connections.map(\.name), ["A"], "the last answer was not kept")
        XCTAssertTrue(namesATimeout(vpnLog()),
                      "a timed-out read was logged as plain silence («unreadable»): \(vpnLog())")
    }

    // MARK: - 2. `--nc status`

    func testAStatusReadThatNeverAnswersDoesNotParkTheRefresh() {
        runner.handler = { args, nth in
            if args == ["--nc", "list"] { return .answer(.init(status: 0, output: Self.list("Connected"))) }
            if args.count == 3, args[1] == "status" {
                return nth == 0 ? .hang : .answer(.init(status: 0, output: Self.tunnelIsUp))
            }
            return .answer(.init(status: 0, output: ""))
        }
        let e = makeEngine()
        XCTAssertTrue(finishes("a refresh whose status read never answers") { e.refresh() },
                      "`readInterfaces` is still waiting on `scutil --nc status` after \(Int(bound)) s: "
                      + "no deadline, so the module's queue is parked")
        XCTAssertEqual(runner.count(of: ["--nc", "status", "A"]), 1, "precondition: the hanging read was reached")
        XCTAssertTrue(namesATimeout(vpnLog()), "no log line names the timeout: \(vpnLog())")
        XCTAssertEqual(e.connections.map(\.name), ["A"], "the list read before the hang was lost")
    }

    func testTheQueueStillRunsWorkAfterAStatusReadThatNeverAnswered() {
        runner.handler = { args, nth in
            if args == ["--nc", "list"] { return .answer(.init(status: 0, output: Self.list("Connected"))) }
            if args.count == 3, args[1] == "status" {
                return nth == 0 ? .hang : .answer(.init(status: 0, output: Self.tunnelIsUp))
            }
            return .answer(.init(status: 0, output: ""))
        }
        let e = makeEngine()
        _ = finishes("the hung refresh") { e.refresh() }
        XCTAssertTrue(finishes("the next refresh") { e.refresh() },
                      "work offered after a hung `scutil --nc status` never ran: the queue is parked")
        XCTAssertGreaterThanOrEqual(runner.count(of: ["--nc", "list"]), 2, "the next refresh did not read the list")
    }

    func testAStatusReadThatTimedOutIsNamedAsATimeout() {
        runner.handler = { args, _ in
            if args == ["--nc", "list"] { return .answer(.init(status: 0, output: Self.list("Connected"))) }
            if args.count == 3, args[1] == "status" {
                return .answer(.init(status: HelmProcess.timedOutStatus, output: ""))
            }
            return .answer(.init(status: 0, output: ""))
        }
        let e = makeEngine()
        e.refresh()
        XCTAssertEqual(runner.count(of: ["--nc", "status", "A"]), 1, "precondition: the status read happened")
        XCTAssertTrue(namesATimeout(vpnLog()),
                      "a status read that ran out of time left no line naming it: \(vpnLog())")
    }


    // MARK: - 3. `--nc show` (KeychainCredentials)

    private func credentialsOnThis() -> KeychainCredentials {
        // `purge: {}`: no test may run the real keychain purge.
        KeychainCredentials(purge: {}, runner: runner,
                            keychainDeadline: KeychainCredentials.systemKeychainDeadline)
    }

    /// The answer is `.unreadable` (defects page row `vpn-show-unreadable`,
    /// owner decision 2026-11-11): «this read timed out» is not «this
    /// configuration keeps no secret», and a connect must not go on as if it
    /// were. The log line names the timeout either way.
    func testAShowThatNeverAnswersReturnsWithinTheBoundAndSaysSo() {
        runner.handler = { _, _ in .hang }
        let credentials = Unsafe(credentialsOnThis())
        let answer = ResultBox()
        XCTAssertTrue(finishes("a credential read whose `--nc show` never answers") {
            answer.value = credentials.value.credentials(for: "Quiet Office", promptingAllowed: false)
        }, "the credential read is still waiting on `scutil --nc show` after \(Int(bound)) s")
        XCTAssertEqual(runner.count(of: ["--nc", "show", "Quiet Office"]), 1, "precondition: the show read was made")
        XCTAssertEqual(answer.value, .unreadable)
        XCTAssertTrue(namesATimeout(vpnLog()), "no log line names the timeout: \(vpnLog())")
        XCTAssertFalse(vpnLog().contains { $0.contains("quiet office") },
                       "the log line carries the connection's name: \(vpnLog())")
    }

    /// The control: a show that answers, with no `AuthPassword`, is `.notNeeded`
    /// without a word in the log — so the line above is about the timeout.
    func testAShowThatAnswersWithNoSecretIsNotNeededAndSilent() {
        runner.handler = { _, _ in .answer(.init(status: 0, output: "<dictionary> {\n  UserDefinedName : A\n}\n")) }
        let credentials = credentialsOnThis()
        XCTAssertEqual(credentials.credentials(for: "A", promptingAllowed: false), .notNeeded)
        XCTAssertEqual(runner.count(of: ["--nc", "show", "A"]), 1, "precondition: the show read was made")
        XCTAssertFalse(namesATimeout(vpnLog()), "a read that answered was logged as a timeout: \(vpnLog())")
    }

    /// The production deadline outlasts a person reading a dialog (minutes) yet
    /// is finite: a default of 0 or 1 s would refuse every prompted read, a
    /// missing bound would park the queue for the life of the process.
    func testTheSystemKeychainDeadlineInProductionOutlastsAPersonAndIsFinite() {
        XCTAssertGreaterThanOrEqual(KeychainCredentials.systemKeychainDeadline, 300)
        XCTAssertLessThanOrEqual(KeychainCredentials.systemKeychainDeadline, 3600)
    }

    /// The System-keychain read has a deadline of its own (`security` may sit
    /// behind a dialog, so it is long in production; here one second against a
    /// stub that sleeps five). The read answers `.behindAPrompt` — the secret
    /// is not known — inside two seconds, names the timeout with no name, and a
    /// following call on the same queue runs.
    func testASystemKeychainReadThatNeverAnswersReturnsWithinItsDeadlineAndSaysSo() throws {
        let dir = scratchDirectory("slow-security")
        let tool = dir.appendingPathComponent("security")
        try "#!/bin/sh\nsleep 5\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let uuid = UUID().uuidString
        runner.handler = { _, _ in
            .answer(.init(status: 0, output: "<dictionary> {\n  AuthPassword : \(uuid)\n}\n"))
        }
        let credentials = Unsafe(KeychainCredentials(purge: {}, runner: runner,
                                                     keychainTool: tool.path, keychainDeadline: 1))
        let queue = DispatchQueue(label: "test.vpn.work")
        let answer = ResultBox()
        let next = expectation(description: "a call behind the read on the same queue")
        let started = Date()
        queue.async { answer.value = credentials.value.credentials(for: "Quiet Office", promptingAllowed: true) }
        queue.async { next.fulfill() }
        XCTAssertEqual(XCTWaiter().wait(for: [next], timeout: 2.5), .completed,
                       "the System-keychain read held the queue past its deadline")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.5)
        XCTAssertEqual(runner.count(of: ["--nc", "show", "Quiet Office"]), 1, "precondition: the show read was made")
        XCTAssertEqual(answer.value, .behindAPrompt)
        XCTAssertTrue(namesATimeout(vpnLog()), "no log line names the timeout: \(vpnLog())")
        XCTAssertFalse(vpnLog().contains { $0.lowercased().contains("quiet office") || $0.contains(uuid.lowercased()) },
                       "the log line carries the connection's name or its keychain service: \(vpnLog())")
    }

    private final class Unsafe<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: VPNCredentialRead?
        var value: VPNCredentialRead? {
            get { lock.lock(); defer { lock.unlock() }; return _value }
            set { lock.lock(); _value = newValue; lock.unlock() }
        }
    }

    // MARK: - 4. Exit status read with stdout

    /// A tool that printed a list and then exited non-zero is not a good
    /// answer: the exit status is read together with the output. This case
    /// stays in this optional class.
    func testAListFromAToolThatExitedNonZeroIsNotAGoodAnswer() {
        runner.handler = { args, nth in
            guard args == ["--nc", "list"] else { return .answer(.init(status: 0, output: "")) }
            return nth == 0 ? .answer(.init(status: 0, output: Self.list("Connected")))
                : .answer(.init(status: 1, output: Self.list("Disconnected")))
        }
        let e = makeEngine()
        e.refresh()
        XCTAssertEqual(e.connections.first?.status.isConnected, true, "precondition: first read was Connected")
        e.refresh()
        XCTAssertEqual(runner.count(of: ["--nc", "list"]), 2, "precondition: the second read happened")
        XCTAssertEqual(e.connections.first?.status.isConnected, true,
                       "a list printed by a tool that exited 1 replaced the last good answer")
        XCTAssertTrue(vpnLog().contains { $0.contains("exit") || $0.contains("status 1") || $0.contains("failed") },
                      "the failed read left no line in the log: \(vpnLog())")
    }

    /// The control: the same two reads, exit 0, are taken — so the test above
    /// cannot pass on an engine that stopped reading lists.
    func testTheSameListFromAToolThatExitedZeroIsTaken() {
        runner.handler = { args, nth in
            guard args == ["--nc", "list"] else { return .answer(.init(status: 0, output: "")) }
            return .answer(.init(status: 0, output: Self.list(nth == 0 ? "Connected" : "Disconnected")))
        }
        let e = makeEngine()
        e.refresh()
        e.refresh()
        XCTAssertEqual(e.connections.first?.status.isConnected, false)
    }
}
