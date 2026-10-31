import AppKit

/// The after-shot window's panel. **Key only while the row is unfolded, and only from a click on itself**: that is
/// how Esc reaches the row, and Helm is not activated for it. It is the pin's rule (`PinPanel.takesKey`) with one
/// more condition and one more event: the click that unfolds the pile is over when the row exists, so the panel is
/// made key at the mouse's coming up, not at its going down. Folded or single it never takes key: a click on a
/// thumbnail must not take the person's typing from the app they are in.
///
/// That `makeKey` from a mouse-up on a non-activating panel gives it the keys while another app stays active is
/// not measured; the pin's rule rests on the same call from a mouse-down.
final class ShotPanel: NSPanel {
    var isUnfolded: () -> Bool = { false }
    var onEscape: () -> Void = {}

    override var canBecomeKey: Bool {
        ShotPanel.takesKey(from: NSApp.currentEvent, windowNumber: windowNumber, unfolded: isUnfolded())
    }

    static func takesKey(from event: NSEvent?, windowNumber: Int, unfolded: Bool) -> Bool {
        guard unfolded, let event else { return false }
        return (event.type == .leftMouseDown || event.type == .leftMouseUp) && event.windowNumber == windowNumber
    }
    override var canBecomeMain: Bool { false }

    /// Esc.
    override func cancelOperation(_ sender: Any?) { onEscape() }

    override func keyDown(with event: NSEvent) {
        // Esc is also `cancelOperation`, but only when the responder chain gets that far.
        if event.keyCode == 53 { onEscape() } else { super.keyDown(with: event) }
    }
}
