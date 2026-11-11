// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmRuntime
@testable import Module_VPN_Engine

/// **A `scutil --nc show` that failed or timed out is not «this configuration
/// keeps no secret».**
///
/// `KeychainCredentials.credentials` answered `.notNeeded` for both, so a connect
/// that needed the secret went to `--nc start` without it; `--nc start` answers
/// nothing either way, so a rule connect then recorded and announced «connected»
/// with no tunnel behind it. Owner decision 2026-11-11 (defects page row
/// `vpn-show-unreadable`): a separate `VPNCredentialRead.unreadable` that neither
/// starts nor announces the connect.
///
/// An unattended rule announcing a tunnel that is not there is work done while
/// nobody watches, so this class is kept.
final class AnUnreadableConfigurationIsNotAConnectTests: XCTestCase {

    private let header = "Available network connection services:"
    private let id = "11111111-1111-1111-1111-111111111111"

    override func setUp() {
        super.setUp()
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.setEnabled(false)
        HelmLog.shared.clearTail()
        super.tearDown()
    }

    // MARK: - The port: KeychainCredentials

    private final class ShowRunner: VPNRunnerPort, @unchecked Sendable {
        let answer: HelmProcess.Result
        init(_ answer: HelmProcess.Result) { self.answer = answer }
        func run(_ args: [String]) -> HelmProcess.Result { answer }
        func read(_ args: [String], timeout: TimeInterval) -> HelmProcess.Result { answer }
        func start(_ name: String, supplying credentials: VPNCredentials) -> VPNStartAnswer { .started }
    }

    private func read(_ answer: HelmProcess.Result) -> VPNCredentialRead {
        // `purge: {}`: no test may run the real keychain purge.
        KeychainCredentials(purge: {}, runner: ShowRunner(answer))
            .credentials(for: "Office", promptingAllowed: false)
    }

    func testAShowThatTimedOutIsUnreadable() {
        XCTAssertEqual(read(.init(status: HelmProcess.timedOutStatus, output: "")), .unreadable)
    }

    func testAShowThatExitedNonZeroIsUnreadable() {
        XCTAssertEqual(read(.init(status: 1, output: "")), .unreadable)
    }

    func testAShowThatExitedNonZeroAfterPrintingASecretFieldIsStillUnreadable() {
        XCTAssertEqual(read(.init(status: 1, output: "<dictionary> {\n  AuthPassword : X\n}\n")),
                       .unreadable)
    }

    /// The control: a read that worked and found no `AuthPassword` is the
    /// ordinary IKEv2 case, and stays `.notNeeded`.
    func testAShowThatAnsweredWithNoSecretIsStillNotNeeded() {
        XCTAssertEqual(read(.init(status: 0, output: "<dictionary> {\n  UserDefinedName : Office\n}\n")),
                       .notNeeded)
    }

    // MARK: - The book

    /// `.unreadable` has its own step and leaves the book as it found it: it is
    /// neither a secret behind a prompt (no entry) nor proof of none (no removal).
    func testAnUnreadableReadLeavesTheSecretBookAsItWas() {
        var book = VPNSecretBook()
        XCTAssertEqual(book.step(for: .unreadable, name: "Office", automatic: true), .unreadable)
        XCTAssertEqual(book.step(for: .unreadable, name: "Office", automatic: false), .unreadable)
        XCTAssertEqual(book.names, [], "an unreadable read entered the book")

        _ = book.step(for: .behindAPrompt, name: "Office", automatic: true)
        XCTAssertEqual(book.step(for: .unreadable, name: "Office", automatic: true), .unreadable)
        XCTAssertEqual(book.names, ["Office"], "an unreadable read cleared what an earlier read learned")
    }

    // MARK: - The engine

    private func engine(_ runner: FakeRunner, _ creds: FakeCreds) -> VPNEngine {
        runner.listOutput = [header, "* (Disconnected) \(id) IPSec \"Office\" [IPSec:1]"]
            .joined(separator: "\n")
        let engine = VPNEngine(settings: VPNSettings(store: NamespacedStore(
                                    namespace: "vpn", backing: InMemoryKeyValueStore())),
                               runner: runner, credentials: creds, apps: FakeApps(),
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)
        engine.refresh()
        engine.clearLastAutomationForTesting()
        return engine
    }

