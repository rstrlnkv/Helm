import SwiftUI

/// The strip's own chrome: the light under the pointer, the scroll edge's
/// material, and the one rule both of them ask for.
///
/// **Measured on macOS 27, on this Mac, against System Settings and Finder.**
/// Both light the *whole* top 52 pt of the content pane — from the sidebar's
/// edge to the window's right edge — and not the control the pointer happens to
/// be over: a button inside the strip moved +3.0 luma while the strip moved
/// +7.8, which is the background changing behind it.
///
/// **The band is the pane's and stops at the divider.** This paragraph said «the
/// sidebar itself unchanged» until 2026-09-21, stated as a measurement, and it
/// was read off too few columns. Re-measured across the divider: the sidebar is
/// not flat but a ramp rising toward it, +2,20 to +3,01, and the first pane
/// pixel at x = 380 steps to +8,06 and holds flat across the pane. Both halves
/// are load-bearing and each has a wrong repair waiting for it — the sidebar
/// does change, so «unchanged» is not the sentence; and the band does not reach
/// the sidebar, so a ramp of two luma is not a band spanning the window.
///
/// The profile is flat to ±0.1 over all 51 rows, so it is a fill and
/// not a gradient, and solving glyph coverage from the composite gave k = 0.100
/// at rest against 0.0999 lit — the glyphs are untouched, so **the lighting** is
/// not itself a material. The surface under it is one, and they are separate
/// layers: only the lighting is a fill. That is what makes the lighting
/// verifiable at all — an offscreen `cacheDisplay` composites a plain fill
/// exactly and never composites glass.
///
/// Dark: pane 30.0 → 37.8, which one constant pair predicted over four different
/// backdrops — near-white at α ≈ 0.038 (`fill`); that was before the window's backdrop
/// became the sidebar's material, and Dark under Glass now draws `darkFill`. `Color.primary` is that
/// white in dark and black in light. The light values were not measured: the Mac
/// switches appearance by the sun and making System Settings draw light is a
/// system setting, which a read-only measurement may not touch.
///
/// # The rule at the bottom edge, and what is actually known about it
///
/// This paragraph used to read «macOS draws no line at rest and a line on
/// hover», stated as a measurement. **What was measured is a rule at dark
/// 30.0 → 46.0, α ≈ 0.0711, present while the pointer was over the strip.**
/// The scroll edge's own rule was measured afterwards at the same place, on the
/// same pane, at 30.0 → 46.0 — the same α to four figures. Two lines that agree
/// to four figures are one line, so the likely reading is that the hover
/// measurement was taken on a scrolled pane and attributed the scroll edge's
/// always-on rule to the pointer. **That is a suspicion and not a finding**:
/// nobody has re-measured hover on an unscrolled pane. Either way it is one
/// line, which is what `HelmPageHeader.isLit` is for.
///
/// 0.5 pt on this screen, which is one device pixel — see `displayScale` below
/// for why that is not the same as typing 0.5.
///
/// # The material, which no test here can see
///
/// The strip is a material and not a fill, proven two independent ways that
/// agree: solving the composite gives 32.2 % of the backdrop passed, and a
/// card's edge (low frequency) comes through at the predicted 32 % — 2.25
/// predicted against 2.36 measured — while text (high frequency) is destroyed,
/// strip max gradient 1.93 against the content's 51.00. That ratio is 0.038
/// where a plain 32 % fill predicts 0.32. Low frequencies through, high
/// frequencies gone: a blur.
///
/// It is `.bar` — the system's own scroll-edge surface — rather than
/// `.glassEffect`, which (ARCHITECTURE.md § Design system) reserves for a thing that
/// *floats*: glass carries its own edge and its own shadow, and this strip
/// draws the pane's edge itself, one point below.
///
/// **The material is not a state, it is the surface.** It is there whenever
/// something *can* pass behind the strip, at rest as much as scrolled: a strip
/// that grew its blur on the way past would show one frame of sharp text
/// first. The fill and the rule are the state; the material is the page's
/// shape.
///
/// **An offscreen `cacheDisplay` never composites it**, so the material is the
/// one part of this modifier no render can check.
///
/// It was measured once by hand instead, on the shipped build, through
/// `screencapture -l` with the appearance thumbnails scrolled under the strip.
/// **Dark:** the strip reads flat at 65.7 (rows varying 65.67…65.74) with a max
/// gradient of **1.26**, over content whose own max gradient is **205.78** — a
/// ratio of 0.006, where a plain fill of the same transmission predicts about
/// 0.3. **Light:** 0.81 against 120.45. And the strip's mean tracks what is
/// behind it — 40.0 with nothing there, 65.7 with the thumbnails — so the low
/// frequencies pass and the high ones are gone. That is a blur, and it is a
/// reading of a screen rather than a test: the day it stops being true, nothing
/// will say so.
///
/// A modifier taking its state as values, not reading the pointer itself, so a
/// settled render can be asked for every state without a pointer to move.
struct HeaderEdgeLight: ViewModifier {
    /// **The one predicate, already answered.** The pointer is over the strip
    /// in the key window, the content has gone under it, or nothing under it
    /// can go under it at all — `HelmPageHeader.isLit` folds the three, and
    /// this draws one appearance from the one answer.
    let lit: Bool
    /// **The live half of that same answer — the pointer and the scroll — and
    /// the only thing the animation is keyed on.**
    ///
    /// `HelmPageHeader.isLive` folds the two facts that can change while a page
    /// is open. The page's declaration is deliberately not among them: it
    /// travels up as a preference and lands one frame *after* the page mounts,
    /// so `lit` goes false → true on every page open, and an animation keyed on
    /// `lit` reads that first delivery as a change and fades the band into
    /// place — measured from the window being built at 243, 145 and 148 ms,
    /// against 0 ms keyed this way, where the first readable frame is already
    /// the settled value (this Mac,
    /// dark, three runs each).
    ///
    /// The rule for a measured height (ARCHITECTURE.md § Motion) — **do not animate the
    /// first measurement** — because nil means nothing has measured this yet
    /// and animating up from it plays the view arriving from a state it was
    /// never in. This was that defect with a `Bool` in place of a `CGFloat`,
    /// and the owner's rule for this band is that the background is always
    /// there.
    ///
    /// **One appearance still.** Nothing here draws: `lit` remains the single
    /// question `HeaderEdgeLight` answers with one fill and one rule, and what
    /// this changes is only which of its reasons the band *moves* for. The
    /// declaration is adopted in both directions — a page swap that withdraws
    /// it takes the band out in the same instant the page it belonged to left,
    /// which is the instant its content went too.
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
    /// **Under Glass in Dark the fill is 1%**, not 3.8%: white at 3.8% over the card's 40 read 49, which is the
    /// window backdrop's own level (Finder's sidebar material, `ShellContentView.makeGlassGround()`), and
    /// a band at the backdrop's level takes the card's top edge and rounded corners away. At 1% the band
    /// read 43 on the card's 40, 6 under the backdrop's 49 (key; 5 non-key), Dark, at rest. These numbers were read on
    /// the Glass ground only (the glass variant 18 at level 49); Flat draws its own `.sidebar` ground that did not match
    /// Finder in Dark, so Flat and Light keep 3.8%, unmeasured against the Flat ground.
    static let darkFill = 0.01
    /// **In Dark, with the content scrolled under the strip, the material is shaded by 20% black.** Over
    /// the card, scrolled, `Material.bar` read 45 to 51 in Dark, the backdrop's level, so the band lost the
    /// card's edge the way the 3.8% fill did. At rest nothing is shaded (the shade at rest read 35 for 43),
    /// and Light is never shaded.
    static let darkShade = 0.2
    /// The bottom edge, at the same moment as the fill.
    static let rule = 0.071
    /// The scroll edge's surface. Named so there is something to check.
    static let material: Material = .bar

