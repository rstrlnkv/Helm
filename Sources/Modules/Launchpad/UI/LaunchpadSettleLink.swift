import AppKit
import QuartzCore

/// **The window's settle clock: one call per frame of the view's display, each with the link's own timestamp, from the display
/// link AppKit makes for a view.** `LaunchpadWindow` reads the reveal from these calls and from nothing else. The shape is
/// `DisplayFoldLink`'s (`Sources/HelmApp/FoldLink.swift`, where the reasons are): the link's target is a small object of this file
/// that holds the tick closure and nothing else, so neither the view nor this wrapper is kept alive by the system's link;
/// `stop()` and `deinit` invalidate it.
///
/// Assumed, read on no screen: that the link ticks while the panel is ordered front at alpha 0 (a pinch's first frames), that
/// the call arrives on the main thread, and that `invalidate()` is legal from inside the link's own call.
@MainActor
final class LaunchpadSettleLink {
    init() {}

    /// What the system's link calls and keeps.
    private var target: AnyObject?

    /// Read in `deinit`, which Swift 6 treats as nonisolated even on a `@MainActor` class.
    nonisolated(unsafe) private var link: CADisplayLink?

    /// Starts the calls for the display `view` is on; a link already running is stopped first. `tick` gets the link's
    /// timestamp in seconds; only differences between timestamps mean anything.
    func start(on view: NSView, tick: @escaping @MainActor (CFTimeInterval) -> Void) {
        stop()
        let target = Target(tick)
        let link = view.displayLink(target: target, selector: #selector(Target.fire(_:)))
        link.add(to: .main, forMode: .common)
        self.target = target
        self.link = link
    }

    /// Ends the calls; safe when nothing runs. A tick already on its way finds no closure and does nothing.
    func stop() {
        (target as? Target)?.tick = nil
        link?.invalidate()
        link = nil
        target = nil
    }

    deinit { link?.invalidate() }

    @MainActor
    private final class Target: NSObject {
        var tick: (@MainActor (CFTimeInterval) -> Void)?

        init(_ tick: @escaping @MainActor (CFTimeInterval) -> Void) { self.tick = tick }

        @objc func fire(_ link: CADisplayLink) { tick?(link.targetTimestamp) }
    }
}
