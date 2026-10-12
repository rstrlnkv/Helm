import AppKit
@testable import HelmApp

/// **A `FoldLink` a row ticks by hand: it starts nothing, runs on no display and answers no clock.** It stands for
/// the display link's side of the port only: `start(on:tick:)` keeps the view weakly and the tick closure
/// strongly, as the real link keeps its target; `stop()` ends the calls; `fire(at:)` delivers one call with the
/// timestamp the row chose, so a row asserts the width at a given timestamp and never that time passed.
///
/// `fire(at:)` delivers after `stop()` on purpose: `isRunning` holds that the view stopped the link, a late
/// tick holds that the view takes it as nothing, and the two halves are asserted apart. `starts` counts the
/// calls of `start(on:tick:)`, so a cut that must not travel is read as a count that did not grow, beside a
/// flip that does grow it.
@MainActor
final class HandTickedFoldLink: FoldLink {
    private(set) var starts = 0
    private(set) var isRunning = false
    private(set) weak var view: NSView?
    private var tick: (@MainActor (CFTimeInterval) -> Void)?

    func start(on view: NSView, tick: @escaping @MainActor (CFTimeInterval) -> Void) {
        starts += 1
        isRunning = true
        self.view = view
        self.tick = tick
    }

    func stop() { isRunning = false }

    /// One tick to whoever started the link last, running or stopped: a stopped link's tick is the one already
    /// on its way. False when nothing ever started the link.
    @discardableResult
    func fire(at timestamp: CFTimeInterval) -> Bool {
        guard let tick else { return false }
        tick(timestamp)
        return true
    }
}
