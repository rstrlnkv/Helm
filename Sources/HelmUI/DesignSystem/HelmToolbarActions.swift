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
    /// Data only — no closures. A frozen `PageBar`'s retention guard
    /// (`testAFrozenBarDropsTheClosuresItsContentCaptured`) has to stay true
    /// of this model as well: none of `HelmToolbarAction.Kind`'s closures, nor
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

        public init(id: String, title: String, symbol: String, isEnabled: Bool,
                    isBusy: Bool = false, kind: EntryKind = .button) {
            self.id = id
            self.title = title
            self.symbol = symbol
            self.isEnabled = isEnabled
            self.isBusy = isBusy
            self.kind = kind
        }
    }

    /// What an entry draws as — the closure-free twin of
    /// `HelmToolbarAction.Kind`, for the same reason `Entry` itself carries no
    /// closure.
    public enum EntryKind: Equatable, Sendable {
        case button
        case toggle(isOn: Bool)
        case menu([MenuEntry])
        /// The closure-free twin of `.segmented` — the switcher only needs
        /// its own options and which one is current; a picked option reaches
        /// `SettingsToolbar` through `pressItem`, the same route a `.menu`
        /// item's own press already takes. `reserveWidth` is carried rather
        /// than computed here: only `SettingsToolbar.actionEntries(for:)`,
        /// in `HelmApp`, has a real toolbar and window to attach a measuring
        /// switcher to (`reserveWidth(_:)`'s own header, below, says why a
        /// detached one will not do), and this module may not reach across
        /// that boundary to ask for one.
        case segmented([SegmentEntry], selectedID: String, reserveWidth: CGFloat)
    }

    /// One option in a `.segmented` entry — `HelmToolbarTab`'s own triple
    /// (id, word, glyph), carried across the same closure-free boundary
    /// `MenuEntry` already crosses for `.menu`.
    public struct SegmentEntry: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let symbol: String

        public init(id: String, title: String, symbol: String) {
            self.id = id
            self.title = title
            self.symbol = symbol
        }
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
    /// `declared` in the same order. `public`: `SettingsToolbar.patchActions`,
    /// a genuinely different module, reads this to decide whether the
    /// visible set actually moved before writing it again.
    public private(set) var visibleIDs: [String] = []
    /// Mirrors a frozen `PageBar`'s own inertness (`SettingsToolbar.freeze`)
    /// — a custom-view item has no `NSToolbarItem.isEnabled` of its own to
    /// dim, so this is how that fact reaches the buttons this model feeds.
    /// Not `public`, on the same grounds as `declared` above: only this
    /// module's own `body` reads it outside a test.
    private(set) var isInteractive = true

    /// Never observed by SwiftUI, and never anything but data going the
    /// other way: `id` in, nothing back. Set once, at construction, by
    /// `SettingsToolbar.makeActionsItem`.
    @ObservationIgnored public var press: (String) -> Void = { _ in }
    /// The `.menu` twin of `press`: the entry's own `id`, then the pressed
    /// item's — nothing back, on the same grounds.
    @ObservationIgnored public var pressItem: (String, String) -> Void = { _, _ in }

    public init() {}

    /// **Guarded on equality — every one of the three setters is.** The
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
}

/// The capsule itself — hosted by `SettingsToolbar.makeActionsItem` in an
/// `NSHostingView` with no AppKit border of its own (`isBordered = false`):
/// a bordered item wraps its view in a second glass, measured, so the
/// capsule's own `.glassEffect` would sit inside another one.
public struct HelmToolbarActionsCapsule: View {
    // Internal, not `private`: a test reaching this through `@testable import
    // HelmUI` (`TheUpgradeAllButtonDoesNotChangeTheToolbarsItemCountTests`) is
    // the only reader outside `body` — SwiftUI's own AX tree for a button
    // built from `Label` is not reliably walkable off a window this harness
    // never orders on screen, so a test asks the model directly instead.
    let model: HelmToolbarActionsModel
    @Namespace private var glassSpace

