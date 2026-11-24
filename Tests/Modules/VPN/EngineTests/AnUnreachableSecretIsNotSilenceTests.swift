// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
@testable import Module_VPN_Engine

/// **A rule that cannot reach its secret must say so, and must stop trying.**
///
/// `CredentialCachePurge` empties Helm's own cache once, and an automatic
/// connect may not prompt for the System keychain (a forged rule could summon
/// the dialog at a moment of its choosing). Empty cache plus no prompt is **no
/// secret at all**, and a log line alone would leave every retry running a
/// `--nc start` that cannot work, each announcing a connection nobody has.
///
/// The prompt stays refused for `auto: true`. The refusal is a **state**
/// (`VPNSecretBook`, `secretsBehindAPrompt`), and the port keeps «this
/// configuration keeps no secret» (IKEv2, WireGuard) apart from «there is one and
/// Helm may not read it», or the notice would be drawn under every automatic
/// connect, and a warning that is always true is not a warning.
final class AnUnreachableSecretIsNotSilenceTests: XCTestCase {

    private let header = "Available network connection services:"
    private let id = "11111111-1111-1111-1111-111111111111"

    private func list(_ status: String) -> String {
        [header, "* (\(status)) \(id) IPSec \"Office\" [IPSec:1]"].joined(separator: "\n")
    }

    private func engine(_ runner: FakeRunner, _ creds: FakeCreds,
                        status: String = "Disconnected") -> VPNEngine {
        if runner.listScript.isEmpty, runner.listOutput.isEmpty {
            runner.listOutput = list(status)
        }
        let engine = VPNEngine(settings: VPNSettings.inMemory(),
                               runner: runner, credentials: creds, apps: FakeApps(),
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)
        engine.refresh()
        return engine
    }

    private func starts(_ runner: FakeRunner) -> [[String]] {
        runner.issued.filter { $0.count > 1 && $0[1] == "start" }
    }

    // MARK: - The book, on its own

    /// Only one of the three answers is news: a read that produced a secret, and
    /// a configuration that keeps none, both leave nothing to tell.
    func testOnlyASecretBehindAPromptEntersTheBook() {
        var book = VPNSecretBook()
        XCTAssertFalse(book.names.contains("Office"), "precondition: it starts empty")

        XCTAssertEqual(book.step(for: .behindAPrompt, name: "Office", automatic: true),
                       .tryWithoutIt, "the first attempt is spent, since the tool may not "
                       + "need the secret at all")
        XCTAssertTrue(book.names.contains("Office"))
        XCTAssertEqual(book.names, ["Office"])
        XCTAssertEqual(book.step(for: .behindAPrompt, name: "Office", automatic: true),
                       .refuse, "a rule can retry for ever, and every retry is a command it "
                       + "already knows cannot work")
        XCTAssertEqual(book.step(for: .behindAPrompt, name: "Office", automatic: false),
                       .tryWithoutIt, "a person's own press is the gesture the prompt exists "
                       + "for and must reach the tool whatever this book remembers")

        let creds = VPNCredentials(secret: "s")
        XCTAssertEqual(book.step(for: .ready(creds), name: "Office", automatic: true),
                       .supply(creds))
        XCTAssertFalse(book.names.contains("Office"), "a read that succeeded left the notice standing")

        _ = book.step(for: .behindAPrompt, name: "Office", automatic: true)
        XCTAssertEqual(book.step(for: .notNeeded, name: "Office", automatic: true),
                       .nothingToSupply)
        XCTAssertFalse(book.names.contains("Office"),
                       "a configuration that keeps no secret was left in a book about secrets")
    }

    /// The list clears the book too: a tunnel that is up needed nothing from
    /// Helm, and one deleted in System Settings is not worth a sentence.
    func testTheListClearsWhatTheBookCanNoLongerBeAbout() {
        func book(_ connections: [VPNConnection]) -> VPNSecretBook {
            var book = VPNSecretBook()
            _ = book.step(for: .behindAPrompt, name: "Office", automatic: true)
            book.reconcile(against: connections)
            return book
        }
        func office(_ status: VPNStatus) -> [VPNConnection] {
            [VPNConnection(id: id, name: "Office", status: status, kind: "IPSec")]
        }

        XCTAssertTrue(book(office(.disconnected)).names.contains("Office"),
                      "the one state the notice exists for was cleared by an ordinary refresh")
        XCTAssertFalse(book(office(.connected)).names.contains("Office"),
                       "the tunnel is up, so telling the person to press Connect is a page "
                       + "inventing a problem")
        XCTAssertTrue(book(office(.connecting)).names.contains("Office"),
                      "a handshake is not proof the secret was accepted")
        XCTAssertFalse(book([]).names.contains("Office"),
                       "a configuration that is gone was still being named on screen")
    }

    // MARK: - The engine, and its state

