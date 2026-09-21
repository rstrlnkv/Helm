import SwiftUI

/// **How a settings page says what it is, now that the window has a toolbar.**
///
/// A page used to draw its own header row — plate, name, and a status at the
/// trailing edge — under a title bar that carried nothing. With the page's
/// controls moved into the window's toolbar that stacked two 52 pt bars, one
/// of them empty, over every page. The header now lives in the toolbar, and
/// there are two ways it can: both were drawn side by side in the approved
/// mockup, and this build still carries both.
///
/// - `moduleName` — the module's plate and name as a toolbar item at the
///   leading edge, with its shared glass background hidden, and the status
///   right after the name: the header as it looked, lifted into the bar.
///   **The owner's choice for the shipping layout** (2026-09-21): the module's
///   name on the left, the switcher centred, and the buttons and search
///   packed to the trailing edge — a three-zone toolbar that needs a leading
///   item to be a real zone at all. It is also load-bearing for the search
///   field: `ToolbarSearchName` no longer pins a resting width, and it is
///   this leading item taking room the bare toolbar did not use to take that
///   makes the collapse to a magnifier reachable inside the window's own
///   resizable range at all — measured on Uninstaller, whose search field
///   stays open at every width a headless sweep reaches with no leading item
///   mounted and reads collapsed at the same widths with one
///   (`ToolbarSearchName`'s own doc, which also says why the exact widths in
///   that sweep are not themselves evidence of where the rendered window
///   collapses).
/// - `windowTitle` — the page's name is the window's own title and its status
///   the subtitle under it: text the system draws, with no glass behind it,
///   which is where the guidelines put a title. Shown on every page,
///   including the ones whose toolbar centres a segment switcher. Kept as the
///   other drafted shape, reachable from `GeneralSettingsPage`'s Appearance
///   section — not removed, because retiring a case a Mac may already have
///   stored is `CLAUDE.md`'s rule and not a preference of this file's.
public enum PageBarStyle: String, CaseIterable, Sendable {
    case windowTitle, moduleName

    public static let storageKey = "pageBarStyle"

