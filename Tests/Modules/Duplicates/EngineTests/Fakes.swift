import Foundation
import XCTest
@testable import Module_Duplicates_Engine

// The engine-side doubles this target shares, the way the UI target's
// `Fakes.swift` shares its fakes.

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

/// What the engine was told to trash. Every construction in this target passes a
/// fake to `trashing:` — this recorder, `neverTrashes` or a closure — so no test
/// here can reach the person's Trash.
final class TrashRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    var count: Int { lock.lock(); defer { lock.unlock() }; return urls.count }
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return urls.map(\.path) }
    func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    /// The `trashing:` argument that records instead of moving.
    var trashing: @Sendable (URL) throws -> Void { { self.add($0) } }
}

/// For a construction whose test reaches no removal: a move through it is a
/// failure, not a file in the Trash.
let neverTrashes: @Sendable (URL) throws -> Void = { _ in XCTFail("a test that removes nothing moved a file") }
