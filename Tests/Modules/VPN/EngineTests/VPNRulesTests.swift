import XCTest
@testable import HelmRuntime
@testable import Module_VPN_Engine

final class VPNRulesTests: XCTestCase {
    func test_encode_decode_roundtrip() {
        let rules = ["com.x": VPNAppRule(vpnName: "A", connectOnLaunch: true, disconnectOnQuit: false)]
        XCTAssertEqual(VPNRules.decode(VPNRules.encode(rules)), rules)
    }
    func test_decode_legacy_string_map() {
        let decoded = VPNRules.decode("{\"com.x\":\"A\"}")
        XCTAssertEqual(decoded["com.x"], VPNAppRule(vpnName: "A"))  // both flags default true
    }
    func test_decode_garbage_is_empty() {
        XCTAssertTrue(VPNRules.decode("not json").isEmpty)
    }
    func test_valid_drops_unknown_vpn() {
        let rules = ["com.x": VPNAppRule(vpnName: "A"), "com.y": VPNAppRule(vpnName: "GONE")]
        let conns = [VPNConnection(id: "1", name: "A", status: .disconnected, kind: nil)]
        XCTAssertEqual(VPNRules.valid(rules, against: conns).keys.sorted(), ["com.x"])
    }

    // MARK: - The four states one control offers

    func testTimingReadsBackFromTheFlags() {
        XCTAssertEqual(VPNAppRule(vpnName: "v").timing, .launchAndQuit)
        XCTAssertEqual(VPNAppRule(vpnName: "v", disconnectOnQuit: false).timing, .launchOnly)
        XCTAssertEqual(VPNAppRule(vpnName: "v", connectOnLaunch: false).timing, .quitOnly)
        XCTAssertEqual(VPNAppRule(vpnName: "v", connectOnLaunch: false,
                                  disconnectOnQuit: false).timing, .off)
    }

    func testSettingATimingRoundTrips() {
        for timing in VPNAppRule.Timing.allCases {
            var rule = VPNAppRule(vpnName: "v")
            rule.set(timing)
            XCTAssertEqual(rule.timing, timing)
        }
    }

    /// "Off" must clear both, so a rule cannot half-fire.
    func testOffClearsBoth() {
        var rule = VPNAppRule(vpnName: "v")
        rule.set(.off)
        XCTAssertFalse(rule.connectOnLaunch)
        XCTAssertFalse(rule.disconnectOnQuit)
    }

    // MARK: - What the AUTOMATIC dial counts

    /// The dial sat above the rules list and disagreed with it: it counted
    /// `autoConnected` — connections a rule has raised *right now* — under a
    /// label the list beneath reads as "the rules I wrote". With nothing
    /// running it said 0 over one visible rule. Whether a rule is firing this
    /// second is the green dot's job.
    func testTheDialCountsRulesRatherThanLiveConnections() {
        let rules = ["com.a": VPNAppRule(vpnName: "Work"),
                     "com.b": VPNAppRule(vpnName: "Work")]
        XCTAssertEqual(VPNRules.automationCount(rules), 2)
    }

    /// A rule set to "Off" is written down and does nothing. Counting it would
    /// be the same lie in the other direction.
    func testARuleTurnedOffIsNotAutomation() {
        var off = VPNAppRule(vpnName: "Work")
        off.set(.off)
        XCTAssertEqual(VPNRules.automationCount(["com.a": VPNAppRule(vpnName: "Work"),
                                                 "com.b": off]), 1)
    }

    func testNoRulesCountAsNone() {
        XCTAssertEqual(VPNRules.automationCount([:]), 0)
    }

    // MARK: - Rules whose VPN is gone

    func testARuleNamingAMissingVPNIsReportedNotJustDropped() {
        let rules = ["com.acme": VPNAppRule(vpnName: "Old VPN")]
        let connections = [VPNConnection(id: "1", name: "New VPN", status: .disconnected, kind: "L2TP")]
        XCTAssertTrue(VPNRules.valid(rules, against: connections).isEmpty)
        XCTAssertEqual(Array(VPNRules.orphaned(rules, against: connections).keys), ["com.acme"])
    }

