import AppKit
import Combine
import SwiftUI
import HelmRuntime
import HelmUI

/// **One cached `NSToolbar` per page, swapped onto the window on every
/// selection change and never rewritten while it is the one attached.**
///
/// Replaces the SwiftUI-AppKit bridge (`sceneBridgingOptions`), which rebuilt
/// the bar's items and reset `allowsUserCustomization` on every SwiftUI
/// update, and the throwaway `SPIKE-APPKIT-TOOLBAR` spike that stood in for it
/// before this file proved the mechanism on the real window — and replaces a
/// first version of this file that kept one `NSToolbar` for the whole window
/// and rewrote its `itemIdentifiers` on every page switch. `NSToolbar.h:154`
/// on that property: "Setting this property will set the current items in the
/// toolbar by diffing against items that already exist" — and AppKit animates
/// every item the diff inserts or removes on a toolbar that is already on
/// screen. Measured on the real window: entering Homebrew logged the bar
/// going from `[sep]` to its full seven-item list some tens of milliseconds
/// later, which is the icons-grow-on-every-visit the owner reported, and
/// leaving repeated it in reverse.
///
/// **So a page switch assigns `window.toolbar`, and nothing here ever writes
/// `itemIdentifiers` on a toolbar the window is currently showing.** A page
/// gets its own `NSToolbar`, built once — its full item list assigned while
/// the toolbar is still detached, which is the diffing above with nothing on
/// screen to animate over — and kept in `pageBars`, keyed by the page's own
/// key (`pageKey`); returning to a page reuses that object outright.
/// `NSToolbar.h:42`: "Toolbars with the same identifier are implicitly
/// synchronized so that they maintain the same state" — which is why every
/// toolbar this file builds gets a freshly serialised identifier
/// (`HelmSettingsToolbar.<pageKey>.<serial>`, `barSerial`, built in
/// `buildBar`) rather than one derived solely from the page key: two objects
/// that ever shared an identifier would answer for each other, and an old,
/// abandoned toolbar for a page whose shape just changed (a page-bar or
/// label-style toggle) must never be able to reach back into the new one.
///
/// **No user customization anywhere in this window** (the owner's decision,
/// 2026-09-22): `allowsUserCustomization` and `autosavesConfiguration` are
/// `false` on every toolbar this file builds, and nothing here ever sets
/// either to `true`. **The actions are one custom-view item, `helm.actions`,
/// hosting `HelmToolbarActionsCapsule`** (`Sources/HelmUI/DesignSystem/HelmToolbarActions.swift`)
/// — not one plain `NSToolbarItem` per action, which is what a hidden
/// action's own width collapsing used to move its neighbours by (measured on
/// a real window, 2026-09-21). An inapplicable control on the tab it belongs
/// to is dimmed through the capsule's own `@Observable` model
/// (`HelmToolbarAction.isEnabled`); one that belongs to a *different* tab is
/// simply left out of the capsule's visible set there
/// (`HelmToolbarAction.isVisible`) rather than out of what the page declares,
/// so the capsule's fixed reserve — and the bar's own identifier list, which
/// carries the one `helm.actions` identifier regardless of which actions are
/// currently shown — never has to change shape for it.
///
/// A page says what it wants through `HelmWindowToolbarChannel`
/// (`HelmWindowToolbar.swift` in `HelmUI`) — `nil` when a page has never
/// declared, which draws the name — plus a status-bearing page's own
/// `helm.status`, under `PageBarStyle.moduleName` — and nothing else.
/// `SettingsWindow` owns
/// both this object and the channel, and hands the channel to the detail
/// pane's environment so a page never needs `HelmApp` in scope to publish
/// into it.
///
/// **A page whose bar exists is shown the instant it is selected, whether or
/// not the channel currently has live content for it.** A page's own mount
/// almost always redeclares within the same run-loop turn it appears in, and
/// showing its last-known bar rather than a bare name avoids a visible dip to
/// name-only on every ordinary visit. A short grace period
/// (`graceInterval`) is armed the moment a bar that was live a heartbeat ago
/// stops being able to say anything — either because the *selection itself*
/// just changed to a page with a cached bar and no live content yet, or
/// because the module the page on screen names has just been switched off
/// without the selection moving at all (`isModuleSwitchedOff()`); if nothing
/// has declared by the time it fires, the bar falls back to the shared
/// name-only toolbar and stays there — a later, non-selection refresh (a
/// language change, a page-bar or switcher-style toggle) does not re-attach
/// the stale bar just because `refresh()` ran again — until the page is
/// selected once more or declares afresh (`fellBackToNameOnly`). A page that
/// has never once declared skips the grace period — there is no prior bar to
/// give the benefit of the doubt to, so it reads name-only immediately. And a
/// withdraw that arrives with **no** selection change and names a module that
/// is still switched on (the window ordered off screen, a language-triggered
/// remount tearing the mount down and building its replacement) never starts
/// this fallback at all: the page's bar stays assigned, its controls are
/// simply disabled until the next declare re-arms them — see
/// `freeze(_:visibly:)`.
@MainActor final class SettingsToolbar: NSObject, NSToolbarDelegate {
    private let model: SettingsModel
    private let channel: HelmWindowToolbarChannel

    /// Set once, by `SettingsWindow`, right after the window exists — this
    /// object is built before the window is (`NSWindow.init` needs something
    /// to hand its own `toolbar` property), so assigning this is what puts
    /// the first bar on screen.
    weak var window: NSWindow? {
        didSet {
            watchBarPresses()
            watchWindowResize()
            refresh()
        }
    }

    private var selectionWatch: AnyCancellable?
    // Read in `deinit`, which Swift 6 treats as nonisolated even on a
    // `@MainActor` class (`OffScreenIdle.swift`'s own reason for the
    // identical spelling) — removed only ever from the main actor in
    // practice, since nothing here posts either notification off it.
    nonisolated(unsafe) private var languageWatch: NSObjectProtocol?
    nonisolated(unsafe) private var pageBarStyleWatch: NSObjectProtocol?
    nonisolated(unsafe) private var switcherStyleWatch: NSObjectProtocol?
    nonisolated(unsafe) private var alwaysCollapseSearchWatch: NSObjectProtocol?
    /// **The status this class copies into `helm.status`/the name zone is a
    /// stored reading (`pageIdentity()`), not a live one** — `refresh()` is
    /// the only thing that re-reads it, and until this pair nothing called
    /// `refresh()` when a module's own enabled flag moved: the "Turn On"
    /// button on the module's own empty page (`SettingsWindow`'s own `page`)
    /// and the sidebar's arrangement toggle (`SidebarComposerList`) both reach
    /// `ModuleHost.setEnabled` with no selection change and no redeclare, so
    /// `watchActivity()` stayed armed for a module that had just stopped
    /// existing, or never got armed for one that had just started. Not
    /// filtered to the module named in the notification: every other trigger
    /// here (language, page-bar style, switcher style) already calls
    /// `refreshAndResettle()` unconditionally, and `pageIdentity()` only ever
    /// reads `currentSelection`'s own module, so a toggle on some other page
    /// is a harmless extra refresh.
    nonisolated(unsafe) private var moduleEnabledWatch: NSObjectProtocol?
    nonisolated(unsafe) private var moduleDisabledWatch: NSObjectProtocol?
    /// **M1**, and the bar's own right-click: catches a press on the
    /// magnifier before AppKit's own `searchButtonClicked:` does, so a fold
    /// the rest verdict calls for is done before the field starts growing, and the menu
    /// gesture anywhere on the bar — see `watchBarPresses()`'s own header for
    /// why one monitor carries both.
    nonisolated(unsafe) private var barPressMonitor: Any?
    nonisolated(unsafe) private var windowResizeWatch: NSObjectProtocol?
    nonisolated(unsafe) private var windowEndLiveResizeWatch: NSObjectProtocol?
    nonisolated(unsafe) private var splitResizeWatch: NSObjectProtocol?
    /// **M3's own net** — replaced whenever `show(_:key:)` actually
    /// changes which bar is attached (`watchOverflow(_:)`), rather than one
    /// set per `PageBar`: only the bar on screen can overflow at all.
    private var visibilityWatch: [NSKeyValueObservation] = []
    /// **M3**'s own coalescing — several `isVisible` flips land in one
    /// animated relayout, and this is what turns them into one overflow
    /// check per relayout rather than one per flip.
    private var pendingOverflowCheck = false
    /// The one settle timer across every bar — re-armed by
    /// `scheduleSettle(_:)`, and always for the *attached* bar by the time it
    /// fires, per that method's own guard.
    private var settleWorkItem: DispatchWorkItem?
    /// **How long `settle(_:)` waits after the last frame change before
    /// predicting whether the tabs can unfold** — a `var`, not a `let`, so a test can
    /// shrink it rather than sleeping through the production value, the same
    /// pattern as `graceInterval`. Argued from AppKit's own collapse: the
    /// largest gap between two frames of the search field folding to its
    /// magnifier measured 22 ms (engineer, this Mac) — this is several
    /// such frames, and still far under anything a person reads as a wait.
    static var settleInterval: TimeInterval = 0.1
    /// The current module's own "my state moved" signal, the same one
    /// `ModuleDetailView`'s own `activityRevision` subscribes to — re-armed on
    /// every page change so the status zone's word does not go stale for the
    /// rest of the visit the way `ModuleDetailView`'s own status word did
    /// before it had a signal like this one (`ModuleDetailView
    /// .activityRevision`'s own history).
    private var activityWatch: AnyCancellable?

    /// **The selection `refresh()` is answering for, resolved once per call
    /// and read by everything else in this file instead of `model.selection`
    /// directly.** `@Published` publishes in `willSet`, so a subscriber that
    /// reads the property back — rather than the value the sink was handed —
    /// reads the page being left, one step behind: a probe against a bare
    /// `sink { _ in model.sel }` recorded `general` for both the send that
    /// carried `about` and the one that carried `log`. `selectionWatch` below
    /// passes its value in; every other trigger (`channel.onChange`, a
    /// language or bar-style change) calls `refresh()` with none, which
    /// defaults to `model.selection` — safe there, because none of those
    /// fire from inside that `willSet`.
    private var currentSelection: SettingsSelection?

    /// **What `HelmToolbarActionsModel.appearsActive` is fed from —
    /// `SettingsWindow.updateWindowAppearsActive()`'s direct read of
    /// `isKeyWindow || isMainWindow` off the window itself.** Measured to
    /// equal AppKit's private `_hasActiveAppearance` on every `STATE` line a
    /// real window logged, sheet included (`SettingsWindow`'s own header,
    /// above its four `windowDid…` methods, has the reading and where it was
    /// taken). Starts `true`: the seed call `SettingsWindow.init` makes right
    /// after handing this toolbar its window corrects it, synchronously,
    /// before the window is ever shown — this default is never the value a
    /// person sees.
    private var windowAppearsActive = true

    // MARK: - Per-page cached toolbars

    private var pageBars: [String: PageBar] = [:]
    private var barsByToolbarID: [ObjectIdentifier: PageBar] = [:]
    /// Shared across every page that has never declared, or whose grace
    /// period ran out — one instance, rebuilt only when its own shape
    /// (`ShapeSignature`) goes stale, since it carries no page-specific
    /// content of its own to key a cache on.
    private var nameOnlyBar: PageBar?
    private static let nameOnlyKey = "name-only"
    /// Which bar is currently `window.toolbar` — `Self.nameOnlyKey` for the
    /// shared fallback, so a page never re-assigns a toolbar the window is
    /// already showing (measured harmless but pointless: a same-object
    /// re-assignment posts no delegate call at all).
    private var attachedPageKey: String?
    private static var barSerial = 0

    /// **The grace period after a genuine selection change with nothing
    /// declared yet.** Chosen as a small multiple of one SwiftUI update turn
    /// — a mount's own first `updateNSView` ordinarily lands in the same or
    /// the next run-loop turn as its appearance — rather than derived from a
    /// measurement of this exact path; `var` and not `let` so a test can
    /// shrink it instead of sleeping through the production value.
    static var graceInterval: TimeInterval = 0.25
    private var graceWorkItem: DispatchWorkItem?
    private var gracePageKey: String?
    /// **Pages whose grace period has already run out once, with nothing
    /// declared.** Read only by `refresh()`'s frozen branch, which keeps such
    /// a page on the shared name-only bar rather than re-attaching its own —
    /// stale — bar on every later, non-selection refresh (a language change,
    /// a page-bar or switcher-style toggle). Cleared the moment the page's
    /// selection is chosen again (`refresh()`'s own `didSwitchPage` branch),
    /// which is what keeps an ordinary return visit optimistic
    /// (`obtainBar`'s `live: false` branch, shown before anything has had a
    /// chance to redeclare) rather than name-only forever once a page has
    /// fallen back from it a single time.
    private var fellBackToNameOnly: Set<String> = []

    private static let nameID = NSToolbarItem.Identifier("helm.name")
    /// **The module's status, at the bar's trailing edge — the owner,
    /// 2026-09-28: «Давай вернем его в правую часть».** Only ever appended
    /// on the shared name-only bar, under `.moduleName` (`identifiers()`):
    /// the one shape every status-bearing page (Keep Awake, VPN, Keyboard)
    /// actually uses, since none of them also declares tabs, actions or
    /// search (`ModuleDescriptor.activity` and `.helmWindowToolbar` are
    /// never both true for one module today) — see `makeStatusItem`'s own
    /// header for why an always-present, empty-when-nil item is what keeps
    /// this bar's identifier list from ever churning.
    private static let statusID = NSToolbarItem.Identifier("helm.status")
    private static let tabsID = NSToolbarItem.Identifier("helm.tabs")
    private static let searchID = NSToolbarItem.Identifier("helm.search")
    /// **One item for the whole capsule**, not one per action — see
    /// `HelmToolbarActionsCapsule`'s own header for why the morph needs a
    /// single SwiftUI subtree rather than several `NSToolbarItem`s AppKit
    /// merely draws adjacent to one another.
    private static let actionsID = NSToolbarItem.Identifier("helm.actions")

