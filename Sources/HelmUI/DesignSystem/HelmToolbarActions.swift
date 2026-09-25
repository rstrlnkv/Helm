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
/// a probe under `scratchpad/probes-mft/`; the `@Observable` model logged
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
    private let trailingInset: CGFloat

    public init(_ model: HelmToolbarActionsModel, trailingInset: CGFloat = 0) {
        self.model = model
        self.trailingInset = trailingInset
    }

    public var body: some View {
        ZStack(alignment: .trailing) {
            // The fixed reserve: every declared action, laid out and never
            // drawn — its width is the capsule's own intrinsic width, which
            // is what stops the hosted item resizing as `visibleIDs` moves.
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
                        entryControl(entry)
                            .help(entry.title)
                            .disabled(!entry.isEnabled || !model.isInteractive)
                            .glassEffect(.regular.interactive())
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
                // **How a selected toggle glyph looks is left to the owner to
                // judge by eye** — accent-coloured while on is this pass's
                // own choice, made on no more evidence than
                // `HelmGlyphPicker` and `HelmSurfaces` already tinting a
                // chosen state the same way.
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
        }
    }
}
