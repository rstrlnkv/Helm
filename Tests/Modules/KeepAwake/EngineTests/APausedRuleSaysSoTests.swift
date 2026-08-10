import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// One rule, one screen, two accounts of it.
///
/// While a rule is paused the settings page drew a banner across the top —
/// «Paused until the rule applies again» — and two hundred points below it the
/// rule's own row said «Not applying right now». The row was reading
/// `activeConditions`, which a paused rule is deliberately absent from, so it
/// could not tell «paused» from «the app quit». Of the two sentences, the row's
/// was the one that sounded like nothing was wrong.
///
/// Two halves, tested here: the note has a fourth case at all, and the engine
/// publishes the fact the fourth case needs.
final class APausedRuleSaysSoTests: XCTestCase {

    // MARK: - The note

    func testAPausedRuleReadsAsPausedRatherThanAsNotApplying() {
        let note = RuleNote.of(enabled: true, satisfied: false,
                              suppressed: true, triggerHolds: true)
        XCTAssertEqual(note, .paused,
                       "the row said «Not applying right now» under a banner saying the rule "
                       + "was paused")
    }

    /// The control, and the reason the flag cannot simply be `suppressed`: a
    /// rule whose own trigger is false is not the rule that was paused, and
    /// marking it so would put «Paused» on every switched-on row on the page.
    func testARuleWhoseTriggerIsFalseIsStillJustWaiting() {
        let note = RuleNote.of(enabled: true, satisfied: false,
                               suppressed: true, triggerHolds: false)
        XCTAssertEqual(note, .waiting)
    }

    func testTheOtherThreeStatesAreUnchanged() {
        XCTAssertEqual(RuleNote.of(enabled: false, satisfied: false,
                                   suppressed: false, triggerHolds: false), .meaning)
        XCTAssertEqual(RuleNote.of(enabled: true, satisfied: true,
                                   suppressed: false, triggerHolds: true), .applies)
        XCTAssertEqual(RuleNote.of(enabled: true, satisfied: false,
                                   suppressed: false, triggerHolds: false), .waiting)
        // Switched off wins over everything: a paused module does not turn an
        // off switch into a paused rule.
        XCTAssertEqual(RuleNote.of(enabled: false, satisfied: false,
                                   suppressed: true, triggerHolds: true), .meaning)
    }

    // MARK: - The fact the note needs

    /// `activeConditions` is empty while suppressed — by design — so nothing
    /// on the wire could distinguish a paused rule from a quiet one.
    func testTheEngineStillReportsATriggerThatHoldsWhilePaused() {
        let store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        store.set(true, for: KeepAwakeSettings.Key.autoPower)
        let power = FakePower()
        power.onMains = true
        let engine = KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                                     assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                                     displayObserver: FakeDisplayObserver(), power: power,
                                     apps: FakeApps(), pointer: FakePointer(),
                                     clamshell: FakeClamshell(), clock: FakeClock())
        engine.activate()
        XCTAssertTrue(engine.isActive, "precondition: the power rule is holding the Mac")
        XCTAssertTrue(engine.triggeredConditions.contains(.power))

        engine.stopSession()

        XCTAssertTrue(engine.suppressed, "precondition: Stop silenced the rule")
        XCTAssertFalse(engine.activeConditions.contains(.power),
                       "precondition: a paused rule is absent from activeConditions, which is "
                       + "exactly why a second field was needed")
        XCTAssertTrue(engine.triggeredConditions.contains(.power),
                      "the charger is still in and the page has no way to say so — the row "
                      + "falls back to «Not applying right now» under a «Paused» banner")
    }

    /// …and when the trigger really does drop, it leaves. Otherwise the field
    /// above is a constant and the row would say «Paused» for ever.
    func testATriggerThatDropsLeavesTheSet() {
        let store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        store.set(true, for: KeepAwakeSettings.Key.autoPower)
        let power = FakePower()
        power.onMains = true
        let engine = KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                                     assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                                     displayObserver: FakeDisplayObserver(), power: power,
                                     apps: FakeApps(), pointer: FakePointer(),
                                     clamshell: FakeClamshell(), clock: FakeClock())
        engine.activate()
        engine.stopSession()

        power.onMains = false
        engine.settingsChangedForTests()

        XCTAssertFalse(engine.triggeredConditions.contains(.power))
        XCTAssertFalse(engine.suppressed, "and the pause lifts with it")
    }
}