    /// The unreachable secret reaches the published state, not only the log.
    func testAnAutomaticConnectPutsTheUnreachableSecretOnTheWire() async {
        let creds = FakeCreds()
        creds.behindAPrompt["Office"] = VPNCredentials(user: "u", password: "p", secret: "s")
        let runner = FakeRunner()
        let engine = engine(runner, creds)

        engine.connect("Office", auto: true)

        XCTAssertEqual(engine.secretsBehindAPrompt, ["Office"],
                       "the rule reached a dead end and nothing but the log knew")
        var payload: VPNEngine.StatePayload?
        for await state in engine.stream() {
            payload = state
            break
        }
        XCTAssertEqual(payload?.secretsBehindAPrompt, ["Office"],
                       "the engine knew and no screen could")
    }

    /// **The control.** An IKEv2 configuration keeps no secret Helm supplies,
    /// and its automatic connect is the ordinary case: a notice there would be
    /// drawn always and mean nothing.
    func testAConfigurationThatKeepsNoSecretIsNeverNamed() {
        let creds = FakeCreds()   // neither tier has anything for «Office»
        let runner = FakeRunner()
        let engine = engine(runner, creds)

        engine.connect("Office", auto: true)

        XCTAssertEqual(engine.secretsBehindAPrompt, [],
                       "a warning that is always true is not a warning")
        XCTAssertFalse(starts(runner).isEmpty,
                       "precondition: the connect that needs no secret still ran")
    }

    /// The first attempt is spent, since Helm cannot know the tool needs the
    /// secret until it has tried; the ones after it are refused.
    func testASecondAutomaticAttemptRunsNoStartItAlreadyKnowsCannotWork() {
        let creds = FakeCreds()
        creds.behindAPrompt["Office"] = VPNCredentials(secret: "s")
        let runner = FakeRunner()
        let engine = engine(runner, creds)

        engine.connect("Office", auto: true)
        XCTAssertEqual(starts(runner).count, 1, "precondition: the first attempt is spent")

        engine.connect("Office", auto: true)
        engine.connect("Office", auto: true)

        XCTAssertEqual(starts(runner).count, 1,
                       "a rule with a launching app can retry for ever, and every retry puts a "
                       + "command it knows cannot work in front of the tool")
        XCTAssertEqual(engine.secretsBehindAPrompt, ["Office"],
                       "and the state that explains the refusal went away with it")
    }

    /// A press of Connect is the gesture the prompt sits behind, and its read
    /// fills Helm's cache, so it is what clears this.
    func testTheSecretBecomingReadableClearsTheBook() {
        let creds = FakeCreds()
        creds.behindAPrompt["Office"] = VPNCredentials(secret: "s")
        let runner = FakeRunner()
        let engine = engine(runner, creds)

        engine.connect("Office", auto: true)
        XCTAssertEqual(engine.secretsBehindAPrompt, ["Office"], "precondition")

        // The press itself, and nothing arranged behind it: the fake reads its
        // System tier only where a prompt is allowed and caches what it read,
        // as the real port does.
        engine.connect("Office", auto: false)

        XCTAssertEqual(engine.secretsBehindAPrompt, [],
                       "the notice outlived the thing it was about")
        XCTAssertEqual(runner.supplied.map(\.name), ["Office"], "and the press itself did nothing")
        XCTAssertEqual(runner.supplied.last?.credentials.secret, "s",
                       "the secret a person asked for never reached the system")
    }

    /// The tunnel coming up regardless clears it too: somebody raised it in
    /// System Settings, or it never needed Helm's secret.
    func testATunnelThatCameUpClearsTheBookByItself() {
        let creds = FakeCreds()
        creds.behindAPrompt["Office"] = VPNCredentials(secret: "s")
        let runner = FakeRunner()
        runner.listScript = [list("Disconnected")]
        let engine = engine(runner, creds)

        engine.connect("Office", auto: true)
        XCTAssertEqual(engine.secretsBehindAPrompt, ["Office"], "precondition")

        runner.listScript = [list("Connected")]
        engine.refresh()

        XCTAssertEqual(engine.secretsBehindAPrompt, [],
                       "the page went on asking for a press against a tunnel that is up")
    }

    /// **It must not announce what it could not do.** A start Helm knowingly
    /// under-supplied must not light the ring or put «Office» in the menu bar
    /// while another screen says the rule could not fire.
    func testNoConnectionIsAnnouncedForASecretHelmCouldNotSupply() {
        let creds = FakeCreds()
        creds.behindAPrompt["Office"] = VPNCredentials(secret: "s")
        let runner = FakeRunner()
        let engine = engine(runner, creds)
        engine.clearLastAutomationForTesting()

        engine.connect("Office", auto: true)

        XCTAssertNil(engine.lastAutomation,
                     "the menu bar named a connection the app knew it had no secret for")
        XCTAssertTrue(engine.autoConnected.contains("Office"),
                      "owning it and announcing it are different questions: the quit rule still "
                      + "has to be able to take this down")
    }

    /// The control: an automatic connect Helm *could* supply is announced.
    func testAConnectionItCouldSupplyIsStillAnnounced() {
        let creds = FakeCreds()
        creds.map["Office"] = VPNCredentials(secret: "s")
        let runner = FakeRunner()
        let engine = engine(runner, creds)
        engine.clearLastAutomationForTesting()

        engine.connect("Office", auto: true)

        XCTAssertEqual(engine.lastAutomation?.kind, .connected)
    }

}
