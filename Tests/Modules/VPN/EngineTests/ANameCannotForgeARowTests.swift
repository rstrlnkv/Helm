// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// A configuration name is free text, and `scutil --nc list` prints it inside
/// one line of a line-oriented format. So a name that embeds a newline writes a
/// *second row* of that format, and the parser splitting on `\n` before any
/// shape check read it as a second configuration — `status=connected`, for a
/// tunnel that does not exist. That lights the header badge, the tile dot and
/// the 1×1 widget, which is the app manufacturing the exact false assurance
/// `VPNAutomation.Kind.dropped` exists to warn about.
///
/// The forged row is byte-identical to a real one, so nothing local to it can
/// be checked. What gives the forgery away is the *other* half: the printed form
/// of any name carries two quote delimiters, so a fragment holding exactly one
/// quote is a row whose name was cut in half — and the two halves belong to one
/// record.
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

    /// Rejoining the halves is only half the repair: what it leaves behind is a
    /// row whose *name* carries the newline and everything after it — a card
    /// label, a menu-bar title and an argument to `--nc start`, all spelled from
    /// a string that wrote the tool's own format once already. No row survives
    /// this output.
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

    /// The guard must not be paid for by every ordinary read: a name is allowed
    /// to carry quotation marks — the Service Name field takes them, and
    /// `quotedName` is written for it — including an odd number of them, which
    /// prints three quotes on a perfectly whole row.
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
