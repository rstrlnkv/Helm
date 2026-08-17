// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmRuntime
@testable import Module_VPN_Engine

/// **A rule that cannot reach its secret must say so, and must stop trying.**
///
/// Two correct changes met and produced the one outcome this app may not produce.
/// `CredentialCachePurge` empties Helm's own cache once — the items it removes
/// carry an access list that let any process running as this user read the secret
/// — and `credentials(for:promptingAllowed:)` refuses the System keychain for an
/// automatic connect, because a forged rule could otherwise summon an
/// authorization dialog at a moment of its own choosing. Empty cache plus no
/// prompt is **no secret at all**, and the only account of it was a log line:
///
/// ```
/// 00:18:01 [vpn] connect vpn#dca3 (auto)
/// 00:18:01 [vpn] no cached credentials for vpn#dca3; an automatic connect does
///                not ask the System keychain
/// ```
///
/// — three times in an hour, each one running a `--nc start` that could not work,
/// each one announcing a connection nobody had.
///
/// The security fix is not weakened anywhere below: the prompt is still refused
/// for `auto: true`. What changes is that the refusal is a **state** rather than a
/// silence, and that the port stops folding «this configuration keeps no secret»
/// (IKEv2, WireGuard) into the same nil as «there is one and Helm may not read
/// it» — without that separation the notice would be drawn under every automatic
/// connect on the machine, which is ARCHITECTURE.md § A warning that is always
/// true is not a warning.
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
        let engine = VPNEngine(settings: VPNSettings(store: NamespacedStore(
                                    namespace: "vpn", backing: InMemoryKeyValueStore())),
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

    /// Only one of the three answers is news, and the other two are the reverse
    /// channel: a read that produced a secret, and a configuration that keeps
    /// none, both mean there is nothing to tell anybody.
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

    /// The list is the other reverse channel: a tunnel that is up needed nothing
    /// from Helm after all, and one that has been deleted in System Settings is
    /// not something to draw a sentence about.
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

    // MARK: - The engine, and the wire

    /// The state the user's log had and the screen did not.
    func testAnAutomaticConnectPutsTheUnreachableSecretOnTheWire() async {
        let creds = FakeCreds()
        creds.behindAPrompt["Office"] = VPNCredentials(user: "u", password: "p", secret: "s")
        let runner = FakeRunner()
        let engine = engine(runner, creds)

        engine.connect("Office", auto: true)

        XCTAssertEqual(engine.secretsBehindAPrompt, ["Office"],
                       "the rule reached a dead end and nothing but the log knew")
        var payload: VPNEngine.StatePayload?
        for await event in engine.transport.events where event.name == VPNEvent.state.rawValue {
            payload = try? JSONDecoder().decode(VPNEngine.StatePayload.self, from: event.payload)
            break
        }
        XCTAssertEqual(payload?.secretsBehindAPrompt, ["Office"],
                       "the engine knew and no screen could")
    }

    /// **The control, and the reason the port had to stop answering nil to two
    /// questions.** An IKEv2 configuration keeps no secret Helm supplies, and an
    /// automatic connect of one is the ordinary case on this Mac — a notice drawn
    /// there would be drawn always, for everybody, and would mean nothing.
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

    /// Finding three: three attempts in an hour, three `--nc start`s that could
    /// not work. The first one is spent — Helm cannot know the tool needs the
    /// secret until it has tried — and the ones after it are refused.
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

    /// A press of Connect is the gesture the prompt sits behind, and the read it
    /// performs is what fills Helm's cache — so it is also the one thing that can
    /// clear this. The fake's own cache is what the real port would have written.
    func testTheSecretBecomingReadableClearsTheBook() {
        let creds = FakeCreds()
        creds.behindAPrompt["Office"] = VPNCredentials(secret: "s")
        let runner = FakeRunner()
        let engine = engine(runner, creds)

        engine.connect("Office", auto: true)
        XCTAssertEqual(engine.secretsBehindAPrompt, ["Office"], "precondition")

        // The press itself, and nothing arranged behind it: the fake reads its
        // System tier only where a prompt is allowed and caches what it read,
        // which is what the real port does and what makes one press enough.
        engine.connect("Office")

        XCTAssertEqual(engine.secretsBehindAPrompt, [],
                       "the notice outlived the thing it was about")
        XCTAssertEqual(starts(runner).count, 2, "and the press itself did nothing")
        XCTAssertTrue(starts(runner).last?.contains("--secret") ?? false,
                      "the secret a person asked for never reached the command")
    }

    /// The other way it stops being true, and the one Helm is not told about:
    /// the tunnel came up regardless — somebody raised it in System Settings, or
    /// this configuration never needed Helm's secret in the first place.
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

    /// **And it must not announce what it could not do.** `--nc start` answers
    /// nothing whether it worked or not, so a start Helm knowingly under-supplied
    /// used to light the ring and put «Office» in the menu bar — one screen saying
    /// the Mac is behind a tunnel while another says the rule could not fire. The
    /// same harm `VPNAutomation.Kind.dropped` exists to warn about, manufactured
    /// by the app.
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

    /// The control for the assertion above: an automatic connect Helm *could*
    /// supply is announced exactly as before.
    func testAConnectionItCouldSupplyIsStillAnnounced() {
        let creds = FakeCreds()
        creds.map["Office"] = VPNCredentials(secret: "s")
        let runner = FakeRunner()
        let engine = engine(runner, creds)
        engine.clearLastAutomationForTesting()

        engine.connect("Office", auto: true)

        XCTAssertEqual(engine.lastAutomation?.kind, .connected)
    }

    /// A payload from a build that predates the field decodes whole. A stored
    /// default does not buy this on its own — Swift's synthesised `Decodable`
    /// requires the key regardless, and `JSONDecoder` then gives up on the
    /// document rather than on the field, which would cost the page every
    /// connection it draws (CLAUDE.md § a `defaulted` property on a `Codable`
    /// payload).
    func testAPayloadFromBeforeThisFieldStillDecodesWithEverythingElseInIt() throws {
        let legacy = Data("""
        {"connections":[{"id":"1","name":"Office","status":"connected"}],
         "autoConnected":[],"defaultName":"Office"}
        """.utf8)

        let payload = try JSONDecoder().decode(VPNEngine.StatePayload.self, from: legacy)

        XCTAssertEqual(payload.connections.count, 1,
                       "one missing field cost the page everything else in the payload")
        XCTAssertEqual(payload.secretsBehindAPrompt, [])
    }
}
