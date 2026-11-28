import SwiftUI

/// The strip's own chrome: the light under the pointer, the scroll edge's
/// material, and the one rule both of them ask for.
///
/// As in System Settings and Finder, the light covers the whole top 52 pt of
/// the content pane, not the control under the pointer, and stops at the
/// sidebar's divider. It is a plain fill over a separate material, and the
/// glyphs under it are untouched. Being a fill is what makes it checkable: an
/// offscreen `cacheDisplay` composites a fill exactly and never composites glass.
///
/// `fill` and `rule` were solved from captures of System Settings in Dark.
/// `Color.primary` is white in Dark and black in Light; the Light values are
/// unmeasured. The rule has the same alpha as the scroll edge's own rule, so it
/// is one line with several reasons, which is what `HelmPageHeader.isLit` is for.
///
/// The material is `.bar`, the system's scroll-edge surface, not `.glassEffect`:
/// glass is for a thing that floats and carries its own edge
/// (Architecture/DesignSystem.md § Surfaces), and this strip draws the pane's
/// edge itself. The material is the page's shape, not a state: it is there
/// whenever something can pass behind the strip, because a blur grown on the
/// way past would show one frame of sharp text first. No offscreen render sees
/// it, so no test here can check it.
///
/// The state comes in as values rather than from the pointer, so a settled
/// render can be asked for every state.
struct HeaderEdgeLight: ViewModifier {
    /// The one predicate, already answered by `HelmPageHeader.isLit`; this
    /// draws one appearance from it.
    let lit: Bool
    /// The live half of that answer, the pointer and the scroll, and the only
    /// thing the animation is keyed on.
    ///
    /// The page's declaration is left out because it travels up as a
    /// preference and lands one frame after the page mounts: keyed on `lit`,
    /// every page open would fade the band in from a state it was never in. The
    /// first measurement is not a change (Architecture/DesignSystem.md § Motion).
    /// Nothing draws from this, and a page swap that withdraws the declaration
    /// takes the band out in the same instant as the page.
    let live: Bool
    /// Whether anything can pass behind the strip. A structural fact about the
    /// page and never a call site's taste: `View.helmPageHeader` is the only
    /// thing that sets it, and setting it is how a page says its content
    /// scrolls under.
    let overContent: Bool
    /// Whether the page's content has gone beneath the strip: only then is the Dark shade drawn.
    var scrolled = false

    /// Near-white at 3.8%, from the composite over four backdrops.
    static let fill = 0.038
    /// The Dark fill for the Liquid Glass toolbar style. It was tuned against the
    /// former Finder-style glass backdrop: `fill` matched that backdrop and hid
    /// the card's top edge and rounded corners. Flat and Light use `fill`.
    static let darkFill = 0.01
    /// The Dark shade for the Liquid Glass toolbar style, with content scrolled
    /// under the strip. Unshaded `Material.bar` matched the former backdrop and
    /// hid the card's edge. At rest and in Light nothing is shaded.
    static let darkShade = 0.2
    /// The bottom edge, at the same moment as the fill.
    static let rule = 0.071
    /// The scroll edge's surface. Named so there is something to check.
    static let material: Material = .bar

    /// The rule is one device pixel, which is not one number: 0.5 pt on a Retina
    /// display, 1 pt on a 1× one, where SwiftUI rounds 0.5 to nothing. An
    /// offscreen render reads `displayScale` 1.0 over a 2× bitmap and sees a
    /// full point, so nothing offscreen can prove the rule's thickness.
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.helmBarAppearance) private var appearance

    private var glassDark: Bool { colorScheme == .dark && appearance == .liquidGlass }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Only where something passes behind it. A blur over an
                    // opaque band is a backdrop filter with nothing to filter.
                    if overContent { Rectangle().fill(Self.material) }
                    if overContent && scrolled && glassDark { Color.black.opacity(Self.darkShade) }
                    Color.primary.opacity(lit ? (glassDark ? Self.darkFill : Self.fill) : 0)
                }
            }
            .overlay(alignment: .bottom) {
                // The same `lit` as the fill, on purpose: one look, three
                // triggers. A rule keyed on its own question would be a second
                // appearance.
                Rectangle()
                    .fill(Color.primary.opacity(lit ? Self.rule : 0))
                    .frame(height: 1 / displayScale)
            }
            // `lit` is what is drawn, `live` is what may move it (see `live`).
            .animation(HelmMotion.hover(entering: lit), value: live)
    }
}

