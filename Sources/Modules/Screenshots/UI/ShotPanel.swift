import AppKit

/// The after-shot window's panel. **Key only while the row is unfolded, and only from a click on itself**: that is
/// how Esc reaches the row, and Helm is not activated for it. The click that unfolds the pile is over when the row
/// exists, so the panel is made key at the mouse's coming up, not at its going down. Never key for another window's
/// click, nor when AppKit passes key on from a window that closed, nor with no event under way. Folded or single it
/// never takes key: a click on a thumbnail must not take the person's typing from the app they are in.
///
/// That `makeKey` from a mouse-up on a non-activating panel gives it the keys while another app stays active is
/// not measured.
final class ShotPanel: BorderlessPanel {
    var isUnfolded: () -> Bool = { false }

    override var canBecomeKey: Bool {
        ShotPanel.takesKey(from: NSApp.currentEvent, windowNumber: windowNumber, unfolded: isUnfolded())
    }

    static func takesKey(from event: NSEvent?, windowNumber: Int, unfolded: Bool) -> Bool {
        guard unfolded, let event else { return false }
        return (event.type == .leftMouseDown || event.type == .leftMouseUp) && event.windowNumber == windowNumber
    }
    override var canBecomeMain: Bool { false }
}
