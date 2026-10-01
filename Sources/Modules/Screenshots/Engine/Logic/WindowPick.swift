import CoreGraphics

/// Which window a click in window mode means.
public enum WindowPick {

    /// A window smaller than this in either direction is not something a person
    /// points at: the system keeps a scatter of one-pixel helper windows on
    /// screen, and the topmost of them under the pointer is nearly always one.
    public static let smallest: CGFloat = 8

    /// The frontmost window under `point` (CG-global points), from a list that is
    /// ordered front to back.
    ///
    /// Only layer 0 and above: the wallpaper and the desktop icons sit below it
    /// and are not a window a person means.
    public static func window(at point: CGPoint, in windows: [FrozenWindow]) -> FrozenWindow? {
        windows.first {
            $0.layer >= 0 && $0.frame.width >= smallest && $0.frame.height >= smallest
                && $0.frame.contains(point)
        }
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