    /// **The margin an `isBordered = false` custom-view item is short of an
    /// AppKit-drawn one, when it is the toolbar's own last item.** Measured
    /// against a bare `NSToolbar`, one 36×36 custom view, nothing else
    /// changed: at 1060 pt, `isBordered = false` left the view's own trailing
    /// edge 4.0 pt from the window's, `isBordered = true` left it 8.0 pt
    /// (`TheLastItemsGlassSitsAsFarFromTheEdgeTests`, `BareToolbarEdgeProbeDelegate`).
    /// The same 4.0 pt shortfall showed on the real bar: Hosts' `helm.actions`
    /// — the toolbar's last item on that page — sat 4.0 pt from the window's
    /// trailing edge at 1060 pt, where Uninstaller's `helm.search` field,
    /// AppKit's own control, rested 8.0 pt from it at the same width. The
    /// capsule stays `isBordered = false` regardless — a bordered item wraps
    /// it in a second glass, this type's own header — so the missing 4 pt is
    /// made up here, in the content, and only where nothing draws after the
    /// capsule to already carry it (`trailingInset`, driven by
    /// `SettingsToolbar.makeActionsItem` from `content.search == nil`):
    /// Homebrew and Uninstaller, where search follows the capsule, are
    /// unaffected.
    public static let edgeMargin: CGFloat = 4

    /// **36 pt — AppKit's own bordered toolbar button's height**, measured
    /// against a live window, so the two zones draw level rather than each
    /// choosing a size of its own.
    static let side: CGFloat = 36

    /// Non-zero exactly when this capsule is the bar's own last item (no
    /// search follows it) — see `edgeMargin`'s own header for the measurement
    /// this closes.
    public let trailingInset: CGFloat

    public init(_ model: HelmToolbarActionsModel, trailingInset: CGFloat = 0) {
        self.model = model
        self.trailingInset = trailingInset
    }

