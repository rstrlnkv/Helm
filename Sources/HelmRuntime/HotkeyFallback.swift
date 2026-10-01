import Foundation

/// The shortcut a module ships with, for a key nobody has recorded yet.
///
/// **Absent and cleared are two different answers.** `HelmHotkeyRecorder.clear()`
/// writes `-1` into the store, and an untouched store holds nothing at all; a
/// reader that folds both into "no shortcut" can never offer a default, and a
/// reader that folds both into "the default" can never let somebody have none.
/// The fallback applies only to the second, so a person who cleared a shortcut
/// keeps the empty row they asked for.
///
/// Plain integers and a string because three targets need it and only this one
/// is under all of them: the engine names a module's defaults, the host
/// registers them, and the recorder row draws the label. `modifiers` is
/// Carbon's mask, which is what `HotkeyCombination` takes.
public struct HotkeyFallback: Equatable, Sendable {
    public let keyCode: Int
    public let modifiers: Int
    public let label: String

    public init(keyCode: Int, modifiers: Int, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }
}