    init(model: SettingsModel, channel: HelmWindowToolbarChannel) {
        self.model = model
        self.channel = channel
        super.init()
        channel.onChange = { [weak self] in self?.refresh() }
        // The value the sink is handed, not a re-read of `model.selection` —
        // see `currentSelection`'s own doc for why the property lags by one.
        selectionWatch = model.$selection.sink { [weak self] selection in
            self?.refresh(selection: selection)
        }
        languageWatch = NotificationCenter.default.addObserver(
            forName: .helmLanguageChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAndResettle() }
        }
        pageBarStyleWatch = NotificationCenter.default.addObserver(
            forName: .helmPageBarStyleChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAndResettle() }
        }
        // The Helm-style switcher reads `AppSettings.toolbarSwitcherStyle`
        // fresh on every patch — this is the trigger that makes a
        // right-click's choice reach it at all.
        switcherStyleWatch = NotificationCenter.default.addObserver(
            forName: .helmToolbarSwitcherStyleChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAndResettle() }
        }
        alwaysCollapseSearchWatch = NotificationCenter.default.addObserver(
            forName: .helmAlwaysCollapseSearchChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restEverySearch() }
        }
        // See `moduleEnabledWatch`'s own header: the module a person is
        // looking at can be switched on or off with no selection change at
        // all, and `refresh()` is the only thing that re-arms `watchActivity`
        // and re-reads `pageIdentity()`.
        moduleEnabledWatch = NotificationCenter.default.addObserver(
            forName: .helmModuleEnabled, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAndResettle() }
        }
        moduleDisabledWatch = NotificationCenter.default.addObserver(
            forName: .helmModuleDisabled, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAndResettle() }
        }
    }

    /// **Every cached bar, not only the one on screen** — a page's bar is
    /// kept while another page is shown, and one that missed the change would
    /// come back with the old rest. Turning the setting on over a field an
    /// earlier interaction left open, then cleared, does not just flip the
    /// cap: AppKit's own minimum from that opening is still on the field
    /// (`foldOpenedSearch`'s own header), so a bar the cap now rests still
    /// folds it — reached here whether or not that bar is the one attached to
    /// the window right now. Then the attached bar's own settle, since the
    /// room the field claims has just moved without the window moving.
    private func restEverySearch() {
        for bar in pageBars.values {
            restSearch(bar)
            if bar.searchRestCap?.isActive == true { foldOpenedSearch(bar) }
        }
        scheduleSettleForAttachedBar()
    }

    /// Called by `SettingsWindow`'s own `windowDid…` delegate methods with
    /// `isKeyWindow || isMainWindow` — see `windowAppearsActive`'s own header
    /// for why the value crosses in from there rather than being read inside
    /// the capsule.
    func setWindowAppearsActive(_ active: Bool) {
        guard windowAppearsActive != active else { return }
        windowAppearsActive = active
        for bar in pageBars.values {
            bar.actionsModel?.setAppearsActive(active)
            rebuildActionsHost(bar)
        }
        // The name zone's own ink: a plain SwiftUI value, not glass, so the
        // one bar actually on screen redrawing is enough — `patchName`'s own
        // `pageIdentity()` answers correctly only for that one (`NameSnapshot`'s
        // own header says why `appearsActive` has to ride in its equality).
        patchAttachedName()
    }

    /// **A capsule built while the window reads inactive can draw lit glass
    /// beside flat AppKit items until it is rebuilt a turn later.** Filmed on
    /// Helm Dev: a capsule built while the window had never been key drew lit
    /// glass beside flat AppKit items, where a reopened window drew flat.
    ///
    /// **The rebuild is deferred one run-loop turn.** Rebuilding in the same
    /// turn read the glass still lit on one Helm Dev probe, log not kept;
    /// deferring the one rebuild through a single `DispatchQueue.main.async`
    /// — no explicit delay — read it flat on every filmed first open. Nothing
    /// here explains *why* the extra turn is what closes the gap.
    ///
    /// `PageBar.actionsGlassNeedsFirstAttachCorrection`, set by
    /// `makeActionsItem` exactly when it builds this bar's capsule while
    /// `windowAppearsActive` already reads `false`, is spent here, once,
    /// right after `show(_:key:)` actually attaches the bar it belongs to. A
    /// bar built while the window already reads active never sets the flag,
    /// so an ordinary S1 build costs nothing extra; a bar built while the
    /// window is already inactive sets it regardless of whether it is that
    /// window's first capsule, and pays for a deferred rebuild even where the
    /// flat look it confirms needed no correction — cheaper than telling the
    /// two cases apart, and `rebuildActionsHost(_:)` is already paid for on
    /// every live signal change regardless.
    private func correctActionsGlassOnFirstAttach(_ bar: PageBar) {
        guard bar.actionsGlassNeedsFirstAttachCorrection else { return }
        bar.actionsGlassNeedsFirstAttachCorrection = false
        DispatchQueue.main.async { [weak self, weak bar] in
            guard let self, let bar else { return }
            self.rebuildActionsHost(bar)
            // **A freshly assigned `item.view` has no measured frame until a
            // layout pass runs, and nothing else is about to force one here**
            // — `show(_:key:)`'s own `scheduleSettle(bar)` (armed when this
            // bar was first attached, before this correction ever ran) reads
            // item frames on its own timer rather than after laying the
            // window out itself, so a reader that ran before this call would
            // find this item's frame still unmeasured. `window?.layoutIfNeeded()`
            // is the same call `settle(_:)`'s own `.window` layout case already
            // makes for exactly this reason — asked for here, once, so no
            // later reader of this item's frame is the one left finding it
            // unmeasured.
            self.window?.layoutIfNeeded()
        }
    }

    /// **Mutating `HelmToolbarActionsModel.appearsActive` alone was not
    /// enough on Helm Dev — a live transition had to rebuild the hosting
    /// view, not only change the value it reads.** Measured there: flipping
    /// the model on an *already-rendered* capsule left its glass at the value
    /// it was built with, log not kept. So a live change rebuilds: a fresh
    /// `NSHostingView` over the same model reads the glass correctly, where
    /// mutating the model alone did not — unlike a bar's very first attach,
    /// where the same kind of rebuild made in the same turn still read lit
    /// on one Helm Dev probe, log not kept
    /// (`correctActionsGlassOnFirstAttach(_:)`'s own header). **Not reproduced since, in any fixture built to check it**
    /// — `HelmToolbarActionsCapsule`'s own header, above `struct
    /// HelmToolbarActionsCapsule`, has what those fixtures read instead (the
    /// glass following the window on its own, with no rebuild at all) and
    /// says why the rebuild stays regardless: nothing explaining the
    /// difference from Helm Dev has been found.
    /// `bar.content?.search == nil` is the same reading `makeActionsItem`
    /// seeds `trailingInset` from — kept in step here because a bar whose
    /// shape has not changed keeps the same answer for the life of the bar
    /// (`ShapeSignature.hasSearch` rebuilds the whole bar, this item
    /// included, the moment that changes).
    private func rebuildActionsHost(_ bar: PageBar) {
        guard let model = bar.actionsModel, let item = bar.actionsItem else { return }
        let trailingInset = bar.content?.search == nil ? HelmToolbarActionsCapsule.edgeMargin : 0
        let hosting = NSHostingView(rootView: HelmToolbarActionsCapsule(model, trailingInset: trailingInset))
        hosting.sizingOptions = [.intrinsicContentSize]
        item.view = hosting
    }

    /// **A language, label-style or page-bar change** — every one of them can
    /// move the room the tabs need (a longer word, a name zone that appears
    /// or disappears) without the selection itself moving, so the attached
    /// bar's own settle has to run again. Nothing here invalidates the tabs'
    /// cached width first: `PageBar.tabsWidth` is keyed on the words, the
    /// label style and the language (`TabsWidthKey`), so the settle this
    /// schedules finds a key that no longer matches and measures again. A
    /// page-bar change moves none of those — what it moves is the room around
    /// the tabs, and `settle(_:)` reads the bar's siblings fresh on every
    /// call.
    private func refreshAndResettle() {
        refresh()
        if let key = attachedPageKey {
            let bar = key == Self.nameOnlyKey ? nameOnlyBar : pageBars[key]
            if let bar { scheduleSettle(bar) }
        }
    }

    deinit {
        if let languageWatch { NotificationCenter.default.removeObserver(languageWatch) }
        if let pageBarStyleWatch { NotificationCenter.default.removeObserver(pageBarStyleWatch) }
        if let switcherStyleWatch { NotificationCenter.default.removeObserver(switcherStyleWatch) }
        if let alwaysCollapseSearchWatch { NotificationCenter.default.removeObserver(alwaysCollapseSearchWatch) }
        if let moduleEnabledWatch { NotificationCenter.default.removeObserver(moduleEnabledWatch) }
        if let moduleDisabledWatch { NotificationCenter.default.removeObserver(moduleDisabledWatch) }
        if let windowResizeWatch { NotificationCenter.default.removeObserver(windowResizeWatch) }
        if let windowEndLiveResizeWatch { NotificationCenter.default.removeObserver(windowEndLiveResizeWatch) }
        if let splitResizeWatch { NotificationCenter.default.removeObserver(splitResizeWatch) }
        if let barPressMonitor { NSEvent.removeMonitor(barPressMonitor) }
        // `graceWorkItem` and `settleWorkItem` are not cancelled here —
        // `DispatchWorkItem` is not `Sendable`, so a nonisolated `deinit`
        // (Swift 6 treats every `deinit` this way even on a `@MainActor`
        // class, `OffScreenIdle.swift`'s own reason for `languageWatch`'s
        // spelling above) cannot touch either. Left to fire once the object
        // is already gone: each closure captures `self` weakly and its guard
        // fails on a nil `self`, so it does nothing.
    }

    // MARK: - What the window calls the current page

    private struct PageIdentity {
        let symbol: String
        let tint: Color
        let title: String
        /// The module's own status word and whether it counts as active —
        /// nil for every page that has no notion of running (`moduleStatus`
        /// below). Drawn by `StatusZoneView`, at the trailing edge of the
        /// shared name-only bar, not by `NameZoneView` (the owner, 2026-09-28).
        let status: (word: String, active: Bool)?
    }

    /// The same symbol, tint and name the sidebar draws for this row
    /// (`SettingsWindow.SettingsSidebar`) — read off `currentSelection` and
    /// `ModuleRegistry` rather than off `model.pageTitle`, which the
    /// `.moduleName` bar style deliberately carries with no subtitle and no
    /// symbol (`PageBarStyle.swift`'s own `PageBarContent`): that preference
    /// is what sets the *window's* title for `.windowTitle` style, and this
    /// is a second, independent reading for the toolbar's own name item.
    private func pageIdentity() -> PageIdentity {
        switch currentSelection {
        case .none, .general:
            return PageIdentity(symbol: "gearshape", tint: .gray, title: AppStr.settingsPane, status: nil)
        case .about:
            return PageIdentity(symbol: "info.circle", tint: .gray, title: AppStr.aboutHelm, status: nil)
        case .log:
            return PageIdentity(symbol: "text.alignleft", tint: .gray, title: AppStr.logPane, status: nil)
        case .module(let id):
            guard let descriptor = ModuleRegistry.descriptor(id) else {
                return PageIdentity(symbol: "gearshape", tint: .gray, title: AppStr.settingsPane, status: nil)
            }
            return PageIdentity(symbol: descriptor.moduleMetadata.sfSymbol,
                                tint: descriptor.moduleTint.colour,
                                title: descriptor.moduleMetadata.name,
                                status: moduleStatus(id, descriptor))
        }
    }

    /// The same reading `ModuleDetailView.statusWord` takes, kept in step
    /// here rather than redrawn a second way — nil where the module answers
    /// nil, which is most of them.
    private func moduleStatus(_ id: String, _ descriptor: any ModuleDescriptor) -> (word: String, active: Bool)? {
        guard let live = model.host.liveModule(id), let activity = descriptor.activity(live.vm) else {
            return nil
        }
        switch activity {
        case .active: return (AppStr.moduleActive, true)
        case .idle: return (AppStr.moduleIdle, false)
        }
    }

    /// The token every module page already passes to `helmWindowToolbar` —
    /// read off `currentSelection` and never typed as a module-id literal.
    private var pageKey: String {
        switch currentSelection {
        case .none, .general: return "general"
        case .about: return "about"
        case .log: return "log"
        case .module(let id): return id
        }
    }

    // MARK: - Refresh

    /// **The one place that decides which bar is on screen**, called on every
    /// page change, every content republish and every language or bar-style
    /// change. See this class's own header for the rules it carries out.
    ///
    /// - Parameter selection: the selection to answer for — passed by
    ///   `selectionWatch`'s sink with the value it was handed, and left `nil`
    ///   everywhere else, which defaults to `model.selection`. See
    ///   `currentSelection`'s own doc for why the two must not be conflated.
    private func refresh(selection: SettingsSelection? = nil) {
        let previousPageKey = pageKey
        let isSelectionSignal = selection != nil
        currentSelection = selection ?? model.selection
        let key = pageKey
        let didSwitchPage = isSelectionSignal && key != previousPageKey

        watchActivity()
        if didSwitchPage {
            graceWorkItem?.cancel()
            graceWorkItem = nil
            gracePageKey = nil
            // A fresh visit is always shown optimistically, per this class's
            // own header — even a page whose grace period ran out on an
            // earlier visit: falling back said nothing about the page's
            // *next* declare, only about the one grace period that expired
            // with nothing said. Without this, selecting the page again
            // would read the `!fellBackToNameOnly.contains(key)` guard below
            // as still tripped and go straight to name-only, with no grace
            // period given at all this time.
            fellBackToNameOnly.remove(key)
        }

        if let content = channel.content(for: AnyHashable(key)) {
            fellBackToNameOnly.remove(key)
            let bar = obtainBar(for: key, content: content, live: true)
            let justAttached = show(bar, key: key)
            patch(bar, animated: !justAttached && bar.isLive)
            if gracePageKey == key {
                graceWorkItem?.cancel()
                graceWorkItem = nil
                gracePageKey = nil
            }
        } else if let cached = pageBars[key], !fellBackToNameOnly.contains(key) {
            // Captured before `obtainBar` can overwrite it: a bar that was
            // still live the moment this call started is a bar that has just
            // stopped declaring, which is the one moment this method has to
            // decide whether that is worth a grace period at all — deciding
            // it again on every later refresh while the bar stays frozen
            // would re-arm the timer for ever on a page a language change
            // keeps refreshing.
            let wasLive = cached.isLive
            // Read before this call can arm or clear it: a grace period
            // already running for exactly this page means this call is still
            // inside the same optimistic window a genuine page switch armed
            // — not only the one call that started it. Without this, a
            // second frozen refresh landing inside that window (a language,
            // page-bar or switcher-style change — every one of which calls
            // `refresh()` unconditionally, whether or not a page switch is
            // under way) read `wasLive` as already `false` from the first
            // freeze and dimmed everything, then the redeclare a moment
            // later lit it again — the disabled-then-enabled flip on the
            // tabs' own text this whole mechanism exists to remove.
            let graceAlreadyArmed = gracePageKey == key
            // Never the closures a live declare carried — see
            // `strippedOfClosures`'s own header for what kept a switched-off
            // module's view model alive without it.
            let bar = obtainBar(for: key, content: Self.strippedOfClosures(cached.content),
                               live: false)
            show(bar, key: key)
            // **An ordinary return visit stays lit.** `wasLive` is what this
            // page's bar answered a moment ago, before this call touched it —
            // true exactly when the page had live content on some earlier
            // visit and has simply not redeclared *yet* this time, which is
            // the case the grace period below exists to paper over. A visit
            // like that never needs the disabled look at all: nothing is
            // interactive regardless (`bar.isLive = false`, just below, is
            // what every handler already guards on), so the *visible* freeze
            // — dimming the tabs, the actions and the search field — is
            // reserved for a bar that is not expected to redeclare within the
            // grace period (module switched off, or a non-selection refresh
            // on a bar that was already frozen coming in).
            let isReturnVisit = (didSwitchPage && wasLive) || graceAlreadyArmed
            freeze(bar, visibly: !isReturnVisit)
            if wasLive, didSwitchPage || isModuleSwitchedOff() {
                armGrace(for: key)
            }
        } else {
            assignNameOnly()
        }
    }

    /// **A closure-free copy of `content`, kept from the moment a bar stops
    /// being live.** `HelmToolbarAction.perform`, a page's `selectedTab`
    /// binding and its search field's binding and `onSubmit` all close over
    /// the page's own view model — Homebrew's own declaration captures `hb`,
    /// an `@ObservedObject`, in every one of them. `PageBar.content` used to
    /// keep those live closures after a withdraw exactly as it held them
    /// before one, which is what let a switched-off module's view model, and
    /// the transport client behind it, outlive `ModuleUICache.dropWhenDisabled`
    /// for the rest of the session: nothing in this file ever set `content`
    /// back to something closure-free, only ever to whatever the last live
    /// declaration or the last frozen copy already was. Every handler a
    /// frozen bar's controls could still reach guards on `bar.isLive`, which
    /// `freeze(_:visibly:)` always clears whether or not it also dims
    /// anything, so none of these closures is ever meant to run again — this
    /// keeps only what a frozen bar still needs to draw itself:
    /// the tabs, the actions' identity and state, and the search prompt.
    private static func strippedOfClosures(_ content: HelmPageToolbarContent?) -> HelmPageToolbarContent? {
        guard let content else { return nil }
        return HelmPageToolbarContent(
            tabs: content.tabs,
            selectedTab: content.selectedTab.map { .constant($0.wrappedValue) },
            tabsEnabled: content.tabsEnabled,
            actions: content.actions.map { action in
                switch action.kind {
                case .button:
                    return HelmToolbarAction(id: action.id, title: action.title, symbol: action.symbol,
                                             isEnabled: action.isEnabled, isVisible: action.isVisible,
                                             isBusy: action.isBusy) {}
                case .toggle(let isOn, _):
                    return HelmToolbarAction(id: action.id, title: action.title, symbol: action.symbol,
                                             isEnabled: action.isEnabled, isVisible: action.isVisible,
                                             isOn: isOn) {}
                case .menu(let items):
                    return HelmToolbarAction(id: action.id, title: action.title, symbol: action.symbol,
                                             isEnabled: action.isEnabled, isVisible: action.isVisible,
                                             menu: items.map {
                                                 HelmToolbarMenuItem(id: $0.id, title: $0.title,
                                                                     isOn: $0.isOn, isEnabled: $0.isEnabled) {}
                                             })
                case .segmented(let options, let selection):
                    return HelmToolbarAction(id: action.id, title: action.title,
                                             isEnabled: action.isEnabled, isVisible: action.isVisible,
                                             options: options, selection: .constant(selection.wrappedValue))
                }
            },
            search: content.search.map {
                HelmToolbarSearch(prompt: $0.prompt, text: .constant($0.text.wrappedValue))
            })
    }

    /// A cached bar for `key` whose shape still matches the settings that
    /// decide it, or a freshly built one — see this class's own header for
    /// why a stale shape always gets a brand new toolbar object rather than a
    /// mutated one.
    private func obtainBar(for key: String, content: HelmPageToolbarContent?, live: Bool) -> PageBar {
        let shape = ShapeSignature(content: content)
        if let existing = pageBars[key], existing.shape == shape {
            existing.content = content
            existing.isLive = live
            return existing
        }
        if let stale = pageBars[key] { barsByToolbarID[ObjectIdentifier(stale.toolbar)] = nil }
        let bar = buildBar(label: key, content: content, shape: shape)
        bar.isLive = live
        pageBars[key] = bar
        return bar
    }

    private func obtainNameOnlyBar() -> PageBar {
        let shape = ShapeSignature(content: nil)
        if let existing = nameOnlyBar, existing.shape == shape { return existing }
        if let stale = nameOnlyBar { barsByToolbarID[ObjectIdentifier(stale.toolbar)] = nil }
        let bar = buildBar(label: Self.nameOnlyKey, content: nil, shape: shape)
        nameOnlyBar = bar
        return bar
    }

    /// **Built once, fully populated while still detached, and only ever
    /// attached afterwards.** `toolbar.itemIdentifiers = list` below runs the
    /// same diffing `NSToolbar.h:154` describes, but against a toolbar with
    /// no window and no prior items — nothing on screen to animate over — so
    /// the bar this returns can be handed straight to `window.toolbar` later
    /// with no per-item insertion.
    private func buildBar(label: String, content: HelmPageToolbarContent?,
                          shape: ShapeSignature) -> PageBar {
        Self.barSerial += 1
        let identifier = NSToolbar.Identifier("HelmSettingsToolbar.\(label).\(Self.barSerial)")
        let toolbar = NSToolbar(identifier: identifier)
        let bar = PageBar(toolbar: toolbar, shape: shape)
        bar.content = content
        barsByToolbarID[ObjectIdentifier(toolbar)] = bar
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        toolbar.allowsDisplayModeCustomization = false
        let list = Self.identifiers(content: content, style: shape.pageBarStyle)
        bar.identifiers = list
        toolbar.itemIdentifiers = list
        toolbar.centeredItemIdentifiers = Self.centredIdentifiers(shape)
        return bar
    }

    /// Assigns `bar.toolbar` to the window if it is not already showing —
    /// re-assigning the identical object posts no delegate call at all
    /// (measured), but there is no reason to ask AppKit to check. `key` is
    /// the bar-cache key (`Self.nameOnlyKey` for the shared fallback) and
    /// stays the one thing `attachedPageKey` means, since `searchSubmitted`
    /// and `patchAttachedName` both read it to find *which bar* is on screen.
    ///
    /// - Returns: whether this call actually attached a bar that was not
    ///   already the one on screen — `patch(_:animated:)`'s own guard against
    ///   animating the very first thing a bar ever shows.
    @discardableResult
    private func show(_ bar: PageBar, key: String) -> Bool {
        let alreadyShowing = attachedPageKey == key && window?.toolbar === bar.toolbar
        if !alreadyShowing {
            window?.toolbar = bar.toolbar
            attachedPageKey = key
            // M3's own net watches whichever bar is now on screen — only that
            // one can overflow at all.
            watchOverflow(bar)
            correctActionsGlassOnFirstAttach(bar)
        }
        // Every `show()`, whether or not the bar actually changed — a
        // republish on the same bar can still move the room the tabs need
        // (an action's own visibility flipping the capsule's width).
        scheduleSettle(bar)
        return !alreadyShowing
    }

    private func assignNameOnly() {
        let bar = obtainNameOnlyBar()
        show(bar, key: Self.nameOnlyKey)
        patchName(bar)
    }

    /// **A page that stopped declaring without the selection itself
    /// changing** (the window went off screen, a language remount tore the
    /// old mount down after the new one's declare already won) keeps its bar
    /// on screen, inert, rather than dropping to name-only and losing its own
    /// shape — the next declare (`obtainBar`'s `live: true` branch) puts it
    /// back exactly as it was. `bar.isLive` is always cleared — every handler
    /// (`tabsBinding`'s setter, the actions model's `press`, `searchSubmitted`)
    /// already guards on it, so a press during this turn does nothing whether
    /// or not anything below is visibly dimmed.
    ///
    /// **`visibly` decides whether that inertness is also *shown*.** An
    /// ordinary return visit (`refresh()`'s own `isReturnVisit`) calls this
    /// with `visibly: false`: the grace period is already armed, and if
    /// nothing redeclares within it the bar falls back to name-only, so the
    /// disabled look is never needed on the way there — showing it anyway,
    /// only to undo it the instant the page redeclares (`patch(_:)` below),
    /// is exactly the disabled-then-enabled flip on the tabs' own text that
    /// used to run on every return visit, because `HelmTabsSnapshot` used to
    /// carry `bar.isLive` itself rather than a separate `isInteractive` flag
    /// this method is now the only place — besides `patch(_:)` — that
    /// touches. `visibly: true` is for a bar that is not expected back this
    /// turn (module switched off, or a non-selection refresh on a bar that
    /// was already frozen coming in): it dims the tabs (through
    /// `patchTabs`'s snapshot), the actions capsule (`HelmToolbarActionsModel
    /// .isInteractive`) and the search field directly, since a custom-view
    /// item carries none of `NSToolbarItem.autovalidates`' machinery.
    private func freeze(_ bar: PageBar, visibly: Bool) {
        bar.isLive = false
        if visibly {
            bar.isInteractive = false
            bar.actionsModel?.setInteractive(false)
            bar.searchItem?.searchField.isEnabled = false
        }
        patchTabs(bar)
        // `bar.isLive` just moved, and `actionMenuItem`'s own `isEnabled`
        // reads it — without this an action already offered in AppKit's own
        // «»» menu stayed enabled after a freeze, and pressing it did
        // nothing (`actionMenuItemPressed` guards on `bar.isLive` and drops
        // it), which is a control that looks live and is not.
        patchActionsMenu(bar)
    }

    /// **Whether the page on screen names a module macOS's own switch has
    /// since turned off**, asked only of a bar that was still live a moment
    /// ago (`refresh()`'s own `wasLive` guard) — the one case a withdraw with
    /// no selection change must still end at the shared name-only bar, per
    /// this class's own header, rather than freezing for the rest of the
    /// session the way a page merely off screen (`helmIdlesOffScreen`, a
    /// language remount) is meant to. `.general`, `.about` and `.log` answer
    /// `false` unconditionally — none of them names a module that can be
    /// switched off at all.
    private func isModuleSwitchedOff() -> Bool {
        guard case .module(let id) = currentSelection else { return false }
        return model.host.liveModule(id) == nil
    }

    private func armGrace(for key: String) {
        graceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.gracePageKey == key, self.pageKey == key else { return }
            self.gracePageKey = nil
            self.graceWorkItem = nil
            guard self.channel.content(for: AnyHashable(key)) == nil else { return }
            self.fellBackToNameOnly.insert(key)
            self.assignNameOnly()
        }
        gracePageKey = key
        graceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.graceInterval, execute: work)
    }

    /// `[.sidebarTrackingSeparator?, name, .flexibleSpace, tabs,
    /// .flexibleSpace, action…, search]` — the owner's own zones, left to
    /// right. The tracking separator is always first: this window's
    /// `.fullSizeContentView` style mask plus its real sidebar item are
    /// exactly the shape `NSToolbarSidebarTrackingSeparatorItemIdentifier`'s
    /// own header names ("automatically configures it to track the divider
    /// of the sidebar if one is discovered … windows with
    /// `NSWindowStyleMaskFullSizeContentView`"), so it is never conditional
    /// here — only the name item, and the name-only bar's own trailing status
    /// zone, are, on the page-bar style (`style == .moduleName` gates both,
    /// below). A hidden action
    /// never removes this list's one `helm.actions` entry — which declared
    /// actions actually draw is the capsule's own model
    /// (`HelmToolbarAction.isVisible`), not `NSToolbarItem.isHidden`, which
    /// nothing here sets any more now that every action shares one item —
    /// so a tab change never renegotiates the bar's shape.
    private static func identifiers(content: HelmPageToolbarContent?,
                                    style: PageBarStyle) -> [NSToolbarItem.Identifier] {
        var list: [NSToolbarItem.Identifier] = [.sidebarTrackingSeparator]
        if style == .moduleName { list.append(nameID) }
        guard let content, !content.tabs.isEmpty || !content.actions.isEmpty || content.search != nil
        else {
            // **The shared name-only bar's own trailing zone** — `helm.status`
            // is always present here, whether or not the page currently on
            // screen has anything to say (drawing nothing when it does not,
            // `makeStatusItem`'s own header): the identifier list this bar
            // carries must never depend on which of General, About, Log, Keep
            // Awake, VPN or Keyboard happens to be selected, since all of them
            // share this one cached `PageBar` (`obtainNameOnlyBar`) and a
            // list that changed shape between them would be exactly the
            // per-visit churn this class exists to rule out. Never on a page
            // that also declares tabs, actions or search — no page does both
            // today — and never under `.windowTitle`, where the status stays
            // the window's own subtitle (`PageBarStyle`'s own header).
            if style == .moduleName {
                list.append(.flexibleSpace)
                list.append(statusID)
            }
            return list
        }
        list.append(.flexibleSpace)
        if !content.tabs.isEmpty {
            list.append(tabsID)
            list.append(.flexibleSpace)
        }
        // One item for every declared action, whatever the tab currently
        // hides — `ShapeSignature.actionIDs` is what invalidates a cached bar
        // when the *declared* set moves, since the reserved width inside the
        // capsule (`HelmToolbarActionsCapsule`'s back layer) depends on it.
        if !content.actions.isEmpty { list.append(actionsID) }
        if content.search != nil { list.append(searchID) }
        return list
    }

    /// **What AppKit centres: the tabs, and the actions capsule with them
    /// when it carries a `.segmented` entry.** A segmented control whose
    /// item is listed in `NSToolbar.centeredItemIdentifiers` gets AppKit's
    /// lift-and-slide tracking — the selection lifts on the press and slides
    /// to the new segment — and one whose item is not tracks the classic way,
    /// the pressed segment lit beside the old one and the selection jumping
    /// on release, across every glass and label style tried — measured in a
    /// reference app built outside this tree and confirmed on the live page
    /// in Helm Dev (engineer, 2026-09-26; the frame counts are
    /// `HelmToolbarActionsCapsule`'s own body comment). **Not across every
    /// hosting**: the same reference wrapped the capsule in an AppKit platter
    /// of its own (`capsule-bordered`, diagnosis only) and got neither
    /// tracking cleanly — Dark L 1,0,1 / S 0,0,0 / B 11,10,10, Light L
    /// 14,0,14 / S 0,4,0 / B 0,1,0, against the classic case's steady L
    /// 0,0,0 / S 0,0,0 / B 3–4 in both — a hosting this capsule's own item
    /// never takes, since it stays `isBordered = false` regardless
    /// (`HelmToolbarActionsCapsule`'s own header). So a capsule holding a
    /// switcher joins the set, which is what makes Hosts' Table / Plain-text
    /// slide the way the tabs do — the owner's decision, 2026-09-26.
    ///
    /// **Only beside the tabs.** Listed alone, the capsule is centred
    /// itself: in that same reference app, the capsule's item moved from the
    /// bar's trailing edge to its middle. Listed with the tabs, a flexible
    /// space between the two, it stays where it was — every page, English
    /// and Russian, at 1060 and 860 pt in `LivePageToolbarFixture` and at
    /// the real window's default and narrowest panes in the fold tests'
    /// split rig: the frames of `helm.tabs`, `helm.actions` and
    /// `helm.search` read the same to a tenth of a point before and after
    /// this set grew (engineer, 2026-09-26 —
    /// `Tests/HelmAppTests/ASwitcherInTheCapsuleIsCentredWithTheTabsTests.swift`'s
    /// own header carries the full reading, and its guard is what this
    /// method answers). **Only with a `.segmented` entry**: no other kind in
    /// the capsule has a selection to slide, so no other page's bar is asked
    /// to change. `ShapeSignature.hasSegmentedAction` is what builds a fresh
    /// bar if that answer moves.
    private static func centredIdentifiers(_ shape: ShapeSignature) -> Set<NSToolbarItem.Identifier> {
        guard !shape.tabIDs.isEmpty else { return [] }
        return shape.hasSegmentedAction ? [tabsID, actionsID] : [tabsID]
    }

    // MARK: - Delegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let bar = barsByToolbarID[ObjectIdentifier(toolbar)] else { return nil }
        switch identifier {
        case Self.nameID: return makeNameItem(bar)
        case Self.statusID: return makeStatusItem(bar)
        case Self.tabsID: return makeTabsItem(bar)
        case Self.searchID: return makeSearchItem(bar)
        case Self.actionsID: return makeActionsItem(bar)
        default: return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        barsByToolbarID[ObjectIdentifier(toolbar)]?.identifiers ?? []
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    // MARK: - Every zone, patched together

    private func patch(_ bar: PageBar, animated: Bool) {
        bar.isInteractive = true
        patchName(bar)
        patchTabs(bar)
        patchActions(bar, animated: animated)
        patchSearch(bar)
        bar.actionsModel?.setInteractive(true)
        bar.searchItem?.searchField.isEnabled = true
    }

    // MARK: - The name zone

    /// A cheap snapshot of what the last `patchName()` actually drew, into
    /// **both** the name host and the status host — so a page republishing on
    /// every keystroke (Homebrew's console, `hb`'s own `@Published`) does not
    /// hand either view a fresh root view, and the hosting view underneath
    /// it, on every one of them. One snapshot for both, not two: the two
    /// hosts dim by the same numbers and key off the same `appearsActive`
    /// (`NameZoneView` and `StatusZoneView`, each its own `.opacity()`), so
    /// there is nothing meaningful about being stale for one and not the
    /// other.
    ///
    /// `fileprivate`, not `private`: `PageBar` below is a sibling top-level
    /// type in this same file rather than an extension of this class, and it
    /// is where the last snapshot for each bar actually lives.
    fileprivate struct NameSnapshot: Equatable {
        let symbol: String
        let title: String
        let statusWord: String?
        let statusActive: Bool
        let iconStyle: SidebarStyle
        /// Included so a signal-only change (no page switch, no republish)
        /// still redraws — see `NameZoneView.appearsActive`'s own header.
        let appearsActive: Bool
        let titlebarIsTransparent: Bool
        /// The bar's own height — the status's trailing inset follows it
        /// (`StatusZoneView.trailingInset(for:barHeight:)`), so a bar that
        /// grows or shrinks redraws the item — `watchWindowResize`
        /// patches the attached bar on every resize, which is what reads it.
        let barHeight: CGFloat?
    }

    /// **The title bar and toolbar's own height** — the window's frame less
    /// its content layout rect, which is what AppKit centres every toolbar
    /// item in and therefore what sets the gap between the window's top edge
    /// and a shorter item's top (52 pt in a 700 pt window on macOS 27.2, read
    /// in `TheStatusBadgeSitsAsFarFromTheRightEdgeAsFromTheTopTests`).
    /// `nil` before there is a window.
    private var barHeight: CGFloat? {
        window.map { $0.frame.height - $0.contentLayoutRect.height }
    }

    /// The title bar the name zone is drawn under, read off the window
    /// itself — `SettingsWindow` sets it from the band decision, and a rig
    /// sets it by hand; macOS 27's until there is a window.
    private var titlebarIsTransparent: Bool { window?.titlebarAppearsTransparent ?? true }

    private func makeNameItem(_ bar: PageBar) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.nameID)
        let identity = pageIdentity()
        let hosting = NSHostingView(rootView: NameZoneView(symbol: identity.symbol, tint: identity.tint,
                                                           title: identity.title,
                                                           iconStyle: AppSettings.sidebarStyle,
                                                           appearsActive: windowAppearsActive,
                                                           titlebarIsTransparent: titlebarIsTransparent))
        hosting.sizingOptions = [.intrinsicContentSize]
        item.view = hosting
        // A title is not a control: no glass behind it — the same call
        // `PageBarStyle`'s SwiftUI `.moduleName` arm made with
        // `.sharedBackgroundVisibility(.hidden)`, said here in the term a
        // custom-view item reads instead (`isBordered` forwards to the view).
        item.isBordered = false
        item.label = identity.title
        bar.nameItem = item
        bar.nameHost = hosting
        bar.lastNameSnapshot = NameSnapshot(symbol: identity.symbol, title: identity.title,
                                            statusWord: identity.status?.word,
                                            statusActive: identity.status?.active ?? false,
                                            iconStyle: AppSettings.sidebarStyle,
                                            appearsActive: windowAppearsActive,
                                            titlebarIsTransparent: titlebarIsTransparent,
                                            barHeight: barHeight)
        return item
    }

    /// **The trailing status item on the shared name-only bar** — the owner,
    /// 2026-09-28: «Давай вернем его в правую часть». Always present in that
    /// bar's own identifier list (`identifiers()`'s own header), whether or
    /// not the page on screen right now has a status at all, so a page
    /// switch among General, About, Log, Keep Awake, VPN and Keyboard —
    /// which all share this one cached bar — never rewrites `itemIdentifiers`
    /// (this class's own header on why that churns). **Empty and out of
    /// VoiceOver when there is nothing to say** — `StatusZoneView`'s own
    /// `accessibilityHidden(status == nil)` — rather than `NSToolbarItem
    /// .isHidden`: an item this bar's own `identifiers()` always lists but
    /// sometimes hides would need `watchedItems`/`checkOverflow`'s fold
    /// machinery to know to ignore it, and that machinery already skips the
    /// name-only bar entirely (`checkOverflow`'s own `key != Self.nameOnlyKey`
    /// guard) — an item that occasionally reported `isHidden` would be the
    /// one case nothing here is built to read.
    private func makeStatusItem(_ bar: PageBar) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.statusID)
        let identity = pageIdentity()
        let hosting = NSHostingView(rootView: StatusZoneView(
            status: identity.status, appearsActive: windowAppearsActive,
            titlebarIsTransparent: titlebarIsTransparent,
            trailingInset: StatusZoneView.trailingInset(for: identity.status, barHeight: barHeight)))
        hosting.sizingOptions = [.intrinsicContentSize]
        item.view = hosting
        item.isBordered = false
        item.label = identity.status?.word ?? ""
        bar.statusItem = item
        bar.statusHost = hosting
        return item
    }

    /// **Patches the name host and, where this bar carries one, the status
    /// host — one snapshot gates both** (`NameSnapshot`'s own header).
    /// `bar.statusHost` is `nil` on every bar except the shared name-only one
    /// (`makeStatusItem` is only ever reached through that bar's own
    /// identifier list), so a page with tabs, actions or search simply has
    /// nothing here to patch.
    private func patchName(_ bar: PageBar) {
        guard bar.nameHost != nil || bar.statusHost != nil else { return }
        let identity = pageIdentity()
        let snapshot = NameSnapshot(symbol: identity.symbol, title: identity.title,
                                    statusWord: identity.status?.word,
                                    statusActive: identity.status?.active ?? false,
                                    iconStyle: AppSettings.sidebarStyle,
                                    appearsActive: windowAppearsActive,
                                    titlebarIsTransparent: titlebarIsTransparent,
                                    barHeight: barHeight)
        bar.nameItem?.label = identity.title
        bar.statusItem?.label = identity.status?.word ?? ""
        guard snapshot != bar.lastNameSnapshot else { return }
        bar.lastNameSnapshot = snapshot
        if let nameHost = bar.nameHost {
            nameHost.rootView = NameZoneView(symbol: identity.symbol, tint: identity.tint,
                                             title: identity.title,
                                             iconStyle: AppSettings.sidebarStyle,
                                             appearsActive: windowAppearsActive,
                                             titlebarIsTransparent: titlebarIsTransparent)
        }
        if let statusHost = bar.statusHost {
            statusHost.rootView = StatusZoneView(
                status: identity.status, appearsActive: windowAppearsActive,
                titlebarIsTransparent: titlebarIsTransparent,
                trailingInset: StatusZoneView.trailingInset(for: identity.status, barHeight: barHeight))
        }
    }

    /// Whichever bar is on screen right now, patched with the page identity
    /// it should currently be showing — the one caller that reaches a bar
    /// outside `refresh()`'s own flow, since a module's activity can change
    /// asynchronously between page switches (`watchActivity`).
    private func patchAttachedName() {
        guard let key = attachedPageKey else { return }
        if key == Self.nameOnlyKey {
            if let bar = nameOnlyBar { patchName(bar) }
        } else if let bar = pageBars[key] {
            patchName(bar)
        }
    }

    // MARK: - The tabs zone

    /// **The tabs have one form: `HelmToolbarSwitcher`.** A dev-only toggle
    /// used to choose between this and AppKit's own `NSToolbarItemGroup` —
    /// retired 2026-09-23 once the owner had looked at both on a real window
    /// and kept this one; `ARCHITECTURE.md`'s own paragraph on the tabs zone
    /// says the same thing in the same words.
    private func makeTabsItem(_ bar: PageBar) -> NSToolbarItem {
        let tabs = bar.content?.tabs ?? []
        let item = NSToolbarItem(itemIdentifier: Self.tabsID)
        let hosting = NSHostingView(rootView: helmSwitcherView(tabs, bar: bar))
        hosting.sizingOptions = [.intrinsicContentSize]
        item.view = hosting
        item.label = HelmA11y.whatToShow
        bar.tabsSwitcherHost = hosting
        bar.tabsItem = item
        bar.lastTabsSnapshot = HelmTabsSnapshot(tabs: tabs, style: AppSettings.toolbarSwitcherStyle,
                                                isInteractive: bar.isInteractive,
                                                tabsEnabled: bar.content?.tabsEnabled ?? true,
                                                compact: bar.tabsFolded,
                                                selectedID: bar.content?.selectedTab?.wrappedValue)
        patchTabsMenu(bar)
        return item
    }

    /// The Helm-style switcher, with the style it is meant to be compared
    /// under carried in explicitly — it is hosted in its own `NSHostingView`,
    /// outside the pane's environment, so nothing above it in a view tree
    /// hands it `AppSettings.toolbarSwitcherStyle` the way `SettingsWindow`
    /// hands the pane's own controls; `NameZoneView`'s icon style takes the
    /// same route for the same reason. `compact: bar.tabsFolded` is read here
    /// rather than the fold writing straight to the hosted view, so
    /// `patchTabs` and `freeze` never have to rebuild the whole switcher just
    /// to fold it — `SettingsToolbar.setTabsFolded(_:bar:layout:reseat:)` is
    /// the one writer of `tabsFolded`, and this is the one reader.
    private func helmSwitcherView(_ tabs: [HelmToolbarTab], bar: PageBar) -> AnyView {
        AnyView(
            HelmToolbarSwitcher(HelmA11y.whatToShow, selection: tabsBinding(bar),
                                segments: tabs.map { HelmSwitcherSegment($0.id, $0.title, symbol: $0.symbol) },
                                compact: bar.tabsFolded, menu: barMenu)
                .environment(\.helmSwitcherStyle, AppSettings.toolbarSwitcherStyle)
                // A frozen bar's tabs are disabled through `bar.isInteractive`
                // rather than through `bar.isLive` — see `HelmTabsSnapshot`'s
                // own header for why the two must not be conflated — since
                // this custom-view item carries none of
                // `NSToolbarItem.autovalidates`' machinery to disable through.
                // `tabsEnabled` dims the same way, for a page that has
                // declared the whole switcher inapplicable right now
                // (Uninstaller's review step) rather than merely frozen.
                .disabled(!bar.isInteractive || !(bar.content?.tabsEnabled ?? true))
        )
    }

    private func tabsBinding(_ bar: PageBar) -> Binding<String> {
        Binding(get: { [weak bar] in bar?.content?.selectedTab?.wrappedValue ?? "" },
               set: { [weak bar] newValue in
                   guard bar?.content?.tabsEnabled ?? true else { return }
                   bar?.content?.selectedTab?.wrappedValue = newValue
               })
    }

    /// The Helm switcher's own change-skip, on the same grounds as
    /// `NameSnapshot` — plus the label style, since a style change is exactly
    /// what this snapshot used to miss: comparing only the segment list left
    /// a style change with nothing to invalidate, so the hosted switcher went
    /// on showing whatever style it was built with until an unrelated shape
    /// change rebuilt the item from under it.
    ///
    /// **`isInteractive`, not `isLive`.** An ordinary return visit sets
    /// `bar.isLive = false` on every single frozen turn — including the ones
    /// where nothing about the tabs should visibly change at all
    /// (`freeze(_:visibly:)`'s own header) — so a snapshot keyed on `isLive`
    /// rebuilt the switcher, and its `.disabled(...)`, on every one of them:
    /// that rebuild, and AppKit's own eviction-and-reinsertion scale-and-fade
    /// on the item viewer this rebuild is not the same thing as, is what read
    /// as "the tabs' text still animates" even after the tabs stopped being
    /// evicted. `isInteractive` moves only on a *visible* freeze or a live
    /// `patch(_:)` — see `freeze(_:visibly:)` and `patch(_:animated:)` — so an
    /// ordinary return visit, which never touches it, leaves this snapshot
    /// equal and rebuilds nothing.
    ///
    /// `compact` is the third: `setTabsFolded` writes `bar.tabsFolded` and
    /// calls `patchTabs` itself rather than waiting for this snapshot to
    /// notice — see that method's own header — but this still has to carry
    /// the value, because a *different* trigger for `patchTabs` (a language
    /// change arriving while folded, say) must not read a stale snapshot and
    /// skip rebuilding a switcher that is still compact.
    ///
    /// **`selectedID` is the fourth, and the one a picked tab needs.** A
    /// compact capsule shows exactly one segment — the selected tab — and a
    /// choice from its own menu (`HelmToolbarSwitcher.Coordinator
    /// .pickedFromMenu`) writes straight through the page's own
    /// `selectedTab` binding rather than through anything AppKit's segmented
    /// control tracks itself, the way a plain click on a full-width segment
    /// does. With nothing else about the tabs' shape moving, a snapshot that
    /// left the selection out never told `patchTabs` to hand the hosted
    /// switcher a fresh `selection`, so the one visible segment, and the
    /// menu's own tick, both kept naming the tab that had just been left.
    ///
    /// `fileprivate` for the reason `NameSnapshot` above states.
    fileprivate struct HelmTabsSnapshot: Equatable {
        let ids: [String]
        let titles: [String]
        let symbols: [String]
        let style: ToolbarSwitcherStyle
        let isInteractive: Bool
        /// The fifth field, added beside `isInteractive` rather than folded
        /// into it: a page can freeze (return visit, module switched off)
        /// with its switcher still enabled, and can stay live while its own
        /// switcher is inapplicable (Uninstaller's review step) — two
        /// different reasons to dim, so a redeclare that moves only this one
        /// still has to rebuild the hosted switcher's `.disabled(...)`.
        let tabsEnabled: Bool
        let compact: Bool
        let selectedID: String?
        init(tabs: [HelmToolbarTab], style: ToolbarSwitcherStyle, isInteractive: Bool, tabsEnabled: Bool,
             compact: Bool, selectedID: String?) {
            ids = tabs.map(\.id); titles = tabs.map(\.title); symbols = tabs.map(\.symbol)
            self.style = style
            self.isInteractive = isInteractive
            self.tabsEnabled = tabsEnabled
            self.compact = compact
            self.selectedID = selectedID
        }
    }

    /// **What the centre tabs' full width was measured under** — the one
    /// reading `settle(_:)` keeps on the bar (`PageBar.tabsWidth`) rather than
    /// taking again. A measurement is a `SwitcherMeasurementRig` mount — a
    /// hosting view, a toolbar and a layout — and every declare re-arms a
    /// settle, so a page that republishes on every keystroke (Hosts' SSH
    /// editor, `HostsViewModel.setSSHText(_:)`) paid for measurements after
    /// every character, for tabs nothing typed can move:
    /// `AKeystrokeInHostsSettlesWithoutMeasuringTheTabsTests` counted 20 for
    /// 10 keystrokes before this key (tester, 2026-09-26, compact and full
    /// both measured), and 10 for 10 with the key's read taken out once only
    /// the full width was (engineer, 2026-09-26).
    ///
    /// Everything that reaches what the switcher draws: the segments' ids,
    /// words and glyphs, the label style, the language and the selection. The
    /// words are already looked up in the running language, so `language`
    /// says nothing a changed word does not; it is kept so that a language
    /// change is a miss whatever a page's tabs carry. Compared by equality
    /// and never explicitly reset — unlike `UnfoldRefusalKey` and
    /// `PageBar.refusedUnfold`, which `searchFieldFrameChanged` and
    /// `tookMagnifierPress` clear at the start of each new interaction
    /// (`UnfoldRefusalKey`'s own header) — a stale entry here is simply
    /// overwritten the next time this key misses, so a change to `style`,
    /// `language`, `selectedID`, `titles` or `symbols` alone is a miss the
    /// next settle measures, with no notification to forget. **Not true of `ids`**: a
    /// moved id reaches `ShapeSignature.tabIDs` first, and that mismatch
    /// rebuilds the bar — a fresh `PageBar`, with no cached width at all —
    /// before this key is ever compared, so a key with `ids` left out would
    /// be measured exactly as often
    /// (`TheTabsAreMeasuredAgainOnlyWhenWhatTheyDrawMovesTests
    /// .testNewIdsUnderTheSameWordsAreMeasuredOnceOnAFreshBar`, tester,
    /// 2026-09-26). The field stays on the key regardless — a change to it
    /// alone never reaches this comparison to be the miss. Kept per bar, not
    /// in a static table: a bar is dropped with its shape, and its width
    /// goes with it.
    ///
    /// `fileprivate` for the reason `NameSnapshot` above states.
    fileprivate struct TabsWidthKey: Equatable {
        let ids: [String]
        let titles: [String]
        let symbols: [String]
        let style: ToolbarSwitcherStyle
        let language: AppLanguage
        let selectedID: String?
        init(tabs: [HelmToolbarTab], style: ToolbarSwitcherStyle, language: AppLanguage, selectedID: String?) {
            ids = tabs.map(\.id); titles = tabs.map(\.title); symbols = tabs.map(\.symbol)
            self.style = style
            self.language = language
            self.selectedID = selectedID
        }
    }

    private func patchTabs(_ bar: PageBar) {
        // Kept current whether or not the switcher's own root view needs
        // rebuilding below — mirrors `patchActionsMenu`'s own place at the
        // end of `patchActions`.
        patchTabsMenu(bar)
        guard let content = bar.content, !content.tabs.isEmpty else { return }
        guard let tabsSwitcherHost = bar.tabsSwitcherHost else { return }
        let snapshot = HelmTabsSnapshot(tabs: content.tabs, style: AppSettings.toolbarSwitcherStyle,
                                        isInteractive: bar.isInteractive, tabsEnabled: content.tabsEnabled,
                                        compact: bar.tabsFolded, selectedID: content.selectedTab?.wrappedValue)
        guard snapshot != bar.lastTabsSnapshot else { return }
        bar.lastTabsSnapshot = snapshot
        tabsSwitcherHost.rootView = helmSwitcherView(content.tabs, bar: bar)
    }

    /// **The floor for the rare case where even the compact capsule
    /// overflows** (German or French at the widest sidebar, say) — mirrors
    /// `patchActionsMenu`'s own reason: a custom-view item has no menu form
    /// of its own, so without this AppKit's own «»» menu would offer the
    /// tabs item's label with nothing behind it to press.
    private func patchTabsMenu(_ bar: PageBar) {
        guard let item = bar.tabsItem, let content = bar.content, !content.tabs.isEmpty else { return }
        let top = NSMenuItem(title: HelmA11y.whatToShow, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: HelmA11y.whatToShow)
        submenu.autoenablesItems = false
        let selected = content.selectedTab?.wrappedValue
        for tab in content.tabs {
            let menuItem = NSMenuItem(title: tab.title, action: #selector(tabsMenuItemPressed(_:)),
                                      keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = tab.id
            menuItem.isEnabled = bar.isLive && content.tabsEnabled
            menuItem.state = tab.id == selected ? .on : .off
            submenu.addItem(menuItem)
        }
        top.submenu = submenu
        item.menuFormRepresentation = top
    }

    @objc private func tabsMenuItemPressed(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let key = attachedPageKey, let bar = pageBars[key], bar.isLive,
              bar.content?.tabsEnabled ?? true else { return }
        bar.content?.selectedTab?.wrappedValue = id
    }

    // MARK: - Folding the tabs

    /// One press, over the line between a monitor's `@Sendable` handler and
    /// the main actor it is already on — the same shape
    /// `HelmToolbarSwitcher.Coordinator.watch(_:)` carries a press across,
    /// restated here because that one is a top-level type scoped to a generic
    /// `Value` this class does not share.
    private struct FoldPress: @unchecked Sendable {
        let event: NSEvent
    }

    /// `Notification` is not `Sendable` (its `object: Any?` is not, in
    /// general) — the same crossing, for `splitResizeWatch`'s handler.
    private struct FoldNotification: @unchecked Sendable {
        let note: Notification
    }

    /// Where a fold's own relayout is driven from — see
    /// `setTabsFolded(_:bar:layout:reseat:)`'s own header.
    private enum FoldLayout {
        /// From outside AppKit's own layout pass (a mouse press, the
        /// coalesced overflow hop, a settle tick): lays the window out
        /// itself, since nothing else is about to.
        case window
        /// From *inside* AppKit's own layout pass (M2's frame-change
        /// observer fires synchronously while AppKit is already laying the
        /// toolbar out): only lays the switcher's own host out, since asking
        /// the window to lay itself out again from inside its own pass is
        /// redundant at best.
        case hostOnly
    }

    /// **The one writer of `PageBar.tabsFolded`.** M1, M2, M3 and `settle(_:)`
    /// all call this rather than writing the flag directly.
    ///
    /// - Parameter reseat: whether to detach and reattach the tabs item's
    ///   view (`item.view = nil`, then the same host) after patching — the
    ///   only way an item AppKit has already moved into its own «»» overflow
    ///   menu comes back once there is room again, measured against leaving
    ///   this out.
    private func setTabsFolded(_ folded: Bool, bar: PageBar, layout: FoldLayout, reseat: Bool = false) {
        guard bar.tabsFolded != folded else { return }
        bar.tabsFolded = folded
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = 0
            animation.allowsImplicitAnimation = false
            patchTabs(bar)
            bar.tabsSwitcherHost?.layoutSubtreeIfNeeded()
        }
        if reseat, let item = bar.tabsItem, let host = bar.tabsSwitcherHost {
            item.view = nil
            item.view = host
        }
        switch layout {
        case .window: window?.layoutIfNeeded()
        case .hostOnly: break
        }
    }

    /// **A sibling with no size of its own, never the view being measured**
    /// (`CLAUDE.md`'s own rule for a geometry reading): the detail pane's own
    /// width when this window's content is the split view it always is
    /// (`SettingsSplitViewController`), or the window's whole content layout
    /// rect for a window under test that mounts the toolbar without one.
    private func offeredRoom() -> CGFloat {
        guard let window else { return 0 }
        if let split = window.contentViewController as? NSSplitViewController,
           let detail = split.splitViewItems.last {
            return detail.viewController.view.bounds.width
        }
        return window.contentLayoutRect.width
    }

    private func watchedItems(_ bar: PageBar) -> [NSToolbarItem] {
        [bar.nameItem, bar.tabsItem, bar.actionsItem].compactMap { $0 }
    }

    /// Every watched item that this bar actually wants shown (`!isHidden`) is
    /// reported by AppKit as actually showing (`isVisible`) — an item this
    /// bar hides on purpose (the name item under `.windowTitle`) does not
    /// count either way.
    private func watchedItemsAllVisible(_ bar: PageBar) -> Bool {
        watchedItems(bar).allSatisfy { $0.isHidden || $0.isVisible }
    }

    /// **M1: catches a press on the magnifier before AppKit's own
    /// `searchButtonClicked:` handles it**, so a fold the rest verdict calls
    /// for is done before the field starts growing — AppKit's own path cannot be
    /// hooked (an override of `beginSearchInteraction` is never called), so a
    /// local monitor ahead of it is the only way in. Installed once, when the
    /// window is set (`window`'s own `didSet`, alongside
    /// `watchWindowResize()`), and removed in `deinit`.
    ///
    /// **The bar's right-click rides the same monitor, and is asked first.**
    /// A Control-click on the collapsed magnifier is a left-button press that
    /// both would claim — the menu, or folding the tabs and opening search —
    /// and with two monitors which one wins would rest on the order AppKit
    /// calls them in, which it does not document. One handler, the menu
    /// first, decides it here; `HelmToolbarSwitcher`'s own monitor never
    /// takes the gesture, so no switcher can answer it either.
    private func watchBarPresses() {
        if let barPressMonitor { NSEvent.removeMonitor(barPressMonitor) }
        guard window != nil else { barPressMonitor = nil; return }
        barPressMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            let press = FoldPress(event: event)
            return MainActor.assumeIsolated {
                guard let self else { return false }
                if self.opensBarMenu(press.event) {
                    self.popUpBarMenu(press.event)
                    return true
                }
                return press.event.type == .leftMouseDown && self.tookMagnifierPress(press.event)
            } ? nil : event
        }
    }

    /// **Whether an opening search field may keep the tabs full, per
    /// `settle(_:)`'s own last verdict** — read by M1 and M2, and the only
    /// thing either reads to make that call: neither measures anything of
    /// its own any more. `settle(_:)` runs outside AppKit's own layout pass
    /// and decides once, at rest, from the same `predictedSlack(bar:
    /// tabsWidth:)` an unfold decision already uses, plus the width an open
    /// field would add; a decision remade live inside M2 would read sibling
    /// positions from *inside* that pass (`FoldLayout.hostOnly`'s own
    /// header) — a frame that may still be the one before this layout — and
    /// a decision remade live inside M1 would have to charge the hidden
    /// field's own frame, which is a different reading before a press than
    /// after one and has nothing to do with the room the field is about to
    /// occupy once open.
    ///
    /// **`false` whenever there is nothing safe to read**: the cap is not
    /// even active (the natural, AppKit-collapsed path, which this predicate
    /// must never touch — that path keeps its own unconditional fold, below),
    /// `settle(_:)` has never run for this bar (`bar.rest == nil`), or the
    /// room has moved since its last pass. An unanchored or stale reading
    /// folds — the safe direction, the same one `currentToolbarSlack(_:)`
    /// returning `nil` already gives every other prediction in this file.
    private func openingKeepsTheTabs(_ bar: PageBar) -> Bool {
        bar.searchRestCap?.isActive == true && bar.rest?.openFits == true
            && bar.rest?.room == offeredRoom()
    }

    /// True consumes the press (folds and opens search, or ends search
    /// interaction on the way to whatever was actually clicked need not be
    /// blocked — see the second branch, which always returns `false`).
    ///
    /// `internal`, not `private`: the real caller is the local monitor above,
    /// which is the only thing that can hand this a genuine mouse-down — a
    /// synthetic `NSEvent` routed through `NSApp.sendEvent(_:)` would have to
    /// resolve `event.window` off a window nothing has ordered onto the
    /// screen list, which a test has no business depending on; a test that
    /// wants M1's own decision instead builds the event and calls straight
    /// in, the same widened-for-testing precedent `settleInterval` and
    /// `graceInterval` already set in this file.
    func tookMagnifierPress(_ event: NSEvent) -> Bool {
        guard let window, event.window === window,
              let key = attachedPageKey, key != Self.nameOnlyKey,
              let bar = pageBars[key], bar.isLive,
              let searchItem = bar.searchItem, let content = bar.content, !content.tabs.isEmpty
        else { return false }
        let field = searchItem.searchField
        let locationInWindow = event.locationInWindow

        // **Fold on every magnifier press, per the owner's own words** — with
        // one exception, added later than this comment's own claim of
        // "every": a field the rest cap alone is holding collapsed
        // (`PageBar.searchRestCap`) says nothing about room, so
        // `openingKeepsTheTabs(_:)` is asked first, and the fold below runs
        // only when it answers no. A field AppKit itself collapsed for lack
        // of room keeps the original, unconditional fold — `isHidden` there
        // already *is* the room reading, and `openingKeepsTheTabs(_:)`
        // answers false whenever the cap is inactive, which is this path.
        // Folding always precedes `beginSearchInteraction()` below, so a
        // fold that does happen still finishes before the field starts
        // growing.
        if field.isHidden, !bar.tabsFolded, let superview = field.superview {
            let point = superview.convert(locationInWindow, from: nil)
            if superview.bounds.contains(point) {
                // A fresh search interaction starting — whatever the last one
                // was refused for is not this one's business. See
                // `UnfoldRefusalKey`'s own header for why a refusal must not
                // outlive the cycle it was recorded against.
                bar.refusedUnfold = nil
                bar.pendingUnfoldFieldWidth = nil
                if !openingKeepsTheTabs(bar) {
                    setTabsFolded(true, bar: bar, layout: .window)
                }
                bar.searchOpening = true
                searchItem.beginSearchInteraction()
                return true
            }
        }

        // **The missing fold-back.** A press on content that cannot take
        // first responder — most of a settings pane — leaves the field's
        // editor as first responder with nothing else in AppKit ever ending
        // that; a press *inside* the field itself is ordinary editing and
        // must not be treated as "outside".
        if field.currentEditor() != nil, window.contentLayoutRect.contains(locationInWindow) {
            var insideField = false
            if let superview = field.superview {
                insideField = superview.bounds.contains(superview.convert(locationInWindow, from: nil))
            }
            if !insideField {
                searchItem.endSearchInteraction()
            }
        }
        return false
    }

    /// Installs the observers `settle(_:)` needs to be re-armed by on a
    /// resize — called once, alongside `watchBarPresses()`, and removed
    /// the same way, in `deinit`.
    private func watchWindowResize() {
        if let windowResizeWatch { NotificationCenter.default.removeObserver(windowResizeWatch) }
        if let windowEndLiveResizeWatch {
            NotificationCenter.default.removeObserver(windowEndLiveResizeWatch)
        }
        if let splitResizeWatch { NotificationCenter.default.removeObserver(splitResizeWatch) }
        guard let window else {
            windowResizeWatch = nil
            windowEndLiveResizeWatch = nil
            splitResizeWatch = nil
            return
        }
        windowResizeWatch = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowDidResize() }
        }
        windowEndLiveResizeWatch = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowDidResize() }
        }
        // Not scoped to `object: window` — an `NSSplitView`'s own
        // notification names only itself, so this filters on the split
        // view's `.window` inside the handler instead.
        splitResizeWatch = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification, object: nil, queue: .main) { [weak self] note in
            // `Notification` is not `Sendable` — boxed the same way `NSEvent`
            // is (`FoldPress`, above), to carry it across into the isolated
            // block below.
            let boxed = FoldNotification(note: note)
            MainActor.assumeIsolated {
                guard let self, let splitView = boxed.note.object as? NSSplitView,
                      splitView.window === self.window else { return }
                self.scheduleSettleForAttachedBar()
            }
        }
    }

    /// A resize can come with a new bar height (full screen, expected to
    /// change it; not measured) and no page switch, and the status's trailing inset follows that
    /// height (`NameSnapshot.barHeight`): re-read it before settling. The
    /// snapshot gate keeps the offscreen ink measurement to the resizes that
    /// moved something it reads.
    private func windowDidResize() {
        patchAttachedName()
        scheduleSettleForAttachedBar()
    }

    private func scheduleSettleForAttachedBar() {
        guard let key = attachedPageKey else { return }
        let bar = key == Self.nameOnlyKey ? nameOnlyBar : pageBars[key]
        if let bar { scheduleSettle(bar) }
    }

    /// Re-arms the one settle timer for `bar` — called from M2, from the
    /// search field ending its own editing, from a window or split-view
    /// resize, after every `show()` and after a language, label-style or
    /// page-bar change (`refreshAndResettle()`).
    private func scheduleSettle(_ bar: PageBar) {
        settleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self, weak bar] in
            guard let self, let bar else { return }
            self.settle(bar)
        }
        settleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleInterval, execute: work)
    }

    // MARK: - Predicting whether the tabs can grow
    //
    // Replaces the trial-and-error unfold this class used to run here: unfold
    // on the live bar, let AppKit's own `isVisible` say whether it fit, refold
    // if it did not. At a room the full tabs never fit, that trial ran on
    // every settle — most visibly on every search exit, since ending an
    // interaction always re-armed one (`controlTextDidEndEditing`) — and each
    // one evicted the tabs and the actions into AppKit's own «»» scale-and-fade
    // and brought them back a frame later, which is the flicker the owner
    // reported both opening search and leaving it: `grep "room=646.0"
    // ~/Library/Logs/Helm/helm.log` on the owner's own machine showed several
    // such unfold/fold pairs landing within milliseconds of each other, e.g.
    // an unfold immediately followed by a fold at the same, unchanged room.
    // What follows predicts the fit instead, from siblings of the tabs item
    // and an off-screen measurement of the switcher, so nothing here ever
    // touches the live, attached bar to find out whether a layout holds.

    /// **A never-shown `NSToolbarItem`, in a never-shown `NSToolbar`, in a
    /// never-shown `NSWindow` — built once and reused for every off-screen
    /// measurement.** A bare `NSHostingView` asked for its own `fittingSize`
    /// is not what `switcherWidth(tabs:style:selectedID:)` needs: measured
    /// against the same switcher hosted in a real toolbar item, in a real
    /// (if never-ordered) window, the bare reading overestimates by 3–57.5 pt
    /// depending on label style and tab count — Text style at four tabs the
    /// worst of it — which is more than `unfoldMargin` (engineer, this Mac:
    /// the same `HelmToolbarSwitcher` configuration measured both ways side
    /// by side).
    /// A toolbar item resolves its content's environment differently from a
    /// bare hosting view with no toolbar or window above it at all — exactly
    /// which environment value accounts for the gap is not something this
    /// comment claims to have isolated — so the fix is to measure inside the
    /// same kind of container the attached item actually is, not to guess at
    /// a correction. The window is real enough for AppKit to lay a toolbar
    /// out in and is never ordered in at all — `isOnScreen` is what
    /// `AnUnfoldIsPredictedNeverTrialledTests.testTheMeasurementWindowNeverReachesTheScreen` reads — and it is
    /// reused across every call precisely so this measurement never touches
    /// the live, attached bar.
    @MainActor
    private final class SwitcherMeasurementRig: NSObject, NSToolbarDelegate {
        private static let itemID = NSToolbarItem.Identifier("helm.measure")
        private let window: NSWindow
        private var hostView: NSHostingView<AnyView>?

        override init() {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 2_000, height: 44),
                              styleMask: [.titled, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            // Never ordered in: `orderBack(nil)`, which stood here, *is* an
            // ordering — it put this empty 2000 × 44 window on screen under
            // every other one, where the owner found it (2026-09-25). The
            // rest makes it inert in case anything ever orders it anyway.
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.isExcludedFromWindowsMenu = true
            window.collectionBehavior = [.transient, .ignoresCycle]
            super.init()
        }

        /// Whether the rig's window is on screen — for the check that it
        /// never is.
        var isOnScreen: Bool { window.isVisible }
        /// How many measurements this rig has taken — so that check can
        /// first see a measurement happen before it asserts the window
        /// stayed off screen through it.
        private(set) var measurements = 0

        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                    willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            guard identifier == Self.itemID, let hostView else { return nil }
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = hostView
            return item
        }
        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [.flexibleSpace, Self.itemID, .flexibleSpace]
        }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            toolbarDefaultItemIdentifiers(toolbar)
        }

        /// A fresh toolbar every call — cheap next to the window it reuses,
        /// and identifier collisions are `NSToolbar.h`'s own reason to avoid
        /// two objects sharing one (this class's own file header, on
        /// `barSerial`) — rather than reconfiguring one item in place, which
        /// would have to fight the same delegate-diffing this file's own
        /// `buildBar` avoids by populating a toolbar only while detached.
        func measure(_ view: AnyView) -> CGFloat {
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = [.intrinsicContentSize]
            hostView = hosting
            let toolbar = NSToolbar(identifier: NSToolbar.Identifier("HelmSettingsToolbar.measure.\(UUID().uuidString)"))
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.layoutIfNeeded()
            let width = hosting.frame.width
            measurements += 1
            window.toolbar = nil
            hostView = nil
            return width
        }
    }

    /// One rig for the whole app, not one per `SettingsToolbar` — there is
    /// only ever one settings window, but nothing here depends on that, and a
    /// second instance would just mean a second idle, never-shown window.
    private static let measurementRig = SwitcherMeasurementRig()

    /// Whether the shared measurement window has reached the screen — read by
    /// `AnUnfoldIsPredictedNeverTrialledTests.testTheMeasurementWindowNeverReachesTheScreen` after a real
    /// measurement has run.
    static var measurementWindowIsOnScreen: Bool { measurementRig.isOnScreen }
    static var measurementsTaken: Int { measurementRig.measurements }

    /// **The full width of the same `HelmToolbarSwitcher` configuration the
    /// attached item hosts — measured in a real toolbar item, never the
    /// attached view's own resolved size**, which is the view this decision
    /// changes: a size AppKit has already squeezed reports the squeeze, not
    /// the shape the switcher wants (`CLAUDE.md`'s own rule against measuring
    /// the view a decision changes). `SwitcherMeasurementRig` is what stands
    /// in for the attached item's own rendering context — a bare, unattached
    /// `NSHostingView` is not close enough (that class's own header) — with
    /// the same segments, style and selection the attached switcher is
    /// drawing, so a longer word in the running language costs what it would
    /// cost the real control. Full only: the compact form's width was
    /// measured beside it until nothing read it (`settle(_:)` bound it to
    /// `_`). Called only from `settle(_:)`, behind `PageBar.tabsWidth`.
    private func switcherWidth(tabs: [HelmToolbarTab], style: ToolbarSwitcherStyle,
                               selectedID: String?) -> CGFloat {
        let view = HelmToolbarSwitcher(HelmA11y.whatToShow, selection: .constant(selectedID ?? ""),
                                       segments: tabs.map { HelmSwitcherSegment($0.id, $0.title, symbol: $0.symbol) },
                                       compact: false)
            .environment(\.helmSwitcherStyle, style)
        return Self.measurementRig.measure(AnyView(view))
    }

    /// **The width the search field claims right now, or is about to
    /// claim.** `bar.searchOpening` covers the gap between a press and the
    /// field editor actually arriving (`PageBar.searchOpening`'s own header)
    /// — while it is set, the field's current frame is still mid-animation
    /// and understates what it is growing toward, so the budget takes the
    /// larger of that frame and `NSSearchToolbarItem.preferredWidthForSearchField`
    /// (`NSSearchToolbarItem.h`: "This value is used to configure the search
    /// field width whenever it gets the keyboard focus").
    ///
    /// **Settled, empty and not being edited, the budget is the field's own
    /// collapsed (magnifier) width — never its current resting frame.**
    /// AppKit widens an idle, empty search field into whatever room a fold
    /// just freed, at rest, with nobody editing anything — that resting frame
    /// is a consequence of the last fold, not an independent demand, and
    /// charging it as fixed cost is what latched the tabs folded for good:
    /// fold once, the field visibly widens into the freed room, the next
    /// prediction reads that wider frame as unavoidable and never finds
    /// enough slack to unfold again, and the field never shrinks back to its
    /// magnifier either, since nothing ever asks it to (engineer, this Mac:
    /// after `endSearchInteraction()` the tabs stayed compact and the field
    /// stayed visible at its resting width, in every round, at every pane
    /// width where a fold had ever happened). `collapsedFieldWidth` is captured the
    /// moment the field is actually seen collapsed — including the very
    /// first `settle()` of a fresh bar, which always starts collapsed — so
    /// this budget predicts what AppKit will *do* if the tabs take the room
    /// back, not what the field happens to look like right now. A field left
    /// with real text after editing ends is a genuine demand and keeps its
    /// current width, per this method's own long-standing rule for that
    /// case. With Always Collapse Search on, the field at rest is always the
    /// magnifier (`PageBar.searchRestCap`), so the collapsed width read here
    /// is the one it charges at every room.
    private func searchRoomBudget(_ bar: PageBar) -> CGFloat {
        guard let searchItem = bar.searchItem else { return 0 }
        let field = searchItem.searchField
        let current = field.frame.width
        if bar.searchOpening {
            return max(current, searchItem.preferredWidthForSearchField)
        }
        guard field.currentEditor() == nil, field.stringValue.isEmpty else { return current }
        if field.isHidden { bar.collapsedFieldWidth = current }
        return bar.collapsedFieldWidth ?? current
    }

    /// **The window's own inline title, when the page-bar style draws one
    /// instead of a name item** (`PageBarStyle.windowTitle`,
    /// `SettingsWindow.applyTitle(_:)`) — `NSToolbarTitleView`, AppKit's own
    /// container for the title and subtitle text it draws inside the
    /// toolbar, found by class name rather than by type (it carries no
    /// public header, the same necessity every AppKit-private view in this
    /// tree is matched by).
    ///
    /// **The container's own `bounds.width` is not this title's width —
    /// it is flexible, and grows into whatever room a fold frees, the same
    /// way `NSSearchToolbarItem` grows an idle field (`searchRoomBudget(_:)`'s
    /// own header).** Read at one pane, tabs full versus tabs folded, with
    /// nothing else on the bar changed (`swift test --filter
    /// AnUnfoldIsPredictedNeverTrialledTests` on this Mac,
    /// `testTheWindowTitleStyleUnfoldsWithinMarginOfAppKitsOwnThreshold`):
    /// `NSToolbarTitleView.frame.width` was 183.5 pt with the tabs full and
    /// 270.5 pt with the tabs folded — the container absorbed the room the
    /// fold freed, 87 pt of it, while `fittingSize.width` read 98 pt in
    /// *both* states, unmoved. Anchoring on the grown edge (as this method
    /// used to) made `currentToolbarSlack(_:)` read the width of whatever the
    /// fold had just handed the title, not the width the title itself needs —
    /// every fold made the next reading under-count the room by exactly its
    /// own growth, which is a fold that never lets a later prediction see
    /// enough slack to undo it: swept 609→603→609 pt (Homebrew, Russian,
    /// this Mac, before this fix) the tabs folded at 609 and did not unfold
    /// again on the way back up through the same width. `fittingSize.width`
    /// is what stays put across that growth, so the maxX below is the
    /// container's leading edge (also unmoved by the same growth — the
    /// container grows on its trailing side) plus `fittingSize.width`, never
    /// its current, possibly-inflated frame.
    ///
    /// `nil` when the toolbar has no window yet, or a future AppKit
    /// restructures the title bar and the walk finds nothing —
    /// `currentToolbarSlack(_:)` reads that exactly the way it already reads
    /// a missing name item: as no anchor to predict from, never as a title
    /// of zero width.
    ///
    /// **`rawMaxX` is the container's own *actual*, current trailing edge**
    /// — `minX + bounds.width`, the reading this method used before this
    /// header's own fix. Returned alongside `maxX` so `currentToolbarSlack(_:)`
    /// can tell how much of the container's current frame is not yet given
    /// back, against a *resting* reading of the same quantity it memoises
    /// itself (`PageBar.restingRawTitleMaxX`) — `bounds.width` alone is not
    /// that amount, since a title container can sit wider than its fitting
    /// size while resting too (a wide, ordinary window with tabs already at
    /// full width leaves it room it takes without anything having folded),
    /// and crediting that ordinary, already-resting width as "not yet given
    /// back" is exactly as wrong in the other direction.
    ///
    /// **`fittingWidth` is `titleView.fittingSize.width` on its own** —
    /// `maxX`'s own edge, minus `minX`, kept as a separate member because
    /// `currentToolbarSlack(_:)`'s floor charge (`PageBar.titleOpenFloorCharge`)
    /// needs exactly this number and nothing else out of this reading.
    private func windowTitleMaxX(_ window: NSWindow) -> (maxX: CGFloat, rawMaxX: CGFloat, fittingWidth: CGFloat)? {
        guard let content = window.contentView, let frame = content.superview else { return nil }
        func find(_ view: NSView) -> NSView? {
            if "\(type(of: view))" == "NSToolbarTitleView" { return view }
            for sub in view.subviews {
                if let hit = find(sub) { return hit }
            }
            return nil
        }
        guard let titleView = find(frame) else { return nil }
        let minX = titleView.convert(.zero, to: nil).x
        let fittingWidth = titleView.fittingSize.width
        let maxX = minX + fittingWidth
        let rawMaxX = minX + titleView.bounds.width
        guard maxX.isFinite, rawMaxX.isFinite else { return nil }
        return (maxX, rawMaxX, fittingWidth)
    }

    /// **AppKit's own currently free room around the tabs — the combined
    /// width of the two flexible spaces either side of them, read from where
    /// AppKit actually put the leading edge, the tabs and the actions items,
    /// not derived by subtracting item widths from `offeredRoom()`.** That
    /// subtraction undercounts by 32–42 pt against a real, live window
    /// (engineer, this Mac): the detail
    /// pane's own width and the toolbar's own width for its items are not the
    /// same number, and the gap is AppKit's own inter-item spacing, which no
    /// item's `frame.width` ever reports. A first attempt at this method read
    /// `tabsItem.view.superview.bounds.width` on the theory that the toolbar's
    /// item-hosting view would answer directly — measured wrong: that
    /// superview is a wrapper scoped to the one item, not a container shared
    /// by the whole bar, and it reported something close to the tabs item's
    /// own width, not the toolbar's, producing slack readings off by hundreds
    /// of points. `NSView.convert(_:to:)` with `to: nil` converts through
    /// every private wrapper view up to the window's own coordinate space
    /// regardless of what sits in between, which is what makes the leading
    /// edge, the tabs and the actions items' positions comparable at all
    /// without knowing that hierarchy by name.
    ///
    /// **The leading edge is the name item's own trailing edge under
    /// `.moduleName`, and the window's own drawn title under `.windowTitle`
    /// (`windowTitleMaxX(_:)`).** Before this pass, a page-bar style with no
    /// name item read `nil` unconditionally here and fell straight through to
    /// the `offeredRoom()` arithmetic below, which has no notion of the title
    /// AppKit was actually drawing in that same leading zone: against
    /// Homebrew's own real shape swept in half-point steps across AppKit's
    /// own eviction width under `.windowTitle` (Russian, this Mac), that
    /// fallback predicted room that was not there and unfolded straight back
    /// into an eviction at every step of the sweep
    /// (`testTheWindowTitleStyleNeverBlinksAcrossASweepAtAppKitsOwnEvictionWidth`,
    /// run before this fix: red on both "no eviction" and "no refusal
    /// recorded"). This header used to describe that fallback as "never
    /// observed to latch, only to answer slightly pessimistic" — true of
    /// every shape this file's tests had swept until then, and false of this
    /// one, because nobody had swept a `.windowTitle` page with a search
    /// field until then.
    ///
    /// **Two gates stand between this reading and an unfold, not one.** The
    /// first is structural: `nil` when there is no name item and no drawn
    /// title to anchor the first gap on, or no actions item at all (a shape
    /// with tabs and no actions, which none of Helm's own pages currently
    /// declare) — `predictedSlack(bar:tabsWidth:)`'s own fallback to the
    /// older, `offeredRoom()`-based arithmetic covers both, and `settle(_:)`
    /// never unfolds from that fallback any more: an unanchored reading may
    /// still fold (the safe direction — `checkOverflow()`'s own reactive net
    /// repairs a fold this method should have predicted and did not) but must
    /// never invent the room to unfold into. The second is `PageBar
    /// .titleGrowth`, set here whenever `windowTitleMaxX(_:)` finds a title:
    /// a `.windowTitle` container that has not yet given back a fold's own
    /// growth (that method's own header) makes this method's return value
    /// alone still too optimistic right at AppKit's own threshold — measured
    /// directly against this fixture, crediting that growth in full unfolded
    /// straight into an eviction of the actions item, every time, across a
    /// whole band of panes AppKit itself was already refusing to hold full
    /// tabs at. `settle(_:)`'s own worst-case check is what reads
    /// `titleGrowth` back out before trusting this reading that far.
    private func currentToolbarSlack(_ bar: PageBar) -> CGFloat? {
        guard let tabsView = bar.tabsItem?.view, let actionsView = bar.actionsItem?.view,
              let window = tabsView.window
        else { return nil }
        let leadingMaxX: CGFloat
        if let nameView = bar.nameItem?.view {
            leadingMaxX = nameView.convert(NSPoint(x: nameView.bounds.width, y: 0), to: nil).x
            bar.titleGrowth = 0
            bar.titleOpenFloorCharge = 0
        } else if let title = windowTitleMaxX(window) {
            leadingMaxX = title.maxX
            // **Charged every pass, independently of `tabsFolded`** — see
            // `SettingsToolbar.windowTitleOpenFloor`'s own header for the
            // reading behind it and `PageBar.titleOpenFloorCharge`'s for why
            // it is a different quantity from
            // `titleGrowth`, which only exists while a fold's own growth has
            // not been given back.
            bar.titleOpenFloorCharge = max(0, Self.windowTitleOpenFloor - title.fittingWidth)
            if bar.tabsFolded {
                // **Growth against the *last resting* edge, never against
                // `title.maxX` itself** — `title.maxX` is this bar's own
                // fitting-based prediction of where the edge will settle, so
                // measuring growth against it would count the very reclaim
                // this gate exists to discount as already banked. `nil` only
                // until the first resting reading this bar ever takes
                // (`PageBar.restingRawTitleMaxX`'s own header) — the same
                // "no signal yet" precedent `collapsedFieldWidth` sets, and
                // the same reason growth reads zero rather than guessing.
                let resting = bar.restingRawTitleMaxX ?? title.rawMaxX
                bar.titleGrowth = max(0, title.rawMaxX - resting)
            } else {
                bar.restingRawTitleMaxX = title.rawMaxX
                bar.titleGrowth = 0
            }
        } else {
            return nil
        }
        let tabsMinX = tabsView.convert(.zero, to: nil).x
        let tabsMaxX = tabsView.convert(NSPoint(x: tabsView.bounds.width, y: 0), to: nil).x
        let actionsMinX = actionsView.convert(.zero, to: nil).x
        let gapBefore = tabsMinX - leadingMaxX
        let gapAfter = actionsMinX - tabsMaxX
        guard gapBefore.isFinite, gapAfter.isFinite else { return nil }
        return gapBefore + gapAfter
    }

    /// **The predicted slack left for the two flexible spaces if the tabs
    /// took `tabsWidth`** — positive is room to spare, negative is eviction.
    ///
    /// Anchored on `currentToolbarSlack(_:)` — AppKit's own, currently
    /// correct reading — and adjusted by how much the tabs and the search
    /// field would each change from where they are *right now*, rather than
    /// computed as an absolute quantity from `offeredRoom()` and every
    /// sibling's width at once. That anchoring is what keeps a wrong decision
    /// from ever being permanent: `NSSearchToolbarItem` grows an idle, empty
    /// field into whatever room a fold frees, which shrinks the flexible
    /// spaces down toward AppKit's own per-gap minimum (measured ~8 pt on
    /// this Mac) — a live reading taken *after* that growth already reflects
    /// it, so subtracting the field's predicted budget from its own current,
    /// already-grown width (rather than from a fresh `offeredRoom()`
    /// arithmetic that has no notion of "current" at all) is what correctly
    /// predicts the field shrinking back the moment the tabs take the room
    /// back, instead of reading that growth as permanent demand.
    ///
    private func predictedSlack(bar: PageBar, tabsWidth: CGFloat) -> CGFloat {
        let searchBudget = searchRoomBudget(bar)
        if let slackNow = currentToolbarSlack(bar), let tabsView = bar.tabsItem?.view {
            let tabsLive = tabsView.frame.width
            // **A missing search item is zero live width and zero budget, not
            // a reason to leave the anchored reading altogether.** Requiring
            // `bar.searchItem` here used to send every search-less page
            // (Hosts, Leftovers) through the `offeredRoom()` fallback below,
            // which does not know AppKit's own inter-item spacing and
            // overcounts the real room by about 8 pt — that spacing itself,
            // which no item's frame ever reports — enough to clear
            // `unfoldMargin` where AppKit still evicts: predicting room
            // that is not there, unfolding, and being evicted straight back —
            // one unfold→evict→refold blink on the very shape that has no
            // search field to anchor against. `searchBudget` is already 0
            // with no search item (`searchRoomBudget(_:)`'s own guard), so
            // `searchBudget - searchLive` is `0 - 0` here and drops out.
            let searchLive = bar.searchItem?.searchField.frame.width ?? 0
            return slackNow - (tabsWidth - tabsLive) - (searchBudget - searchLive)
        }
        let nameWidth = bar.nameItem?.view?.frame.width ?? 0
        let actionsWidth = bar.actionsItem?.view?.frame.width ?? 0
        return offeredRoom() - (nameWidth + tabsWidth + actionsWidth + searchBudget)
    }

    /// **Hysteresis on the predicted slack, not on the room itself** — a
    /// resize or a search closing that lands the predicted slack near one
    /// number must not unfold and immediately re-fold on the next tick.
    /// These are a judgment call, not a measurement: `foldMargin` is zero,
    /// since a negative predicted slack is eviction by construction and a bar
    /// already folded costs nothing further to leave folded, so there is no
    /// reason to wait for a cushion below zero before folding. `unfoldMargin`
    /// is deliberately well above zero so that the few points of imprecision
    /// in an off-screen `fittingSize` reading or a sibling's own frame cannot
    /// by themselves cross it — an unfold attempted right at the edge is
    /// exactly the oscillation this whole mechanism replaces the old
    /// trial-and-error with.
    static let foldMargin: CGFloat = 0
    static let unfoldMargin: CGFloat = 16

    /// **The margin `settle(_:)` requires of the *worst case* — crediting
    /// none of `PageBar.titleGrowth` back — before it will unfold a
    /// `.windowTitle` bar.** `unfoldMargin` alone is not enough here: right
    /// at AppKit's own fold threshold, `predictedSlack(bar:tabsWidth:)`
    /// already counts the title container's currently-unreturned growth as
    /// reclaimed, and that growth does not visibly reverse in the same pass
    /// that hands the tabs item its full width back
    /// (`currentToolbarSlack(_:)`'s "Two gates" paragraph). Measured directly
    /// against this fixture (`swift test --filter
    /// AnUnfoldIsPredictedNeverTrialledTests`, this Mac, Russian, Homebrew's
    /// own three tabs): at the pane one AppKit fold-width below the real
    /// threshold, `predictedSlack` minus `titleGrowth` came to 19.5 pt and
    /// the tabs still could not actually hold full width there — an unfold
    /// attempted anyway evicted the actions item every single time; at 646
    /// pt, where an ordinary magnifier press/close cycle already worked, the
    /// same worst-case reading came to 38.0 pt. This sits between the two,
    /// a judgment call rather than a measurement the same way `unfoldMargin`
    /// itself is — `testTheWindowTitleStyleNeverBlinksAcrossASweepAtAppKitsOwnEvictionWidth`
    /// is what a change to this number has to keep passing.
    static let unfoldWorstCaseMargin: CGFloat = 24

    /// **The narrowest width AppKit was ever seen to hold `NSToolbarTitleView`
    /// at while an *opening* field left the full tabs their room, independent
    /// of what the title's own text needs.** Measured on a 2-pt grid, a fresh
    /// window per pane, first press (tester, this Mac, macOS 27.2): the
    /// container's own floor is **160.0 pt** — the first pane that still kept
    /// every item visible with the field open, one step wider than the last
    /// pane where AppKit evicted `helm.actions` rather than shrinking the
    /// container any further (Russian 812 -> 814, title 160.0; English
    /// 712 -> 714, title 161.0 — the same edge across "Homebrew"/"3" and "H"/"1", with and
    /// without a subtitle, light and dark, an opaque or a transparent title
    /// bar). AppKit squeezes a title already wider than this floor down
    /// toward it too, rather than evicting anything: a synthetic 272.5-pt
    /// title's own container held at 167–277 pt across English 720–830, and
    /// Russian's own Uninstaller title («Удаление приложений»/«Не активно»,
    /// 172.5 pt fitting) held at 167 pt from pane 652 — at 560–580 pt the same
    /// title's container sat at 160 pt while AppKit evicted the tabs and the
    /// actions regardless, a pane with too little room for anything, not a
    /// floor reading. The floor is a property of AppKit's own layout, not of
    /// what the title says or how wide it already needs to be.
    ///
    /// **`openFitsPrediction(_:searchItem:slack:anchored:)`'s own charge is
    /// `max(0, windowTitleOpenFloor - fittingWidth)`** — the gap between this
    /// floor and what `windowTitleMaxX(_:)` would otherwise credit as
    /// reclaimable, never more: a title whose own `fittingWidth` already sits
    /// above the floor (the long-title readings above) is charged nothing and
    /// stays uncredited for the difference, since `windowTitleMaxX(_:)`'s own
    /// reading already accounts for it and charging both would double count.
    ///
    /// **Set to 167, not the measured 160** — about 7 pt of headroom in the
    /// safe direction (folding a little more readily than the measured floor
    /// strictly requires) until this reading is repeated on macOS 26, which
    /// this Mac does not run. Nothing public exposes *why* AppKit holds the
    /// container here — its own `NSLayoutConstraint`s record only the
    /// resolved width already decided on, an `NSView-Encapsulated-Layout-Width`
    /// lock rather than a stated minimum — so this is a reading of this
    /// system rather than a value derived from a public API, and a different
    /// macOS version or a larger system text size could move it. A system
    /// whose true floor sits above roughly 166.5 pt would see this constant
    /// keep the tabs full and then lose them to an eviction anyway — the
    /// owner's own bug, in a band as wide as the excess — which is the
    /// direction this headroom exists to guard against; a long title, never
    /// credited past its own `fittingWidth`, gains nothing from this number
    /// moving either way. Not measured: macOS 26, a 1x display, accessibility
    /// display settings.
    static let windowTitleOpenFloor: CGFloat = 167

    /// **How long `settle(_:)` keeps refusing an unfold after a search
    /// interaction ends empty, before trusting the field's own frame to have
    /// stopped moving.** Against a bare `NSSearchToolbarItem` with nothing
    /// beside it (engineer, this Mac), `endSearchInteraction()` narrows the
    /// field to its magnifier over
    /// ~198–205 ms — but that bare figure is *not* what this wait has to
    /// outlast in Helm's real bar, and crediting it as such was itself a
    /// defect this comment used to repeat: **while the tabs are still
    /// folded, the field does not narrow toward its magnifier at all — it
    /// keeps the room the fold freed**, and it is settling into *that* wider
    /// rest, not shrinking to anything small, for as long as this wait runs.
    /// Read directly off this exact bar (engineer, this Mac, 646 pt,
    /// Russian): `controlTextDidEndEditing`
    /// fires with the field still at its wide, mid-edit frame (`width=240.0`
    /// at 1078.5 ms with the gate, 1063.9 ms without it), and the field's
    /// own `frameDidChangeNotification` (M2) keeps firing — each one
    /// re-arming `scheduleSettle(_:)` — until it stops moving at `162.5` pt
    /// some 50–62 ms later (1140.3 ms with the gate, 1114.4 ms without; the
    /// settle that follows ran at 1293.7 and 1264.2 ms):
    /// still folded, still far
    /// wider than a magnifier, but finally *stable*, which is the one
    /// property `predictedSlack(bar:tabsWidth:)`'s live-minus-live arithmetic
    /// actually needs from it. Deciding on an earlier, still-narrowing
    /// reading is what overstates the room a fold would free and is what
    /// asked AppKit to lay the tabs out full beside a field mid-shrink in the
    /// first place. 300 ms outlasts both the ~50–62 ms this bar's field
    /// takes to stop and the ~198–205 ms the bare item takes to narrow, with
    /// a margin for a real toolbar's own heavier layout. This is a
    /// backstop, not dead weight: every one of those frame-change
    /// notifications already re-arms `scheduleSettle(_:)` on its own, so an
    /// ordinary cycle's last notification typically lands past this deadline
    /// anyway — this only matters when this Mac's real toolbar takes longer
    /// to stop moving than that. A `var`, not a `let`, on `settleInterval`
    /// and `graceInterval`'s own precedent — so a test can shrink it rather
    /// than sleeping through the production value.
    static var searchCollapseWait: TimeInterval = 0.3

    /// **How soon after our own unfold an M3 net-fold counts as caused by
    /// it**, rather than by something unrelated (a resize, a sidebar drag)
    /// landing moments later by coincidence. Generous next to the ~18 ms the
    /// owner's own log showed between an unfold and the very net-fold that
    /// followed it (`grep "room=646.0" ~/Library/Logs/Helm/helm.log`, the
    /// owner's own machine) — `checkOverflow()` itself only ever runs one
    /// `DispatchQueue.main.async` hop after the KVO that schedules it.
    static let overflowAttributionWindow: TimeInterval = 1.0

    /// **What an M3 net-fold shortly after one of our own unfolds is keyed
    /// on**, so `settle(_:)` can refuse to repeat exactly the attempt AppKit
    /// just refused — `checkOverflow()`'s own second gate against the
    /// flicker, kept even when the wait above judges wrong: recorded there,
    /// read here. Equality, not a timeout: a context that recurs identically
    /// failed once for a real reason and is not owed a second try within the
    /// same search interaction, while any one of these four actually moving —
    /// the room, the field's own live width, the language, the switcher
    /// style — is what lets `settle(_:)` try again *before* that interaction
    /// ends, and each of those four is exactly what the fold could plausibly
    /// have been caused by. **This alone is not what bounds the refusal to
    /// one interaction** — at a room this narrow the field settles back to
    /// the identical collapsed width every time, so none of the four ever
    /// moves on its own: a build with only this equality gate and no explicit
    /// clearing ran four more press/close rounds at the owner's own 646 pt,
    /// Russian, after one forced eviction, and every one of them read `gate
    /// refused` and ended folded — only widening the pane and returning
    /// unstuck it, because that is the one thing that actually changed `room`
    /// (engineer, this Mac). What actually bounds it to one interaction is explicit:
    /// `searchFieldFrameChanged`'s own reading of the field's growth against
    /// `preferredWidthForSearchField` (its header says why this, and not a
    /// delegate call or a `settle(_:)` branch, is the reliable signal) clears
    /// `bar.refusedUnfold` the moment a *new* interaction opens, whatever
    /// state the tabs were left in by the last one, and `tookMagnifierPress`
    /// clears it earlier still on the path where the field was genuinely
    /// hidden beforehand, so a refusal never outlives the cycle that earned
    /// it — a build with the read half of this gate disabled
    /// (nothing here ever refuses, only records) recovered to four segments
    /// on every one of the same four rounds instead (engineer, this Mac),
    /// which is the outcome the explicit clearing above restores without
    /// giving up the gate itself.
    ///
    /// `fileprivate`, not `private`: `PageBar` below is a sibling top-level
    /// type in this same file rather than an extension of this class, the
    /// same reason `NameSnapshot` and `HelmTabsSnapshot` above already state.
    fileprivate struct UnfoldRefusalKey: Equatable {
        let room: CGFloat
        let fieldWidth: CGFloat
        let language: AppLanguage
        let style: ToolbarSwitcherStyle
    }

    /// **What `settle(_:)` found the bar looking like the last time it
    /// finished measuring it** — see `PageBar.rest`'s own header for what
    /// each field means and who reads it. A named type, not a plain tuple,
    /// once a third field (`openFits`) joined `collapsed` and `room`: past
    /// two members a tuple reads as a positional pun rather than a record,
    /// which is the same reasoning `TabsWidthKey` and `NameSnapshot` above
    /// already give their own fields names for.
    fileprivate struct RestSnapshot {
        let collapsed: Bool
        let room: CGFloat
        let openFits: Bool
    }

    /// The context a fold or an unfold decision is actually being made
    /// against right now — room, language and style read fresh by both
    /// `settle(_:)`'s own gate and `checkOverflow()`'s own recording, since
    /// all three can move between the two (a resize, a language change).
    ///
    /// **`fieldWidth` is the one component `checkOverflow()` must not read
    /// fresh, and takes an override for exactly that reason.** A net fold
    /// (M3) reaches `checkOverflow()` through one KVO hop and one
    /// `DispatchQueue.main.async` hop after AppKit actually evicted
    /// something — by the time that runs, the field itself has already
    /// started shrinking back from the wide, freed-room width it held while
    /// still folded (measured, this Mac: `fieldW=162.5`
    /// at the unfold decision, `fieldW=43.0`–`44.0` one KVO hop later at the
    /// fold `checkOverflow()` reacts to, then `166.5` and back to `162.5`
    /// again once the field re-settles into the room the re-fold just freed
    /// a second time) — a fresh read here would record a
    /// value no future `settle(_:)` call, which always runs while the field
    /// has already settled one way or the other, could ever match again,
    /// which is what let `checkOverflow()` record a refusal that never once
    /// refused (`AnUnfoldIsPredictedNeverTrialledTests`'s own build report
    /// for this fix). `checkOverflow()` passes the width `settle(_:)` itself
    /// read at the very moment it decided to unfold
    /// (`PageBar.pendingUnfoldFieldWidth`) instead, which is exactly the
    /// steady, settled width a later `settle(_:)` call — folded again, room
    /// unchanged — reads back.
    private func unfoldContext(_ bar: PageBar, fieldWidth: CGFloat? = nil) -> UnfoldRefusalKey {
        UnfoldRefusalKey(room: offeredRoom(),
                         fieldWidth: fieldWidth ?? bar.searchItem?.searchField.frame.width ?? 0,
                         language: AppLanguage.current, style: AppSettings.toolbarSwitcherStyle)
    }

    /// Test-only counters for the two gates below — read only by
    /// `AnUnfoldIsPredictedNeverTrialledTests`, the same widened-for-testing
    /// precedent `tookMagnifierPress` and `settleInterval` already set in
    /// this file. `gateUnfoldFieldWidths` is the search field's own live
    /// width at the exact moment `settle(_:)` decided to unfold, one entry
    /// per unfold — what a test can check it against is the field's width
    /// while search was still open, since at a pane with slack to spare the
    /// field need not have narrowed *at all* for the unfold to be correct
    /// (measured: equal, not less, at 760/860 pt) — the invariant is *never
    /// wider*, not *always narrower*. Bounded at `gateUnfoldFieldWidthsLimit`
    /// (`CLAUDE.md`'s own rule against a record that grows for the life of
    /// the app) rather than unbounded — this array ships in every build, not
    /// only the test target, since it is only ever *read* by a test; a test
    /// run exercises at most a handful of unfolds per case, so the cap never
    /// binds there.
    private(set) var gateWaitedCount = 0
    private(set) var gateRefusedCount = 0
    private static let gateUnfoldFieldWidthsLimit = 32
    private(set) var gateUnfoldFieldWidths: [CGFloat] = []
    private func recordGateUnfoldFieldWidth(_ width: CGFloat) {
        gateUnfoldFieldWidths.append(width)
        if gateUnfoldFieldWidths.count > Self.gateUnfoldFieldWidthsLimit {
            gateUnfoldFieldWidths.removeFirst(gateUnfoldFieldWidths.count - Self.gateUnfoldFieldWidthsLimit)
        }
    }
    /// Incremented in `checkOverflow()` whenever it attributes its own fold
    /// to a recent unfold and records an `UnfoldRefusalKey` — proves the
    /// recording half of the second gate ran, independently of whether a
    /// later `settle(_:)` call ever finds a matching context to refuse.
    private(set) var gateRefusalsRecorded = 0
    /// **The field-width component of the last `UnfoldRefusalKey`
    /// `checkOverflow()` recorded** — separate from `gateRefusalsRecorded`'s
    /// count so a test can check *what* got recorded and not only *that*
    /// something did: it must equal the width `settle(_:)` itself read at
    /// the matching unfold decision (the last entry of
    /// `gateUnfoldFieldWidths`), never a width read fresh at attribution time
    /// (`unfoldContext(_:fieldWidth:)`'s own header for why the two differ —
    /// this is exactly the check that catches a regression back to a fresh
    /// read, which every other assertion here already passed).
    private(set) var lastRefusedUnfoldFieldWidth: CGFloat?
    /// **`settle(_:)`'s own last computed "open slack"** — the predicted
    /// slack if the tabs stayed full beside an *open* search field, for
    /// whichever bar `settle(_:)` last examined with both a search item and
    /// tabs; what `openFitsPrediction(_:searchItem:slack:anchored:)`'s own
    /// `unfoldMargin` comparison reads, exposed here only for a test to record the same number rather
    /// than re-deriving it. `nil` before the first such pass, and left at its
    /// last value on a pass with no search item or no tabs to have one.
    private(set) var lastOpenSlack: CGFloat?

    /// **The one place that decides whether the tabs should be full or
    /// compact, and the one place that records `PageBar.rest`.** Runs only on
    /// the bar that is still attached by the time it fires, and never while
    /// the search field is mid-edit — reopening a field somebody is typing
    /// into is `patchSearch`'s own rule, restated here for the same reason. A
    /// field left with text after editing ends stays wide; the prediction
    /// below is what decides whether the full tabs still fit beside that
    /// width, so nothing here has to special-case a non-empty field.
    ///
    /// **No trial against the live bar any more.** `switcherWidth(tabs:style:
    /// selectedID:)` and `predictedSlack(bar:tabsWidth:)` answer from an
    /// off-screen switcher and the bar's own siblings, so the decision below
    /// either unfolds once, correctly, or does not unfold at all — never
    /// unfolds and watches AppKit refuse it.
    ///
    /// **Four gates in front of the unfold itself, on top of that
    /// prediction.** Anchoring is the first, and structural rather than
    /// timed: `currentToolbarSlack(_:)` returning `nil` means there is
    /// nothing under either page-bar style to predict a real layout from,
    /// and `slack` in that case is `predictedSlack(bar:tabsWidth:)`'s own
    /// `offeredRoom()` fallback, which must never be read as room to unfold
    /// into (`currentToolbarSlack(_:)`'s own header has the swept eviction
    /// this refusal exists to stop) — it may still leave a fold below in
    /// place, the safe direction, since `checkOverflow()`'s reactive net
    /// repairs a fold this prediction should have made and did not.
    /// `PageBar.searchClosingDeadline` (`controlTextDidEndEditing`'s own
    /// header) is the second: a search that just ended empty starts an
    /// independent AppKit collapse animation this prediction cannot see the
    /// end of, so an unfold decided before the deadline passes is deferred
    /// rather than acted on — `scheduleSettle(_:)` is re-armed by every one
    /// of the field's own frame changes (M2), so the very next tick after the
    /// field actually catches up tries again. `UnfoldRefusalKey` is the
    /// third, and the one that holds even if the second judges wrong: a room
    /// this exact field width has evicted the tabs from once already is not
    /// retried until the room, the field's width, the language or the
    /// switcher style has actually moved — see `checkOverflow()` for where
    /// that gets recorded. `worstCaseOK` is the fourth, specific to
    /// `.windowTitle`: `currentToolbarSlack(_:)`'s own "Two gates" paragraph
    /// has why `slack` alone still over-credits a title container's
    /// not-yet-reversed growth right at AppKit's own threshold, and
    /// `SettingsToolbar.unfoldWorstCaseMargin`'s own header has what was
    /// measured discounting it in full. Together the four are what keep a
    /// wrong decision to at most one visible blink rather than a repeating
    /// flicker.
    ///
    /// **The verdict `openingKeepsTheTabs(_:)` later reads back, computed
    /// once per `settle(_:)` pass from the same `slack` and `anchored` the
    /// unfold decision above already has** — not a second, independent
    /// measurement: it reuses the `slack` and `anchored` this pass already
    /// computed rather than calling `predictedSlack(bar:tabsWidth:)` or
    /// `currentToolbarSlack(_:)` again. Charges the same `slack` once more for the
    /// difference between the field's current, resting occupancy and the
    /// width it would claim open. `occupied` reads the field's own frame
    /// rather than `searchRoomBudget(_:)`'s cached `collapsedFieldWidth`
    /// because at rest, with the cap active, the two already agree
    /// (`searchRoomBudget(_:)`'s own header) — so a direct read needs no
    /// dependency on which branch that method took. **`bar.titleOpenFloorCharge`
    /// is subtracted from `openSlack` itself, before either margin
    /// compares against it** — under `.windowTitle`, a growing field does not
    /// let the title container shrink all the way to its own `fittingWidth`
    /// (`SettingsToolbar.windowTitleOpenFloor`'s own header has the reading);
    /// `slack` alone credits that unreachable room as available the same way
    /// it over-credited a fold's own not-yet-reversed growth before
    /// `titleGrowth` existed, and this is the same fix for a different
    /// trigger — a search opening rather than a fold. `false` whenever there
    /// is nothing for this predicate to decide: no search item, the cap
    /// inactive, or a field AppKit itself has already opened — the
    /// unconditional fold in `tookMagnifierPress` and `searchFieldFrameChanged`
    /// already covers both of those. `unfoldWorstCaseMargin`, not
    /// `unfoldMargin` alone, for the same `.windowTitle` reason `worstCaseOK`
    /// above needs it: keeping the tabs full is an unfold-grade bet either
    /// way.
    ///
    /// **Carries no memory of a past wrong bet.** A verdict this predicate
    /// gets wrong is not permanent: `checkOverflow()` (M3) reacts to the
    /// eviction AppKit itself reports and folds the tabs back regardless of
    /// what this predicate answered, and the next opening asks fresh rather
    /// than reading anything remembered from the one before. The one case
    /// this predicate used to get systematically wrong — a `.windowTitle`
    /// container not yet giving back the room `windowTitleOpenFloor` claims
    /// it can reach — is exactly what `bar.titleOpenFloorCharge`, subtracted
    /// above, now corrects before either margin ever compares against it.
    private func openFitsPrediction(_ bar: PageBar, searchItem: NSSearchToolbarItem?,
                                    slack: CGFloat, anchored: Bool) -> Bool {
        guard let field = searchItem?.searchField else { return false }
        let occupied = min(field.frame.width, field.superview?.frame.width ?? field.frame.width)
        let openSlack = slack - ((searchItem?.preferredWidthForSearchField ?? 0) - occupied)
            - bar.titleOpenFloorCharge
        lastOpenSlack = openSlack
        return bar.searchRestCap?.isActive == true && field.isHidden && anchored
            && openSlack >= Self.unfoldMargin
            && (bar.titleGrowth <= 0 || openSlack - bar.titleGrowth >= Self.unfoldWorstCaseMargin)
    }

    private func settle(_ bar: PageBar) {
        guard let key = attachedPageKey,
              key == Self.nameOnlyKey ? bar === nameOnlyBar : pageBars[key] === bar
        else { return }
        // **A search item is not a precondition for the tabs prediction
        // below — only for the search-specific gates in front of it.**
        // Before this pass, a page whose shape carried tabs but no search
        // (Hosts, Leftovers) returned above before the tabs were ever
        // judged, so `checkOverflow()`'s own fold-only KVO net was the one
        // and only way this bar's tabs ever moved — reachable, once a
        // longer tab title, a third tab or another action ever made this
        // page's tabs overflow at all, the tabs would fold on the first
        // eviction and never unfold again for the rest of the session,
        // however wide the window then grew. `searchItem` is `nil` exactly
        // when the page declares no search field at all (or before the
        // toolbar has asked for the item on a page that does) — it is never
        // cleared once assigned (`makeSearchItem`'s own single `bar
        // .searchItem = item`), so the search-specific gates below simply do
        // not apply to a bar that has no field to be mid-edit or mid-open.
        let searchItem = bar.searchItem
        if let searchItem {
            guard searchItem.searchField.currentEditor() == nil else { return }
            // **A search still opening is not yet settled**, even in the gap
            // before AppKit's own field editor arrives — see `PageBar
            // .searchOpening`'s own header for why the editor guard above is
            // not enough by itself.
            guard !bar.searchOpening else { return }
        }

        // **Whether the full tabs would still fit beside an *open* search
        // field, for a field the rest cap alone is resting as a magnifier** —
        // read back by M1 and M2 through `openingKeepsTheTabs(_:)`, which
        // never measures anything itself; see that method's own header for
        // why the decision belongs here rather than live inside either
        // opener. `false` whenever this bar has no tabs or no search item —
        // set below only inside the block that has both.
        var openFits = false
        if let content = bar.content, !content.tabs.isEmpty {
            // Measured once per `TabsWidthKey` — see its header for why a
            // settle after every keystroke must not measure tabs a keystroke
            // cannot move, and for what makes a key miss.
            let key = TabsWidthKey(tabs: content.tabs, style: AppSettings.toolbarSwitcherStyle,
                                   language: AppLanguage.current, selectedID: content.selectedTab?.wrappedValue)
            let full: CGFloat
            if let measured = bar.tabsWidth, measured.key == key {
                full = measured.full
            } else {
                full = switcherWidth(tabs: content.tabs, style: key.style, selectedID: key.selectedID)
                bar.tabsWidth = (key, full)
            }
            let slack = predictedSlack(bar: bar, tabsWidth: full)
            // **Never unfold from an unanchored prediction** — see this
            // method's own header, "Four gates," for why a `nil` here must
            // still be free to fold on the branch below.
            let anchored = currentToolbarSlack(bar) != nil
            // **Never unfold on the strength of a `.windowTitle` container's
            // own, not-yet-returned growth alone** — `bar.titleGrowth`, just
            // populated by the `currentToolbarSlack(_:)` call above, is zero
            // under `.moduleName` and whenever the container has already
            // settled, so this is a no-op there; `SettingsToolbar
            // .unfoldWorstCaseMargin`'s own header has the measured pane
            // where crediting the growth in full unfolded straight into an
            // eviction.
            let worstCaseOK = bar.titleGrowth <= 0 || (slack - bar.titleGrowth) >= Self.unfoldWorstCaseMargin
            openFits = openFitsPrediction(bar, searchItem: searchItem, slack: slack, anchored: anchored)
            if bar.tabsFolded, slack >= Self.unfoldMargin, worstCaseOK, anchored {
                if let deadline = bar.searchClosingDeadline, Date() < deadline {
                    gateWaitedCount += 1
                    // Retried explicitly rather than left to the field's own
                    // frame-change notifications (M2): a field that has
                    // already reached the width `searchRoomBudget(_:)` is
                    // crediting it as, without one further frame change to
                    // report, would otherwise never get a second look before
                    // this deadline passes, and the tabs would stay folded
                    // for the rest of the session.
                    scheduleSettle(bar)
                } else {
                    bar.searchClosingDeadline = nil
                    // `nil` with no search item at all — `unfoldContext(_:
                    // fieldWidth:)` and `recordGateUnfoldFieldWidth` both
                    // already read that as "no field to have a width",
                    // consistently across every call on this bar, since
                    // there is nothing here for AppKit to ever grow or
                    // shrink.
                    let fieldWidth = searchItem?.searchField.frame.width
                    let context = unfoldContext(bar, fieldWidth: fieldWidth)
                    if bar.refusedUnfold == context {
                        gateRefusedCount += 1
                    } else {
                        if let fieldWidth { recordGateUnfoldFieldWidth(fieldWidth) }
                        setTabsFolded(false, bar: bar, layout: .window)
                        bar.lastOurUnfoldAt = Date()
                        // **What `checkOverflow()` promotes into a refusal if
                        // AppKit evicts this very unfold** — not re-read
                        // there, where the field is already mid-shrink one
                        // hop later (`unfoldContext(_:fieldWidth:)`'s own
                        // header). Set beside `lastOurUnfoldAt` since both are
                        // read together, on the attribution condition below.
                        bar.pendingUnfoldFieldWidth = fieldWidth
                        // **`openFits`, just computed above, was measured
                        // with the tabs still folded — a `.windowTitle`
                        // container does not give a fold's own growth back in
                        // the same pass that hands the tabs their room
                        // (`currentToolbarSlack(_:)`'s "Two gates"
                        // paragraph), so `bar.titleGrowth > 0` here means this
                        // verdict is stale the instant this unfold runs, not
                        // a fresh reading of the bar this unfold just made.**
                        // `false`, the safe direction, until the settle this
                        // re-arms reads the container actually resting at its
                        // new, unfolded width — calling `currentToolbarSlack(_:)`
                        // again in this same pass is deliberately not done
                        // instead: the container has not moved yet, so
                        // another call here would only rewrite
                        // `restingRawTitleMaxX` from a still-inflated frame.
                        // **Scoped to the cap being active** — `openFits` only
                        // ever feeds `openingKeepsTheTabs(_:)`, which answers
                        // false outright whenever the cap is inactive, so with
                        // the option off this stale verdict is already inert;
                        // re-arming `scheduleSettle(bar)` regardless would,
                        // with the option off, spend a settle pass nobody
                        // asked for wherever the unfold leaves the search
                        // field where it was (en 1060 measured; where the
                        // field moves, M2's own re-arm lands at the same
                        // moment and the two merge) — not this gate's
                        // business to spend.
                        if bar.titleGrowth > 0, bar.searchRestCap?.isActive == true {
                            openFits = false
                            scheduleSettle(bar)
                        }
                    }
                }
            } else if !bar.tabsFolded, slack < Self.foldMargin {
                setTabsFolded(true, bar: bar, layout: .window, reseat: !(bar.tabsItem?.isVisible ?? true))
            }
        }
        bar.rest = RestSnapshot(collapsed: searchItem?.searchField.isHidden ?? true, room: offeredRoom(),
                               openFits: openFits)
    }

    /// **M2: the search field's own frame.** Set up in `makeSearchItem`,
    /// which turns on `postsFrameChangedNotifications` on the field it
    /// builds. Covers an opening that does not come from the mouse —
    /// keyboard, VoiceOver, or the field simply having more room at rest —
    /// which M1 cannot see because it only ever fires on a press.
    private func watchSearchFieldFrame(_ bar: PageBar, field: NSSearchField) {
        if let old = bar.fieldFrameWatch { NotificationCenter.default.removeObserver(old) }
        bar.lastFieldWidth = field.frame.width
        bar.fieldFrameWatch = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: field, queue: nil) { [weak self, weak bar] _ in
            MainActor.assumeIsolated {
                guard let self, let bar else { return }
                self.searchFieldFrameChanged(bar: bar, field: field)
            }
        }
    }

    private func searchFieldFrameChanged(bar: PageBar, field: NSSearchField) {
        let width = field.frame.width
        defer { bar.lastFieldWidth = width }
        // **Reaching the field's own preferred, editing-focus width clears
        // whatever a *previous* interaction was refused for.** Two other
        // signals were tried and rejected first: `NSSearchFieldDelegate`'s
        // own `controlTextDidBeginEditing` is never once invoked for this
        // control — instrumented to log every call, including the one M1
        // itself drives by calling `beginSearchInteraction()`, across
        // several full press-close cycles (engineer, this Mac) — and
        // clearing from inside `settle(_:)` on `currentEditor() != nil`
        // loses a real race instead of never firing: M2 only re-arms
        // `scheduleSettle(_:)` while `field.currentEditor() == nil` (this
        // method's own tail, below), so the one settle tick that could still
        // observe a live edit is whichever `settleInterval` timer the *last*
        // such frame change armed, and whether the editor has attached by
        // the time that timer fires is exactly the race — this file's own
        // `testARefusalDoesNotOutliveTheInteractionThatEarnedIt` caught that
        // approach clearing the stale refusal on one run and missing it on
        // another, same pane, same language, nothing committed in between.
        // The field's own growth is not subject to either problem: it
        // reached its full `preferredWidthForSearchField` (240 pt on this
        // Mac, `NSSearchToolbarItem.h`'s own "used to configure the search
        // field width whenever it gets the keyboard focus") on every
        // press-driven opening this session, including the one where the
        // tabs were already stuck folded from a stale refusal and neither
        // `tookMagnifierPress` nor this method's own fold-and-open branch
        // below ever ran (both require `!bar.tabsFolded`, which is false in
        // exactly that case) — and the one other growth this field ever
        // makes, the auto-widen into a fold's own freed room
        // (`searchRoomBudget(_:)`'s own header), reached at most 166.5 pt
        // across every recorded eviction this session (engineer, this Mac),
        // which is what makes this threshold — not merely "the field grew" —
        // safe to fire unconditionally.
        if let searchItem = bar.searchItem, width > bar.lastFieldWidth,
           width >= searchItem.preferredWidthForSearchField {
            bar.refusedUnfold = nil
            bar.pendingUnfoldFieldWidth = nil
        }
        // **The room-equality check is what tells "the magnifier opened the
        // field" apart from "the window or sidebar widened and the field
        // re-opened at rest with more room already available"** — the same
        // growing frame either way, and the field's own first-responder
        // status arrives too late to serve (measured at ~200 ms after the
        // click, well past the frame that matters here). **With the cap
        // active, a room that has moved is `openingKeepsTheTabs(_:)`'s own
        // business, not a reason to skip this branch entirely** — that
        // predicate already folds on a room mismatch (its own `bar.rest?
        // .room == offeredRoom()` clause), the same "unanchored means fold"
        // rule `currentToolbarSlack(_:)` returning `nil` gives every other
        // prediction here; keeping the equality as a hard *gate* left a
        // keyboard or VoiceOver opening that lands between a resize and the
        // settle that follows it doing nothing at all — full tabs beside a
        // growing field at a room that has no verdict yet — until AppKit
        // itself evicted something and `checkOverflow()` cleaned up after
        // the fact. `|| bar.searchRestCap?.isActive == true` is scoped to
        // exactly that: with the cap off (this predicate's other caller,
        // `tookMagnifierPress`, never gated on room equality either), the
        // clause is unchanged, byte for byte — `roomKnown` below is the
        // original condition on its own.
        let roomKnown = offeredRoom() == bar.rest?.room
        // **Not while a just-ended interaction is still finishing.**
        // `controlTextDidEndEditing` clears `searchOpening` the moment editing
        // ends, but AppKit's own layout can still deliver one more *growing*
        // frame after that — measured for an empty close: 218.5 → 222.0 pt,
        // one frame past the close (engineer, this Mac); the same one-tick gap
        // exists for a close that leaves a query behind, since the field
        // editor's resignation and the layout pass it triggers do not land in
        // the same tick either way. With the tabs kept full that stray frame
        // reads as a brand new opening, re-arms `searchOpening` with no editor
        // behind it, and nothing but `controlTextDidEndEditing` ever clears it
        // again — an empty field is then stuck open and idle instead of
        // folding back to its magnifier, and a field left with a query, once
        // that query is cleared, never rests as the magnifier again, since
        // `restSearch(_:)` will not rest a field while `searchOpening` is
        // set. `bar.searchEditEndedDeadline`
        // is armed by that same method for exactly this window, whatever text
        // the close leaves — not `bar.searchClosingDeadline`, which
        // `settle(_:)`'s own wait gate reads for an unrelated reason (an empty
        // close's own shrink animation) and must not newly wait on a query
        // left wide.
        let closing = bar.searchEditEndedDeadline.map { Date() < $0 } ?? false
        //
        // **`!bar.searchOpening` keeps M2 from re-deciding an opening M1 has
        // kept the tabs full for.** Without it, M2 would re-ask
        // `openingKeepsTheTabs(_:)` on each growth frame of that opening; an
        // opening M1 folded is already kept out by `!bar.tabsFolded`. With
        // the option off this changes nothing: `setTabsFolded(false, ...)` is
        // called only from `settle(_:)`, which is blocked while
        // `searchOpening` is set, so on that path `!bar.tabsFolded` is
        // already false by the time this fires. The fold itself is the same
        // conditional M1 uses — `openingKeepsTheTabs(_:)` — for the field the
        // cap is holding at rest; a field AppKit itself collapsed keeps its
        // unconditional fold, since `openingKeepsTheTabs(_:)` answers false
        // whenever the cap is inactive.
        if width > bar.lastFieldWidth, !bar.tabsFolded, !bar.searchOpening, !closing,
           bar.rest?.collapsed == true, bar.content?.tabs.isEmpty == false,
           roomKnown || bar.searchRestCap?.isActive == true {
            // Same reason as M1's own fold-and-open branch above: a fresh
            // interaction starting through this path (keyboard, VoiceOver)
            // must not inherit a stale refusal either.
            bar.refusedUnfold = nil
            bar.pendingUnfoldFieldWidth = nil
            bar.searchOpening = true
            if !openingKeepsTheTabs(bar) {
                setTabsFolded(true, bar: bar, layout: .hostOnly)
            }
        }
        // **The field narrowing is itself news for `settle(_:)`'s own
        // prediction** — `searchRoomBudget(_:)` reads the field's current
        // frame while it is not opening, so a field that has just shrunk
        // (a fold-back that only ends the interaction, leaving less budget
        // claimed) can newly leave slack for an unfold that a moment ago
        // there was none for; the *prediction* needs nothing cleared here,
        // it reads this frame fresh — `bar.refusedUnfold`
        // (`checkOverflow()`'s own header) is a different, coarser refusal
        // and clears itself the same way, by comparison rather than by a
        // call from here: this frame changing is one of the four things
        // that comparison is keyed on.
        if field.currentEditor() == nil {
            scheduleSettle(bar)
        }
    }

    /// **M3: the overflow net** — catches a fold AppKit's own layout forced
    /// (narrowing the window or the sidebar) that neither a mouse press nor
    /// the search field's own frame ever announced. `isVisible` is
    /// KVO-observable on any `NSToolbarItem` (`NSToolbarItem.h:169-172`) and
    /// flips several times in one animated relayout — `checkOverflow` below
    /// is the coalesced, one-per-relayout reaction; this only schedules it.
    private func scheduleOverflowCheck() {
        guard !pendingOverflowCheck else { return }
        pendingOverflowCheck = true
        DispatchQueue.main.async { [weak self] in self?.checkOverflow() }
    }

    /// A *reading*, re-read here rather than trusted from whichever
    /// `isVisible` flip scheduled this hop (`CLAUDE.md`'s own rule for a
    /// value crossing a `DispatchQueue.main.async` boundary).
    ///
    /// **Last-resort only — a real eviction the prediction missed** (a
    /// language, label-style or sidebar change `refreshAndResettle()` did not
    /// catch in time, or an unfold `settle(_:)`'s own wait gate let through
    /// too early). This never unfolds, only folds in reaction to AppKit
    /// having already evicted something; the next unfold for this bar still
    /// goes through `settle(_:)`'s own prediction — **except** when this
    /// fold lands shortly after one `settle(_:)` itself just issued
    /// (`PageBar.lastOurUnfoldAt`, `Self.overflowAttributionWindow`), which
    /// is recorded as an `UnfoldRefusalKey` so that one exact context is not
    /// retried until it has actually changed — see `settle(_:)`'s own
    /// header for the read side of both gates.
    private func checkOverflow() {
        pendingOverflowCheck = false
        guard let key = attachedPageKey, key != Self.nameOnlyKey, let bar = pageBars[key],
              !bar.tabsFolded, bar.content?.tabs.isEmpty == false
        else { return }
        // **Not yet laid out is not evicted.** During a bar's very first
        // attachment AppKit inserts its items one at a time, and a watched
        // item's `isVisible` starts `false` until that insertion finishes —
        // this net's own KVO can fire on that transient, with the tabs
        // item's view still at zero width, and reading it as a real overflow
        // folds the tabs before they have ever had a real width to judge at
        // all. That spurious fold is not cosmetic: the search field then
        // auto-expands into the room it freed before `settle(_:)`'s own
        // prediction has ever seen the field collapsed, so
        // `searchRoomBudget(_:)` never captures a `collapsedFieldWidth` to
        // fall back on and the fold reads as permanent (measured: exactly
        // this sequence, at a real pane and real Russian labels where full
        // tabs do fit, in `AnUnfoldIsPredictedNeverTrialledTests`).
        guard let tabsWidth = bar.tabsItem?.view?.frame.width, tabsWidth > 0 else { return }
        guard !watchedItemsAllVisible(bar) else { return }
        // **Attribute this fold to our own recent unfold, if it is one** —
        // before the fold itself, using the room, the language and the
        // switcher style *as they stand right now* (all three are read fresh
        // and correctly reflect whatever AppKit is actually refusing), but
        // `bar.pendingUnfoldFieldWidth` rather than a fresh field read for
        // the field's own width — see `unfoldContext(_:fieldWidth:)`'s own
        // header for why a fresh read here recorded a value no later
        // `settle(_:)` call could ever match, which is what let this
        // recording run on every single fold without the comparison in
        // `settle(_:)` ever once matching it back
        // (`AnUnfoldIsPredictedNeverTrialledTests`'s own build report).
        // `settle(_:)` reads this back and does not attempt the identical
        // context again until one of the four has moved.
        if let unfoldedAt = bar.lastOurUnfoldAt,
           Date().timeIntervalSince(unfoldedAt) < Self.overflowAttributionWindow {
            bar.refusedUnfold = unfoldContext(bar, fieldWidth: bar.pendingUnfoldFieldWidth)
            gateRefusalsRecorded += 1
            lastRefusedUnfoldFieldWidth = bar.refusedUnfold?.fieldWidth
        }
        setTabsFolded(true, bar: bar, layout: .window, reseat: !(bar.tabsItem?.isVisible ?? true))
    }

    /// **Replaces the KVO net for whichever bar is now attached.** Called
    /// only when `show(_:key:)` actually changes which bar is on
    /// screen — a bar that stays attached across a republish keeps watching
    /// the same three items it already was.
    private func watchOverflow(_ bar: PageBar) {
        visibilityWatch = watchedItems(bar).map { item in
            item.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scheduleOverflowCheck() }
            }
        }
    }

    // MARK: - The action capsule

    /// **What pressing a `.button` or a `.toggle` action actually runs** —
    /// the one place either kind's closure is unwrapped, shared between
    /// `model.press` (a capsule press) and `actionMenuItemPressed` (the
    /// overflow menu's own). A `.menu` action has no press of its own: each
    /// item inside it presses through `pressItem` / `actionMenuSubitemPressed`
    /// instead, so this silently does nothing for one — the caller already
    /// has no route to reach here for a menu's own top-level press.
    private static func perform(_ action: HelmToolbarAction) {
        switch action.kind {
        case .button(let perform): perform()
        case .toggle(_, let perform): perform()
        case .menu, .segmented: break
        }
    }

    /// **The two identical `Entry` mappings this file used to carry, become
    /// one.** `HelmToolbarAction.Kind`'s closures never survive into
    /// `HelmToolbarActionsModel.EntryKind` — see `Entry`'s own header for why.
    private static func actionEntries(for content: HelmPageToolbarContent) -> [HelmToolbarActionsModel.Entry] {
        content.actions.map { action in
            let kind: HelmToolbarActionsModel.EntryKind
            switch action.kind {
            case .button:
                kind = .button
            case .toggle(let isOn, _):
                kind = .toggle(isOn: isOn)
            case .menu(let items):
                kind = .menu(items.map {
                    HelmToolbarActionsModel.MenuEntry(id: $0.id, title: $0.title,
                                                      isOn: $0.isOn, isEnabled: $0.isEnabled)
                })
            case .segmented(let options, let selection):
                kind = .segmented(options.map {
                    HelmToolbarActionsModel.SegmentEntry(id: $0.id, title: $0.title, symbol: $0.symbol)
                }, selectedID: selection.wrappedValue, reserveWidth: segmentedReserveWidth(options))
            }
            return HelmToolbarActionsModel.Entry(id: action.id, title: action.title, symbol: action.symbol,
                                                 isEnabled: action.isEnabled, isBusy: action.isBusy, kind: kind)
        }
    }

    /// **Every `.segmented` reserve this app has ever measured, keyed on the
    /// options' own glyphs, in order — never re-measured for the life of the
    /// app.** `actionEntries(for:)` calls `segmentedReserveWidth(_:)` on
    /// every declare, and Hosts republishes its whole toolbar on every
    /// keystroke in the SSH editor (`HostsViewModel.setSSHText(_:)`); without
    /// this cache, that mounts `SwitcherMeasurementRig` — a fresh hosting
    /// view, a fresh toolbar and a full layout — once per character. Before
    /// this cache existed, `AKeystrokeInHostsMountsNoMeasuringSwitcherTests`
    /// counted one mount per keystroke, 20 of 20, and 100 declares of one
    /// unchanged `.segmented` entry took 1828–1990 ms against 1.7 ms for the
    /// same declares with no `.segmented` entry in them (tester, 2026-09-25,
    /// debug build); with this cache's read taken back out (2026-09-26) it
    /// counted 10 measurements for 10 keystrokes, and measured no time.
    /// **The key is the ordered `symbol` array and nothing else**,
    /// because `HelmToolbarActionsCapsule.entryContent(_:)` fixes a
    /// `.segmented` entry's style to `.icons` unconditionally
    /// (`ASegmentedActionIsAlwaysGlyphsTests`) — no title, no `id`, no
    /// selection and no ambient label style ever reaches what is drawn, only
    /// each option's own SF Symbol name feeds its image, and the array's own
    /// length already says how many segments there are. A key built from the
    /// titles instead would be wrong exactly because titles *are*
    /// translated — a language change would then read as a new key and
    /// remeasure for nothing, which is the churn this cache exists to
    /// remove. Not bounded the way `Sources/HelmRuntime/LogTail.swift` or
    /// `Sources/Modules/Autopilot/Engine/Logic/ActionHistory.swift` cap a
    /// record that grows for the life of the app, because nothing a person
    /// does adds a key: a key is a `.segmented` declaration's own glyphs, and
    /// a page that spells its options out as a literal
    /// (`command grep -rn 'options: \[$' Sources/Modules` lists those) fixes
    /// them at compile time. A page that built its options from data would
    /// grow this table with that data, and would need the cap.
    private static var segmentedReserveCache: [[String]: CGFloat] = [:]

    /// **The margin a one-option entry's reserve needs on top of what the rig
    /// measures alone, because the rig is not the capsule.** `SwitcherMeasurementRig`
    /// mounts the switcher by itself, the one item in its own toolbar; the
    /// capsule mounts it beside every other declared action inside one
    /// `GlassEffectContainer`, and a segmented control with a single segment
    /// does not draw there at the width the rig alone reads for it —
    /// `AOneOptionSegmentedEntrysReserveCoversItTests` measured the gap on
    /// this Mac at 3.0 pt for `keyboard`, 3.0 pt for `rectangle.3.group` and
    /// 2.5 pt for `tablecells`, against a rig reading of 36.0–39.0 pt. Two
    /// options or more do not show this gap
    /// (`ASegmentedEntrysReserveIsWhatItDrawsTests`,
    /// `ASegmentedEntrysReserveCoversItsOwnGlyphsTests` hold that case to the
    /// point already), so the margin is added only when `options.count == 1`,
    /// and it is the ceiling of what was measured rather than the exact
    /// figure. A wider sweep of 22 glyphs (same test file) found the rig
    /// never reading below a 36.0 pt floor, while the capsule attached draws
    /// anywhere from 35.0 to 39.0 pt at that floor — so a narrow glyph such
    /// as `minus` or `circle` reserves 39.0 pt over the 35.0 pt it actually
    /// draws, a 4.0 pt margin rather than the few tenths the first three
    /// glyphs alone showed. Over-reserving costs nothing the capsule's own
    /// fixed-reserve mechanism does not already spend; under-reserving it is
    /// the resize this whole entry exists to prevent. `HelmToolbarAction`'s
    /// own segmented initialiser accepts any count, so a one-option entry is
    /// an input the API leaves open; which pages declare how many options is
    /// read at the declarations `command grep -rn 'options: \[$' Sources/Modules`
    /// lists, not written here, and the guard this margin answers for stays
    /// in the tree whatever they say.
    private static let oneOptionCapsuleMargin: CGFloat = 3

    /// **A `.segmented` entry's own reserve — measured attached, through
    /// `SwitcherMeasurementRig`, the same rig `switcherWidth(tabs:style:selectedID:)`
    /// above already uses for the centre tabs' fold prediction, cached in
    /// `segmentedReserveCache` and never read as a fraction of a point.**
    /// Attached for the reason the rig's own header gives for the tabs — a
    /// bare hosting view's `fittingSize` is not what a toolbar item draws —
    /// and per glyph set, because each of four pairs reserves what it draws,
    /// 73.0–85.0 pt across the set, rather than one number standing in for
    /// all of them (`ASegmentedEntrysReserveCoversItsOwnGlyphsTests`).
    /// Measured non-compact and in `.icons` — the one form
    /// `HelmToolbarActionsCapsule.entryContent(_:)` ever draws a `.segmented`
    /// entry in (`HelmToolbarActions.swift`, `HelmUI`, which may not reach
    /// this rig itself — the reserve crosses to it as plain data on the
    /// entry). Tester (2026-09-26) measured the switcher's own width unchanged
    /// across selecting the first option, the second, or none, so the first
    /// option stands in here for whichever is actually selected; an entry
    /// with no options at all reserves nothing.
    /// **Rounded up to the next whole point** — a half-point reserve for
    /// Hosts' own pair (77.5 pt, this file's centre-tabs width too, since the
    /// capsule's `helm.actions` item sits beside them) left the tabs evicting
    /// once and coming back a point later as the pane widened across it
    /// (`HostsTabsUnfoldWithoutABlinkTests`: 72.0, 78.0 and 80.0 unfold
    /// clean, 77.5 blinks every time — a correlation with the half point,
    /// not a located threshold) — rounding down would risk landing short on
    /// some other pair the same way, so the ceiling is the only direction
    /// that never re-introduces the half-point.
    private static func segmentedReserveWidth(_ options: [HelmToolbarTab]) -> CGFloat {
        guard let first = options.first else { return 0 }
        let key = options.map(\.symbol)
        if let cached = segmentedReserveCache[key] { return cached }
        let view = HelmToolbarSwitcher(HelmA11y.whatToShow, selection: .constant(first.id),
                                       segments: options.map { HelmSwitcherSegment($0.id, $0.title, symbol: $0.symbol) })
            .environment(\.helmSwitcherStyle, .icons)
        var width = measurementRig.measure(AnyView(view))
        if options.count == 1 { width += oneOptionCapsuleMargin }
        width = width.rounded(.up)
        segmentedReserveCache[key] = width
        return width
    }

    /// **One custom-view item for every declared action, hosting
    /// `HelmToolbarActionsCapsule`** (`HelmUI/DesignSystem/HelmToolbarActions.swift`)
    /// — replaces one plain `NSToolbarItem` per action, adjacent so AppKit's
    /// own glass-sharing (WWDC25-310) drew them as one capsule and hiding one
    /// (`NSToolbarItem.isHidden`) collapsed its width, a relayout AppKit
    /// itself animates: Refresh visibly sliding to make room for Upgrade on
    /// every visit to Homebrew's Updates tab. The capsule's own back layer
    /// reserves that width for every declared action regardless of which are
    /// shown, so the hosted item's intrinsic size — and everything beside it
    /// in the bar — never moves at all.
    private func makeActionsItem(_ bar: PageBar) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.actionsID)
        let model = HelmToolbarActionsModel()
        model.press = { [weak self, weak bar] id in
            guard self != nil, let bar, bar.isLive,
                  let action = bar.content?.actions.first(where: { $0.id == id }) else { return }
            Self.perform(action)
        }
        model.pressItem = { [weak self, weak bar] actionID, itemID in
            guard self != nil, let bar, bar.isLive,
                  let action = bar.content?.actions.first(where: { $0.id == actionID }) else { return }
            switch action.kind {
            case .menu(let items):
                guard let item = items.first(where: { $0.id == itemID }) else { return }
                item.perform()
            case .segmented(let options, let selection):
                guard options.contains(where: { $0.id == itemID }) else { return }
                selection.wrappedValue = itemID
            case .button, .toggle:
                break
            }
        }
        // **Seeded from whatever `bar.content` already carries.** `content`
        // is assigned before this delegate call ever runs (`buildBar` sets
        // it, then assigns `itemIdentifiers`, which is what asks for this
        // item) — so a bar rebuilt while frozen (a page-bar style toggle
        // mid-visit) starts its capsule already showing the same actions the
        // page had before the rebuild, rather than empty. Without this, the
        // live redeclare that follows found `model.visibleIDs` still `[]`
        // and animated the whole capsule in from nothing — exactly the
        // movement Refresh is meant never to make.
        if let content = bar.content {
            model.setDeclared(Self.actionEntries(for: content))
            model.setVisibleIDs(content.actions.filter(\.isVisible).map(\.id))
        }
        // Seeded the same way `isInteractive` is not (it defaults `true` on
        // the model itself): `windowAppearsActive`'s own header says why this
        // one crosses in from outside rather than starting from a model
        // default that would never move for a page whose bar is built while
        // the window is already inactive.
        model.setAppearsActive(windowAppearsActive)
        // The model answers correctly the instant it is read — the glyph's own
        // dim above proves that — but the *glass* below is not seeded from it
        // at all, and reads whatever this window happened to already carry
        // before this capsule existed. See
        // `correctActionsGlassOnFirstAttach(_:)`'s own header for the reading:
        // flagged here, spent once this bar is actually attached.
        if !windowAppearsActive { bar.actionsGlassNeedsFirstAttachCorrection = true }
        // **`content.search == nil` is "the capsule is this bar's own last
        // item"** — `identifiers(content:style:)` never puts anything after
        // `helm.actions` but `helm.search`, and `ShapeSignature.hasSearch`
        // rebuilds the whole bar, this item included, the moment that
        // changes — so this reads once, at construction, rather than on every
        // `patchActions`. See `HelmToolbarActionsCapsule.edgeMargin`'s own
        // header for the measurement this closes: Hosts and Leftovers, which
        // end their bar here, used to sit 4.0 pt from the window's trailing
        // edge against Uninstaller's 8.0 pt for `helm.search` at the same
        // width.
        let trailingInset = bar.content?.search == nil ? HelmToolbarActionsCapsule.edgeMargin : 0
        let hosting = NSHostingView(rootView: HelmToolbarActionsCapsule(model, trailingInset: trailingInset))
        hosting.sizingOptions = [.intrinsicContentSize]
        item.view = hosting
        // Not a plain image item any more, so no second AppKit glass behind
        // the SwiftUI one it now draws for itself (`isBordered = true` wraps
        // the hosted view in AppKit's own bordered chrome — measured).
        item.isBordered = false
        item.label = HelmA11y.moreActions
        bar.actionsModel = model
        bar.actionsItem = item
        patchActionsMenu(bar)
        return item
    }

    /// **`patchActions(_:animated:)`.** `declared` and each entry's
    /// `isEnabled` are written inside a transaction with animations off,
    /// always — a button dimming is not the morph. Whether the *visible* set
    /// moves is written separately, and only that write may animate: `animated`
    /// is true exactly when `refresh()`'s own `patch(_:animated:)` call was
    /// answering for a bar that was already attached to the window before this
    /// call (`show(_:key:)`'s return value) and is live — the first
    /// build of a bar, a return visit and a frozen bar all take the
    /// non-animated path, because a capsule that has not been on screen yet,
    /// or is not meant to look interactive, has nothing to morph *from*.
    private func patchActions(_ bar: PageBar, animated: Bool) {
        guard let content = bar.content, let model = bar.actionsModel else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            model.setDeclared(Self.actionEntries(for: content))
        }
        let visible = content.actions.filter(\.isVisible).map(\.id)
        if visible != model.visibleIDs {
            if animated {
                withAnimation(HelmMotion.interface) { model.setVisibleIDs(visible) }
            } else {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { model.setVisibleIDs(visible) }
            }
        }
        patchActionsMenu(bar)
    }

    /// **The floor for the rare case where even the capsule overflows.**
    /// `NSToolbarItem.menuFormRepresentation` is what AppKit draws in its own
    /// «»» menu once an item no longer fits at all — a custom-view item has
    /// no menu form of its own by default, so without this an overflowed
    /// actions capsule would offer nothing to press.
    private func patchActionsMenu(_ bar: PageBar) {
        guard let item = bar.actionsItem, let content = bar.content else { return }
        let visible = content.actions.filter(\.isVisible)
        switch visible.count {
        case 0:
            item.menuFormRepresentation = nil
        case 1:
            item.menuFormRepresentation = actionMenuItem(visible[0], bar: bar)
        default:
            let top = NSMenuItem(title: HelmA11y.moreActions, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: HelmA11y.moreActions)
            // Not AppKit's own automatic enabling: `actionMenuItemPressed(_:)`
            // has no `validateMenuItem(_:)` of its own, and this app's own
            // rule is that a button macOS is already offering to press has to
            // be one it can act on — the same rule `NSToolbarItemValidation`
            // used to enforce for the plain items this replaced.
            submenu.autoenablesItems = false
            for action in visible { submenu.addItem(actionMenuItem(action, bar: bar)) }
            top.submenu = submenu
            item.menuFormRepresentation = top
        }
    }

    /// **A `.button` or a `.toggle` becomes one pressable item, as before; a
    /// `.menu` becomes a submenu of its own, one item per
    /// `HelmToolbarMenuItem`, checkmarked and routed to
    /// `actionMenuSubitemPressed` instead** — there is no single press for a
    /// menu action to route to `actionMenuItemPressed` at all.
    private func actionMenuItem(_ action: HelmToolbarAction, bar: PageBar) -> NSMenuItem {
        switch action.kind {
        case .button:
            let item = NSMenuItem(title: action.title, action: #selector(actionMenuItemPressed(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = action.id
            item.isEnabled = action.isEnabled && bar.isLive
            return item
        case .toggle(let isOn, _):
            let item = NSMenuItem(title: action.title, action: #selector(actionMenuItemPressed(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = action.id
            item.isEnabled = action.isEnabled && bar.isLive
            item.state = isOn ? .on : .off
            return item
        case .menu(let items):
            let top = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: action.title)
            submenu.autoenablesItems = false
            for menuItem in items {
                let subitem = NSMenuItem(title: menuItem.title,
                                         action: #selector(actionMenuSubitemPressed(_:)), keyEquivalent: "")
                subitem.target = self
                subitem.representedObject = [action.id, menuItem.id]
                subitem.isEnabled = menuItem.isEnabled && action.isEnabled && bar.isLive
                subitem.state = menuItem.isOn ? .on : .off
                submenu.addItem(subitem)
            }
            top.submenu = submenu
            return top
        case .segmented(let options, let selection):
            // The same submenu-of-checks shape a `.menu` action's own floor
            // already takes — this is the "overflow (») menu form shows the
            // two options with a checkmark on the current one" the owner
            // asked for, reusing `actionMenuSubitemPressed` rather than a
            // route of its own.
            let top = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: action.title)
            submenu.autoenablesItems = false
            let current = selection.wrappedValue
            for option in options {
                let subitem = NSMenuItem(title: option.title,
                                         action: #selector(actionMenuSubitemPressed(_:)), keyEquivalent: "")
                subitem.target = self
                subitem.representedObject = [action.id, option.id]
                subitem.isEnabled = action.isEnabled && bar.isLive
                subitem.state = option.id == current ? .on : .off
                submenu.addItem(subitem)
            }
            top.submenu = submenu
            return top
        }
    }

    @objc private func actionMenuItemPressed(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let key = attachedPageKey, let bar = pageBars[key], bar.isLive,
              let action = bar.content?.actions.first(where: { $0.id == id }) else { return }
        Self.perform(action)
    }

    /// The overflow menu's own route into a `.menu` action's items, or into a
    /// `.segmented` action's options — the capsule's own equivalent, for
    /// either kind, is `HelmToolbarActionsModel.pressItem`.
    @objc private func actionMenuSubitemPressed(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let key = attachedPageKey, let bar = pageBars[key], bar.isLive,
              let action = bar.content?.actions.first(where: { $0.id == pair[0] }) else { return }
        switch action.kind {
        case .menu(let items):
            guard let item = items.first(where: { $0.id == pair[1] }) else { return }
            item.perform()
        case .segmented(let options, let selection):
            guard options.contains(where: { $0.id == pair[1] }) else { return }
            selection.wrappedValue = pair[1]
        case .button, .toggle:
            break
        }
    }

    // MARK: - The bar's own right-click menu

    /// **Whether `event` is the menu gesture on this window's bar** —
    /// anywhere in the titlebar and toolbar: the name zone or AppKit's own
    /// title, empty bar space, the tabs full or folded, the actions capsule,
    /// the collapsed magnifier. Not the page (the same "not content" measure
    /// M1's fold-back uses), not the window's own buttons, and not the search
    /// field while it is being edited, whose own text menu (Cut, Copy, Paste)
    /// is the one a person is reaching for there. AppKit offers nothing of its
    /// own on this bar to override: its toolbar view answers `menu(for:)`
    /// with nil for a right-click on the bar, the title, the titlebar and
    /// every item viewer while customisation and display-mode customisation
    /// are both off (`buildBar(label:content:shape:)`), read on the fold
    /// tests' split rig under both page-bar styles (engineer, 2026-09-27).
    ///
    /// `internal` and apart from `popUpBarMenu(_:)` for the reason
    /// `tookMagnifierPress(_:)` is: a test can hand it a built event and read
    /// the decision, where the pop-up itself is modal.
    func opensBarMenu(_ event: NSEvent) -> Bool {
        guard let window, event.window === window,
              HelmToolbarSwitcher<String>.isTheGesture(type: event.type, modifiers: event.modifierFlags)
        else { return false }
        let point = event.locationInWindow
        guard !window.contentLayoutRect.contains(point) else { return false }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(kind),
               button.convert(button.bounds, to: nil).contains(point) { return false }
        }
        if let field = attachedBar?.searchItem?.searchField, field.currentEditor() != nil,
           let superview = field.superview,
           superview.bounds.contains(superview.convert(point, from: nil)) {
            return false
        }
        return true
    }

    /// Whichever bar is `window.toolbar` right now — a page's own, or the
    /// shared name-only one.
    private var attachedBar: PageBar? {
        guard let key = attachedPageKey else { return nil }
        return key == Self.nameOnlyKey ? nameOnlyBar : pageBars[key]
    }

    private func popUpBarMenu(_ event: NSEvent) {
        guard let view = window?.contentView?.superview ?? window?.contentView else { return }
        NSMenu.popUpContextMenu(barMenu, with: event, for: view)
    }

    /// **One menu for the whole bar, rebuilt each time it opens**
    /// (`menuNeedsUpdate(_:)`) from the settings and from what the bar on
    /// screen holds. The same instance is every centre switcher's own
    /// `NSView.menu` (`helmSwitcherView`), which is what VoiceOver's "show
    /// menu" opens on a focused switcher — one menu whichever way it is
    /// reached.
    private lazy var barMenu: NSMenu = {
        let menu = NSMenu(title: AppStr.pageBar)
        menu.autoenablesItems = false
        menu.delegate = self
        return menu
    }()

    /// **What the bar's menu offers, left to right as the bar reads**: the
    /// page header on every page; the tabs' label style only where the page
    /// has tabs; Always Collapse Search only where it has a search field,
    /// even one disabled right now. Absent rather than dimmed where it does
    /// not apply — a context menu hides what cannot act (HIG, context menus),
    /// the same answer the tabs' own row already gave on a page without tabs.
    /// `tabLabels` and `alwaysCollapseSearch` are nil for a page without that
    /// part. `static` so a test reads the items without raising a menu.
    static func barMenuItems(pageBarStyle: PageBarStyle, tabLabels: ToolbarSwitcherStyle?,
                             alwaysCollapseSearch: Bool?, target: AnyObject?) -> [NSMenuItem] {
        var items: [NSMenuItem] = [NSMenuItem.sectionHeader(title: AppStr.pageBar)]
        for (choice, title) in [(PageBarStyle.moduleName, AppStr.pageBarWithIcon),
                                (PageBarStyle.windowTitle, AppStr.pageBarWithoutIcon)] {
            let item = NSMenuItem(title: title, action: #selector(barMenuChosePageBar(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = choice.rawValue
            item.state = choice == pageBarStyle ? .on : .off
            items.append(item)
        }
        if let tabLabels {
            items.append(.separator())
            items.append(NSMenuItem.sectionHeader(title: AppStr.tabLabels))
            for choice in ToolbarSwitcherStyle.allCases {
                let item = NSMenuItem(title: choice.label, action: #selector(barMenuChoseTabLabels(_:)),
                                      keyEquivalent: "")
                item.target = target
                item.representedObject = choice.rawValue
                item.state = choice == tabLabels ? .on : .off
                items.append(item)
            }
        }
        if let alwaysCollapseSearch {
            items.append(.separator())
            let item = NSMenuItem(title: AppStr.alwaysCollapseSearch,
                                  action: #selector(barMenuToggledCollapseSearch(_:)), keyEquivalent: "")
            item.target = target
            item.state = alwaysCollapseSearch ? .on : .off
            items.append(item)
        }
        for item in items where !item.isSeparatorItem { item.isEnabled = true }
        return items
    }

    // Each only writes the setting; the setting's own notification is what
    // reaches the bar, the same path General's Appearance row takes.
    @objc private func barMenuChosePageBar(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = PageBarStyle(rawValue: raw),
              choice != AppSettings.pageBarStyle else { return }
        AppSettings.pageBarStyle = choice
    }

    @objc private func barMenuChoseTabLabels(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let choice = ToolbarSwitcherStyle(stored: raw)
        guard choice != AppSettings.toolbarSwitcherStyle else { return }
        AppSettings.toolbarSwitcherStyle = choice
    }

    @objc private func barMenuToggledCollapseSearch(_ sender: NSMenuItem) {
        AppSettings.alwaysCollapseSearch.toggle()
    }

    // MARK: - Search

    private func makeSearchItem(_ bar: PageBar) -> NSSearchToolbarItem {
        let item = NSSearchToolbarItem(itemIdentifier: Self.searchID)
        // "The field should be configured before assigned" (`NSSearchToolbarItem.h`)
        // — built here and handed over once, rather than mutated on the
        // default field the item starts with.
        let field = NSSearchField()
        field.sendsWholeSearchString = true
        // `sendsWholeSearchString` governs keystrokes only; ending editing can
        // still fire the field's action regardless
        // (`NSCell.sendsActionOnEndEditing`), which `endSearchInteraction`
        // calls into whenever the field folds back to a magnifier or focus
        // simply moves elsewhere. Measured directly, this Mac: a bare
        // `NSSearchField()` — what is built above — already answers `false`
        // here, but `NSSearchToolbarItem`'s own default field, before this
        // one is assigned over it, answers `true`; assigning our own field is
        // what makes the difference, not this line. Kept explicit rather than
        // relied on by construction, so a future AppKit default, or a future
        // change to configure the item's own default field instead of
        // building a fresh one, cannot silently turn this back on. Off, only
        // the field editor's own `insertNewline(_:)` — a Return — reaches
        // `searchSubmitted`, which `testEndingEditingSubmitsNothing`
        // (`ASearchRunsOnReturnNotOnAKeyTests.swift`) guards directly.
        field.cell?.sendsActionOnEndEditing = false
        field.recentsAutosaveName = nil
        field.delegate = self
        field.target = self
        field.action = #selector(searchSubmitted(_:))
        field.setAccessibilityLabel(HelmA11y.searchField)
        field.placeholderString = bar.content?.search?.prompt ?? ""
        field.stringValue = bar.content?.search?.text.wrappedValue ?? ""
        // M2's own hook — see `watchSearchFieldFrame`'s header.
        field.postsFrameChangedNotifications = true
        // Built inactive and switched by `restSearch(_:)` alone — see
        // `PageBar.searchRestCap`'s own header for what it does to AppKit's
        // own collapse and why its priority sits below 750.
        let cap = field.widthAnchor.constraint(lessThanOrEqualToConstant: 0)
        cap.priority = .defaultLow
        cap.identifier = "helm.search.restCap"
        bar.searchRestCap = cap
        item.searchField = field
        // AppKit's own default reads "Search" in its own language, never
        // this app's — said in this app's words, and kept current on a
        // language change through `patchSearch()`.
        item.label = HelmA11y.searchField
        item.paletteLabel = HelmA11y.searchField
        item.toolTip = HelmA11y.searchField
        bar.searchItem = item
        watchSearchFieldFrame(bar, field: field)
        // A bar built after the setting was turned on — a page not visited
        // since — is born resting, rather than waiting for a change it
        // missed.
        restSearch(bar)
        return item
    }

    /// **The one rest predicate for "Always Collapse Search"
    /// (`AppSettings.alwaysCollapseSearch`).** The search rests as AppKit's
    /// own magnifier only while the setting is on, the field is empty, nobody
    /// is editing it and no opening is under way; anything else releases it
    /// to AppKit's ordinary layout — so a query left in the field is never
    /// hidden behind a glyph. Called where one of those four can have just
    /// moved: the bar's own search item being built, the setting changing
    /// (`alwaysCollapseSearchWatch`, in `restEverySearch`), editing ending
    /// (`controlTextDidEndEditing`), a page writing the field's text
    /// itself (`patchSearch`) and the field's own clear button pressed with
    /// nobody editing (`searchSubmitted`) — the setting changing and the last
    /// two then fold a field an interaction had opened (`foldOpenedSearch`),
    /// which the cap alone does not. **Not** on an opening: AppKit's own
    /// `beginSearchInteraction()` opens a capped field to
    /// `preferredWidthForSearchField` by itself, so the magnifier press
    /// (M1), the keyboard and VoiceOver all open it the same way
    /// (`PageBar.searchRestCap`'s own header has the reading).
    ///
    /// **A release clears `bar.rest` first.** M2 (`searchFieldFrameChanged`)
    /// reads a field that grows at an unchanged room while `rest` says it
    /// was collapsed as a magnifier press opening it — it decides whether to
    /// fold the tabs (`openingKeepsTheTabs(_:)`, off `rest.openFits`) and
    /// sets `searchOpening`, which only the end of an editing session ever
    /// clears. A release grows the field in exactly that way with no editor
    /// at all (the setting turned off, a query left behind), so without this
    /// `searchOpening` would stay set and `settle(_:)` would never run for
    /// this bar again.
    /// `settle(_:)` writes `rest` afresh on its next pass.
    private func restSearch(_ bar: PageBar) {
        guard let cap = bar.searchRestCap, let field = bar.searchItem?.searchField else { return }
        let rests = AppSettings.alwaysCollapseSearch && field.stringValue.isEmpty
            && field.currentEditor() == nil && !bar.searchOpening
        guard cap.isActive != rests else { return }
        if !rests { bar.rest = nil }
        cap.isActive = rests
    }

    private func patchSearch(_ bar: PageBar) {
        guard let item = bar.searchItem else { return }
        item.label = HelmA11y.searchField
        item.paletteLabel = HelmA11y.searchField
        item.toolTip = HelmA11y.searchField
        // **Defect found in this pass**: the field's own accessibility label
        // was set once, in `makeSearchItem`, and never again — nothing in the
        // toolbar's shape tracks the language, so after a language change the
        // field kept naming itself in the old one
        // (`TheSearchFieldsNameFollowsALanguageChangeThroughTheNewToolbarTests
        // .testALanguageChangeReReadsTheSearchFieldsAccessibilityLabel`).
        item.searchField.setAccessibilityLabel(HelmA11y.searchField)
        guard let search = bar.content?.search else { return }
        if item.searchField.placeholderString != search.prompt {
            item.searchField.placeholderString = search.prompt
        }
        // Never while the field is being edited — reading back into a field
        // somebody is mid-keystroke in is how a caret jumps to the end of
        // whatever this write puts there.
        let isEditing = item.searchField.currentEditor() != nil
        if !isEditing, item.searchField.stringValue != search.text.wrappedValue {
            item.searchField.stringValue = search.text.wrappedValue
            // The page just filled or emptied the field itself: whether it
            // may rest as the magnifier has moved with it — and emptied, a
            // field an interaction had opened is folded as well.
            restSearch(bar)
            if bar.searchRestCap?.isActive == true { foldOpenedSearch(bar) }
        }
    }

    @objc private func searchSubmitted(_ sender: NSSearchField) {
        guard let key = attachedPageKey, let bar = pageBars[key],
              bar.searchItem?.searchField === sender else { return }
        bar.content?.search?.text.wrappedValue = sender.stringValue
        // The field's own clear button, pressed while nobody is editing —
        // VoiceOver's press and Full Keyboard Access's Space reach it as a
        // `performClick`, no focus — empties the field through this action
        // alone: no editing ends, and `patchSearch` then finds the field
        // already equal to the binding written above, so nothing else asks.
        // Only with no editor: mid-edit (Return, or the button clicked while
        // typing) the end of editing asks, a turn later, as it always did.
        if sender.currentEditor() == nil {
            restSearch(bar)
            if bar.searchRestCap?.isActive == true { foldOpenedSearch(bar) }
        }
        guard !sender.stringValue.isEmpty else { return }
        bar.content?.search?.onSubmit?()
    }

    /// **Folds a field an interaction once opened, now empty and idle, back
    /// to the magnifier — without touching first responder.** The cap alone
    /// does not: an opening leaves AppKit's own minimum on the field's item
    /// view at `preferredWidthForSearchField`, priority 750, above the cap's
    /// 250, and AppKit lifts it when an editing session on this field ends
    /// empty — a query typed and left keeps it, so clearing that query
    /// later with nobody editing (the clear button's `performClick`, a page
    /// writing "") left the field standing open at 240 pt (read on the
    /// collapse rig, engineer, 2026-09-27: `preferredWidthForSearchField`
    /// written down and back, the item hidden and shown, the cap switched off
    /// and on, the item handed another field and this one back, the item and
    /// the field disabled and enabled, `endSearchInteraction()` and a posted
    /// end-of-editing notification each left it at 240 pt).
    ///
    /// **What AppKit does at that end is asked for directly:** the field's
    /// own `textDidEndEditing(_:)`, with a throwaway text view standing in for
    /// the field editor, since the window's one editor may be somebody
    /// else's. Read on the same rig: the field folds to the magnifier on
    /// AppKit's own animation, the window's first responder is the same
    /// object before and after, and a page field being typed in keeps its
    /// editor, its caret, its undo, no end of editing and no action; on a
    /// field already resting it changes nothing, width or frame. A whole
    /// interaction begun and ended here — the fold this replaced — took the
    /// window's first responder and gave a page field back with its text all
    /// selected and its undo gone (tester, 2026-09-27). `controlTextDidEndEditing` hears it as it
    /// hears an empty edit ending, and arms the settle the tabs come back by.
    /// The field's action does not fire: `sendsActionOnEndEditing` is off
    /// (`makeSearchItem`).
    private func foldOpenedSearch(_ bar: PageBar) {
        guard let field = bar.searchItem?.searchField, field.currentEditor() == nil,
              field.stringValue.isEmpty else { return }
        let standIn = NSTextView()
        standIn.isFieldEditor = true
        field.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: standIn,
                                             userInfo: [NSText.movementUserInfoKey: NSTextMovement.other.rawValue]))
    }

    /// Re-arms `activityWatch` for whichever module `currentSelection` names,
    /// or drops it where there is none to watch.
    private func watchActivity() {
        guard case .module(let id) = currentSelection,
              let descriptor = ModuleRegistry.descriptor(id),
              let live = model.host.liveModule(id),
              let changes = descriptor.statusChanges(live.vm) else {
            activityWatch = nil
            return
        }
        activityWatch = changes.sink { [weak self] _ in self?.patchAttachedName() }
    }

}

