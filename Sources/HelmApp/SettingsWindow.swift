import AppKit
import Combine
import SwiftUI
import HelmRuntime
import HelmUI

/// The settings window: glass with a column of module rows on it, and an opaque
/// card holding the page, built by `SettingsShellViewController` from
/// `ShellContentView`. Each of the two hosts a SwiftUI view; a shared
/// `SettingsModel` carries the selection between them.
///
/// **The window has no `NSToolbar`.** The page's bar is Helm's own
/// (`ShellPageBar`), a view at the top of the card's clip that
/// `ShellContentView` places; the window holds the controller and hands its
/// view to the shell, and the pane below it starts under the bar. The window
/// recalculates its key-view loop itself (`autorecalculatesKeyViewLoop`, in
/// `init`), which is how the bar's views come to be in it.
@MainActor final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let model: SettingsModel
    /// What a page's toolbar content crosses into this target by
    /// (`HelmWindowToolbar.swift` in `HelmUI`) — handed to the detail pane's
    /// environment so a page never needs to import `HelmApp` to publish into
    /// it, and read by `pageBar` on the other side.
    private let toolbarChannel = HelmWindowToolbarChannel()
    private let pageBar: ShellPageBar

    /// One size for every page. Switching pages must never resize the window
    /// under the user's cursor; the size they pick is remembered instead.
    ///
    /// Measured against the two pages that ask for the most. Homebrew's
    /// densest row — name, kind badge, version, description and an action
    /// button — fits from about 940. The Disk screen wants more: its bar needs
    /// 800 pt of pane before the scan statement will show
    /// (`DiskLayout.barWithStatement`), and at 940 the pane, the window less
    /// `ShellGeometry.defaultSidebarWidth` and `ShellGeometry.inset`, is under it, so the
    /// statement never appeared out of the box and nothing suggested widening
    /// the window would reveal it. 1060 clears it.
    ///
    /// Not private: `SidebarComposerSheet` caps itself at this height, because
    /// a sheet is drawn inside this window and the window's own content is the
    /// ceiling. Two literal heights in one target, with a comment claiming they
    /// were the same number, is a comment.
    ///
    /// The height is 760 by the owner's decision, up from 700: the eleventh
    /// module (Screenshots, in Utilities) makes the shipped composer measure 723,
    /// which 700 could not hold. 760 holds the eleven with 37 pt to spare, which
    /// is less than the 40 pt row a twelfth module adds, so a twelfth wants the
    /// window raised again.
    nonisolated static let defaultSize = NSSize(width: 1060, height: 760)
    /// Below this the list rows start truncating names and paths.
    private static let minSize = NSSize(width: 860, height: 540)

    /// `band` is whose band lies under the bar — the running system's
    /// decision unless a test builds another system's window on this one; the
    /// same value sets the title bar below, reaches the pane's
    /// `helmToolbarBackdrop` (`HelmBandChoice`) and tells the bar's zones which
    /// title bar they sit in.
    init(host: ModuleHost, band: HelmBandChoice = .running) {
        let model = SettingsModel(host: host)
        self.model = model
        let transparent = band.titlebarAppearsTransparent
        // The zones are handed to the bar and to nothing else: the window keeps none.
        let tabs = ShellBarTabs(titlebarIsTransparent: transparent)
        let bar = ShellPageBar(model: model, channel: toolbarChannel, tabs: tabs,
                               actions: ShellBarActions(titlebarIsTransparent: transparent),
                               search: ShellBarSearch(titlebarIsTransparent: transparent),
                               titlebarIsTransparent: transparent)
        tabs.barMenu = bar.view.menu
        pageBar = bar
        let shell = SettingsShellViewController(model: model, toolbarChannel: toolbarChannel,
                                                band: band, bar: bar.view)
        let window = NSWindow(contentViewController: shell)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = AppStr.settingsWindowTitle
        // **Load-bearing on the pane, not in the bar.** Transparent, it holds
        // the detail pane's own scroll-edge pocket at opacity 0 — with the
        // flag off that layer stands at opacity 1 over the pane's width —
        // which is the whole reason `helmToolbarBackdrop` exists, and the
        // bar's own backdrop layer does not move with it.
        // `TheSystemsScrollEdgeEffectAttachesTests` is that measurement and
        // holds the two halves of the decision together. On macOS 27 a dev
        // toggle once read the system's own scroll edge instead; shown a
        // screenshot of it, the owner kept Helm's own band there. On macOS 26
        // the owner asked for the system's back, so the flag is off there and
        // the pane draws no band of Helm's — that the system's effect then
        // draws on 26 is inferred from this Mac's 27.2, not measured on 26.
        window.titlebarAppearsTransparent = transparent
        window.titleVisibility = .hidden
        window.setContentSize(Self.defaultSize)
        window.contentMinSize = Self.minSize
        window.center()
        window.isReleasedWhenClosed = false
        // **The window recalculates its key-view loop.** The bar's zones are content views, and the actions
        // host is built anew when another page's actions arrive. In a window that was never shown, with this
        // line removed every row of `TheKeyViewRingRunsSidebarPaneBarTests` is red: Tab from the
        // sidebar's host leaves the first responder at the window. With it, Tab from there lands in the bar's
        // search field, and the raw `nextKeyView` ring closes through sidebar, pane, bar, the bar's zones in
        // `Zone` order with the search zone among them and a rebuilt actions host on it in place of the old one;
        // the family asserts each of these. Pane before bar is the order AppKit gave, accepted and not chosen;
        // why it gives that order is not measured (the two are siblings in the clip with one top-left corner).
        // No `nextKeyView` is set by hand: assumed, not measured in the tree, that a hosting view overwrites a
        // link set on it. Not measured: a key or shown window, Shift-Tab, a pressed key, and anything with
        // keyboard navigation on; the rows do not read that setting and were run with it off, so Tab is shown
        // to reach the search field only, not the tabs, the actions or the sidebar's rows.
        window.autorecalculatesKeyViewLoop = true
        // Remember whatever size the user settles on.
        window.setFrameAutosaveName("HelmSettingsWindow.v4")
        self.window = window
        super.init()
        window.delegate = self
        // Seeds the bar with this window's own, freshly-created state —
        // neither key nor main yet — before the window is shown, rather than
        // leaving it at the bar's default until the first notification below
        // arrives. See the header above this class's four `windowDid…`
        // methods for the signal and `HelmToolbarActionsModel.appearsActive`'s
        // for why it is read here and not from SwiftUI content.
        updateWindowAppearsActive()
        // **The window's title is the page's name**, set here on the
        // `NSWindow` rather than through SwiftUI: the bridge that used to
        // carry a detail pane's toolbar into the window carried its subtitle
        // and dropped its title (measured on macOS 27 — «Untitled» over a
        // pane that had set one), and that reason survives the bridge's own
        // removal — the window's title is still this class's to set. The
        // page says what it is called with `HelmPageTitleKey`; this is the
        // one place that listens.
        titleWatch = model.$pageTitle.sink { [weak self] title in
            self?.applyTitle(title)
        }
        NotificationCenter.default.addObserver(
            forName: .helmPageBarStyleChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTitle(self?.model.pageTitle) }
        }
    }

    private var titleWatch: AnyCancellable?

    /// Writes what the page published as the window's title, and under `.windowTitle` its subtitle too (empty
    /// under `.moduleName`). `titleVisibility` is `.hidden` under both styles: the bar's name zone draws the
    /// name, with the module's plate under `.moduleName` and without it under `.windowTitle`.
    private func applyTitle(_ title: HelmPageTitle?) {
        let style = AppSettings.pageBarStyle
        window.title = title?.title ?? AppStr.settingsWindowTitle
        window.subtitle = style == .windowTitle ? (title?.subtitle ?? "") : ""
        window.titleVisibility = .hidden
    }

    /// `selecting` opens the window on that module's page (used by panel utility rows).
    /// `helm.settings` asks for the settings page itself rather than a module.
    ///
    /// Without it, «Показать» on the panel's permissions notice posted
    /// `.helmOpenSettings` with no object, `show(selecting:)` left the
    /// selection alone, and the window came forward on whatever page somebody
    /// had been reading last — a button that says «Показать» and shows you the
    /// Homebrew package list.
    static let settingsPage = "helm.settings"

    func show(selecting moduleID: String? = nil) {
        if moduleID == Self.settingsPage {
            model.selection = .general
        } else if let moduleID {
            // A module that is off has no row to show where the window is:
            // it opens on General.
            model.selection = ShellSidebarRows.settled(.module(moduleID),
                                                       enabled: model.host.enabledModuleIDs)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Whether AppKit draws this window's chrome active

    /// **The signal AppKit's own toolbar platter follows, read directly off
    /// this window rather than off any SwiftUI content** — not
    /// `\.controlActiveState`, which reads `.inactive` in two states where
    /// AppKit's platter stays lit: a nonactivating panel taking key while this
    /// window stays main, and a sheet, where the private `_hasActiveAppearance`
    /// this window answers for AppKit stays `true` (`isKeyWindow=false`,
    /// `isMainWindow=true` in both).
    ///
    /// `isKeyWindow || isMainWindow` was read alongside `_hasActiveAppearance`
    /// on every `STATE` line four real fixture runs logged, then a fifth set
    /// that hands genuine activation between two processes to reach the same
    /// states for real — S1 through S5, a nonactivating panel taking key, and
    /// a sheet opened, cancelled, begun while the app was away, or ended
    /// while it was away — and the two agreed on every line, sheet included.
    ///
    /// **What this reading cannot see.** `isKeyWindow` and `isMainWindow`
    /// answer only for a *real* window-server transition — a genuine
    /// `activate()`, a real key/main window change — and a test process can
    /// never produce one of its own: calling AppKit's private
    /// `acquireKeyAppearance`/`resignKeyAppearance`/`acquireMainAppearance`/
    /// `resignMainAppearance` moves `_hasActiveAppearance` and AppKit's own
    /// glass but leaves `isKeyWindow`, `isMainWindow`, `NSApp.keyWindow` and
    /// `NSApp.mainWindow` all unchanged and posts none of the four
    /// notifications below. `TheCapsuleDrawsWhatAppKitsPlatterDrawsTests`'s
    /// own rig stands in for the window server for exactly that reason,
    /// driving the private appearance calls and the notifications together
    /// rather than trusting a second reading to cover the gap.
    func windowDidBecomeKey(_ notification: Notification) { updateWindowAppearsActive() }
    func windowDidResignKey(_ notification: Notification) { updateWindowAppearsActive() }
    func windowDidBecomeMain(_ notification: Notification) { updateWindowAppearsActive() }
    func windowDidResignMain(_ notification: Notification) { updateWindowAppearsActive() }

    private func updateWindowAppearsActive() {
        pageBar.setWindowAppearsActive(window.isKeyWindow || window.isMainWindow)
    }
}

// MARK: - Shared model

enum SettingsSelection: Hashable {
    case general
    case module(String)
    case about
    /// On every build — the logging switch lives in this page, so gating the
    /// page would hide the control that turns the log on. Not a module: no
    /// store, no engine, no tour step, no place in `ModuleOrder`, and nothing
    /// counts it among the modules.
    case log
}

@MainActor final class SettingsModel: ObservableObject {
    let host: ModuleHost
    /// `didSet` announces the change a second time, after the value is stored. `@Published` announces in
    /// `willSet`, and the page bar redraws synchronously inside that announcement (`ShellPageBar`'s
    /// `selectionWatch`). Measured in the test process, in a window ordered front: without this `didSet` a
    /// selection that leaves the log for a module page left the pane's page title the log's, and with it the
    /// title is the module's
    /// (`EveryPageNamesTheWindowAfterItselfTests.testASelectionFromTheLogStraightToAModulePageTitlesThePaneWithTheModule`).
    /// That the pane's update ran against the old selection, and that the bar's redraw inside `willSet` is
    /// the cause, are inferred from that, not read.
    @Published var selection: SettingsSelection? = .general {
        didSet { objectWillChange.send() }
    }
    /// What the page on screen calls itself, for the window's title bar.
    @Published var pageTitle: HelmPageTitle?
    /// Bumped when the module order changes, so the sidebar redraws with it —
    /// the order is read from settings, which SwiftUI cannot observe.
    @Published private(set) var orderRevision = 0

    /// Bumped when the interface language changes.
    ///
    /// Every label in this window is a computed property that reads
    /// `AppLanguage.current` at draw time, so the values are already right the
    /// moment the override is set — what is wrong is that nothing asked for
    /// them again. The first attempt bumped a `@State` inside the sidebar,
    /// which redrew the sidebar and left every button in the pane beside it in
    /// the old language: a `@State` reaches its own subtree and no further.
    ///
    /// It lives here because this is the one object both panes observe, and it
    /// is spent on `.id()` rather than on a plain dependency — a re-evaluated
    /// parent may hand a child the same inputs and SwiftUI will keep the view
    /// it already built. A changed identity is the only thing that guarantees
    /// the whole subtree is made again.
    @Published private(set) var languageRevision = 0
    private var liveWatch: AnyCancellable?

    init(host: ModuleHost) {
        self.host = host
        // A module switched off while the window is open leaves the selection
        // on a page no row leads to. The sink reads the store through
        // `enabledModuleIDs`, not `host.live`: `@Published` publishes in
        // `willSet`, so `live` still holds the old set inside it. It closes
        // the difference between the page and the bar after `live` moves, not
        // after the stored flag is written: between the store write
        // (`ModuleHost.swift:56`) and `live[key] = nil` (`:133`) the page
        // already draws General while the bar still reads the raw selection.
        liveWatch = host.$live.sink { [weak self] _ in
            guard let self else { return }
            let settled = ShellSidebarRows.settled(self.selection, enabled: host.enabledModuleIDs)
            if settled != self.selection { self.selection = settled }
        }
        // The model lives as long as the settings window, so the observation
        // needs no teardown — and a deinit cannot touch main-actor state.
        NotificationCenter.default.addObserver(
            forName: .helmLanguageChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.languageRevision += 1 }
        }
        NotificationCenter.default.addObserver(
            forName: .helmModuleOrderChanged, object: nil, queue: .main) { [weak self] _ in
            // In a transaction: the sidebar behind the composer sheet is that
            // sheet's live preview, and a raw bump made its rows appear,
            // vanish and reorder in a single frame while the list in front of
            // them animated. Two lists disagreeing about what just happened.
            MainActor.assumeIsolated {
                withAnimation(HelmMotion.interface) { self?.orderRevision += 1 }
            }
        }
    }
}