    private func starts(_ runner: FakeRunner) -> [[String]] {
        runner.issued.filter { $0.count > 1 && $0[1] == "start" }
    }

    private func vpnLog() -> [String] {
        HelmLog.shared.recentEntries().filter { $0.category == "vpn" }.map { $0.message.lowercased() }
    }

    /// Rule connect, secret unreadable: no start, nothing announced, a line
    /// says why and does not carry the name.
    func testARuleConnectWhoseSecretIsUnreadableStartsNothingAndAnnouncesNothing() {
        let creds = FakeCreds()
        creds.unreadable = ["Office"]
        let runner = FakeRunner()
        let engine = engine(runner, creds)

        engine.connect("Office", auto: true)

        XCTAssertEqual(creds.asks.map(\.name), ["Office"], "precondition: the secret was asked for")
        XCTAssertTrue(starts(runner).isEmpty,
                      "a start went out without a secret the configuration may need: \(starts(runner))")
        XCTAssertTrue(runner.supplied.isEmpty, "a start with credentials went out")
        XCTAssertNil(engine.lastAutomation,
                     "the menu bar / banner announced a tunnel nobody started")
        XCTAssertFalse(engine.autoConnected.contains("Office"),
                       "Helm claimed a tunnel it never started")
        let lines = vpnLog()
        XCTAssertTrue(lines.contains { $0.contains("unreadable") || $0.contains("could not be read")
                                       || $0.contains("cannot be read") },
                      "nothing in the log says the connect was not attempted: \(lines)")
        XCTAssertFalse(lines.contains { $0.contains("office") }, "the log carries the name: \(lines)")
    }

    /// An unreadable read is not a locked secret: the page must not tell the
    /// person to press Connect for a prompt that is not the problem.
    func testAnUnreadableSecretIsNotReportedAsBehindAPrompt() {
        let creds = FakeCreds()
        creds.unreadable = ["Office"]
        let engine = engine(FakeRunner(), creds)
        engine.connect("Office", auto: true)
        XCTAssertEqual(engine.secretsBehindAPrompt, [])
    }

    /// An unreadable read is not remembered as a refusal either: the next launch
    /// asks again (the next `show` may answer), it is not a second-attempt ban.
    func testAnUnreadableSecretIsAskedAgainAtTheNextRuleConnect() {
        let creds = FakeCreds()
        creds.unreadable = ["Office"]
        let runner = FakeRunner()
        let engine = engine(runner, creds)
        engine.connect("Office", auto: true)
        creds.unreadable = []
        engine.connect("Office", auto: true)
        XCTAssertEqual(creds.asks.count, 2)
        XCTAssertEqual(starts(runner).count, 1, "the read recovered and the connect did not go")
        XCTAssertEqual(engine.lastAutomation?.kind, .connected)
    }

    /// The control: `.notNeeded` starts and announces as before.
    func testARuleConnectThatNeedsNoSecretStartsAndAnnounces() {
        let creds = FakeCreds()
        let runner = FakeRunner()
        let engine = engine(runner, creds)

        engine.connect("Office", auto: true)

        XCTAssertEqual(starts(runner).count, 1)
        XCTAssertEqual(engine.lastAutomation?.kind, .connected)
    }

    /// A person's press with the secret unreadable: no start. The refusal is the
    /// module's one person-facing failure, `lastFailure` with verb `.connect` and
    /// its own reason, `.secretUnreadable` (not `.refused`, whose sentence says
    /// macOS refused). A rule has no one pressing, so only this path sets it.
    func testAPressWhoseSecretIsUnreadableStartsNothingAndSaysSo() {
        let creds = FakeCreds()
        creds.unreadable = ["Office"]
        let runner = FakeRunner()
        let engine = engine(runner, creds)

        engine.connect("Office", auto: false)

        XCTAssertTrue(starts(runner).isEmpty, "a start went out without the secret: \(starts(runner))")
        XCTAssertTrue(runner.supplied.isEmpty)
        XCTAssertEqual(engine.lastFailure, VPNFailure(name: "Office", reason: .secretUnreadable, verb: .connect),
                       "the person pressed Connect and nothing happened and nothing said why")
        XCTAssertNil(engine.lastAutomation)
    }
}
