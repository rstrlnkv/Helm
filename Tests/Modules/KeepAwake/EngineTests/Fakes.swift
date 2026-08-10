import CoreGraphics
import Foundation
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
    /// Separate from `snap`, because on a real Mac the two are separate: a
    /// desktop answers «on mains» while `snapshot()` answers nil, and that
    /// combination is the one the power rule was broken on. A fake that
    /// derived this from `snap` could not express it, so no test of it could
    /// exist — which is how the defect lived.
    var onMains: Bool?
    private var onChange: (@Sendable () -> Void)?
    func snapshot() -> (onBattery: Bool, percent: Int)? { snap }
    var isOnMains: Bool { onMains ?? !(snap?.onBattery ?? true) }
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
        return disableSleepSucceeds
    }
    func pmsetReport() -> String { pmset }
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