// MARK: - Shell controller

/// What the window's content is: the shell's view, with the sidebar and the page
/// hosted in it. A plain view controller; the window's size is the user's and
/// the controller asks nothing of it.
///
/// The page bar's view is handed in and placed by the shell's view; the
/// controller holds no zone and assigns the window no toolbar.
@MainActor final class SettingsShellViewController: NSViewController {
    private let model: SettingsModel
    /// Handed to the detail pane's environment so a page can publish its
    /// toolbar content (`helmWindowToolbar`) without importing `HelmApp` —
    /// `ShellPageBar`, on the other side of it, is `SettingsWindow`'s.
    private let toolbarChannel: HelmWindowToolbarChannel
    /// The window's own band decision, handed down rather than read again —
    /// no default, so the pane cannot be built on one system's decision
    /// under a title bar set from another's.
    private let band: HelmBandChoice
    /// The page bar's view, which the shell places at the top of the card's clip.
    private let bar: ShellPageBarView

    private let fold = SidebarFold()
    private var foldWatch: AnyCancellable?

    init(model: SettingsModel, toolbarChannel: HelmWindowToolbarChannel, band: HelmBandChoice,
         bar: ShellPageBarView) {
        self.model = model
        self.toolbarChannel = toolbarChannel
        self.band = band
        self.bar = bar
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// The view the controller shows, built on first use.
    private(set) lazy var shell: ShellContentView = makeShell()

    override func loadView() {
        view = shell
        // Stage 1 opens expanded; whether the sidebar stays folded across a
        // launch is not remembered. The sink also sets the width once, now.
        foldWatch = fold.$collapsed.sink { [weak self] collapsed in
            self?.shell.sidebarWidth = collapsed
                ? ShellGeometry.railWidth
                : ShellGeometry.sidebarWidth(stored: ShellGeometry.defaultSidebarWidth)
        }
    }

    /// Whether the sidebar is folded to the rail.
    var sidebarCollapsed: Bool {
        get { fold.collapsed }
        set { fold.collapsed = newValue }
    }

    private func makeShell() -> ShellContentView {
        // The window's size belongs to the user. By default NSHostingController
        // feeds SwiftUI's ideal size into auto layout, and any pane whose ideal
        // height is unbounded (Spacer-centred empty states, plain VStacks
        // without a Form) grows the WINDOW to the full screen. Turning the
        // sizing options off makes every pane fill whatever the window gives
        // it and never the other way around.
        let sidebar = NSHostingController(
            rootView: SidebarInTheShell(model: model, fold: fold)
                .modifier(RebuiltOnLanguageChange(model: model))
                // The window survives closing (`isReleasedWhenClosed = false`),
                // so without this both panes went on re-rendering — and keeping
                // memory — for every engine event for as long as the app ran.
                // `OffScreenIdle` in HelmUI has the measurements.
                .helmIdlesOffScreen())
        sidebar.sizingOptions = []

        let detail = NSHostingController(
            rootView: SettingsDetail(model: model)
                // A page publishes its tabs, actions and search through this
                // channel (`HelmWindowToolbar.swift` in `HelmUI`); a page that
                // never does leaves the bar showing its name — plus a
                // status-bearing page's own status under
                // `PageBarStyle.moduleName` — and nothing else
                // (`ShellPageBar.refresh`). The bar exists whether or not any
                // page ever asks it for anything.
                .environment(\.helmWindowToolbarChannel, toolbarChannel)
                // The strip under the bar, lit once the page's content
                // has scrolled beneath it — `helmToolbarBackdrop` says why it
                // is Helm's and not the system's, and on which system it is
                // the system's after all.
                .helmToolbarBackdrop()
                // Outside the backdrop, so the band it draws — or does not —
                // is the decision the window's title bar was set from.
                .environment(\.helmBandChoice, band)
                .onPreferenceChange(HelmPageTitleKey.self) { [model] title in
                    model.pageTitle = title
                }
                .helmTracksPageBarStyle { AppSettings.pageBarStyle }
                .modifier(RebuiltOnLanguageChange(model: model))
                // The pane as well as the sidebar: a module page's header plate
                // and its empty state are module icons too, and «Module icons»
                // is what the switch says.
                .helmTracksModuleIconStyle { AppSettings.sidebarStyle }
                // Same reason as the sidebar's, and this pane is the expensive
                // one: it holds whichever module page was open, and LogView's
                // live tail, when the window was closed.
                .helmIdlesOffScreen())
        // **The pane keeps AppKit's safe area.** The inset above the page is
        // the bar's height: `ShellContentView` adds to the pane's own top safe
        // area, as an additional safe-area inset, what the bar's height needs
        // beyond it; the bar is a view of the card's clip, not a toolbar, and
        // the window has none. No `sceneBridgingOptions` is set
        // on this controller, on purpose: every page says what it wants in
        // its bar through `helmWindowToolbar`, which reaches `ShellPageBar`
        // through `HelmWindowToolbarChannel` and needs no bridge from this
        // controller at all.
        detail.sizingOptions = []
        addChild(sidebar)
        addChild(detail)
        return ShellContentView(sidebar: sidebar.view, pane: detail.view, bar: bar)
    }
}

/// Whether the sidebar is folded to the rail, held in memory by the shell's controller and
/// read by the one hosting view of the sidebar: it is never rebuilt for a fold,
/// so a permission state it has probed stays.
@MainActor private final class SidebarFold: ObservableObject {
    @Published var collapsed = false
}

private struct SidebarInTheShell: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var fold: SidebarFold

