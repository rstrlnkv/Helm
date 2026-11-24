import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_KeepAwake_Engine

/// Two assertions, because the real port holds two.
///
/// `IOKitSleepAssertions` takes an IOKit assertion per kind, and a display
/// assertion outliving the setting that asked for it is what "the display never
/// sleeps" looks like from the inside. A fake simpler than the thing it stands
/// for cannot fail the way the thing can.
final class FakeAssertions: SleepAssertions {
    /// Whether the system assertion is up.
    var held = false
    /// Whether the display assertion is up.
    var displayHeld = false
    var lastDisplay: Bool?
    var preventCount = 0
    var releaseCount = 0
    /// Whether IOKit takes the assertion, so «macOS refused to hold the Mac
    /// awake» is representable: the Mac sleeps while every surface says the
    /// session is holding it.
    var succeeds = true
    func preventSleep(display: Bool) -> Bool {
        preventCount += 1
        guard succeeds else { return false }
        held = true
        displayHeld = display
        lastDisplay = display
        return true
    }
    func release() {
        held = false
        displayHeld = false
        releaseCount += 1
    }
}

final class FakeDisplayInfo: DisplayInfoPort {
    var flags: [Bool] = [true]
    func builtInFlags() -> [Bool] { flags }
}

final class FakeLidInfo: LidInfoPort {
    var lid = true
    var battery = true
    func hasLid() -> Bool { lid }
    func hasBattery() -> Bool { battery }
}

final class FakeDisplayObserver: DisplayObserverPort {
    private var onChange: (@Sendable () -> Void)?
    func startObserving(_ onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    func fire() { onChange?() }
    func stopObserving() { onChange = nil }
}

final class FakePower: PowerInfoPort {
    var snap: (onBattery: Bool, percent: Int)? = (onBattery: false, percent: 100)
    /// What `IOPSGetProvidingPowerSourceType` named, a separate fact from `snap`
    /// on a real Mac: a desktop answers `.mains` while `snapshot()` answers nil,
    /// and a Mac drawing from a UPS names a supply this app does not reason
    /// about while a capacity is readable.
    ///
    /// Three answers, as the real port has, so «no reading and not on mains»
    /// (`BatteryGuard.shouldDeactivateWithNoReading`) is a state a test can
    /// plant.
    private var plantedSupply: PowerSource.Supply??
    /// The system names this supply. `nil` is «it named one this app does not
    /// know, or named none at all», which is a state and not an omission.
    func says(_ supply: PowerSource.Supply?) { plantedSupply = .some(supply) }
    private var onChange: (@Sendable () -> Void)?
    func snapshot() -> (onBattery: Bool, percent: Int)? { snap }
    /// Unplanted, the supply follows `snap` — a Mac whose two readings agree,
    /// which is every laptop with a working battery and is what a test that only
    /// cares about a charge should get.
    func supply() -> PowerSource.Supply? {
        if case .some(let planted) = plantedSupply { return planted }
        return snap.map { $0.onBattery ? .battery : .mains }
    }
    private(set) var observing = false
    func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        observing = true
    }
    func stopObserving() { onChange = nil; observing = false }
    func fire() { onChange?() }
}

final class FakeApps: AppRunningPort {
    var ids: Set<String> = []
    private var onChange: (@Sendable () -> Void)?
    func runningBundleIDs() -> Set<String> { ids }
    private(set) var observing = false
    func startObserving(_ onChange: @escaping @Sendable () -> Void) { self.onChange = onChange; observing = true }
    func fire() { onChange?() }
    func stopObserving() { onChange = nil; observing = false }
}

final class FakePointer: PointerPort {
    var loc: CGPoint?
    var bounds: CGRect?
    var moved: [CGPoint] = []
    func location() -> CGPoint? { loc }
    func move(to p: CGPoint) { moved.append(p) }
    func displayBounds(containing p: CGPoint) -> CGRect? { bounds }
}

