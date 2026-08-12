import AppKit
import SwiftUI
import XCTest
import HelmTestSupport
import HelmUI
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// Five live buttons that could not do anything, and a change nobody was told
/// about.
///
/// While the battery guard vetoes, `recompute` reaches `releaseForBattery` before
/// anything is held: a session asked for is refused **instantly**, which is the
/// «pressed 15 min at 5 % and nothing happened» this module's notice was written
/// for. The notice arrived and the buttons stayed live, so the page's answer to
/// «why did nothing happen» sat beside five invitations to try again — and the
/// second press is what makes somebody decide the app is broken rather than the
/// battery flat.
///
/// The other half is the same state as heard rather than seen. Every other change
/// on this page follows a press, so the screen's answer is the answer to something
/// the reader just did. This one arrives because a charge fell: the session ends,
/// the buttons go grey, a field grows in, and none of it moves focus or changes
/// the value of anything a VoiceOver reader is on.
@MainActor
final class AVetoedScreenOffersNothingAndSaysSoTests: XCTestCase {

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let floor = 20

    /// The engine drives this, so the test does too: a box the harness can write
    /// while the mounted view keeps its identity, which is what `onChange` needs
    /// to see an edge at all.
    private final class Veto: ObservableObject {
        @Published var stopped = false
    }

    /// **Pinned to the top of the block, and that is what makes a band mean
    /// anything.** A hero shorter than the window is centred in it, so a notice
    /// growing in at the foot moves the figure and the verbs up by half its
    /// height — and every band below would then be measuring the page sliding
    /// past a fixed rectangle. The `Spacer` takes the slack instead, which is what
    /// the settings page does with it.
    private struct Harness: View {
        @ObservedObject var veto: Veto
        let announce: (String) -> Void

        var body: some View {
            VStack(spacing: 0) {
                KeepAwakeHero(state: .idle, now: now, anyRuleOn: true,
                              defaultDurationMinutes: 60, suppressed: false, ruleHolds: false,
                              batteryStopped: veto.stopped, batteryFloor: floor,
                              timedNote: { _ in "" },
                              start: { _ in }, stop: {}, resume: {}, announce: announce)
                Spacer(minLength: 0)
            }
            .frame(width: HelmLayout.settingsColumn)
        }

        private var now: Date { AVetoedScreenOffersNothingAndSaysSoTests.now }
        private var floor: Int { AVetoedScreenOffersNothingAndSaysSoTests.floor }
    }

    private var mounted: [MountedRender] = []
    private var said: [String] = []

    /// One block, in one named screen, settled.
    ///
    /// Built per reading rather than in `setUp`, because the appearance is an
    /// input now: the pixel checks below take it twice, once for each screen
    /// somebody might be looking at.
    private func mount(_ appearance: NSAppearance.Name) -> (Veto, MountedRender) {
        let veto = Veto()
        let render = MountedRender(Harness(veto: veto, announce: { [self] in said.append($0) }),
                                   width: HelmLayout.settingsColumn, height: 400,
                                   appearance: appearance)
        mounted.append(render)
        render.settle()
        return (veto, render)
    }

    /// `async`, so the isolation of the class is inherited: a synchronous
    /// `tearDown()` override is nonisolated, and every line below it touches
    /// AppKit.
    override func tearDown() async throws {
        mounted.forEach { $0.drop() }
        mounted = []
        said = []
        try await super.tearDown()
    }

    // MARK: - The buttons

    /// **Bands, and they were measured rather than reasoned about.** The
    /// accessibility tree was the first attempt and is not available here: an
    /// `NSHostingView` builds its elements for a real AX client, so
    /// `accessibilityChildren()` is empty under the suite whatever the buttons
    /// are — a check that could only ever skip, which a failures-only summary
    /// reads as green.
    ///
    /// So this reads the render, and the profile of the two states is what says
    /// where to read. Row by row of the settled hero — 744 pt wide, 145 pt tall,
    /// 290 device rows at 2× — ink under the veto against ink without it:
    /// identical from pixel 20 to 80 (the 40 pt figure), **zero against ~98 000**
    /// from 116 to 142 (the reason line), and **halved** from 196 to 250
    /// (168 408 → 60 489 at the widest row — the buttons, still drawn and no
    /// longer black). Nothing else on the block moves, because opacity does not
    /// change layout and the notice grows in *below* every one of these.
    ///
    /// In points, which is what `ink` takes, because the scale is a fact about
    /// whichever display the suite runs on and the bands are not.
    private enum Band {
        /// The 40 pt figure, which neither change may touch.
        static let figure = 10...40
        /// «No rule applies right now».
        static let reason = 56...74
        /// The row of five verbs.
        static let verbs = 96...126
    }

