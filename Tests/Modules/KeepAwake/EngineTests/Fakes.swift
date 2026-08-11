import CoreGraphics
import Foundation
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// Two assertions, because the real port holds two.
///
/// This was a single `held` flag plus a record of the last `display:` argument,
/// which made the interesting state **unrepresentable**: `IOKitSleepAssertions`
/// takes an IOKit assertion per kind, and a display assertion outliving the
/// setting that asked for it is what "the display never sleeps" looks like from
/// the inside. A fake simpler than the thing it stands for cannot fail the way
/// the thing can, and the one test that touched `display` only asked whether
/// the argument had been passed.
final class FakeAssertions: SleepAssertions {
    /// Whether the system assertion is up. `held` is kept as its old name
    /// because every existing test reads it and it means the same thing.
    var held = false
    /// Whether the *display* assertion is up — the half that used to be a
    /// record of an argument rather than a state.
    var displayHeld = false
    var lastDisplay: Bool?
    var preventCount = 0
    var releaseCount = 0
    func preventSleep(display: Bool) {
        held = true
        displayHeld = display
        lastDisplay = display
        preventCount += 1
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

final class FakeDisplayObserver: DisplayObserverPort {
    private var onChange: (@Sendable () -> Void)?
    func startObserving(_ onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    func fire() { onChange?() }
    func stopObserving() { onChange = nil }
}

final class FakePower: PowerInfoPort {
    var snap: (onBattery: Bool, percent: Int)? = (onBattery: false, percent: 100)
    /// What `IOPSGetProvidingPowerSourceType` named, and it is a separate fact
    /// from `snap` on a real Mac: a desktop answers `.mains` while `snapshot()`
    /// answers nil — the combination the power rule was broken on — and a Mac
    /// drawing from a UPS names a supply this app does not reason about while a
    /// capacity is perfectly readable.
    ///
    /// **The third answer is the one that matters here.** While this was a
    /// `Bool` the real port could not produce «no reading *and* not on mains» —
    /// `isOnMains` folded every unreadable source to `true` — so a test
    /// planting it was testing a state that did not exist, and
    /// `BatteryGuard.shouldDeactivateWithNoReading`'s whole reason for being
    /// was unreachable in production while its test passed.
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
    func startObserving(_ onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    func fire() { onChange?() }
}

final class FakePointer: PointerPort {
    var loc: CGPoint?
    var bounds: CGRect?
    var moved: [CGPoint] = []
    func location() -> CGPoint? { loc }
    func move(to p: CGPoint) { moved.append(p) }
    func displayBounds(containing p: CGPoint) -> CGRect? { bounds }
}

final class FakeClamshell: ClamshellPort {
    var sudoersInstalled = false
    var pmset = ""
    var disableSleepCalls: [Bool] = []
    var installCompletion: ((Bool) -> Void)?
    var installCalls = 0
    func isSudoersInstalled() -> Bool { sudoersInstalled }
    func installSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        installCalls += 1
        installCompletion = done
    }
    /// Answer the prompt that is on screen. **The real one takes seconds to
    /// minutes and can be declined**, and a fake that only ever completed
    /// through a stored closure nobody called left the engine permanently
    /// mid-prompt — which is a state that flatters every «did it ask again?»
    /// test, because the in-flight guard suppresses the second ask for a reason
    /// that has nothing to do with the code under test.
    func finishInstall(granted: Bool) {
        let done = installCompletion
        installCompletion = nil
        if granted { sudoersInstalled = true }
        done?(granted)
    }
    var removeCalls = 0
    func removeSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        removeCalls += 1
        sudoersInstalled = false
        done(true)
    }
    /// Whether `pmset` accepts the call. A fake that always succeeds makes
    /// «the sudoers rule was removed behind the app's back» an unrepresentable
    /// state, so no test of the failure could exist whatever anybody wrote —
    /// and that failure is the one that leaves a Mac unable to sleep.
    var disableSleepSucceeds = true
    /// Whether a passwordless rule exists at all — separate from
    /// `sudoersInstalled`, which is «our file is there». On a real Mac the two
    /// differ: a rule written by something else grants the same capability
    /// under another name, and that is the state the file check could not see.
    var passwordlessGrantExists: Bool?
    func canDisableSleepWithoutPassword() -> Bool {
        passwordlessGrantExists ?? sudoersInstalled
    }
    func setDisableSleep(_ on: Bool) -> Bool {
        disableSleepCalls.append(on)
        // **The call needs the grant.** `PmsetClamshellPort` runs
        // `sudo -n pmset disablesleep …`, and `-n` fails outright when no
        // passwordless rule covers it. Answering yes without one made «the rule
        // is gone, so the restore cannot run» an unrepresentable state — which is
        // the state the grant's lifetime was changed for: a removal fired at quit
        // took away the very thing the next launch's recovery needs.
        guard canDisableSleepWithoutPassword() else { return false }
        return disableSleepSucceeds
    }
    /// How many times the report was read, because «did this launch shell out to
    /// `pmset` at all» is a question about every launch on every Mac: the
    /// recovery's anchors exist to keep that read off the ordinary path.
    private(set) var pmsetReads = 0
    func pmsetReport() -> String {
        pmsetReads += 1
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