extension SettingsToolbar: NSMenuDelegate {
    /// The bar's menu, filled for the bar on screen at the moment it opens —
    /// a page switch, a setting changed in General or a language change
    /// since the last time has nothing else to rebuild it by.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === barMenu else { return }
        let content = attachedBar?.content
        let hasTabs = !(content?.tabs.isEmpty ?? true)
        let hasSearch = content?.search != nil
        menu.removeAllItems()
        for item in Self.barMenuItems(pageBarStyle: AppSettings.pageBarStyle,
                                      tabLabels: hasTabs ? AppSettings.toolbarSwitcherStyle : nil,
                                      alwaysCollapseSearch: hasSearch ? AppSettings.alwaysCollapseSearch : nil,
                                      target: self) {
            menu.addItem(item)
        }
    }
}

extension SettingsToolbar: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField,
              let key = attachedPageKey, let bar = pageBars[key],
              field === bar.searchItem?.searchField else { return }
        bar.content?.search?.text.wrappedValue = field.stringValue
    }

    /// **Arms the settle debounce the moment editing ends** — the field can
    /// stay visually wide with text left in it after Return or after focus
    /// simply moves elsewhere, and `settle(_:)`'s own prediction is what
    /// decides whether the full tabs fit beside that width; nothing here has
    /// to special-case a field left non-empty. **A refusal recorded during
    /// this very interaction is deliberately left alone here** — clearing it
    /// on end-of-editing would let the close this refusal exists to gate
    /// retry immediately, which is the flicker back; it is cleared only when
    /// the *next* interaction actually opens, which `searchFieldFrameChanged`
    /// (M2) reads off the field's own growth against
    /// `preferredWidthForSearchField` (see its header for why that, and not
    /// a delegate call or a branch in `settle(_:)`, is the reliable signal),
    /// and `tookMagnifierPress`'s own fold-and-open branch clears it earlier
    /// still, on the ordinary path where the field was genuinely hidden
    /// beforehand. Together these keep a wrong decision to one blink per
    /// cycle rather than latching for the rest of the session.
    ///
    /// **This interaction's tail is armed here, unconditionally** —
    /// `bar.searchEditEndedDeadline` (`PageBar.searchEditEndedDeadline`'s own header) is what M2 reads
    /// to tell one more growth frame from the interaction that just ended
    /// apart from a brand new opening, whatever text this one leaves behind.
    /// **A field left empty is, in addition, about to start its own collapse
    /// animation this class cannot see the end of** — `bar
    /// .searchClosingDeadline` is armed only for that case, for `settle(_:)`'s
    /// own wait gate to read; a field left with text stays wide and is a
    /// genuine demand, not a collapse in progress, so that second deadline is
    /// not armed for it.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField,
              let key = attachedPageKey, let bar = pageBars[key],
              field === bar.searchItem?.searchField else { return }
        bar.searchOpening = false
        bar.searchEditEndedDeadline = Date().addingTimeInterval(Self.searchCollapseWait)
        if field.stringValue.isEmpty {
            bar.searchClosingDeadline = Date().addingTimeInterval(Self.searchCollapseWait)
        }
        // Empty: the cap stays on and AppKit folds the field back to its
        // magnifier; a query left behind releases it (`restSearch(_:)`).
        // A turn later, and read then: this notification arrives while the
        // field editor is still attached, and a predicate asked now reads
        // "being edited" and releases a field that is about to be empty and
        // idle — the rig read it resting open at 226 pt instead of folding.
        DispatchQueue.main.async { [weak self, weak bar] in
            guard let self, let bar else { return }
            self.restSearch(bar)
        }
        scheduleSettle(bar)
    }
}

