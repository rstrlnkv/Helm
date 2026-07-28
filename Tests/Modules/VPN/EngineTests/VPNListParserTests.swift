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

/// Where the protocol tag ends and the connection's name begins.
///
/// `scutil --nc list` puts the protocol in square brackets *before* the quoted
/// name. `between(line, "[", "]")` takes the first pair on the line, which is
/// the right one — until the name itself carries brackets, at which point the
/// first pair is still the protocol's. These pin that the name is not searched
/// and that the tag is read from where scutil writes it.
final class VPNListParserBracketTests: XCTestCase {

    func testTheProtocolComesFromBeforeTheName() {
        let line = #"* (Disconnected)   4C9E... --> 4B3F...  "Office" [IKEv2:Office]"#
        let parsed = VPNListParser.parseList(line)
        XCTAssertEqual(parsed.first?.name, "Office")
        XCTAssertEqual(parsed.first?.kind, "IKEv2:Office")
    }

    /// A name with brackets in it. The tag scutil writes still wins, because it
    /// is the first pair on the line and the name is quoted.
    func testANameWithBracketsDoesNotBecomeTheProtocol() {
        let line = #"* (Connected)   4C9E... --> 4B3F...  "Office [old]" [IKEv2]"#
        let parsed = VPNListParser.parseList(line)
        XCTAssertEqual(parsed.first?.name, "Office [old]")
        XCTAssertEqual(parsed.first?.kind, "IKEv2",
                       "the name's own brackets were read as the protocol")
    }
}
