import SwiftUI

/// **The toolbar's action capsule: one Liquid Glass shape that morphs as
/// which actions are visible changes, rather than an item entering or
/// leaving the bar.**
///
/// Before this file, Homebrew's Upgrade and Refresh were two separate plain
/// `NSToolbarItem`s that happened to share one glass capsule because AppKit
/// draws adjacent bordered items that way (WWDC25-310) — and hiding one of
/// them (`NSToolbarItem.isHidden`) collapsed its width, which is an AppKit
/// relayout AppKit itself animates: Refresh visibly slid to make room, on
/// every visit to the Updates tab. `SettingsToolbar` now builds a single
/// `helm.actions` item hosting this capsule instead, so the whole shape is
/// one SwiftUI subtree AppKit lays out once and never reflows.
///
/// **The reserve.** The back layer is every *declared* action, hidden and
/// laid out at its natural width — that is what the hosted item's own
/// intrinsic size answers, so the capsule never resizes as actions come and
/// go, which is what keeps a still action still: `ZStack(alignment:
/// .trailing)` puts the front layer's visible buttons flush with the
/// trailing edge of that reserve, so a button already there (Refresh) never
/// moves and a button that appears (Upgrade) grows out of the space already
/// reserved to its left.
///
/// **The model is `@Observable`, changed synchronously — not
/// `ObservableObject`.** Helm has no other `@Observable` model; this is the
/// first, and it is here because it was measured against the alternative and
/// not merely preferred: an `ObservableObject` changed synchronously from
/// inside `SettingsToolbar`'s own `patchActions` — the same call site this
/// model is written from — logged two SwiftUI observation faults per flip in
/// a probe (engineer, this Mac); the `@Observable` model logged
/// none. A deferred, one-hop write was also tried and rejected: it adds a
/// full run-loop turn of lag between "Upgrade should be visible" and the
/// capsule actually showing it, and raises the same reading/payload question
/// `CLAUDE.md` already answers for a `DispatchQueue.main.async` hop — nothing
/// here needs a hop at all, because `patchActions` already runs on the main
/// actor.
@MainActor
@Observable
public final class HelmToolbarActionsModel {
    /// Data only — no closures: none of `HelmToolbarAction.Kind`'s closures, nor
    /// a menu item's `perform`, ever reach here — only what a button or a
    /// menu draws itself from.
    public struct Entry: Equatable, Sendable {
        public let id: String
        public let title: String
        public let symbol: String
        public let isEnabled: Bool
        /// Spinning while `true` — `HelmToolbarAction.isBusy`'s own header,
        /// in `HelmWindowToolbar.swift`, says why only a `.button` entry
        /// ever carries `true` here.
        public let isBusy: Bool
        public let kind: EntryKind
        /// The toggle's own two glyphs and two words, when it has them
        /// (`HelmToolbarToggleFace`); nil draws the accent-tinted toggle.
        public let toggleFace: HelmToolbarToggleFace?

        public init(id: String, title: String, symbol: String, isEnabled: Bool,
                    isBusy: Bool = false, kind: EntryKind = .button,
                    toggleFace: HelmToolbarToggleFace? = nil) {
            self.id = id
            self.title = title
            self.symbol = symbol
            self.isEnabled = isEnabled
            self.isBusy = isBusy
            self.kind = kind
            self.toggleFace = toggleFace
        }
    }

    /// What an entry draws as — the closure-free twin of
    /// `HelmToolbarAction.Kind`, for the same reason `Entry` itself carries no
    /// closure.
    public enum EntryKind: Equatable, Sendable {
        case button
        case toggle(isOn: Bool)
        case menu([MenuEntry])
    }

    /// One item in a `.menu` entry's own submenu — a check and a title, with
    /// no `perform` of its own: a press reaches it by `id` through
    /// `pressItem`, below, the way a plain entry's press reaches `press`.
    public struct MenuEntry: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let isOn: Bool
        public let isEnabled: Bool

