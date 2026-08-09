import HelmRuntime

/// What the module draws in the menu bar, and what it draws when nobody has
/// said otherwise.
///
/// Six settings, and every one of them was spelled out twice: once where the
/// settings page seeds its state, once where the descriptor builds the status
/// item — plus `activeTintColor` a third time, in `KeepAwakeSettings`, which
/// the engine never reads. Three files, one key, three copies of its default.
/// A drift in any of them shows the page one thing and draws the menu bar
/// another, and nothing in the build would say so.
///
/// This lives in the UI target because the engine reads none of it: what the
/// menu bar looks like is not a fact the module acts on.
enum MenuBarLook {

    /// Written where the page seeds and read where the item is drawn, so the
    /// key and its default cannot come apart.
    enum Key {
        static let activeTint = "activeTintColor"
        static let ringTimer = "ringTimer"
        static let showTimerText = "showTimerText"
        static let timerTint = "timerTintColor"
        static let customIcon = "customActiveIcon"
        static let iconShape = "activeIconShape"
    }

    static func activeTint(_ store: NamespacedStore) -> String {
        store.string(Key.activeTint, default: "orange")
    }
    /// On by default: a countdown nobody asked to hide is the reason a timed
    /// session is visible at all.
    static func ringTimer(_ store: NamespacedStore) -> Bool {
        store.bool(Key.ringTimer, default: true)
    }
    static func showTimerText(_ store: NamespacedStore) -> Bool {
        store.bool(Key.showTimerText, default: false)
    }
    /// Orange, the same as `activeTint` above — so out of the box a countdown
    /// looks like the module rather than like something wrong.
    ///
    /// It was `red`, and red is `HelmSignal.danger`: a session running normally
    /// was painted in the app's own failure colour, and the page showed two
    /// palettes disagreeing — orange ringed under «Active icon color», red
    /// ringed under «Timer color», neither of them chosen by anybody.
    ///
    /// **This value is always applied**, and the two comments that said
    /// otherwise are corrected where they stand: a stored tint is never empty,
    /// so the reader in `KeepAwakeDescriptor` has no fallback path to take.
    /// Changing the active colour therefore does not change the countdown's —
    /// that is a second decision, and it is the person's to make in the row
    /// below it.
    static func timerTint(_ store: NamespacedStore) -> String {
        store.string(Key.timerTint, default: "orange")
    }
    static func customIcon(_ store: NamespacedStore) -> Bool {
        store.bool(Key.customIcon, default: false)
    }
    static func iconShape(_ store: NamespacedStore) -> String {
        store.string(Key.iconShape, default: "ring")
    }
}
