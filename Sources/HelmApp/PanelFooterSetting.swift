import Foundation

/// Whether the panel draws its footer — folded out of the three switches that
/// used to ask it separately.
///
/// «Show Settings button», «Show the edit button in the panel» and «Show Quit
/// button» were three rows for one taste. The panel never treated them as three:
/// its `showsFooter` was `showSettingsButton || showQuitButton || showEditButton`,
/// because a footer with all three hidden is an empty card, and the arithmetic
/// that takes the footer's height off the grid has already shipped one defect for
/// exactly that reason — hiding the last button left 38 pt reserved under a
/// footer that was no longer drawn, and a panel that had fitted began to scroll.
///
/// **The fold is that expression**, so the switch a person had is the switch they
/// have. Each of the three defaulted to *true* — the version of these settings
/// before them defaulted to false, which gave a clean install a panel with no way
/// into settings and no way to find the switch that would have added one — so an
/// absent key is a button that was shown, and only three deliberate «off»s make a
/// panel that had no footer keep none.
enum PanelFooterSetting {

    /// The stored key, named here so the property that reads it and the
    /// migration that writes it cannot be renamed apart.
    static let key = "showPanelFooter"

    /// The keys this replaced. They are read exactly once, by the migration, and
    /// retired in the same launch — `ObsoleteDefaults.retired` names them again,
    /// because a purge must be able to reach a key whose code is gone.
    ///
    /// An enum rather than three strings positionally: the fold takes three
    /// `Bool?`s that are indistinguishable at a call site.
    enum Replaced: String, CaseIterable {
        case settings = "showSettingsButton"
        case edit = "showPanelEditButton"
        case quit = "showQuitButton"
    }

    /// - Parameters:
    ///   - stored: the new key, or nil if it has never been written.
    ///   - settings, quit, edit: the three old keys, each nil if never written.
    static func folded(stored: Bool?, settings: Bool?, quit: Bool?, edit: Bool?) -> Bool {
        if let stored { return stored }
        // Every one of the three defaulted to true, so nil is «shown».
        return (settings ?? true) || (quit ?? true) || (edit ?? true)
    }
}
