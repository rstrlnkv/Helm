import HelmRuntime

/// The three buttons at the foot of the panel — Settings, the pencil, Quit —
/// each its own switch, and the one key they were folded into for a build.
///
/// **The fold is undone, and undoing it is not symmetrical.** Folding was
/// lossless in one direction only: `showsFooter` was
/// `showSettingsButton || showQuitButton || showEditButton`, so three switches
/// turned off by hand became `false`, and every other arrangement became `true`.
/// Coming back, `false` is therefore the one answer that was really given, and
/// the only one worth writing: it is restored to all three. `true`, or a key
/// never written at all, is the shipped default said out loud, and the three
/// keys are left alone to say it themselves.
///
/// The keys are named here rather than at each property, so the switch that
/// reads one, the migration that writes it and the purge list that must **not**
/// name it are looking at the same string.
enum PanelFooterSetting {

    /// The key the three were folded into. Read once more at every launch, by
    /// the migration, and retired in the same pass — `ObsoleteDefaults.retired`
    /// names it again, namespaced, because a purge must be able to reach a key
    /// whose code is gone.
    static let foldedKey = "showPanelFooter"

    /// An enum rather than three strings positionally: the unfold takes three
    /// `Bool?`s that are indistinguishable at a call site.
    enum Button: String, CaseIterable {
        case settings = "showSettingsButton"
        case edit = "showPanelEditButton"
        case quit = "showQuitButton"
    }

    /// Whether one of the three is drawn.
    ///
    /// **Default true**, which is the whole difference from the first version of
    /// these settings, deleted long before the fold: those defaulted to *false*,
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

    /// What the three keys should be written as when the fold is undone, or nil
    /// when there is nothing to write.
    ///
    /// - Parameters:
    ///   - folded: the key of the build that had one switch, or nil.
    ///   - settings, quit, edit: the three keys as they stand, each nil if never
    ///     written. Any one of them present means this Mac has already been
    ///     through the restoration and has been answering for itself since; a
    ///     stale fold must not speak over it.
    static func unfolded(folded: Bool?, settings: Bool?, quit: Bool?, edit: Bool?) -> Bool? {
        guard settings == nil, quit == nil, edit == nil else { return nil }
        // Only the deliberate «off» survived the fold. Everything else is the
        // default, and the default needs no key.
        return folded == false ? false : nil
    }

    /// Puts the three keys back from the fold, if there is anything to put back.
    ///
    /// Here rather than in `AppSettings` because the keys are here: a caller
    /// that had to spell `Button.settings.rawValue` to read one is a second
    /// place the storage layout is written down.
    static func restore(in store: NamespacedStore) {
        func written(_ button: Button) -> Bool? { store.object(button.rawValue) as? Bool }
        guard let value = unfolded(folded: store.object(foldedKey) as? Bool,
                                   settings: written(.settings), quit: written(.quit),
                                   edit: written(.edit))
        else { return }
        for button in Button.allCases { store.set(value, for: button.rawValue) }
    }
}
