import SwiftUI

// **What a settings page may put in the window's toolbar, said once here so
// every module page says it the same way.**
//
// The toolbar itself is AppKit's — one `NSToolbar` per page shape, owned by
// `SettingsToolbar` in `HelmApp` and swapped onto the window on every
// selection change rather than rewritten in place — because rewriting
// `itemIdentifiers` on the toolbar the window is currently showing is what
// animates every item in and out of it (`SettingsToolbar`'s own header says
// why one cached toolbar per page replaced that). A page cannot reach an
// object in another target, so it says what it wants through this contract
// and `HelmWindowToolbarChannel` instead — the same shape a preference key
// would give, without the requirement that a preference's value be
// `Equatable`, which a `perform` or `onSubmit` closure never is.
//
// A module's UI target imports `HelmUI` and never `HelmApp` — so this file,
// and not `SettingsToolbar`, is where a page-facing name has to live.

/// One tab a page's toolbar centres — the switcher's segments, said as data
/// rather than as a view, since a module's UI target cannot build
/// `HelmToolbarSwitcher`'s own host directly. The tabs have one form:
/// `HelmToolbarSwitcher` (`HelmToolbarSwitcher.swift`, this same directory) —
/// a dev-only toggle used to let a build compare this against AppKit's own
/// segmented-toolbar-item group, retired 2026-09-23 once that comparison had
/// been made.
public struct HelmToolbarTab {
    /// Stable, and the value a segment's selection is compared against — not
    /// an index, which a tab list that ever reorders would silently mis-read.
    public let id: String
    /// Localised already: every string that reaches a person in this app is
    /// looked up once, at the page, and never at the toolbar controller,
    /// which has no language of its own to read one in.
    public let title: String
    public let symbol: String

    public init(id: String, title: String, symbol: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
    }
}

/// One item in a `.menu`-kind `HelmToolbarAction`'s own submenu — a check
/// beside a title, with a press of its own rather than the action's single
/// `perform`: Leftovers' kind filter is the first caller, one checkmark per
/// `StaleKind`.
public struct HelmToolbarMenuItem {
    public let id: String
    public let title: String
    public let isOn: Bool
    public let isEnabled: Bool
    public let perform: () -> Void

    public init(id: String, title: String, isOn: Bool, isEnabled: Bool = true,
                perform: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.perform = perform
    }
}

/// One button in the toolbar's single Liquid Glass action capsule
/// (`HelmToolbarActionsCapsule`, `HelmToolbarActions.swift`, this same
/// directory) — every declared action shares that one capsule and one
/// `NSToolbarItem` now, `helm.actions`; there is no longer an item per action
/// for `isEnabled` and `isVisible` to be mapped onto individually.
public struct HelmToolbarAction {
    /// **What the action draws as and what pressing it does — one shape, not
    /// three optionals a caller could set inconsistently.** A plain button
    /// runs `perform` on a press; a toggle also carries its own current
    /// state, read back into the glyph's tint; a menu has no single
    /// `perform` at all, only the items inside it, each with its own — so a
    /// menu that is also a toggle, or a toggle with a submenu, cannot be
    /// written down.
    public enum Kind {
        case button(() -> Void)
        case toggle(isOn: Bool, () -> Void)
        case menu([HelmToolbarMenuItem])
        /// A grouped choice among `options`, one of them selected — drawn as
        /// `HelmToolbarSwitcher` in the capsule (`HelmToolbarActions.swift`,
        /// this same directory) rather than as two `.toggle` actions kept in
        /// lockstep by hand, or as a `.menu`'s dropdown. Hosts' Table /
        /// Plain-text pair is the first caller. `options` reuses
        /// `HelmToolbarTab`'s own shape (id, word, glyph) — the same triple
        /// the centred tabs switcher already takes a segment from — and
        /// `selection` is a plain `Binding<String>`, the same shape
        /// `HelmPageToolbarContent.selectedTab` already is, rather than a
        /// closure per option: there is nothing here for a per-option
        /// `perform` to do that writing the binding does not already say.
        case segmented(options: [HelmToolbarTab], selection: Binding<String>)
    }