    var body: some View {
        ShellSidebar(model: model, collapsed: fold.collapsed) { fold.collapsed.toggle() }
    }
}

// MARK: - Detail

private struct SettingsDetail: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        let tabs = HelmPageToolbarContent(tabs: SettingsTabs.all,
                                          selectedTab: SettingsTabs.binding($model.selection))
        // A module that is off reads as General, as it does in the sidebar,
        // whatever the selection still says.
        switch ShellSidebarRows.settled(model.selection, enabled: model.host.enabledModuleIDs) {
        case .none, .general:
            // The keys are the ones `ShellPageBar.pageKey(for:)` answers for the
            // page; General and About put nothing in their bar but the tabs.
            MenuBarSettingsView()
                .helmWindowToolbar(tabs, token: "general")
        case .about:
            AboutHelmView()
                .helmWindowToolbar(tabs, token: "about")
        case .log:
            LogView(settingsTabs: tabs)
        case .module(let id):
            if let descriptor = ModuleRegistry.all.first(where: { $0.idRaw == id }) {
                ModuleDetailView(host: model.host, descriptor: descriptor, id: id)
            } else {
                // A selection can outlive its module (removed build, stale
                // state). Falling back beats showing an empty pane.
                MenuBarSettingsView()
            }
        }
    }
}

