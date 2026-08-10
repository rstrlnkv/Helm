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

    private func hero(ruleHolds: Bool, state: SessionHero,
                      suppressed: Bool = false) -> some View {
        KeepAwakeHero(state: state, now: Self.now, anyRuleOn: true,
                      defaultDurationMinutes: 60, suppressed: suppressed,
                      heldByOthers: false, ruleHolds: ruleHolds,
                      timedNote: { _ in "until 15:42" },
                      start: { _ in }, stop: {}, resume: {})
            .frame(width: HelmLayout.settingsColumn)
    }

    /// Every pixel of ink in the block.
    ///
    /// **Not a band, and the first version of this file got that wrong.** The
    /// caption's own strip was read as «the bottom 24 pt», which is the caption
    /// only while nothing is below it — with the rule paused, the suppression
    /// banner grows into exactly that strip and the reading became 804412 for
    /// a caption that was not there. Two renders that differ in one thing and
    /// are compared against each other need no such arithmetic: everything else
    /// on screen is identical and cancels.
    private func ink(ruleHolds: Bool, state: SessionHero, suppressed: Bool = false) -> Int {
        let host = NSHostingView(rootView: AnyView(
            hero(ruleHolds: ruleHolds, state: state, suppressed: suppressed)))
        host.frame = NSRect(x: 0, y: 0, width: HelmLayout.settingsColumn,
                            height: host.fittingSize.height)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4 else { return -1 }
        var mass = 0
        for y in 0..<rep.pixelsHigh {
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
        let with = ink(ruleHolds: true, state: state)
        let without = ink(ruleHolds: false, state: state)
        try XCTSkipIf(with < 0 || without < 0, "nothing drew — no window server")

        XCTAssertGreaterThan(with, without,
                             "the caption is not on screen while a rule's trigger holds, so "
                             + "Stop pauses that rule with nothing saying so: \(with) vs "
                             + "\(without)")
    }

    /// Once the rule *is* paused, the caption stops offering to pause it.
    ///
    /// Photographed during this change: the caption sat directly above the
    /// banner that says the same thing, one of them in the future tense about
    /// something that had already happened. The banner stays, because it is the
    /// one carrying the way back.
    func testTheCaptionGoesOnceTheRuleIsActuallyPaused() throws {
        let state = SessionHero.automatic([.externalDisplay])
        let holds = ink(ruleHolds: true, state: state, suppressed: true)
        let not = ink(ruleHolds: false, state: state, suppressed: true)
        try XCTSkipIf(holds < 0 || not < 0, "nothing drew — no window server")

        XCTAssertEqual(holds, not,
                       "«Stop pauses the rule» is still on screen above a banner saying the "
                       + "rule is already paused: \(holds) vs \(not)")
    }

    /// The same in the state that always carried it, so moving the caption out
    /// of `.automatic` did not lose it there.
    func testTheAutomaticStateStillCarriesIt() throws {
        let with = ink(ruleHolds: true, state: .automatic([.externalDisplay]))
        let without = ink(ruleHolds: false, state: .automatic([.externalDisplay]))
        try XCTSkipIf(with < 0 || without < 0, "nothing drew — no window server")

        XCTAssertGreaterThan(with, without)
    }
}
