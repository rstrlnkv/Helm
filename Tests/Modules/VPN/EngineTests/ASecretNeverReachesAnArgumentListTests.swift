// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_VPN_Engine

/// **A secret never rides in an argument list, whichever tool carries it.**
///
/// CLAUDE.md § What not to do, and what breaks if you do (the line on a secret a tool reads;
/// → ARCHITECTURE.md § Running other programs): a secret a tool reads from its terminal
/// goes there, never in argv, env, file or log. An argument list is readable by
/// every process running as this user for as long as the child lives, and a
/// `scutil --nc` child lives long enough to be read. `scutil`
/// has no terminal form, so `--nc start <name> --user … --password … --secret …`
/// is the defect class «a secret in argv» in this module.
///
/// The check is on the structure, not on one spelling: every element of every
/// command the runner was asked to run, whatever the flag is called, must be
/// free of the marker the credentials carry. Each credential carries the marker
/// `7f3a`, so a repair that drops `--secret` but keeps `--password` stays red.
///
/// The secret goes to the system in process (`VPNRunnerPort.start(_:supplying:)`),
/// which the fake records in `supplied`: the test names where it went, not only
/// where it did not.
///
/// Controls inside each test: the connect did reach the runner (a start was
/// supplied), so «nothing contains the marker» is not true of an empty record.
final class ASecretNeverReachesAnArgumentListTests: XCTestCase {

    private let marker = "7f3a"
    private let header = "Available network connection services:"
    private let id = "11111111-1111-1111-1111-111111111111"

    private func credentials() -> VPNCredentials {
        VPNCredentials(user: "user-\(marker)", password: "password-\(marker)",
                       secret: "secret-\(marker)")
    }

    private func engine(_ runner: FakeRunner, _ creds: FakeCreds) -> VPNEngine {
        runner.listOutput = [header,
                             "* (Disconnected) \(id) IPSec \"Office\" [IPSec:1]"].joined(separator: "\n")
        let engine = VPNEngine(settings: VPNSettings(store: NamespacedStore(
                                    namespace: "vpn", backing: InMemoryKeyValueStore())),
                               runner: runner, credentials: creds, apps: FakeApps(),
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)
        engine.refresh()
        return engine
    }

    private func assertNoElementCarriesTheMarker(_ runner: FakeRunner,
                                                 file: StaticString = #filePath,
                                                 line: UInt = #line) {
        XCTAssertFalse(runner.supplied.isEmpty,
                      "the connect never reached the runner, so the check below proves nothing",
                      file: file, line: line)
        for command in runner.issued {
            for element in command where element.contains(marker) {
                XCTFail("a secret reached an argument list: element \"\(element)\" of "
                        + "\(command.prefix(3).joined(separator: " ")) …", file: file, line: line)
            }
        }
    }

    /// A person's press of Connect, credentials read behind the prompt.
    func testAPersonsConnectSuppliesTheSecretOutsideTheArguments() {
        let creds = FakeCreds()
        creds.behindAPrompt["Office"] = credentials()
        let runner = FakeRunner()

        engine(runner, creds).connect("Office", auto: false)

        XCTAssertEqual(creds.asks.map(\.promptingAllowed), [true],
                       "the credential read this test stands on did not happen")
        assertNoElementCarriesTheMarker(runner)
        XCTAssertEqual(runner.supplied.map(\.name), ["Office"])
        XCTAssertEqual(runner.supplied.first?.credentials, credentials())
    }

    /// A rule's connect, with the secret Helm cached earlier.
    func testARuleWithACachedSecretSuppliesItOutsideTheArgumentsToo() {
        let creds = FakeCreds()
        creds.map["Office"] = credentials()
        let runner = FakeRunner()

        engine(runner, creds).connect("Office", auto: true)

        XCTAssertEqual(creds.asks.map(\.promptingAllowed), [false],
                       "the credential read this test stands on did not happen")
        assertNoElementCarriesTheMarker(runner)
        XCTAssertEqual(runner.supplied.map(\.name), ["Office"])
        XCTAssertEqual(runner.supplied.first?.credentials, credentials())
    }

    /// The system refusing is reported, with its number and without the name,
    /// and is not announced as a connection nobody has.
    func testAStartTheSystemRefusesIsReportedNotAnnounced() {
        let creds = FakeCreds()
        creds.map["Office"] = credentials()
        let runner = FakeRunner()
        runner.startAnswer = .refused(code: 1001)
        let engine = engine(runner, creds)

        engine.connect("Office", auto: true)

        XCTAssertEqual(runner.supplied.count, 1, "precondition: the start reached the port")
        XCTAssertNil(engine.lastAutomation, "a refused start was announced as a connection")
        XCTAssertEqual(VPNCommandReply.of(.refused(code: 1001)),
                       .refused("SCNetworkConnectionStart refused (SCError 1001)"))
    }

    /// A configuration gone between the list and the press is the same news
    /// whichever path the start took.
    func testNoSuchServiceFromTheInProcessStartIsTheSameNews() {
        XCTAssertEqual(VPNCommandReply.of(.noSuchService), .noSuchService)
        XCTAssertEqual(VPNCommandReply.of(.started), .accepted)
        let creds = FakeCreds()
        creds.map["Office"] = credentials()
        let runner = FakeRunner()
        runner.startAnswer = .noSuchService
        let engine = engine(runner, creds)

        engine.connect("Office", auto: true)

        XCTAssertEqual(runner.supplied.count, 1, "precondition: the start reached the port")
        XCTAssertNil(engine.lastAutomation, "a start for nothing was announced")
    }

    /// A configuration the system could not be read for is not one that is gone:
    /// the answer is a refusal, which is logged and shown as one, and no
    /// connection is announced.
    func testAnUnreadableConfigurationIsARefusalNotARename() {
        let reply = VPNCommandReply.of(.unreadable)
        XCTAssertNotEqual(reply, .noSuchService)
        guard case .refused = reply else { return XCTFail("expected a refusal, got \(reply)") }
        let creds = FakeCreds()
        creds.map["Office"] = credentials()
        let runner = FakeRunner()
        runner.startAnswer = .unreadable
        let engine = engine(runner, creds)

        engine.connect("Office", auto: true)

        XCTAssertEqual(runner.supplied.count, 1, "precondition: the start reached the port")
        XCTAssertNil(engine.lastAutomation, "an unreadable start was announced")
        XCTAssertEqual(engine.lastFailure?.reason, .refused)
    }
}
