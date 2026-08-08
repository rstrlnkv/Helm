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

    /// `nil` for a pair no shortcut can be made of — which includes the pair
    /// `HelmHotkeyRecorder.clear()` writes for "no shortcut" (-1 and 0), and a
    /// key with no modifier at all, which would swallow an ordinary letter
    /// everywhere in the system.
    ///
    /// Zero is a key: `kVK_ANSI_A` is 0, so the empty field has to be spelled
    /// by the *modifiers* rather than by the code.
    public init?(keyCode: Int, modifiers: Int) {
        guard (0...0xFF).contains(keyCode), (1...0xFFFF).contains(modifiers) else { return nil }
        self.code = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
    }
}
