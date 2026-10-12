import AppKit
import QuartzCore

/// **The source of frames for the sidebar's fold: one call per frame of a view's display, each with the link's own
/// timestamp.** `ShellContentView` drives the width from these calls and from nothing else, so a row hands the
/// view a link of its own and ticks it by hand.
@MainActor
protocol FoldLink: AnyObject {
    /// Starts the calls for the display `view` is on; a link already running is stopped first. `tick` gets the
    /// link's timestamp in seconds; only differences between timestamps mean anything.
    func start(on view: NSView, tick: @escaping @MainActor (CFTimeInterval) -> Void)

    /// Ends the calls; safe when nothing runs. A tick already on its way may still arrive, and the caller takes it
    /// as nothing.
    func stop()
}

/// **`FoldLink` over the display link AppKit makes for a view.** The link's target is a small object of this file
/// that holds the tick closure and nothing else: neither the view nor this wrapper is ever the target, because the
/// system's link keeps its target and a view as target would never be freed. The chain is the view, this wrapper,
/// the link, the target, the closure, and the closure holds the view weakly.
///
/// The wrapper stops the link in `stop()` and in `deinit`. What holds each way a link ends: a shell that leaves
/// its window ends a fold in flight and stops the link (`ShellContentView.viewDidMoveToWindow`, row
/// `testAViewMovedToAnotherWindowOrToNoneMidWayLandsOnTheTarget`); the wrapper released while it runs invalidates
/// in `deinit` (row `testTheRealLinksTargetIsGoneAfterTheWrapperIsReleased`); the closure holds the view weakly
/// (row `testNothingKeepsTheViewAliveAfterItsControllerIsReleased`, over a link ticked by hand). A shell freed
/// with its real link running is a net over that whole chain
/// (`testAShellReleasedWhileItsRealLinkRunsLetsTheTargetGo`), not a guard of the `deinit` or of the closure.
/// The `CADisplayLink` is added to the main run loop in the common modes.
///
/// Assumed, read on no screen and by no row (no row ticks this link): that the system pauses the link while the
/// view's window is not shown and resumes it; that the link calls its target at all once it is added to the run
/// loop, once per frame; that `targetTimestamp` never goes backwards (`ShellContentView.tick` takes a step back as
/// a landing, which a person sees as a cut); that the call arrives on the main thread; that `invalidate()` is legal
/// from inside the link's own call, which every travel that arrives does (tick, then `didSet`, `endTravel`,
/// `stop`).
@MainActor
final class DisplayFoldLink: FoldLink {
    init() {}

    /// Whether this wrapper holds a link: true from `start(on:tick:)` until `stop()`. It says nothing of whether the
    /// system calls the target. Rows read it; nothing in the app does.
    var isRunning: Bool { link != nil }

    /// What the system's link calls and keeps; readable so a row can hold it weakly and see it go.
    private(set) var target: AnyObject?

    /// Read in `deinit`, which Swift 6 treats as nonisolated even on a `@MainActor` class.
    nonisolated(unsafe) private var link: CADisplayLink?

    func start(on view: NSView, tick: @escaping @MainActor (CFTimeInterval) -> Void) {
        stop()
        let target = Target(tick)
        let link = view.displayLink(target: target, selector: #selector(Target.fire(_:)))
        link.add(to: .main, forMode: .common)
        self.target = target
        self.link = link
    }

    func stop() {
        (target as? Target)?.tick = nil
        link?.invalidate()
        link = nil
        target = nil
    }

    deinit { link?.invalidate() }

    /// What the system's link calls. A call that was already on its way when `stop()` ran finds no closure and does
    /// nothing.
    @MainActor
    private final class Target: NSObject {
        var tick: (@MainActor (CFTimeInterval) -> Void)?

        init(_ tick: @escaping @MainActor (CFTimeInterval) -> Void) {
            self.tick = tick
        }

        @objc func fire(_ link: CADisplayLink) {
            guard let tick else { return }
            tick(link.targetTimestamp)
        }
    }
}
