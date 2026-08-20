import SwiftUI

/// The strip's own chrome: the light under the pointer, the scroll edge's
/// material, and the one rule both of them ask for.
///
/// **Measured on macOS 27, on this Mac, against System Settings and Finder.**
/// Both light the *whole* top 52 pt of the content pane — from the sidebar's
/// edge to the window's right edge, the sidebar itself unchanged — and not the
/// control the pointer happens to be over: a button inside the strip moved
/// +3.0 luma while the strip moved +7.8, which is the background changing
/// behind it. The profile is flat to ±0.1 over all 51 rows, so it is a fill and
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
/// `.glassEffect`, which ARCHITECTURE.md § Surfaces reserves for a thing that
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
    /// in the key window, or the content has gone under it —
    /// `HelmPageHeader.isLit` folds the two, and this draws one appearance from
    /// the one answer.
    let lit: Bool
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
                // The same `lit` as the fill above, on purpose: one look, two
                // triggers. A rule keyed on its own question would be a second
                // appearance that happened to coincide most of the time.
                Rectangle()
                    .fill(Color.primary.opacity(lit ? Self.rule : 0))
                    .frame(height: 1 / displayScale)
            }
            .animation(HelmMotion.hover(entering: lit), value: lit)
    }
}

public struct HelmPageHeader<Trailing: View>: View {
    /// **The strip has one appearance and two reasons to wear it.**
    ///
    /// At rest it draws nothing — no fill, no rule. Both arrive together, and
    /// they arrive because the pointer is over the strip **or** because the
    /// content has gone under it. Not a fill for one reason and a rule for the
    /// other; not two overlays that coincide. One question, asked here, drawn
    /// once by `HeaderEdgeLight`.
    ///
    /// # This is deliberately not what System Settings does
    ///
    /// **Read this before "fixing" it against the measurement.** The capture is
    /// unambiguous and it disagrees with the code: System Settings' separator
    /// is present at the **scroll origin** — 2400 px of scroll-up did not
    /// remove it — and scrolling moves only the strip, by 2.6 luma. So the
    /// system draws its rule always. Helm draws it only when the pointer is
    /// over the strip or the content has gone under it. **That is a decision
    /// the owner took, not a mismatch somebody left behind**, and the reason
    /// this paragraph exists is that a number whose reason had been lost has
    /// twice been "repaired" back to the measurement it was chosen against.
    ///
    /// # The two facts, and why neither is trusted alone
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
    /// Static and taking its three facts, so it is a question a test can ask
    /// without a window, a pointer, or a render.
    static func isLit(hovering: Bool, active: ControlActiveState, scrolled: Bool) -> Bool {
        scrolled || (hovering && active == .key)
    }

    @State private var hovering = false
    @Environment(\.controlActiveState) private var activeState

    let symbol: String
    let tint: Color
    let title: String
    /// True for a page whose content spans the pane rather than sitting in the
    /// 744 pt form column — Disk, Uninstaller, Homebrew, Leftovers.
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
    let trailing: Trailing

    public init(symbol: String, tint: Color, title: String,
                bleeds: Bool = false,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.init(symbol: symbol, tint: tint, title: title, bleeds: bleeds,
                  overContent: false, scrolled: false, trailing: trailing)
    }

    /// Internal, so neither fact can be reached from outside `HelmUI`: the
    /// structural claim stays `helmPageHeader`'s to make, and the live one
    /// stays the scroll view's to report.
    init(symbol: String, tint: Color, title: String, bleeds: Bool,
         overContent: Bool, scrolled: Bool,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.bleeds = bleeds
        self.overContent = overContent
        self.scrolled = scrolled
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
    func helmPageHeader<Trailing: View>(
        symbol: String, tint: Color, title: String, bleeds: Bool = false,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(PageHeaderOverContent(symbol: symbol, tint: tint, title: title,
                                       bleeds: bleeds, trailing: trailing()))
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
private struct PageHeaderOverContent<Trailing: View>: ViewModifier {
    let symbol: String
    let tint: Color
    let title: String
    let bleeds: Bool
    let trailing: Trailing

    @State private var scrolled = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 0.5
            } action: { _, now in
                scrolled = now
            }
            // `spacing: 0` — the gap under the header is the page's own top
            // padding, which every page already draws.
            .safeAreaInset(edge: .top, spacing: 0) {
                HelmPageHeader(symbol: symbol, tint: tint, title: title, bleeds: bleeds,
                               overContent: true, scrolled: scrolled) { trailing }
            }
    }
}