/// **What decides whether a cached bar can be reused as it stands, or must be
/// rebuilt as a fresh `NSToolbar`.** Everything here can change without a
/// page ever redeclaring — `pageBarStyle` from a `defaults write`, and the
/// tab/action id lists, whether search exists and whether an action is
/// `.segmented` (which decides the centred set) come from whichever content
/// (live or last-known) the bar is being asked to show — so equality here,
/// not a separate invalidation call, is what a style change actually
/// invalidates: the next time any page's bar is obtained, a stale shape
/// simply fails the comparison and a fresh `NSToolbar` is built in its place.
/// `actionIDs` stays even though there is one `NSToolbarItem` for the whole
/// capsule now, not one per action — `HelmToolbarActionsCapsule`'s reserve is
/// sized from the *declared* set, so a page whose declared actions change
/// shape still needs a fresh item. `PageBarStyle` is a plain enumeration with
/// no associated values, so it is `Equatable` for nothing more than declaring
/// it here.
@MainActor
private struct ShapeSignature: Equatable {
    let pageBarStyle: PageBarStyle
    let tabIDs: [String]
    let actionIDs: [String]
    let hasSearch: Bool
    /// Read by `SettingsToolbar.centredIdentifiers(_:)` — the actions id list
    /// above cannot say it, since an entry keeps its id whatever its kind.
    let hasSegmentedAction: Bool

