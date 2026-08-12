import Foundation
import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// Two ways the lid feature fails, and neither reached a window.
///
/// **macOS refused.** `reallyEngage` reads `setDisableSleep(true)`, and `sudo -n`
/// fails whenever the NOPASSWD rule is not what Helm wrote. The engine logged it
/// and set `active` false — and `active` false is also what «nobody asked» looks
/// like, so the lid row went on explaining what an administrator password buys.
/// A person who switched that option on was told, by omission, that their lid was
/// safe to close.
///
/// **The rule outlived the feature.** `removeSudoers`' `Bool` was discarded, so a
/// declined administrator dialog left a permanent passwordless
/// `pmset disablesleep` for this account with nothing on screen about it — and the
/// one log line it did write accused something else of having written a rule Helm
/// wrote itself.
@MainActor
final class ALidThatDidNotWorkSaysSoTests: XCTestCase {

    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!
    private var clamshell: FakeClamshell!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        settings = KeepAwakeSettings(store: store)
        clamshell = FakeClamshell()
        // The grant is there, so nothing here raises a dialog: what is being
        // measured is `pmset` refusing, not the password flow.
        clamshell.sudoersInstalled = true
        clamshell.passwordlessGrantExists = true
        settings.setClamshellEnabled(true)
        engine = KeepAwakeEngine(settings: settings, store: store,
                                 assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(), power: FakePower(),
                                 apps: FakeApps(), pointer: FakePointer(),
                                 clamshell: clamshell, clock: FakeClock())
    }

    override func tearDown() {
        HelmLog.shared.setEnabled(false)
        HelmLog.shared.clearTail()
        super.tearDown()
    }

    // MARK: - macOS refused

    func testARefusalIsPublishedRatherThanLookingLikeNothingHappened() throws {
        try XCTSkipUnless(MacHardware.hasLid, "this Mac has no lid, so the lid is never engaged")
        clamshell.disableSleepSucceeds = false

        engine.startSession(minutes: 0)

        XCTAssertFalse(engine.clamshellActive, "precondition: pmset said no")
        XCTAssertTrue(clamshell.disableSleepCalls.contains(true),
                      "precondition: it was asked at all — an absence proves nothing when the "
                      + "subject never happened")
        XCTAssertTrue(engine.lidRefused,
                      "asked and refused reads exactly like never asked, and the row then "
                      + "described what the password would buy")
    }

    /// And it leaves when a later attempt works, so the row reports the state of
    /// the last answer rather than the worst answer it ever had.
    func testARefusalClearsWhenTheNextAttemptWorks() throws {
        try XCTSkipUnless(MacHardware.hasLid, "this Mac has no lid, so the lid is never engaged")
        clamshell.disableSleepSucceeds = false
        engine.startSession(minutes: 0)
        XCTAssertTrue(engine.lidRefused, "precondition: it refused once")

        engine.stopSession()
        clamshell.disableSleepSucceeds = true
        engine.startSession(minutes: 0)

        XCTAssertTrue(engine.clamshellActive, "precondition: this time it worked")
        XCTAssertFalse(engine.lidRefused, "the row would say «macOS refused» for ever")
    }

    /// The control: an ordinary session says nothing is wrong.
    func testAnOrdinarySessionPublishesNoRefusal() {
        engine.startSession(minutes: 0)
        XCTAssertFalse(engine.lidRefused)
    }

    /// It has to cross the wire, or the fact exists only inside the engine — the
    /// defect `StatePayload`'s own doc comment records.
    func testTheRefusalReachesThePayload() throws {
        try XCTSkipUnless(MacHardware.hasLid, "this Mac has no lid, so the lid is never engaged")
        clamshell.disableSleepSucceeds = false
        engine.startSession(minutes: 0)

        let decoded = try roundTrip()
        XCTAssertTrue(decoded.lidRefused, "the engine knew and the screen could not")
    }

    /// A payload from a build that never had these fields still decodes, and
    /// decodes to «nothing is wrong» — which is what such a build meant, since it
    /// could not ask either.
    func testAnOlderPayloadWithoutTheFieldsStillDecodes() throws {
        let older = Data("""
        {"isActive":true,"conditions":[],"clamshellActive":false,"suppressed":false}
        """.utf8)
        let decoded = try JSONDecoder().decode(KeepAwakeEngine.StatePayload.self, from: older)
        XCTAssertFalse(decoded.lidRefused)
        XCTAssertFalse(decoded.lidGrantRemains)
    }

    // MARK: - The rule outlived the feature

    /// A declined administrator dialog. The `Bool` said so and nobody read it.
    func testADeclinedRemovalIsPublishedRatherThanDiscarded() async {
        clamshell.removalSucceeds = false
        settings.setClamshellEnabled(false)

        engine.settingsChangedForTests()
        await settle()

        XCTAssertEqual(clamshell.removeCalls, 1, "precondition: the removal was attempted")
        XCTAssertTrue(clamshell.isSudoersInstalled(),
                      "precondition: Cancel leaves our own file exactly where it was")
        XCTAssertTrue(engine.lidGrantRemains,
                      "a passwordless pmset rule for a feature that is off, and no window says so")
    }

    /// **And the log stops blaming a third party in the one case Helm wrote the
    /// rule.** The old line fired on `canDisableSleepWithoutPassword()` alone, so
    /// a declined dialog — our file, untouched, still granting — was reported as
    /// «a rule survives that Helm did not write», which sends whoever reads the
    /// log looking for a second file that does not exist.
    func testADeclinedRemovalIsNotReportedAsSomebodyElsesRule() async {
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
        clamshell.removalSucceeds = false
        settings.setClamshellEnabled(false)

        engine.settingsChangedForTests()
        await settle()

        XCTAssertEqual(lines(containing: "Helm did not write"), 0,
                       "the rule Helm wrote itself was reported as somebody else's")
        XCTAssertEqual(lines(containing: "was not removed"), 1,
                       "…and the thing that did happen has to be in the trail, or this test "
                       + "passes on a module that logs nothing at all")
    }

    /// The other half, which the fix must not cost: a removal that really does
    /// leave a foreign grant behind is still named as one.
    func testAForeignGrantThatSurvivesIsStillNamedAsForeign() async {
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
        // Our file goes; the capability stays, because something else grants it.
        clamshell.removalSucceeds = true
        clamshell.passwordlessGrantExists = true
        settings.setClamshellEnabled(false)

        engine.settingsChangedForTests()
        await settle()

        XCTAssertFalse(clamshell.isSudoersInstalled(), "precondition: our file went")
        XCTAssertEqual(lines(containing: "Helm did not write"), 1,
                       "a revocation that revoked nothing was reported as done")
        XCTAssertFalse(engine.lidGrantRemains,
                       "and it is not *our* rule remaining — the row would tell somebody to "
                       + "switch a setting that cannot remove a file it did not write")
    }

    /// An ordinary removal publishes nothing, or the field above is wallpaper.
    func testAnOrdinaryRemovalPublishesNothing() async {
        clamshell.passwordlessGrantExists = false
        settings.setClamshellEnabled(false)

        engine.settingsChangedForTests()
        await settle()

        XCTAssertFalse(engine.lidGrantRemains)
    }

    // MARK: - Who asks for the rule back

    /// **The person's own switch, and only theirs.** The grant's lifetime is the
    /// feature; until now the only falling edge that took it out was the lid
    /// option's, so somebody who switched all of Keep Awake off left the rule
    /// behind for a module they had just turned off.
    func testSwitchingTheModuleOffAsksForTheGrantBack() async {
        engine.willDisable()
        await settle()

        XCTAssertEqual(clamshell.removeCalls, 1,
                       "the module is off and its NOPASSWD line is not — and this is the last "
                       + "moment there is anybody at the screen to answer the dialog")
    }

    /// Quitting must not, and that is the whole reason `willDisable` exists:
    /// `applicationWillTerminate` calls `deactivate()` on every live engine, and
    /// an `osascript` dialog raised there belongs to an app that is already gone.
    func testQuittingStillDoesNotAskForIt() {
        engine.startSession(minutes: 0)
        engine.deactivate()

        XCTAssertEqual(clamshell.removeCalls, 0,
                       "a terminating process put an administrator password dialog on screen")
        XCTAssertTrue(clamshell.isSudoersInstalled())
    }

    /// And with no rule on disk there is nothing to ask about, so switching the
    /// module off on an ordinary Mac raises nothing at all.
    func testWithNoRuleOnDiskSwitchingTheModuleOffAsksNothing() async {
        clamshell.sudoersInstalled = false
        clamshell.passwordlessGrantExists = false

        engine.willDisable()
        await settle()

        XCTAssertEqual(clamshell.removeCalls, 0)
    }

    // MARK: - Plumbing

    private func roundTrip() throws -> KeepAwakeEngine.StatePayload {
        let payload = KeepAwakeEngine.StatePayload(
            isActive: engine.isActive, conditions: [], clamshellActive: engine.clamshellActive,
            endDate: nil, startDate: nil, suppressed: engine.suppressed,
            lidRefused: engine.lidRefused, lidGrantRemains: engine.lidGrantRemains)
        return try JSONDecoder().decode(KeepAwakeEngine.StatePayload.self,
                                        from: JSONEncoder().encode(payload))
    }

    private func lines(containing text: String) -> Int {
        HelmLog.shared.recentEntries()
            .filter { $0.category == "keepawake" && $0.message.contains(text) }
            .count
    }

    /// The removal's callback records its verdict on the main actor — state of
    /// ours hops, the reads of the port deliberately do not. Awaiting a hop of our
    /// own is what puts this after it; a serial executor runs them in order, so
    /// this is an ordering fact rather than a sleep.
    private func settle() async {
        await Task.yield()
        let drained = expectation(description: "main actor drained")
        Task { @MainActor in drained.fulfill() }
        await fulfillment(of: [drained], timeout: 5)
    }
}
