import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// The hero and the panel tile each have **one** slot under their buttons, and
/// two things can want it: a rule that has been paused, and the battery guard
/// having stopped everything.
///
/// Both are true at once whenever a rule's trigger holds while the charge is
/// under the floor — `recompute` refreshes the triggers and then vetoes, leaving
/// `suppressed` exactly as it was — and of the two only the guard explains why
/// nothing at all is running. «Resume» while the veto is in force is a control
/// that cannot do what it says, so the battery notice wins and carries no verb:
/// it goes by itself when the charger goes in.
///
/// **This file used to read the source, and that is why it is rewritten.** It
/// greped `KeepAwakeHero.swift` for the two branches and their order — both of
/// which were there, both correct — while the page's call to the hero passed
/// neither battery argument, so the branch it was pinning could not be reached
/// from any screen. Green over a cut wire, for a release.
///
/// So the precedence is measured now, on both surfaces, as pixels and as height:
///
/// - **which wins** — with both flags true the block is *identical* to the one
///   drawn with the battery alone, down to the last channel of the last pixel;
/// - **and they never stack** — the block is no taller with both than with
///   either, which a second notice under the first could not satisfy.
///
/// `TheBatteryNoticeReachesThePageTests` asks a different question with the same
/// instrument: whether an event on the transport reaches the settings page at
/// all. This one is about what happens in the slot once it does.
@MainActor
final class BothNoticesShareOneSlotTests: XCTestCase {

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// The width the tile is drawn at in the narrowest panel — read from
    /// `PanelGrid` rather than typed, since the number is the panel's and moves
    /// with it. All four readings are taken at one width, so what it has to be is
    /// plausible rather than exact.
    private static var tileWidth: CGFloat { PanelGrid.narrowestPanel - PanelGrid.padding * 2 }

    private var mounted: [MountedRender] = []
    private var alive: [AnyObject] = []

    /// Every window a reading opened is dropped here, and with it the hosted view
    /// and the view model behind it.
    ///
    /// **`async`, which is what makes it main-actor.** The synchronous
    /// `XCTestCase.tearDown` is nonisolated, so touching this class's own state
    /// from it warns — four files in this directory carry that warning today — and
    /// `MainActor.assumeIsolated` does not fix it: it sends `self` into the
    /// closure, which Swift 6 refuses outright (measured, `error: sending 'self'
    /// risks causing data races`). The `async` override inherits the class's
    /// isolation instead, so the properties are reached where they live.
    override func tearDown() async throws {
        mounted.forEach { $0.drop() }
        mounted = []
        alive = []
        try await super.tearDown()
    }

    // MARK: - The reading

    /// One settled still: every channel of every pixel, and the height the block
    /// asks for.
    ///
    /// Two numbers because the two claims are different. Colour mass answers «is
    /// this the same drawing» — the notices differ in their mark, their sentence
    /// and one of them has a button, so two renders that agree to the channel are
    /// the same notice. Height answers «is there one of them»: a slot holding two
    /// banners is taller by a banner, whatever either of them says.
    ///
    /// **Not colour, and not alpha: the departure from the background.** Colour
    /// mass — r + g + b — was the first instrument and it could only ever work on
    /// one of the two screens: `labelColor` is black in light, `cacheDisplay`
    /// premultiplies, so a quiet hero of type and buttons summed to *exactly zero*
    /// and `colourMass` reported «nothing drew». Two tests here failed in 0.08 s
    /// the morning this Mac turned itself light. Alpha is no better the other way
    /// round: the panel tile draws on an opaque card where every pixel is 255 —
    /// the mistake `SettingsPageProbe` records making once, in the file next door.
    /// `RenderedInk` answers both, and the readings below are taken in both
    /// screens.
    private struct Still {
        let mass: Int
        let height: CGFloat
    }

