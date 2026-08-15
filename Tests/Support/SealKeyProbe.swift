import Foundation
import HelmRuntime

/// A seal-key port that can be in every state the login keychain can be in, and
/// records what was asked of it.
///
/// Written once here because it was written three times before: two identical
/// copies in the tests for this fix and a third, thinner one that the door-shuts
/// guard already depended on. The rule those broke is the one about a helper
/// that stands in for something being no simpler than the thing — each capability
/// below exists because a state was otherwise impossible to write down.
///
/// - **First use is spent.** `KeychainSealKey` answers `firstUse: true` only for
///   the run that creates the item and `false` for ever after; that is the
///   trust-on-first-use door closing. A probe answering `true` for ever cannot
///   tell a cache that shuts the door from one that props it open.
/// - **The thread is recorded.** A keychain round trip on the thread that draws
///   is a modal authorization dialog in front of a window with nothing in it, so
///   *which thread asked* is the question, not *how many times*.
/// - **It can be held mid-answer.** A port that returns instantly is over before
///   the code under test is reached, and every assertion about drawing while the
///   keychain is still deciding is then vacuous. `gate` is that pause.
public final class SealKeyProbe: SealKeyPort, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var mainThread = false
    private var material: Data?
    private let gate: DispatchSemaphore?

    /// - Parameter gate: held shut until a test opens it. Nil answers at once.
    public init(gate: DispatchSemaphore? = nil) { self.gate = gate }

    /// How many times the key has been asked for.
    public var reads: Int { lock.withLock { count } }

    /// Whether any of those asks came from the main thread.
    public var wasAskedOnTheMainThread: Bool { lock.withLock { mainThread } }

    public func key() -> SealKey? {
        // Read before the gate: a caller blocked inside here has already told us
        // which thread it is, which is the only thing a deadlocked test could
        // otherwise never report.
        let onMain = Thread.isMainThread
        gate?.wait()
        return lock.withLock {
            count += 1
            mainThread = mainThread || onMain
            if let material { return SealKey(material: material, firstUse: false) }
            let made = Data(repeating: 0x5A, count: 32)
            material = made
            return SealKey(material: made, firstUse: true)
        }
    }
}

/// A keychain that cannot answer — locked at login, the reachable case
/// `KeychainSealKey` returns nil for. Separate from `SealKeyProbe` rather than a
/// flag on it: "refuses" and "answers" are different ports, and a flag would
/// invite a test to change one into the other mid-run, which no keychain does.
public final class SilentSealKey: SealKeyPort, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    public init() {}

    public var reads: Int { lock.withLock { count } }

    public func key() -> SealKey? {
        lock.withLock { count += 1 }
        return nil
    }
}