    init(content: HelmPageToolbarContent?) {
        pageBarStyle = AppSettings.pageBarStyle
        tabIDs = content?.tabs.map(\.id) ?? []
        actionIDs = content?.actions.map(\.id) ?? []
        hasSearch = content?.search != nil
        hasSegmentedAction = content?.actions.contains { action in
            if case .segmented = action.kind { return true }
            return false
        } ?? false
    }
}

/// **One page's own toolbar and everything `SettingsToolbar` has drawn into
/// it.** Kept in `SettingsToolbar.pageBars`, one per page key, for the life of
/// the settings window — bounded by the number of pages Helm ships
/// (`ModuleRegistry.all.count` plus the three non-module pages), which does
/// not grow while the app runs, so nothing here is the unbounded record
/// `CLAUDE.md` warns against.
@MainActor
private final class PageBar {
    let toolbar: NSToolbar
    var shape: ShapeSignature
    /// The last content this bar was ever shown with — kept even after a
    /// withdraw, so a frozen bar still knows its own tabs, actions and search
    /// prompt until a fresh declare replaces it.
    var content: HelmPageToolbarContent?
    /// Whether `content` is backed by a live declaration right now — `false`
    /// disables every handler (`SettingsToolbar.freeze`, the actions model's
    /// `press`, `searchSubmitted`) without discarding anything. **Not** what
    /// the tabs and the actions capsule read to decide whether to *look*
    /// disabled — see `isInteractive`.
    var isLive = true
    /// Whether the tabs, the actions capsule and the search field should
    /// *look* interactive right now — moved only by a visible `freeze(_:
    /// visibly:)` and by `patch(_:animated:)`, and deliberately not tied to
    /// `isLive`: an ordinary return visit sets `isLive = false` on every
    /// frozen turn, including the ones with nothing worth dimming, and a
    /// snapshot keyed on `isLive` used to rebuild the tabs — disabled, then
    /// re-enabled — on every one of them, which is what read as the tabs'
    /// text still animating even once the tabs had stopped being evicted
    /// from the bar.
    var isInteractive = true
    var identifiers: [NSToolbarItem.Identifier] = []

