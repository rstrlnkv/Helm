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

    /// The highest one an application's own window reaches: a floating panel (a
    /// utility palette, an inspector). Above it live the system's surfaces and
    /// status items and overlays, none of which is "a window" to Command-Shift-4
    /// and then Space, bar the two below.
    public static let highestLevel = Int(CGWindowLevelForKey(.floatingWindow))

    /// The menu bar's level, and the Dock's: the two system surfaces macOS offers
    /// as targets. Read from the system, never typed.
    public static let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
    public static let dockLevel = Int(CGWindowLevelForKey(.dockWindow))

    /// The process that draws the menu bar. Its name is fixed by the system. The
    /// Dock is not identified by name — Dock.app's display name is localised — but
    /// by its level alone.
    static let menuBarOwner = "Window Server"

    /// Whether this is the menu bar or the Dock, the two surfaces that are not
    /// application windows and are cut from the freeze, not asked for by id.
    /// The list is trusted to carry the Dock's window at the **strip's** frame
    /// (`DockStrip`), never at the sheet's: the ports file does that when it reads.
    public static func isSystemSurface(_ window: FrozenWindow) -> Bool {
        (window.layer == menuBarLevel && window.ownerName == menuBarOwner) || window.layer == dockLevel
    }

    /// Whether a person could mean this window by pointing at it: an ordinary or
    /// floating application window, the menu bar or the Dock strip, of a useful
    /// size. The one predicate every reader of the window list asks.
    public static func isPickable(_ window: FrozenWindow) -> Bool {
        ((lowestLevel...highestLevel).contains(window.layer) || isSystemSurface(window))
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