    public var body: some View {
        ZStack(alignment: .trailing) {
            // The fixed reserve: every declared action, laid out and never
            // drawn — its width is the capsule's own intrinsic width, which
            // is what stops the hosted item resizing as `visibleIDs` moves.
            // `reserveWidth(_:)` is `Self.side` for every button-shaped kind
            // and a `.segmented` entry's own measured glyph width for that one
            // — see its own header.
            HStack(spacing: 0) {
                ForEach(model.declared, id: \.id) { entry in
                    Color.clear.frame(width: reserveWidth(entry), height: Self.side)
                }
            }
            .hidden()
            .accessibilityHidden(true)

            GlassEffectContainer(spacing: HelmSpace.s4) {
                HStack(spacing: 0) {
                    ForEach(visible, id: \.id) { entry in
                        // **Every kind takes the same glass shape, `.segmented`
                        // included — but not the same `interactive()`.** It
                        // used to skip the glass entirely on the assumption
                        // that AppKit already drew Liquid Glass around a
                        // segmented control wherever it sat — measured false
                        // on the live item: `helm.actions` stays
                        // `isBordered = false` (`SettingsToolbar.makeActionsItem`'s
                        // own body, beside that assignment, and this type's own
                        // header above — a bordered item would wrap a
                        // button-shaped sibling's own glass a second time), and
                        // AppKit's own bordered-item chrome is what the centre
                        // tabs draw theirs with (`NSGlassEffectView` sits above
                        // that item's hosted view; nothing does above this
                        // one), so the switcher drew with neither AppKit's
                        // glass nor this one — the owner's first report
                        // (2026-09-25). `TheViewModeSwitcherSitsOnOneGlassTests
                        // .testTheSwitcherSitsInsideExactlyOneGlassAndNoAppKitPlatter`
                        // proves the glass *shape* — not only a marker layer,
                        // which belongs to the whole `GlassEffectContainer`
                        // and passes just as well with the switcher bare
                        // beside a glassy button — actually covers the
                        // switcher's own frame, on the real page.
                        //
                        // **`interactive()` is a second thing, and `glass(for:)`
                        // below withholds it from `.segmented` alone.** Reading
                        // what SwiftUI itself exports — `xcrun swift-demangle`
                        // over the SDK's `SwiftUICore.tbd` — shows
                        // `Glass.interactive(_:)` routed through
                        // `_Glass.interactive(_:variant:sources:)`, which
                        // carries a `FlexInteraction.Configuration` and a
                        // `FlexInteraction.GestureFactory` that builds its own
                        // SwiftUI gesture over the glass's shape: a second,
                        // independent press recogniser laid over whatever the
                        // glass wraps, on paper. **Not measured at runtime**:
                        // tester's own harness (2026-09-26), comparing the live
                        // item under `.regular` against `.regular.interactive()`
                        // offscreen, found the two the same in the view tree,
                        // every gesture recogniser, every tracking area, the
                        // hit-test target and every glass layer's own
                        // properties — so what follows about the recogniser is
                        // read off the SDK's exported symbols, not seen to
                        // happen on this control. Every other kind here is pure
                        // SwiftUI (`Button`, `Toggle`, `Menu`), so whatever that
                        // recogniser costs there is shared with the control's
                        // own press, which is what Homebrew's Upgrade and
                        // Refresh already rely on.
                        // A `.segmented` entry's content is `HelmToolbarSwitcher`,
                        // an `NSViewRepresentable` around `NSSegmentedControl`.
                        // Designer's own before/after films (pass 2, 2026-09-26,
                        // 60 fps, same session, differing only in this line's
                        // `.regular` vs `.regular.interactive()`) measured, with
                        // `.regular`: the glass flash gone (Dark: 58–90 before
                        // this line, 41–42 after; Light: 255 before, 241–242
                        // after), the capsule's outline swell on a press gone
                        // (1.0–1.5 pt before, 0.0 pt after), the selection
                        // indicator visible in every frame where before it was
                        // missing from 5–7 (Light), and a press on the segment
                        // already selected no longer lighting both segments
                        // (Dark: 12 frames in both films before, 0 in all four
                        // films after). Not changed by this line: a press that
                        // *moves* the selection lights both segments for 8–10
                        // frames of a 50 ms press in Dark and 5–10 in Light,
                        // against 0–4 for the centre tabs' presses in the same
                        // films — at that point this entry's item was not yet
                        // in `NSToolbar.centeredItemIdentifiers`, which moves
                        // this number, and so does hosting the capsule in
                        // AppKit's own bordered platter (below). Withholding
                        // `interactive()` touches neither
                        // this entry's glass shape, its union or its
                        // transition, nor any other kind's own interactive
                        // press.
                        //
                        // **Why it did not slide, and now does.** Filmed in a
                        // reference app (engineer, 2026-09-26, both
                        // appearances): a copy of this capsule tracks a press
                        // the classic way — the pressed segment highlighted
                        // while the old one stays selected, then a jump on
                        // release, no slide frame — with this glass, with
                        // none, and inside an `NSGlassEffectView` alike.
                        // **Not inside AppKit's own bordered platter**: the
                        // same copy wrapped there got neither tracking
                        // cleanly, and a hosting this capsule's own item
                        // never takes anyway, since it stays
                        // `isBordered = false` regardless (this type's own
                        // header above); the same
                        // copy, glass and all, lifts on the press and slides
                        // like the centre tabs once its item is listed in
                        // `NSToolbar.centeredItemIdentifiers`
                        // (`SettingsToolbar.centredIdentifiers(_:)`), and the
                        // centre tabs' own switcher stops sliding when its
                        // item is left out of that list. Measured on the live
                        // page in Helm Dev (engineer, 2026-09-26, window
                        // 1060×828; L = frames of a 250 ms hold with the old
                        // segment already dark, S = slide frames — the
                        // indicator strictly between the two segments'
                        // centres, 6 px clear of each — of a 50 ms press,
                        // B = both-lit frames of a 50 ms press): before this
                        // entry's item joined the set, L 0,0,0, S 0,0,0,
                        // B 6,6,4, in both appearances — the classic jump this
                        // paragraph opens with, no lift and no slide at all;
                        // after, Dark L 7–9, S 5–8, B 0–1, Light L 7–8, S 3–7,
                        // B 0
                        // (`ASwitcherInTheCapsuleIsCentredWithTheTabsTests`'s
                        // own header carries this reading in full). Against
                        // the centre tabs' own S 7–14, L 6–9, B 0–4 in the
                        // same films, L and B now match; S alone reads lower,
                        // and that is the metric, not a weaker slide — S only
                        // counts a frame with the indicator clear of both
                        // segments' centres, and this switcher's own travel is
                        // about 40 pt against the tabs' about 77 (designer's
                        // own frame measurements, both appearances — the
                        // segment centres are 76.8–77.2 pt apart), so the
                        // same tracking lands fewer frames inside the
                        // narrower gap it measures.
                        entryContent(entry)
                            .disabled(!entry.isEnabled || !model.isInteractive)
                            .glassEffect(glass(for: entry.kind))
                            .glassEffectID(entry.id, in: glassSpace)
                            .glassEffectUnion(id: "actions", namespace: glassSpace)
                            .glassEffectTransition(
                                HelmMotion.morphs(reduceMotion: HelmMotion.reduceMotion)
                                    ? .matchedGeometry : .identity)
                    }
                }
            }
        }
        // Outside the `ZStack`, so it widens the hosted item's own intrinsic
        // size rather than reserving room the buttons' trailing alignment
        // would swallow — `patchActionsMenu`'s reserve is unaffected, since
        // this is measured directly against `content.search`, never against
        // `model.declared`.
        .padding(.trailing, trailingInset)
    }