        public init(id: String, title: String, isOn: Bool, isEnabled: Bool) {
            self.id = id
            self.title = title
            self.isOn = isOn
            self.isEnabled = isEnabled
        }
    }

    /// Every action the page has declared, in the order it declared them —
    /// the fixed reserve the capsule's back layer draws from. Not `public`:
    /// `HelmToolbarActionsCapsule.body`, in this same module, is the only
    /// non-test reader — a test reaches it through `@testable import HelmUI`,
    /// which internal access already answers for.
    private(set) var declared: [Entry] = []
    /// The subset of `declared` currently shown — always a subsequence of
    /// `declared` in the same order. `public`: `SettingsToolbar`, in another
    /// module, reads this to decide whether the visible set actually moved
    /// before writing it again.
    public private(set) var visibleIDs: [String] = []
    /// Mirrors a frozen `PageBar`'s own inertness (`SettingsToolbar.freeze`)
    /// — a custom-view item has no `NSToolbarItem.isEnabled` of its own to
    /// dim, so this is how that fact reaches the buttons this model feeds.
    /// Not `public`, on the same grounds as `declared` above: only this
    /// module's own `body` reads it outside a test.
    private(set) var isInteractive = true

    /// **Whether AppKit currently draws this window's own chrome active** —
    /// the same fact its private `_hasActiveAppearance` answers, and
    /// `window.isKeyWindow || window.isMainWindow` was measured to equal in
    /// every state produced (`SettingsWindow`'s own header, above its four
    /// `windowDid…` methods, has the reading and where it was taken).
    /// **Not** SwiftUI's `controlActiveState`: that reads `.inactive` in two
    /// of those states — a nonactivating panel taking key while this window
    /// stays main, and a sheet — where AppKit's platter stays lit. Read by
    /// `HelmToolbarActionsCapsule.glyph(_:)` and the `disabledGlyphOpacity`
    /// it calls, to dim a plain `Label`'s ink the same amount AppKit's own
    /// toolbar button glyph dims by — the capsule's *glass* needs no such value:
    /// it follows AppKit's own active appearance, which in a real app equals
    /// `isKeyWindow || isMainWindow`, proven by pinning this environment key on
    /// a live capsule and reading zero glass difference either way
    /// (`HelmToolbarActionsCapsule`'s own header, above `struct
    /// HelmToolbarActionsCapsule`, has that measurement). Not `public`, on
    /// the same grounds as `isInteractive` above.
    private(set) var appearsActive = true

    /// Never observed by SwiftUI, and never anything but data going the
    /// other way: `id` in, nothing back. Set once by whoever owns the model:
    /// `SettingsToolbar.makeActionsItem`.
    @ObservationIgnored public var press: (String) -> Void = { _ in }
    /// The `.menu` twin of `press`: the entry's own `id`, then the pressed
    /// item's — nothing back, on the same grounds.
    @ObservationIgnored public var pressItem: (String, String) -> Void = { _, _ in }

    public init() {}

    /// **Guarded on equality — every setter is.** The
    /// `@Observable` macro's synthesised setter notifies observers whenever a
    /// tracked property is *written*, whether or not the new value differs
    /// from the old one, and Homebrew republishes its whole toolbar
    /// declaration on every keystroke in its search field
    /// (`HomebrewSettingsPage`'s own `.helmWindowToolbar` call, inside a view
    /// that redraws on every character). Without this guard, the capsule's
    /// `GlassEffectContainer` would re-evaluate its glass identities on every
    /// keystroke rather than only when the declared or visible set actually
    /// moves.
    public func setDeclared(_ entries: [Entry]) {
        guard declared != entries else { return }
        declared = entries
    }

    public func setVisibleIDs(_ ids: [String]) {
        guard visibleIDs != ids else { return }
        visibleIDs = ids
    }

    public func setInteractive(_ value: Bool) {
        guard isInteractive != value else { return }
        isInteractive = value
    }

    /// Called by `SettingsToolbar.setWindowAppearsActive(_:)` with the activity
    /// `SettingsWindow` hands it — its own direct read of the window's `isKeyWindow` and
    /// `isMainWindow`; see this type's own `appearsActive` header for why the value
    /// crosses in from there rather than being read here.
    public func setAppearsActive(_ value: Bool) {
        guard appearsActive != value else { return }
        appearsActive = value
    }
}

