import AppKit
import HelmUI
import Module_Screenshots_Engine

/// What opens the system's colour panel for the overlay, and puts it away: a protocol so that a test hands the overlay a fake and
/// no test opens the real `NSColorPanel`.
@MainActor protocol ColourPanelOpening: AnyObject {
    /// Shows the panel on `ink`; each colour it sends back, in sRGB, goes to `onPick`.
    func open(showing ink: AnnotationInk, onPick: @escaping (AnnotationInk) -> Void)
    /// Orders the panel out, drops its target and action, and gives back what `open` changed but the colour, which stays as picked.
    func close()
}

/// The colour wheel's panel: `NSColorPanel.shared`, raised over the overlay.
///
/// **Measured (macOS 27.2, a probe over the overlay):** with its defaults the panel does not show over the overlay; with
/// `level = .screenSaver + 1` and `hidesOnDeactivate = false` it stands above it, and showing it does not activate Helm. `makeKey` in an
/// inactive process gives the panel no key and takes it from the overlay, so it is never called here. Setting `color` by code fires the
/// action, so the colour is set before the target and the action are. After both windows are ordered out an activated process stays
/// frontmost, and only `previous.activate()` returns the focus. `NSApp.isActive` reads true under a key non-activating panel (one line of the
/// probe's output), so it cannot say whether Helm is frontmost at the close and `NSWorkspace`'s frontmost application is asked instead.
///
/// **Inferred, not measured:** that a real click on the panel activates Helm, which is what the `previous.activate()` branch of `close()`
/// stands on. **Never measured:** a real click or drag on the wheel, the panel's own eyedropper, a full-screen Space.
///
/// The panel's target is held here, by the object that opens it (`ColorPanelBridge`'s reason: the panel holds it weakly). The panel is shared
/// with the settings window's pickers, so what `open` changes besides the colour is remembered and put back by `close`, which drops the target and
/// the action and leaves the colour as picked; the colour panel is never kept on the screen by anything but the overlay.
@MainActor final class EditorColourPanel: ColourPanelOpening {
    private let bridge = ColorPanelBridge()
    /// What the panel was before `open` raised it, and who was frontmost; nil while it is not open.
    private var saved: (level: NSWindow.Level, hides: Bool, behaviour: NSWindow.CollectionBehavior, alpha: Bool, continuous: Bool,
                        previous: NSRunningApplication?)?

    func open(showing ink: AnnotationInk, onPick: @escaping (AnnotationInk) -> Void) {
        let panel = NSColorPanel.shared
        if saved == nil {
            saved = (panel.level, panel.hidesOnDeactivate, panel.collectionBehavior, panel.showsAlpha, panel.isContinuous, NSWorkspace.shared.frontmostApplication)
        }
        // The colour first: setting it fires the action, so no target is there to hear it.
        panel.setTarget(nil)
        panel.showsAlpha = false
        panel.isContinuous = false
        panel.color = NSColor(cgColor: ink.cgColor) ?? .red
        bridge.onPick = { color in if let ink = AnnotationInk(color.cgColor) { onPick(ink) } }
        panel.setTarget(bridge)
        panel.setAction(#selector(ColorPanelBridge.colourChanged(_:)))
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = OverlayPanel.behaviour
        panel.orderFrontRegardless()
    }

    func close() {
        guard let saved else { return }
        self.saved = nil
        let panel = NSColorPanel.shared
        panel.orderOut(nil)
        panel.setTarget(nil)
        panel.setAction(nil)
        bridge.onPick = { _ in }
        panel.level = saved.level
        panel.hidesOnDeactivate = saved.hides
        panel.collectionBehavior = saved.behaviour
        panel.showsAlpha = saved.alpha
        panel.isContinuous = saved.continuous
        if let previous = saved.previous, NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() {
            previous.activate()
        }
    }
}
