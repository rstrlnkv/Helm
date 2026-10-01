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

/// What Accessibility said about the Dock's own bounds. **Every reason for "no
/// rectangle" is a case**, because the strip is the answer to the first two and
/// "hidden" is the answer to a rectangle that is not on a display.
public enum DockBoundsReading: Sendable, Equatable {
    /// The Dock's list element, in CG-global points (origin top left).
    case bounds(CGRect)
    /// This process has no Accessibility grant. The ordinary state: the module
    /// never asks for it, and nothing is logged.
    case notTrusted
    /// Trusted, and the Dock has no list element to read (not running yet, not
    /// answering, a layout this reading does not know).
    case noElement
    /// The Dock did not answer inside the read's budget (stopped, or busy beyond it). The
    /// strip is what is known, as for `noElement`; unlike it, this is the system refusing
    /// to answer, so the caller logs it.
    case timedOut
}

/// Where the Dock is and how its picture is made.
public struct DockPlacement: Sendable, Equatable {
    /// The pick rect, in CG-global points.
    public let rect: CGRect
    /// True when `rect` is the Dock's own bounds from Accessibility: the picture is then
    /// the system's capture of the Dock window (the Dock alone, its shadow, a clear
    /// ground — what Command-Shift-4 and Space makes) and not a cut from the freeze,
    /// which is the strip with the wallpaper behind it.
    public let drawnAlone: Bool

    public init(rect: CGRect, drawnAlone: Bool) {
        self.rect = rect
        self.drawnAlone = drawnAlone
    }
}

extension DockStrip {
    /// Accessibility's rectangle when it is on a display, else the strip, else no Dock.
    ///
    /// A rectangle that Accessibility gave and that is not mostly on a display is a
    /// Dock that hides itself and is hidden: **no Dock**, and not the strip, which
    /// would be a reading older than the one in hand. Without Accessibility, or with
    /// no element, the strip is what is known. `displays` are CG-global frames.
    public static func placement(_ reading: DockBoundsReading, displays: [CGRect], strip: CGRect?) -> DockPlacement? {
        switch reading {
        case .bounds(let rect):
            guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
                  rect.width >= WindowPick.smallest, rect.height >= WindowPick.smallest
            else { return strip.map { DockPlacement(rect: $0, drawnAlone: false) } }
            let shown = displays.contains { display in
                let part = rect.intersection(display)
                return !part.isNull && part.width * part.height * 2 >= rect.width * rect.height
            }
            return shown ? DockPlacement(rect: rect, drawnAlone: true) : nil
        case .notTrusted, .noElement, .timedOut:
            return strip.map { DockPlacement(rect: $0, drawnAlone: false) }
        }
    }
}

extension DockStrip {
    /// The Dock's process: the first window in the list that its own executable owns.
    /// Not the first window at the Dock's level, and not any other process's.
    public static func dockPID(_ entries: [RawWindow]) -> pid_t? {
        entries.first(where: \.ownedByDock)?.ownerPID
    }

    /// Asks `ports` about the Dock's process as `dockPID` names it, and places the
    /// answer. The one place the pid is chosen, so a test drives the choice.
    public static func placement(entries: [RawWindow], ports: DockBounds, displays: [CGRect], strip: CGRect?,
                                 onTimeout: () -> Void = {}) -> DockPlacement? {
        guard let pid = dockPID(entries) else { return nil }
        let reading = ports.read(dockPID: pid)
        if reading == .timedOut { onTimeout() }
        return placement(reading, displays: displays, strip: strip)
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
    /// of them, is listed at `dock`'s rect (placed by `DockStrip.placement`) instead of
    /// its sheet-sized frame; with no placement (a Dock that hides itself) it is not
    /// listed. Any other window at that level is dropped, never reframed: a rect there
    /// is the Dock's and nothing else's.
    public static func visible(_ raw: [RawWindow], excluding pid: pid_t, dock: DockPlacement?) -> [FrozenWindow] {
        var dockListed = false
        return raw.compactMap { entry in
            guard entry.ownerPID != pid, entry.alpha > 0 else { return nil }
            var frame = entry.frame
            var alone = false
            if entry.layer == WindowPick.dockLevel {
                guard entry.ownedByDock, !dockListed, let dock else { return nil }
                dockListed = true
                frame = dock.rect
                alone = dock.drawnAlone
            }
            return FrozenWindow(id: entry.number, frame: frame, layer: entry.layer, ownerName: entry.ownerName,
                                drawnAlone: alone)
        }
    }
}