final class FakeClamshell: ClamshellPort, @unchecked Sendable {
    /// Behind one lock, because the port is asked from whichever thread the
    /// caller is on (the coordinator's queue, the drawing thread) while the test
    /// reads from its own. It covers the recorded state (the call lists, the
    /// counters, `sudoersInstalled`, `installCompletion`, the pending prompts) and
    /// the one-shot holds (`holdNextLook`). The answers a test sets before it
    /// starts the work (`pmset`, `removalSucceeds`, `withdrawalIsGranted`, …) are
    /// plain properties. Nothing is called with the lock held: a completion
    /// re-enters this fake, and a lock held across that is a deadlock waiting for
    /// the first port that answers on the same thread.
    private let lock = NSLock()
    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    private var _sudoersInstalled = false
    var sudoersInstalled: Bool {
        get { locked { _sudoersInstalled } }
        set { locked { _sudoersInstalled = newValue } }
    }
    var pmset: String? = ""
    private var _disableSleepCalls: [Bool] = []
    var disableSleepCalls: [Bool] {
        get { locked { _disableSleepCalls } }
        set { locked { _disableSleepCalls = newValue } }
    }
    private var _installCompletion: ((Bool) -> Void)?
    var installCompletion: ((Bool) -> Void)? {
        get { locked { _installCompletion } }
        set { locked { _installCompletion = newValue } }
    }
    private var _installCalls = 0
    var installCalls: Int { locked { _installCalls } }
    /// Every install prompt still up, oldest first: the real one takes minutes and
    /// the app carries on underneath, so a second ask is a second entry here and
    /// not an overwrite. `installCompletion` is the latest of them.
    private var pendingInstalls: [(Bool) -> Void] = []
    private var pendingRemovals: [(Bool) -> Void] = []

    /// The port's answers come back on a thread of their own, as `osascript`'s
    /// do (`installSudoers` and `removeSudoers` hand theirs back on a global queue).
    /// Set at construction; the rule on disk is left as it was.
    let answersOffTheCallersThread: Bool
    /// The removal prompt goes up and stays up, file still on disk, until
    /// `answerRemovalPrompts` — the state the real dialog is in for minutes.
    let holdsRemovals: Bool

    init(answersOffTheCallersThread: Bool = false, holdsRemovals: Bool = false) {
        self.answersOffTheCallersThread = answersOffTheCallersThread
        self.holdsRemovals = holdsRemovals
    }

