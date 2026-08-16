import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// Nothing bounded the rules value, and it is read on every recompute.
///
/// The rules live in one string in `~/Library/Preferences`, which any process
/// running as this user can write, and `recompute()` runs from three observers —
/// a display moving, the charger, an app launching or quitting. Measured on the
/// value a plist can hold: a **4.7 MB** rules string decodes to **50 001** rules
/// and costs about **57 ms every time**, and a single bundle id can be a million
/// characters long. That is not a crash; it is a Mac that pauses for a twentieth
/// of a second every time anything launches, for as long as the file says so.
///
/// A person cannot reach these numbers. The picker adds one app at a time from a
/// file dialog, and the ids are bundle identifiers — 256 characters is already
/// far past `com.microsoft.VSCode`.
///
/// So `readable` refuses instead, and refusing routes into the same honest place
/// a wrong plist type does: `KeepAwakeSettings.AppRulesReading.unreadable`, which
/// is no rules and the banner that says so. Silently truncating to the first 200
/// would be the one outcome nobody could see — a Mac held awake by rules the page
/// does not draw, or rules the page draws that hold nothing.
final class AFileWithMoreRulesThanAnybodyChoseTests: XCTestCase {

    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        settings = KeepAwakeSettings(store: store)
    }

    private func rules(_ count: Int, idLength: Int = 24) -> String {
        AppTriggerRules.encode((0..<count).map { index in
            let head = "com.example.\(index)."
            return AppTrigger(bundleID: head + String(repeating: "a",
                                                      count: max(0, idLength - head.count)))
        })
    }

    // MARK: - How many rules

    func testTwoHundredRulesAreRead() {
        let decoded = AppTriggerRules.readable(rules(200))

        XCTAssertEqual(decoded?.count, 200, "the ceiling is 200 and 200 is under it")
    }

    func testTwoHundredAndOneAreNot() {
        XCTAssertNil(AppTriggerRules.readable(rules(201)),
                     "nothing bounded this, and the value is decoded on every display, charger "
                     + "and application event")
    }

    /// The last rule of a file at the ceiling still holds the Mac, so the cap is
    /// a refusal and never a truncation. «The first N are read» is the shape of
    /// defect that hides in a list nobody makes by hand.
    func testTheLastRuleOfAFileAtTheCeilingStillHoldsTheMac() {
        var list = (0..<199).map { AppTrigger(bundleID: "com.example.filler\($0)") }
        list.append(AppTrigger(bundleID: "com.example.render"))
        backing.raw["module.keep-awake.autoAppRules"] = AppTriggerRules.encode(list)

        XCTAssertEqual(settings.appTriggers.count, 200)
        XCTAssertFalse(settings.appRulesUnreadable)
        XCTAssertTrue(AppTriggerRules.isHolding(settings.appTriggers,
                                                running: ["com.example.render"],
                                                externalDisplay: false, onPower: false))
    }

    // MARK: - How long an id

    func testABundleIdOfTwoHundredAndFiftySixCharactersIsRead() {
        let id = String(repeating: "a", count: 256)
        let decoded = AppTriggerRules.readable(AppTriggerRules.encode([AppTrigger(bundleID: id)]))

        XCTAssertEqual(decoded?.map(\.bundleID), [id])
    }

    func testTwoHundredAndFiftySevenAreNot() {
        let id = String(repeating: "a", count: 257)

        XCTAssertNil(AppTriggerRules.readable(AppTriggerRules.encode([AppTrigger(bundleID: id)])))
    }

    /// One absurd id among ordinary ones takes the whole value with it, rather
    /// than being dropped quietly: a row the page cannot draw and the engine
    /// cannot match is not something to keep half of.
    func testOneMillionCharacterIdRefusesTheWholeValue() {
        let list = [AppTrigger(bundleID: "com.example.render"),
                    AppTrigger(bundleID: String(repeating: "a", count: 1_000_000))]

        XCTAssertNil(AppTriggerRules.readable(AppTriggerRules.encode(list)))
    }

    /// The worst *legitimate* file — the ceiling on both counts at once — still
    /// reads. This is what keeps the byte ceiling in front of the decode from
    /// being tighter than the two ceilings above it.
    func testTwoHundredRulesWithTheLongestIdsStillRead() {
        XCTAssertEqual(AppTriggerRules.readable(rules(200, idLength: 256))?.count, 200)
    }

    // MARK: - How big the value may be at all

    /// Two ordinary rules in a JSON document padded to a quarter of a megabyte.
    /// It decodes perfectly well and it is not something this app ever wrote —
    /// and it is the case the byte ceiling exists for, since neither of the two
    /// ceilings above it can see the size of the *value*. Without a check in
    /// front of the decode, every recompute pays for parsing all of it.
    func testAValidButEnormousValueIsRefusedBeforeItIsParsed() {
        let padded = paddedRules(toBytes: AppTriggerRules.maxEncodedBytes + 1)

        XCTAssertGreaterThan(padded.utf8.count, AppTriggerRules.maxEncodedBytes,
                             "precondition: the fixture really is over the ceiling")
        XCTAssertNotNil(try? JSONDecoder().decode([AppTrigger].self,
                                                  from: Data(padded.utf8)),
                        "precondition: and it is otherwise perfectly readable, so the refusal "
                        + "below can only be the size")
        XCTAssertNil(AppTriggerRules.readable(padded))
    }

    /// The same document just under the ceiling reads, so the ceiling is a
    /// boundary and not a ban on whitespace.
    func testTheSameValueJustUnderTheCeilingReads() {
        let padded = paddedRules(toBytes: AppTriggerRules.maxEncodedBytes)

        XCTAssertEqual(AppTriggerRules.readable(padded)?.count, 2)
    }

    /// Two rules, then as many spaces as it takes. JSON allows whitespace
    /// between tokens, so this is a legal document of any size.
    private func paddedRules(toBytes bytes: Int) -> String {
        let body = AppTriggerRules.encode([AppTrigger(bundleID: "com.example.render"),
                                           AppTrigger(bundleID: "com.example.encode")])
        let padding = bytes - body.utf8.count
        return String(body.dropLast()) + String(repeating: " ", count: max(0, padding)) + "]"
    }

    // MARK: - What the module does with such a file

    func testThePlistBombEndsInTheBannerAndNoRules() {
        backing.raw["module.keep-awake.autoAppRules"] = rules(50_001)

        XCTAssertTrue(settings.appRulesUnreadable,
                      "50 001 rules is a file nobody wrote by choosing apps")
        XCTAssertTrue(settings.appTriggers.isEmpty,
                      "and no rule from it holds the Mac awake")
    }

    /// The engine over the same store answers the same way, and says so once.
    func testTheEngineHoldsNothingForSuchAFileAndSaysSo() {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }
        HelmLog.shared.clearTail()
        backing.raw["module.keep-awake.autoAppRules"] = rules(50_001)
        let apps = FakeApps()
        apps.ids = ["com.example.0.aaaaaaaaaaaa"]
        let engine = KeepAwakeEngine(settings: settings, store: store,
                                     assertions: FakeAssertions(),
                                     displayInfo: FakeDisplayInfo(),
                                     displayObserver: FakeDisplayObserver(),
                                     power: FakePower(), apps: apps, pointer: FakePointer(),
                                     clamshell: FakeClamshell(), clock: FakeClock())

        engine.activate()

        XCTAssertFalse(engine.isActive)
        XCTAssertTrue(HelmLog.shared.recentEntries().contains {
            $0.category == KeepAwakeEngine.moduleID && $0.message.contains("could not be read")
        }, "a refusal nobody is told about is the module failing silently")
    }

    /// The control, and the one that matters most: an ordinary file is untouched
    /// by any of this.
    func testTheFileSomebodyActuallyWroteIsUnaffected() {
        backing.raw["module.keep-awake.autoAppRules"] = AppTriggerRules.encode([
            AppTrigger(bundleID: "com.apple.FinalCut"),
            AppTrigger(bundleID: "com.microsoft.VSCode", needsPower: true),
        ])

        XCTAssertEqual(settings.appTriggers.count, 2)
        XCTAssertFalse(settings.appRulesUnreadable)
    }
}