    /// **The reading was the weather, and this is the correction.** The bands
    /// above were right and the instrument under them summed *colour* — r + g + b
    /// — of type drawn in `labelColor`. That resolves to white in dark and black
    /// in light, and `cacheDisplay` hands back premultiplied bytes, so black type
    /// on a transparent view is `(0, 0, 0, α)` and every one of these bands read
    /// **exactly zero** in light. Four of the tests below were green for as long as
    /// this Mac was dark and went red at 04:34:58 on 2026-08-12, when it turned
    /// itself light, with nothing committed since 03:05.
    ///
    /// `RenderedInk` reads the departure from the band's own background instead,
    /// which is the alpha coverage on a transparent view and the colour difference
    /// on an opaque card — measured within 14 % of itself between the two screens
    /// for type, and 0.358 of full for `.opacity(0.35)` in both. So every band is
    /// now read **twice, in both screens**, and the numbers below hold in each.
    ///
    /// Measured 2026-08-12 on the quiet block, light then dark: figure
    /// 1 873 457 / 1 873 457, reason 387 351 / 442 917, verbs
    /// 1 308 727 / 1 385 391. Under the veto the verbs read 43 % of that and the
    /// reason band reads 0, in both. The 40 pt figure agreeing to the byte while
    /// the 13 pt line under it is 14 % heavier in dark is why the thresholds here
    /// are floors and ratios rather than recorded values: what moves between the
    /// two screens is how much ink small type is given, and no assertion should
    /// have to know that number.
    private func ink(_ render: MountedRender, _ band: ClosedRange<Int>) -> Int? {
        render.ink(band)
    }

