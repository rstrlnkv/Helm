import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_VPN_Engine

/// The log carries no names, and this checks that this module's lines obey it.
///
/// `Redact` implements the rule (Architecture/DiagnosticsLog.md § Diagnostics log),
/// but only a *call site* can break it: `info("vpn", "connect \(name)")` instead
/// of `Redact.vpn(name)` compiles, reads correctly, and puts somebody's
/// employer in the file they send with a bug report. "Acme Corp VPN" names
/// where somebody works.
///
/// **The control matters more than the assertion here.** A test that only
/// checks the raw name is absent passes when nothing was logged at all — the
/// default in a test process, since `LogPolicy` keeps the log off for a build
/// that is not `-dev`. So each test below also proves its line exists.
final class TheLogDoesNotNameTheConnectionTests: XCTestCase {

    /// Distinctive enough that finding it in a message cannot be a coincidence.
    private let secretName = "Acme-Corp-VPN-\(UUID().uuidString)"

    /// The log is off in a test process — `LogPolicy` keeps it off for a build
    /// that is not `-dev`, and nothing here calls `start()`. Switched on for the
    /// length of each test and off again, which is where it began.
    override func setUp() {
        super.setUp()
        tailTheLog()
    }

    private func engine(_ runner: FakeRunner) -> VPNEngine {
        VPNEngine(settings: VPNSettings.inMemory(), runner: runner, apps: FakeApps(),
                  interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                  work: .inline)
    }

    private var vpnLines: [String] {
        loggedLines("vpn")
    }

    func testConnectingDoesNotWriteTheName() {
        let runner = FakeRunner()
        runner.listOutput = """
        Available network connection services:
        (Disconnected) 11111111-1111-1111-1111-111111111111 PPP (L2TP) --> "\(secretName)"
        """
        engine(runner).connect(secretName, auto: false)

        XCTAssertTrue(vpnLines.contains { $0.hasPrefix("connect ") },
                      "no connect line was written at all, so this proves nothing: \(vpnLines)")
        XCTAssertFalse(vpnLines.contains { $0.contains(secretName) },
                       "the log names the connection: \(vpnLines)")
    }

    func testDisconnectingDoesNotWriteTheName() {
        let runner = FakeRunner()
        runner.listOutput = """
        Available network connection services:
        (Connected) 11111111-1111-1111-1111-111111111111 PPP (L2TP) --> "\(secretName)"
        """
        engine(runner).disconnect(secretName, auto: false)

        XCTAssertTrue(vpnLines.contains { $0.hasPrefix("disconnect ") },
                      "no disconnect line was written at all: \(vpnLines)")
        XCTAssertFalse(vpnLines.contains { $0.contains(secretName) },
                       "the log names the connection: \(vpnLines)")
    }

    /// The settle and still-transitioning lines list every connection by name
    /// and status — the densest naming in the module, and the easiest place for
    /// a raw name to be added without anyone noticing.
    func testThePollingLinesDoNotNameTheConnections() {
        let runner = FakeRunner()
        runner.listOutput = """
        Available network connection services:
        (Connected) 11111111-1111-1111-1111-111111111111 PPP (L2TP) --> "\(secretName)"
        """
        let engine = engine(runner)
        engine.connect(secretName, auto: false)
        engine.refresh()

        XCTAssertFalse(vpnLines.isEmpty, "nothing was logged, so this proves nothing")
        XCTAssertFalse(vpnLines.contains { $0.contains(secretName) },
                       "a polling line names the connection: \(vpnLines)")
    }

    /// And a name that *is* redacted still tells one connection from another,
    /// which is the whole point of tagging rather than dropping it.
    func testTheRedactedTagStillDistinguishesConnections() {
        let one = Redact.vpn("Acme Corp VPN")
        let other = Redact.vpn("Home")
        XCTAssertNotEqual(one, other)
        XCTAssertEqual(one, Redact.vpn("Acme Corp VPN"), "the same name tagged twice must match")
    }
}