    var nameItem: NSToolbarItem?
    var nameHost: NSHostingView<NameZoneView>?
    /// **Only on the shared name-only bar** — `nil` on every bar built for a
    /// page that declares tabs, actions or search, since `identifiers()`
    /// never lists `helm.status` there. See `SettingsToolbar.makeStatusItem`'s
    /// own header.
    var statusItem: NSToolbarItem?
    var statusHost: NSHostingView<StatusZoneView>?
    var tabsItem: NSToolbarItem?
    // `AnyView`: the Helm-style switcher is wrapped with `.environment(...)`
    // before it is hosted (`helmSwitcherView`), which changes the concrete
    // `some View` type without changing what is actually mounted.
    var tabsSwitcherHost: NSHostingView<AnyView>?
    /// **Whether the tabs are folded to a one-item capsule with a menu.** The
    /// one field `SettingsToolbar.setTabsFolded(_:bar:layout:reseat:)` writes
    /// — see its own header for the whole mechanism — and the one
    /// `helmSwitcherView` and `HelmTabsSnapshot` read to decide what the
    /// hosted `HelmToolbarSwitcher` draws.
    var tabsFolded = false
    /// **True from the moment a search interaction starts opening — a
    /// magnifier press (M1) or a growth M2 reads as one — until it actually
    /// ends** (`controlTextDidEndEditing`). AppKit's own field editor does
    /// not arrive until well after the field has started growing (measured:
    /// the gaps between the field's own animation frames run longer than
    /// `settleInterval`), so `settle(_:)`'s existing guard on
    /// `currentEditor() == nil` is not enough by itself to keep a decision
    /// from running mid-open, against a field frame that has not caught up
    /// with where it is growing to yet — `searchRoomBudget(_:)` is what reads
    /// this flag, to budget the field's `preferredWidthForSearchField`
    /// instead of its stale, understated current frame while it is set.
    var searchOpening = false
    /// **What the bar looked like the last time `settle(_:)` finished
    /// measuring it (`nil` once `restSearch(_:)` releases the cap)** — whether the search field was
    /// collapsed to its magnifier, the room offered at that moment, and
    /// whether the full tabs would still fit beside that field *open*
    /// (`openFits`). M2 reads `collapsed`/`room` to tell "the magnifier was
    /// pressed and the field is opening" apart from "the window widened and
    /// the field re-opened at rest with more room already available", which
    /// is the same growing frame either way; both M1 and M2 read `openFits`
    /// through `openingKeepsTheTabs(_:)`, never geometry of their own — see
    /// that method's own header for why the decision belongs here, at rest,
    /// rather than live inside either opener.
    var rest: SettingsToolbar.RestSnapshot?
    /// The search field's own last measured width — M2's own before/after
    /// reading, since `NSView.frameDidChangeNotification` carries no delta.
    var lastFieldWidth: CGFloat = 0
    /// **The field's own width the last time it was actually seen collapsed
    /// to its magnifier** — `searchRoomBudget(_:)`'s own reading, kept here
    /// rather than recomputed, since once a fold has widened the field at
    /// rest there is no live `isHidden == true` moment left to read it from
    /// until the tabs genuinely give the room back. `nil` only until the
    /// first `settle()` this bar ever runs, which always finds the field
    /// collapsed (a fresh bar starts that way).
    var collapsedFieldWidth: CGFloat?
    /// **The `.windowTitle` title container's own trailing edge, the last
    /// time this bar's tabs were seen *not* folded** — `currentToolbarSlack(_:)`'s
    /// own memory of where the container rests without anything having
    /// folded, so `titleGrowth` can measure a fold's own growth against the
    /// resting edge rather than against the fitting-based prediction of it
    /// (`titleGrowth`'s own header has why those are not the same
    /// comparison). `nil` only until the first `settle()` this bar ever runs
    /// with the tabs not folded — the same precedent `collapsedFieldWidth`
    /// already sets for the search field's own resting width.
    var restingRawTitleMaxX: CGFloat?
    /// **The `.windowTitle` title container's own growth beyond its last
    /// resting edge, as `currentToolbarSlack(_:)` last read it** — zero under
    /// `.moduleName`, and zero whenever the tabs are not currently folded.
    /// `settle(_:)`'s own worst-case gate reads this right after calling
    /// `predictedSlack(bar:tabsWidth:)`, which is what populates it, the same
    /// "write in one call, read in the next" shape `pendingUnfoldFieldWidth`
    /// already uses.
    var titleGrowth: CGFloat = 0
    /// **How much of `SettingsToolbar.windowTitleOpenFloor` sits above this
    /// bar's own title `fittingWidth`, read fresh every `currentToolbarSlack(_:)`
    /// call that finds an anchor** — zero under `.moduleName`, and zero whenever the title's own
    /// content already needs more than the floor. Unlike `titleGrowth`, set
    /// regardless of `tabsFolded`: it charges a property of AppKit's own
    /// layout under `.windowTitle`, not a fold's own not-yet-reversed growth
    /// — see `SettingsToolbar.windowTitleOpenFloor`'s own header for the
    /// reading behind the number and `openFitsPrediction(_:searchItem:slack:
    /// anchored:)` for where it is charged.
    var titleOpenFloorCharge: CGFloat = 0
    /// **Set by `controlTextDidEndEditing` when the field is left empty —
    /// `settle(_:)`'s own wait gate refuses to unfold before this passes.**
    /// A search ending empty leaves the field mid-shrink from its wide,
    /// edited frame toward whatever it rests at with the tabs still folded
    /// (`SettingsToolbar.searchCollapseWait`'s own header measures that, and
    /// is where the corrected account of what it settles to — not
    /// necessarily anything small — lives), which this class only observes
    /// through the field's own frame changes (M2); deciding to unfold before
    /// that frame has actually stopped moving is what asked AppKit to lay
    /// the tabs out full beside a field still mid-shrink and got evicted for
    /// it. Cleared the moment `settle(_:)` reads it past the
    /// deadline — not on every tick — so a `settle(_:)` call that still
    /// finds it in the future keeps waiting without needing to know why.
    var searchClosingDeadline: Date?
    /// **Set by `controlTextDidEndEditing` every time an edit ends, whatever
    /// text is left in the field — unlike `searchClosingDeadline`, armed
    /// unconditionally.** M2 (`searchFieldFrameChanged`) reads this, not
    /// `searchClosingDeadline`, to tell a stray growth frame that follows the
    /// close of the interaction that just ended apart from a brand new
    /// opening: the field editor's resignation and AppKit's own layout do not
    /// land in the same tick, so one more growing frame can arrive after
    /// editing has already ended whether or not a query was left behind.
    /// Reusing `searchClosingDeadline` for that read would also feed
    /// `settle(_:)`'s own wait gate above, which exists only for an empty
    /// close's shrink animation and must not newly wait on a query left
    /// wide — this field is this one reader's own, so that gate's timing
    /// stays exactly as it was.
    var searchEditEndedDeadline: Date?
    /// **Set the moment `settle(_:)` itself calls `setTabsFolded(false, ...)`.**
    /// `checkOverflow()`'s own read of this, against
    /// `SettingsToolbar.overflowAttributionWindow`, is what tells "AppKit
    /// evicted something we just unfolded" apart from an ordinary, unrelated
    /// overflow it must still react to regardless (a language change, a
    /// sidebar drag).
    var lastOurUnfoldAt: Date?
    /// **The search field's own width at the exact moment `settle(_:)` set
    /// `lastOurUnfoldAt`** — always written together with it, and what
    /// `checkOverflow()` promotes into `refusedUnfold`'s own field-width
    /// component in place of a fresh read (`SettingsToolbar.unfoldContext(_:
    /// fieldWidth:)`'s own header for why a fresh read there never matches
    /// what a later `settle(_:)` call sees).
    var pendingUnfoldFieldWidth: CGFloat?
    /// **The last context an M3 net-fold attributed to our own unfold** —
    /// see `SettingsToolbar.UnfoldRefusalKey`'s own header for what it is
    /// keyed on and why equality, not a timeout, is what clears it.
    var refusedUnfold: SettingsToolbar.UnfoldRefusalKey?
    /// **The centre tabs' full width, and what it was measured under** —
    /// read and written only by `SettingsToolbar.settle(_:)`; see
    /// `SettingsToolbar.TabsWidthKey`'s own header for why a settle reuses it
    /// and what makes it measure again.
    var tabsWidth: (key: SettingsToolbar.TabsWidthKey, full: CGFloat)?
    nonisolated(unsafe) var fieldFrameWatch: NSObjectProtocol?
    /// **A `width <= 0` cap on the search field, below 750 — what makes
    /// AppKit rest the search as its own magnifier while room is plenty.**
    /// `NSSearchToolbarItem` has no public "collapse"; its field "layout
    /// constraints are managed by the item" (`NSSearchToolbarItem.h`). Read
    /// on a split-view rig at panes of 646, 846 and 1186 pt (engineer,
    /// 2026-09-27): AppKit's own constraints on the field are its edges
    /// pinned to `NSSearchToolbarItemView` at 1000 and that view's width at
    /// 997 (226 pt at rest in an 846 pt pane, 236 while editing) — nothing at
    /// or below 750. This cap, active at 250, 490 or 749 alike, rested the
    /// field hidden at 36 pt at every pane; `beginSearchInteraction()` with
    /// the cap still on opened it to `preferredWidthForSearchField`, 240 pt,
    /// with an editor; `endSearchInteraction()` on an empty field folded it
    /// back to hidden; and deactivating it at rest returned the field to
    /// exactly its uncapped width (226 and 325 pt). At 751 the cap did
    /// nothing at all, and at 999 it pinned the field at 0 pt through an
    /// editing session — a search nobody could see. Hence `.defaultLow`, and
    /// hence one rest predicate (`SettingsToolbar.restSearch(_:)`) as the only
    /// writer of `isActive`.
    var searchRestCap: NSLayoutConstraint?
    var actionsModel: HelmToolbarActionsModel?
    var actionsItem: NSToolbarItem?
    var searchItem: NSSearchToolbarItem?
    /// **Set by `SettingsToolbar.makeActionsItem` the moment it builds this
    /// bar's capsule while the window already reads inactive, and consumed —
    /// once — the moment `show(_:key:)` actually attaches this bar.** See
    /// `SettingsToolbar.correctActionsGlassOnFirstAttach(_:)`'s own header for
    /// the reading behind it: the capsule's glass, unlike its glyph, is not
    /// seeded from `windowAppearsActive` at all, so a capsule built while the
    /// window reads inactive can draw lit glass until the deferred rebuild.
    var actionsGlassNeedsFirstAttachCorrection = false

