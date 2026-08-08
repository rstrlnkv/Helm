import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The names the module's settings have on somebody's disk.
///
/// Seven of these keys, and every one of their defaults, used to be written out
/// again in `KeepAwakeSettingsPage` and once more in `KeepAwakePanelTile` — three
/// copies of each, in three targets, where a drift would show the page one thing
/// and let the Mac do another with nothing in the build to say so. `Key` is the
/// only spelling now, and that moves the risk rather than removing it: a rename
/// there is silent. It reads a key nobody's Mac has ever had, the setting comes
/// back to its default, and the person's answer sits on disk under the old name.
///
/// So the literals live here, once, and the two directions are separate: what a
/// setter puts on disk under that exact name, and what the getter finds there.
/// Both, because a setter and a getter that agree on the *wrong* name are
/// perfectly consistent and lose every existing answer.
final class SettingsKeysAreSpelledOnceTests: XCTestCase {
    private var backing: InMemoryKeyValueStore!
    private var settings: KeepAwakeSettings!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        settings = KeepAwakeSettings(store: NamespacedStore(namespace: "keep-awake",
                                                            backing: backing))
    }

    /// `NamespacedStore` prefixes what it is given; this is the whole string a
    /// plist carries.
    private func onDisk(_ key: String) -> Any? { backing.raw["module.keep-awake." + key] }

    func test_each_switch_is_written_and_read_under_its_own_name() {
        let switches: [(key: String, set: (Bool) -> Void, get: () -> Bool)] = [
            ("autoExternalDisplay",
             { self.settings.setAutoExternalDisplay($0) }, { self.settings.autoExternalDisplay }),
            ("autoPower", { self.settings.setAutoPower($0) }, { self.settings.autoPower }),
            ("keepDisplayOn",
             { self.settings.setKeepDisplayOn($0) }, { self.settings.keepDisplayOn }),
            ("jiggleEnabled",
             { self.settings.setJiggleEnabled($0) }, { self.settings.jiggleEnabled }),
            ("clamshellEnabled",
             { self.settings.setClamshellEnabled($0) }, { self.settings.clamshellEnabled }),
            ("batteryGuardEnabled",
             { self.settings.setBatteryGuardEnabled($0) }, { self.settings.batteryGuardEnabled }),
        ]
        for row in switches {
            for value in [true, false] {
                row.set(value)
                XCTAssertEqual(onDisk(row.key) as? Bool, value,
                               "nothing landed under \"\(row.key)\" — the setter spells it "
                               + "something else, and every stored answer is orphaned")
                XCTAssertEqual(row.get(), value,
                               "\"\(row.key)\" is not read back from where it was written")
            }
        }
    }

    func test_each_number_is_written_and_read_under_its_own_name() {
        let numbers: [(key: String, set: (Int) -> Void, get: () -> Int)] = [
            ("jiggleIntervalMinutes",
             { self.settings.setJiggleIntervalMinutes($0) },
             { self.settings.jiggleIntervalMinutes }),
            ("defaultDurationMinutes",
             { self.settings.setDefaultDurationMinutes($0) },
             { self.settings.defaultDurationMinutes }),
            ("batteryGuardPercent",
             { self.settings.setBatteryGuardPercent($0) },
             { self.settings.batteryGuardPercent }),
        ]
        for row in numbers {
            row.set(37)
            XCTAssertEqual(onDisk(row.key) as? Int, 37,
                           "nothing landed under \"\(row.key)\"")
            XCTAssertEqual(row.get(), 37,
                           "\"\(row.key)\" is not read back from where it was written")
        }
    }

    /// The rules are one string under one key, and the older list under another.
    /// Both names have shipped, so both are pinned: the migration is the only
    /// thing standing between an upgrade and an empty list.
    func test_the_app_rules_keep_their_two_names() {
        settings.setAppTriggers([AppTrigger(bundleID: "com.apple.Music", needsPower: true)])
        let stored = try? XCTUnwrap(onDisk("autoAppRules") as? String)
        XCTAssertEqual(settings.appTriggers,
                       [AppTrigger(bundleID: "com.apple.Music", needsPower: true)])
        XCTAssertEqual(AppTriggerRules.decode(stored ?? ""),
                       [AppTrigger(bundleID: "com.apple.Music", needsPower: true)],
                       "the rules did not land under \"autoAppRules\" as JSON")

        let older = InMemoryKeyValueStore()
        older.raw["module.keep-awake.autoApps"] = ["com.apple.Safari"]
        let upgraded = KeepAwakeSettings(store: NamespacedStore(namespace: "keep-awake",
                                                                backing: older))
        XCTAssertEqual(upgraded.appTriggers, [AppTrigger(bundleID: "com.apple.Safari")],
                       "\"autoApps\" no longer migrates — an upgrade loses the person's apps")
    }

    /// Reading a setting nobody has set answers the default and writes nothing.
    /// A default that persists itself stops being a default: changing it later
    /// would reach every install that had merely *opened* the page.
    func test_the_defaults_are_answered_without_touching_the_store() {
        XCTAssertFalse(settings.autoExternalDisplay)
        XCTAssertFalse(settings.autoPower)
        XCTAssertFalse(settings.keepDisplayOn)
        XCTAssertFalse(settings.jiggleEnabled)
        XCTAssertFalse(settings.clamshellEnabled)
        XCTAssertTrue(settings.batteryGuardEnabled)
        XCTAssertEqual(settings.batteryGuardPercent, 20)
        XCTAssertEqual(settings.jiggleIntervalMinutes, 5)
        XCTAssertEqual(settings.defaultDurationMinutes, 0)
        XCTAssertEqual(settings.appTriggers, [])
        XCTAssertTrue(backing.raw.isEmpty,
                      "reading the defaults wrote \(backing.raw.keys.sorted())")
    }

    /// The jiggle timer is a `while` interval: a stored 0 is a loop that fires as
    /// fast as it can wake up. The clamp is the module's, not the stepper's —
    /// the page's own copy of it was the seventh duplicate.
    func test_a_jiggle_interval_below_a_minute_is_read_as_a_minute() {
        for stored in [0, -3] {
            backing.raw["module.keep-awake.jiggleIntervalMinutes"] = stored
            XCTAssertEqual(settings.jiggleIntervalMinutes, 1,
                           "a stored \(stored) came back unclamped")
        }
        backing.raw["module.keep-awake.jiggleIntervalMinutes"] = 7
        XCTAssertEqual(settings.jiggleIntervalMinutes, 7, "the clamp ate a real answer")
    }
}
