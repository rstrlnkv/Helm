import AppKit

// MARK: - The panel

/// The capture overlay's panel: borderless, non-activating, at the screen-saver level.
///
/// What was measured of a menu and tooltips over it (2026-10-02/03, Helm inactive, real keyboard): an `NSMenu`
/// popped up from the editor's bar (the two bars, before 43704363, which replaced them with the palette) works: an item click and a submenu item click both land, and the
/// checkmark is drawn. With the menu closed, `EditorKeys` selects tools by key code, in the US and the Russian layout alike (the two measured);
/// with it open, a `keyEquivalent` "a" fired in the US layout and not in the Russian one. Tooltips (`.help`) were not
/// shown on the cells of those two bars, and the overlay forces the crosshair on every move (its cursor sets climbed by hundreds per
/// open). Not yet measured: whether that forced crosshair is what hides the tooltips, and whether a menu
/// item's SF Symbol image is drawn on its own (it was not, beside `state = .on`). The palette is hosted by `EditorBarHostingView`.
final class OverlayPanel: NSPanel {
    /// Every Space and full-screen apps; the colour panel that stands over the overlay (`EditorColourPanel`) takes the same.
    static let behaviour: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

    init(screen: NSScreen, view: NSView) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        // Above the menu bar and the Dock, over full-screen apps, in every Space.
        level = .screenSaver
        collectionBehavior = Self.behaviour
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
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