    public let id: String
    /// Said in the tooltip and in the accessibility label — a glyph-only
    /// control has no other name (`Tests/HelmUITests/NamedControlsTests.swift`'s
    /// own rule, restated for a control this target cannot mount itself).
    public let title: String
    public let symbol: String
    /// **Dimmed while it stays in the capsule, and inapplicable *there* rather
    /// than inapplicable everywhere.** An action a page shows on only some of
    /// its own tabs is out of the capsule's visible set on the rest
    /// (`isVisible`), and on the tab where it belongs it is dimmed — through
    /// the capsule's own `@Observable` model, `HelmToolbarActionsModel` —
    /// until it can act.
    public let isEnabled: Bool
    /// **Whether this action belongs on the tab currently showing at all.**
    /// `true` for an action every tab offers (Homebrew's Refresh); `false`
    /// leaves it out of `HelmToolbarActionsModel.visibleIDs`, so the capsule
    /// simply does not draw a button for it — the capsule's own back layer
    /// still reserves its width from the *declared* set regardless, which is
    /// what keeps every other button still when this one appears or
    /// disappears (`HelmToolbarActionsCapsule`'s own header) rather than
    /// sliding the way an `NSToolbarItem` collapsing to `isHidden` used to.
    public let isVisible: Bool
    /// Spinning in the capsule while `true` — `.helmSteadySpin`, which
    /// already honours Reduce Motion (`HelmMotion.swift`). Only the plain
    /// `.button` initializer below takes this as a parameter: a toggle's own
    /// state is what its glyph already reports, and a menu has no one glyph
    /// whose state a spin would report on either, so both initializers below
    /// leave it `false` and there is no way to write a spinning toggle or
    /// menu down at all.
    public let isBusy: Bool
    public let kind: Kind

    /// A plain button — the shape every action but Hosts' view toggle and
    /// Leftovers' kind filter takes.
    public init(id: String, title: String, symbol: String, isEnabled: Bool = true,
                isVisible: Bool = true, isBusy: Bool = false, perform: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.isEnabled = isEnabled
        self.isVisible = isVisible
        self.isBusy = isBusy
        self.kind = .button(perform)
    }

    /// A toggle: `isOn` decides the glyph's tint, and the same `perform`
    /// convention as a plain button — the caller flips its own state, which
    /// the next declare reads back into `isOn`.
    public init(id: String, title: String, symbol: String, isEnabled: Bool = true,
                isVisible: Bool = true, isOn: Bool, perform: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.isEnabled = isEnabled
        self.isVisible = isVisible
        self.isBusy = false
        self.kind = .toggle(isOn: isOn, perform)
    }

    /// A menu of checkmarked items — no `perform` of the action's own; each
    /// item carries its own.
    public init(id: String, title: String, symbol: String, isEnabled: Bool = true,
                isVisible: Bool = true, menu: [HelmToolbarMenuItem]) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.isEnabled = isEnabled
        self.isVisible = isVisible
        self.isBusy = false
        self.kind = .menu(menu)
    }

    /// A segmented control: `title` names the *group*, for the switcher's own
    /// accessibility label (`HelmA11y.whatToShow` is the word every other
    /// unlabelled segmented picker in this app already uses for the same
    /// role) — each option carries its own word and glyph, so this action's
    /// own `symbol` goes unused and is fixed to `""`.
    public init(id: String, title: String, isEnabled: Bool = true, isVisible: Bool = true,
                options: [HelmToolbarTab], selection: Binding<String>) {
        self.id = id
        self.title = title
        self.symbol = ""
        self.isEnabled = isEnabled
        self.isVisible = isVisible
        self.isBusy = false
        self.kind = .segmented(options: options, selection: selection)
    }
}

/// The page's search: a binding kept live on every keystroke, and a submit
/// action that fires on Return and on Return only — `sendsWholeSearchString`
/// is what makes that true on the AppKit side, so nothing here has to filter
/// keystrokes itself.
public struct HelmToolbarSearch {
    public let prompt: String
    public var text: Binding<String>
    public let onSubmit: (() -> Void)?

    public init(prompt: String, text: Binding<String>, onSubmit: (() -> Void)? = nil) {
        self.prompt = prompt
        self.text = text
        self.onSubmit = onSubmit
    }
}