    /// `declared`, filtered to `visibleIDs` — declared order preserved, so a
    /// page that lists Upgrade before Refresh always shows them in that
    /// order however many are visible.
    private var visible: [HelmToolbarActionsModel.Entry] {
        model.declared.filter { model.visibleIDs.contains($0.id) }
    }

    /// **One entry's own content, before the uniform glass wrap in `body`
    /// above is applied to it.** A `.segmented` entry is the switcher itself,
    /// fixed to `.icons` — see that branch's own comment for why it is never
    /// the environment's or the tabs' style — every other kind is
    /// `entryControl(_:)`, with its own tooltip; a `.segmented` entry needs
    /// none, since each of its own segments already carries one
    /// (`HelmToolbarSwitcher.fill`'s own `setToolTip`).
    @ViewBuilder
    private func entryContent(_ entry: HelmToolbarActionsModel.Entry) -> some View {
        if case .segmented(let options, let selectedID, _) = entry.kind {
            HelmToolbarSwitcher(entry.title,
                selection: Binding(get: { selectedID },
                                   set: { model.pressItem(entry.id, $0) }),
                segments: options.map { HelmSwitcherSegment($0.id, $0.title, symbol: $0.symbol) })
                // **Always glyphs — never the environment's or the tabs'
                // label style.** The owner's own rule for this action: unlike
                // the centre tabs, a `.segmented` action in the capsule has no
                // word of its own to fall back to
                // (`HelmToolbarAction`'s own segmented initialiser fixes the
                // action's `symbol` to `""`), and a `.text` or
                // `.iconsAndText` reading meant for the centre tabs would draw
                // this one as a second, worded set of tabs beside the first.
                .environment(\.helmSwitcherStyle, .icons)
        } else {
            entryControl(entry).help(entry.title)
        }
    }