    /// Which thread each call came on, recorded as a fact about the caller: a
    /// port asked the instant a test looks cannot tell the drawing thread from
    /// another.
    private var _asked: [(method: String, onMain: Bool)] = []
    private var _onAsked: [String: XCTestExpectation] = [:]
    var asked: [(method: String, onMain: Bool)] { locked { _asked } }
    func wasAskedOnMain(_ method: String) -> Bool { asked.contains { $0.method == method && $0.onMain } }
    func wasAsked(_ method: String) -> Bool { asked.contains { $0.method == method } }
    /// Fulfilled the first time the named method is asked, so a case can wait for
    /// the work to have happened before judging where it happened.
    func fulfil(_ expectation: XCTestExpectation, whenAsked method: String) {
        locked { _onAsked[method] = expectation }
    }
    /// A child process that has not finished yet. A port that answers the
    /// instant it is asked cannot tell a caller that waits from one that does
    /// not; with `blockUntilReleased` every call parks on `stillRunning` (a
    /// turnstile: a gate that let one through would leave the others parked for
    /// the rest of the run) until the test signals it.
    let stillRunning = DispatchSemaphore(value: 0)
    var blockUntilReleased = false
    private func record(_ method: String) {
        let waiting: XCTestExpectation? = locked {
            _asked.append((method, Thread.isMainThread))
            return _onAsked[method]
        }
        waiting?.fulfill()
        if blockUntilReleased { stillRunning.wait(); stillRunning.signal() }
    }
    /// How many times the file was looked for. An absence — «the launch put
    /// nothing back» — has to be read *after* the launch looked, or it is green
    /// because nothing has run yet.
    private var _installedChecks = 0
    var installedChecks: Int { locked { _installedChecks } }
    /// Set to hold the next look at the file until the test signals it, which
    /// is what a look still out looks like to a setting changed meanwhile;
    /// `lookBegan` is fulfilled when the look has read the file and is parked.
    private var _holdNextLook: DispatchSemaphore?
    var holdNextLook: DispatchSemaphore? {
        get { locked { _holdNextLook } }
        set { locked { _holdNextLook = newValue } }
    }
    var lookBegan: XCTestExpectation?
    func isSudoersInstalled() -> Bool {
        record("isSudoersInstalled")
        locked { _installedChecks += 1 }
        let answer = sudoersInstalled
        let held: DispatchSemaphore? = locked { defer { _holdNextLook = nil }; return _holdNextLook }
        if let gate = held {
            lookBegan?.fulfill()
            gate.wait()
        }
        return answer
    }
    func installSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        record("installSudoers")
        locked { _installCalls += 1 }
        if answersOffTheCallersThread { DispatchQueue.global().async { done(true) }; return }
        installCompletion = done
        locked { pendingInstalls.append(done) }
    }
    /// The person typed their password, for every prompt that is up. The file
    /// exists from this moment on, before any completion runs.
    func answerAllPrompts(granted: Bool) {
        let waiting: [(Bool) -> Void] = locked {
            let held = pendingInstalls
            pendingInstalls = []
            if granted { _sudoersInstalled = true }
            return held
        }
        installCompletion = nil
        for done in waiting { done(granted) }
    }
    /// Answer the prompt that is on screen. The real one takes seconds to
    /// minutes and can be declined; an engine left mid-prompt would flatter
    /// every «did it ask again?» test, because the in-flight guard suppresses
    /// the second ask for a reason unrelated to the code under test.
    func finishInstall(granted: Bool) {
        let done = installCompletion
        installCompletion = nil
        locked { pendingInstalls.removeAll() }
        if granted { sudoersInstalled = true }
        done?(granted)
    }
    private var _removeCalls = 0
    var removeCalls: Int { locked { _removeCalls } }
    /// Whether the removal goes through, so «the administrator dialog was
    /// declined» is representable: it leaves a permanent passwordless `pmset
    /// disablesleep` for a feature just switched off. `removeSudoers` answering
    /// `false` with the file in place is what `osascript` does on Cancel.
    var removalSucceeds = true
    func removeSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        record("removeSudoers")
        locked { _removeCalls += 1 }
        if answersOffTheCallersThread { DispatchQueue.global().async { done(true) }; return }
        if holdsRemovals { locked { pendingRemovals.append(done) }; return }
        if removalSucceeds { sudoersInstalled = false }
        done(removalSucceeds)
    }
    /// The person typed their password (or clicked Cancel). Only now does the file
    /// go, and only if they said yes.
    func answerRemovalPrompts(granted: Bool) {
        let waiting: [(Bool) -> Void] = locked {
            let held = pendingRemovals
            pendingRemovals = []
            if granted { _sudoersInstalled = false }
            return held
        }
        for done in waiting { done(granted) }
    }
    /// Whether the rule on disk permits its own withdrawal. False is a real
    /// state: a rule without the withdrawal line, or one written by something
    /// else, cannot take itself out, and only then does the removal cost a
    /// password.
    var withdrawalIsGranted = true
    /// How many times the free route was tried. «No dialog was raised» has to be
    /// read beside this or it is green because nothing was attempted at all.
    private var _passwordlessRemovals = 0
    var passwordlessRemovals: Int { locked { _passwordlessRemovals } }
    func removeSudoersWithoutPassword() -> Bool {
        record("removeSudoersWithoutPassword")
        locked { _passwordlessRemovals += 1 }
        // Read here rather than remembered: `sudoersInstalled` is a `var` a test
        // may move between two of these, which is what an administrator tidying
        // `/etc/sudoers.d` under the app looks like.
        guard sudoersInstalled else { return true }
        guard withdrawalIsGranted else { return false }
        sudoersInstalled = false
        return true
    }
    /// Whether `pmset` accepts the call, so «the sudoers rule was removed behind
    /// the app's back» is representable.
    var disableSleepSucceeds = true
    /// Whether a passwordless rule exists at all — separate from
    /// `sudoersInstalled`, which is «our file is there». On a real Mac the two
    /// differ: a rule written by something else grants the same capability
    /// under another name, a state a file check cannot see.
    var passwordlessGrantExists: Bool?
    /// How many times the coordinator asked whether it may disable sleep without
    /// a password — `sudo -n pmset disablesleep 0`, asked on a queue of its own.
    /// «No dialog was raised» has to be read after the question was answered,
    /// or it is green because nobody has asked yet.
    /// Architecture/TestsAndMeasurement.md § What makes a check.
    private var _grantChecks = 0
    var grantChecks: Int { locked { _grantChecks } }
    /// Set to hold the next probe on the lid's queue until the test signals it,
    /// which is what a probe still out looks like to the next edit.
    var holdNextProbe: DispatchSemaphore?
    func canDisableSleepWithoutPassword() -> Bool {
        record("canDisableSleepWithoutPassword")
        locked { _grantChecks += 1 }
        let gate = holdNextProbe
        holdNextProbe = nil
        gate?.wait()
        return passwordlessGrantExists ?? sudoersInstalled
    }
    func setDisableSleep(_ on: Bool) -> Bool {
        record("setDisableSleep")
        locked { _disableSleepCalls.append(on) }
        // The call needs the grant: `PmsetClamshellPort` runs `sudo -n pmset
        // disablesleep …`, and `-n` fails outright when no passwordless rule
        // covers it. So «the rule is gone, so the restore cannot run» is
        // representable.
        guard canDisableSleepWithoutPassword() else { return false }
        return disableSleepSucceeds
    }
    /// How many times the report was read, because «did this launch shell out to
    /// `pmset` at all» is a question about every launch on every Mac: the
    /// recovery's anchors exist to keep that read off the ordinary path.
    private var _pmsetReads = 0
    var pmsetReads: Int { locked { _pmsetReads } }
    /// Signalled on entry: the next call the launch look makes on `shell` after
    /// the file read and the verdict's hop, so a test can know both have happened.
    var pmsetEntered: DispatchSemaphore?
    func pmsetReport() -> String? {
        record("pmsetReport")
        locked { _pmsetReads += 1 }
        pmsetEntered?.signal()
        return pmset
    }
}

