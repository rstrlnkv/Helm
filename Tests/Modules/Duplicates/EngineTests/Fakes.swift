import Foundation
import HelmRuntime
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
/// verdict», which is the note such a duplication is.
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

    func check(_: String, _: String) -> DuplicateVerification.Verdict {
        lock.lock(); count += 1; lock.unlock()
        gate.wait()
        return verdict
    }
}

/// A fixed instant: `n` days after the epoch, so a test names its dates by
/// order rather than by clock.
func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

/// The facts of one file for the keep-ladder tests, its identity taken from the
/// path so two paths are two files.
func facts(_ path: String, added: Date? = nil, bytes: Int = 4_096) -> FileFacts {
    FileFacts(path: path, bytes: bytes, fileID: UInt64(abs(path.hashValue)), added: added)
}

/// A rule with no transit tier and no `.system` read: every rung above `.date` is
/// silent, so nothing depends on where this Mac keeps Downloads.
func rule(_ policy: KeepPolicy, transit: TransitFolders = TransitFolders(roots: [])) -> KeepRule {
    KeepRule(policy, transit: transit)
}

/// Every order of `items`.
func permutations<T>(_ items: [T]) -> [[T]] {
    guard items.count > 1 else { return [items] }
    return items.indices.flatMap { index -> [[T]] in
        var rest = items
        let head = rest.remove(at: index)
        return permutations(rest).map { [head] + $0 }
    }
}

extension XCTestCase {
    /// A text file for a test that cares what the file says; the byte filler in
    /// `HelmTestSupport` is for the ones that only need its size.
    @discardableResult
    func writeText(_ name: String, _ contents: String, in directory: URL) throws -> String {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url.path
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
    /// The `trashing:` argument that records, then removes the file as a real move leaves it.
    var trashing: @Sendable (URL) throws -> Void { { self.add($0); try FileManager.default.removeItem(at: $0) } }
}

/// For a construction whose test reaches no removal: a move through it is a
/// failure, not a file in the Trash.
let neverTrashes: @Sendable (URL) throws -> Void = { _ in XCTFail("a test that removes nothing moved a file") }