    /// Anything unknown, including nothing stored, is `moduleName` — the
    /// direction the owner chose for the shipping layout. A Mac that already
    /// has `windowTitle` written keeps reading it: only an *empty or
    /// unrecognised* value falls here, and a value this enum itself wrote is
    /// never either.
    public init(stored: String) {
        self = PageBarStyle(rawValue: stored) ?? .moduleName
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

/// Whether the page's content has scrolled under the window's toolbar. The
/// page's scroll view is the only thing that knows, and the window's strip is
/// the thing that draws it, so the answer travels up as a preference.
public struct HelmPageScrolledKey: PreferenceKey {
    public static let defaultValue = false

    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// **Whether what sits directly under the band is a scroll view** — the page's
/// own structural claim, travelling to whoever draws the band.
///
/// The same road `HelmPageScrolledKey` takes and for the same reason: the band
/// is applied from outside the page, so the page cannot hand this over as an
/// argument, and the only alternative would be a list of pages kept by hand
/// somewhere neither the page nor the band can see.
///
/// The reduction is `||`, so an inner page that says nothing cannot take the
/// claim back — which is what a declaration means, against `HelmPageScrolledKey`'s
/// identical `||` meaning "some scroll view under here has moved".
public struct HelmPageStandsOnStillContentKey: PreferenceKey {
    public static let defaultValue = false

    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

public extension View {
    /// **The toolbar's strip, drawn the way the page header drew itself before
    /// it moved into the toolbar** (`HeaderEdgeLight`): the scroll edge's
    /// material always, and the fill and the rule under it once the page's
    /// content has gone beneath.
    ///
    /// **The system's own scroll edge effect attaches here; a window flag
    /// withholds it.** `titlebarAppearsTransparent`, which `SettingsWindow`
    /// sets, holds the detail pane's effect layer at opacity 0 — with the flag
    /// off the same layer stands at opacity 1 over an 846 × 52 pocket, exactly
    /// the pane's width, while the *same window's* sidebar pocket draws at 1
    /// either way. The pane's content type has nothing to do with it: the
    /// reading is a `Form` because the settings pages are, and a tester read a
    /// `List` and a bare `ScrollView` the same way.
    /// `TheSystemsScrollEdgeEffectAttachesTests` is that measurement, taken by
    /// walking layers and not pixels — the effect *is* a layer and an offscreen
    /// render never composites one, which is how the note that stood here came
    /// to blame `Form`.
    ///
    /// **The strip exists because the effect has nothing to act on at rest, not
    /// because the platform gives us nothing.** This pane keeps AppKit's safe
    /// area, so at rest no content is under the bar; with the flag off the live
    /// effect contributed +7.7/255 in Dark and 0/255 in Light (a reading from
    /// that investigation, which no check in the tree re-takes) — an effect
    /// drawing over nothing. **Scrolled, content does pass beneath the bar**:
    /// that is what `HelmPageScrolledKey` reports and what lights this band, and
    /// Helm's own band was measured tracking a scroll at 38,43 / 39,97 / 38,70
    /// luma over three offsets (2026-09-21, this Mac, dark). The sentence that
    /// stood here said a page's content never passes beneath the bar at all;
    /// only the narrower half of it is true, and it is the half the argument
    /// needs.
    ///
    /// `scrollEdgeEffectStyle(.hard)` is no way round it either, and it is not
    /// ignored: the pocket takes `HardPocketContentBlur`,
    /// `HardPocketBackgroundReplay` and `Separator`, and the transparent title
    /// bar holds that same layer at opacity 0 — which is why it «changed no
    /// pixel».
    ///
    /// So the strip is Helm's, over exactly the height the toolbar takes from
    /// the pane: read from the safe area, because that height is AppKit's to
    /// decide. Items and the title live in the titlebar's own view, above this
    /// one.
    func helmToolbarBackdrop() -> some View {
        modifier(ToolbarBackdrop())
    }

    /// **Says that nothing scrolls under this page's band**, which is what
    /// keeps the band lit from the page's first frame instead of waiting for a
    /// scroll that can never come.
    ///
    /// Applying it *is* the declaration — there is no `false` to pass, the way
    /// there is no `overContent: false` for a page that hands itself to
    /// `helmPageHeader`. A page whose top band is a stack of rows, a switcher
    /// or a toolbar of its own says this; a page that opens a `Form`, a `List`
    /// or a `ScrollView` directly under the band does not, and the scroll
    /// trigger it already has is the right one for it.
    ///
    /// **Declared and not measured**: `HelmPageHeader.standsOnStillContent`
    /// records what that costs and why it is still the cheaper error.
    func helmPageStandsOnStillContent() -> some View {
        preference(key: HelmPageStandsOnStillContentKey.self, value: true)
    }

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
            // A new identity, for the reason `helmTracksSwitcherStyle` gives:
            // the toolbar is AppKit's, and an environment change alone leaves
            // the items it already published where they are.
            .id(style ?? current())
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
                .modifier(ReportsScrolledUnderBar())
                .preference(key: HelmPageTitleKey.self,
                            value: HelmPageTitle(title: title, subtitle: subtitle))
        case .moduleName:
            content
                .modifier(ReportsScrolledUnderBar())
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
                        // The toolbar puts a navigation item 8,5 pt from the
                        // sidebar's edge, where the window's own title starts at
                        // 20 — photographed 2026-09-17, the plate sat hard against
                        // the divider while the other shape's title had the page
                        // gutter. 12 more puts the plate where that title starts.
                        .padding(.leading, HelmSpace.s5)
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

/// The page's half of the strip: asks its own scroll view whether content has
/// gone under the top inset, for the reasons `PageHeaderOverContent` gives —
/// a `Bool` projection so the action fires on the two crossings only, and
/// `0.5` of slack so rounding at rest never lights the strip.
private struct ReportsScrolledUnderBar: ViewModifier {
    @State private var scrolled = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 0.5
            } action: { _, now in
                scrolled = now
            }
            .preference(key: HelmPageScrolledKey.self, value: scrolled)
    }
}

private struct ToolbarBackdrop: ViewModifier {
    @State private var scrolled = false
    @State private var standsOnStillContent = false

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(HelmPageScrolledKey.self) { now in
                scrolled = now
            }
            // The page's structural claim, read the same way its live one is.
            // Without this the eight pages that declare it are exactly the
            // eight the window draws through a toolbar, so the declaration
            // would reach nothing that ships.
            .onPreferenceChange(HelmPageStandsOnStillContentKey.self) { now in
                standsOnStillContent = now
            }
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    Color.clear
                        .frame(height: proxy.safeAreaInsets.top)
                        .modifier(HeaderEdgeLight(
                            lit: HelmPageHeader<EmptyView>.isLit(
                                hovering: false, active: .key, scrolled: scrolled,
                                standsOnStillContent: standsOnStillContent),
                            // Without the declaration in it, so the band is
                            // there from the page's first frame instead of
                            // fading in as the preference lands — see
                            // `HeaderEdgeLight.live`.
                            live: HelmPageHeader<EmptyView>.isLive(
                                hovering: false, active: .key, scrolled: scrolled),
                            overContent: true))
                        .offset(y: -proxy.safeAreaInsets.top)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}