/// Manual clock: `schedule` records blocks keyed by an incrementing id so tests can
/// fire them explicitly via `fire(after:)`. The returned token cancels the entry
/// when released (deinit), mirroring how a real timer wrapper would invalidate.
final class FakeClock: Clock {
    final class Token {
        private let onCancel: () -> Void
        init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
        deinit { onCancel() }
    }
    private struct Entry { let id: Int; let after: TimeInterval; let block: () -> Void }
    private var entries: [Entry] = []
    private var nextID = 0
    private var cancelledIDs: Set<Int> = []
    var current = Date()
    /// How many timers have been scheduled since this clock was created,
    /// including ones since cancelled — a benchmark asking "did anything get
    /// armed at rest" wants to know that a timer was requested at all, not only
    /// whether one is still live.
    var scheduledCount: Int { entries.count }

    func schedule(after: TimeInterval, _ block: @escaping @Sendable () -> Void) -> AnyObject {
        let id = nextID; nextID += 1
        entries.append(Entry(id: id, after: after, block: block))
        return Token(onCancel: { [weak self] in self?.cancelledIDs.insert(id) })
    }
    func now() -> Date { current }

    /// Fire the most recently scheduled, not-cancelled entry with this `after` value.
    func fire(after: TimeInterval) {
        guard let e = entries.last(where: { $0.after == after && !cancelledIDs.contains($0.id) }) else { return }
        e.block()
    }
}

