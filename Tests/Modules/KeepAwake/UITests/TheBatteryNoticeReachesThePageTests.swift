import XCTest
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// «Stopped below 20 %» could not appear on the settings page. Ever.
///
/// The hero draws it, the view model publishes both values, and the page's call
/// to `KeepAwakeHero(…)` simply did not pass them — the initialiser defaults them
/// to `false` and `0`, so nothing was missing, nothing was red, and the branch
/// was unreachable. Pressing «15 min» at 5 % was silence on the one screen whose
/// whole job is to say what is happening.
///
/// **The guard that existed could not see it.** `BothNoticesShareOneSlotTests`
/// greps `KeepAwakeHero.swift` for the branch and the precedence, which were both
/// there and both correct — green over a cut wire. So this one renders the real
/// page, delivers the engine's own payload, and looks at the pixels: the whole
/// hop, from an event on the transport to ink on the screen.
@MainActor
final class TheBatteryNoticeReachesThePageTests: XCTestCase {

    private var probe: SettingsPageProbe!

    override func setUp() {
        super.setUp()
        probe = SettingsPageProbe()
    }

    override func tearDown() {
        probe?.unmount()
        probe = nil
        super.tearDown()
    }

    private func stopped(_ batteryStopped: Bool) -> KeepAwakeEngine.StatePayload {
        KeepAwakeEngine.StatePayload(isActive: false, conditions: [], clamshellActive: false,
                                     endDate: nil, startDate: nil, suppressed: false,
                                     batteryStopped: batteryStopped)
    }

    /// The whole hop: the engine says the guard stopped everything, and the page
    /// says so on screen.
    func testTheBatteryNoticeAppearsOnThePage() throws {
        let vm = probe.mount(height: 700)
        let quiet = try XCTUnwrap(probe.read(depth: 200), "nothing drew — no window server")

        XCTAssertTrue(probe.deliver(stopped(true)), "the engine's own payload did not encode")
        // The subject first: an absence proves nothing when the thing being
        // watched for never happened at all.
        XCTAssertTrue(vm.batteryStopped, "the payload never reached the view model")

        let notice = try XCTUnwrap(probe.read(depth: 200))
        XCTAssertGreaterThan(notice.warning, quiet.warning + 1000,
                             "the battery guard stopped everything and the top of the page "
                             + "carries \(notice.warning) warning-tinted pixels against "
                             + "\(quiet.warning) before it. «Stopped below 20 %» is a branch "
                             + "of the hero nothing can reach")
    }

    /// And it goes again, so the notice is the state rather than a smear: a page
    /// that only ever grew would leave the sentence up after the charger went in.
    func testAndItGoesWhenTheChargerGoesIn() throws {
        let vm = probe.mount(height: 700)
        XCTAssertTrue(probe.deliver(stopped(true)))
        let notice = try XCTUnwrap(probe.read(depth: 200), "nothing drew — no window server")
        XCTAssertTrue(vm.batteryStopped, "precondition: the guard was in force")
        XCTAssertGreaterThan(notice.warning, 1000, "precondition: the notice was on screen")

        XCTAssertTrue(probe.deliver(stopped(false)))
        let quiet = try XCTUnwrap(probe.read(depth: 200))
        XCTAssertLessThan(quiet.warning, notice.warning - 1000,
                          "the notice stayed on screen after the guard lifted: "
                          + "\(notice.warning) → \(quiet.warning) warning-tinted pixels")
    }

    /// The floor in the sentence is the one the page shows, not a zero. Read as
    /// two renders that differ only in the stored floor — the number is drawn, so
    /// two different numbers cannot come out as the same pixels.
    func testTheSentenceCarriesTheFloorTheRowShows() throws {
        probe.store.set(45, for: KeepAwakeSettings.Key.batteryGuardPercent)
        let vm = probe.mount(height: 700)
        XCTAssertTrue(probe.deliver(stopped(true)))
        let atFortyFive = try XCTUnwrap(probe.read(depth: 200), "nothing drew — no window server")
        XCTAssertTrue(vm.batteryStopped, "precondition: the guard was in force")

        let second = SettingsPageProbe()
        defer { second.unmount() }
        second.store.set(5, for: KeepAwakeSettings.Key.batteryGuardPercent)
        _ = second.mount(height: 700)
        XCTAssertTrue(second.deliver(stopped(true)))
        let atFive = try XCTUnwrap(second.read(depth: 200))

        XCTAssertNotEqual(atFortyFive.mass, atFive.mass,
                          "the notice reads the same at a floor of 45 % and one of 5 %, so the "
                          + "figure in it is not the floor this page was set to")
    }
}