private struct ModuleDetailView: View {
    @ObservedObject var host: ModuleHost
    let descriptor: any ModuleDescriptor
    let id: String

    /// `statusWord`'s own reason to redraw — the badge that used to sit
    /// beside the name here is gone (the owner, 2026-09-28: «Давай вернем
    /// его в правую часть»; `ShellPageBar` draws it now, in `StatusZoneView`, at
    /// the bar's own trailing edge).
    ///
    /// `activity` reads a `@Published` on the module's view model — an object
    /// this view holds and does not observe — so measured, the badge this
    /// once fed changed exactly once per visit to the page: start a session
    /// from the hero, and the countdown ran while the badge two inches above
    /// it still said «Not active», until you left the page and came back.
    /// `statusWord` inherits the same publisher for the same reason, now
    /// feeding only the subtitle the window is given under `.windowTitle`, where `titleVisibility` is `.hidden`.
    ///
    /// `statusChanges` is the publisher for exactly this and already existed
    /// before this view subscribed — `command grep -rn 'statusChanges(live.vm)'
    /// Sources | command grep -v '///'` finds every subscriber.
    @State private var activityRevision = 0

    /// The module's own «my state moved» signal, or nothing for a module that
    /// publishes none — in which case `statusWord` stays nil below.
    private var activityChanges: AnyPublisher<Void, Never> {
        guard let live = host.liveModule(id),
              let changes = descriptor.statusChanges(live.vm) else {
            return Empty().eraseToAnyPublisher()
        }
        return changes
    }

