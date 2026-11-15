// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
import HelmTestSupport
@testable import HelmApp

/// **Past defect: the card kept «Update & Relaunch» over a refusal.** The card asks
/// about `available` before it asks about the note, so a declined release left in
/// place showed the offer while a browser opened by itself. `decline` withdraws the
/// offer and says which reason it was; the install state is private to the service, so only a test of the callers can pin its reset.
@MainActor
final class ADeclinedUpdateTakesTheOfferAwayTests: XCTestCase {

    private func service() -> UpdateService {
        let s = UpdateService(notices: FakeAutomationNotice(),
                              store: AppSettings.store.over(InMemoryKeyValueStore()),
                              feed: { _ in throw URLError(.notConnectedToInternet) },
                              channelBacking: InMemoryKeyValueStore())
        s.available = UpdateService.Release(
            version: "9.9.9", pageURL: URL(string: "https://example.invalid/r")!,
            zipURL: nil, downloadURL: nil, notes: "")
        return s
    }

    func testDecliningWithdrawsTheOfferAndNamesTheReason() {
        for reason in [UpdateService.Note.manualInstall, .cannotReplaceItself] {
            let s = service()
            XCTAssertNotNil(s.available, "precondition: an offer was standing")
            s.decline(reason)
            XCTAssertNil(s.available, "the offer stays on the card over a refusal: \(reason)")
            XCTAssertEqual(s.note, reason, "the note names another reason than the one given")
        }
    }
}
