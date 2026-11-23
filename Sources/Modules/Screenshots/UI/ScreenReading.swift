import AppKit
import Module_Screenshots_Engine

extension NSScreen {
    /// The screen whose frame holds the pointer, nil when none does: a caller that must place something falls back to `main`.
    static var underPointer: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouse) }
    }

    /// The display this screen is, from the system's own `NSScreenNumber`; nil when it gives none.
    var displayID: DisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32).map { DisplayID($0) }
    }
}
