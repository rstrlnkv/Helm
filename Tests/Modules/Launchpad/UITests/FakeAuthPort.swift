import Foundation
import HelmTestSupport
@testable import Module_Launchpad_Engine

/// Stands for the system's Touch ID / password prompt, one side of `LaunchpadAuthPort` and its four answers. `.immediate` answers
/// at once; `.slow` waits in the prompt until `release(_:)` (which may come after the ask was cancelled: the stale result a
/// closed window must not act on). It counts the asks and the cancellations it saw. The real port is never built in a test of the UI.
final class FakeAuthPort: LaunchpadAuthPort, @unchecked Sendable {
    enum Mode { case immediate(AuthOutcome), slow }

    private let mode: Mode
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<AuthOutcome, Never>] = []
    private var asked = 0
    private var cancels = 0

    init(_ mode: Mode) { self.mode = mode }

    var evaluations: Int { lock.withLock { asked } }
    var cancellations: Int { lock.withLock { cancels } }

    func evaluate(reason: String) async -> AuthOutcome {
        lock.withLock { asked += 1 }
        switch mode {
        case .immediate(let outcome): return outcome
        case .slow:
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in lock.withLock { waiting.append(continuation) } }
            } onCancel: {
                lock.withLock { cancels += 1 }
            }
        }
    }

    /// Waits until the port has been asked `count` times: the gate's task starts after the press that made it.
    func waitForAsks(_ count: Int = 1) async {
        await waitUntilWithin("the port was asked \(count) time(s)", .seconds(5)) { evaluations >= count }
    }

    /// The answer of the oldest ask only.
    func releaseFirst(_ outcome: AuthOutcome) {
        let first = lock.withLock { waiting.isEmpty ? nil : waiting.removeFirst() }
        first?.resume(returning: outcome)
    }

    /// The prompt's answer, for every ask waiting in it.
    func release(_ outcome: AuthOutcome) {
        let all = lock.withLock { () -> [CheckedContinuation<AuthOutcome, Never>] in defer { waiting = [] }; return waiting }
        for continuation in all { continuation.resume(returning: outcome) }
    }
}
