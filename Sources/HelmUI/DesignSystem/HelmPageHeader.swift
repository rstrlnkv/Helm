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
/// Dark: pane 30.0 → 37.8, which one constant pair predicts over four different
/// backdrops — near-white at α ≈ 0.038. `Color.primary` **is** that white in
/// dark and black in light, so the token says the measurement rather than
/// restating it per appearance. The light values were not measured: the Mac
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
/// `.glassEffect`, which ARCHITECTURE.md § Design system reserves for a thing that
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
/// one part of this modifier no render can check — see
/// `TheHeaderIsTheSystemsScrollEdgeTests`, which guards it by construction and
/// says so in every message it prints.
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
    /// the settled value (`TheBandIsThereFromTheFirstFrameTests`, this Mac,
    /// dark, three runs each).
    ///
    /// CLAUDE.md states the rule for a measured height — **do not animate the
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

    /// Near-white at 3.7%, from the composite over four backdrops.
    static let fill = 0.038
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
    /// So the app draws 0.5 pt on a Retina display, 1 pt on a 1× one, and the
    /// offscreen renders in `TheHeaderIsTheSystemsScrollEdgeTests` — where
    /// `displayScale` reads 1.0 while the bitmap is still backed at 2× — see a
    /// point. Which means the guards there prove the fill and the rule are
    /// *present, absent and together*, and do not prove the rule's thickness.
    /// Nothing offscreen can.
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Only where something passes behind it. A blur over an
                    // opaque band is a backdrop filter with nothing to filter.
                    if overContent { Rectangle().fill(Self.material) }
                    Color.primary.opacity(lit ? Self.fill : 0)
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
    /// (`ThePageHeaderCarriesNoRuleTests`) back over the five pages that hand
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
    /// CLAUDE.md's rule about a local flag standing in for an external one asks
    /// for.
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
    /// **The pointer is live in one of the two drawers only.** Drawn in the page
    /// the header reads its own `onHover`; drawn in the window's toolbar
    /// `ToolbarBackdrop` (`Sources/HelmUI/DesignSystem/PageBarStyle.swift`)
    /// passes `hovering: false, active: .key` and has no pointer to read, so
    /// there the band has two reasons and not three. The `&&` above is what
    /// makes the pair honest wherever the pointer *is* asked for; it is not a
    /// claim that both live triggers reach both placements.
    ///
    /// Static and taking its four facts, so it is a question a test can ask
    /// without a window, a pointer, or a render.
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

    @State private var hovering = false
    @Environment(\.controlActiveState) private var activeState

    let symbol: String
    let tint: Color
    let title: String
    /// True for a page whose content spans the pane rather than sitting in the
    /// 744 pt form column. Which pages those are is a command and not a list
    /// here, because a list written into prose is wrong from the next commit:
    /// `command grep -rn 'pageBleeds: Bool { true }' Sources` names the module
    /// descriptors that declare it, and the log, which has no descriptor,
    /// spells `bleeds: true` at its own call to this view.
    /// `TheBandStandsOnWhatIsUnderItTests` holds both halves and fails on
    /// either alone.
    let bleeds: Bool
    /// Whether the page's content passes *under* this strip.
    ///
    /// Not `showsRule:` with a nicer name. `ThePageHeaderCarriesNoRuleTests`
    /// argues that one out at length — a per-page choice about whether to draw
    /// a line is four decisions where there should be none — and this is the
    /// other kind of parameter: a fact about how the page is built, the way
    /// `bleeds` is a fact a module declares about its own content. No call site
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
    /// Eight things declare each — the seven module descriptors plus the log —
    /// and on all thirteen pages the two answers coincide exactly. They are
    /// still different questions: `bleeds` is about the header's **width**, and
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
    /// place: on Uninstaller's objects tab the band is lit over a list that
    /// does scroll under it. That is an over-reach the design pass chose, not
    /// an oversight to repair.
    let standsOnStillContent: Bool
    let trailing: Trailing

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
         overContent: Bool, scrolled: Bool, standsOnStillContent: Bool,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.bleeds = bleeds
        self.overContent = overContent
        self.scrolled = scrolled
        self.standsOnStillContent = standsOnStillContent
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 12) {
            // 28, asked of the mockup itself rather than counted off a picture:
            // `.pagehead` measures 46 tall and its plate 28. Ours was the 44 pt
            // plate the About window uses for the app's own icon, and a 44 pt
            // square with 18 pt above and below is an 80 pt strip — a third of
            // the height before the first control, on every page.
            HelmIconPlate(symbol: symbol, tint: tint, size: 28)
            // 16, the redesign's «заголовок» step. It was 20, which is not on
            // the ladder at all — the six sizes are 10 · 11 · 13 · 16 · 22 · 40
            // — and with the summary gone the name no longer has to hold a
            // two-line block up on its own.
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.2)
                .lineLimit(1)
            Spacer(minLength: 12)
            trailing
        }
        // **20 across, not the redesign's 18.** The mockups draw this strip and
        // the pane below it at one gutter, and moving only the header to 18
        // breaks the rule that matters more: a bleeding page's content starts
        // at 20, and `StartScreenColumnTests` measures that the two begin at
        // the same x. The gutter is an app-wide number; changing it is its own
        // pass, not a side effect of restyling a header.
        .padding(.horizontal, HelmLayout.formInset)
        // 12 above and below a 28 pt plate is **52** — System Settings' own
        // strip, measured on the Accessibility pane at 2× as 11,5 over a 29,0
        // pt back-forward control and 11,5 under it.
        //
        // The *sum* is taken and the parts are not. 11,5 is a step of nothing
        // and 29 is not a size this app has; 12 is `HelmSpace.s5` and 28 is
        // `HelmIconPlate`'s, and they happen to add to the system's total —
        // which is the one arrangement of this strip that is both the system's
        // height and on Helm's ladders. It was 9 and 46, the mockup's strip,
        // derived the same way from the same plate.
        .padding(.vertical, HelmSpace.s5)
        // On the same column as the content below it. Which column that is
        // depends on the page: a grouped Form is capped at 744 pt and centred,
        // so its header is too — but a full-bleed page draws its toolbar at a
        // flat 20 pt inset across the whole pane, and a centred header above
        // it walks away as the window grows. Measured on a 1400 pt window: the
        // title sat 203 pt right of the controls beneath it. It has never
        // been seen because at the default window the pane is 690 pt —
        // narrower than the column, where the two rules agree.
        .frame(maxWidth: bleeds ? .infinity : HelmLayout.settingsColumn)
        // The lighting goes on the pane-wide frame and not the one above it:
        // macOS lights the whole strip, and on a grouped-`Form` page the frame
        // above is capped at the 744 pt column and centred, so a background
        // there would be a lit band floating in an unlit pane.
        .frame(maxWidth: .infinity, alignment: bleeds ? .leading : .center)
        .modifier(HeaderEdgeLight(lit: Self.isLit(hovering: hovering, active: activeState,
                                                  scrolled: scrolled,
                                                  standsOnStillContent: standsOnStillContent),
                                  live: Self.isLive(hovering: hovering, active: activeState,
                                                    scrolled: scrolled),
                                  overContent: overContent))
        .onHover { hovering = $0 }
    }
}

