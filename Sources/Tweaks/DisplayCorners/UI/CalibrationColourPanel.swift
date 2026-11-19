import AppKit
import HelmUI
import Tweak_DisplayCorners_Engine

/// The calibration colour's panel: `NSColorPanel.shared`, opened by the model and closed by it.
///
/// The panel's target is held here (`ColorPanelBridge`'s reason: the panel holds it weakly), and this object is held by
/// `DisplayCornersModel`, so the panel can be closed when the tweak goes off or the page is left, which a view could not
/// do once it was gone (`EditorColourPanel`, which this follows, says the same of its owner). The panel is shared with
/// the kit's swatch rows (`HelmPaletteSwatches`): `open` takes it over, and `close` puts back what it changed but the
/// colour, which stays as picked. The swatch row sets its own target and action each time it opens the panel, so it takes the
/// panel back from this object, and this one's close notice still ends the calibration if the panel is then closed.
///
/// Setting `color` by code fires the action, so the colour is set before the target and the action are. The panel is
/// continuous: the corners follow the wheel while somebody is dragging round it. It is shown with `makeKeyAndOrderFront`
/// and Helm is not activated for it (not measured here); `hidesOnDeactivate` is off for the time it is open,
/// because Helm is mostly an accessory app that is not active.
///
/// A person closing the panel is told by `NSWindow.willCloseNotification`; `close()` takes the observer off first and
/// orders the panel out, which posts none, so the model's own close is not told back.
@MainActor final class CalibrationColourPanel: CalibrationPanelSeam {
    private let bridge = ColorPanelBridge()
    /// What the panel was before `open` changed it; nil while it is not open.
    private var saved: (title: String, alpha: Bool, continuous: Bool, hides: Bool)?
    private var closing: NSObjectProtocol?
    private var onClosed: () -> Void = {}

    func open(showing colour: CalibrationColour, title: String,
              onPick: @escaping (Double, Double, Double) -> Void, onClosed: @escaping () -> Void) {
        let panel = NSColorPanel.shared
        if saved == nil {
            saved = (panel.title, panel.showsAlpha, panel.isContinuous, panel.hidesOnDeactivate)
        }
        stopWatching()
        panel.setTarget(nil)
        panel.color = NSColor(srgbRed: colour.red, green: colour.green, blue: colour.blue, alpha: 1)
        panel.title = title
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.hidesOnDeactivate = false
        // A colour the panel cannot give in sRGB is dropped; the engine clamps what is passed.
        bridge.onPick = { color in
            guard let rgb = color.usingColorSpace(.sRGB) else { return }
            onPick(Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
        }
        self.onClosed = onClosed
        closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel,
                                                         queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closedByPerson() }
        }
        panel.setTarget(bridge)
        panel.setAction(#selector(ColorPanelBridge.colourChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    /// Orders the panel out, drops its target and action, and gives back what `open` changed but the colour.
    func close() { release(orderOut: true) }

    isolated deinit { stopWatching() }

    private func closedByPerson() {
        let tell = onClosed
        release(orderOut: false)
        tell()
    }

    private func release(orderOut: Bool) {
        stopWatching()
        guard let saved else { return }
        self.saved = nil
        let panel = NSColorPanel.shared
        if orderOut { panel.orderOut(nil) }
        panel.setTarget(nil)
        panel.setAction(nil)
        bridge.onPick = { _ in }
        onClosed = {}
        panel.title = saved.title
        panel.showsAlpha = saved.alpha
        panel.isContinuous = saved.continuous
        panel.hidesOnDeactivate = saved.hides
    }

    private func stopWatching() {
        if let closing { NotificationCenter.default.removeObserver(closing) }
        closing = nil
    }
}
