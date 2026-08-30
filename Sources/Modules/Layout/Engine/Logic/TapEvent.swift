import Carbon.HIToolbox
import Foundation

/// What a key press is, before the tap looks at what it types.
///
/// **Pure, because the order of two questions here costs text.** The port asked
/// «is a modifier held» first and reported `.chord` if it was, so ⌘←, ⌥←, ⌘↑
/// and ⌥Delete never reached the keycode switch below them. A chord spends
/// `UndoRecord.soften()`'s single forgiveness instead of invalidating, and its
/// `movedTheCaret` is false, so the word it ended was stored: type `ghbdtn `,
/// watch it become `привет `, press ⌥Delete to take that word out, then tap the
/// bound key — the undo was still live, and seven backspaces plus `ghbdtn `
/// landed in text the module had never looked at.
///
/// Written here rather than inside `CGKeyTap.deliver`, which is private and
/// takes a `CGEvent`, so the arrangement could not be asked a question by any
/// test. It can now.
public enum TapEvent {

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
    /// **A modified caret key is `.navigation`, not `.chord`, and that is the
    /// whole point of the ordering.** It costs one thing and it is named where
    /// it is paid: somebody who records ⌘← as their fix hotkey loses the
    /// forgiveness that exists because the head-inserted tap sees the hotkey's
    /// own keys before Carbon dispatches the action, so their gesture stops
    /// firing. Annoying, and the safe direction — the other way round destroys
    /// text for everyone who deletes a word with ⌥Delete.
    public static func classify(keycode: Int, modified: Bool) -> TypingBuffer.Event? {
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
