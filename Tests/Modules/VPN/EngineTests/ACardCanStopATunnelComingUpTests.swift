// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// **A promise the page made in a comment and broke two lines later.**
///
/// `connectionCard` says «what you can ask for while it is connecting is to
/// stop» — and the button under it was `.disabled(transitioning)`, which is the
/// opposite. A tunnel that hangs on `connecting` (a server that never answers,
/// a captive portal) left a card with a dot, three words and nothing pressable,
/// so the only way out was System Settings.
///
/// The engine can do it: `scutil --nc stop` acts on a service that is still
/// coming up. So the verb and whether it can be pressed are the engine's
/// vocabulary, next to `isUp` and `isConnected`, and this table is the promise
/// with a test under it.
final class ACardCanStopATunnelComingUpTests: XCTestCase {

    /// The one that was wrong, on its own line: `stop` works here.
    func testATunnelComingUpCanStillBeAskedToStop() {
        XCTAssertEqual(VPNCardAction.of(.connecting),
                       VPNCardAction(verb: .disconnect, enabled: true))
    }

    /// And the whole table, so a status added later has to answer this too.
    func testEveryStatusSaysWhichVerbAndWhether() {
        XCTAssertEqual(VPNCardAction.of(.connected),
                       VPNCardAction(verb: .disconnect, enabled: true))
        XCTAssertEqual(VPNCardAction.of(.disconnected),
                       VPNCardAction(verb: .connect, enabled: true))
        XCTAssertEqual(VPNCardAction.of(.unknown),
                       VPNCardAction(verb: .connect, enabled: true))
        // The one state that is still waited out rather than acted on: asking
        // `--nc start` of a service that is going down has not been measured,
        // and this one resolves itself in seconds where `connecting` can hang.
        XCTAssertEqual(VPNCardAction.of(.disconnecting),
                       VPNCardAction(verb: .connect, enabled: false))
    }

    /// The verb follows «is something happening here», which is what `isUp`
    /// answers — asserted against the status vocabulary rather than against a
    /// second list of cases, so the two cannot drift apart.
    func testTheVerbIsStopForEveryStatusThatIsUp() {
        for status in [VPNStatus.connected, .connecting, .disconnected, .disconnecting, .unknown] {
            XCTAssertEqual(VPNCardAction.of(status).verb, status.isUp ? .disconnect : .connect,
                           "\(status) draws the wrong verb")
        }
    }
}
