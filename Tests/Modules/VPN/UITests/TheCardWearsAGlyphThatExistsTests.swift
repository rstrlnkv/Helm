// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import AppKit
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// The button on a connection is faced by a glyph now, and a glyph is a string.
///
/// A misspelled symbol name draws **nothing**: the button keeps its frame, its
/// border and its action, and loses its face — which no compiler catches and
/// nobody notices in the state they were not testing. So every verb the card can
/// offer is resolved against SF Symbols here.
///
/// The word did not go away with the text: it is the tooltip and the name
/// VoiceOver reads, and `VPNStr.cardWord`'s own tests still hold what it says in
/// eight languages.
final class TheCardWearsAGlyphThatExistsTests: XCTestCase {

    private let everyStatus: [VPNStatus] = [.connected, .connecting, .disconnected,
                                            .disconnecting, .unknown]

    func testEveryStateOffersASymbolMacOSHas() {
        for status in everyStatus {
            let name = VPNCardGlyph.of(VPNCardAction.of(status))
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                            "\(status) is drawn with \"\(name)\", which SF Symbols does not have")
        }
    }

    /// A handshake being abandoned is not the tunnel being switched off, and the
    /// two must not wear one mark: there is no connection to switch off yet,
    /// which is the same reasoning `VPNCardAction` gives its own word for.
    func testAbandoningAHandshakeIsNotTheSameMarkAsSwitchingOff() {
        let cancelling = VPNCardGlyph.of(VPNCardAction.of(.connecting))
        let switchingOff = VPNCardGlyph.of(VPNCardAction.of(.connected))
        XCTAssertNotEqual(cancelling, switchingOff)
    }

    /// Connecting and disconnecting are the two directions of one act and share
    /// the power key deliberately — asserted so that sharing it stays a
    /// decision. What tells them apart is the accent on the button and the row
    /// they sit in, never the glyph.
    func testTheTwoDirectionsShareThePowerKeyOnPurpose() {
        XCTAssertEqual(VPNCardGlyph.of(VPNCardAction.of(.connected)),
                       VPNCardGlyph.of(VPNCardAction.of(.disconnected)))
        XCTAssertEqual(VPNCardGlyph.of(VPNCardAction.of(.disconnected)), "power")
    }
}
