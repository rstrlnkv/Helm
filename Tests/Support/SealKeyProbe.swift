import Foundation
import HelmRuntime

/// A seal-key port that can be in every state the login keychain can be in, and
/// records what was asked of it.
///
/// A fake is no simpler than the thing (Architecture/TestsAndMeasurement.md § Fakes):
/// each capability below exists because a state was otherwise impossible to
/// write down.
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
    private let fixedFirstUse: Bool?
    /// Raised as each caller *enters*, before the gate is waited on.
    ///
    /// `reads` is incremented on the way out, so a caller parked on the gate is
    /// invisible in it, and that is the state a test of two callers arriving
    /// together has to wait for.
    private let entered = DispatchSemaphore(value: 0)

    /// - Parameters:
    ///   - gate: held shut until a test opens it. Nil answers at once.
    ///   - firstUse: answered on every ask, for a guard built fresh over a store
    ///     that is, or is not, the run that made the item. Nil is the real
    ///     door: `true` once, then spent.
    public init(gate: DispatchSemaphore? = nil, firstUse: Bool? = nil) {
        self.gate = gate
        self.fixedFirstUse = firstUse
    }

    /// Blocks until a caller has reached the gate, so a test can arrange a second
    /// one behind the first. False when nobody arrived inside `seconds`, which is
    /// a failure the caller reports rather than a wait that never ends.
    @discardableResult
    public func waitUntilAsked(seconds: TimeInterval = 5) -> Bool {
        entered.wait(timeout: .now() + seconds) == .success
    }

    /// How many times the key has been asked for.
    public var reads: Int { lock.withLock { count } }

    /// Whether any of those asks came from the main thread.
    public var wasAskedOnTheMainThread: Bool { lock.withLock { mainThread } }

    public func key() -> SealKey? {
        // Read before the gate, so a caller blocked here has already told us
        // which thread it is.
        let onMain = Thread.isMainThread
        entered.signal()
        gate?.wait()
        return lock.withLock {
            count += 1
            mainThread = mainThread || onMain
            if let material { return SealKey(material: material, firstUse: fixedFirstUse ?? false) }
            let made = Data(repeating: 0x5A, count: 32)
            material = made
            return SealKey(material: made, firstUse: fixedFirstUse ?? true)
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
