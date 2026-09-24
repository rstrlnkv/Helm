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
/// declared, which draws the name and nothing else. `SettingsWindow` owns
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
            watchMagnifierPress()
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
    /// **M1**: catches a press on the magnifier before AppKit's own
    /// `searchButtonClicked:` does, so the tabs are already folded by the
    /// time the field starts growing — see `watchMagnifierPress()`'s own
    /// header for the whole mechanism.
    nonisolated(unsafe) private var magnifierPressMonitor: Any?
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
    /// magnifier measured 22 ms in `scratchpad/probes-mft/` — this is several
    /// such frames, and still far under anything a person reads as a wait.
    static var settleInterval: TimeInterval = 0.1
    /// The current module's own "my state moved" signal, the same one
    /// `ModuleDetailView`'s trailing badge subscribes to — re-armed on every
    /// page change so the name zone's status word does not go stale for the
    /// rest of the visit the way the badge did before it had one
    /// (`ModuleDetailView.activityRevision`'s own history).
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
    }

    /// **A language, label-style or page-bar change** — every one of them can
    /// move the room the tabs need (a longer word, a name zone that appears
    /// or disappears) without the selection itself moving, so the attached
    /// bar's own settle has to run again. Nothing here has to invalidate a
    /// cached reading first: `settle(_:)`'s own prediction reads the bar's
    /// current siblings and measures the switcher off-screen fresh on every
    /// call, so a floor measured under the shape that just changed cannot
    /// survive into this one — there is no such floor kept any more.
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
        if let windowResizeWatch { NotificationCenter.default.removeObserver(windowResizeWatch) }
        if let windowEndLiveResizeWatch { NotificationCenter.default.removeObserver(windowEndLiveResizeWatch) }
        if let splitResizeWatch { NotificationCenter.default.removeObserver(splitResizeWatch) }
        if let magnifierPressMonitor { NSEvent.removeMonitor(magnifierPressMonitor) }
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
        /// What `ModuleDetailView`'s own trailing view drew beside the name —
        /// nil for every page that has no notion of running, exactly as that
        /// view answers nil for the same modules. See `NameZoneView`.
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

    /// The same reading `ModuleDetailView.statusWord` and its trailing badge
    /// take, kept in step here rather than redrawn a third way — nil where
    /// the module answers nil, which is most of them.
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
            actions: content.actions.map {
                HelmToolbarAction(id: $0.id, title: $0.title, symbol: $0.symbol,
                                  isEnabled: $0.isEnabled, isVisible: $0.isVisible) {}
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
        toolbar.centeredItemIdentifiers = content?.tabs.isEmpty == false ? [Self.tabsID] : []
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
    /// here — only the name item is, on the page-bar style. A hidden action
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

    // MARK: - Delegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let bar = barsByToolbarID[ObjectIdentifier(toolbar)] else { return nil }
        switch identifier {
        case Self.nameID: return makeNameItem(bar)
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

    /// A cheap snapshot of what the last `patchName()` actually drew — so a
    /// page republishing on every keystroke (Homebrew's console, `hb`'s own
    /// `@Published`) does not hand `NameZoneView` a fresh root view, and the
    /// hosting view underneath it, on every one of them.
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
    }

    private func makeNameItem(_ bar: PageBar) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.nameID)
        let identity = pageIdentity()
        let hosting = NSHostingView(rootView: NameZoneView(symbol: identity.symbol, tint: identity.tint,
                                                           title: identity.title, status: identity.status,
                                                           iconStyle: AppSettings.sidebarStyle))
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
                                            iconStyle: AppSettings.sidebarStyle)
        return item
    }

    private func patchName(_ bar: PageBar) {
        guard let nameHost = bar.nameHost else { return }
        let identity = pageIdentity()
        let snapshot = NameSnapshot(symbol: identity.symbol, title: identity.title,
                                    statusWord: identity.status?.word,
                                    statusActive: identity.status?.active ?? false,
                                    iconStyle: AppSettings.sidebarStyle)
        bar.nameItem?.label = identity.title
        guard snapshot != bar.lastNameSnapshot else { return }
        bar.lastNameSnapshot = snapshot
        nameHost.rootView = NameZoneView(symbol: identity.symbol, tint: identity.tint,
                                         title: identity.title, status: identity.status,
                                         iconStyle: AppSettings.sidebarStyle)
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
                                                isInteractive: bar.isInteractive, compact: bar.tabsFolded,
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
                                compact: bar.tabsFolded)
                .environment(\.helmSwitcherStyle, AppSettings.toolbarSwitcherStyle)
                .environment(\.helmSetSwitcherStyle, AppSettings.ToolbarSwitcherStyleSetter())
                // A frozen bar's tabs are disabled through `bar.isInteractive`
                // rather than through `bar.isLive` — see `HelmTabsSnapshot`'s
                // own header for why the two must not be conflated — since
                // this custom-view item carries none of
                // `NSToolbarItem.autovalidates`' machinery to disable through.
                .disabled(!bar.isInteractive)
        )
    }

    private func tabsBinding(_ bar: PageBar) -> Binding<String> {
        Binding(get: { [weak bar] in bar?.content?.selectedTab?.wrappedValue ?? "" },
               set: { [weak bar] newValue in bar?.content?.selectedTab?.wrappedValue = newValue })
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
        let compact: Bool
        let selectedID: String?
        init(tabs: [HelmToolbarTab], style: ToolbarSwitcherStyle, isInteractive: Bool, compact: Bool,
             selectedID: String?) {
            ids = tabs.map(\.id); titles = tabs.map(\.title); symbols = tabs.map(\.symbol)
            self.style = style
            self.isInteractive = isInteractive
            self.compact = compact
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
                                        isInteractive: bar.isInteractive, compact: bar.tabsFolded,
                                        selectedID: content.selectedTab?.wrappedValue)
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
            menuItem.isEnabled = bar.isLive
            menuItem.state = tab.id == selected ? .on : .off
            submenu.addItem(menuItem)
        }
        top.submenu = submenu
        item.menuFormRepresentation = top
    }

    @objc private func tabsMenuItemPressed(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let key = attachedPageKey, let bar = pageBars[key], bar.isLive else { return }
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
    /// `searchButtonClicked:` handles it**, so the tabs are already folded by
    /// the time the field starts growing — AppKit's own path cannot be
    /// hooked (an override of `beginSearchInteraction` is never called), so a
    /// local monitor ahead of it is the only way in. Installed once, when the
    /// window is set (`window`'s own `didSet`, alongside
    /// `watchWindowResize()`), and removed in `deinit`.
    private func watchMagnifierPress() {
        if let magnifierPressMonitor { NSEvent.removeMonitor(magnifierPressMonitor) }
        guard window != nil else { magnifierPressMonitor = nil; return }
        magnifierPressMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            let press = FoldPress(event: event)
            return MainActor.assumeIsolated { self?.tookMagnifierPress(press.event) ?? false } ? nil : event
        }
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

        // **Fold on every magnifier press**, per the owner's own words — not
        // only when the tabs would otherwise overflow. Unconditional rather
        // than predicted: folding always precedes `beginSearchInteraction()`
        // below, so the field never grows past a magnifier beside tabs still
        // full — there is nothing for a prediction to decide on this path.
        if field.isHidden, !bar.tabsFolded, let superview = field.superview {
            let point = superview.convert(locationInWindow, from: nil)
            if superview.bounds.contains(point) {
                // A fresh search interaction starting — whatever the last one
                // was refused for is not this one's business. See
                // `UnfoldRefusalKey`'s own header for why a refusal must not
                // outlive the cycle it was recorded against.
                bar.refusedUnfold = nil
                bar.pendingUnfoldFieldWidth = nil
                setTabsFolded(true, bar: bar, layout: .window)
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
    /// resize — called once, alongside `watchMagnifierPress()`, and removed
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
            MainActor.assumeIsolated { self?.scheduleSettleForAttachedBar() }
        }
        windowEndLiveResizeWatch = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSettleForAttachedBar() }
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
    /// is not what `switcherWidths(tabs:style:selectedID:)` needs: measured
    /// against the same switcher hosted in a real toolbar item, in a real
    /// (if never-ordered) window, the bare reading overestimates by 3–57.5 pt
    /// depending on label style and tab count — Text style at four tabs the
    /// worst of it — which is more than `unfoldMargin`
    /// (`scratchpad/probes-unfold/review/p8.log`, this Mac: the same
    /// `HelmToolbarSwitcher` configuration measured both ways side by side).
    /// A toolbar item resolves its content's environment differently from a
    /// bare hosting view with no toolbar or window above it at all — exactly
    /// which environment value accounts for the gap is not something this
    /// comment claims to have isolated — so the fix is to measure inside the
    /// same kind of container the attached item actually is, not to guess at
    /// a correction. The window is real enough for AppKit to lay a toolbar
    /// out in, but `orderBack(nil)` is as far as it ever goes — never
    /// `makeKeyAndOrderFront`, never shown to anyone — and it is reused
    /// across every call precisely so this measurement never touches the
    /// live, attached bar.
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
            super.init()
            window.orderBack(nil)
        }

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
            window.toolbar = nil
            hostView = nil
            return width
        }
    }

    /// One rig for the whole app, not one per `SettingsToolbar` — there is
    /// only ever one settings window, but nothing here depends on that, and a
    /// second instance would just mean a second idle, never-shown window.
    private static let measurementRig = SwitcherMeasurementRig()

    /// **Widths for the same `HelmToolbarSwitcher` configuration the attached
    /// item hosts — measured in a real toolbar item, never the attached
    /// view's own resolved size**, which is the view this decision changes: a
    /// size AppKit has already squeezed reports the squeeze, not the shape
    /// the switcher wants (`CLAUDE.md`'s own rule against measuring the view
    /// a decision changes). `SwitcherMeasurementRig` is what stands in for
    /// the attached item's own rendering context — a bare, unattached
    /// `NSHostingView` is not close enough (that class's own header) — with
    /// the same segments, style and selection the attached switcher is
    /// drawing, so a longer word in the running language, or a longer
    /// selected tab's own label in the compact form, costs what it would
    /// cost the real control.
    private func switcherWidths(tabs: [HelmToolbarTab], style: ToolbarSwitcherStyle,
                                selectedID: String?) -> (compact: CGFloat, full: CGFloat) {
        func width(compact: Bool) -> CGFloat {
            let view = HelmToolbarSwitcher(HelmA11y.whatToShow, selection: .constant(selectedID ?? ""),
                                           segments: tabs.map { HelmSwitcherSegment($0.id, $0.title, symbol: $0.symbol) },
                                           compact: compact)
                .environment(\.helmSwitcherStyle, style)
                .environment(\.helmSetSwitcherStyle, AppSettings.ToolbarSwitcherStyleSetter())
            return Self.measurementRig.measure(AnyView(view))
        }
        return (width(compact: true), width(compact: false))
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
    /// magnifier either, since nothing ever asks it to
    /// (`scratchpad/probes-unfold/review/p5-new.log`, this Mac: after
    /// `endSearchInteraction()` the tabs stayed compact and the field stayed
    /// visible at its resting width, in every round, at every pane width
    /// where a fold had ever happened). `collapsedFieldWidth` is captured the
    /// moment the field is actually seen collapsed — including the very
    /// first `settle()` of a fresh bar, which always starts collapsed — so
    /// this budget predicts what AppKit will *do* if the tabs take the room
    /// back, not what the field happens to look like right now. A field left
    /// with real text after editing ends is a genuine demand and keeps its
    /// current width, per this method's own long-standing rule for that
    /// case.
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

    /// **AppKit's own currently free room around the tabs — the combined
    /// width of the two flexible spaces either side of them, read from where
    /// AppKit actually put the name and actions items, not derived by
    /// subtracting item widths from `offeredRoom()`.** That subtraction
    /// undercounts by 32–42 pt against a real, live window
    /// (`scratchpad/probes-unfold/review/p1.log`, this Mac): the detail
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
    /// regardless of what sits in between, which is what makes the name,
    /// tabs and actions items' positions comparable at all without knowing
    /// that hierarchy by name.
    ///
    /// `nil` when there is no name item to anchor the first gap on (a
    /// page-bar style other than `.moduleName`) or no actions item at all (a
    /// shape with tabs and no actions, which none of Helm's own pages
    /// currently declare) — `predictedSlack(bar:tabsWidth:)`'s own fallback
    /// to the older, `offeredRoom()`-based arithmetic covers both; it is less
    /// accurate but was never observed to *latch*, only to answer slightly
    /// pessimistic.
    private func currentToolbarSlack(_ bar: PageBar) -> CGFloat? {
        guard let nameView = bar.nameItem?.view, let tabsView = bar.tabsItem?.view,
              let actionsView = bar.actionsItem?.view, tabsView.window != nil
        else { return nil }
        let nameMaxX = nameView.convert(NSPoint(x: nameView.bounds.width, y: 0), to: nil).x
        let tabsMinX = tabsView.convert(.zero, to: nil).x
        let tabsMaxX = tabsView.convert(NSPoint(x: tabsView.bounds.width, y: 0), to: nil).x
        let actionsMinX = actionsView.convert(.zero, to: nil).x
        let gapBefore = tabsMinX - nameMaxX
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
        if let slackNow = currentToolbarSlack(bar), let tabsView = bar.tabsItem?.view,
           let searchItem = bar.searchItem {
            let tabsLive = tabsView.frame.width
            let searchLive = searchItem.searchField.frame.width
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

    /// **How long `settle(_:)` keeps refusing an unfold after a search
    /// interaction ends empty, before trusting the field's own frame to have
    /// stopped moving.** Against a bare `NSSearchToolbarItem` with nothing
    /// beside it (`scratchpad/probes-settle/collapse-timing.swift`, this
    /// Mac), `endSearchInteraction()` narrows the field to its magnifier over
    /// ~198–205 ms — but that bare figure is *not* what this wait has to
    /// outlast in Helm's real bar, and crediting it as such was itself a
    /// defect this comment used to repeat: **while the tabs are still
    /// folded, the field does not narrow toward its magnifier at all — it
    /// keeps the room the fold freed**, and it is settling into *that* wider
    /// rest, not shrinking to anything small, for as long as this wait runs.
    /// Read directly off this exact bar
    /// (`scratchpad/probes-settle/review/probe4-gate-1.log`,
    /// `probe3-nogate-1.log`, 646 pt, Russian): `controlTextDidEndEditing`
    /// fires with the field still at its wide, mid-edit frame (`width=240.0`
    /// at 1078.5 ms / 1063.9 ms into each log), and the field's own
    /// `frameDidChangeNotification` (M2) keeps firing — each one re-arming
    /// `scheduleSettle(_:)` — until it stops moving at `162.5` pt some
    /// 200–215 ms later (1293.7 ms / 1264.2 ms): still folded, still far
    /// wider than a magnifier, but finally *stable*, which is the one
    /// property `predictedSlack(bar:tabsWidth:)`'s live-minus-live arithmetic
    /// actually needs from it. Deciding on an earlier, still-narrowing
    /// reading is what overstates the room a fold would free and is what
    /// asked AppKit to lay the tabs out full beside a field mid-shrink in the
    /// first place. 300 ms is that measured ~200–215 ms plus a margin for a
    /// real toolbar's own heavier layout, not the bare figure. This is a
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
    /// (`scratchpad/probes-settle/review/second/probeA-2.log`, lines 187–274,
    /// this Mac). What actually bounds it to one interaction is explicit:
    /// `searchFieldFrameChanged`'s own reading of the field's growth against
    /// `preferredWidthForSearchField` (its header says why this, and not a
    /// delegate call or a `settle(_:)` branch, is the reliable signal) clears
    /// `bar.refusedUnfold` the moment a *new* interaction opens, whatever
    /// state the tabs were left in by the last one, and `tookMagnifierPress`
    /// clears it earlier still on the path where the field was genuinely
    /// hidden beforehand, so a refusal never outlives the cycle that earned
    /// it — a build with the read half of this gate disabled
    /// (nothing here ever refuses, only records) recovered to four segments
    /// on every one of the same four rounds instead
    /// (`scratchpad/probes-settle/review/second/probeC-noread.log`), which is
    /// the outcome the explicit clearing above restores without giving up
    /// the gate itself.
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
    /// still folded (measured, this Mac,
    /// `scratchpad/probes-settle/review/probe3-nogate-1.log`: `fieldW=162.5`
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

    /// **The one place that decides whether the tabs should be full or
    /// compact, and the one place that records `PageBar.rest`.** Runs only on
    /// the bar that is still attached by the time it fires, and never while
    /// the search field is mid-edit — reopening a field somebody is typing
    /// into is `patchSearch`'s own rule, restated here for the same reason. A
    /// field left with text after editing ends stays wide; the prediction
    /// below is what decides whether the full tabs still fit beside that
    /// width, so nothing here has to special-case a non-empty field.
    ///
    /// **No trial against the live bar any more.** `switcherWidths(tabs:style:
    /// selectedID:)` and `predictedSlack(bar:tabsWidth:)` answer from an
    /// off-screen switcher and the bar's own siblings, so the decision below
    /// either unfolds once, correctly, or does not unfold at all — never
    /// unfolds and watches AppKit refuse it.
    ///
    /// **Two gates in front of the unfold itself, on top of that
    /// prediction.** `PageBar.searchClosingDeadline`
    /// (`controlTextDidEndEditing`'s own header) is the first: a search that
    /// just ended empty starts an independent AppKit collapse animation this
    /// prediction cannot see the end of, so an unfold decided before the
    /// deadline passes is deferred rather than acted on — `scheduleSettle(_:)`
    /// is re-armed by every one of the field's own frame changes (M2), so the
    /// very next tick after the field actually catches up tries again.
    /// `UnfoldRefusalKey` is the second, and the one that holds even if the
    /// first judges wrong: a room this exact field width has evicted the tabs
    /// from once already is not retried until the room, the field's width,
    /// the language or the switcher style has actually moved — see
    /// `checkOverflow()` for where that gets recorded. Together the two are
    /// what keep a wrong decision to at most one visible blink rather than a
    /// repeating flicker.
    private func settle(_ bar: PageBar) {
        guard let key = attachedPageKey,
              key == Self.nameOnlyKey ? bar === nameOnlyBar : pageBars[key] === bar
        else { return }
        guard let searchItem = bar.searchItem else {
            bar.rest = (true, offeredRoom())
            return
        }
        guard searchItem.searchField.currentEditor() == nil else { return }
        // **A search still opening is not yet settled**, even in the gap
        // before AppKit's own field editor arrives — see `PageBar
        // .searchOpening`'s own header for why the editor guard above is not
        // enough by itself.
        guard !bar.searchOpening else { return }

        if let content = bar.content, !content.tabs.isEmpty {
            let (_, full) = switcherWidths(tabs: content.tabs, style: AppSettings.toolbarSwitcherStyle,
                                           selectedID: content.selectedTab?.wrappedValue)
            let slack = predictedSlack(bar: bar, tabsWidth: full)
            if bar.tabsFolded, slack >= Self.unfoldMargin {
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
                    let fieldWidth = searchItem.searchField.frame.width
                    let context = unfoldContext(bar, fieldWidth: fieldWidth)
                    if bar.refusedUnfold == context {
                        gateRefusedCount += 1
                    } else {
                        recordGateUnfoldFieldWidth(fieldWidth)
                        setTabsFolded(false, bar: bar, layout: .window)
                        bar.lastOurUnfoldAt = Date()
                        // **What `checkOverflow()` promotes into a refusal if
                        // AppKit evicts this very unfold** — not re-read
                        // there, where the field is already mid-shrink one
                        // hop later (`unfoldContext(_:fieldWidth:)`'s own
                        // header). Set beside `lastOurUnfoldAt` since both are
                        // read together, on the attribution condition below.
                        bar.pendingUnfoldFieldWidth = fieldWidth
                    }
                }
            } else if !bar.tabsFolded, slack < Self.foldMargin {
                setTabsFolded(true, bar: bar, layout: .window, reseat: !(bar.tabsItem?.isVisible ?? true))
            }
        }
        bar.rest = (searchItem.searchField.isHidden, offeredRoom())
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
        // several full press-close cycles, this Mac
        // (`scratchpad/probes-settle/review/second/probeFix-2.log`) — and
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
        // across every recorded eviction this session
        // (`scratchpad/probes-settle/review/second/probeFix-3.log`), which
        // is what makes this threshold — not merely "the field grew" — safe
        // to fire unconditionally.
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
        // click, well past the frame that matters here).
        if width > bar.lastFieldWidth, !bar.tabsFolded, bar.rest?.collapsed == true,
           bar.content?.tabs.isEmpty == false, offeredRoom() == bar.rest?.room {
            // Same reason as M1's own fold-and-open branch above: a fresh
            // interaction starting through this path (keyboard, VoiceOver)
            // must not inherit a stale refusal either.
            bar.refusedUnfold = nil
            bar.pendingUnfoldFieldWidth = nil
            bar.searchOpening = true
            setTabsFolded(true, bar: bar, layout: .hostOnly)
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
            guard self != nil, let bar, bar.isLive else { return }
            bar.content?.actions.first { $0.id == id }?.perform()
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
            model.setDeclared(content.actions.map {
                HelmToolbarActionsModel.Entry(id: $0.id, title: $0.title, symbol: $0.symbol,
                                              isEnabled: $0.isEnabled)
            })
            model.setVisibleIDs(content.actions.filter(\.isVisible).map(\.id))
        }
        let hosting = NSHostingView(rootView: HelmToolbarActionsCapsule(model))
        hosting.sizingOptions = [.intrinsicContentSize]
        item.view = hosting
        // Not a plain image item any more, so no second AppKit glass behind
        // the SwiftUI one it now draws for itself (`isBordered = true` wraps
        // the hosted view in AppKit's own bordered chrome — measured).
        item.isBordered = false
        item.label = HelmA11y.moreActions
        bar.actionsModel = model
        bar.actionsHost = hosting
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
            model.setDeclared(content.actions.map {
                HelmToolbarActionsModel.Entry(id: $0.id, title: $0.title, symbol: $0.symbol,
                                              isEnabled: $0.isEnabled)
            })
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

    private func actionMenuItem(_ action: HelmToolbarAction, bar: PageBar) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: #selector(actionMenuItemPressed(_:)),
                              keyEquivalent: "")
        item.target = self
        item.representedObject = action.id
        item.isEnabled = action.isEnabled && bar.isLive
        return item
    }

    @objc private func actionMenuItemPressed(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let key = attachedPageKey, let bar = pageBars[key], bar.isLive else { return }
        bar.content?.actions.first { $0.id == id }?.perform()
    }

    // MARK: - Search

    private func makeSearchItem(_ bar: PageBar) -> NSSearchToolbarItem {
        let item = NSSearchToolbarItem(itemIdentifier: Self.searchID)
        // "The field should be configured before assigned" (`NSSearchToolbarItem.h`)
        // — built here and handed over once, rather than mutated on the
        // default field the item starts with.
        let field = NSSearchField()
        field.sendsWholeSearchString = true
        // `sendsWholeSearchString` governs keystrokes only; the field still
        // fires its action on losing first responder regardless
        // (`NSCell.sendsActionOnEndEditing`, on by default), which
        // `endSearchInteraction` calls into whenever the field folds back to
        // a magnifier or focus simply moves elsewhere — measured against this
        // exact field: `endEditing` fired the action with `sendsWholeSearchString`
        // left at its default *and* set. Off, only the field editor's own
        // `insertNewline(_:)` — a Return — reaches `searchSubmitted`.
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
        item.searchField = field
        // AppKit's own default reads "Search" in its own language, never
        // this app's — said in this app's words, and kept current on a
        // language change through `patchSearch()`.
        item.label = HelmA11y.searchField
        item.paletteLabel = HelmA11y.searchField
        item.toolTip = HelmA11y.searchField
        bar.searchItem = item
        watchSearchFieldFrame(bar, field: field)
        return item
    }

    private func patchSearch(_ bar: PageBar) {
        guard let item = bar.searchItem else { return }
        item.label = HelmA11y.searchField
        item.paletteLabel = HelmA11y.searchField
        item.toolTip = HelmA11y.searchField
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
        }
    }

    @objc private func searchSubmitted(_ sender: NSSearchField) {
        guard let key = attachedPageKey, let bar = pageBars[key],
              bar.searchItem?.searchField === sender else { return }
        bar.content?.search?.text.wrappedValue = sender.stringValue
        guard !sender.stringValue.isEmpty else { return }
        bar.content?.search?.onSubmit?()
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
    /// **A field left empty is about to start its own collapse animation
    /// this class cannot see the end of** — `bar.searchClosingDeadline`
    /// (`PageBar`'s own header) is armed here, for `settle(_:)`'s own wait
    /// gate to read; a field left with text stays wide and is a genuine
    /// demand, not a collapse in progress, so nothing is armed for it.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField,
              let key = attachedPageKey, let bar = pageBars[key],
              field === bar.searchItem?.searchField else { return }
        bar.searchOpening = false
        if field.stringValue.isEmpty {
            bar.searchClosingDeadline = Date().addingTimeInterval(Self.searchCollapseWait)
        }
        scheduleSettle(bar)
    }
}