public extension View {
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
    /// away (`ThePageHeaderCarriesNoRuleTests`) under a different name.
    ///
    /// **Where the window has a toolbar, the header goes there instead**
    /// (`PageBarStyle`): the settings window sets `helmPageBar`, and this draws
    /// no row in the page at all. `subtitle` is the status said in words, for
    /// the style that puts it under the window's title; `trailing` is the same
    /// status as the page draws it, for the other two.
    func helmPageHeader<Trailing: View>(
        symbol: String, tint: Color, title: String, subtitle: String? = nil, bleeds: Bool = false,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(PageHeaderPlacement(symbol: symbol, tint: tint, title: title, subtitle: subtitle,
                                     bleeds: bleeds, trailing: trailing()))
    }
}

/// The row in the page, or the header in the window's bar — one question,
/// asked of the environment, so no page has to know which window it is in.
private struct PageHeaderPlacement<Trailing: View>: ViewModifier {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String?
    let bleeds: Bool
    let trailing: Trailing

    @Environment(\.helmPageBar) private var bar

    @ViewBuilder
    func body(content: Content) -> some View {
        if bar == nil {
            content.modifier(PageHeaderOverContent(symbol: symbol, tint: tint, title: title,
                                                   bleeds: bleeds, trailing: trailing))
        } else {
            content.modifier(PageBarContent(symbol: symbol, tint: tint, title: title,
                                            subtitle: subtitle, trailing: trailing))
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
/// by `ToolbarBackdrop` — the header is applied from outside the page, so a
/// preference is the only way round, and the alternative would be a hand-kept
/// list of pages living somewhere neither the page nor the band can see.
private struct PageHeaderOverContent<Trailing: View>: ViewModifier {
    let symbol: String
    let tint: Color
    let title: String
    let bleeds: Bool
    let trailing: Trailing

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
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 0.5
            } action: { _, now in
                scrolled = now
            }
            // `spacing: 0` — the gap under the header is the page's own top
            // padding, which every page already draws.
            .safeAreaInset(edge: .top, spacing: 0) {
                HelmPageHeader(symbol: symbol, tint: tint, title: title, bleeds: bleeds,
                               overContent: true, scrolled: scrolled,
                               standsOnStillContent: standsOnStillContent) { trailing }
            }
    }
}