    var body: some View {
        // The header lies **over** the page, and the page scrolls under it —
        // which is where the strip's material and its scroll-edge rule come
        // from. It was a sibling in a `VStack(spacing: 0)`, with nothing
        // passing behind it to blur. `safeAreaInset` reserves the strip's own
        // height, so no page here reserves it and none had to give anything up.
        page
            // Leading, not centre. This alignment governs only content that
            // does not fill the pane, and everything here fills it — a capped
            // column and a non-bleeding header each centre themselves,
            // measured unmoved at 610, 810 and 1400 pt. What it does govern is
            // a row that wants *more* than the pane: centred, the overflow was
            // split between the two edges, so a clipped toolbar hid its path
            // under the sidebar and its buttons off the right. Pinned leading,
            // an overflow spills one way and reads as one.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .helmPageHeader(symbol: descriptor.moduleMetadata.sfSymbol,
                            tint: descriptor.moduleTint.colour,
                            title: descriptor.moduleMetadata.name,
                            subtitle: statusWord,
                            bleeds: descriptor.pageBleeds)
            // `statusWord` reads a value off an object this view does not
            // observe, so without this it is right once per visit and stale
            // after.
            .onReceive(activityChanges) { _ in activityRevision &+= 1 }
    }

    /// The module's status said in words: what the page publishes as its
    /// subtitle, which `SettingsWindow.applyTitle` gives the window under
    /// `.windowTitle`, where `titleVisibility` is `.hidden`. nil for a module
    /// with no notion of running.
    private var statusWord: String? {
        _ = activityRevision
        guard let live = host.liveModule(id), let activity = descriptor.activity(live.vm) else {
            return nil
        }
        switch activity {
        case .active: return AppStr.moduleActive
        case .idle: return AppStr.moduleIdle
        }
    }

    /// The module's own page. A module that is off never gets here: the detail
    /// reads it as General (`ShellSidebarRows.settled`), so there is no empty state
    /// with a switch to write, and no switch on this page either.
    ///
    /// Whether a module exists at all is a settings question, and it is asked
    /// where the sidebar is arranged.
    ///
    /// The page's name is a preference on its content, and a chain hung on no
    /// view publishes none. A module that is enabled in the store and not live
    /// draws nothing of its own, so the `Color.clear` is what still names the
    /// window after it.
    @ViewBuilder private var page: some View {
        if let live = host.liveModule(id) {
            descriptor.settingsPage(live.vm)
        } else {
            Color.clear
        }
    }
}

/// Gives its content a new identity whenever the interface language changes.
///
/// Not a redraw — a rebuild. A view whose inputs have not changed is one
/// SwiftUI is entitled to keep, and every string here is read from a computed
/// property rather than passed in, so nothing about a label's *inputs* changes
/// when the language does. `.id()` is what says «this is a different view now».
private struct RebuiltOnLanguageChange: ViewModifier {
    @ObservedObject var model: SettingsModel

    func body(content: Content) -> some View {
        content.id(model.languageRevision)
    }
}
