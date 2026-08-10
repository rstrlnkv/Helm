import XCTest
import SwiftUI
import AppKit
import HelmUI
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// «Stop pauses the rule until it applies again» — the one sentence that
/// explains why pressing Stop does not simply hand the Mac back.
///
/// It used to be written inside the hero's `.automatic` branch, on the
/// reasoning that a rule is what that branch is about. The engine asks a
/// different question: `stopSession` suppresses whenever a *trigger* holds,
/// whatever started the session. So a hand-started timer running while the
/// rule's app was also on screen drew the countdown, and Stop there paused the
/// rule with nothing anywhere saying so.
///
/// The caption is drawn in every state now and its opacity carries the
/// condition — an `if` would take the page's height with it in one frame, the
/// accordion defect the suppression row was rewritten to avoid. Which means
/// the thing to check is not the hierarchy but the screen: **a mutation
/// replacing `.opacity(ruleHolds ? 1 : 0)` with `.opacity(1)` broke nothing in
/// the whole suite**, and this file exists because of that result.
@MainActor
final class TheStopCaptionIsOnScreenOrNotTests: XCTestCase {

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func hero(ruleHolds: Bool, state: SessionHero) -> some View {
        KeepAwakeHero(state: state, now: Self.now, anyRuleOn: true,
                      defaultDurationMinutes: 60, suppressed: false,
                      heldByOthers: false, ruleHolds: ruleHolds,
                      timedNote: { _ in "until 15:42" },
                      start: { _ in }, stop: {}, resume: {})
            .frame(width: HelmLayout.settingsColumn)
    }

    /// Ink in the bottom 24 pt of the block — where the 11 pt caption sits,
    /// under the row of buttons.
    private func captionInk(ruleHolds: Bool, state: SessionHero) -> Int {
        let host = NSHostingView(rootView: AnyView(hero(ruleHolds: ruleHolds, state: state)))
        host.frame = NSRect(x: 0, y: 0, width: HelmLayout.settingsColumn,
                            height: host.fittingSize.height)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4 else { return -1 }
        var mass = 0
        for y in max(0, rep.pixelsHigh - 24)..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                mass += Int(data[y * rep.bytesPerRow + x * 4 + 3])
            }
        }
        return mass
    }

    /// The countdown state, which is where the defect lived: a timer running
    /// beside a rule whose trigger holds.
    func testTheCaptionIsDrawnWhileARuleCouldBePaused() throws {
        let state = SessionHero.timed(until: Self.now.addingTimeInterval(3600))
        let with = captionInk(ruleHolds: true, state: state)
        let without = captionInk(ruleHolds: false, state: state)
        try XCTSkipIf(with < 0 || without < 0, "nothing drew — no window server")

        XCTAssertGreaterThan(with, without,
                             "the caption is not on screen while a rule's trigger holds, so "
                             + "Stop pauses that rule with nothing saying so: \(with) vs "
                             + "\(without)")
    }

    /// And it is *not* drawn when no rule could be paused — otherwise the test
    /// above passes with the condition deleted, which is exactly the mutation
    /// that survived before this file existed.
    func testTheCaptionIsAbsentWhenNoRuleApplies() throws {
        let ink = captionInk(ruleHolds: false,
                             state: .timed(until: Self.now.addingTimeInterval(3600)))
        try XCTSkipIf(ink < 0, "nothing drew — no window server")

        XCTAssertEqual(ink, 0,
                       "a Mac with no rule at all was told that Stop would pause one: \(ink)")
    }

    /// The same in the state that always carried it, so moving the caption out
    /// of `.automatic` did not lose it there.
    func testTheAutomaticStateStillCarriesIt() throws {
        let with = captionInk(ruleHolds: true, state: .automatic([.externalDisplay]))
        try XCTSkipIf(with < 0, "nothing drew — no window server")

        XCTAssertGreaterThan(with, 0)
    }
}