/// The capsule itself — hosted by `SettingsToolbar.makeActionsItem` in an
/// `NSHostingView` with no AppKit border of its own (`isBordered = false`):
/// a bordered item wraps its view in a second glass, measured, so the
/// capsule's own `.glassEffect` would sit inside another one.
///
/// **Why `body` does not read `\.controlActiveState`, and does not override
/// it either.** A Helm Dev probe saw no movement in `\.controlActiveState`
/// read from this capsule's own host, nor from `helm.tabs`' own switcher
/// host, through a real deactivate/reactivate cycle — log not kept. So this
/// view never asks its own hosting for the answer, for the glyph's own dim
/// (`HelmToolbarActionsModel.appearsActive`, fed by `SettingsWindow`'s direct
/// read of the window itself rather than by any SwiftUI content — that
/// type's own header has the reading).
///
/// **The glass needs no such value at all, and used to carry one anyway.**
/// This `body` once re-injected `model.appearsActive` as
/// `.environment(\.controlActiveState, ...)` on the theory that it was the
/// key AppKit's own glass reads — measured false: pinning that key to `.key`,
/// to `.inactive`, and replacing it with `\.appearsActive` instead, all read
/// zero glass differences against a live capsule's own baseline. What moves
/// the glass instead, in every fixture built to check it, is AppKit's own
/// active appearance, which in a real app equals `isKeyWindow || isMainWindow`
/// — no SwiftUI environment read back out of it changed the reading either
/// way; a fixture built line-for-line from this type's own shape (the
/// `ZStack`, the hidden reserve,
/// `glassEffectID`/`glassEffectUnion`/`glassEffectTransition`, all of it) read
/// its glass moving with the window with no override and no rebuild, across a
/// same-process deactivate and a genuine switch to a second, independently
/// running app and back — appearance not recorded for the same-process run,
/// and the two-process run logged only the moment of the notification. So the
/// override was deleted; nothing here asks for `controlActiveState` any more.
///
/// **What is still unexplained.** Every fixture built to test this — a
/// line-for-line copy of this type's own shape, a standalone toolbar built to
/// the same exact shape, and a real two-process activation switch — reads the
/// glass following AppKit's own active appearance on its own, with no
/// rebuild. A probe on Helm Dev read the opposite: flipping
/// `model.appearsActive` on an already-rendered capsule left its glass at the
/// value it was built with, even with the override (since removed) in place
/// and correctly returning `.inactive`. No fixture since has reproduced that
/// reading, and nothing that differs between Helm Dev and every fixture above
/// has been found. `SettingsToolbar.rebuildActionsHost(_:)` keeps two callers
/// for two different reasons, both under Liquid Glass only (a flat capsule draws no
/// glass and follows the window by the model's `appearsActive`):
/// `setWindowAppearsActive(_:)` calls it on every
/// live transition for the unresolved reason above, and
/// `correctActionsGlassOnFirstAttach(_:)` calls it at most once, and only for
/// a bar built while the window reads inactive, for the
/// separate, confirmed reason its own header gives.
/// What its glass draws after a live transition was not seen on a screen.
public struct HelmToolbarActionsCapsule: View {
    let model: HelmToolbarActionsModel
    @Namespace private var glassSpace
    /// Which glyph-dim constant applies — see `inactiveGlyphOpacity`'s and
    /// `disabledGlyphOpacity`'s own headers.
    @Environment(\.colorScheme) private var colorScheme
    /// Which look the entries are backed in: glass unless the environment says flat
    /// (`HelmBarAppearance`, on why the environment's default is the glass).
    @Environment(\.helmBarAppearance) private var appearance

    /// **4 pt: the trailing inset the status zone falls back to** when it has no status or its ink
    /// cannot be measured (`StatusZoneView.trailingInset(for:barHeight:)`), and what
    /// `StatusZoneView.boxMargin` takes from 8. The number is a reading of AppKit's toolbar, kept
    /// as a number: a custom-view item with `isBordered = false`, last in an `NSToolbar`, ended
    /// 4.0 pt from the window's trailing edge at 1060 pt where a bordered one ended 8.0 pt.
    /// The capsule carries an inset of its own only where its caller hands one
    /// (`trailingInset`, 0 by default): `SettingsToolbar.actionsHost(_:for:)` hands this number
    /// where no search follows the capsule.
    public static let edgeMargin: CGFloat = 4

    /// **36 pt — AppKit's own bordered toolbar button's height**, measured
    /// against a live window, so the two zones draw level rather than each
    /// choosing a size of its own.
    static let side: CGFloat = 36

    /// **The glyph's own dim, when the model reads inactive — a second gap
    /// from the same measurement, separate from the glass.** A plain SwiftUI
    /// `Label`'s ink does not move with `controlActiveState` on its own:
    /// measured against a live window, a `Label` in a plain `Button` kept
    /// full ink (Dark 255, Light 0) where AppKit's own bordered toolbar
    /// button's glyph reads Dark 93, Light 169. Solved as the opacity a
    /// full-ink glyph needs over that row's own flat, inactive chrome (Dark bg
    /// 40, Light bg 244) to land on the target: `bg·(1−x) + ink·x = target`.
    /// Two constants and not one, because the algebra does not agree between
    /// appearances — a white glyph over one background, a black glyph over a
    /// different one — which is the same reason `Clamped.swift` keeps a
    /// not-a-number's two bounds apart rather than collapsing them.
    static let inactiveGlyphOpacityDark: Double = 0.25   // (93−40)/(255−40) ≈ 0.2465
    static let inactiveGlyphOpacityLight: Double = 0.31  // (244−169)/244 ≈ 0.3074