    /// The control, and it comes first: «the verbs are dim» is satisfied by a
    /// page with no verbs on it, and «the reason line is gone» by a page that
    /// never drew one.
    func testTheIdleBlockDrawsItsReasonAndItsVerbsWhenNothingIsWrong() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let (_, render) = mount(appearance)
            let reason = try XCTUnwrap(ink(render, Band.reason),
                                       "nothing drew in \(screen) — no window server")
            let verbs = try XCTUnwrap(ink(render, Band.verbs))
            XCTAssertGreaterThan(reason, 10_000, "the reason line was not drawn at all in \(screen)")
            XCTAssertGreaterThan(verbs, 100_000, "the row of verbs was not drawn at all in \(screen)")
        }
    }

    func testEveryStartOnTheRowGoesDimUnderTheVeto() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let (veto, render) = mount(appearance)
            let before = try XCTUnwrap(ink(render, Band.verbs),
                                       "nothing drew in \(screen) — no window server")
            let figureBefore = try XCTUnwrap(ink(render, Band.figure))
            XCTAssertGreaterThan(before, 100_000, "precondition: the verbs were there to dim")

            veto.stopped = true
            render.settle()

            let after = try XCTUnwrap(ink(render, Band.verbs))
            XCTAssertLessThan(after, before * 3 / 4,
                              "in \(screen) the five verbs are drawn exactly as they were, so "
                              + "they still invite a press the engine refuses on arrival — beside "
                              + "a notice explaining why nothing happened")
            XCTAssertGreaterThan(after, 0,
                                 "the row vanished rather than going dim, which takes the block's "
                                 + "height with it and leaves nobody able to see what is "
                                 + "unavailable")
            XCTAssertEqual(try XCTUnwrap(ink(render, Band.figure)), figureBefore,
                           "the figure above moved as well, so this reading is about the page "
                           + "redrawing rather than about the buttons")
        }
    }

    /// And they come back, or this is a page that never recovers when the charger
    /// goes in — the veto lifting by itself is the whole promise the notice makes.
    func testTheyComeBackWhenTheVetoLifts() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let (veto, render) = mount(appearance)
            let before = try XCTUnwrap(ink(render, Band.verbs),
                                       "nothing drew in \(screen) — no window server")
            XCTAssertGreaterThan(before, 100_000, "precondition: the verbs were there to dim")
            veto.stopped = true
            render.settle()
            XCTAssertLessThan(try XCTUnwrap(ink(render, Band.verbs)), before * 3 / 4,
                              "precondition: they went dim in \(screen)")

            veto.stopped = false
            render.settle()

            XCTAssertEqual(try XCTUnwrap(ink(render, Band.verbs)), before,
                           "the charger went in and the page stayed dim in \(screen)")
        }
    }

    /// Item 12's other half: the banner *is* the reason, so the vaguer line above
    /// it steps aside rather than answering the same question worse.
    func testTheIdleReasonStepsAsideForTheNotice() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let (veto, render) = mount(appearance)
            let before = try XCTUnwrap(ink(render, Band.reason),
                                       "nothing drew in \(screen) — no window server")
            XCTAssertGreaterThan(before, 10_000,
                                 "precondition: the line was there to lose in \(screen)")

            veto.stopped = true
            render.settle()

            XCTAssertEqual(try XCTUnwrap(ink(render, Band.reason)), 0,
                           "in \(screen), «No rule applies right now» sat between a figure saying "
                           + "the Mac sleeps and a notice naming the charge — two answers to one "
                           + "question, and the useful one was the lower")
        }
    }

    // MARK: - The announcement

    /// One screen for these four, named rather than inherited: what is being
    /// counted is an edge in the engine's own state reaching `announce`, and a
    /// sentence read aloud is the same sentence on either screen. The pixel checks
    /// above are the ones the appearance can move, and they take both.
    private static let eitherScreen = NSAppearance.Name.aqua

    func testTheVetoIsAnnouncedOnceWhenItArrives() {
        let (veto, render) = mount(Self.eitherScreen)
        XCTAssertEqual(said, [], "precondition: nothing is announced by merely opening the page")

        veto.stopped = true
        render.settle()

        XCTAssertEqual(said, [KAStr.stoppedByBattery(Self.floor)],
                       "a session ended, five buttons went dead and a field grew in, and a "
                       + "VoiceOver reader was told none of it")
    }

    /// The long form, with the way out in it — not the panel's short one. Said
    /// once is the only chance there is to say what to do about it.
    func testWhatIsSaidCarriesTheWayOut() throws {
        let (veto, render) = mount(Self.eitherScreen)
        veto.stopped = true
        render.settle()

        let sentence = try XCTUnwrap(said.first, "nothing was announced at all")
        XCTAssertEqual(sentence, KAStr.stoppedByBattery(Self.floor))
        XCTAssertNotEqual(sentence, KAStr.stoppedByBatteryShort(Self.floor),
                          "the short form is the panel's: it states the boundary and stops, "
                          + "and a reader who cannot see the greyed buttons has nothing else")
    }

    /// The falling edge is not news worth interrupting anybody for — the buttons
    /// work again, which is what pressing one will say.
    func testTheVetoLiftingIsNotAnnounced() {
        let (veto, render) = mount(Self.eitherScreen)
        veto.stopped = true
        render.settle()
        XCTAssertEqual(said.count, 1, "precondition: the arrival was announced")

        veto.stopped = false
        render.settle()

        XCTAssertEqual(said.count, 1, "the guard lifting interrupted whatever was being read")
    }

    /// And the page redrawing does not say it again. The hero is rebuilt once a
    /// second by the page's own `TimelineView`, so «once» has to mean once per
    /// edge rather than once per body.
    func testARedrawWithTheVetoStillInForceSaysNothingFurther() {
        let (veto, render) = mount(Self.eitherScreen)
        veto.stopped = true
        render.settle()
        XCTAssertEqual(said.count, 1)

        veto.objectWillChange.send()
        render.settle()

        XCTAssertEqual(said.count, 1, "every redraw under the veto announced it again")
    }
}
