import Foundation
import HelmRuntime
import XCTest
@testable import Module_VPN_Engine

/// The log carries no names, and nothing checked that this module's lines obey
/// it.
///
/// CLAUDE.md states the rule and `Redact` implements it, with three test files
/// of its own. What none of them can see is the *call site*: a line written as
/// `info("vpn", "connect \(name)")` instead of `Redact.vpn(name)` compiles,
/// reads correctly, and puts somebody's employer in the file they are asked to
/// send when they report a problem. It would be an error nowhere.
///
/// A VPN name is the sharpest case in the app. "Acme Corp VPN" names where
/// somebody works; the connection list is the shape of their week.
///
/// **The control matters more than the assertion here.** A test that only
/// checks the raw name is absent passes when nothing was logged at all — which
/// is the state a test process is in by default, since `LogPolicy` keeps the
/// log off for a build that is not `-dev`. So each test below also proves the
/// line it is judging actually exists.
final class TheLogDoesNotNameTheConnectionTests: XCTestCase {

    /// Distinctive enough that finding it in a message cannot be a coincidence.
    private let secretName = "Acme-Corp-VPN-\(UUID().uuidString)"

    /// The log is off in a test process — `LogPolicy` keeps it off for a build
    /// that is not `-dev`, and nothing here calls `start()`. Switched on for the
    /// length of each test and off again, which is where it began.
    override func setUp() {
        super.setUp()
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private func makeSettings() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore()))
    }

    private func engine(_ runner: FakeRunner) -> VPNEngine {
        VPNEngine(settings: makeSettings(), runner: runner, apps: FakeApps(),
                  interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                  work: .inline)
    }

    private var vpnLines: [String] {
        HelmLog.shared.recentEntries().filter { $0.category == "vpn" }.map(\.message)
    }

    func testConnectingDoesNotWriteTheName() {
        let runner = FakeRunner()
        runner.listOutput = """
        Available network connection services:
        (Disconnected) 11111111-1111-1111-1111-111111111111 PPP (L2TP) --> "\(secretName)"
        """
        engine(runner).connect(secretName)

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
        engine(runner).disconnect(secretName)

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
        engine.connect(secretName)
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