    /// **The glyph's own dim, when the entry itself is disabled — the owner's
    /// "as AppKit" for a disabled action.** Not `inactiveGlyphOpacityDark` /
    /// `inactiveGlyphOpacityLight` above: those answer "the window reads
    /// inactive" (`HelmToolbarActionsModel.appearsActive` false — neither key
    /// nor main), these answer "the action refuses," and AppKit dims the two
    /// differently.
    ///
    /// **`.disabled(...)` on `entryControl(entry)`, in `body` below, halves
    /// whatever opacity this glyph draws, on top of it** — the automatic dim
    /// a disabled `.plain` `Button`, and a `Menu` styled as one, applies to
    /// its label (a bare `Label` under `.disabled(true)` keeps its ink, and
    /// `.environment(\.isEnabled, true)` inside the label does not undo it),
    /// found by drawing a fixed value and reading what a screen actually
    /// shows (an out-of-tree probe, 2026-09-28, both appearances, key and not
    /// key): drawing `1.0` / `inactiveGlyphOpacity` read back as 0.500 Dark /
    /// 0.520 Light in a key window and 0.126 / 0.163 not key — against a live
    /// disabled `NSToolbarButton`'s 0.240 / 0.313 key and 0.178 / 0.260 not
    /// key, ours came out brighter than AppKit when key and dimmer when not, never
    /// AppKit's own number, because that automatic halving sits between
    /// whatever this file draws and what lands on screen. So these four are
    /// not solved against AppKit's own reading directly the way
    /// `inactiveGlyphOpacityDark` above is — the halving itself is one clean
    /// x0.5 in-process (no display involved), but what a screen reads back
    /// from the halved glyph varies across the four states and moves with
    /// the display (0.479–0.552 across the four states, in the engineer's
    /// own on-screen read-back) — each is fit as a line through two measured
    /// (drawn, read-back) points and solved for AppKit's own number as the
    /// target of the *read-back*, not of what this file sets.
    static let disabledGlyphOpacityDark: Double = 0.49
    static let disabledGlyphOpacityLight: Double = 0.60
    static let disabledInactiveGlyphOpacityDark: Double = 0.35
    static let disabledInactiveGlyphOpacityLight: Double = 0.50

    /// Non-zero exactly when this capsule is a toolbar's own last item (no
    /// search follows it) — see `edgeMargin`'s own header for the measurement
    /// this closes.
    public let trailingInset: CGFloat

    /// **The two numbers a flat capsule dims by in a window that is not active,
    /// one per appearance.** The caller owns them (the name zone's, which
    /// `HelmApp` can reach and this module cannot); nil leaves the capsule on
    /// `inactiveGlyphOpacityDark` / `inactiveGlyphOpacityLight`, AppKit's own.
    public struct InactiveInk: Equatable, Sendable {
        public let dark: Double
        public let light: Double

        public init(dark: Double, light: Double) {
            self.dark = dark
            self.light = light
        }
    }

    private let flatInactiveInk: InactiveInk?

    public init(_ model: HelmToolbarActionsModel, trailingInset: CGFloat = 0,
                flatInactiveInk: InactiveInk? = nil) {
        self.model = model
        self.trailingInset = trailingInset
        self.flatInactiveInk = flatInactiveInk
    }

    /// **How far an inactive window dims the capsule's ink.** Under `.flat` with
    /// numbers handed in, those; otherwise `inactiveGlyphOpacityDark` or
    /// `inactiveGlyphOpacityLight`, picked by the scheme. Static, so a test asks it
    /// without drawing.
    static func inactiveOpacity(appearance: HelmBarAppearance, dark: Bool,
                                flatInactiveInk: InactiveInk?) -> Double {
        if appearance == .flat, let ink = flatInactiveInk { return dark ? ink.dark : ink.light }
        return dark ? inactiveGlyphOpacityDark : inactiveGlyphOpacityLight
    }

    /// `inactiveOpacity(appearance:dark:flatInactiveInk:)` for the scheme and the
    /// look this capsule draws in, read here where the value is drawn rather than cached.
    private var inactiveGlyphOpacity: Double {
        Self.inactiveOpacity(appearance: appearance, dark: colorScheme == .dark,
                             flatInactiveInk: flatInactiveInk)
    }