    /// **The rule is one device pixel, which is not one number.**
    ///
    /// The capture measured 0.5 pt at 2×, and 0.5 pt is the wrong thing to
    /// type: on a 1× display SwiftUI rounds it to nothing and the rule
    /// disappears — measured, offscreen, where the layout scale is 1: a
    /// `.frame(height: 0.5)` came back with the bottom rows untouched, and 0.75
    /// came back at a full point. What the system draws is a hairline, and a
    /// hairline is a pixel; 0.5 pt is that pixel *on this screen*.
    ///
    /// Confirmed through the real compositor at 2×: the rule lands on exactly
    /// one pixel row, the last of the strip's 104.
    ///
    /// So the app draws 0.5 pt on a Retina display, 1 pt on a 1× one, and an
    /// offscreen render — where `displayScale` reads 1.0 while the bitmap is still
    /// backed at 2× — sees a point. Nothing offscreen can prove the rule's thickness.
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.helmBarAppearance) private var appearance

    /// The Dark numbers were read on the Glass ground; see `darkFill`.
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
                // The same `lit` as the fill above, on purpose: one look,
                // three triggers. A rule keyed on its own question would be a
                // second appearance that happened to coincide most of the time
                // — which is exactly what an always-on band drawn as its own
                // overlay would have been.
                Rectangle()
                    .fill(Color.primary.opacity(lit ? Self.rule : 0))
                    .frame(height: 1 / displayScale)
            }
            // Keyed on the live half and not on the answer: `lit` is what is
            // drawn, `live` is what may move it. See `live` above — an
            // animation keyed on `lit` animates the page's declaration
            // arriving, which is a first delivery and not a change.
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
/// **No summary line.** It carried the module's one-sentence description under
/// the name — «Не давать Mac засыпать» under «Не спать» — which is the sidebar
/// row you just clicked, said again in more words. Every mockup in the
/// redesign draws the plate, the name, and then the page's own controls; the
/// sentence still has two homes where it is the answer rather than an echo:
/// the empty state of a module that is switched off, and the composer's
/// tooltip.
public struct HelmPageHeader<Trailing: View>: View {
    /// **The strip has one appearance and three reasons to wear it.**
    ///
    /// Over a scroll view it draws nothing at rest — no fill, no rule. Both
    /// arrive together, and they arrive because the pointer is over the strip,
    /// **or** because the content has gone under it, **or** because what sits
    /// directly beneath it is not a scroll view at all. Not a fill for one
    /// reason and a rule for another; not two overlays that coincide. One
    /// question, asked here, drawn once by `HeaderEdgeLight`.
    ///
    /// # Where the third reason came from
    ///
    /// **Read this before "fixing" it against a capture of System Settings.**
    /// There are two of them, they disagree, and both stay on the record,
    /// because a number whose reason had been lost has twice been "repaired"
    /// back to a measurement it was chosen against.
    ///
    /// The older capture, taken while this app lit its band under the pointer
    /// and under scrolled content only: System Settings' separator is present
    /// at the **scroll origin** — 2400 px of scroll-up did not remove it — and
    /// scrolling moves only the strip, by 2.6 luma. So the system draws its
    /// rule always, and Helm was diverging from it. **Re-measured in September
    /// 2026 it comes out the other way round**: at the scroll origin there is
    /// no line anywhere, and scrolled there is one. On that reading there is no
    /// divergence to defend at all — Helm's `Form` pages already do what System
    /// Settings does.
    ///
    /// **The decision this predicate carries was the owner's, in September
    /// 2026, and it rests on neither of those captures.** It rests on Finder:
    /// the band is lit whenever the thing directly beneath it is not a scroll
    /// view, and where it is one the band waits for content to go under.
    /// Finder's gallery view carries the band with no column header of any kind
    /// and its icon view carries neither, which is what killed the "pinned
    /// header" reading of the same captures; and that always-on line measured
    /// α = 16/225 = 0.0711 against `HeaderEdgeLight.rule`, which is 0.071. One
    /// line at one alpha with several reasons — which is why this is a third
    /// argument to one predicate and not a second overlay.
    ///
    /// **Both directions are tempting and both are wrong.** Lighting every
    /// page's band always, because the older capture says the system draws its
    /// rule at rest, puts the hairline this app measured away
    /// back over the pages that hand
    /// over a `Form`. Taking the declaration out, because the newer capture
    /// says the system draws none at rest, leaves every page that stands on
    /// still content waiting for a scroll that cannot come. The rule above is
    /// the one the owner took, and the date is when.
    ///
    /// # The three facts, and why neither of the first two is trusted alone
    ///
    /// The strip lights under the pointer only while the window is key —
    /// measured: with System Settings not key, hover changes nothing at all.
    /// `hovering` is a flag the view sets from a pointer that may never leave
    /// (`onHover` does not reliably send `false` when a window loses key under
    /// a stationary pointer), so it is never trusted alone; `controlActiveState`
    /// is the live fact beside it, and the `&&` is the reverse channel
    /// that a local flag standing in for an external one asks for
    /// (ARCHITECTURE.md § Ports and logic).
    ///
    /// `scrolled` carries **no** key gate, and that is not an oversight. Hover
    /// being ignored in a background window is a fact about the pointer; content
    /// sitting under the strip is a fact about the page, and a background window
    /// whose text ran unmarked into its header would be showing the defect the
    /// strip exists to prevent.
    ///
    /// `standsOnStillContent` carries no key gate either, and for the same
    /// reason `scrolled` does not: it is a fact about how the page is built,
    /// not about where the pointer is, and a page's shape does not change when
    /// its window stops being key.
    ///
    /// The `&&` above is what makes the pair honest wherever the pointer *is* asked for.
    static func isLit(hovering: Bool, active: ControlActiveState, scrolled: Bool,
                      standsOnStillContent: Bool) -> Bool {
        standsOnStillContent || isLive(hovering: hovering, active: active, scrolled: scrolled)
    }

