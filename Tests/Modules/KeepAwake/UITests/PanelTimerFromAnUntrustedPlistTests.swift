import SwiftUI
import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// The one duration of this module that is not `KeepAwakeSettings`'s.
///
/// `panelTimerMinutes` is the tile's own memory of what was last picked in the
/// panel, and it stays out of the settings type because the engine never reads
/// it — the same reason `MenuBarLook` keeps the keys the menu bar draws. That
/// exemption is about *who reads it*, and it was taken as an exemption from the
/// rest: the number still leaves the tile through the model's
/// `start(minutes:)` and still lands in `startSession`, which does `TimeInterval(minutes * 60)` twice.
///
/// `SettingsFromAPlistThatCanSayAnythingTests` states the premise for the two
/// durations that do live in the settings type. This is the third one, read one
/// target away, with the same file behind it: `~/Library/Preferences` is not a
/// trusted input, and a range the UI enforces is not a fact about what is on
/// disk.
@MainActor
final class PanelTimerFromAnUntrustedPlistTests: XCTestCase {

    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!

    override func setUp() async throws {
        try await super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: KeepAwakeDescriptor.id.rawValue, backing: backing)
        settings = KeepAwakeSettings(store: store)
    }

    private func plant(_ key: String, _ value: Any) {
        backing.raw["module.keep-awake." + key] = value
    }

    private var opening: Int { KeepAwakePanelTile.openingMinutes(store) }

    /// The tile hands this number straight to `vm.start(minutes:)`. `startSession`
    /// clamps what it is given, so a stored `Int.max` does not trap there; this
    /// pins that the tile's own reading is already inside what `minutes * 60` can
    /// hold. `<integer>9223372036854775807</integer>` is a legal plist and
    /// `UserDefaults` hands it straight back.
    ///
    /// Asserted as the property the multiply needs rather than as a particular
    /// clamped value, the way its two siblings in the engine are.
    func testAStoredPanelDurationCannotOverflowTheSessionItStarts() {
        for stored in [Int.max, Int.max / 59, Int.max / 60 + 1] {
            plant(KeepAwakePanelTile.panelTimerMinutes, stored)
            XCTAssertLessThanOrEqual(opening, Int.max / 60,
                                     "a stored \(stored) came back as \(opening); the tile "
                                     + "sends it to startSession, where multiplying it by 60 "
                                     + "traps — a crash, not a long timer")
        }
    }

    /// The ceiling is the one the typed entry enforces, shared with the page:
    /// nothing a person can do here produces more than a day.
    func testAStoredPanelDurationIsHeldToWhatTheTileItselfCanProduce() {
        plant(KeepAwakePanelTile.panelTimerMinutes, Int.max)
        XCTAssertEqual(opening, TimerPolicy.longestSessionMinutes, "Int.max reads as the day")
        plant(KeepAwakePanelTile.panelTimerMinutes, 100_000)
        XCTAssertEqual(opening, TimerPolicy.longestSessionMinutes,
                       "the entry clamps to 1…\(TimerPolicy.longestSessionMinutes), so \(opening) "
                       + "cannot have been typed here")
    }

    /// Both surfaces build their editor through `KeepAwakeCustomDuration`, so its
    /// ceiling is the one a person can type; it must be what `startSession` accepts.
    func testTheTypedEntryCeilingIsTheLongestSession() {
        XCTAssertEqual(KeepAwakeCustomDuration.ceiling, TimerPolicy.longestSessionMinutes)
        XCTAssertEqual(KeepAwakeCustomDuration.ceiling, 1440)
        // The value that reaches the control, not only the constant.
        var minutes = 5
        let view = KeepAwakeCustomDuration(minutes: Binding(get: { minutes }, set: { minutes = $0 }),
                                           verb: "x", apply: {})
        let given = Mirror(reflecting: view.prompt).children.first { $0.label == "ceiling" }?.value as? Int
        XCTAssertEqual(given, TimerPolicy.longestSessionMinutes)
    }

    /// The ceiling constant alone does not say the surfaces use it: each one's
    /// own editor must carry the ceiling a person can type, so a call site that
    /// goes back to its own prompt goes red here.
    func testTheTileAndThePageBuildTheirEditorsWithTheLongestSession() {
        let ports = Inert()
        let engine = KeepAwakeEngine(settings: settings, store: store, assertions: ports,
                                     displayInfo: ports, displayObserver: ports,
                                     power: ports, apps: ports, pointer: ports,
                                     clamshell: ports, clock: ports, lidInfo: ports)
        let model = KeepAwakeViewModel(engine: engine)
        defer { model.stop() }
        let tile = KeepAwakePanelTile(vm: model, store: store)
        let hero = KeepAwakeHero(state: .idle, now: Date(), anyRuleOn: false,
                                 defaultDurationMinutes: 30, notice: .none,
                                 ruleHolds: false, timerEndsAutomation: false,
                                 batteryFloor: 20,
                                 timedNote: { _ in "" }, start: { _ in }, stop: {}, resume: {})
        for editor in [tile.customTimeEditor, hero.customTimeEditor] {
            let given = Mirror(reflecting: editor.prompt).children.first { $0.label == "ceiling" }?.value as? Int
            XCTAssertEqual(given, TimerPolicy.longestSessionMinutes)
        }
    }

    /// What must keep working once the ceiling goes in: every duration the tile
    /// can actually store comes back untouched — the menu's longest, the typed
    /// entry's highest (a day), and the shortest.
    func testTheDurationsTheTileCanStoreComeBackUnchanged() {
        for minutes in [1, 15, 30, 240, 720, 721, 1000, 1440] {
            plant(KeepAwakePanelTile.panelTimerMinutes, minutes)
            XCTAssertEqual(opening, minutes)
        }
    }

    /// Nothing stored, or something stored that is not a duration: the module's
    /// default answers, and then the tile's own 30. Asserted so "clamped" cannot
    /// quietly become "always the floor".
    func testWithNothingUsableStoredTheModulesDefaultAnswersAndThen30() {
        XCTAssertEqual(opening, 30, "no panel choice and an indefinite default")

        settings.setDefaultDurationMinutes(45)
        XCTAssertEqual(opening, 45)

        for junk in [0, -1, "20"] as [Any] {
            plant(KeepAwakePanelTile.panelTimerMinutes, junk)
            XCTAssertEqual(opening, 45, "a stored \(junk) was read as a duration")
        }
    }

    /// Reading a value the file got wrong must not rewrite the file: a clamp
    /// that saves its answer back has edited somebody's preferences because a
    /// panel was opened.
    func testReadingAPanelDurationThePlistGotWrongDoesNotRewriteThePlist() {
        plant(KeepAwakePanelTile.panelTimerMinutes, Int.max)
        let before = backing.raw.keys.sorted()

        _ = opening

        XCTAssertEqual(backing.raw.keys.sorted(), before,
                       "reading wrote \(Set(backing.raw.keys).subtracting(before).sorted())")
        XCTAssertEqual(backing.raw["module.keep-awake.panelTimerMinutes"] as? Int, Int.max,
                       "the clamp wrote its answer back over what the person's file said")
    }
}
