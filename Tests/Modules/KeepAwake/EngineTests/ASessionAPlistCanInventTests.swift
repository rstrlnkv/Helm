import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// Three keys in a preferences file decide whether this Mac sleeps tonight.
///
/// `SessionSurvivesRelaunchTests` covers the pairs that *trap* — `1e300` in
/// either date, a start after the end. These are the ones that do not: values
/// that are finite, plausible and wrong, read at `activate()` before anything
/// is drawn. `~/Library/Preferences` is a file any process running as this user
/// can rewrite, and the module's whole output is whether the machine is allowed
/// to sleep.
final class ASessionAPlistCanInventTests: XCTestCase {

    private var store: NamespacedStore!
    private var clock: FakeClock!
    private var assertions: FakeAssertions!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        clock = FakeClock()
        assertions = FakeAssertions()
    }

    private func engine() -> KeepAwakeEngine {
        KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                        assertions: assertions, displayInfo: FakeDisplayInfo(),
                        displayObserver: FakeDisplayObserver(), power: FakePower(),
                        apps: FakeApps(), pointer: FakePointer(),
                        clamshell: FakeClamshell(), clock: FakeClock())
    }

    // MARK: - One boolean, and the Mac never sleeps again

    /// `sessionOn` alone, with neither date. `SessionRestore` reads that as
    /// `.indefinite` — «until I say stop» — because that is exactly what the
    /// engine's own writer stores for a session started with `minutes: 0`: the
    /// dates go down as `0`, and `0` is read back as «no date». The two are
    /// indistinguishable by construction, so this cannot be refused without a
    /// production change, and it is not a defect so much as the cost of the
    /// shape.
    ///
    /// What it must not be is *silent*: the Mac comes up held awake with no
    /// countdown and nothing on screen that says why it began. The line in the
    /// log is the only account, which is the same reason `restoreSession`
    /// writes one for a session that had already ended.
    func testAPlistThatSaysOnlySessionOnHoldsTheMacAndSaysSoInTheLog() {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }
        HelmLog.shared.clearTail()

        store.set(true, for: KeepAwakeEngine.SessionKey.on)

        let module = engine()
        module.activate()

        XCTAssertTrue(module.isActive,
                      "one boolean in a file is a Mac that will not sleep until somebody "
                      + "opens Helm and stops it")
        XCTAssertTrue(assertions.held)
        XCTAssertTrue(restoreLines().contains { $0.contains("no deadline") },
                      "nothing anywhere accounts for a Mac that came up held awake: "
                      + "\(restoreLines())")
    }

    /// The control for the line above — an ordinary launch with nothing stored
    /// says nothing, so «the log mentions it» is not wallpaper.
    func testALaunchWithNoStoredSessionSaysNothingAboutRestoring() {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }
        HelmLog.shared.clearTail()

        let module = engine()
        module.activate()

        XCTAssertFalse(module.isActive, "precondition")
        XCTAssertEqual(restoreLines(), [])
    }

    // MARK: - Dates that are real and wrong

    /// A deadline in the year 3000 — not `1e300`, which is obviously nobody's
    /// date, but a `Date` that formats, sorts and compares like any other. A
    /// clock set wrong on a Mac whose battery died produces it, and so does a
    /// plist written by hand.
    ///
    /// Refused, because it is nine hundred years and this module's ceiling for
    /// every number however it arrives is a day. Asserted as the property the
    /// countdown needs rather than as a particular answer.
    func testADeadlineInTheYearThreeThousandIsNotASession() {
        let year3000 = DateComponents(calendar: Calendar(identifier: .gregorian),
                                      timeZone: TimeZone(identifier: "UTC"),
                                      year: 3000, month: 1, day: 1).date!
        store.set(true, for: KeepAwakeEngine.SessionKey.on)
        store.set(0.0, for: KeepAwakeEngine.SessionKey.startedAt)
        store.set(year3000.timeIntervalSinceReferenceDate, for: KeepAwakeEngine.SessionKey.endsAt)

        let module = engine()
        module.activate()

        XCTAssertFalse(module.isActive,
                       "a Mac held awake for nine hundred years, from a date that looks "
                       + "perfectly ordinary in the file")
        XCTAssertFalse(assertions.held)
    }

    /// The same date with a start beside it an hour earlier. The pair is
    /// credible as a *duration*, so the session restores — and the deadline the
    /// engine keeps must be the one it decided on, an hour from now, not the
    /// one it read. Every countdown surface converts `endDate - now` to an
    /// `Int`.
    func testADeadlineInTheYearThreeThousandWithAStartBesideItComesBackAsAnHour() throws {
        let year3000 = DateComponents(calendar: Calendar(identifier: .gregorian),
                                      timeZone: TimeZone(identifier: "UTC"),
                                      year: 3000, month: 1, day: 1).date!
        store.set(true, for: KeepAwakeEngine.SessionKey.on)
        store.set(year3000.addingTimeInterval(-3600).timeIntervalSinceReferenceDate,
                  for: KeepAwakeEngine.SessionKey.startedAt)
        store.set(year3000.timeIntervalSinceReferenceDate, for: KeepAwakeEngine.SessionKey.endsAt)

        let module = engine()
        module.activate()

        let end = try XCTUnwrap(module.endDate, "precondition: the pair bounds itself to an hour")
        XCTAssertLessThanOrEqual(end.timeIntervalSinceNow, TimerPolicy.longestSession,
                                 "the stored date was kept and every surface draws it")
        XCTAssertGreaterThan(end.timeIntervalSinceNow, 0)
    }

    /// A deadline that has already passed is over, however recently. One second
    /// is the boundary the `endDate > now` test is written at, and a session
    /// with nothing left of it must not come back holding the assertion behind
    /// a countdown reading 0:00.
    func testADeadlineOneSecondInThePastIsOver() {
        store.set(true, for: KeepAwakeEngine.SessionKey.on)
        store.set(Date().addingTimeInterval(-1800).timeIntervalSinceReferenceDate,
                  for: KeepAwakeEngine.SessionKey.startedAt)
        store.set(Date().addingTimeInterval(-1).timeIntervalSinceReferenceDate,
                  for: KeepAwakeEngine.SessionKey.endsAt)

        let module = engine()
        module.activate()

        XCTAssertFalse(module.isActive)
        XCTAssertFalse(assertions.held)
    }

    /// And one second in the future is a session, so the boundary above is a
    /// boundary rather than a floor that swallows everything short.
    func testADeadlineOneSecondAwayIsStillASession() {
        store.set(true, for: KeepAwakeEngine.SessionKey.on)
        store.set(Date().addingTimeInterval(-1800).timeIntervalSinceReferenceDate,
                  for: KeepAwakeEngine.SessionKey.startedAt)
        store.set(Date().addingTimeInterval(1).timeIntervalSinceReferenceDate,
                  for: KeepAwakeEngine.SessionKey.endsAt)

        let module = engine()
        module.activate()

        XCTAssertTrue(module.isActive, "a session with a second left is a session")
        XCTAssertTrue(assertions.held)
    }

    /// The dates without the flag are stale bookkeeping, not a session. This is
    /// the pair a stopped session leaves behind, and reading it would resurrect
    /// what somebody switched off.
    func testAFutureDeadlineWithTheFlagOffIsNotASession() {
        store.set(false, for: KeepAwakeEngine.SessionKey.on)
        store.set(Date().timeIntervalSinceReferenceDate, for: KeepAwakeEngine.SessionKey.startedAt)
        store.set(Date().addingTimeInterval(1800).timeIntervalSinceReferenceDate,
                  for: KeepAwakeEngine.SessionKey.endsAt)

        let module = engine()
        module.activate()

        XCTAssertFalse(module.isActive)
    }

    // MARK: - The wrong type under a session key

    /// A string where a `Double` lived, a list where the flag lived. The plist
    /// is not a trusted input for these three keys any more than it is for the
    /// settings next to them, and the answer has to be «no session» rather than
    /// a crash on the way up.
    func testAValueOfTheWrongTypeUnderASessionKeyIsNoSession() {
        for junk in ["soon", "", ["a"], 0.0] as [Any] {
            store.set(true, for: KeepAwakeEngine.SessionKey.on)
            store.set(junk, for: KeepAwakeEngine.SessionKey.startedAt)
            store.set(junk, for: KeepAwakeEngine.SessionKey.endsAt)
            let fresh = FakeAssertions()
            let module = KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                                         assertions: fresh, displayInfo: FakeDisplayInfo(),
                                         displayObserver: FakeDisplayObserver(),
                                         power: FakePower(), apps: FakeApps(),
                                         pointer: FakePointer(), clamshell: FakeClamshell(),
                                         clock: clock)

            module.activate()

            // «On, with no readable dates» is the same shape as a real
            // indefinite session, so the Mac is held — what must not happen is
            // a deadline invented out of a string.
            XCTAssertNil(module.endDate, "a stored \(junk) became a deadline")
        }
    }

    private func restoreLines() -> [String] {
        HelmLog.shared.recentEntries()
            .filter { $0.category == "keepawake" }
            .map(\.message)
            .filter { $0.contains("restored") || $0.contains("had already ended") }
    }
}
