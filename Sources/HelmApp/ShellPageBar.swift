import AppKit
import Combine
import SwiftUI
import HelmRuntime
import HelmUI

/// What one zone of the bar is told on every pass. Not Equatable: the content carries closures; a zone
/// compares what it draws.
struct ShellBarZoneState {
    var content: HelmPageToolbarContent?   // nil: the bar shows the name only
    var isLive: Bool                       // false: no handler may run, and `content` holds no page closure
    var isDimmed: Bool                     // the frozen look; never true while isLive
    var appearsActive: Bool                // the window's isKeyWindow || isMainWindow, as handed in
    var appearance: HelmBarAppearance
    var animated: Bool                     // true only when this same page's bar was already shown
    var pageKey: String? = nil             // `ShellPageBar.pageKey(for:)` of the page shown; nil with no content
}

/// One zone with behaviour of its own: tabs, actions or search.
@MainActor protocol ShellBarZone: AnyObject {
    /// The view the bar places, nil while the zone has nothing to place. May change in `show` and in `apply`.
    var view: NSView? { get }
    /// Called on every republication, and again with an equal state after a language or a setting moved:
    /// a zone that reads a setting or a string compares what it draws, not the state it was handed.
    func show(_ state: ShellBarZoneState)
    /// Writes this zone's own fields of the measures and no others, from what `show` last measured;
    /// it measures nothing itself and its answer does not depend on a verdict.
    func measure(into measures: inout ShellPageBarView.Measures)
    /// Called inside the bar's layout pass, before any frame of that pass is
    /// set. The zone may swap `view` here and sees the new view placed in the same pass. It must not call
    /// `measuresMoved` and must not change what `measure(into:)` answers: the pass has already read the
    /// measures and does not read them again.
    func apply(_ verdicts: ShellPageBarView.Verdicts)
    /// Set once by the bar's controller, which holds the zone; the closure captures the
    /// controller weakly, and a zone never holds its controller. The same rule one level up: the bar view
    /// holds `verdictsChanged` and the controller holds the bar view, so that closure captures the controller
    /// weakly too. Called by the zone when its natural width or its search flags moved without a `show`.
    var measuresMoved: (() -> Void)? { get set }
}

/// **The controller of the page bar: it hears the page's channel, the selection and the settings, and tells
/// the bar's three zones what to show.** It owns the page's name and its status (two hosted views, one
/// snapshot), the activity flag and the grace; the zones own their own controls. It writes the bar view's
/// accessibility label, the page's name, on every draw. It is the delegate of the bar view's right-click menu
/// and fills it from the page it shows (`ShellBarMenu`).
///
/// **After the controller is released nothing answers a notification, a channel change or a selection: every
/// observer is removed in `deinit` and every closure it handed out holds it weakly.**
///
/// **A page that has declared before is shown the instant it is selected, whether or not the channel
/// currently has live content for it.** A page's own mount almost always redeclares within the same run-loop
/// turn it appears in, and showing its last-known content rather than a bare name avoids a visible dip to the
/// name on every ordinary visit. A short grace (`graceInterval`) is armed the moment a page that was live a
/// heartbeat ago stops being able to say anything: either because the selection itself just changed to such
/// a page, or because the module the page on screen names has just been switched off without the selection
/// moving. If nothing has declared when it fires, the bar falls to the name and stays there (`fellBack`) until
/// the page is selected once more or declares afresh; a language or setting change does not bring the stale
/// page back. A page that has never declared reads as the name at once. A withdraw with no selection change
/// that names a module still switched on (a language remount tearing the mount down) never starts the
/// fallback: the page stays, frozen, until the next declare.
///
/// **A frozen page holds none of its closures.** `strippedOfClosures` keeps only what a zone needs to draw
/// the page: the page's closures capture its view model, and a bar that kept them kept a switched-off
/// module's view model, and the transport client behind it, alive. A page left while live is stripped the
/// moment the selection leaves it.
///
/// **`refresh` is the one place that decides what the zones are told.** On a selection signal it reads the
/// selection the sink was handed, not `model.selection`: `@Published` publishes in `willSet`, so the property
/// read back is the page being left. Every other trigger fires outside that `willSet`, where the property is
/// right.
///
/// `identity(for:host:)`, `status`, `pageKey(for:)` and `strippedOfClosures` are second copies of
/// `SettingsToolbar`'s `pageIdentity`, `moduleStatus`, `pageKey` and `strippedOfClosures`: both bars are in the
/// tree, and a change to one side is made in the other.
@MainActor final class ShellPageBar: NSObject {

    // MARK: - Values

