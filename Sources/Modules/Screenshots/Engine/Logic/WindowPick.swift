import CoreGraphics

/// Which window a click in window mode means.
public enum WindowPick {

    /// A window smaller than this in either direction is not something a person
    /// points at: the system keeps a scatter of one-pixel helper windows on
    /// screen, and the topmost of them under the pointer is nearly always one.
    public static let smallest: CGFloat = 8

    /// The lowest window level a person points at: an ordinary application window.
    /// Read from `CGWindowLevelForKey` once, so the bound is the system's own and
    /// not a number copied from a header. The wallpaper and the desktop icons sit
    /// below it.
    public static let lowestLevel = Int(CGWindowLevelForKey(.normalWindow))

    /// The highest one: a floating panel (a utility palette, an inspector). Above
    /// it live the Dock (a full-screen transparent sheet at its own level), the
    /// menu bar, status items and overlays, none of which is "a window" to
    /// Command-Shift-4 and then Space.
    public static let highestLevel = Int(CGWindowLevelForKey(.floatingWindow))

    /// The two processes whose windows are the system's furniture, whatever level
    /// they claim. Names are fixed by the system, not localised.
    static let furniture: Set<String> = ["Dock", "Window Server"]

    /// Whether a person could mean this window by pointing at it: an ordinary or
    /// floating application window of a useful size, not the system's furniture.
    /// The one predicate every reader of the window list asks.
    public static func isPickable(_ window: FrozenWindow) -> Bool {
        (lowestLevel...highestLevel).contains(window.layer)
            && !furniture.contains(window.ownerName)
            && window.frame.width >= smallest && window.frame.height >= smallest
    }

    /// The frontmost pickable window under `point` (CG-global points), from a
    /// list that is ordered front to back.
    public static func window(at point: CGPoint, in windows: [FrozenWindow]) -> FrozenWindow? {
        windows.first { isPickable($0) && $0.frame.contains(point) }
    }

    /// The display a window belongs to for a crop, and the part of the window on it.
    ///
    /// A window that straddles two displays is cut from the one that holds more
    /// of it: a selection is bounded to one display, and so is a picture cut
    /// from a freeze, which has one image per display. `displays` are in
    /// CG-global points.
    public static func home(of window: CGRect, among displays: [(id: DisplayID, frame: CGRect)])
        -> (id: DisplayID, part: CGRect)? {
        var best: (id: DisplayID, part: CGRect, area: CGFloat)?
        for display in displays {
            let part = window.intersection(display.frame)
            guard !part.isNull, part.width > 0, part.height > 0 else { continue }
            let area = part.width * part.height
            if best == nil || area > best!.area { best = (display.id, part, area) }
        }
        return best.map { ($0.id, $0.part) }
    }
}
