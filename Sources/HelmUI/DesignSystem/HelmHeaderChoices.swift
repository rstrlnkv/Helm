import SwiftUI

/// **The three stored choices about the settings window's header row that the row itself draws by: whether the
/// page's name wears its plate, how its tabs are labelled, and whether its search rests as a magnifier.**
///
/// Their keys and raw values are the ones of the toolbar's day, so a Mac that chose any before reads the
/// same choice after (`ObsoleteDefaults` no longer purges them).
///
/// **Not sealed:** nothing unattended reads any (`AppSettings.pageBarStyle`, `AppSettings.toolbarSwitcherStyle`,
/// `AppSettings.alwaysCollapseSearch`).
///
/// - `moduleName` — "With Icon": the plate, then the name; today's row.
/// - `windowTitle` — "Without Icon": the name alone. The status after the name stays (the owner's decision;
///   the toolbar's `windowTitle` dropped it).
public enum PageBarStyle: String, CaseIterable, Sendable {
    case windowTitle, moduleName

    public static let storageKey = "pageBarStyle"

    /// Anything unknown, including nothing stored, is `moduleName`.
    public init(stored: String) {
        self = PageBarStyle(rawValue: stored) ?? .moduleName
    }
}

/// How the header row's tabs are labelled.
///
/// - `text` — each tab its word.
/// - `icons` — a glyph per tab, the word in the tooltip and to VoiceOver.
/// - `iconsAndText` — a glyph beside each word.
///
/// A fourth, `iconsNamingSelected`, lived for a day and was cut on 2026-09-18: it is not a case and reads
/// back as `text`, as does anything `init(stored:)` does not know.
public enum ToolbarSwitcherStyle: String, CaseIterable, Sendable {
    case text, icons, iconsAndText

    public static let storageKey = "toolbarSwitcherStyle"

    /// Anything unknown, including nothing stored, is `text`.
    public init(stored: String) {
        self = ToolbarSwitcherStyle(rawValue: stored) ?? .text
    }
}

/// What the header row reads from the environment: the choices as one value, so one notification and one
/// tracker carry them.
public struct HelmHeaderChoices: Equatable, Sendable {
    public var pageBar: PageBarStyle
    public var tabLabels: ToolbarSwitcherStyle
    /// "Always Collapse Search": the page's search rests as a magnifier unless it holds a query or is being edited.
    public var collapseSearch: Bool

    public init(pageBar: PageBarStyle, tabLabels: ToolbarSwitcherStyle, collapseSearch: Bool = false) {
        self.pageBar = pageBar
        self.tabLabels = tabLabels
        self.collapseSearch = collapseSearch
    }

    /// What a view mounted with nobody having set a choice gets: the row as it was drawn before the choices existed.
    public static let standard = HelmHeaderChoices(pageBar: .moduleName, tabLabels: .text, collapseSearch: false)
}

extension Notification.Name {
    /// Posted by `AppSettings` after a choice is written, by General's rows and by the row's own menu alike.
    public static let helmHeaderChoicesChanged = Notification.Name("helmHeaderChoicesChanged")
}

extension EnvironmentValues {
    @Entry public var helmHeaderChoices: HelmHeaderChoices = .standard
}

extension View {
    /// Sets `helmHeaderChoices` from `current` and again whenever `.helmHeaderChoicesChanged` is posted. Set only
    /// at the settings pane's root, and **never as an identity** (`.id`): the page below is not rebuilt for
    /// a choice it does not draw, and under `.flat` (and on Launchpad) the row's tabs keep their sliding pick.
    public func helmTracksHeaderChoices(_ current: @escaping () -> HelmHeaderChoices) -> some View {
        modifier(HelmHeaderChoicesTracker(current: current))
    }
}

private struct HelmHeaderChoicesTracker: ViewModifier {
    let current: () -> HelmHeaderChoices
    @State private var choices: HelmHeaderChoices?

    func body(content: Content) -> some View {
        content
            .environment(\.helmHeaderChoices, choices ?? current())
            .onReceive(NotificationCenter.default.publisher(for: .helmHeaderChoicesChanged)) { _ in
                choices = current()
            }
    }
}
