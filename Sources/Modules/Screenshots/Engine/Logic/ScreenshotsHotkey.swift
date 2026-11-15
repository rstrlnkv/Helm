import HelmRuntime

/// The shortcuts this module registers with the host, named once.
///
/// **Two halves of one name.** The host files the binding under `slot` and the
/// page asks `HotkeyStatus` about the same string; `storePrefix` is where the
/// recorded combination lives, read by the host's registration and written by
/// the page's recorder. A rename on one side leaves a row that draws a
/// shortcut pressing which does nothing, so both are declared here and read
/// from here.
///
/// **Deployed stored data: a store prefix never moves.** A new shortcut takes a
/// new prefix.
///
/// Only shortcuts that do something exist: a recorder for an action that is not
/// built would be a row drawing a shortcut that does nothing.
public enum ScreenshotsHotkey: String, CaseIterable, Sendable {
    case area
    case fullScreen
    /// Opens the capture panel — the bar with the mode buttons, the options and
    /// the timer. It takes no capture of its own.
    case panel

    /// The slot `HotkeyManager` files the binding under.
    public var slot: String { "\(ScreenshotsEngine.moduleID).\(rawValue)" }

    /// `<prefix>KeyCode`, `<prefix>Modifiers`, `<prefix>Label` in the module's store.
    public var storePrefix: String { "\(rawValue)Hotkey" }

    /// ⌘⇧1 for the whole screen, ⌘⇧2 for an area and ⌘⇧8 for the panel. None is
    /// macOS's own (those are ⌘⇧3, ⌘⇧4 and ⌘⇧5, and ⌘⇧6 and ⌘⇧7 are taken too —
    /// `TheSystemDefaultsAreMacOSsOwnTests` reads the table), so the module works the
    /// moment it is switched on, without asking anybody to untick anything
    /// first; ⌘⇧5 goes to the panel only through the page's button, and only
    /// once macOS's own box for it is read as off. The label is spelled the way
    /// `HotkeyCombination.label` spells it.
    public var fallback: HotkeyFallback {
        switch self {
        case .fullScreen: HotkeyFallback(keyCode: 18, modifiers: CarbonModifier.cmd | CarbonModifier.shift, label: "⇧⌘1")
        case .area: HotkeyFallback(keyCode: 19, modifiers: CarbonModifier.cmd | CarbonModifier.shift, label: "⇧⌘2")
        case .panel: HotkeyFallback(keyCode: 28, modifiers: CarbonModifier.cmd | CarbonModifier.shift, label: "⇧⌘8")
        }
    }
}
