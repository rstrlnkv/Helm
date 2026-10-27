import Foundation

/// A repeating main-run-loop tick that exists only while something wants it.
///
/// Written for the menu bar, which has two of these — a 1 Hz countdown and a
/// 30 Hz spin — and where the failure is silent: an armed timer nobody wants
/// keeps redrawing the status item, and a screenshot of the menu bar looks the
/// same either way.
@MainActor public final class RepeatingTick {
    private let interval: TimeInterval
    private let onTick: () -> Void
    /// The run loop keeps its own reference, so dropping ours stops nothing:
    /// `set(active: false)` invalidates it, and so does the timer's block once
    /// the tick is gone.
    private var timer: Timer?

    public init(interval: TimeInterval, onTick: @escaping () -> Void) {
        self.interval = interval
        self.onTick = onTick
    }

    public var isRunning: Bool { timer?.isValid == true }

    /// Idempotent: callers ask on every redraw, and re-arming an armed tick
    /// would stack timers on the run loop.
    public func set(active: Bool) {
        if active, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
                // The run loop holds the timer, so it outlives its owner unless
                // it stops itself — the same shape as the observers in
                // ARCHITECTURE.md § An observer outlives the thing it points at.
                guard let self else { return timer.invalidate() }
                MainActor.assumeIsolated { self.onTick() }
            }
        } else if !active {
            timer?.invalidate()
            timer = nil
        }
    }
}