/// Waiting for the two things this module's ports do off the caller's thread.
///
/// Test plumbing shared by one target lives beside that target's fakes, the
/// way `HelmTestSupport` holds what every target shares.
extension XCTestCase {

    /// Everything already posted to the main actor has run.
    ///
    /// A hop of our own, awaited: a serial executor runs them in order, so this
    /// is an ordering fact rather than a sleep.
    @MainActor
    func drainMainActor() async {
        let drained = expectation(description: "main actor drained")
        Task { @MainActor in drained.fulfill() }
        await fulfillment(of: [drained], timeout: 5)
    }

    /// Everything already on the main queue has run.
    ///
    /// The engine posts a callback with `DispatchQueue.main.async` (`osascript`
    /// calls back on a background queue, and engine state belongs on main); this
    /// block is enqueued after it, and a serial queue runs them in order.
    ///
    /// It asserts that the block ran on main, so a drain that skipped the hop
    /// is red. `await fulfillment` rather than `wait(for:)`: these tests are on
    /// the main actor, and blocking it stops the queue draining at all.
    @MainActor
    func drainMainQueue() async {
        let drained = expectation(description: "main queue drained")
        var ranOnMain = false
        DispatchQueue.main.async {
            MainActor.assumeIsolated { ranOnMain = true }
            drained.fulfill()
        }
        await fulfillment(of: [drained], timeout: 5)
        XCTAssertTrue(ranOnMain, "the drain block was not run from the main queue")
    }

    /// The withdrawal has been attempted, and its verdict has landed.
    ///
    /// It runs on the coordinator's own serial queue — a child process must not
    /// run on the thread that draws — so «it happened» is waited for rather than
    /// assumed. Draining the main actor afterwards is what puts the reader after
    /// the verdict the port posts back.
    @MainActor
    func removalRan(on clamshell: FakeClamshell, attempts: Int = 1,
                    file: StaticString = #filePath, line: UInt = #line) async {
        await waitUntil("the withdrawal was attempted \(attempts) time(s)", file: file, line: line) {
            clamshell.passwordlessRemovals >= attempts
        }
        await drainMainActor()
    }
}

/// One `KeepAwakeEngine` over fakes. `KeepAwakeEngine.init` has no port defaults,
/// so a forgotten port there does not compile; here a forgotten port is a fresh
/// fake the test holds no reference to, and asserting on a fake the engine never
/// saw is the hazard. A call names every fake it configures or asserts on, and
/// always `store:`. Defaults are fakes, never a production port (`IOPSPowerInfo`,
/// `CGEventPointer`, `MacLidInfo`): that would drive the machine's own power
/// source, pointer or lid. `settings` is `KeepAwakeSettings` over `store`; `news`
/// and `batteryVeto` repeat the engine's defaults, they are not linked to them.
func fakeEngine(settings: KeepAwakeSettings? = nil,
                store: NamespacedStore = NamespacedStore(namespace: "keep-awake",
                                                         backing: InMemoryKeyValueStore()),
                assertions: SleepAssertions = FakeAssertions(),
                displayInfo: DisplayInfoPort = FakeDisplayInfo(),
                displayObserver: DisplayObserverPort = FakeDisplayObserver(),
                power: PowerInfoPort = FakePower(),
                apps: AppRunningPort = FakeApps(),
                pointer: PointerPort = FakePointer(),
                clamshell: ClamshellPort = FakeClamshell(),
                clock: Clock = FakeClock(),
                lidInfo: LidInfoPort = FakeLidInfo(),
                news: EngineNews<KeepAwakeEngine.StatePayload> = EngineNews(),
                batteryVeto: BatteryVetoChannel? = nil) -> KeepAwakeEngine {
    KeepAwakeEngine(settings: settings ?? KeepAwakeSettings(store: store), store: store,
                    assertions: assertions, displayInfo: displayInfo,
                    displayObserver: displayObserver, power: power, apps: apps,
                    pointer: pointer, clamshell: clamshell, clock: clock, lidInfo: lidInfo,
                    news: news, batteryVeto: batteryVeto)
}