/// **The whole of what a page asks the window's toolbar to show**, beyond the
/// name every page gets for nothing. Any of the three may be empty or nil — a
/// page with none of them still gets tabs-less, action-less, search-less
/// treatment rather than an error, which is what "temporarily show only the
/// name" (the migration's own words for every page not yet converted) means
/// in practice: such a page simply never calls `helmWindowToolbar` at all.
public struct HelmPageToolbarContent {
    public var tabs: [HelmToolbarTab]
    /// nil when `tabs` is empty; set when it is not. Two facts kept apart
    /// rather than folded into one, for the reason a lone `Binding` never
    /// says whether there is anything to select from.
    public var selectedTab: Binding<String>?
    /// **Dims the whole switcher** — Uninstaller's during its review step, so
    /// far the one caller — rather than any one tab: per-tab disabling was
    /// never asked for, so there is nothing here to disable a tab by.
    public var tabsEnabled: Bool
    public var actions: [HelmToolbarAction]
    public var search: HelmToolbarSearch?

    public init(tabs: [HelmToolbarTab] = [], selectedTab: Binding<String>? = nil, tabsEnabled: Bool = true,
                actions: [HelmToolbarAction] = [], search: HelmToolbarSearch? = nil) {
        self.tabs = tabs
        self.selectedTab = selectedTab
        self.tabsEnabled = tabsEnabled
        self.actions = actions
        self.search = search
    }
}

/// **The one channel a page's toolbar content crosses into `HelmApp` by.**
///
/// Not `ObservableObject`, and deliberately not read by SwiftUI at all: the
/// one reader is `SettingsToolbar`, an `NSToolbarDelegate`, and it is told
/// about a change rather than asked to watch for one — `onChange` is set once,
/// by the window, and called after every `declare` and every `withdraw` that
/// actually changed something.
///
/// **Content is kept per page token, not in one shared slot.** `SettingsDetail`
/// mounts exactly one page's view at a time, so in steady state at most one
/// token ever has a live entry — but `SettingsToolbar` reads a page's content
/// by *that page's own token* (`token(for:)` on its side is the same page key
/// every module already passes to `helmWindowToolbar`), which is what keeps a
/// declaration credited to the page that made it rather than to whichever
/// selection happened to be current when it arrived. Two measured orderings
/// broke a single shared `current` field: the selection sink can run before
/// the outgoing page's subtree is torn down, and SwiftUI can call the
/// outgoing mount's `updateNSView` after the incoming mount's and before
/// dismantling it — either way the outgoing page's content landed under the
/// page now on screen.
///
/// **A late write from an outgoing mount must still lose to the incoming
/// one, and a stale withdraw must not erase a live declaration.** Ownership
/// for a token is kept as the *generation* of the mount that last wrote it —
/// `Coordinator` is handed a generation, read once, at the moment SwiftUI
/// creates it (`makeCoordinator`), which is a fresh object and a fresh,
/// strictly higher number every time — so a coordinator built before another
/// one always carries the smaller number, whichever of the two SwiftUI
/// happens to update or dismantle last. `declare` from a generation *below*
/// the token's current owner is refused outright rather than merging or
/// overwriting — an equal generation is accepted, since that is the same
/// mount redeclaring after a change of its own; `withdraw` is honoured only
/// from the generation that is currently the owner. Measured (`remount.swift` in the review that found
/// this): a language-triggered remount calls the new mount's `updateNSView`,
/// then the old mount's `updateNSView` once more, then the old mount's
/// `dismantleNSView` — in that order. The old mount's late `declare` is
/// refused (its generation is the smaller one), so the new mount's content
/// stands; the old mount's `withdraw` is then refused too, because it is no
/// longer the token's owner — so the channel is never left empty by an
/// ordering that was "not observed either way" the first time this was
/// written and has been observed since.
@MainActor
public final class HelmWindowToolbarChannel {
    private struct Entry {
        var content: HelmPageToolbarContent
        var generation: Int
    }
    private var entries: [AnyHashable: Entry] = [:]
    private var nextGenerationValue = 0

    /// `SettingsToolbar`'s one hook into this object.
    public var onChange: (() -> Void)?

    public init() {}

    /// What the page named by `token` last declared, or `nil` where it has
    /// never declared or has since withdrawn — the one thing `SettingsToolbar`
    /// reads, keyed on the page it is currently showing rather than on
    /// whichever page wrote last.
    public func content(for token: AnyHashable) -> HelmPageToolbarContent? {
        entries[token]?.content
    }

