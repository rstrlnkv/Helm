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
/// rest: the number still leaves the tile in a `KeepAwakeStart` payload and
/// still lands in `startSession`, which does `TimeInterval(minutes * 60)` twice.
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

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: KeepAwakeDescriptor.id.rawValue, backing: backing)
        settings = KeepAwakeSettings(store: store)
    }

    private func plant(_ key: String, _ value: Any) {
        backing.raw["module.keep-awake." + key] = value
    }

    private var opening: Int { KeepAwakePanelTile.openingMinutes(store) }

    /// The tile hands this number straight to `startPayload`, so a stored
    /// `Int.max` is not a very long timer — it is the app terminating the moment
    /// the panel is opened and Start is pressed. `<integer>9223372036854775807</integer>`
    /// is a legal plist and `UserDefaults` hands it straight back.
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

    /// The ceiling is the one this tile's own typed entry enforces, not the
    /// settings type's day: nothing a person can do here produces more than 720.
    func testAStoredPanelDurationIsHeldToWhatTheTileItselfCanProduce() {
        plant(KeepAwakePanelTile.panelTimerMinutes, 100_000)
        XCTAssertLessThanOrEqual(opening, 720,
                                 "the panel's own entry clamps to 1…720, so \(opening) "
                                 + "cannot have been typed here")
    }

    /// What must keep working once the ceiling goes in: every duration the tile
    /// can actually store comes back untouched — the menu's longest, the typed
    /// entry's highest, and the shortest.
    func testTheDurationsTheTileCanStoreComeBackUnchanged() {
        for minutes in [1, 15, 30, 240, 720] {
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