    /// **The one thing withheld from a `.segmented` entry's glass — see
    /// `body`'s own comment, above the call site, for the reading behind
    /// this.** Every other kind keeps `.interactive()`; a `.segmented` entry
    /// is the one whose content is a wrapped `NSSegmentedControl`, and the
    /// SDK's own exported symbols read `.interactive()` as laying a second,
    /// SwiftUI-only press recogniser over whatever the glass wraps — not
    /// measured at runtime on this control, where withholding it removed the
    /// glass flash and the outline swell (`body`'s own comment).
    private func glass(for kind: HelmToolbarActionsModel.EntryKind) -> Glass {
        if case .segmented = kind { return .regular }
        return .regular.interactive()
    }

    /// **What one declared entry costs the reserve.** Every button-shaped
    /// kind costs exactly `Self.side` — the invariant
    /// `testAMenuEntryCostsTheSameReserveAsEveryOtherKindAcrossVisibility`
    /// holds them to — but a `.segmented` entry draws at whatever width its
    /// own glyphs need in `.icons` style, the one style `entryContent(_:)`
    /// ever puts it in — no word ever reaches what is drawn, so the reserve
    /// tracks the symbol set rather than the current language — so its
    /// reserve is carried on the entry itself as `EntryKind.segmented`'s own
    /// `reserveWidth`, measured by `SettingsToolbar.actionEntries(for:)`, in
    /// `HelmApp`, rather than computed here.
    ///
    /// **Measured attached, per glyph set** — each pair's own reserve tracks
    /// what it draws rather than one number standing in for all of them
    /// (`ASegmentedEntrysReserveCoversItsOwnGlyphsTests`: 73.0–85.0 pt across
    /// four pairs). `SettingsToolbar.actionEntries(for:)` measures through
    /// `SwitcherMeasurementRig` — the same rig the centre tabs' own fold
    /// prediction uses (`SettingsToolbar.switcherWidth(tabs:style:selectedID:)`),
    /// whose own header has what a bare hosting view got wrong for the tabs —
    /// mounting the same segments, non-compact and in `.icons`, the one style
    /// `entryContent(_:)` ever draws a `.segmented` entry in. This module
    /// cannot import `HelmApp` to reach that rig itself — `Package.swift`'s
    /// own target graph has `HelmApp` depend on `HelmUI`
    /// (`Package.swift:137-143`), and the reverse edge would be a cycle —
    /// which is why the number crosses as plain data on the entry rather than
    /// being asked for here.
    ///
    /// Not `private`, on the same grounds as `model` above: it is what
    /// `TheLastItemsGlassSitsAsFarFromTheEdgeTests` reads, through
    /// `@testable import HelmUI`, to tell the reserve's own width apart from
    /// `HelmToolbarActionsCapsule`'s deliberate `trailingInset` — a test that
    /// instead assumed every declared entry costs `Self.side` would read a
    /// `.segmented` entry's own extra width as if it were the inset.
    @MainActor
    func reserveWidth(_ entry: HelmToolbarActionsModel.Entry) -> CGFloat {
        if case .segmented(_, _, let reserveWidth) = entry.kind {
            return reserveWidth
        }
        return Self.side
    }

    /// **The glyph every kind shares.** The frame and the hit shape sit on it
    /// rather than on whatever wraps it, for the reason the button case's own
    /// comment used to give here: a `.plain` button's tap target is its
    /// label's rendered bounds, which for an icon-only `Label` is the bare
    /// glyph, and a frame applied outside the control changes only layout,
    /// not what AppKit's hit test asks SwiftUI for.
    @ViewBuilder
    private func glyph(_ entry: HelmToolbarActionsModel.Entry) -> some View {
        Label(entry.title, systemImage: entry.symbol)
            .labelStyle(.iconOnly)
            .helmSteadySpin(entry.isBusy)
            .frame(width: Self.side, height: Self.side)
            .contentShape(Rectangle())
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
        case .segmented:
            // Never reached: `entryContent(_:)` above intercepts a
            // `.segmented` entry before this switch, over `EntryKind`, is
            // ever asked — kept here only because Swift requires the switch
            // to stay exhaustive, per `CLAUDE.md`'s own rule against a
            // `default` arm that would hide a case added here later.
            EmptyView()
        }
    }
}
