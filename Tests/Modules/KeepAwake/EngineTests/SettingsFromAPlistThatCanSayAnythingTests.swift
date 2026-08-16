import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The module's settings read from a file any process can rewrite.
///
/// `SettingsKeysAreSpelledOnceTests` proves each key is written and read under
/// its own name, and that a jiggle interval below a minute is clamped. The
/// reason that clamp exists is stated in the source — "the stepper cannot offer
/// less than a minute, and a plist can say anything" — and it is the whole of
/// this file's premise: `~/Library/Preferences` is not a trusted input, a
/// stepper's range is not a guarantee about what is on disk, and a value that
/// arrives from there is arithmetic the module is about to do.
///
/// The module whose worst failure is a Mac that will not sleep is where that
/// matters most.
final class SettingsFromAPlistThatCanSayAnythingTests: XCTestCase {

    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        settings = KeepAwakeSettings(store: store)
    }

    private func plant(_ key: String, _ value: Any) {
        backing.raw["module.keep-awake." + key] = value
    }

    // MARK: - Numbers that are about to be multiplied

    /// The jiggle interval was clamped from below and not from above, and its
    /// only reader multiplies it:
    ///
    ///     let interval = TimeInterval(settings.jiggleIntervalMinutes * 60)
    ///     // KeepAwakeEngine.scheduleJiggle
    ///
    /// `Int` multiplication traps on overflow in Swift, in release builds as
    /// well as debug, so any stored value above `Int.max / 60` is not a long
    /// interval — it is the app terminating the moment a session with jiggle on
    /// starts. `<integer>9223372036854775807</integer>` is a legal plist and
    /// `UserDefaults` hands it straight back (measured).
    ///
    /// Asserted as the property the multiply needs rather than as a particular
    /// clamped value, so a fix may choose any ceiling it likes.
    func testAStoredJiggleIntervalCannotOverflowTheTimerItFeeds() {
        for stored in [Int.max, Int.max / 59, Int.max / 60 + 1] {
            plant("jiggleIntervalMinutes", stored)
            XCTAssertLessThanOrEqual(settings.jiggleIntervalMinutes, Int.max / 60,
                                     "a stored \(stored) came back as "
                                     + "\(settings.jiggleIntervalMinutes); multiplying it by "
                                     + "60 traps, which is a crash and not a long interval")
        }
    }

    /// The same shape one setting over.
    /// `defaultDurationMinutes` had no clamp at all, and `startSession` does
    /// `TimeInterval(minutes * 60)` twice on it — reached from `toggleSession`,
    /// which is the panel tile's main button.
    ///
    /// The picker offers a fixed list of durations, so nothing a person can do
    /// produces this; a hand-edited or migrated plist can, and the picker's
    /// range is not a fact about the file.
    func testAStoredDefaultDurationCannotOverflowTheSessionItStarts() {
        plant("defaultDurationMinutes", Int.max)
        XCTAssertLessThanOrEqual(settings.defaultDurationMinutes, Int.max / 60,
                                 "the duration the main button starts a session with "
                                 + "overflows the multiply that turns it into seconds")
    }

    /// The weakest of the three: the battery floor was unclamped in both
    /// directions. The stepper offers 5…50; a stored 0 or
    /// a negative leaves `percent <= threshold` unable to fire, which switches
    /// off the only thing that ever ends an unattended session — while the
    /// screen still draws the guard as on. A stored 101 ends every session on
    /// battery immediately, which reads as the feature being broken.
    ///
    /// Hardening rather than a crash. It is here because its sibling one field
    /// up *is* clamped, for a reason that applies word for word to this one.
    func testAStoredBatteryFloorStaysInsideWhatTheStepperCanOffer() {
        for stored in [0, -1, 101, Int.max] {
            plant("batteryGuardPercent", stored)
            XCTAssertTrue((1...100).contains(settings.batteryGuardPercent),
                          "a stored \(stored) came back as \(settings.batteryGuardPercent)")
        }
    }

    /// What must keep working once the ceilings go in: the ordinary values the
    /// two steppers can actually produce come back untouched. A clamp that ate
    /// a real answer would be the same defect wearing the other sign.
    func testTheValuesTheStepperCanProduceComeBackUnchanged() {
        for minutes in [1, 5, 30, 60] {
            plant("jiggleIntervalMinutes", minutes)
            XCTAssertEqual(settings.jiggleIntervalMinutes, minutes)
        }
        for percent in [5, 20, 50] {
            plant("batteryGuardPercent", percent)
            XCTAssertEqual(settings.batteryGuardPercent, percent)
        }
        for minutes in [0, 15, 60, 480] {
            plant("defaultDurationMinutes", minutes)
            XCTAssertEqual(settings.defaultDurationMinutes, minutes)
        }
    }

    // MARK: - The wrong type under a known key

    /// A string where an int lived, a list where a flag lived. This is what a
    /// hand-edited plist, a botched migration and a defaults-write with the
    /// wrong `-type` all produce, and every one of them has to answer the
    /// module's own default — never zero, never false, and never a crash from a
    /// forced cast.
    ///
    /// Each default is asserted to be something other than the type's zero, so
    /// "answered the default" cannot be confused with "answered nothing".
    ///
    /// **A number is not the wrong type for a flag**, which is why `1` is not in
    /// the list below and has a test of its own. A plist holds no booleans of
    /// its own kind: `<true/>` and `<integer>1</integer>` arrive as the same
    /// `NSNumber`, and the cast reads its value.
    func testAValueOfTheWrongTypeUnderAKnownKeyAnswersTheModulesDefault() {
        XCTAssertEqual(settings.jiggleIntervalMinutes, 5, "the default moved; re-read this test")
        XCTAssertEqual(settings.batteryGuardPercent, 20)
        XCTAssertTrue(settings.batteryGuardEnabled)

        for junk in ["12", "", "true"] as [Any] {
            plant("jiggleIntervalMinutes", junk)
            plant("batteryGuardPercent", junk)
            XCTAssertEqual(settings.jiggleIntervalMinutes, 5,
                           "a stored \(junk) under an Int key answered "
                           + "\(settings.jiggleIntervalMinutes)")
            XCTAssertEqual(settings.batteryGuardPercent, 20,
                           "a stored \(junk) under an Int key answered "
                           + "\(settings.batteryGuardPercent)")
        }

        for junk in ["yes", ["a", "b"]] as [Any] {
            plant("batteryGuardEnabled", junk)
            XCTAssertTrue(settings.batteryGuardEnabled,
                          "a stored \(junk) under a Bool key turned the battery guard off — "
                          + "the only thing that ends an unattended session")
        }

        plant("autoAppRules", 7)
        XCTAssertEqual(settings.appTriggers, [],
                       "a number under the rules key was read as rules")
    }

    /// The one wrong type that is not one. `defaults write … -int 0` under a
    /// flag switches the flag off, because that is what the file says and what
    /// `UserDefaults` answers — the number is not junk to fall back from.
    ///
    /// Stated because the guard is the only thing that ever ends an unattended
    /// session, so "somebody's plist can switch it off with a 0" is a fact about
    /// this module worth having written down. Both values are asserted, so
    /// "answered the number" cannot be confused with "answered the default".
    func testANumberUnderTheBatteryFlagIsTheFlag() {
        plant("batteryGuardEnabled", 0)
        XCTAssertFalse(settings.batteryGuardEnabled)

        plant("batteryGuardEnabled", 1)
        XCTAssertTrue(settings.batteryGuardEnabled)
    }

    /// The rules are JSON in one string, so the file can hold something that is
    /// not JSON. It must come back as no rules rather than as invented ones,
    /// and it must not take the process with it.
    ///
    /// (What it does *not* do is fall back to the older `autoApps` list, because
    /// the string is non-empty. That is a loss, and it fails in the safe
    /// direction — the Mac sleeps — so the module goes on working while the apps
    /// somebody chose stop holding it awake. The line that says so is
    /// `testARulesStringThatCouldNotBeReadIsSaidSoInTheLog` below.)
    func testARulesStringThatIsNotJSONIsNoRulesRatherThanInventedOnes() {
        plant("autoApps", ["com.apple.Safari"])
        XCTAssertEqual(settings.appTriggers, [AppTrigger(bundleID: "com.apple.Safari")],
                       "the older list does not migrate at all, so the fallback below is "
                       + "not what this test is about")

        for junk in ["{", "not json", "[{\"bundleID\":}]", "null", "[]"] {
            plant("autoAppRules", junk)
            XCTAssertEqual(settings.appTriggers, [],
                           "\"\(junk)\" was read as \(settings.appTriggers)")
        }
    }

    /// A rules string that *is* JSON and is the wrong shape — a list of plain
    /// strings, which is exactly what the older `autoApps` key holds — must not
    /// become rules by accident. It is refused, and the module holds no apps
    /// rather than apps with invented conditions on them.
    func testARulesStringOfTheOlderShapeIsNotMistakenForRules() {
        plant("autoAppRules", "[\"com.apple.Safari\",\"com.apple.Music\"]")
        XCTAssertEqual(settings.appTriggers, [])
    }

    // MARK: - The one loss that is allowed to be quiet, but not silent

    /// **A rules string nothing can read costs somebody their apps, and the
    /// module goes on looking well.** Nothing is refused and nothing crashes:
    /// the list is simply empty, the conditions never hold, and the Mac sleeps
    /// through the render it was meant to sit out. The safe direction is the
    /// right one to fail in; saying nothing at all is not part of it.
    ///
    /// Written at `activate`, once, and not in `appTriggers` — that getter is
    /// read from `recompute`, which runs from three observers, and this module's
    /// own rule is that it logs on a transition and never on the recompute.
    ///
    /// The control is the second half: a string that *is* readable, including
    /// the empty list, must produce no line at all — otherwise the warning is
    /// wallpaper and says nothing about anybody's file.
    func testARulesStringThatCouldNotBeReadIsSaidSoInTheLog() {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }

        // The readable pair is spelled by the encoder rather than by hand: every
        // field of a rule is required, so a plausible-looking `{"bundleID": …}`
        // is one of the unreadable strings and would make the control vacuous.
        let real = AppTriggerRules.encode([AppTrigger(bundleID: "com.apple.Safari")])
        for (stored, expected) in [("not json", true), ("[{\"bundleID\":}]", true),
                                   ("[{\"bundleID\":\"com.apple.Safari\"}]", true),
                                   ("[]", false), (real, false)] {
            HelmLog.shared.clearTail()
            plant("autoAppRules", stored)

            engine().activate()

            let said = HelmLog.shared.recentEntries()
                .filter { $0.category == KeepAwakeEngine.moduleID }
                .contains { $0.message.contains("app rules") }
            XCTAssertEqual(said, expected,
                           "\"\(stored)\": the log says \(said) about rules it could not read")
        }
    }

    /// The engine over this test's own store, with every port faked.
    private func engine() -> KeepAwakeEngine {
        KeepAwakeEngine(settings: settings, store: store,
                        assertions: FakeAssertions(),
                        displayInfo: FakeDisplayInfo(),
                        displayObserver: FakeDisplayObserver(),
                        power: FakePower(), apps: FakeApps(),
                        pointer: FakePointer(), clamshell: FakeClamshell(), clock: FakeClock())
    }

    // MARK: - Reading never writes

    /// None of the above may leave anything behind under a key that was not
    /// already there. A default that persists itself stops being a default, and
    /// a clamp that writes its clamped value back rewrites somebody's file
    /// because they opened a page.
    func testReadingAValueThePlistGotWrongDoesNotRewriteThePlist() {
        plant("jiggleIntervalMinutes", -3)
        plant("batteryGuardPercent", "nonsense")
        let before = backing.raw.keys.sorted()

        _ = settings.jiggleIntervalMinutes
        _ = settings.batteryGuardPercent
        _ = settings.defaultDurationMinutes
        _ = settings.appTriggers
        _ = settings.batteryGuardEnabled

        XCTAssertEqual(backing.raw.keys.sorted(), before,
                       "reading wrote \(Set(backing.raw.keys).subtracting(before).sorted())")
        XCTAssertEqual(backing.raw["module.keep-awake.jiggleIntervalMinutes"] as? Int, -3,
                       "the clamp wrote its answer back over what the person's file said")
    }
}
