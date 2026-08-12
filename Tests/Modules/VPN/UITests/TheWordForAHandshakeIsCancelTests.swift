// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmUI
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// The word on a card whose tunnel has not arrived.
///
/// «Disconnect» was asked to mean «stop this handshake» as well, and in two
/// languages that is not a shade of meaning but an error: 接続解除 is *release
/// the connection*, 断开连接 is *break the connection*, and there is no
/// connection yet. macOS's own word for abandoning something in flight is
/// `Cancel`, which this app already ships in all eight.
///
/// Parameterized by language rather than reading `AppLanguage.current`: the
/// suite runs in this machine's language, so a test that asks `current` checks
/// English eight times.
final class TheWordForAHandshakeIsCancelTests: XCTestCase {

    /// From the status through the engine's own table, so the page cannot go
    /// back to labelling a handshake with the tunnel's verb without this failing.
    private func connectingWord(_ language: AppLanguage) -> String {
        VPNStr.cardWord(VPNCardAction.of(.connecting).word, language: language)
    }

    func testAHandshakeIsCancelledInEveryLanguage() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(connectingWord(language), L("Cancel", language: language),
                           "\(language): the card labels a handshake with something other than "
                           + "macOS's own word for abandoning one")
        }
    }

    /// The two that were outright wrong, by name.
    func testTheCJKWordsDoNotReleaseAConnectionThatDoesNotExist() {
        XCTAssertEqual(connectingWord(.ja), "キャンセル")
        XCTAssertEqual(connectingWord(.zh), "取消")
        XCTAssertFalse(connectingWord(.ja).contains("接続解除"),
                       "Japanese still says «release the connection» about a handshake")
        XCTAssertFalse(connectingWord(.zh).contains("断开"),
                       "Chinese still says «break the connection» about a handshake")
    }

    /// Three words, and three different ones: a translation that collapsed two
    /// of them would put the module back where it started with nothing failing.
    func testTheThreeWordsAreThreeWordsInEveryLanguage() {
        for language in AppLanguage.allCases {
            let words = [VPNCardAction.Word.connect, .disconnect, .cancel]
                .map { VPNStr.cardWord($0, language: language) }
            XCTAssertEqual(Set(words).count, 3,
                           "\(language) draws \(Set(words).count) distinct words for three "
                           + "states: \(words)")
        }
    }

    /// A tunnel on its way down keeps the word that was pressed, and it is the
    /// tunnel's word rather than the handshake's.
    func testATunnelGoingDownKeepsTheWordThatWasPressed() {
        let action = VPNCardAction.of(.disconnecting)
        for language in AppLanguage.allCases {
            XCTAssertEqual(VPNStr.cardWord(action.word, language: language),
                           L("Disconnect", language: language),
                           "\(language): the dimmed control changed its word")
        }
    }
}
