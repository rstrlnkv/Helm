import AppKit

/// What the module's floating panels share: borderless, non-activating, clear, no shadow of its own, kept when
/// closed, in every Space and over full-screen apps. Each subclass sets its level, its keys and what else it differs in.
class BorderlessPanel: NSPanel {
    /// Every Space and full-screen apps; the colour panel that stands over the overlay (`EditorColourPanel`) takes the same.
    static let behaviour: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    /// One above `.screenSaver`, the overlay's: what stands over the overlay.
    static let aboveOverlay = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)

    /// Esc; a panel that is given none leaves the key to AppKit.
    var onCancel: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        collectionBehavior = Self.behaviour
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override func cancelOperation(_ sender: Any?) {
        if let onCancel { onCancel() } else { super.cancelOperation(sender) }
    }

    override func keyDown(with event: NSEvent) {
        // Esc is also `cancelOperation`, but only when the responder chain gets that far.
        if event.keyCode == ShotKey.escape, let onCancel { onCancel() } else { super.keyDown(with: event) }
    }
}