    func testNothingIsOrphanedWhileTheVPNExists() {
        let rules = ["com.acme": VPNAppRule(vpnName: "NBCom VPN")]
        let connections = [VPNConnection(id: "1", name: "NBCom VPN", status: .connected, kind: "L2TP")]
        XCTAssertTrue(VPNRules.orphaned(rules, against: connections).isEmpty)
    }
}

/// The three questions a status can be asked, and which is which.
///
/// `isUp` means "something is happening here" — right for a tile that lights,
/// wrong for a number labelled *active*, which counted a connection whose own
/// row was spinning and saying "Connecting", in green.
final class VPNStatusVocabularyTests: XCTestCase {

    func testConnectedIsNarrowerThanUp() {
        XCTAssertTrue(VPNStatus.connected.isConnected)
        XCTAssertFalse(VPNStatus.connecting.isConnected, "still on its way")
        XCTAssertTrue(VPNStatus.connecting.isUp, "but something is happening")
    }

    func testNothingIsBothConnectedAndMidChange() {
        for status in [VPNStatus.connected, .connecting, .disconnected, .disconnecting, .unknown] {
            XCTAssertFalse(status.isConnected && status.isTransitioning, "\(status)")
        }
    }

    func testDisconnectedIsNoneOfThem() {
        XCTAssertFalse(VPNStatus.disconnected.isUp)
        XCTAssertFalse(VPNStatus.disconnected.isConnected)
        XCTAssertFalse(VPNStatus.disconnected.isTransitioning)
        XCTAssertFalse(VPNStatus.unknown.isUp)
    }
}

/// What the strip says Helm is holding up.
///
/// `autoConnected` is the set Helm raised itself, and it was emptied only when
/// Helm took one down. A VPN can also drop on its own — the network goes, the
/// server hangs up, somebody stops it in System Settings — and the strip then
/// read "ACTIVE 0 · AUTOMATIC 1" until the app restarted.
final class AutoConnectedFollowsRealityTests: XCTestCase {

    /// **The credit runs out at `VPNDropSettle.window`, not at the first read
    /// showing the tunnel down.** That read is the one the settle exists to
    /// distrust — a NetworkExtension tunnel re-handshaking on a Wi-Fi change is
    /// down for three seconds — and emptying the book on it cost Helm the
    /// tunnel it was holding, and with it the next real drop
    /// (`ABlipDoesNotCostHelmItsTunnelTests`).
    func testANameNoLongerUpIsNoLongerCountedAsAutomatic() {
        let runner = FakeRunner()
        let clock = TestClock()
        runner.listOutput = #"* (Connected) A --> B  "Work" [IKEv2]"#
        let engine = VPNEngine(settings: VPNSettings(store: NamespacedStore(
            namespace: "vpn", backing: InMemoryKeyValueStore())),
            runner: runner, apps: FakeApps(),
            interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
            now: { clock.now }, work: .inline)
        engine.connect("Work", auto: true)
        XCTAssertEqual(engine.autoConnected, ["Work"])

        // It drops without Helm asking.
        runner.listOutput = #"* (Disconnected) A --> B  "Work" [IKEv2]"#
        engine.refresh()
        XCTAssertEqual(engine.autoConnected, ["Work"],
                       "a fall inside the settle window was taken for a loss")

        clock.advance(VPNDropSettle.window)
        engine.refresh()

        XCTAssertTrue(engine.autoConnected.isEmpty,
                      "the strip still credits Helm with a connection that is down")
    }
}

/// The other half of the same rule, and the reason it is not one line.
extension AutoConnectedFollowsRealityTests {

    /// The refresh that follows a connect usually still reports the old
    /// status — the handshake takes seconds. Forgetting on "not up right now"
    /// would wipe a connection Helm had just raised, which is what broke
    /// `test_auto_connect_on_app_launch` on the first attempt at this.
    func testAConnectionThatHasNotComeUpYetIsStillCredited() {
        let runner = FakeRunner()
        runner.listOutput = #"(Disconnected) 1111 IPSec "Work""#
        let engine = VPNEngine(settings: VPNSettings(store: NamespacedStore(
            namespace: "vpn", backing: InMemoryKeyValueStore())),
            runner: runner, apps: FakeApps(),
            interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
            work: .inline)

        engine.connect("Work", auto: true)     // the list still says disconnected
        engine.refresh()

        XCTAssertEqual(engine.autoConnected, ["Work"],
                       "a connection mid-handshake was forgotten before it arrived")
    }
}
