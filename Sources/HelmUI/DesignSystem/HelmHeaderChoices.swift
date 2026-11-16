import SwiftUI

/// **The two stored choices about the settings window's header row that the row itself draws by: whether the
/// page's name wears its plate, and how its tabs are labelled.**
///
/// Their keys and raw values are the ones of the toolbar's day, so a Mac that chose either before reads the
/// same choice after (`ObsoleteDefaults` no longer purges them).
///
/// **Not sealed:** nothing unattended reads either (`AppSettings.pageBarStyle`, `AppSettings.toolbarSwitcherStyle`).
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

/// What the header row reads from the environment: both choices as one value, so one notification and one
/// tracker carry them.
public struct HelmHeaderChoices: Equatable, Sendable {
    public var pageBar: PageBarStyle
    public var tabLabels: ToolbarSwitcherStyle

    public init(pageBar: PageBarStyle, tabLabels: ToolbarSwitcherStyle) {
        self.pageBar = pageBar
        self.tabLabels = tabLabels
    }

    /// What a view mounted with nobody having set a choice gets: the row as it was drawn before the choices existed.
    public static let standard = HelmHeaderChoices(pageBar: .moduleName, tabLabels: .text)
}

extension Notification.Name {
    /// Posted by `AppSettings` after either choice is written, by General's rows and by the row's own menu alike.
    public static let helmHeaderChoicesChanged = Notification.Name("helmHeaderChoicesChanged")
}

extension EnvironmentValues {
    @Entry public var helmHeaderChoices: HelmHeaderChoices = .standard
}

extension View {
    /// Sets `helmHeaderChoices` from `current` and again whenever `.helmHeaderChoicesChanged` is posted. Set only
    /// at the settings pane's root, and **never as an identity** (`.id`): the row's tabs keep their pick
    /// sliding across a change of label, and the page below is not rebuilt for a choice it does not draw.
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
