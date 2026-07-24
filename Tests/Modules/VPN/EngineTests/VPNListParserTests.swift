import XCTest
@testable import Module_VPN_Engine

final class VPNListParserTests: XCTestCase {
    func test_parseStatus() {
        XCTAssertEqual(VPNListParser.parseStatus("Connected"), .connected)
        XCTAssertEqual(VPNListParser.parseStatus(" disconnected "), .disconnected)
        XCTAssertEqual(VPNListParser.parseStatus("bogus"), .unknown)
    }
    func test_parseList_name_status_id() {
        let out = "* (Connected)   1B2C3D4E-0000-0000-0000-000000000000  IPSec  \"NBCom VPN\"  [foo]"
        let list = VPNListParser.parseList(out)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].name, "NBCom VPN")
        XCTAssertEqual(list[0].status, .connected)
        XCTAssertEqual(list[0].id, "1B2C3D4E-0000-0000-0000-000000000000")
    }
    func test_parseList_skips_garbage_lines() {
        XCTAssertTrue(VPNListParser.parseList("garbage\nno match here").isEmpty)
    }
    func test_defaultConnection_sole() {
        let c = [VPNConnection(id: "a", name: "A", status: .disconnected, kind: nil)]
        XCTAssertEqual(VPNListParser.defaultConnection(from: c, lastUsedName: nil)?.name, "A")
    }
    func test_defaultConnection_prefers_lastUsed_else_first() {
        let c = [VPNConnection(id: "a", name: "A", status: .disconnected, kind: nil),
                 VPNConnection(id: "b", name: "B", status: .disconnected, kind: nil)]
        XCTAssertEqual(VPNListParser.defaultConnection(from: c, lastUsedName: "B")?.name, "B")
        XCTAssertEqual(VPNListParser.defaultConnection(from: c, lastUsedName: nil)?.name, "A")
    }
}