    /// The disabled twin of `inactiveGlyphOpacity`, above — one of the four
    /// `disabled…GlyphOpacity…` constants, picked by `colorScheme` and by
    /// `model.appearsActive`, where `inactiveGlyphOpacity` is picked by
    /// `colorScheme`, the look and the numbers handed in; see those constants'
    /// own header for why a disabled entry needs both.
    private var disabledGlyphOpacity: Double {
        if colorScheme == .dark {
            return model.appearsActive ? Self.disabledGlyphOpacityDark : Self.disabledInactiveGlyphOpacityDark
        }
        return model.appearsActive ? Self.disabledGlyphOpacityLight : Self.disabledInactiveGlyphOpacityLight
    }

    public var body: some View {
        ZStack(alignment: .trailing) {
            // The fixed reserve: every declared action, laid out and never
            // drawn — its width is the capsule's own intrinsic width, which
            // is what stops the hosted item resizing as `visibleIDs` moves.
            // Every kind costs `Self.side`.
            HStack(spacing: 0) {
                ForEach(model.declared, id: \.id) { _ in
                    Color.clear.frame(width: Self.side, height: Self.side)
                }
            }
            .hidden()
            .accessibilityHidden(true)

            GlassEffectContainer(spacing: HelmSpace.s4) {
                HStack(spacing: 0) {
                    ForEach(visible, id: \.id) { entry in
                        backing(entryControl(entry).help(entry.title)
                                    .disabled(!entry.isEnabled || !model.isInteractive),
                                for: entry)
                    }
                }
            }
        }
        // Outside the `ZStack`, so it widens the hosted view's own intrinsic
        // size rather than reserving room the buttons' trailing alignment
        // would swallow. The hidden reserve row above is unaffected: it is
        // laid out from `model.declared`, and the inset is the caller's,
        // which `SettingsToolbar.actionsHost(_:for:)` decides from `content.search`.
        .padding(.trailing, trailingInset)
    }

    /// `declared`, filtered to `visibleIDs` — declared order preserved, so a
    /// page that lists Upgrade before Refresh always shows them in that
    /// order however many are visible.
    private var visible: [HelmToolbarActionsModel.Entry] {
        model.declared.filter { model.visibleIDs.contains($0.id) }
    }

    /// **What sits behind one entry: under `.liquidGlass` the glass chain below,
    /// under `.flat` nothing.** Every kind takes `.regular.interactive()`: each
    /// is pure SwiftUI (`Button`, `Toggle`, `Menu`), so whatever that adds is
    /// shared with the control's own press, which is what Homebrew's Upgrade and
    /// Refresh already rely on. Under `.flat` the container around the entries
    /// holds no glass; that it then draws nothing, and that the entries'
    /// appearing and leaving reads acceptably without the glass morph, were not
    /// seen on a screen.
    @ViewBuilder
    private func backing(_ content: some View, for entry: HelmToolbarActionsModel.Entry) -> some View {
        switch appearance {
        case .liquidGlass:
            content
                .glassEffect(.regular.interactive())
                .glassEffectID(entry.id, in: glassSpace)
                .glassEffectUnion(id: "actions", namespace: glassSpace)
                .glassEffectTransition(
                    HelmMotion.morphs(reduceMotion: HelmMotion.reduceMotion)
                        ? .matchedGeometry : .identity)
        case .flat:
            content
        }
    }