/// What the module is doing, as the header row says it after the name: `word` is localised already,
/// `active` picks the badge over the quiet word.
public struct HelmHeaderStatus: Equatable, Sendable {
    let word: String
    let active: Bool

    public init(word: String, active: Bool) {
        self.word = word
        self.active = active
    }
}

/// The strip at the top of every page: what this page is, and the controls
/// that belong to the page rather than to any row in it.
///
/// No summary line: the module's description under the name repeats the
/// sidebar row just clicked. The sentence stays where it answers something:
/// the empty state of a module that is switched off, and the composer's tooltip.
public struct HelmPageHeader<Trailing: View>: View {
    /// The strip has one appearance and three reasons to wear it.
    ///
    /// Over a scroll view it draws nothing at rest. The fill and the rule arrive
    /// together when the pointer is over the strip, when the content has gone
    /// under it, or when what sits directly beneath it is not a scroll view at
    /// all. One question, asked here, drawn once by `HeaderEdgeLight`.
    ///
    /// The third reason is the owner's decision, taken from Finder: the band is
    /// lit whenever the thing beneath it is not a scroll view, and otherwise it
    /// waits for content to go under. Captures of System Settings disagree with
    /// each other about a rule at rest, so do not "fix" this against one.
    /// Lighting every band always puts a hairline back over the `Form` pages;
    /// dropping the declaration leaves a page on still content waiting for a
    /// scroll that cannot come.
    ///
    /// Hover lights the strip only while the window is key, as in System
    /// Settings. `hovering` comes from `onHover`, which does not reliably send
    /// `false` when the window loses key under a still pointer, so it is never
    /// trusted alone: `controlActiveState` is the live fact beside it
    /// (Architecture/ModulePattern.md § Ports and logic). `scrolled` and
    /// `standsOnStillContent` carry no key gate: they are facts about the page,
    /// and a background window whose text ran unmarked into its header would
    /// show the defect the strip exists to prevent.
    static func isLit(hovering: Bool, active: ControlActiveState, scrolled: Bool,
                      standsOnStillContent: Bool) -> Bool {
        standsOnStillContent || isLive(hovering: hovering, active: active, scrolled: scrolled)
    }

    /// The same answer without the declaration: the two facts that can change
    /// while one page is open. `HeaderEdgeLight.live` is keyed on it, so the
    /// declaration, arriving a frame after the page mounts, is adopted rather
    /// than animated. `isLit` is built on it so the two cannot drift.
    static func isLive(hovering: Bool, active: ControlActiveState, scrolled: Bool) -> Bool {
        scrolled || (hovering && active == .key)
    }

    @State private var pointerOver = false
    @Environment(\.helmShownInteraction) private var shown
    private var hovering: Bool { pointerOver || shown == .hover }
    @Environment(\.controlActiveState) private var activeState
    /// Whether this header wears Helm's band at all — on macOS 26 it does
    /// not, by the owner's answer (`HelmBandChoice.pageHeaderBandOn26`).
    @Environment(\.helmBandChoice) private var band
    @Environment(\.helmTraits) private var traits

