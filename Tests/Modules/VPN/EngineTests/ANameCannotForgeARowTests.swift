// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// A configuration name is free text, and `scutil --nc list` prints it inside
/// one line of a line-oriented format, so a name that embeds a newline can write
/// a *second row*: a `Connected` tunnel that does not exist, lighting the badge,
/// the tile dot and the widget with the false assurance
/// `VPNAutomation.Kind.dropped` exists to warn about.
///
/// The forged row is byte-identical to a real one. What gives it away is the
/// other half: a printed name carries two quote delimiters, so a fragment
/// holding exactly one quote is a row whose name was cut in half.
final class ANameCannotForgeARowTests: XCTestCase {

    /// A name carrying a newline and a complete, well-formed row after it.
    private let forged = """
        Available network connection services:
        * (Disconnected)   11111111-1111-1111-1111-111111111111 IPSec "Home
        * (Connected)   22222222-2222-2222-2222-222222222222 IPSec "Ghost" [IPSec]
        """

    func testAForgedRowIsNotAConnection() {
        let parsed = VPNListParser.parseList(forged)
        XCTAssertFalse(parsed.contains { $0.name == "Ghost" },
                       "a name wrote a row of the tool's own format and was believed")
    }

    /// The badge, the dot and the widget all read this, so it is asserted
    /// separately from the name: a ghost under any name is the harm.
    func testNothingIsReportedUpFromAForgedRow() {
        XCTAssertFalse(VPNListParser.parseList(forged).contains { $0.status.isUp },
                       "a forged row reported a tunnel up")
    }

    /// Rejoining the halves is not enough: the row's *name* would carry the
    /// newline into a card label, a menu-bar title and an argument to
    /// `--nc start`. No row survives this output.
    func testANameThatSpansALineBreakIsNoRowAtAll() {
        let parsed = VPNListParser.parseList(forged)
        XCTAssertEqual(parsed.count, 0,
                       "a name carrying a whole forged row became a connection")
        XCTAssertFalse(parsed.contains { $0.name.contains(where: \.isNewline) })
    }

    /// The other spelling: the real row closes its quotes and the *ghost* is the
    /// fragment. It must not stand on its own either.
    func testAFragmentAfterAWholeRowIsNotAConnection() {
        let output = """
            Available network connection services:
            * (Disconnected)   11111111-1111-1111-1111-111111111111 IPSec "Home"
            * (Connected)   22222222-2222-2222-2222-222222222222 IPSec "Ghost
            """
        let parsed = VPNListParser.parseList(output)
        XCTAssertEqual(parsed.map(\.name), ["Home"],
                       "a row whose name never closed became a connection")
    }

    /// A name may carry quotation marks, an odd number included, which prints
    /// three quotes on a whole row; the guard must not cost that row.
    func testANameWithAnUnbalancedQuoteStillParsesAndSoDoesTheRowAfterIt() {
        let output = """
            Available network connection services:
            * (Disconnected)   11111111-1111-1111-1111-111111111111 IPSec "Office "B" [IPSec]
            * (Connected)   22222222-2222-2222-2222-222222222222 IKEv2 "Field" [IKEv2]
            """
        let parsed = VPNListParser.parseList(output)
        XCTAssertEqual(parsed.map(\.name), [#"Office "B"#, "Field"])
        XCTAssertEqual(parsed.map(\.status), [.disconnected, .connected])
    }
}