    /// A fresh, strictly increasing number for a fresh mount — see this
    /// class's own header for why ownership is decided by this rather than by
    /// call order.
    func nextGeneration() -> Int {
        nextGenerationValue += 1
        return nextGenerationValue
    }

    func declare(_ content: HelmPageToolbarContent, token: AnyHashable, generation: Int) {
        if let existing = entries[token], existing.generation > generation { return }
        entries[token] = Entry(content: content, generation: generation)
        onChange?()
    }

    func withdraw(token: AnyHashable, generation: Int) {
        guard let existing = entries[token], existing.generation == generation else { return }
        entries[token] = nil
        onChange?()
    }
}

public extension EnvironmentValues {
    /// nil where nothing carries one — a sheet, a page mounted on its own in a
    /// test — and `helmWindowToolbar` below then does nothing at all. The
    /// settings window is the one place that sets it.
    @Entry var helmWindowToolbarChannel: HelmWindowToolbarChannel? = nil
}

public extension View {
    /// **The one way a page's toolbar content reaches the window.**
    ///
    /// `token` is the page's own key — a module's engine identifier, or a
    /// literal for one of the three non-module pages — and it is what
    /// `HelmWindowToolbarChannel` stores content under and what
    /// `SettingsToolbar` reads back by by the page it is currently showing.
    /// Two mounts of the same page (a language-triggered remount, an outgoing
    /// and an incoming page briefly overlapping) share one token on purpose;
    /// the channel's own generation guard, not a fresh token per mount, is
    /// what keeps the later mount's declaration from being overwritten by the
    /// earlier one's.
    func helmWindowToolbar(_ content: HelmPageToolbarContent?, token: AnyHashable) -> some View {
        modifier(HelmWindowToolbarPublisher(content: content, token: token))
    }
}

private struct HelmWindowToolbarPublisher: ViewModifier {
    @Environment(\.helmWindowToolbarChannel) private var channel
    let content: HelmPageToolbarContent?
    let token: AnyHashable

    func body(content view: Content) -> some View {
        view.background(Bridge(channel: channel, content: content, token: token))
    }

    /// A zero-size `NSView` rather than a `PreferenceKey`: this file's own
    /// header says why a preference cannot carry a closure, and an
    /// `NSViewRepresentable` gets `dismantleNSView`, which a preference has no
    /// equivalent of at all — the `.onDisappear` this would otherwise need
    /// fires on the page's own subtree, not on the moment SwiftUI actually
    /// tears the view down, and firing early would withdraw content the page
    /// is still showing.
    private struct Bridge: NSViewRepresentable {
        let channel: HelmWindowToolbarChannel?
        let content: HelmPageToolbarContent?
        let token: AnyHashable

        /// **The mount's own generation, read once at construction, and the
        /// token `dismantleNSView` needs — it is static and cannot read
        /// `self`, so this is the one place left to keep it.** See
        /// `HelmWindowToolbarChannel`'s own header for why a fresh, ordered
        /// number decides ownership rather than the order calls happen to
        /// arrive in.
        final class Coordinator {
            weak var channel: HelmWindowToolbarChannel?
            var token: AnyHashable?
            let generation: Int
            init(generation: Int) { self.generation = generation }
        }

        func makeCoordinator() -> Coordinator { Coordinator(generation: channel?.nextGeneration() ?? 0) }

        func makeNSView(context: Context) -> NSView {
            NSView(frame: .zero)
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            context.coordinator.channel = channel
            context.coordinator.token = token
            guard let channel else { return }
            if let content {
                channel.declare(content, token: token, generation: context.coordinator.generation)
            } else {
                channel.withdraw(token: token, generation: context.coordinator.generation)
            }
        }

        /// **The ordinary teardown, not only the one a `withdraw` in
        /// `updateNSView` already covered.** A page switch removes the whole
        /// outgoing subtree in one step — no final `updateNSView(content:
        /// nil)` runs first — so this is the only call that ever tells the
        /// channel a page that was still declaring has actually gone.
        static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
            guard let channel = coordinator.channel, let token = coordinator.token else { return }
            channel.withdraw(token: token, generation: coordinator.generation)
        }
    }
}
