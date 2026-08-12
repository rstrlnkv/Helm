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
///
/// **Which *word* each status draws is
/// `ACancelIsAStopWithItsOwnWordTests`**, together with the tie between
/// the word and the direction — this file is «can it be pressed, and where does
/// the press go», that one is «what does it say».
final class ACardCanStopATunnelComingUpTests: XCTestCase {

    /// The one that was wrong, on its own line: `stop` works here.
    func testATunnelComingUpCanStillBeAskedToStop() {
        XCTAssertEqual(VPNCardAction.of(.connecting).verb, .disconnect)
        XCTAssertTrue(VPNCardAction.of(.connecting).enabled)
    }

    /// And the whole table, so a status added later has to answer this too.
    func testEveryStatusSaysWhetherItCanBePressed() {
        for status in [VPNStatus.connected, .connecting, .disconnected, .unknown] {
            XCTAssertTrue(VPNCardAction.of(status).enabled,
                          "\(status) draws a card with nothing to press")
        }
        // The one state that is still waited out rather than acted on: asking
        // `--nc start` of a service that is going down has not been measured,
        // and this one resolves itself in seconds where `connecting` can hang.
        XCTAssertFalse(VPNCardAction.of(.disconnecting).enabled)
    }
}