    let symbol: String
    let tint: Color
    let title: String
    /// True for a page whose content spans the pane rather than sitting in the
    /// 744 pt form column (`command grep -rn 'bleeds: true' Sources` lists the
    /// callers). The card's header (`CardHeader`) passes true for every page.
    let bleeds: Bool
    /// Whether the page's content passes *under* this strip: a fact about how
    /// the page is built, like `bleeds`, not a per-page choice to draw a line.
    /// Only `helmPageHeader` sets it, since laying the header over the content
    /// is what that modifier means.
    let overContent: Bool
    /// Whether it has, right now. Live, and only ever true where `overContent`
    /// is: a page with nothing behind its header has nothing to report.
    let scrolled: Bool
    /// What sits directly beneath the band is not a scroll view, so the band is
    /// lit from the first frame.
    ///
    /// Not `bleeds` under another name, though the card's header passes
    /// `bleeds` true everywhere: `bleeds` is about the header's width, this is
    /// about the kind of thing under it.
    ///
    /// Declared by the page, never computed from what it draws. A page's first
    /// child changes with a tab, a step or a refused permission, so a computed
    /// answer would flicker the band under a still pointer. The price is known:
    /// on Uninstaller's page the band is lit over lists that do scroll under it.
    let standsOnStillContent: Bool
    /// The module's state, said after the name: a badge while it is active, a quiet word while it is idle.
    /// nil for a page that has none, and then nothing is drawn.
    let status: HelmHeaderStatus?
    /// The row's elements — name, status, tabs, actions, search — dim as one; the ground under them does not,
    /// so a header over content hides what passes behind it as well in a window that is not the active one.
    let dimmed: Bool
    /// The plate's distance from the row's left edge and the controls' from its right. 20 and 20 (`HelmLayout.formInset`)
    /// where the row heads a page on its own; the card's row passes the Kit's 14 and 10 (`CardHeader`).
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let trailing: Trailing
    @Environment(\.helmHeaderChoices) private var choices

    public init(symbol: String, tint: Color, title: String,
                bleeds: Bool = false, standsOnStillContent: Bool = false,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.init(symbol: symbol, tint: tint, title: title, bleeds: bleeds,
                  overContent: false, scrolled: false,
                  standsOnStillContent: standsOnStillContent, trailing: trailing)
    }

    /// Internal, so neither fact can be reached from outside `HelmUI`: the
    /// structural claim stays `helmPageHeader`'s to make, and the live one
    /// stays the scroll view's to report. `standsOnStillContent` is public
    /// above because a page that draws this header as a view — the log — has
    /// no `helmPageHeader` to declare it through.
    init(symbol: String, tint: Color, title: String, bleeds: Bool,
         overContent: Bool, scrolled: Bool, standsOnStillContent: Bool, status: HelmHeaderStatus? = nil,
         dimmed: Bool = false, leadingInset: CGFloat = HelmLayout.formInset,
         trailingInset: CGFloat = HelmLayout.formInset,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.bleeds = bleeds
        self.overContent = overContent
        self.scrolled = scrolled
        self.standsOnStillContent = standsOnStillContent
        self.status = status
        self.dimmed = dimmed
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
        self.trailing = trailing()
    }

    public var body: some View {
        lit(row).onHover { pointerOver = $0 }
    }

    @ViewBuilder
    private func lit(_ row: some View) -> some View {
        if band.pageHeaderBand {
            row.modifier(HeaderEdgeLight(lit: Self.isLit(hovering: hovering, active: activeState,
                                                         scrolled: scrolled,
                                                         standsOnStillContent: standsOnStillContent),
                                         live: Self.isLive(hovering: hovering, active: activeState,
                                                           scrolled: scrolled),
                                         overContent: overContent, scrolled: scrolled))
        } else {
            row
        }
    }

