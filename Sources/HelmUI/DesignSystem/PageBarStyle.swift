import SwiftUI

/// **How a settings page says what it is, now that the window has a toolbar.**
///
/// A page used to draw its own header row — plate, name, and a status at the
/// trailing edge — under a title bar that carried nothing. With the page's
/// controls moved into the window's toolbar that stacked two 52 pt bars, one
/// of them empty, over every page. The header now lives in the toolbar, and
/// there are two ways it can: both are drawn side by side in the approved
/// mockup, and this build carries both so the owner can live with each.
///
/// - `windowTitle` — the page's name is the window's own title and its status
///   the subtitle under it: text the system draws, with no glass behind it,
///   which is where the guidelines put a title. Shown on every page,
///   including the ones whose toolbar centres a segment switcher.
/// - `moduleName` — the module's plate and name as a toolbar item at the
///   leading edge, with its shared glass background hidden, and the status
///   right after the name: the header as it looked, lifted into the bar.
///
/// **A developer option, not a preference.** It exists to choose between two
/// drafts and is expected to be cut; the row that writes it is in the
/// developer section of a dev build only.
public enum PageBarStyle: String, CaseIterable, Sendable {
    case windowTitle, moduleName

    public static let storageKey = "pageBarStyle"

    /// Anything unknown, including nothing stored, is `windowTitle` — the
    /// direction chosen as the default.
    public init(stored: String) {
        self = PageBarStyle(rawValue: stored) ?? .windowTitle
    }
}

public extension Notification.Name {
    static let helmPageBarStyleChanged = Notification.Name("helmPageBarStyleChanged")
}

public extension EnvironmentValues {
    /// **nil means there is no window toolbar to put a header in** — a sheet,
    /// a test mounting a page on its own — and the page draws its header row
    /// in the page, as it always did. The settings window sets it.
    @Entry var helmPageBar: PageBarStyle? = nil
}

/// What the page asks the window to call it. The window, not the page, owns
/// its title: the SwiftUI bridge carries a subtitle from a split view's detail
/// pane into the toolbar and drops the title — measured on macOS 27, the
/// window read «Untitled» over a pane that had set `navigationTitle` — so the
/// settings window reads this and sets both on the `NSWindow` itself.
public struct HelmPageTitle: Equatable, Sendable {
    public let title: String
    public let subtitle: String?

    public init(title: String, subtitle: String?) {
        self.title = title
        self.subtitle = subtitle
    }
}

public struct HelmPageTitleKey: PreferenceKey {
    public static let defaultValue: HelmPageTitle? = nil

    /// The innermost page that says anything wins; views that say nothing
    /// contribute nil and must not erase it.
    public static func reduce(value: inout HelmPageTitle?, nextValue: () -> HelmPageTitle?) {
        value = nextValue() ?? value
    }
}

public extension View {
    /// Follows `PageBarStyle` as it is changed, the way
    /// `helmTracksModuleIconStyle` follows the sidebar's icons.
    func helmTracksPageBarStyle(_ current: @escaping () -> PageBarStyle) -> some View {
        modifier(HelmPageBarStyleTracker(current: current))
    }

    /// **The header, in the window's toolbar** — whichever of the two shapes
    /// the environment asks for — or nothing at all where there is no toolbar.
    ///
    /// For a page that draws its own header row outside `helmPageHeader`
    /// (the log, which is not a scroll view) and so needs to say both «here is
    /// my title» and «draw the row only when there is no bar».
    func helmPageBar<Trailing: View>(
        symbol: String, tint: Color, title: String, subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(PageBarContent(symbol: symbol, tint: tint, title: title,
                                subtitle: subtitle, trailing: trailing()))
    }
}

private struct HelmPageBarStyleTracker: ViewModifier {
    let current: () -> PageBarStyle
    @State private var style: PageBarStyle?

    func body(content: Content) -> some View {
        content
            .environment(\.helmPageBar, style ?? current())
            .onReceive(NotificationCenter.default.publisher(for: .helmPageBarStyleChanged)) { _ in
                style = current()
            }
    }
}

struct PageBarContent<Trailing: View>: ViewModifier {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String?
    let trailing: Trailing

    @Environment(\.helmPageBar) private var bar

    @ViewBuilder
    func body(content: Content) -> some View {
        switch bar {
        case .none:
            content
        case .windowTitle:
            content
                .preference(key: HelmPageTitleKey.self,
                            value: HelmPageTitle(title: title, subtitle: subtitle))
        case .moduleName:
            content
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        HStack(spacing: HelmSpace.s5) {
                            HelmIconPlate(symbol: symbol, tint: tint, size: 24)
                            Text(title)
                                .font(.system(size: 16, weight: .semibold))
                                .tracking(-0.2)
                                .lineLimit(1)
                            // The status sits after the name rather than at the
                            // trailing edge, where the page's own actions are:
                            // measured in a probe window, a status item there
                            // took the Refresh button's place.
                            trailing
                        }
                    }
                    // A title is not a control: no glass behind it.
                    .sharedBackgroundVisibility(.hidden)
                }
                // Still the window's title — the Window menu and Mission
                // Control name the window by it — but not drawn in the bar,
                // which already says it.
                .preference(key: HelmPageTitleKey.self,
                            value: HelmPageTitle(title: title, subtitle: nil))
        }
    }
}