    var lastNameSnapshot: SettingsToolbar.NameSnapshot?
    var lastTabsSnapshot: SettingsToolbar.HelmTabsSnapshot?

    init(toolbar: NSToolbar, shape: ShapeSignature) {
        self.toolbar = toolbar
        self.shape = shape
    }

    deinit {
        // `NotificationCenter` is safe to call from any thread/actor — its
        // own header says so — which is what lets a `deinit` Swift 6 treats
        // as nonisolated remove this at all.
        if let fieldFrameWatch { NotificationCenter.default.removeObserver(fieldFrameWatch) }
    }
}

/// **The dim shared by every piece of the name zone's own row, and by the
/// trailing status item beside it** — dimming together, as one unit,
/// applies across both `NSToolbarItem`s that carry the name's ink now that
/// the status has moved to the bar's trailing edge (2026-09-28), even though
/// the two are separate hosted views with nothing to composite together:
/// each reads the same four numbers, from `SettingsToolbar.patchName`'s one
/// snapshot, so they move on exactly the same call.
@MainActor func helmNameZoneInactiveOpacity(dark: Bool, titlebarIsTransparent: Bool) -> Double {
    switch (dark, titlebarIsTransparent) {
    case (true, true): NameZoneView.inactiveOpacityDark
    case (false, true): NameZoneView.inactiveOpacityLight
    case (true, false): NameZoneView.inactiveOpacityOpaqueDark
    case (false, false): NameZoneView.inactiveOpacityOpaqueLight
    }
}

