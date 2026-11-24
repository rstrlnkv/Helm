import HelmRuntime

/// The three buttons at the foot of the panel — Settings, the pencil, Quit —
/// each its own switch.
///
/// The keys are named here rather than at each call site, so the switch that
/// reads one and the purge list that must **not** name it are looking at the
/// same string.
enum PanelFooterSetting {

    /// An enum rather than three strings: the keys are indistinguishable at a call site.
    enum Button: String, CaseIterable {
        case settings = "showSettingsButton"
        case edit = "showPanelEditButton"
        case quit = "showQuitButton"
    }

    /// Whether one of the three is drawn.
    ///
    /// **Default true**, which is the whole difference from the first version of
    /// these settings, deleted long ago: those defaulted to *false*,
    /// so a clean install got a panel with no way into settings and no way to
    /// find the switch that would have added one. Safe to hide, because none of
    /// the three is the only way to what it does — the menu-bar icon's
    /// right-click menu carries all of them and cannot be switched off.
    ///
    /// Takes the store rather than reaching for `AppSettings`', so the answer a
    /// panel draws from can be asked of a store a test owns.
    static func shows(_ button: Button, in store: NamespacedStore) -> Bool {
        store.bool(button.rawValue, default: true)
    }
}
