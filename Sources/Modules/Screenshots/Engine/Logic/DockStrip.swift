import CoreGraphics

/// Where the Dock is actually drawn.
///
/// The Dock owns one transparent window the size of its whole display, at its own
/// window level, so that rect is never what a person means by "the Dock". What
/// they mean is the strip the system reserves for it, and that is what the
/// display's `visibleFrame` gives up: the inset on the Dock's edge. No grant is
/// needed to read it. A Dock that hides itself reserves nothing and has no strip.
public enum DockStrip {

    /// The strip on one display, in CG-global points (origin top left), or nil when
    /// the display reserves nothing for the Dock.
    ///
    /// `frame` and `visible` are the display's `frame` and `visibleFrame` as AppKit
    /// gives them (origin bottom left, global); `primaryHeight` is the height of the
    /// display that holds the origin, which is what turns one spelling into the
    /// other. The top inset is the menu bar's and is not read: the Dock is on the
    /// bottom, the left or the right.
    public static func rect(frame: CGRect, visible: CGRect, primaryHeight: CGFloat) -> CGRect? {
        let left = visible.minX - frame.minX
        let right = frame.maxX - visible.maxX
        let bottom = visible.minY - frame.minY
        let widest = max(left, right, bottom)
        guard widest > 0, widest.isFinite else { return nil }
        let strip: CGRect
        if widest == bottom {
            strip = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: bottom)
        } else if widest == left {
            strip = CGRect(x: frame.minX, y: frame.minY, width: left, height: frame.height)
        } else {
            strip = CGRect(x: visible.maxX, y: frame.minY, width: right, height: frame.height)
        }
        return CGRect(x: strip.minX, y: primaryHeight - strip.maxY, width: strip.width, height: strip.height)
    }

    /// The strip of the first display, in the order given, that gives up room for
    /// the Dock; nil when none does. `displays` are AppKit `frame` / `visibleFrame`
    /// pairs, the first holding the origin. Later displays are not read once one has
    /// answered: the Dock is on one display.
    public static func rect(displays: [(frame: CGRect, visible: CGRect)]) -> CGRect? {
        guard let primary = displays.first else { return nil }
        return displays.lazy.compactMap {
            rect(frame: $0.frame, visible: $0.visible, primaryHeight: primary.frame.height)
        }.first
    }
}

/// One entry of the window list as the system gave it, before anything is judged.
public struct RawWindow: Equatable {
    public let number: UInt32
    public let layer: Int
    public let ownerPID: pid_t
    public let ownerName: String
    public let alpha: Double
    public let frame: CGRect
    /// Whether the owning process is the Dock itself (its executable), which is
    /// what a window at the Dock's level is not enough to say.
    public let ownedByDock: Bool

    public init(number: UInt32, layer: Int, ownerPID: pid_t, ownerName: String = "",
                alpha: Double = 1, frame: CGRect, ownedByDock: Bool = false) {
        self.number = number
        self.layer = layer
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.alpha = alpha
        self.frame = frame
        self.ownedByDock = ownedByDock
    }
}

public enum WindowListing {

    /// What the picker sees, front to back: not `pid`'s own, not transparent.
    ///
    /// At the Dock's level the rule is: the Dock's own window, and only the first
    /// of them, is listed at `strip` instead of its sheet-sized frame; with no strip
    /// (a Dock that hides itself) it is not listed. Any other window at that level
    /// is dropped, never reframed: a strip is the Dock's and nothing else's.
    public static func visible(_ raw: [RawWindow], excluding pid: pid_t, dockStrip strip: CGRect?) -> [FrozenWindow] {
        var dockListed = false
        return raw.compactMap { entry in
            guard entry.ownerPID != pid, entry.alpha > 0 else { return nil }
            var frame = entry.frame
            if entry.layer == WindowPick.dockLevel {
                guard entry.ownedByDock, !dockListed, let strip else { return nil }
                dockListed = true
                frame = strip
            }
            return FrozenWindow(id: entry.number, frame: frame, layer: entry.layer, ownerName: entry.ownerName)
        }
    }
}
