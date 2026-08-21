import XCTest
import SwiftUI
import AppKit
import HelmUI
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// The button's word is the name of what pressing it will do **now**, and never
/// a mode the last press put it into.
///
/// That is the whole answer to «how long does it stay ‹Отключить›»: as long as
/// the state it names is true, and not one moment past it. There is no armed
/// flag to expire, none to survive a relaunch, and none to go on offering a
/// second step after the rule it was aimed at has quit — the four inputs are
/// re-read on every rebuild, and the page rebuilds every second under its own
/// `TimelineView`.
///
/// The engine's half of the same decision is in
/// `TheSecondPressIsWhatEndsTheRulesTests`; both sides call `StopPress.next`, so
/// the word somebody reads and the act they get cannot drift apart.
@MainActor
final class TheStopButtonSaysWhatThePressWillDoTests: XCTestCase {

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func hero(_ state: SessionHero, ruleHolds: Bool, timerEndsAutomation: Bool,
                      suppressed: Bool = false, batteryStopped: Bool = false) -> KeepAwakeHero {
        // Both battery inputs at every call, and the new one too: they carry no
        // defaults on purpose, because a default here looks exactly like
        // «nothing is wrong» — `TheBatteryNoticeReachesThePageTests` is the
        // account of what that cost the last time.
        KeepAwakeHero(state: state, now: Self.now, anyRuleOn: true,
                      defaultDurationMinutes: 60, suppressed: suppressed,
                      ruleHolds: ruleHolds, timerEndsAutomation: timerEndsAutomation,
                      batteryStopped: batteryStopped, batteryFloor: 20,
                      timedNote: { _ in "until 15:42" },
                      start: { _ in }, stop: {}, resume: {})
    }

    // MARK: - The word

    func testTheWordForEachPress() {
        XCTAssertEqual(KAStr.stopWord(.stopEverything), KAStr.stop)
        XCTAssertEqual(KAStr.stopWord(.stopSessionOnly), KAStr.stop,
                       "the first of two steps is still a stop; it is the session it stops")
        XCTAssertNotEqual(KAStr.stopWord(.turnAutomationOff), KAStr.stop,
                          "a press that switches somebody's automation off must not be reading "
                          + "as the ordinary Stop they pressed a moment ago")
    }

    // MARK: - Which press the block is offering

    /// A session running over a rule, with the switch on: the first step.
    func testACountdownOverARuleOffersTheFirstStep() {
        let state = SessionHero.timed(until: Self.now.addingTimeInterval(3600))
        XCTAssertEqual(hero(state, ruleHolds: true, timerEndsAutomation: true).stopPress,
                       .stopSessionOnly)
    }

    /// The session is over and the rule is still holding: the second step, and
    /// the only thing left for the button to mean.
    func testARuleHoldingOnItsOwnOffersTheSecondStep() {
        XCTAssertEqual(hero(.automatic([.app]), ruleHolds: true,
                            timerEndsAutomation: true).stopPress,
                       .turnAutomationOff)
    }

    /// With the switch off the button never renames itself, in either state.
    func testWithTheSwitchOffTheButtonIsAlwaysTheOnePress() {
        let timed = SessionHero.timed(until: Self.now.addingTimeInterval(3600))
        XCTAssertEqual(hero(timed, ruleHolds: true, timerEndsAutomation: false).stopPress,
                       .stopEverything)
        XCTAssertEqual(hero(.automatic([.app]), ruleHolds: true,
                            timerEndsAutomation: false).stopPress,
                       .stopEverything)
    }

    /// **The rule quit while somebody was reading the button.** Nothing is held
    /// and nothing is paused, so the second step is not merely inapplicable —
    /// it names something that no longer exists.
    func testARuleThatQuitTakesTheSecondStepWithIt() {
        XCTAssertEqual(hero(.indefinite, ruleHolds: false,
                            timerEndsAutomation: true).stopPress,
                       .stopEverything)
    }

    /// `SessionHero` is what the block is handed, so «is a session running» is
    /// answered from it rather than derived a second time by whoever draws.
    func testWhichStatesAreASessionSomebodyStarted() {
        XCTAssertTrue(SessionHero.timed(until: Self.now).sessionRunning)
        XCTAssertTrue(SessionHero.indefinite.sessionRunning)
        XCTAssertFalse(SessionHero.automatic([.app]).sessionRunning,
                       "a rule holding the Mac is not a session anybody started")
        XCTAssertFalse(SessionHero.idle.sessionRunning)
    }

    // MARK: - The caption under the buttons

    /// «Stop pauses the rule until it applies again» is a claim about the next
    /// press, and with the switch on the next press does no such thing. Left
    /// where it was, the page would be promising the opposite of what the
    /// button beside it now does.
    func testTheCaptionIsOnlyOfferedWhileOnePressReallyDoesBoth() {
        let timed = SessionHero.timed(until: Self.now.addingTimeInterval(3600))
        XCTAssertTrue(hero(timed, ruleHolds: true, timerEndsAutomation: false)
            .saysWhatStopWouldDo)
        XCTAssertFalse(hero(timed, ruleHolds: true, timerEndsAutomation: true)
            .saysWhatStopWouldDo,
                       "the caption says Stop pauses the rule, and with the switch on it does not")
        XCTAssertFalse(hero(.automatic([.app]), ruleHolds: true, timerEndsAutomation: true)
            .saysWhatStopWouldDo,
                       "and on the second step the button says what it does, so the caption is "
                       + "a sentence about a control that is no longer on screen")
    }