    /// The symbol, tint, name and status of one page.
    struct Identity {
        var symbol: String
        var tint: Color
        var title: String
        /// The module's own status word and whether it counts as active; nil for every page with no notion of
        /// running.
        var status: (word: String, active: Bool)?
    }

    /// What the two hosts last drew. One snapshot gates both hosts, so a page republishing on every keystroke
    /// hands neither a fresh root view.
    struct Snapshot: Equatable {
        let symbol: String
        let title: String
        /// The "module name" style draws the name.
        let showsName: Bool
        /// nil unless that style and a page with no tabs, no actions and no search.
        let statusWord: String?
        let statusActive: Bool
        let iconStyle: SidebarStyle
        let appearsActive: Bool
        let titlebarIsTransparent: Bool

        init(identity: Identity, style: PageBarStyle, content: HelmPageToolbarContent?,
             iconStyle: SidebarStyle, appearsActive: Bool, titlebarIsTransparent: Bool) {
            symbol = identity.symbol
            title = identity.title
            showsName = style == .moduleName
            let bare = content.map { $0.tabs.isEmpty && $0.actions.isEmpty && $0.search == nil } ?? true
            statusWord = showsName && bare ? identity.status?.word : nil
            statusActive = identity.status?.active ?? false
            self.iconStyle = iconStyle
            self.appearsActive = appearsActive
            self.titlebarIsTransparent = titlebarIsTransparent
        }
    }

    /// What the zones were last told.
    enum Presentation: Equatable {
        case nameOnly
        case page(key: String, isLive: Bool, isDimmed: Bool)
    }

    private enum Trigger {
        case selection(SettingsSelection?)
        case other
    }

    private struct Remembered {
        var content: HelmPageToolbarContent
        var wasLive: Bool
        var isDimmed: Bool
    }

    // MARK: - State

    let view = ShellPageBarView()
    /// An instance value, so a test shrinks its own bar's.
    var graceInterval: TimeInterval = 0.25
    private(set) var presentation: Presentation = .nameOnly
    private(set) var snapshot: Snapshot?

    private let model: SettingsModel
    private let channel: HelmWindowToolbarChannel
    private let tabs: any ShellBarZone
    private let actions: any ShellBarZone
    private let search: any ShellBarZone
    private let titlebarIsTransparent: Bool

    private var remembered: [String: Remembered] = [:]
    private var fellBack: Set<String> = []
    private var graceKey: String?
    private var graceWork: DispatchWorkItem?
    private var currentSelection: SettingsSelection?

    /// Read on init and on the notification that names each, never per republication: a page republishes on
    /// every keystroke.
    private var pageBarStyle: PageBarStyle
    private var sidebarStyle: SidebarStyle
    private var alwaysCollapseSearch: Bool
    private var barAppearance: HelmBarAppearance

    private var appearsActive = true
    private var isApplyingVerdicts = false
    private var refusedMeasuresMoved = false
    /// What the zones were last shown, for a re-show that changes only the activity flag.
    private var shownContent: HelmPageToolbarContent?
    private var shownLive = false
    private var shownDimmed = false

    // Read in `deinit`, which Swift 6 treats as nonisolated even on a `@MainActor` class; only ever touched on
    // the main actor otherwise.
    nonisolated(unsafe) private var watches: [NSObjectProtocol] = []
    private var selectionWatch: AnyCancellable?
    private var activityWatch: AnyCancellable?

    private var nameHost: NSHostingView<NameZoneView>?
    private var statusHost: NSHostingView<StatusZoneView>?
    private var nameWidth: CGFloat = 0
    private var statusWidth: CGFloat = 0

    // MARK: - Init