    /// **The same answer without the declaration in it: the two facts that can
    /// change while one page is open.**
    ///
    /// Not a second predicate for a second appearance — nothing draws from
    /// this. It is what `HeaderEdgeLight.live` is keyed on, so that the
    /// declaration, which arrives one frame after the page mounts, is adopted
    /// rather than animated. The reasons stay folded: `isLit` is this answer
    /// plus the declaration, written once here so the two cannot drift.
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
    /// 744 pt form column. Which pages those are is a command and not a list
    /// here, because a list written into prose is wrong from the next commit:
    /// `command grep -rn 'bleeds: true' Sources` names the pages that spell it
    /// at their own call to this view. The header the settings window draws in
    /// its card (`CardHeader`) passes true for every page, and every module page
    /// is mounted there.
    let bleeds: Bool
    /// Whether the page's content passes *under* this strip.
    ///
    /// Not `showsRule:` with a nicer name: a per-page choice about whether to
    /// draw a line is four decisions where there should be none, and this is the
    /// other kind of parameter: a fact about how the page is built, the way
    /// `bleeds` is a fact about the page's width. No call site
    /// spells it, because the only thing that sets it is `helmPageHeader`,
    /// which is *what laying the header over the content means*.
    let overContent: Bool
    /// Whether it has, right now. Live, and only ever true where `overContent`
    /// is: a page with nothing behind its header has nothing to report.
    let scrolled: Bool
    /// **What sits directly beneath the band is not a scroll view**, so there
    /// is no moment for the band to start lighting at and it is lit from the
    /// first frame.
    ///
    /// **Not `bleeds` under another name, however alike the two look today.**
    /// The header in the card takes `bleeds` true on every page, so the two
    /// coincide there. They are still different questions: `bleeds` is about the header's **width**, and
    /// this is about the **species of the thing under it**. Folding one into
    /// the other would pass every test anybody could write today and fail
    /// silently on the first page where a full-bleed `ScrollView` or a
    /// column-width stack of bands arrives.
    ///
    /// **Declared by the page, never computed from what it is drawing.** A
    /// page's first child changes with a tab, a step and a refused permission
    /// — `UninstallerSettingsPage` changes it with both of the first two, and
    /// `DuplicatesSettingsPage` opens on a permission note — so a computed
    /// answer would flicker the band exactly where the page changes shape
    /// under a stationary pointer. The price is paid knowingly and in one
    /// place: on Uninstaller's page the band is lit over lists that do
    /// scroll under it. That is an over-reach the design pass chose, not
    /// an oversight to repair.
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
        HStack(spacing: 12) {
            // 24, the Kit's `Toolbar` (Figma 309:216): the plate is 24 and the title starts 12 after it.
            // Without Icon (`HelmHeaderChoices`) draws the name alone; the status after it stays.
            if choices.pageBar == .moduleName {
                HelmIconPlate(symbol: symbol, tint: tint, size: 24)
            }
            // 16, the redesign's «заголовок» step. It was 20, which is not on
            // the ladder at all — the six sizes are 10 · 11 · 13 · 16 · 22 · 40
            // — and with the summary gone the name no longer has to hold a
            // two-line block up on its own.
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
            Spacer(minLength: 12)
            trailing
        }
        .opacity(dimmed ? HelmText.inactiveOpacity : 1)
        // **The row's insets are the caller's.** The Kit's card row has its plate 14 from the card's edge and its
        // controls 10 from the other (`CardHeader`), while the content below starts at 20
        // (`HelmLayout.formInset`): the row is chrome and the page's gutter is content's, and the two no longer
        // begin at one x. A header over a page on its own keeps 20 and 20.
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        // The row is **52**: the Kit's 36 pt controls with 8 above and below. `minHeight` holds the 36 on a page
        // whose row has no control (24 pt plate alone), so no page's row is shorter than another's.
        .frame(minHeight: HelmHeaderActions.side)
        .padding(.vertical, HelmSpace.s4)
        // On the same column as the content below it. Which column that is
        // depends on the page: outside the card a grouped Form is capped at 744 pt
        // and centred, so its header is too — but a full-bleed page draws its toolbar
        // across the whole pane, and a centred header above it walks away as the
        // window grows. Measured on a 1400 pt window: the title sat 203 pt right of
        // the controls beneath it (with the old 20 pt insets). It has never been seen
        // because at the default window the pane is 690 pt — narrower than the
        // column, where the two rules agree. Only a header drawn in the page can get
        // `false` here; the card's passes `true`, and its row's insets are the Kit's
        // 14 and 10, not the 20 of the page's gutter (above).
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
    /// **This is a structural change and not a decoration.** System Settings
    /// puts its content behind the strip — which is what gives the material
    /// something to blur and the scroll edge something to be the edge of — and
    /// Helm's header was a sibling in a `VStack(spacing: 0)`, with nothing
    /// passing behind it at all. `safeAreaInset` is both halves at once: the
    /// strip is drawn over the page, and the page's scroll view is given a top
    /// inset of exactly its height, so the first row still starts below it and
    /// no page has to reserve the space by hand.
    ///
    /// A page whose top band does not scroll — the Log page is a stack of
    /// bands, a sheet is a sheet — draws `HelmPageHeader` directly instead. It
    /// gets the same 52 pt strip and no scroll edge, because there is no scroll
    /// to be the edge of; a rule there would be the hairline this app measured
    /// away under a different name.
    ///
    /// **Where the window has set `\.helmHeaderInCard`** (`SettingsWindow`), this draws
    /// no row in the page at all: the settings window's own row, `helmCardHeader`, is the header and takes
    /// the page's name from the window's page identity; `PageBarContent` carries the window's title and
    /// whether the page has scrolled under the row.
    /// A page mounted without it (a sheet, a page on its own) draws `HelmPageHeader` directly, which
    /// takes a `trailing` view of its own for that case (`AboutPage`'s `WhatsNewView`, its one caller today).
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
/// **The offset is asked of the scroll view, never inferred.**
/// `onScrollGeometryChange` reports the real thing — content offset against the
/// top inset `safeAreaInset` just added — so «scrolled» is the scroll view's
/// fact travelling up to the strip, not a flag somebody set once. Where a page
/// has no scroll view in it the closure never runs and `scrolled` stays false,
/// which is the correct answer for a page nothing can pass behind.
///
/// `+ 0.5` rather than `> 0`: a rubber-band bounce and a fractional inset both
/// put a few hundredths on the offset at rest, and a strip that lit itself
/// because of rounding would be lit for ever.
///
/// **The projection is a `Bool`, not the offset.** `onScrollGeometryChange`
/// calls its action when the *projected value* changes, so asking it for a
/// `CGFloat` would wake this view on every frame of every scroll to set a flag
/// that changed twice. Asked for the answer instead, it fires on the two
/// crossings and nowhere else.
///
/// **And the page's own declaration about what is under the band travels the
/// same direction.** `helmPageStandsOnStillContent` is set inside the page and
/// read here, exactly as `HelmPageScrolledKey` is set inside the page and read
/// by `CardHeader` — the header is applied from outside the page, so a
/// preference is the only way round, and the alternative would be a hand-kept
/// list of pages living somewhere neither the page nor the band can see.
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

extension View {
    /// **The header row in the card, over this page.** One row for every page of the settings window, drawn
    /// at the root of the detail pane so it keeps its identity across a page switch: the page's name and
    /// status on the left, on the right what the page declared through `helmWindowToolbar` — tabs, actions,
    /// search (`HelmPageToolbarKey`). The page scrolls under it, as it does under `helmPageHeader`, and
    /// the pane reserves the row's height as a top inset.
    ///
    /// The declaration is read with `overlayPreferenceValue`: the value carries closures cut from the page's
    /// state at its last body, and a copy kept in `@State` behind an `==` would hold the old ones
    /// (`LogView`'s Copy captures `page.lines`).
    ///
    /// The empty part of the row drags the window, since there is no title bar under it any more.
    ///
    /// **The row has no right-click menu of its own**: it lies in the window's title bar zone, where a SwiftUI
    /// `.contextMenu` is never reached; the window pops one up (`HeaderBarMenu`) over the band
    /// `HelmCardHeaderBand.height` names.
    public func helmCardHeader(symbol: String, tint: Color, title: String, status: HelmHeaderStatus?) -> some View {
        modifier(CardHeader(symbol: symbol, tint: tint, title: title, status: status))
    }
}

/// The header row's height, for the window that decides which presses are the row's.
@MainActor public enum HelmCardHeaderBand {
    public static let height = CardHeader.height
}

private struct CardHeader: ViewModifier {
    let symbol: String
    let tint: Color
    let title: String
    let status: HelmHeaderStatus?

