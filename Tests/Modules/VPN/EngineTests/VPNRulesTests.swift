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
}