    private var row: some View {
        HeaderRowLayout(shift: (trailingInset - leadingInset) / 2) {
            HStack(spacing: 12) {
                // 24, the Kit's `Toolbar` (Figma 309:216): the plate is 24 and the title starts 12 after it.
                // Without Icon (`HelmHeaderChoices`) draws the name alone; the status after it stays.
                if choices.pageBar == .moduleName {
                    HelmIconPlate(symbol: symbol, tint: tint, size: 24)
                }
                // 16, the type ladder's heading step (10 · 11 · 13 · 16 · 22 · 40).
                Text(title)
                    .font(HelmText.plateTitle)
                    .tracking(-0.2)
                    .lineLimit(1)
                    // The name does not give way, nor do the tabs and the search beside it: the window's minimum
                    // width (`SettingsWindow.minSize`) is measured on the Log page, the fullest row, in every language.
                    .fixedSize(horizontal: true, vertical: false)
                if let status {
                    if status.active {
                        HelmBadge(status.word, tint: HelmSignal.success(increased: traits.increasedContrast))
                    } else {
                        Text(status.word).font(.system(size: 11)).foregroundStyle(HelmText.quiet)
                    }
                }
            }
            .layoutValue(key: HeaderRoleKey.self, value: .name)
            trailing
        }
        .opacity(dimmed ? HelmText.inactiveOpacity : 1)
        // The row's insets are the caller's: the card's row puts its plate 14
        // from the edge and its controls 10 (`CardHeader`), while the content
        // below starts at 20 (`HelmLayout.formInset`). A header over a page on
        // its own keeps 20 and 20.
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        // The row is **52**: the Kit's 36 pt controls with 8 above and below. `minHeight` holds the 36 on a page
        // whose row has no control (24 pt plate alone), so no page's row is shorter than another's.
        .frame(minHeight: HelmHeaderActions.side)
        .padding(.top, HelmSpace.s4)
        .padding(.bottom, HelmSpace.s4)
        // On the same column as the content below. Outside the card a grouped
        // Form is capped at 744 pt and centred, so its header is too; a
        // full-bleed page draws its toolbar across the pane, and a centred
        // header above it would walk away as the window grows. Only a header
        // drawn in the page gets `false`; the card's passes `true`.
        .frame(maxWidth: bleeds ? .infinity : HelmLayout.settingsColumn)
        // The lighting goes on the pane-wide frame and not the one above it:
        // macOS lights the whole strip, and on a grouped-`Form` page drawn outside
        // the card the frame above is capped at the 744 pt column and centred,
        // so a background there would be a lit band floating in an unlit pane.
        .frame(maxWidth: .infinity, alignment: bleeds ? .leading : .center)
    }
}

extension View {
    /// Lays the page header **over** this page, and lets the page scroll under
    /// it.
    ///
    /// `safeAreaInset` does both at once: the strip is drawn over the page,
    /// which gives the material something to blur, and the page's scroll view
    /// gets a top inset of the strip's height, so the first row still starts
    /// below it and no page reserves the space by hand.
    ///
    /// A page whose top band does not scroll (the Log page, a sheet) draws
    /// `HelmPageHeader` directly: the same 52 pt strip with no scroll edge.
    ///
    /// Where the window has set `\.helmHeaderInCard` (`SettingsWindow`), this
    /// draws no row in the page: the window's `helmCardHeader` is the header,
    /// and `PageBarContent` carries the page's title and whether it has
    /// scrolled under the row.
    public func helmPageHeader(
        symbol: String, tint: Color, title: String, bleeds: Bool = false
    ) -> some View {
        modifier(PageHeaderPlacement(symbol: symbol, tint: tint, title: title,
                                     bleeds: bleeds))
    }
}

/// The row in the page, or the header in the window's bar — one question,
/// asked of the environment, so no page has to know which window it is in.
private struct PageHeaderPlacement: ViewModifier {
    let symbol: String
    let tint: Color
    let title: String
    let bleeds: Bool

    @Environment(\.helmHeaderInCard) private var inCard

    @ViewBuilder
    func body(content: Content) -> some View {
        if !inCard {
            content.modifier(PageHeaderOverContent(symbol: symbol, tint: tint, title: title,
                                                   bleeds: bleeds))
        } else {
            // The window's card header draws the name and the status;
            // neither the icon nor a trailing view reaches this arm.
            content.modifier(PageBarContent(title: title))
        }
    }
}

/// The header laid over the page, and the page's own answer to «have I gone
/// under it yet».
///
/// The offset is asked of the scroll view, never inferred. Where a page has
/// no scroll view the closure never runs and `scrolled` stays false, which is
/// right for a page nothing can pass behind. `onScrolledUnder` tests `> 0.5`
/// rather than `> 0`, because a bounce or a fractional inset leaves a few
/// hundredths at rest, and it projects a `Bool`, so its action fires on the
/// two crossings and not on every frame of a scroll.
///
/// The page's declaration about what is under the band travels the same way,
/// as a preference, because the header is applied from outside the page.
private struct PageHeaderOverContent: ViewModifier {
    let symbol: String
    let tint: Color
    let title: String
    let bleeds: Bool

