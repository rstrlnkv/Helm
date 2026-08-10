import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// «Timer until 15:42 · then the external display keeps it awake.»
///
/// That second clause is the only answer any screen gives to what happens when
/// the countdown reaches zero, and it is computed by
/// `SessionHero.holderAfterTimer(conditions:timerEndsAutomation:)` from the
/// conditions the engine published. The engine decides the same question for
/// itself, elsewhere and differently:
///
///     TimerPolicy.onExpiry(hasAutoCondition:suppressed:timerEndsAutomation:)
///
/// The two read a different number of inputs. `holderAfterTimer` knows nothing
/// about `suppressed`, and `Conditions.resolve` puts `.app` in the published set
/// whenever the app is running and a session is on — suppressed or not. So the
/// forecast and the outcome agree for exactly one reason: `startSession` clears
/// `suppressed` as a side effect, three lines above the arithmetic, where
/// nothing says it is load-bearing for a sentence in another target.
///
/// Delete that one line and nothing fails to compile, no test of the timer
/// notices, and the page tells somebody their render will keep the Mac awake
/// while the engine has already decided it will not.
final class TheForecastAtZeroIsWhatHappensTests: XCTestCase {

    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!
    private var apps: FakeApps!
    private var clock: FakeClock!
    private var assertions: FakeAssertions!
    private var engine: KeepAwakeEngine!

    private let render = "com.example.render"

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        settings = KeepAwakeSettings(store: store)
        settings.setAppTriggers([AppTrigger(bundleID: render)])
        apps = FakeApps()
        apps.ids = [render]
        clock = FakeClock()
        assertions = FakeAssertions()
        engine = KeepAwakeEngine(settings: settings, store: store, assertions: assertions,
                                 displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(),
                                 power: FakePower(), apps: apps, pointer: FakePointer(),
                                 clamshell: FakeClamshell(), clock: clock)
    }

    /// Exactly what `KeepAwakeSettingsPage.timedNote` computes, from exactly
    /// what the engine publishes. Spelling the conditions by hand here would be
    /// a second declaration of the page and would go on agreeing with itself
    /// after the real one stopped.
    private func whatThePageSaysWillHoldItAtZero() -> ActiveCondition? {
        SessionHero.holderAfterTimer(conditions: engine.activeConditions,
                                     timerEndsAutomation: settings.timerEndsAutomation)
    }

    // MARK: - The two answers are one answer

    /// The path that makes the coupling load-bearing: the rule is silenced,
    /// *then* a timed session is started on top of it. The page draws a
    /// countdown with «then Final Cut keeps it awake» underneath.
    func testAfterASuppressionTheForecastAndTheExpiryStillAgree() {
        engine.activate()
        engine.stopSession()
        XCTAssertTrue(engine.suppressed, "precondition: the rule is silenced")

        engine.startSession(minutes: 30)
        let forecast = whatThePageSaysWillHoldItAtZero()
        XCTAssertEqual(forecast, .app,
                       "precondition: the page promises the app will hold it at zero")

        clock.fire(after: 30 * 60)

        XCTAssertEqual(engine.isActive, forecast != nil,
                       "the page said the Mac would stay awake at zero and the engine let it "
                       + "sleep — `startSession` clearing `suppressed` is the only thing "
                       + "holding those two sentences together")
        XCTAssertTrue(engine.activeConditions.contains(.app))
        XCTAssertTrue(assertions.held)
    }

    /// The same agreement with the answer the other way round, so the equality
    /// above cannot pass by both sides always being «yes». The person has asked
    /// a timer to be the end of the automation as well: the page then promises
    /// nothing at zero, and nothing is what happens.
    func testWhenTheTimerEndsTheAutomationThePageAndTheEngineBothSayNothingHolds() {
        store.set(true, for: KeepAwakeSettings.Key.timerEndsAutomation)
        engine.activate()
        engine.startSession(minutes: 30)
        let forecast = whatThePageSaysWillHoldItAtZero()
        XCTAssertNil(forecast, "precondition: the page promises nothing at zero")

        clock.fire(after: 30 * 60)

        XCTAssertEqual(engine.isActive, forecast != nil)
        XCTAssertFalse(assertions.held)
    }

    /// And the ordinary case, which is the one somebody actually reads.
    func testTheForecastAndTheExpiryAgreeOnAPlainTimerOverARule() {
        engine.activate()
        engine.startSession(minutes: 30)
        let forecast = whatThePageSaysWillHoldItAtZero()
        XCTAssertEqual(forecast, .app, "precondition")

        clock.fire(after: 30 * 60)

        XCTAssertEqual(engine.isActive, forecast != nil)
    }

    // MARK: - The invariant underneath it

    /// Said as a property of the engine rather than of one screen: a session
    /// that names `.manual` is a session somebody asked for, and a rule cannot
    /// be «being ignored» at the same moment. Every surface that draws the
    /// paused banner reads `suppressed`, and every surface that draws a
    /// countdown reads the conditions; the two overlapping is a page that says
    /// «Awake · 29:58» and «Automation paused» at once.
    ///
    /// Walked over the orderings a person can produce with the controls that
    /// exist, rather than over one of them.
    func testNoSessionStartedByHandEverRunsWhileARuleIsSilenced() {
        engine.activate()

        let steps: [(String, () -> Void)] = [
            ("stop the rule", { self.engine.stopSession() }),
            ("start by hand", { self.engine.startSession(minutes: 30) }),
            ("stop again", { self.engine.stopSession() }),
            ("toggle", { self.engine.toggleSession() }),
            ("toggle again", { self.engine.toggleSession() }),
            ("start with no deadline", { self.engine.startSession(minutes: 0) }),
            ("stop once more", { self.engine.stopSession() }),
            ("resume", { self.engine.resumeAutomation() }),
            ("the app quits", { self.apps.ids = []; self.apps.fire() }),
            ("start with the app gone", { self.engine.startSession(minutes: 15) }),
            ("the app comes back", { self.apps.ids = [self.render]; self.apps.fire() }),
        ]

        var reached = false
        for (name, step) in steps {
            step()
            XCTAssertFalse(engine.suppressed && engine.activeConditions.contains(.manual),
                           "after «\(name)»: a session the person started is running while "
                           + "the rule under it is marked as being ignored")
            reached = reached || engine.activeConditions.contains(.manual)
        }
        XCTAssertTrue(reached, "no step ever started a session by hand; the walk proves nothing")
    }
}
