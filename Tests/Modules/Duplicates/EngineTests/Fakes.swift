import Foundation
@testable import Module_Duplicates_Engine

/// The engine-side doubles this target shares, the way the UI target's
/// `Fakes.swift` shares its transports.

/// A verification mid-read: each call announces itself and then waits for the
/// test, so the interleaving is chosen rather than raced. A check that answers
/// on the spot is over before Stop can be pressed, so every assertion about
/// «while it runs» would pass with the guard deleted.
///
/// The verdict is the caller's, because it was the only difference between the
/// two copies of this class — `ParkedVerify` answering `.identical` and
/// `ParkedUnreadableVerify` answering `.unreadable`, each private to its own
/// file. A comment in the second called it «the same class with the other
/// verdict», which is the note CLAUDE.md says such a duplication is.
final class ParkedVerify: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let gate = DispatchSemaphore(value: 0)
    private let verdict: DuplicateVerification.Verdict

    init(answering verdict: DuplicateVerification.Verdict = .identical) {
        self.verdict = verdict
    }

    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    func release(_ n: Int) { for _ in 0..<n { gate.signal() } }

    func check(_ remove: String, _ keep: String) -> DuplicateVerification.Verdict {
        lock.lock(); count += 1; lock.unlock()
        gate.wait()
        return verdict
    }
}

/// The ticks a progress stream delivered, collected from whatever thread the
/// engine emits on and read by the test after — the search's guard and the
/// removal's both listen this way.
final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [DuplicateProgress] = []
    var ticks: [DuplicateProgress] { lock.lock(); defer { lock.unlock() }; return collected }
    func add(_ tick: DuplicateProgress) { lock.lock(); collected.append(tick); lock.unlock() }
}
