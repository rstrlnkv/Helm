import XCTest
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