/// The name zone's own view: the module's plate and its name, the way
/// `PageBarStyle`'s `.moduleName` arm drew them before the bridge — reused
/// here rather than redrawn, to the letter of size and spacing. **The status
/// word or badge that used to sit
/// beside the name here draws in `StatusZoneView` instead**, at the bar's
/// trailing edge (the owner, 2026-09-28: «Давай вернем его в правую часть») —
/// this view no longer knows a module has one.
struct NameZoneView: View {
    let symbol: String
    let tint: Color
    let title: String
    let iconStyle: SidebarStyle
    /// **The same `isKeyWindow || isMainWindow` signal the actions capsule
    /// reads** (`SettingsToolbar.windowAppearsActive`'s own header has the
    /// reading), not `\.controlActiveState`: this view is hosted through an
    /// `NSToolbarItem`'s custom view exactly like the capsule, and that
    /// environment key is not trusted here, for the capsule's reason
    /// (`HelmToolbarActionsCapsule`'s own header). `appearsActive` costs no
    /// rebuild the capsule's own glass needs — every ink below is a plain
    /// SwiftUI value read at draw time, not Liquid Glass, so reassigning this
    /// view's `rootView` (`SettingsToolbar.patchName`) is enough to move it.
    let appearsActive: Bool
    /// Which title bar the zone sits in — `window.titlebarAppearsTransparent`,
    /// which the band decision sets (`HelmBandChoice.titlebarAppearsTransparent`).
    /// AppKit dims its own title by a different amount under each, so the
    /// zone does too.
    let titlebarIsTransparent: Bool
    @Environment(\.colorScheme) private var colorScheme

    /// **Dark 222→92, Light 37→177 — AppKit's own `.windowTitle` layout,
    /// measured against this same toolbar row under macOS 27's transparent
    /// title bar**: a window's title text over
    /// this row's own flat, inactive chrome (bg 37 Dark, 247 Light) lands on
    /// that target from the zone's own full ink (222 Dark, 38 Light) at the
    /// opacity `bg·(1−x) + ink·x = target` solves for — the same algebra
    /// `HelmToolbarActionsCapsule.inactiveGlyphOpacity…` uses for the
    /// capsule's own glyph, kept as its own pair of constants for the same
    /// reason that one is two and not one: the two appearances do not agree.
    /// **The plate dims by the same amount as the title, as one unit.**
    /// AppKit draws a title as a single readable line and offers no separate
    /// dimming for an icon beside it — there is no distinct AppKit reading to
    /// give the plate and the title of their own, and picking one anyway
    /// would be a difference this zone's own model (a module's name, standing
    /// in for the window's title) does not have. One `.opacity()` on the
    /// whole row is that decision. `StatusZoneView` dims by the same two
    /// numbers, in its own `.opacity()`, so the two read as one row even
    /// though nothing composites them together — its own header.
    static let inactiveOpacityDark: Double = 0.30    // (92−37)/(222−37) ≈ 0.2973
    static let inactiveOpacityLight: Double = 0.33   // (247−177)/(247−38) ≈ 0.3349
    /// **The same two under the opaque title bar — macOS 26's, by the band
    /// decision — and AppKit 27.2's answer to that decision, not macOS 26's.**
    /// Read on this Mac (27.2, engineer, 2026-09-27) off a real
    /// `SettingsWindow` built with `HelmBandChoice.onMacOS(26)`, AppKit's own
    /// title drawn beside the zone, as the share of its lit ink the title
    /// keeps inactive (S3 and S5 alike, through its own `draw(_:)`): Light
    /// 0.399, Dark 0.279 — against 0.329 and 0.296 under the transparent
    /// title bar in the same run, which the pair above answers. Whether
    /// macOS 26 itself dims its title by the same amount is for the owner's
    /// 26 virtual machine to confirm; `TheCapsuleDrawsWhatAppKitsPlatterDrawsTests`
    /// holds the zone to AppKit's title under both title bars.
    static let inactiveOpacityOpaqueDark: Double = 0.28
    static let inactiveOpacityOpaqueLight: Double = 0.40

    private var inactiveOpacity: Double {
        helmNameZoneInactiveOpacity(dark: colorScheme == .dark, titlebarIsTransparent: titlebarIsTransparent)
    }

    var body: some View {
        HStack(spacing: HelmSpace.s5) {
            HelmIconPlate(symbol: symbol, tint: tint, size: 24)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.2)
                .lineLimit(1)
        }
        .padding(.leading, HelmSpace.s5)
        // Hosted outside the pane's own view tree, so the style this reads
        // has to be handed in explicitly rather than inherited.
        .environment(\.helmModuleIconStyle, iconStyle)
        // Flattens the row to one layer before dimming it — without this,
        // `HelmIconPlate`'s own drop shadow keeps its *own* alpha under the
        // opacity above rather than being scaled down with the plate, so the
        // two partly-transparent layers can composite to a higher combined
        // alpha right at the plate's edge than either dims to alone (measured:
        // the row's peak alpha read 0.54/0.58 instead of the requested
        // 0.30/0.33 without this line).
        .compositingGroup()
        .opacity(appearsActive ? 1 : inactiveOpacity)
    }
}

/// **The status word or badge, at the shared name-only bar's trailing
/// edge** — the owner, 2026-09-28: «Давай вернем его в правую часть». A
/// sibling of `NameZoneView` rather than a branch inside it, because the two
/// now live in separate `NSToolbarItem`s (`SettingsToolbar.makeStatusItem`),
/// drawing the two shapes a status has always had — a badge for active,
/// quiet text for idle, nothing for a module with no notion of running — and
/// dimming by the same four numbers (`helmNameZoneInactiveOpacity`) so the
/// two read as one row even though nothing composites them together.
///
/// **The trailing inset is the top gap, not the capsule's 8 pt** — the owner,
/// 2026-09-29: «Бейдж "Активно" / "Не активно" слишком близко находится к
/// правому краю экрана. Отступ сверху и справа должны быть одинаковые».
/// `trailingInset(for:barHeight:)` answers it: the gap from the
/// window's top edge to the drawn top of the badge's fill (or of the quiet
/// word's ink) is what AppKit's vertical centring leaves in a bar
/// `barHeight` tall, and the same distance is put between the drawn right
/// edge and the window's. The actions capsule keeps AppKit's own 8 pt
/// (`HelmToolbarActionsCapsule.edgeMargin`): it is 36 pt tall in a 52 pt
/// bar, so its top gap is that 8 already, and only this item is shorter
/// than the bar by enough to matter.
struct StatusZoneView: View {
    let status: (word: String, active: Bool)?
    let appearsActive: Bool
    let titlebarIsTransparent: Bool
    /// Between the hosted view's own trailing edge and what it draws — see
    /// `trailingInset(for:barHeight:)`.
    let trailingInset: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var inactiveOpacity: Double {
        helmNameZoneInactiveOpacity(dark: colorScheme == .dark, titlebarIsTransparent: titlebarIsTransparent)
    }

    var body: some View {
        Group {
            if let status {
                if status.active {
                    HelmBadge(status.word, tint: HelmSignal.success)
                } else {
                    Text(status.word)
                        .font(.system(size: 11))
                        .foregroundStyle(HelmText.quiet)
                }
            }
        }
        .padding(.trailing, trailingInset)
        .compositingGroup()
        .opacity(appearsActive ? 1 : inactiveOpacity)
        // **Out of VoiceOver on every page with nothing to say** — General,
        // About, Log and every module with no notion of running — since this
        // item is always in the bar's own identifier list, empty or not
        // (`makeStatusItem`'s own header): a placeholder is not a name, and
        // an unnamed control is worse than one that is simply not there.
        .accessibilityHidden(status == nil)
    }
}

extension StatusZoneView {

    /// **The distance AppKit leaves between an `isBordered = false` last
    /// item's own box and the window's trailing edge** — measured, and pinned
    /// by `TheStatusBadgeMovesToTheWindowsTrailingEdgeTests` (box margin 4 pt
    /// at 1060 pt): the 8 pt of a bordered item less the
    /// `HelmToolbarActionsCapsule.edgeMargin` an unbordered one is short.
    private static let boxMargin: CGFloat = 8 - HelmToolbarActionsCapsule.edgeMargin

    /// Where the drawing lies inside its own box, in points from the box's
    /// top and from its trailing edge — read off one offscreen render of the
    /// content with no inset, since a word's ink is not its box (the badge's
    /// fill is the whole box; a quiet word's cap line sits some way under the
    /// box's top and its last letter a fraction short of its right edge, and
    /// both move with the language).
    private struct Ink { let boxHeight: CGFloat, top: CGFloat, trailing: CGFloat }

    /// `nil` where the render draws nothing (an empty status, or a view AppKit
    /// would not photograph): the caller then keeps the capsule's own inset.
    ///
    /// **Measured the way the placed item is laid out and drawn** — inside a
    /// window of its own that is never shown, so `fittingSize` keeps the
    /// backing scale's half points (a window-less hosting view was read, by an
    /// earlier tester, rounding a 56.5 pt word up to 57, and the inset came
    /// out half a point short).
    private static func ink(of status: (word: String, active: Bool)) -> Ink? {
        let host = NSHostingView(rootView: StatusZoneView(status: status, appearsActive: true,
                                                          titlebarIsTransparent: true, trailingInset: 0))
        host.sizingOptions = [.intrinsicContentSize]
        let probe = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                             styleMask: .borderless, backing: .buffered, defer: true)
        probe.isReleasedWhenClosed = false
        probe.contentView = host
        let size = host.fittingSize
        probe.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard size.width > 0, size.height > 0,
              let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8 else { return nil }
        let alphaOffset = rep.bitmapFormat.contains(.alphaFirst) ? 0 : 3
        let scale = CGFloat(rep.pixelsWide) / size.width
        var top = Int.max, right = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where Int(data[y * rep.bytesPerRow + x * 4 + alphaOffset]) > 12 {
                top = min(top, y)
                right = max(right, x)
            }
        }
        guard right >= 0 else { return nil }
        return Ink(boxHeight: size.height, top: CGFloat(top) / scale,
                   trailing: size.width - CGFloat(right + 1) / scale)
    }

    /// **The inset that puts the drawn right edge as far from the window's
    /// right edge as the drawn top is from its top.** The top gap is what
    /// AppKit's centring leaves: `(barHeight - box) / 2` above the box, plus
    /// the ink's own offset inside it (`Ink.top`); `barHeight` is the window
    /// frame less its content layout rect (`SettingsToolbar.barHeight`). The
    /// right gap is `boxMargin` (AppKit's own margin), this inset and the
    /// ink's own trailing bearing, so the inset is the top gap less the other
    /// two.
    ///
    /// A not-a-number bar height (no window yet reads as none at all) and an
    /// unreadable render both keep `HelmToolbarActionsCapsule.edgeMargin`,
    /// the inset this item had before it followed the top; a result outside
    /// `0…barHeight` is clamped, a not-a-number to 0 — no inset is the
    /// nearer of the two wrong answers, an inset that eats the bar is not.
    static func trailingInset(for status: (word: String, active: Bool)?, barHeight: CGFloat?) -> CGFloat {
        guard let status, let barHeight, barHeight.isFinite, barHeight > 0,
              let ink = ink(of: status) else { return HelmToolbarActionsCapsule.edgeMargin }
        let topGap = (barHeight - ink.boxHeight) / 2 + ink.top
        return (topGap - boxMargin - ink.trailing).clamped(to: 0...barHeight, whenNotANumber: 0)
    }
}