/// **What decides whether a cached bar can be reused as it stands, or must be
/// rebuilt as a fresh `NSToolbar`.** Everything here can change without a
/// page ever redeclaring — `pageBarStyle` from a `defaults write`, and the
/// tab/action id lists and whether search exists come from whichever content
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

    init(content: HelmPageToolbarContent?) {
        pageBarStyle = AppSettings.pageBarStyle
        tabIDs = content?.tabs.map(\.id) ?? []
        actionIDs = content?.actions.map(\.id) ?? []
        hasSearch = content?.search != nil
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
    /// **What the bar looked like the last time `settle(_:)` or `show(_:key:)`
    /// finished measuring it** — whether the search field was
    /// collapsed to its magnifier, and the room offered at that moment. M2
    /// reads this to tell "the magnifier was pressed and the field is
    /// opening" apart from "the window widened and the field re-opened at
    /// rest with more room already available", which is the same growing
    /// frame either way.
    var rest: (collapsed: Bool, room: CGFloat)?
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
    nonisolated(unsafe) var fieldFrameWatch: NSObjectProtocol?
    var actionsModel: HelmToolbarActionsModel?
    var actionsHost: NSHostingView<HelmToolbarActionsCapsule>?
    var actionsItem: NSToolbarItem?
    var searchItem: NSSearchToolbarItem?

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

/// The name zone's own view: the module's plate, its name and its status, the
/// way `PageBarStyle`'s `.moduleName` arm and `ModuleDetailView`'s trailing
/// view drew them before the bridge — reused here rather than redrawn, to the
/// letter of size, spacing and which shape each state gets: a badge for
/// active, quiet text for idle, nothing for a module with no notion of
/// running at all.
struct NameZoneView: View {
    let symbol: String
    let tint: Color
    let title: String
    let status: (word: String, active: Bool)?
    let iconStyle: SidebarStyle

    var body: some View {
        HStack(spacing: HelmSpace.s5) {
            HelmIconPlate(symbol: symbol, tint: tint, size: 24)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.2)
                .lineLimit(1)
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
        .padding(.leading, HelmSpace.s5)
        // Hosted outside the pane's own view tree, so the style this reads
        // has to be handed in explicitly rather than inherited.
        .environment(\.helmModuleIconStyle, iconStyle)
    }
}
