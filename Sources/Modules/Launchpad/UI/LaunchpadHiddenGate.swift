import Foundation
import HelmRuntime
import Module_Launchpad_Engine

/// The block the hidden apps sit behind. Not a category kind: the category blocks are computed from visible apps, and the apps of
/// this one are never part of that output. Its entry always carries `apps: []`; the names exist only in the open, unlocked card.
enum LaunchpadHiddenBlock {
    /// A fixed id of its own: the category blocks' kind byte runs 0 to 29, and this id is distinct from every one of them.
    static let id = UUID(uuid: (0xC0, 0x7E, 0x1A, 0x55, 0xB0, 0x0C, 0x4A, 0x11, 0x9E, 0x5D, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFE))
}

/// **The lock in front of the hidden apps**, one per window state and one per settings page, so each scope locks on its own.
///
/// `locked` → `asking` → `unlocked`, in memory only: no store key, no file. Only the port's `.success` unlocks; every other
/// answer leaves it locked. One ask is in flight at a time (`ask` does nothing unless locked), and every ask carries a
/// ticket that `lock()` bumps, so a result that arrives after a lock, a close or a newer ask is read once on the main actor
/// and dropped. The log lines carry no names and no counts.
@MainActor final class LaunchpadHiddenGate: ObservableObject {
    enum Phase: Equatable { case locked, asking, unlocked }

    @Published private(set) var phase = Phase.locked
    /// The last ask found the Mac with no password or biometrics: the one banner line says so.
    @Published private(set) var unavailable = false
    /// Called with true before the system dialog is asked for and false when it is gone, for the window to hold off its closers.
    var onAsking: ((Bool) -> Void)?
    /// Called when an unlocked gate locks, for the window to drop what names a hidden app (a failed launch's notice).
    var onLocked: (() -> Void)?

    private let port: any LaunchpadAuthPort
    private var ticket = 0
    private var task: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    /// How long the prompt may stay up unanswered before the gate locks and the system's dialog is dismissed.
    private let timeout: Duration

    init(port: any LaunchpadAuthPort, timeout: Duration = .seconds(90)) {
        self.port = port
        self.timeout = timeout
    }

    func ask(reason: String, then: @escaping () -> Void) {
        guard phase == .locked else { return }
        ticket += 1
        let mine = ticket
        phase = .asking
        unavailable = false
        onAsking?(true)
        HelmLog.shared.info("launchpad", "hidden: asked")
        timer = Task { @MainActor [weak self, timeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.ticket == mine, self.phase == .asking else { return }
            HelmLog.shared.info("launchpad", "hidden: timed out")
            self.lock()
        }
        task = Task { @MainActor [weak self, port] in
            let outcome = await port.evaluate(reason: reason)
            guard let self, self.ticket == mine, self.phase == .asking else { return }
            self.task = nil
            self.timer?.cancel()
            self.timer = nil
            self.onAsking?(false)
            if outcome == .success {
                self.phase = .unlocked
                HelmLog.shared.info("launchpad", "hidden: unlocked")
                then()
            } else {
                self.phase = .locked
                self.unavailable = outcome == .unavailable
                HelmLog.shared.info("launchpad", "hidden: \(outcome == .unavailable ? "unavailable" : outcome == .cancelled ? "cancelled" : "refused")")
            }
        }
    }

    /// Ends when the last ask has been answered or dropped (a locked-out one is held until then, cancelled); a test waits on it.
    func settled() async { await task?.value }

    func lock() {
        ticket += 1
        task?.cancel()
        timer?.cancel()
        timer = nil
        let was = phase
        phase = .locked
        unavailable = false
        if was == .asking { onAsking?(false) }
        if was != .locked { HelmLog.shared.info("launchpad", "hidden: locked") }
        if was == .unlocked { onLocked?() }
    }
}
