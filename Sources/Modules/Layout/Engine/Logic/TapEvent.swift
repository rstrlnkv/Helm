import Carbon.HIToolbox
import Foundation

/// What a key press is, before the tap looks at what it types.
///
/// Pure, because the order of two questions here costs text. A caret key held
/// with a modifier (⌘←, ⌥←, ⌘↑, ⌥Delete) is navigation, checked before «is a
/// modifier held»: reported as `.chord` it would spend `UndoRecord.soften()`'s
/// single forgiveness and leave the undo live after ⌥Delete took the word out.
/// Only the chord on the recorded hotkey's key is forgiven; any other chord
/// invalidates the undo and drops the stored word (`LayoutEngine.handle`).
///
/// Here rather than inside `CGKeyTap.deliver`, which is private and takes a
/// `CGEvent`, so a test can ask it.
enum TapEvent {

    /// The keys that move the caret or delete backwards. Held with ⌘, ⌥ or ⌃
    /// they still do — ⌥Delete removes the word before the caret, ⌘← goes to
    /// the start of the line — so the modifier changes the distance, never the
    /// fact.
    private static let caretKeys: Set<Int> = [
        kVK_Delete, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
    ]

    /// The event for a key press, or nil when the answer depends on what the
    /// key types and the caller must read the unicode string.
    ///
    /// A modified caret key is `.navigation`, not `.chord`. It costs one thing and it is named where
    /// it is paid: somebody who records ⌘← as their fix hotkey loses the
    /// forgiveness that exists because the head-inserted tap sees the hotkey's
    /// own keys before Carbon dispatches the action, so their gesture stops
    /// firing. Annoying, and the safe direction — the other way round destroys
    /// text for everyone who deletes a word with ⌥Delete.
    static func classify(keycode: Int, modified: Bool) -> TypingBuffer.Event? {
        if modified {
            return caretKeys.contains(keycode) ? .navigation : .chord(UInt16(keycode))
        }
        switch keycode {
        case kVK_Delete: return .backspace
        case kVK_Space: return .space
        case kVK_Return, kVK_ANSI_KeypadEnter: return .newline
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_Escape, kVK_Tab:
            return .navigation
        default: return nil
        }
    }
}
