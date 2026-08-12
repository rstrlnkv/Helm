import AppKit
import SwiftUI
import XCTest
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

    private struct Harness: View {
        @ObservedObject var veto: Veto
        let announce: (String) -> Void

        var body: some View {
            KeepAwakeHero(state: .idle, now: now, anyRuleOn: true,
                          defaultDurationMinutes: 60, suppressed: false, ruleHolds: false,
                          batteryStopped: veto.stopped, batteryFloor: floor,
                          timedNote: { _ in "" },
                          start: { _ in }, stop: {}, resume: {}, announce: announce)
                .frame(width: HelmLayout.settingsColumn)
        }

        private var now: Date { AVetoedScreenOffersNothingAndSaysSoTests.now }
        private var floor: Int { AVetoedScreenOffersNothingAndSaysSoTests.floor }
    }

    private var veto: Veto!
    private var host: NSHostingView<Harness>!
    private var window: NSWindow!
    private var said: [String] = []

    /// `async`, so the isolation of the class is inherited: a synchronous
    /// `setUp()` override is nonisolated, and every line below it touches AppKit.
    override func setUp() async throws {
        veto = Veto()
        said = []
        let harness = Harness(veto: veto, announce: { [self] in said.append($0) })
        host = NSHostingView(rootView: harness)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                              width: HelmLayout.settingsColumn, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: HelmLayout.settingsColumn, height: 400)
        window.layoutIfNeeded()
        settle()
    }

    override func tearDown() async throws {
        window?.contentView = nil
        window = nil
        host = nil
        veto = nil
    }

    private func settle(_ turns: Int = 40) {
        for _ in 0..<turns {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
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

    /// Colour mass in a band of the settled render, in points from the top.
    ///
    /// `nil` for anything that would make the reading a guess: no window server,
    /// or a render that does not reach the band. The second is not a skip — a band
    /// off the end of the image would read as zero ink, which is what «the row is
    /// gone» looks like, so it has to be told apart from it.
    private func ink(_ band: ClosedRange<Int>) -> Int? {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4,
              host.bounds.height > 0 else { return nil }
        let scale = max(1, rep.pixelsHigh / Int(host.bounds.height))
        guard band.upperBound * scale <= rep.pixelsHigh else { return nil }
        var mass = 0
        for y in (band.lowerBound * scale)..<(band.upperBound * scale) {
            for x in 0..<rep.pixelsWide {
                let at = y * rep.bytesPerRow + x * 4
                mass += Int(data[at]) + Int(data[at + 1]) + Int(data[at + 2])
            }
        }
        return mass
    }

    /// The control, and it comes first: «the verbs are dim» is satisfied by a
    /// page with no verbs on it, and «the reason line is gone» by a page that
    /// never drew one.
    func testTheIdleBlockDrawsItsReasonAndItsVerbsWhenNothingIsWrong() throws {
        let reason = try XCTUnwrap(ink(Band.reason), "nothing drew — no window server")
        let verbs = try XCTUnwrap(ink(Band.verbs))
        XCTAssertGreaterThan(reason, 10_000, "the reason line was not drawn at all")
        XCTAssertGreaterThan(verbs, 100_000, "the row of verbs was not drawn at all")
    }

    func testEveryStartOnTheRowGoesDimUnderTheVeto() throws {
        let before = try XCTUnwrap(ink(Band.verbs), "nothing drew — no window server")
        let figureBefore = try XCTUnwrap(ink(Band.figure))

        veto.stopped = true
        settle()

        let after = try XCTUnwrap(ink(Band.verbs))
        XCTAssertLessThan(after, before * 3 / 4,
                          "the five verbs are drawn exactly as they were, so they still invite a "
                          + "press the engine refuses on arrival — beside a notice explaining why "
                          + "nothing happened")
        XCTAssertGreaterThan(after, 0,
                             "the row vanished rather than going dim, which takes the block's "
                             + "height with it and leaves nobody able to see what is unavailable")
        XCTAssertEqual(try XCTUnwrap(ink(Band.figure)), figureBefore,
                       "the figure above moved as well, so this reading is about the page "
                       + "redrawing rather than about the buttons")
    }

    /// And they come back, or this is a page that never recovers when the charger
    /// goes in — the veto lifting by itself is the whole promise the notice makes.
    func testTheyComeBackWhenTheVetoLifts() throws {
        let before = try XCTUnwrap(ink(Band.verbs), "nothing drew — no window server")
        veto.stopped = true
        settle()
        XCTAssertLessThan(try XCTUnwrap(ink(Band.verbs)), before * 3 / 4,
                          "precondition: they went dim")

        veto.stopped = false
        settle()

        XCTAssertEqual(try XCTUnwrap(ink(Band.verbs)), before,
                       "the charger went in and the page stayed dim")
    }

    /// Item 12's other half: the banner *is* the reason, so the vaguer line above
    /// it steps aside rather than answering the same question worse.
    func testTheIdleReasonStepsAsideForTheNotice() throws {
        let before = try XCTUnwrap(ink(Band.reason), "nothing drew — no window server")
        XCTAssertGreaterThan(before, 10_000, "precondition: the line was there to lose")

        veto.stopped = true
        settle()

        XCTAssertEqual(try XCTUnwrap(ink(Band.reason)), 0,
                       "«No rule applies right now» sat between a figure saying the Mac sleeps "
                       + "and a notice naming the charge — two answers to one question, and the "
                       + "useful one was the lower")
    }

    // MARK: - The announcement

    func testTheVetoIsAnnouncedOnceWhenItArrives() {
        XCTAssertEqual(said, [], "precondition: nothing is announced by merely opening the page")

        veto.stopped = true
        settle()

        XCTAssertEqual(said, [KAStr.stoppedByBattery(Self.floor)],
                       "a session ended, five buttons went dead and a field grew in, and a "
                       + "VoiceOver reader was told none of it")
    }

    /// The long form, with the way out in it — not the panel's short one. Said
    /// once is the only chance there is to say what to do about it.
    func testWhatIsSaidCarriesTheWayOut() {
        veto.stopped = true
        settle()

        let sentence = try? XCTUnwrap(said.first)
        XCTAssertEqual(sentence, KAStr.stoppedByBattery(Self.floor))
        XCTAssertNotEqual(sentence, KAStr.stoppedByBatteryShort(Self.floor),
                          "the short form is the panel's: it states the boundary and stops, "
                          + "and a reader who cannot see the greyed buttons has nothing else")
    }

    /// The falling edge is not news worth interrupting anybody for — the buttons
    /// work again, which is what pressing one will say.
    func testTheVetoLiftingIsNotAnnounced() {
        veto.stopped = true
        settle()
        XCTAssertEqual(said.count, 1, "precondition: the arrival was announced")

        veto.stopped = false
        settle()

        XCTAssertEqual(said.count, 1, "the guard lifting interrupted whatever was being read")
    }

    /// And the page redrawing does not say it again. The hero is rebuilt once a
    /// second by the page's own `TimelineView`, so «once» has to mean once per
    /// edge rather than once per body.
    func testARedrawWithTheVetoStillInForceSaysNothingFurther() {
        veto.stopped = true
        settle()
        XCTAssertEqual(said.count, 1)

        veto.objectWillChange.send()
        settle()

        XCTAssertEqual(said.count, 1, "every redraw under the veto announced it again")
    }
}