    @State private var scrolled = false
    @State private var standsOnStillContent = false
    @Environment(\.helmWindowAppearsActive) private var windowAppearsActive

    /// The Kit's 36 pt controls (`HelmHeaderActions.side`) with `HelmSpace.s4` above and below (`HelmPageHeader`).
    static let height = HelmSpace.s4 * 2 + HelmHeaderActions.side
    /// The Kit's `Toolbar` (Figma 309:216): the plate 14 from the card's left edge, the controls 10 from its right.
    static let leadingInset = CGFloat(14)
    static let trailingInset = CGFloat(10)

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(HelmPageScrolledKey.self) { scrolled = $0 }
            .onPreferenceChange(HelmPageStandsOnStillContentKey.self) { standsOnStillContent = $0 }
            .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: Self.height) }
            .overlayPreferenceValue(HelmPageToolbarKey.self, alignment: .top) { controls in
                HelmPageHeader(symbol: symbol, tint: tint, title: title, bleeds: true,
                               overContent: true, scrolled: scrolled,
                               standsOnStillContent: standsOnStillContent, status: status,
                               dimmed: !windowAppearsActive, leadingInset: Self.leadingInset,
                               trailingInset: Self.trailingInset) {
                    HelmHeaderControls(content: controls, page: title)
                }
                .frame(height: Self.height)
                .background { Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()) }
            }
    }
}

