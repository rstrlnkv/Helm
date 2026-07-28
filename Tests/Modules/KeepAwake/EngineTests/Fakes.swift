import CoreGraphics
import Foundation
@testable import Module_KeepAwake_Engine

final class FakeAssertions: SleepAssertions {
    var held = false
    var lastDisplay: Bool?
    var preventCount = 0
    var releaseCount = 0
    func preventSleep(display: Bool) { held = true; lastDisplay = display; preventCount += 1 }
    func release() { held = false; releaseCount += 1 }
}

final class FakeDisplayInfo: DisplayInfoPort {
    var flags: [Bool] = [true]
    func builtInFlags() -> [Bool] { flags }
}

final class FakeDisplayObserver: DisplayObserverPort {
    private var onChange: (@Sendable () -> Void)?
    func startObserving(_ onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    func fire() { onChange?() }
}

final class FakePower: PowerInfoPort {
    var snap: (onBattery: Bool, percent: Int)? = (onBattery: false, percent: 100)
    private var onChange: (@Sendable () -> Void)?
    func snapshot() -> (onBattery: Bool, percent: Int)? { snap }
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
    func isSudoersInstalled() -> Bool { sudoersInstalled }
    func installSudoers(_ done: @escaping @Sendable (Bool) -> Void) { installCompletion = done }
    var removeCalls = 0
    func removeSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        removeCalls += 1
        sudoersInstalled = false
        done(true)
    }
    func setDisableSleep(_ on: Bool) -> Bool { disableSleepCalls.append(on); return true }
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