    /// **Settled on the pixels themselves, and the first version was not.**
    ///
    /// Both notices arrive by *growing* — the row is always in the hierarchy, its
    /// natural height is measured, and the frame animates between zero and that
    /// number over 300 ms and two round trips through `onGeometryChange`. Settling
    /// on the host's `fittingSize` looked like the answer and is blind to it: the
    /// panel tile's own height is fixed by its card, so the outer measurement was
    /// stable from the first turn while the notice inside was still ramping. Three
    /// consecutive runs of the panel reading then gave 9 690 566 / 9 944 005,
    /// 9 690 566 / 10 435 283 and 9 360 957 / 9 944 005 — six different numbers
    /// for two renders, which is a check that reports the weather.
    ///
    /// So `MountedRender.settledInk` reads the bitmap every turn and stops when the
    /// reading has repeated eight times running — the loop was written here and
    /// moved to `Tests/Support` when the second file needed it. A block that never
    /// settles returns nothing at all rather than its last frame: an unsettled
    /// still is not a slower measurement, it is a different one every time.
    private func still<V: View>(_ view: V, width: CGFloat, height: CGFloat,
                                in appearance: NSAppearance.Name) -> Still? {
        let render = MountedRender(view, width: width, height: height, appearance: appearance)
        mounted.append(render)
        // Zero ink is a bitmap holding nothing but its own background, which is a
        // machine with no window server rather than a still — and every equality
        // below would be satisfied by two of them.
        guard let mass = render.settledInk(), mass > 0 else { return nil }
        return Still(mass: mass, height: render.fittingHeight)
    }

    // MARK: - The settings page's block

    /// The hero as the page builds it, with only the two flags differing.
    ///
    /// **`ruleHolds` is false in every reading, and it has to be.** The block holds
    /// one other thing that reads `suppressed` — the caption «Stop pauses the rule
    /// until it applies again», drawn on `ruleHolds && !suppressed` — so with a
    /// trigger holding, the battery-only and the both-flags renders differ by the
    /// caption as well as by the slot, and the equality below fails for a reason
    /// that has nothing to do with which notice won. Measured, before this
    /// parameter was pinned: 1 685 235 of colour, which is that 11 pt line and
    /// nothing else. Two renders compared against each other have to differ in one
    /// thing, which is the lesson `TheStopCaptionIsOnScreenOrNotTests` records
    /// learning about a band; what the caption does under a veto is that file's
    /// question, not this one's.
    private func hero(suppressed: Bool, batteryStopped: Bool) -> some View {
        KeepAwakeHero(state: .idle, now: Self.now, anyRuleOn: true,
                      defaultDurationMinutes: 60, suppressed: suppressed,
                      ruleHolds: false, timerEndsAutomation: false,
                      batteryStopped: batteryStopped, batteryFloor: 20,
                      timedNote: { _ in "until 15:42" },
                      start: { _ in }, stop: {}, resume: {})
    }

    private func heroStill(suppressed: Bool, batteryStopped: Bool,
                           in appearance: NSAppearance.Name) -> Still? {
        still(hero(suppressed: suppressed, batteryStopped: batteryStopped),
              width: HelmLayout.settingsColumn, height: 420, in: appearance)
    }

    /// The subject, before anything is said about precedence: a notice arrives at
    /// all, and it arrives by making the block taller. An assertion about which of
    /// two notices is drawn is empty if neither is.
    func testANoticeArrivesInTheSlotAndTakesRoom() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let quiet = try XCTUnwrap(heroStill(suppressed: false, batteryStopped: false,
                                                in: appearance),
                                      "nothing drew in \(screen), or the block never settled")
            let battery = try XCTUnwrap(heroStill(suppressed: false, batteryStopped: true,
                                                  in: appearance))
            let paused = try XCTUnwrap(heroStill(suppressed: true, batteryStopped: false,
                                                 in: appearance))

