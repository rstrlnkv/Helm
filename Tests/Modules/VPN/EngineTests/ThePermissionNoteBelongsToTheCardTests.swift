// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// One sentence per card, however many rows want to say it.
///
/// The notice card decides two events, and each row asked the permission
/// question for itself — so choosing «System notification» for both and then
/// refusing Helm the permission in System Settings drew *the same sentence
/// twice*, 20 pt apart, and took the card from 285 to 423 pt. The question is
/// about the card («can this card's choices be honoured»), not about a row, and
/// asking it once is what makes a second copy impossible rather than unlikely.
final class ThePermissionNoteBelongsToTheCardTests: XCTestCase {

    /// The state that drew it twice: both rows loud, macOS refusing.
    func testBothRowsWantingABannerIsStillOneQuestion() {
        XCTAssertTrue(VPNNotice.permissionMissing(among: [.system, .system],
                                                  authorization: .denied))
    }

    /// Either row alone is enough — the note is about the card, and a card with
    /// one loud row and one quiet one has something to say.
    func testEitherRowAloneAsksIt() {
        XCTAssertTrue(VPNNotice.permissionMissing(among: [.system, .menuBar],
                                                  authorization: .denied))
        XCTAssertTrue(VPNNotice.permissionMissing(among: [.silent, .system],
                                                  authorization: .denied))
    }

    /// And nothing to say when no row wants a banner…
    func testNoRowWantingABannerAsksNothing() {
        XCTAssertFalse(VPNNotice.permissionMissing(among: [.menuBar, .silent],
                                                   authorization: .denied))
    }

    /// …nor when macOS has not refused. **`nil` is not a refusal**: it is
    /// «nobody has asked this launch», which is what the page holds before its
    /// `.task` has run, and a warning drawn from it would accuse macOS of a
    /// denial it never made.
    func testAPermissionThatWasNeverRefusedSaysNothing() {
        for answer: NoticeAuthorization? in [nil, .authorized, .notDetermined] {
            XCTAssertFalse(VPNNotice.permissionMissing(among: [.system, .system],
                                                       authorization: answer),
                           "a \(String(describing: answer)) permission drew a refusal")
        }
    }
}