    init(model: SettingsModel, channel: HelmWindowToolbarChannel,
         tabs: any ShellBarZone, actions: any ShellBarZone, search: any ShellBarZone,
         titlebarIsTransparent: Bool) {
        self.model = model
        self.channel = channel
        self.tabs = tabs
        self.actions = actions
        self.search = search
        self.titlebarIsTransparent = titlebarIsTransparent
        pageBarStyle = AppSettings.pageBarStyle
        sidebarStyle = AppSettings.sidebarStyle
        alwaysCollapseSearch = AppSettings.alwaysCollapseSearch
        barAppearance = AppSettings.barAppearance
        currentSelection = model.selection
        super.init()

        channel.onChange = { [weak self] in self?.refresh(.other) }
        for zone in [tabs, actions, search] {
            zone.measuresMoved = { [weak self] in self?.zoneMeasuresMoved() }
        }
        view.verdictsChanged = { [weak self] verdicts in self?.verdictsChanged(verdicts) }
        view.menu = ShellBarMenu.menu(delegate: self)

        let names: [Notification.Name] = [
            .helmLanguageChanged, .helmPageBarStyleChanged, .helmToolbarSwitcherStyleChanged,
            .helmAlwaysCollapseSearchChanged, .helmModuleEnabled, .helmModuleDisabled,
            .helmSidebarStyleChanged, .helmBarAppearanceChanged,
        ]
        watches = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.heard(name) }
            }
        }
        // The value the sink is handed: the sink fires at once with the current selection, which is the
        // first refresh.
        selectionWatch = model.$selection.sink { [weak self] selection in
            self?.refresh(.selection(selection))
        }
    }

    deinit {
        for watch in watches { NotificationCenter.default.removeObserver(watch) }
        // `graceWork` is not cancelled here: `DispatchWorkItem` is not `Sendable`, so a nonisolated `deinit`
        // cannot touch it. Its closure holds the controller weakly and does nothing once it is gone.
    }

    // MARK: - The window's activity

    /// `isKeyWindow || isMainWindow`, handed in; an equal value is refused.
    func setWindowAppearsActive(_ active: Bool) {
        guard appearsActive != active else { return }
        appearsActive = active
        showZones(content: shownContent, isLive: shownLive, isDimmed: shownDimmed, animated: false)
        draw(Self.identity(for: currentSelection, host: model.host))
    }

    // MARK: - What a page is called

    /// General, Log, About and no selection answer one Settings identity, so the bar's plate does not change
    /// under the three tabs; a module answers its descriptor's and the status `ModuleDetailView.statusWord`
    /// reads; an id nobody holds answers Settings.
    static func identity(for selection: SettingsSelection?, host: ModuleHost) -> Identity {
        let settings = Identity(symbol: "gearshape", tint: .gray, title: AppStr.settingsPane, status: nil)
        switch selection {
        case .none, .general, .about, .log: return settings
        case .module(let id):
            guard let descriptor = ModuleRegistry.descriptor(id) else { return settings }
            return Identity(symbol: descriptor.moduleMetadata.sfSymbol, tint: descriptor.moduleTint.colour,
                            title: descriptor.moduleMetadata.name, status: status(id, descriptor, host: host))
        }
    }

    private static func status(_ id: String, _ descriptor: any ModuleDescriptor,
                               host: ModuleHost) -> (word: String, active: Bool)? {
        guard let live = host.liveModule(id), let activity = descriptor.activity(live.vm) else { return nil }
        switch activity {
        case .active: return (AppStr.moduleActive, true)
        case .idle: return (AppStr.moduleIdle, false)
        }
    }

    /// The token a page passes to `helmWindowToolbar`: a module's id for a module's page, and the literal
    /// General, About and Log each pass for their own.
    static func pageKey(for selection: SettingsSelection?) -> String {
        switch selection {
        case .none, .general: return "general"
        case .about: return "about"
        case .log: return "log"
        case .module(let id): return id
        }
    }

    /// A closure-free copy of `content`. `HelmToolbarAction.perform`, a page's `selectedTab` binding and its
    /// search field's binding and `onSubmit` all close over the page's own view model; a frozen zone is told
    /// `isLive == false`, under which no handler may run (`ShellBarZoneState.isLive`), so none of these closures
    /// is meant to run again. This keeps
    /// only what a frozen zone needs to draw itself: the tabs, the actions' identity and state, and the
    /// search prompt.
    static func strippedOfClosures(_ content: HelmPageToolbarContent) -> HelmPageToolbarContent {
        HelmPageToolbarContent(
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
                                             isOn: isOn, face: action.toggleFace) {}
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

    // MARK: - Notifications

    /// Re-reads the setting the notification names, then answers as any republication does: every zone shown
    /// again, one pass.
    private func heard(_ name: Notification.Name) {
        switch name {
        case .helmPageBarStyleChanged: pageBarStyle = AppSettings.pageBarStyle
        case .helmSidebarStyleChanged: sidebarStyle = AppSettings.sidebarStyle
        case .helmAlwaysCollapseSearchChanged: alwaysCollapseSearch = AppSettings.alwaysCollapseSearch
        case .helmBarAppearanceChanged: barAppearance = AppSettings.barAppearance
        default: break
        }
        refresh(.other)
    }

    // MARK: - Refresh

    private func refresh(_ trigger: Trigger) {
        let previous = Self.pageKey(for: currentSelection)
        var isSelectionSignal = false
        if case .selection(let selection) = trigger {
            currentSelection = selection
            isSelectionSignal = true
        } else {
            currentSelection = model.selection
        }
        let key = Self.pageKey(for: currentSelection)
        let didSwitch = isSelectionSignal && key != previous

        watchActivity()
        if didSwitch {
            cancelGrace()
            // A fresh visit is shown optimistically, even a page whose grace ran out on an earlier visit:
            // falling back said nothing about its next declare.
            fellBack.remove(key)
            // The page left keeps its shape for its next visit and none of its closures.
            if let left = remembered[previous] {
                remembered[previous]?.content = Self.strippedOfClosures(left.content)
            }
        }

        if let content = channel.content(for: AnyHashable(key)) {
            fellBack.remove(key)
            var animated = false
            if case .page(key, _, _) = presentation { animated = true }
            remembered[key] = Remembered(content: content, wasLive: true, isDimmed: false)
            present(.page(key: key, isLive: true, isDimmed: false), content, animated: animated)
            if graceKey == key { cancelGrace() }
        } else if let cached = remembered[key], !fellBack.contains(key) {
            // Both read before this call can overwrite or arm them: a page live a moment ago has just
            // stopped declaring, and a grace already running for it means this call is still inside the
            // window a page switch armed. Without the second, a language change landing inside the grace
            // read `wasLive` as false from the first freeze and dimmed a page about to redeclare.
            let wasLive = cached.wasLive
            let graceArmed = graceKey == key
            let isReturnVisit = (didSwitch && wasLive) || graceArmed
            // Sticky: a second frozen pass never lights a dimmed page again.
            let dimmed = cached.isDimmed || !isReturnVisit
            let stripped = Self.strippedOfClosures(cached.content)
            remembered[key] = Remembered(content: stripped, wasLive: false, isDimmed: dimmed)
            present(.page(key: key, isLive: false, isDimmed: dimmed), stripped, animated: false)
            if wasLive, didSwitch || isModuleSwitchedOff() { armGrace(key) }
        } else {
            present(.nameOnly, nil, animated: false)
        }
    }

    /// Whether the page on screen names a module the host no longer holds live, which is what the person's own
    /// switch leaves; asked only of a page that was live a moment ago. General, About and Log name no module that can be switched off.
    private func isModuleSwitchedOff() -> Bool {
        guard case .module(let id) = currentSelection else { return false }
        return model.host.liveModule(id) == nil
    }

    private func cancelGrace() {
        graceWork?.cancel()
        graceWork = nil
        graceKey = nil
    }

    private func armGrace(_ key: String) {
        graceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.graceKey == key, Self.pageKey(for: self.currentSelection) == key else { return }
            self.graceKey = nil
            self.graceWork = nil
            guard self.channel.content(for: AnyHashable(key)) == nil else { return }
            self.fellBack.insert(key)
            self.present(.nameOnly, nil, animated: false)
        }
        graceKey = key
        graceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + graceInterval, execute: work)
    }

    /// Re-arms `activityWatch` for whichever module the selection names, or drops it where there is none to
    /// watch. A module's own "my state moved" signal redraws the name and the status.
    private func watchActivity() {
        guard case .module(let id) = currentSelection,
              let descriptor = ModuleRegistry.descriptor(id),
              let live = model.host.liveModule(id),
              let changes = descriptor.statusChanges(live.vm) else {
            activityWatch = nil
            return
        }
        watchStatus(of: changes)
    }

    /// Redraws the name and the status on each signal of `changes`. The signal is received on the main queue:
    /// a module's `objectWillChange` fires in `willSet`, and the status read inside the block must see the value
    /// after it landed. Internal so a test hands in a publisher of its own.
    func watchStatus<Changes: Publisher>(of changes: Changes) where Changes.Failure == Never {
        activityWatch = changes.receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            self.draw(Self.identity(for: self.currentSelection, host: self.model.host))
        }
    }

    // MARK: - Presenting

    private func present(_ next: Presentation, _ content: HelmPageToolbarContent?, animated: Bool) {
        presentation = next
        let live: Bool
        let dimmed: Bool
        if case .page(_, let isLive, let isDimmed) = next { live = isLive; dimmed = isDimmed } else { live = false; dimmed = false }
        showZones(content: content, isLive: live, isDimmed: dimmed, animated: animated)
        drawIdentity(Self.identity(for: currentSelection, host: model.host))
        collect()
    }

    private func showZones(content: HelmPageToolbarContent?, isLive: Bool, isDimmed: Bool, animated: Bool) {
        shownContent = content
        shownLive = isLive
        shownDimmed = isDimmed
        let state = ShellBarZoneState(content: content, isLive: isLive, isDimmed: isDimmed,
                                      appearsActive: appearsActive, appearance: barAppearance,
                                      animated: animated,
                                      pageKey: content == nil ? nil : Self.pageKey(for: currentSelection))
        tabs.show(state)
        view.setView(tabs.view, for: .tabs)
        actions.show(state)
        view.setView(actions.view, for: .actions)
        search.show(state)
        view.setView(search.view, for: .search)
    }

    /// Writes the bar's, the name's and the status's accessibility labels on every call, and the name's and
    /// the status's hosts for `identity` when what they draw moved, recollecting the measures then. Internal so a test
    /// draws a status without switching a module on.
    func draw(_ identity: Identity) {
        if drawIdentity(identity) { collect() }
    }

    /// - Returns: whether the snapshot changed, which is when the widths and the hosts' views moved.
    @discardableResult
    private func drawIdentity(_ identity: Identity) -> Bool {
        // Written before the equality guard so a label never lags the page; a host built below gets its label
        // when it is built, since no host exists yet on the first pass.
        let statusWord = identity.status?.word ?? ""
        // This line decides the bar's accessibility label: the page's name.
        view.setAccessibilityLabel(identity.title)
        nameHost?.setAccessibilityLabel(identity.title)
        statusHost?.setAccessibilityLabel(statusWord)
        let next = Snapshot(identity: identity, style: pageBarStyle, content: shownContent,
                            iconStyle: sidebarStyle, appearsActive: appearsActive,
                            titlebarIsTransparent: titlebarIsTransparent)
        guard next != snapshot else { return false }
        snapshot = next

        if next.showsName {
            let root = NameZoneView(symbol: next.symbol, tint: identity.tint, title: next.title,
                                    iconStyle: next.iconStyle, appearsActive: next.appearsActive,
                                    titlebarIsTransparent: next.titlebarIsTransparent)
            let host = nameHost ?? makeHost(root)
            host.rootView = root
            host.setAccessibilityLabel(identity.title)
            nameHost = host
            nameWidth = host.fittingSize.width
            view.setView(host, for: .name)
        } else {
            nameWidth = 0
            view.setView(nil, for: .name)
        }

        if let word = next.statusWord {
            let status = (word: word, active: next.statusActive)
            let root = StatusZoneView(
                status: status, appearsActive: next.appearsActive,
                titlebarIsTransparent: next.titlebarIsTransparent,
                trailingInset: StatusZoneView.trailingInset(for: status, barHeight: ShellBarLayout.height,
                                                            boxMargin: ShellBarLayout.statusTrailing))
            let host = statusHost ?? makeHost(root)
            host.rootView = root
            host.setAccessibilityLabel(statusWord)
            statusHost = host
            statusWidth = host.fittingSize.width
            view.setView(host, for: .status)
        } else {
            // Written as 0, not read from the host: an empty status view is still as wide as its trailing
            // padding, which would make an absent status a present zone.
            statusWidth = 0
            view.setView(nil, for: .status)
        }
        return true
    }

    private func makeHost<Root: View>(_ root: Root) -> NSHostingView<Root> {
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [.intrinsicContentSize]
        return host
    }

    // MARK: - Measures and verdicts

    /// One assignment of the bar's measures: every zone's own fields, the name's and the status's widths, and
    /// the cached setting.
    private func collect() {
        var measures = view.measures
        for zone in [tabs, actions, search] { zone.measure(into: &measures) }
        measures.name = nameWidth
        measures.status = statusWidth
        measures.alwaysCollapseSearch = alwaysCollapseSearch
        view.measures = measures
    }

    private func zoneMeasuresMoved() {
        guard !isApplyingVerdicts else {
            if !refusedMeasuresMoved {
                refusedMeasuresMoved = true
                HelmLog.shared.warn("bar", "a zone reported new measures inside the bar's layout pass; refused")
            }
            return
        }
        collect()
    }

    /// Called inside the bar's layout pass, before any frame of it is set: every zone hears the verdicts, and
    /// the view each now holds is handed to the bar for this same pass.
    private func verdictsChanged(_ verdicts: ShellPageBarView.Verdicts) {
        isApplyingVerdicts = true
        defer { isApplyingVerdicts = false }
        tabs.apply(verdicts)
        actions.apply(verdicts)
        search.apply(verdicts)
        view.setView(tabs.view, for: .tabs)
        view.setView(actions.view, for: .actions)
        view.setView(search.view, for: .search)
    }
}

extension ShellPageBar: NSMenuDelegate {
    /// The bar's menu, filled from what the bar shows at the moment it opens. The bar's view holds the menu;
    /// the menu holds its delegate weakly.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === view.menu else { return }
        ShellBarMenu.fill(menu, showing: shownContent)
    }
}