    /// **The glyph every kind shares.** The frame and the hit shape sit on it
    /// rather than on whatever wraps it, for the reason the button case's own
    /// comment used to give here: a `.plain` button's tap target is its
    /// label's rendered bounds, which for an icon-only `Label` is the bare
    /// glyph, and a frame applied outside the control changes only layout,
    /// not what AppKit's hit test asks SwiftUI for.
    ///
    /// **13 pt, medium weight, large scale — the size AppKit draws a live
    /// toolbar button's symbol at**, a bordered item with a target and an
    /// action, as Refresh is. Read 2026-09-28 on macOS 27.2: a bare
    /// `NSToolbar` at 1060 pt holding one such `NSToolbarItem`, which AppKit
    /// draws as an `NSToolbarButton`; the bitmap in that button's own image
    /// layer (2×) compared pixel for pixel against the same symbol under every
    /// `NSImage.SymbolConfiguration` from 11 to 24 pt in half points, four
    /// weights and three scales, among those that come out at the same pixel
    /// size: 13 pt / medium / large matched with no difference at all for
    /// `arrow.clockwise`, `text.alignleft`,
    /// `line.3.horizontal.decrease.circle` and `magnifyingglass`, in Light and
    /// Dark alike, and the nearest other was off by 5.2 to 8.7 alpha levels a
    /// pixel — the configuration the same method read for a collapsed
    /// `NSSearchToolbarItem`'s magnifier on 2026-09-27. The same item with no
    /// action is a different drawing: AppKit puts it through
    /// `NSToolbarImageView`, greyed as disabled, at 20 pt / regular / medium
    /// (same method, 2026-09-27), which is what this glyph was set to until
    /// 2026-09-28 and read 17.5 × 21.0 pt of ink for Refresh beside the live
    /// button's 14.5 × 17.5. With no font of its own the `Label` takes
    /// the hosting view's default body size, smaller again — the owner's "very
    /// small". The glyph sits inside the same `Self.side` frame whatever its
    /// size, so no reserve, fold prediction or edge margin reads it.
    @ViewBuilder
    private func glyph(_ entry: HelmToolbarActionsModel.Entry, symbol: String? = nil) -> some View {
        let isDisabled = !entry.isEnabled || !model.isInteractive
        Label(entry.title, systemImage: symbol ?? entry.symbol)
            .font(.system(size: 13, weight: .medium))
            .imageScale(.large)
            .labelStyle(.iconOnly)
            .helmSteadySpin(entry.isBusy)
            .frame(width: Self.side, height: Self.side)
            .contentShape(Rectangle())
            // AppKit's own dim does not reach a plain SwiftUI `Label`'s ink on
            // its own — `inactiveGlyphOpacityDark`'s own header has the
            // reading and the algebra behind these two numbers. A disabled
            // entry is a third case again, and it is not simply this
            // opacity applied to a full-ink glyph: `.disabled(...)` on
            // `entryControl(entry)`, in `body` above, halves whatever
            // opacity lands here on top of it, which is why
            // `disabledGlyphOpacityDark`'s own header, above, solves its
            // four constants against the *read-back* rather than against
            // AppKit's own number directly.
            .opacity(isDisabled ? disabledGlyphOpacity : (model.appearsActive ? 1 : inactiveGlyphOpacity))
    }

    /// **One entry, drawn as its own kind.** A button and a toggle both press
    /// through `model.press`, which reads `HelmToolbarAction.Kind` back apart
    /// on the `SettingsToolbar` side (`SettingsToolbar.perform(_:)`); a menu
    /// has no press of its own; each item presses through `model.pressItem`.
    @ViewBuilder
    private func entryControl(_ entry: HelmToolbarActionsModel.Entry) -> some View {
        switch entry.kind {
        case .button:
            Button {
                model.press(entry.id)
            } label: {
                glyph(entry)
            }
            .buttonStyle(.plain)
        case .toggle(let isOn):
            if let face = entry.toggleFace {
                // The state is the glyph, and never a tint: an accent fill
                // beside the capsule's other glyphs reads as a different kind
                // of control. The word the glyph stands for is the
                // accessibility value, since the label stays the name.
                Button {
                    model.press(entry.id)
                } label: {
                    glyph(entry, symbol: face.symbol(isOn: isOn, on: entry.symbol))
                }
                .buttonStyle(.plain)
                .accessibilityValue(face.value(isOn: isOn))
            } else {
                Button {
                    model.press(entry.id)
                } label: {
                    if isOn {
                        glyph(entry).foregroundStyle(Color.accentColor)
                    } else {
                        glyph(entry)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        case .menu(let items):
            Menu {
                ForEach(items) { item in
                    Toggle(item.title, isOn: Binding(
                        get: { item.isOn },
                        set: { _ in model.pressItem(entry.id, item.id) }))
                        .disabled(!item.isEnabled)
                }
            } label: {
                glyph(entry)
            }
            .menuIndicator(.hidden)
            // Without these two, AppKit draws a `Menu` as its own bordered
            // pull-down button — measured at 60×44 against every other
            // entry's 36×36 — so the capsule's reserve (every declared
            // action laid out at `Self.side`) stopped matching what a menu
            // entry actually occupies, and the capsule resized whenever one
            // came in or out of `visibleIDs`, which is the relayout the
            // reserve exists to prevent. `.buttonStyle(.plain)` alone is not
            // enough: it is `.menuStyle(.button)` that drops the pull-down
            // bezel.
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }
}
