// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// **One word was doing two jobs, and in two languages it was simply wrong.**
///
/// `.connecting` offers a `--nc stop`, so the card was labelled «Disconnect» —
/// which asks that word to mean both «stop this handshake» and «bring this
/// tunnel down». Japanese and Chinese cannot carry both: 接続解除 is *release the
/// connection* and 断开连接 is *break the connection*, and there is no connection
/// yet to release or break.
///
/// So the card draws three words where the tool has two directions, and the
/// direction is derived from the word rather than stored beside it — a press on
/// «Cancel» is the same `--nc stop` a press on «Disconnect» is.
final class ACancelIsAStopWithItsOwnWordTests: XCTestCase {

    /// The word for a tunnel that has not arrived is its own.
    func testAHandshakeIsOfferedAThirdWord() {
        XCTAssertEqual(VPNCardAction.of(.connecting),
                       VPNCardAction(word: .cancel, enabled: true))
    }

    /// **A dimmed control keeps the word that was pressed.** `.disconnecting`
    /// drew a disabled «Connect», so the control under the cursor turned into
    /// the thing nobody asked for at the moment it stopped answering.
    func testTheDimmedControlKeepsTheWordThatWasPressed() {
        XCTAssertEqual(VPNCardAction.of(.disconnecting),
                       VPNCardAction(word: .disconnect, enabled: false))
    }

    /// The whole table, so a status added later has to answer this too.
    func testEveryStatusSaysWhichWordAndWhether() {
        XCTAssertEqual(VPNCardAction.of(.connected),
                       VPNCardAction(word: .disconnect, enabled: true))
        XCTAssertEqual(VPNCardAction.of(.disconnected),
                       VPNCardAction(word: .connect, enabled: true))
        XCTAssertEqual(VPNCardAction.of(.unknown),
                       VPNCardAction(word: .connect, enabled: true))
    }

    /// Three words, two directions: everything that is not «connect» is the one
    /// `--nc stop`, so the third word cannot become a third command by drifting.
    func testEveryWordButConnectSendsTheSameStop() {
        XCTAssertEqual(VPNCardAction(word: .connect, enabled: true).verb, .connect)
        XCTAssertEqual(VPNCardAction(word: .disconnect, enabled: true).verb, .disconnect)
        XCTAssertEqual(VPNCardAction(word: .cancel, enabled: true).verb, .disconnect)
    }

    /// And the guard the old table carried, kept: whatever `isUp` counts as up,
    /// the card offers a way **down** — asserted against the status vocabulary
    /// rather than against a second list of cases.
    func testATunnelThatIsUpIsAlwaysOfferedAWayDown() {
        for status in [VPNStatus.connected, .connecting] {
            XCTAssertEqual(VPNCardAction.of(status).verb, .disconnect,
                           "\(status) is up and the card does not offer a stop")
        }
        for status in [VPNStatus.disconnected, .unknown] {
            XCTAssertEqual(VPNCardAction.of(status).verb, .connect,
                           "\(status) is down and the card does not offer a connect")
        }
    }
}
