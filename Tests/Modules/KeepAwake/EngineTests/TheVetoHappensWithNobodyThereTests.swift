import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The battery veto is the one thing this app does with nobody in front of the
/// screen.
///
/// Every other account of it is a place the person is, by definition, not
/// looking: the hero announces it to VoiceOver on a page that has to be open,
/// the panel draws a banner behind a click, and the log is the log. The session
/// ends, the Mac goes to sleep, and the first the person knows of it is a Mac
/// that is asleep with the work not done — which is the state the guard exists
/// to produce and the one nothing was telling them about.
///
/// So one system notification, on the veto's rising edge. The decision is here
/// rather than in the view model, because a view model is built when a screen
/// asks for one and «nobody is looking» is precisely when no screen has.
final class TheVetoHappensWithNobodyThereTests: XCTestCase {

    // MARK: - Whether the arrival is news at all

    /// A veto that took nothing away is not news, and this is not a nicety: the
    /// guard is recomputed from every power event, so a laptop woken on a low
    /// battery vetoes before anybody has asked for anything. A notification
    /// then names a session nobody started.
    ///
    /// The same question `releaseForBattery` already asked inline to decide
    /// whether to write its log line — one predicate, so the banner and the log
    /// cannot disagree about whether anything happened.
    func testAVetoThatEndedNothingIsNotNews() {
        XCTAssertFalse(BatteryVetoNews.tookSomethingAway(active: false, manual: false,
                                                         hasDeadline: false))
    }

    /// Three ways there was something to lose, and a session that was only
    /// *asked for* is one of them: pressing «15 min» at 5 % is refused on
    /// arrival, and a refusal nobody is told about is the module failing
    /// silently at the one thing it was asked to do.
    func testEachWayThereWasSomethingToLoseIsNews() {
        XCTAssertTrue(BatteryVetoNews.tookSomethingAway(active: true, manual: false,
                                                        hasDeadline: false))
        XCTAssertTrue(BatteryVetoNews.tookSomethingAway(active: false, manual: true,
                                                        hasDeadline: false))
        XCTAssertTrue(BatteryVetoNews.tookSomethingAway(active: false, manual: false,
                                                        hasDeadline: true))
    }

    // MARK: - What to do about a permission

    /// Asked at the moment something wants it, which is this one: the guard
    /// ships **on**, so a person who never opens its settings row would never
    /// reach a gesture to hang the question on, and a permission asked for at
    /// launch is the one people learn to refuse.
    func testAPermissionNobodyHasAskedForIsAskedForNow() {
        XCTAssertEqual(BatteryVetoNews.step(given: .notDetermined), .ask)
    }

    /// And a refusal is not asked again — macOS would not prompt anyway, and the
    /// answer to «post?» is no.
    func testARefusalIsNotAskedAgainAndPostsNothing() {
        XCTAssertEqual(BatteryVetoNews.step(given: .denied), .stayQuiet)
    }

    func testAGrantedPermissionPosts() {
        XCTAssertEqual(BatteryVetoNews.step(given: .authorized), .post)
    }

    // MARK: - The engine, with a notification centre it can reach

    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!
    private var power: FakePower!
    private var notices: FakeAutomationNotice!
    private var engine: KeepAwakeEngine!

    /// The words the engine is handed, so a body that came from anywhere else is
    /// visible. In the app they are `KAStr.batteryVetoNotice`'s — `L()` lives in
    /// `HelmUI`, which no engine may import.
    private static func words(_ percent: Int) -> NoticeText {
        NoticeText(title: "the module", body: "the floor is \(percent)%")
    }

    private func build(_ notice: FakeAutomationNotice) {
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        settings = KeepAwakeSettings(store: store)
        power = FakePower()
        notices = notice
        engine = KeepAwakeEngine(settings: settings, store: store,
                                 assertions: FakeAssertions(),
                                 displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(),
                                 power: power, apps: FakeApps(), pointer: FakePointer(),
                                 clamshell: FakeClamshell(), clock: FakeClock(),
                                 batteryVeto: BatteryVetoChannel(port: notice,
                                                                 words: { Self.words($0) }))
    }

    private func onMains() {
        power.snap = (onBattery: false, percent: 100)
        power.says(.mains)
    }

    /// Under the shipped floor of 20 %.
    private func onAFlatBattery() {
        power.snap = (onBattery: true, percent: 5)
        power.says(.battery)
    }

