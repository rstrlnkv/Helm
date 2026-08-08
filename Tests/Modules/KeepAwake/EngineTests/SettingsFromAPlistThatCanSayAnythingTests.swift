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
    private var settings: KeepAwakeSettings!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        settings = KeepAwakeSettings(store: NamespacedStore(namespace: "keep-awake",
                                                            backing: backing))
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

    /// A string where an int lived, an int where a string lived, a list where a
    /// flag lived. This is what a hand-edited plist, a botched migration and a
    /// defaults-write with the wrong `-type` all produce, and every one of them
    /// has to answer the module's own default — never zero, never false, and
    /// never a crash from a forced cast.
    ///
    /// Each default is asserted to be something other than the type's zero, so
    /// "answered the default" cannot be confused with "answered nothing".
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

        for junk in [1, "yes", ["a", "b"]] as [Any] {
            plant("batteryGuardEnabled", junk)
            XCTAssertTrue(settings.batteryGuardEnabled,
                          "a stored \(junk) under a Bool key turned the battery guard off — "
                          + "the only thing that ends an unattended session")
        }

        plant("autoAppRules", 7)
        XCTAssertEqual(settings.appTriggers, [],
                       "a number under the rules key was read as rules")
    }

    /// The rules are JSON in one string, so the file can hold something that is
    /// not JSON. It must come back as no rules rather than as invented ones,
    /// and it must not take the process with it.
    ///
    /// (What it does *not* do is fall back to the older `autoApps` list, because
    /// the string is non-empty. That is a silent loss with no line in the log;
    /// it fails in the safe direction — the Mac sleeps — so it is recorded here
    /// rather than pinned.)
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
