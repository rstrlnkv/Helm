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

/// `scutil --nc list` is parsed by scanning for the first `(`, the first `"` and
/// the first 36-character dashed token on a line. Connection names are chosen by
/// the user and travel through all three.
final class VPNListParserHostileTests: XCTestCase {

    private let realShape = """
    * (Disconnected)   D4A0E5D5-3D26-4C0B-9E93-1F2C0F5A9A11 IPSec "Work" [IPSec:—]
    * (Connected)      6E1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9 PPP   "Home" [PPP:L2TP]
    """

    /// Baseline, so the hostile cases below can be read as deviations.
    func test_the_real_shape_yields_one_row_per_line_with_distinct_ids() {
        let list = VPNListParser.parseList(realShape)
        XCTAssertEqual(list.map(\.name), ["Work", "Home"])
        XCTAssertEqual(Set(list.map(\.id)).count, 2)
        XCTAssertEqual(list[1].status, .connected)
    }

    /// Trap: a row without a UUID-shaped token takes `<name>#<namesakes before
    /// it>` as its id, and macOS lets two VPN configurations carry the same
    /// display name. This test's rows carry UUIDs; the fallback is held by
    /// `ANameIsNotAnIdentityTests`. Everything downstream keys on
    /// one or the other — `VPNRules` on `vpnName`, the panel tile's rows on `id` — so if
    /// ids can collide, two rows become one and a rule points at "whichever".
    /// This records which of the two is true today rather than asserting a wish.
    func test_two_configurations_sharing_a_name_stay_two_rows() {
        let output = """
        * (Disconnected)   D4A0E5D5-3D26-4C0B-9E93-1F2C0F5A9A11 IPSec "Work" [IPSec:—]
        * (Disconnected)   6E1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9 IPSec "Work" [IPSec:—]
        """
        let list = VPNListParser.parseList(output)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(Set(list.map(\.id)).count, 2,
                       "duplicate names must still produce distinct ids: \(list.map(\.id))")
    }

    /// Trap: a name is free text. Parens in it must not be read as the status,
    /// and the row must survive rather than vanish from the list.
    func test_a_name_containing_parentheses_keeps_its_status_and_its_name() {
        let output = "* (Connected) D4A0E5D5-3D26-4C0B-9E93-1F2C0F5A9A11 IPSec \"Work (Berlin)\" [IPSec:—]"
        let list = VPNListParser.parseList(output)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.status, .connected)
        XCTAssertEqual(list.first?.name, "Work (Berlin)")
    }
}