/// Tabs, then actions and search, in that order, on the right of the row; each only where the page declared it.
///
/// **The tab strip's place is the owner's, not the page's.** Where pages share one strip and declare different
/// runs (the settings window's three), the owner declares the widest (`HelmPageToolbarContent.reserves`) and the
/// run keeps at least that width, so the strip ends `HelmTrailingRun.gap` before it on every one of them. A page without a
/// declaration gets exactly the room of what it declared, as the row had before.
private struct HelmHeaderControls: View {
    let content: HelmPageToolbarContent?
    /// The page's name: the search slot's identity, so what it holds open does not leak to the next page. Never the tabs'.
    let page: String

    var body: some View {
        if let content {
            HStack(spacing: HelmTrailingRun.gap) {
                if !content.tabs.isEmpty, let selected = content.selectedTab {
                    HelmHeaderTabs(tabs: content.tabs, selection: selected, enabled: content.tabsEnabled)
                }
                if !content.actions.isEmpty || content.search != nil || content.reserves != nil {
                    HStack(spacing: HelmTrailingRun.gap) {
                        if !content.actions.isEmpty {
                            HelmHeaderActions(actions: content.actions)
                        }
                        if let search = content.search {
                            HelmHeaderSearch(search: search).id(page)
                        }
                    }
                    .frame(minWidth: content.reserves?.width ?? 0, alignment: .trailing)
                }
            }
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
