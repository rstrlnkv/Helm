import Foundation
@testable import Module_Layout_Engine

/// The port's states and nothing else: observing or not, how many times it was
/// asked to start, and the two moments the port delivers.
///
/// `observing` is a Bool and not a count because `AppActivationPort.startObserving`
/// *replaces* an earlier registration: after two starts one registration is
/// left, which a Bool says and a counter would not. `starts` is the other half
/// (how many times the engine asked). A handler runs only while observing, as
/// the real port's does; the real port delivers on the main thread, the fake
/// delivers on the caller's, which is the one place it is simpler than the port
/// and why `TheActivationPortKeepsOneWatchTests` also drives the real one.
final class FakeActivation: AppActivationPort, @unchecked Sendable {
    private let lock = NSLock()
    private var helmActive: (@Sendable () -> Void)?
    private var frontmost: (@Sendable (String) -> Void)?
    private var startCount = 0

    /// True between a start and a stop.
    var observing: Bool { lock.withLock { helmActive != nil || frontmost != nil } }
    /// How many times the engine asked the port to start.
    var starts: Int { lock.withLock { startCount } }

    func startObserving(helmBecameActive: @escaping @Sendable () -> Void,
                        frontmostChanged: @escaping @Sendable (String) -> Void) {
        lock.withLock {
            startCount += 1
            helmActive = helmBecameActive
            frontmost = frontmostChanged
        }
    }

    func stopObserving() {
        lock.withLock { helmActive = nil; frontmost = nil }
    }

    /// Helm itself came to the front; nothing when not observing.
    func helmComesToTheFront() {
        let handler = lock.withLock { helmActive }
        handler?()
    }

    /// Another application came to the front; nothing when not observing.
    func comesToTheFront(_ bundleID: String) {
        let handler = lock.withLock { frontmost }
        handler?(bundleID)
    }
}
