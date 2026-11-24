import AppKit

// MARK: - The panel

/// The capture overlay's panel: borderless, non-activating, at the screen-saver level.
///
/// An `NSMenu` popped up from it works, item, submenu and check mark alike, with Helm inactive. With the menu
/// closed `EditorKeys` selects tools by key code in any layout; with it open a `keyEquivalent` fires only in some
/// layouts, so the keys act with the menu closed. The palette is hosted by `EditorBarHostingView`.
final class OverlayPanel: BorderlessPanel {
    init(screen: NSScreen, view: NSView) {
        super.init(contentRect: screen.frame)
        // Above the menu bar and the Dock, over full-screen apps, in every Space.
        level = .screenSaver
        acceptsMouseMovedEvents = true
        contentView = view
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Called when this panel stops being key: the pointer went to another display, whose panel the overlay makes key.
    var onResignKey: (() -> Void)?
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
