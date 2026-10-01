import Carbon.HIToolbox

/// A stored shortcut as Carbon will take it, or nothing.
///
/// The three keys `HelmHotkeyRecorder` writes are ordinary `Int`s in
/// `UserDefaults.standard` — `module.keep-awake.hotkey*` and
/// `module.layout.convertHotkey*` are live today — and `HotkeyManager.reload()`
/// turned them into the `UInt32`s `RegisterEventHotKey` wants with a bare
/// `UInt32(keyCode)`. That conversion **traps** on anything outside
/// `0..<2^32`, and the guard in front of it asked only `keyCode >= 0,
/// modifiers != 0`: `Int.max` walked through, and so did every negative
/// modifier. `reload()` runs from `applicationDidFinishLaunching`, so the
/// answer to `defaults write com.helm.app module.layout.convertHotkeyModifiers
/// -int -1` was an app that terminated at launch — with no window left to
/// correct the shortcut from.
///
/// The bounds are Carbon's own. `EventModifiers` is a `UInt16`
/// (`Events.h:105`) and the documented mask fills it, up to `rightControlKey`
/// at 0x8000; a key code is one byte of the classic event message
/// (`keyCodeMask = 0x0000FF00`), and the `kVK_` constants stop at 0x7E. The
/// recorder's own source is wider — `NSEvent.keyCode` is a `UInt16` — and a
/// code past the byte is refused rather than truncated: Carbon has no room to
/// mean it, and refusing leaves the shortcut unregistered instead of
/// registering a different key than the one that was pressed.
public struct HotkeyCombination {
    public let code: UInt32
    public let modifiers: UInt32

    /// The four modifiers a shortcut can be made of — the ones `label` spells.
    /// `EventModifiers` also carries the side-specific bits and `alphaLock`;
    /// none of those makes a key a shortcut, and a mask of only those is a
    /// bare letter everywhere in the system.
    private static let shortcutModifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    /// **The one predicate for "this can be a shortcut"**: at least one of the
    /// four. The recorder asks it of what it captured and `init?` of what it
    /// read, so the row can never draw a pair the recorder would have refused.
    public static func carriesAModifier(_ mask: Int) -> Bool {
        (1...0xFFFF).contains(mask) && UInt32(mask) & shortcutModifiers != 0
    }

    /// `nil` for a pair no shortcut can be made of — which includes the pair
    /// `HelmHotkeyRecorder.clear()` writes for "no shortcut" (-1 and 0), and a
    /// key with no modifier at all, which would swallow an ordinary letter
    /// everywhere in the system.
    ///
    /// Zero is a key: `kVK_ANSI_A` is 0, so the empty field has to be spelled
    /// by the *modifiers* rather than by the code.
    public init?(keyCode: Int, modifiers: Int) {
        guard (0...0xFF).contains(keyCode), Self.carriesAModifier(modifiers) else { return nil }
        self.code = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
    }

    /// The shortcut spelled the way the recorder spells one, for a pair that
    /// has no `<prefix>Label` beside it: the label is a key of its own, and a
    /// hand-edited or half-written store can hold a pair the manager registers
    /// with nothing to draw in its row.
    ///
    /// The key is named by its place on an ANSI keyboard, and not by the
    /// person's layout: asking the layout means the text-input services, which
    /// this row has no business waking for a file nobody meant to write by
    /// hand. A code the table does not hold is written as `#code`, so the row
    /// still says *something is registered*.
    public var label: String {
        var out = ""
        if modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { out += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { out += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { out += "⌘" }
        return out + (Self.keyNames[Int(code)] ?? "#\(code)")
    }

    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Backslash: "\\", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "␣", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}
