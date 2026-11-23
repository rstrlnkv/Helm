import AppKit
import QuartzCore
import Tweak_DisplayCorners_Engine

/// **One mask window: a borderless, click-through square at a corner of a display.**
///
/// A plain `NSWindow`, not a panel: a panel hides when the app is not active, and Helm is mostly an accessory
/// app that is not. `hidesOnDeactivate` and `canHide` are set off as well, which the standalone app did not
/// set, and which has not been measured. It is ordered by `orderFrontRegardless`, never made key or main.
///
/// `constrainFrameRect` returns the rect as given, so a top mask stands over the menu bar. The engine finds a
/// mask at rest by its window bounds being exactly the spec's frame, so the window is put at `spec.frame` and
/// nowhere else. `sharingType` stays at its default: `CaptureShield` is what is meant to keep the mask out of
/// screenshots. What the engine samples is only whether the window is on screen, its number and its bounds; what
/// another sharing type would do to that is not measured.
///
/// Levels: the bottom masks `.floating`, the top ones one above `.statusBar`. The collection behaviour is the
/// standalone app's: on every Space and in their animations (`.canJoinAllSpaces`, `.managed`, never `.stationary`,
/// so a Space slide moves the masks and the engine can see it), out of the Cycle Through Windows list (`.ignoresCycle`), and absent from a
/// native full-screen Space (`.fullScreenNone`).
@MainActor final class CornerMaskWindow: NSWindow {
    static let behaviour: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .managed, .ignoresCycle, .fullScreenNone]

    static func level(topLevel: Bool) -> NSWindow.Level {
        topLevel ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) : .floating
    }

    let maskView: CornerMaskView

    init(spec: MaskSpec) {
        maskView = CornerMaskView(spec: spec)
        super.init(contentRect: spec.frame, styleMask: .borderless, backing: .buffered, defer: false)
        // The owner closes it with `close()`; a window that released itself there would be freed twice.
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        animationBehavior = .none
        hidesOnDeactivate = false
        canHide = false
        isExcludedFromWindowsMenu = true
        level = Self.level(topLevel: spec.topLevel)
        collectionBehavior = Self.behaviour
        contentView = maskView
        setFrame(spec.frame, display: false)
    }

    /// Moves, re-levels and repaints this window for a changed spec; it does not order it.
    func apply(_ spec: MaskSpec) {
        if frame != spec.frame {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            setFrame(spec.frame, display: false)
            CATransaction.commit()
        }
        let level = Self.level(topLevel: spec.topLevel)
        if self.level != level { self.level = level }
        maskView.apply(spec)
    }

    func tearDown() {
        orderOut(nil)
        maskView.stop()
        contentView = nil
        close()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