    // MARK: - …and all of it reaches the screen

    /// Ink in a band of the settled block, in points from its top.
    ///
    /// The two properties above are what the button is *told*; this is what a
    /// reader sees, and the two are not the same check — a `stopButton` that
    /// ignored `stopPress` and went on drawing `KAStr.stop` would leave every
    /// assertion above green.
    ///
    /// **The bands were measured, not reasoned about.** The block settles at
    /// 145 pt, 290 device rows at 2×, and the same hero was rendered with the
    /// switch on and off, row against row. In `.automatic` the two differ from
    /// device row 194 to 289; in `.timed` only from 265 to 289, and there the
    /// second reading is **zero**. So 132.5 pt down is where the caption starts
    /// and everything above it in that stretch is the row of verbs.
    private func ink(_ state: SessionHero, timerEndsAutomation: Bool,
                     from top: CGFloat, to bottom: CGFloat) -> Int {
        let view = hero(state, ruleHolds: true, timerEndsAutomation: timerEndsAutomation)
            .frame(width: HelmLayout.settingsColumn)
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: HelmLayout.settingsColumn,
                            height: host.fittingSize.height)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4,
              host.bounds.height > 0 else { return -1 }
        let scale = CGFloat(rep.pixelsHigh) / host.bounds.height
        var mass = 0
        for y in Int(top * scale)..<min(Int(bottom * scale), rep.pixelsHigh) {
            for x in 0..<rep.pixelsWide { mass += Int(data[y * rep.bytesPerRow + x * 4 + 3]) }
        }
        return mass
    }

    private static let buttons: (CGFloat, CGFloat) = (97, 132)
    private static let caption: (CGFloat, CGFloat) = (133, 145)

    /// The second step, on screen: the row of verbs is not the row it was.
    func testTheButtonRowIsRedrawnWhenTheSecondStepIsWhatIsOffered() throws {
        let (top, bottom) = Self.buttons
        let one = ink(.automatic([.app]), timerEndsAutomation: false, from: top, to: bottom)
        let two = ink(.automatic([.app]), timerEndsAutomation: true, from: top, to: bottom)
        try XCTSkipIf(one < 0 || two < 0, "nothing drew — no window server")
        XCTAssertGreaterThan(one, 0, "the band is empty, so the comparison below reads nothing")

        XCTAssertNotEqual(one, two,
                          "the button is still drawing the word «Stop» in the state where "
                          + "pressing it switches somebody's automation off: \(one) vs \(two)")
    }

    /// **The control, and it is the half that says the band means the buttons.**
    /// A countdown is the first step whatever the switch says, so this row must
    /// come out pixel for pixel the same — if it did not, the reading above
    /// would be the caption below moving, or the page reflowing, and would
    /// prove nothing about a word.
    func testACountdownsButtonRowIsUntouchedByTheSwitch() throws {
        let (top, bottom) = Self.buttons
        let state = SessionHero.timed(until: Self.now.addingTimeInterval(3600))
        let one = ink(state, timerEndsAutomation: false, from: top, to: bottom)
        let two = ink(state, timerEndsAutomation: true, from: top, to: bottom)
        try XCTSkipIf(one < 0 || two < 0, "nothing drew — no window server")
        XCTAssertGreaterThan(one, 0, "the band is empty, so this cannot fail")

        XCTAssertEqual(one, two,
                       "the countdown's Stop renamed itself on a press that only ends the "
                       + "countdown: \(one) vs \(two)")
    }

    /// And the caption really does leave the screen, rather than merely being
    /// withheld by a property nothing draws from.
    func testTheCaptionLeavesTheScreenOnceOnePressNoLongerDoesBoth() throws {
        let (top, bottom) = Self.caption
        let state = SessionHero.timed(until: Self.now.addingTimeInterval(3600))
        let shown = ink(state, timerEndsAutomation: false, from: top, to: bottom)
        let gone = ink(state, timerEndsAutomation: true, from: top, to: bottom)
        try XCTSkipIf(shown < 0 || gone < 0, "nothing drew — no window server")

        XCTAssertGreaterThan(shown, 0, "the caption was never on screen, so its absence is not "
                             + "news and this check cannot fail")
        XCTAssertEqual(gone, 0,
                       "«Stop pauses the rule until it applies again» is still under a button "
                       + "that no longer does: \(gone)")
    }

    /// The three states it was already withheld in, unchanged by any of this.
    func testTheCaptionsOtherThreeRefusalsStand() {
        let timed = SessionHero.timed(until: Self.now.addingTimeInterval(3600))
        XCTAssertFalse(hero(timed, ruleHolds: false, timerEndsAutomation: false)
            .saysWhatStopWouldDo, "no rule holds, so there is nothing to pause")
        XCTAssertFalse(hero(timed, ruleHolds: true, timerEndsAutomation: false, suppressed: true)
            .saysWhatStopWouldDo, "already paused, and the banner below carries the way back")
        XCTAssertFalse(hero(.idle, ruleHolds: true, timerEndsAutomation: false,
                            batteryStopped: true).saysWhatStopWouldDo,
                       "the battery guard has everything stopped and there is no Stop on screen")
    }
}