    @State private var scrolled = false
    @State private var standsOnStillContent = false

    func body(content: Content) -> some View {
        content
            // Read off `content` and before the inset below, so what is
            // answered for is the page and never the header this modifier is
            // about to lay over it.
            .onPreferenceChange(HelmPageStandsOnStillContentKey.self) { now in
                standsOnStillContent = now
            }
            .onScrolledUnder { scrolled = $0 }
            // `spacing: 0` — the gap under the header is the page's own top
            // padding, which every page already draws.
            .safeAreaInset(edge: .top, spacing: 0) {
                HelmPageHeader(symbol: symbol, tint: tint, title: title, bleeds: bleeds,
                               overContent: true, scrolled: scrolled,
                               standsOnStillContent: standsOnStillContent)
            }
    }
}

extension EnvironmentValues {
    /// Whether the window draws its chrome active — the window's own reading (`SettingsWindow`'s header above
    /// `windowDidBecomeKey`), not `\.controlActiveState`, which reads `.inactive` under a sheet where the
    /// window is still the active one. The header row and the sidebar's rows dim by it; a view outside the settings window reads true.
    @Entry public var helmWindowAppearsActive = true
}

extension EnvironmentValues {
    /// **True where the window's card draws the page's header row** — the settings window sets it; a sheet or a
    /// test mounting a page on its own leaves it false. Then `helmPageHeader` draws the page's own header
    /// row in the page (`PageHeaderPlacement`), `helmPageBar` is inert, and a page that draws its own row
    /// reads this itself (`LogView`).
    @Entry public var helmHeaderInCard: Bool = false
}

/// What the page asks the window to call it. The window, not the page, owns its title: the settings window
/// reads this and sets it on the `NSWindow` itself.
public struct HelmPageTitleKey: PreferenceKey {
    public static let defaultValue: String? = nil
    /// The innermost page that says anything wins; views that say nothing contribute nil and must not erase it.
    public static func reduce(value: inout String?, nextValue: () -> String?) {
        value = nextValue() ?? value
    }
}

/// Whether the page's content has scrolled under the header row. The page's scroll view is the only thing that
/// knows, and the row (`CardHeader`) is the thing that draws it, so the answer travels up as a preference.
struct HelmPageScrolledKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// **Whether what sits directly under the header row is a scroll view** — the page's own structural claim,
/// travelling to whoever draws the row, by the road `HelmPageScrolledKey` takes and for the same reason: the row
/// is applied from outside the page. The reduction is `||`, so an inner page that says nothing cannot take the
/// claim back.
struct HelmPageStandsOnStillContentKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    /// Declares that this page's content under the header row is still, not a scroll view
    /// (`HelmPageStandsOnStillContentKey`).
    public func helmPageStandsOnStillContent() -> some View {
        preference(key: HelmPageStandsOnStillContentKey.self, value: true)
    }

    /// What the page says to the window's card: its name, and whether its scroll view has moved. Inert where no
    /// card draws the header (`helmHeaderInCard`).
    public func helmPageBar(title: String) -> some View {
        modifier(PageBarContent(title: title))
    }
}

struct PageBarContent: ViewModifier {
    let title: String
    @Environment(\.helmHeaderInCard) private var inCard

    @ViewBuilder
    func body(content: Content) -> some View {
        if inCard {
            content.modifier(ReportsScrolledUnderBar())
                .preference(key: HelmPageTitleKey.self, value: title)
        } else {
            content
        }
    }
}

private extension View {
    /// Says whether the content has scrolled past the bar laid over its top.
    func onScrolledUnder(_ set: @escaping (Bool) -> Void) -> some View {
        onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 0.5 } action: { _, now in set(now) }
    }
}

private struct ReportsScrolledUnderBar: ViewModifier {
    @State private var scrolled = false

    func body(content: Content) -> some View {
        content
            .onScrolledUnder { scrolled = $0 }
            .preference(key: HelmPageScrolledKey.self, value: scrolled)
    }
}