    /// The notification is posted from a task of its own — nothing in the engine
    /// waits for macOS — so the test waits for the count it expects, and for a
    /// grace period afterwards when it expects none. A read of `posted` taken
    /// immediately would pass an absence for free.
    private func waitUntil(_ reached: () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !reached(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func waitForPosts(_ wanted: Int) async {
        await waitUntil { notices.posted.count >= wanted }
    }

    private func grace() async {
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    /// A hand-started session, and then the charge falls under the floor with
    /// nobody there. This is the notification's whole reason to exist.
    func testTheArrivalIsToldToSomebodyOnce() async {
        build(FakeAutomationNotice(state: .authorized))
        onMains()
        engine.activate()
        engine.startSession(minutes: 0)
        XCTAssertTrue(engine.isActive, "precondition: the Mac is being held awake")

        onAFlatBattery()
        power.fire()
        await waitForPosts(1)

        XCTAssertFalse(engine.isActive, "precondition: the guard ended the session")
        XCTAssertEqual(notices.posted, [Self.words(settings.batteryGuardPercent)],
                       "the session ended with nobody at the Mac and the only accounts of it "
                       + "were a page nobody had open and the log")
    }

    /// And the words are the ones handed in, not any the engine made up: an
    /// engine target cannot reach `L()`, so a sentence composed here would be
    /// English on a Japanese Mac.
    func testTheBodyIsTheSentenceItWasHandedAndCarriesTheFloor() async {
        build(FakeAutomationNotice(state: .authorized))
        settings.setBatteryGuardPercent(35)
        onMains()
        engine.activate()
        engine.startSession(minutes: 0)
        onAFlatBattery()
        power.fire()
        await waitForPosts(1)

        XCTAssertEqual(notices.posted.first?.body, "the floor is 35%",
                       "the notice was drawn from something other than the words the app "
                       + "layer wrote, or the floor never reached it")
    }

    /// While the veto holds there is nothing new to say, and `recompute` runs
    /// from every power event IOKit reports — each percentage step on the way
    /// down. The rising edge is the news; the state is not.
    func testAVetoThatIsStillInForceIsNotToldAgain() async {
        build(FakeAutomationNotice(state: .authorized))
        onMains()
        engine.activate()
        engine.startSession(minutes: 0)
        onAFlatBattery()
        power.fire()
        await waitForPosts(1)
        XCTAssertEqual(notices.posted.count, 1, "precondition: the arrival was told")

        power.snap = (onBattery: true, percent: 4)
        power.fire()
        power.snap = (onBattery: true, percent: 3)
        power.fire()
        await grace()

        XCTAssertEqual(notices.posted.count, 1,
                       "every percentage step on a draining battery posted a banner")
    }

    /// **A press while the veto holds is not news, and the person is watching.**
    ///
    /// The rising edge is what makes this so, and nothing else does: pressing
    /// «15 min» under the veto sets `manualOn`, which is one of the three facts
    /// that say something was taken away — so a notification decided on those
    /// alone would post a system banner at somebody who is looking at the very
    /// screen that explains it, once per press. The page's own notice and the
    /// dimmed verbs are that answer; a banner is for the arrival nobody saw.
    ///
    /// Found by mutation: with the `!batteryStopped` half deleted, every other
    /// test in this file still passed, because `releaseForBattery` clears those
    /// three facts on the way out and the *next power event* therefore has
    /// nothing to report. A press is the case that does not go through a power
    /// event.
    func testAPressUnderTheVetoIsNotABannerBecauseThePersonIsRightThere() async {
        build(FakeAutomationNotice(state: .authorized))
        onAFlatBattery()
        engine.activate()
        XCTAssertTrue(engine.batteryStopped, "precondition: the veto is in force")

        engine.startSession(minutes: 15)
        await grace()

        XCTAssertFalse(engine.isActive, "precondition: the press was refused, as it must be")
        XCTAssertEqual(notices.posted, [],
                       "the person pressed a button, watched nothing happen, read the notice "
                       + "on screen saying why — and was sent a system banner about it")
    }

    /// The charger goes in and comes back out a week later. The edge is a fact
    /// about the guard's state, not a once-per-launch flag.
    func testTheFallingEdgeArmsItAgain() async {
        build(FakeAutomationNotice(state: .authorized))
        onMains()
        engine.activate()
        engine.startSession(minutes: 0)
        onAFlatBattery()
        power.fire()
        await waitForPosts(1)

        onMains()
        power.fire()
        XCTAssertFalse(engine.batteryStopped, "precondition: the veto lifted")
        engine.startSession(minutes: 0)
        onAFlatBattery()
        power.fire()
        await waitForPosts(2)

        XCTAssertEqual(notices.posted.count, 2,
                       "the second time the battery ran out, nobody was told")
    }

    /// A veto that ended nothing says nothing — and the control for it, so
    /// «says nothing» cannot be satisfied by a notification path that has
    /// stopped working altogether: the same engine, the same fake, one veto with
    /// nothing to lose and one with a session.
    func testAVetoWithNothingToStopTellsNobodyAndTheOneAfterItStillDoes() async {
        build(FakeAutomationNotice(state: .authorized))
        onAFlatBattery()
        engine.activate()
        XCTAssertTrue(engine.batteryStopped, "precondition: the veto is in force")
        XCTAssertFalse(engine.isActive, "precondition: nothing was being held")
        power.snap = (onBattery: true, percent: 4)
        power.fire()
        await grace()

        XCTAssertEqual(notices.posted, [],
                       "a Mac woken on a low battery was told its session had been stopped, "
                       + "and there had never been one")
        XCTAssertEqual(notices.reads, 0,
                       "macOS was asked about banners for a veto that took nothing away")

        onMains()
        power.fire()
        engine.startSession(minutes: 0)
        onAFlatBattery()
        power.fire()
        await waitForPosts(1)

        XCTAssertEqual(notices.posted.count, 1,
                       "the control: with a session to lose the same path still speaks, so "
                       + "the silence above is a decision rather than a dead notifier")
    }

    /// Nobody has been asked, and the person says no. Nothing is posted, nothing
    /// throws, and the second time the battery runs out they are not asked
    /// again — macOS keeps the refusal and would not prompt anyway.
    func testARefusedPermissionPostsNothingAndIsNotAskedTwice() async {
        build(FakeAutomationNotice(state: .notDetermined, answersRequest: .denied))
        onMains()
        engine.activate()
        engine.startSession(minutes: 0)
        onAFlatBattery()
        power.fire()
        await waitUntil { notices.requests >= 1 }
        XCTAssertEqual(notices.requests, 1, "precondition: the person was asked once")
        XCTAssertEqual(notices.posted, [], "a banner was recorded that macOS had refused")

        onMains()
        power.fire()
        engine.startSession(minutes: 0)
        onAFlatBattery()
        power.fire()
        await grace()

        XCTAssertEqual(notices.requests, 1,
                       "the person was asked a second time for a permission they refused")
        XCTAssertEqual(notices.posted, [])
    }

    /// The permission is **read** at every arrival rather than remembered: it can
    /// be revoked in System Settings at any moment and nothing tells the app.
    /// A granted-then-revoked run must not post.
    func testAPermissionRevokedBehindTheAppsBackIsNoticed() async {
        build(FakeAutomationNotice(state: .authorized))
        onMains()
        engine.activate()
        engine.startSession(minutes: 0)
        onAFlatBattery()
        power.fire()
        await waitForPosts(1)
        XCTAssertEqual(notices.posted.count, 1, "precondition")

        notices.state = .denied
        onMains()
        power.fire()
        engine.startSession(minutes: 0)
        onAFlatBattery()
        power.fire()
        await grace()

        XCTAssertEqual(notices.reads, 2, "precondition: macOS was asked again, not remembered")
        XCTAssertEqual(notices.posted.count, 1, "a banner macOS would have dropped was counted")
    }

    /// An engine built without a notification centre is the one every other test
    /// in this module builds, and it must go on working: no port, no banner, no
    /// crash.
    func testAnEngineWithNoWayToReachMacOSStillEndsTheSession() {
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        settings = KeepAwakeSettings(store: store)
        power = FakePower()
        let assertions = FakeAssertions()
        engine = KeepAwakeEngine(settings: settings, store: store, assertions: assertions,
                                 displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(),
                                 power: power, apps: FakeApps(), pointer: FakePointer(),
                                 clamshell: FakeClamshell(), clock: FakeClock())
        power.snap = (onBattery: false, percent: 100)
        power.says(.mains)
        engine.activate()
        engine.startSession(minutes: 0)
        XCTAssertTrue(assertions.held, "precondition")

        power.snap = (onBattery: true, percent: 5)
        power.says(.battery)
        power.fire()

        XCTAssertFalse(assertions.held)
        XCTAssertTrue(engine.batteryStopped)
    }
}