            XCTAssertGreaterThan(battery.height, quiet.height,
                                 "in \(screen) the battery notice takes no height, so the slot "
                                 + "never opened and every reading below is of an empty block")
            XCTAssertGreaterThan(paused.height, quiet.height,
                                 "the paused notice takes no height either, in \(screen)")
            XCTAssertNotEqual(battery.mass, quiet.mass)
        }
    }

    /// Which of the two wins. Identical pixels, not «the battery one is bigger»:
    /// what is being pinned is that the *same* notice is drawn, and two notices
    /// that merely differ in size would satisfy anything weaker.
    func testTheBatteryNoticeIsTheOneDrawnWhenBothApply() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let battery = try XCTUnwrap(heroStill(suppressed: false, batteryStopped: true,
                                                  in: appearance),
                                        "nothing drew in \(screen), or the block never settled")
            let both = try XCTUnwrap(heroStill(suppressed: true, batteryStopped: true,
                                               in: appearance))

            XCTAssertEqual(both.mass, battery.mass,
                           "in \(screen) a rule is paused and the charge is under the floor, and "
                           + "the block is not the one the battery guard draws on its own: "
                           + "\(both.mass) vs \(battery.mass). «Resume» cannot resume anything "
                           + "while the veto is in force")
        }
    }

    /// And there is one of them. The slot's own height is measured from the two
    /// readings that bracket it, so the assertion is «one notice tall», not a
    /// number typed here that a redesign would falsify.
    func testTheTwoNoticesNeverStack() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let quiet = try XCTUnwrap(heroStill(suppressed: false, batteryStopped: false,
                                                in: appearance),
                                      "nothing drew in \(screen), or the block never settled")
            let battery = try XCTUnwrap(heroStill(suppressed: false, batteryStopped: true,
                                                  in: appearance))
            let both = try XCTUnwrap(heroStill(suppressed: true, batteryStopped: true,
                                               in: appearance))

            let oneNotice = battery.height - quiet.height
            XCTAssertGreaterThan(oneNotice, 10,
                                 "precondition: a notice is worth some height in \(screen)")
            XCTAssertLessThan(both.height, quiet.height + oneNotice * 1.5,
                              "in \(screen) the block is \(both.height) pt with both notices "
                              + "against \(battery.height) with one, and a notice is "
                              + "\(oneNotice) pt — the two are stacked in a slot that has room "
                              + "for one")
        }
    }

    /// The instrument. Both readings above are of production code, so the equality
    /// would hold just as well if the two notices were one sentence — this is the
    /// assertion that says the measurement can tell them apart at all.
    func testTheMeasurementTellsTheTwoNoticesApart() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let battery = try XCTUnwrap(heroStill(suppressed: false, batteryStopped: true,
                                                  in: appearance),
                                        "nothing drew in \(screen), or the block never settled")
            let paused = try XCTUnwrap(heroStill(suppressed: true, batteryStopped: false,
                                                 in: appearance))

            XCTAssertNotEqual(battery.mass, paused.mass,
                              "in \(screen), «Stopped below 20 %» and «Paused until the rule "
                              + "applies again» draw the same pixels, so the equality above "
                              + "cannot fail")
        }
    }

    // MARK: - The panel's block

    /// The tile, fed the engine's own payload over a real transport.
    ///
    /// The tile reads `vm.batteryStopped` where the hero is handed a flag, so
    /// there is no way to ask it this question without the hop — which is the half
    /// the old source check could not see. The payload is the engine's own type;
    /// a dictionary written here would be a second declaration of the wire.
    private func tileStill(suppressed: Bool, batteryStopped: Bool,
                           in appearance: NSAppearance.Name) -> Still? {
        let transport = LocalTransport()
        let host = ModuleViewModel(transport: transport)
        let store = NamespacedStore(namespace: KeepAwakeEngine.moduleID,
                                    backing: InMemoryKeyValueStore())
        let shared = KeepAwakeViewModel.shared(vm: host)
        alive.append(contentsOf: [transport, host, shared] as [AnyObject])
        let payload = KeepAwakeEngine.StatePayload(
            isActive: false, conditions: [], clamshellActive: false, endDate: nil,
            startDate: nil, suppressed: suppressed,
            triggeredConditions: [ActiveCondition.app.rawValue],
            holdingApps: ["com.example.render"], batteryStopped: batteryStopped)
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        transport.emit(EngineEvent(name: KeepAwakeEvent.state.rawValue, payload: data))
        let reading = still(KeepAwakePanelTile(vm: host, store: store),
                            width: Self.tileWidth, height: 420, in: appearance)
        // The subject, checked where it is knowable: the payload really arrived,
        // so a still that says nothing changed is a fact about the tile rather
        // than about a wire that never delivered.
        guard shared.batteryStopped == batteryStopped, shared.suppressed == suppressed else {
            return nil
        }
        return reading
    }

    /// The panel says it at all — it was the settings page only, on the surface
    /// somebody opens deliberately, while the panel they actually use kept the
    /// silence the whole change was about.
    func testThePanelDrawsTheBatteryNotice() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let quiet = try XCTUnwrap(tileStill(suppressed: false, batteryStopped: false,
                                                in: appearance),
                                      "in \(screen) nothing drew, the block never settled, or "
                                      + "the payload never arrived")
            let battery = try XCTUnwrap(tileStill(suppressed: false, batteryStopped: true,
                                                  in: appearance))

            XCTAssertGreaterThan(battery.height, quiet.height,
                                 "in \(screen) the guard stopped everything and the tile is the "
                                 + "same height it is when nothing is wrong: pressing «15 min» "
                                 + "at 5 % is silence in the panel")
        }
    }

    /// …and the same one wins there, in the same direction.
    func testTheBatteryNoticeWinsInThePanelToo() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let battery = try XCTUnwrap(tileStill(suppressed: false, batteryStopped: true,
                                                  in: appearance),
                                        "in \(screen) nothing drew, the block never settled, or "
                                        + "the payload never arrived")
            let both = try XCTUnwrap(tileStill(suppressed: true, batteryStopped: true,
                                               in: appearance))
            let paused = try XCTUnwrap(tileStill(suppressed: true, batteryStopped: false,
                                                 in: appearance))

            XCTAssertNotEqual(battery.mass, paused.mass,
                              "the two notices draw the same pixels in the panel in \(screen), "
                              + "so the equality below cannot fail")
            XCTAssertEqual(both.mass, battery.mass,
                           "in \(screen) the panel draws «Rule paused» with a Resume button "
                           + "while the battery guard has everything stopped: \(both.mass) vs "
                           + "\(battery.mass)")
            XCTAssertEqual(both.height, battery.height,
                           "the panel stacks the two notices in \(screen): \(both.height) pt "
                           + "against \(battery.height)")
        }
    }

    // MARK: - The shape that let the wiring break

    /// **The initialiser must not default the two battery inputs.**
    ///
    /// `batteryStopped: Bool = false, batteryFloor: Int = 0` is what made the
    /// broken call site compile: the page asked for a hero, forgot the two values
    /// it had, and got a hero that could never draw the notice — with nothing red
    /// anywhere. Every other input the hero needs is required, and these two are
    /// the only ones with an answer that looks like «nothing is wrong».
    ///
    /// A source check, and it is the right instrument for once: what is being
    /// pinned is that the **compiler** stands guard here, which no render can
    /// show. Every call site in these tests already passes both, so removing the
    /// defaults is one edit in `KeepAwakeHero.swift` and nothing else.
    func testTheHeroRequiresTheBatteryInputsItDraws() throws {
        let source = try RepoSource.text(of: "Sources/Modules/KeepAwake/UI/KeepAwakeHero.swift")
        XCTAssertGreaterThan(source.count, 5000, "the hero was not read at all")
        XCTAssertTrue(source.contains("batteryStopped: Bool"),
                      "the hero no longer takes the flag at all, so this check is about a "
                      + "parameter that has gone")

        XCTAssertFalse(source.contains("batteryStopped: Bool = false"),
                       "the flag that decides whether the notice can appear defaults to «all "
                       + "well», so a call site that forgets it is not an error anywhere — "
                       + "which is exactly how it went unreachable for a release")
        XCTAssertFalse(source.contains("batteryFloor: Int = 0"),
                       "the floor defaults to 0, so a call site that forgets it draws «Stopped "
                       + "below 0 %» rather than failing to build")
    }
}
