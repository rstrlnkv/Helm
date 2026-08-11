import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// Turning system sleep off for the whole Mac is the one thing this module does
/// that outlives the process — a sudoers rule in `/etc/sudoers.d` and a `pmset`
/// setting that survives Helm quitting — and no window said it was in force.
///
/// `clamshellActive` was published by the engine from the first version, crossed
/// the wire in every state payload, and was read by exactly one thing: the panel
/// tile's subtitle, which only exists while a session is running. The settings
/// page that carries the switch drew the row nailed to `.spacer` — no mark, ever
/// — under a note about the administrator password.
///
/// Measured on the render, because what is being checked is that a person can see
/// it: the mark is `HelmSignal.success` and nothing else at the top of this page
/// is green (the palette swatches, which are, sit far below the band read here).
@MainActor
final class TheLidRowSaysSleepIsOffTests: XCTestCase {

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

    /// **A session is running in both readings.** The first version of this file
    /// sent `isActive: clamshellActive`, so the two renders differed in the hero
    /// as well — a 40 pt figure and a whole row of buttons — and «the words
    /// changed» passed with the lid row reverted to what it was. The engine only
    /// ever engages the lid inside a session, so holding `isActive` at true is
    /// both the honest state and the isolated one.
    private func lid(_ active: Bool) -> KeepAwakeEngine.StatePayload {
        KeepAwakeEngine.StatePayload(isActive: true,
                                     conditions: [ActiveCondition.manual.rawValue],
                                     clamshellActive: active, endDate: nil,
                                     startDate: nil, suppressed: false)
    }

    /// The band the automation card is in, in points. The palette swatches are
    /// the other green on this page and are much further down.
    private static let cardDepth = 560

    func testTheMarkArrivesWhenSleepGoesOff() throws {
        try XCTSkipUnless(MacHardware.hasLid, "this Mac has no lid, so it draws no lid row")
        let vm = probe.mount()
        let before = try XCTUnwrap(probe.read(depth: Self.cardDepth),
                                   "nothing drew — no window server")
        XCTAssertEqual(before.success, 0, "something at the top of this page is already green, "
                       + "so the count below is not the lid's mark")

        XCTAssertTrue(probe.deliver(lid(true)), "the engine's own payload did not encode")
        // The subject first, or an assertion about what is drawn is an assertion
        // about a payload that never arrived.
        XCTAssertTrue(vm.clamshellActive, "the payload never reached the view model")

        let marked = try XCTUnwrap(probe.read(depth: Self.cardDepth))
        XCTAssertGreaterThan(marked.success, 100,
                             "sleep is off for the whole Mac and the row that switched it off "
                             + "carries no mark. Nothing in any window says the setting is in "
                             + "force")
    }

    /// And it goes when the lid opens, so the mark is the state of the machine
    /// rather than a memory of it.
    func testTheMarkGoesWhenSleepComesBack() throws {
        try XCTSkipUnless(MacHardware.hasLid, "this Mac has no lid, so it draws no lid row")
        let vm = probe.mount()
        XCTAssertTrue(probe.deliver(lid(true)))
        let marked = try XCTUnwrap(probe.read(depth: Self.cardDepth),
                                   "nothing drew — no window server")
        XCTAssertGreaterThan(marked.success, 100, "precondition: the mark was drawn at all")

        XCTAssertTrue(probe.deliver(lid(false)))
        XCTAssertFalse(vm.clamshellActive, "the payload never reached the view model")
        let plain = try XCTUnwrap(probe.read(depth: Self.cardDepth))
        XCTAssertEqual(plain.success, 0,
                       "the tick stayed on the lid row after sleep came back")
    }

    /// The words as well as the mark: «Sleep is off right now» replaces the note
    /// about the password, and a mark with no sentence beside it is a green dot
    /// nobody can read.
    func testTheRowSaysItInWords() throws {
        try XCTSkipUnless(MacHardware.hasLid, "this Mac has no lid, so it draws no lid row")
        _ = probe.mount()
        XCTAssertTrue(probe.deliver(lid(false)))
        let quiet = try XCTUnwrap(probe.read(), "nothing drew — no window server")

        XCTAssertTrue(probe.deliver(lid(true)))
        let marked = try XCTUnwrap(probe.read())
        XCTAssertNotEqual(marked.mass, quiet.mass,
                          "the row draws exactly the same words with sleep off as with sleep "
                          + "on, so nothing but the mark changed")
    }

    /// **One declaration of «which rows can carry a mark».** The set used to be
    /// built twice in the page — once as the seed and once live — and the seed was
    /// the copy that never learned about the hardware. Both go through
    /// `MarkableRules` now, which is where the rule has a test.
    func testThePageAsksTheOneFunctionForTheColumn() throws {
        let source = try RepoSource.text(of:
            "Sources/Modules/KeepAwake/UI/KeepAwakeSettingsPage.swift")
        XCTAssertGreaterThan(source.count, 5000, "the page was not read at all")
        XCTAssertEqual(source.components(separatedBy: "MarkableRules.onThisMac(").count - 1, 2,
                       "the seed and the live reader are not both asking `MarkableRules` — a "
                       + "second copy of the rule is a copy that will not learn the next thing "
                       + "this one learns")
        XCTAssertFalse(source.contains("enabled.insert("),
                       "the page builds the marked-rules set inline again")
    }
}
