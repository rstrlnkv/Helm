import AppKit
import Combine
import SwiftUI
import HelmRuntime
import HelmUI
import HelmAppStrings

/// The settings window: the ground of the stored look (`HelmBarAppearance`) with a column of module rows on it, and an opaque
/// card holding the page, built by `SettingsShellViewController` from
/// `ShellContentView`. Each of the two hosts a SwiftUI view; a shared
/// `SettingsModel` carries the selection between them.
///
/// **The header row is the card's, and only the page tabs are a system toolbar item, under Glass**
/// (Architecture/TheSettingsWindow.md, Architecture/ThePageHeader.md § How the page reaches the toolbar).
@MainActor final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let model: SettingsModel
    /// The page tabs' toolbar, worn under both looks, with items under Liquid Glass only (`SettingsToolbar`).
    private let toolbar: SettingsToolbar
    /// One size for every page. Switching pages must never resize the window
    /// under the user's cursor; the size they pick is remembered instead.
    ///
    /// The width is `minSize` and a margin of 4. It also clears the pages
    /// that ask most of the pane: Homebrew's densest row, and Disk's bar, which
    /// needs 800 pt of pane before the scan statement shows
    /// (`DiskLayout.barWithStatement`); nothing would suggest widening the
    /// window to reveal it.
    ///
    /// Not private: `SidebarComposerSheet` caps itself at this height, because
    /// a sheet is drawn inside this window and the window's own content is the
    /// ceiling. One number, not two literals that must agree.
    ///
    /// The height is the owner's decision: it holds the composer with every
    /// module listed.
    nonisolated static let defaultSize = NSSize(width: 1211, height: 760)
    /// Below this the Log page's header row, the fullest one, no longer fits the card in German with its tabs
    /// labelled by glyph and word (`HeaderTabLabels.iconsAndText`, the widest of the three labellings).
    ///
    /// **1207 is that row in German at the default sidebar** (`ShellGeometry.defaultSidebarWidth`, 200, which
    /// nothing in the window changes): «Einstellungen», the tabs «Grundlagen | Protokoll | Über Helm» each with its
    /// glyph, five actions and the search at `HelmHeaderSearch.width`, read from `HelmReadout ax` frames with
    /// `-module.app.toolbarSwitcherStyle iconsAndText`. The name and the tab group are what change with the
    /// language, and German's are the widest of the eight (426). The rest is the same in all eight: 14 + 24 plate
    /// + 12 + the name + 36 (`HeaderRowLayout.nameGap`: 12, 12, 12) + the tabs + 8 + 471 (five 36 pt actions, 8,
    /// the search's 283) + 10, which is 575 + 426 = 1001; the card is the window less 200 of sidebar and 4 of
    /// window inset, so 1205, and 2 more for a frame rounded to whole points. The search cannot give way instead.
    private static let minSize = NSSize(width: 1207, height: 540)

    /// The header row's band is the running system's decision (`HelmBandChoice.running`), handed to the pane.
    init(host: ModuleHost) {
        let band = HelmBandChoice.running
        let model = SettingsModel(host: host)
        self.model = model
        let toolbar = SettingsToolbar()
        self.toolbar = toolbar
        let shell = SettingsShellViewController(model: model, band: band, tabs: toolbar.sink)
        let window = NSWindow(contentViewController: shell)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = AppStr.settingsWindowTitle
        // Transparent on every system: the header row is the card's, and no title bar material may sit
        // over it.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(Self.defaultSize)
        window.contentMinSize = Self.minSize
        window.center()
        window.isReleasedWhenClosed = false
        // Remember whatever size the user settles on.
        window.setFrameAutosaveName("HelmSettingsWindow.v4")
        self.window = window
        super.init()
        window.delegate = self
        toolbar.attach(to: window)
        // **The window's title is the page's name**, set here on the
        // `NSWindow` rather than through SwiftUI, so it is this class's to
        // set. The page says what it is called with `HelmPageTitleKey`; this is the
        // one place that listens.
        titleWatch = model.$pageTitle.sink { [weak self] title in
            self?.applyTitle(title)
        }
    }

    private var titleWatch: AnyCancellable?

    /// Writes what the page published as the window's title. `titleVisibility` is `.hidden`, written once by the
    /// initialiser: the card's header row draws the name, and the title stays the window's (the Window menu and
    /// Mission Control name the window by it).
    private func applyTitle(_ title: String?) {
        window.title = title ?? AppStr.settingsWindowTitle
    }

    /// `selecting` opens the window on that module's page (used by panel utility rows).
    /// `helm.settings` asks for the settings page itself rather than a module:
    /// the panel's permissions notice must land on General, not on whatever
    /// page was read last.
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
        bringForward()
    }

    /// Opens the window on exactly this page, whatever the page is: Log and About
    /// too, which `show(selecting:)` cannot name (`LaunchPage`).
    func show(page: SettingsSelection) {
        model.selection = page
        bringForward()
    }

    /// Whether this window is in `HostWindow`'s count of open windows. A flag, not `isVisible`: `show` is
    /// called again while the window is open, and a miniaturised window is not visible and still open.
    private var counted = false

    private func bringForward() {
        if !counted {
            counted = true
            HostWindow.windowOpened()
        }
        watchHeaderPresses()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // A window ordered front without the app's activation gets no key or main notification until
        // one comes, so its chrome would not dim: read it now.
        updateWindowAppearsActive()
    }

    func windowWillClose(_ notification: Notification) {
        stopWatchingHeaderPresses()
        if counted {
            counted = false
            HostWindow.windowClosed()
        }
    }

    // MARK: - The header row's right-click menu

    /// Read in `deinit`, which Swift 6 treats as nonisolated even on a main-actor class.
    nonisolated(unsafe) private var headerPressMonitor: Any?

    deinit {
        if let headerPressMonitor { NSEvent.removeMonitor(headerPressMonitor) }
    }

    /// One press, across the line between a monitor's `@Sendable` handler and the main actor it already runs on.
    private struct HeaderPress: @unchecked Sendable {
        let event: NSEvent
    }

    /// **A local monitor, installed while the window is shown and removed when it closes** (`deinit` too): the
    /// header row lies in the title bar zone, where AppKit takes a right-click before the hosting view
    /// (`HeaderBarMenu`'s header). A press the menu takes is swallowed, any other goes on.
    private func watchHeaderPresses() {
        guard headerPressMonitor == nil else { return }
        headerPressMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            let press = HeaderPress(event: event)
            let taken = MainActor.assumeIsolated { self?.popUpHeaderMenu(press.event) ?? false }
            return taken ? nil : event
        }
    }

    private func stopWatchingHeaderPresses() {
        if let headerPressMonitor { NSEvent.removeMonitor(headerPressMonitor) }
        headerPressMonitor = nil
    }

    /// Pops the menu up if `event` is the gesture on the header row; whether it did.
    private func popUpHeaderMenu(_ event: NSEvent) -> Bool {
        guard event.window === window, let content = window.contentView,
              let shell = (window.contentViewController as? SettingsShellViewController)?.shell else { return false }
        let card = shell.paneFrameInWindow
        let band = NSRect(x: card.minX, y: card.maxY - HelmCardHeaderBand.height,
                          width: card.width, height: HelmCardHeaderBand.height)
        guard HeaderBarMenu.opens(type: event.type, modifiers: event.modifierFlags, at: event.locationInWindow,
                                  band: band, excluding: HeaderBarMenu.excluded(in: window)) else { return false }
        let menu = HeaderBarMenu.menu(hasTabs: model.pageHasTabs, hasSearch: model.pageHasSearch)
        NSMenu.popUpContextMenu(menu, with: event, for: content)
        return true
    }

    // MARK: - Whether AppKit draws this window's chrome active

    /// **The signal AppKit's own toolbar platter follows, read directly off
    /// this window rather than off any SwiftUI content** — not
    /// `\.controlActiveState`, which reads `.inactive` in two states where
    /// AppKit's platter stays lit: a nonactivating panel taking key while this
    /// window stays main, and a sheet (`isKeyWindow=false`, `isMainWindow=true`
    /// in both). `isKeyWindow || isMainWindow` agrees with AppKit's private
    /// `_hasActiveAppearance` in every such state, sheets included.
    ///
    /// **What this reading cannot see.** `isKeyWindow` and `isMainWindow`
    /// answer only for a real window-server transition, which a test process
    /// cannot produce on its own: AppKit's private `acquireKeyAppearance` and
    /// its siblings move `_hasActiveAppearance` and AppKit's own glass but
    /// leave both unchanged and post none of the four notifications below.
    func windowDidBecomeKey(_ notification: Notification) { updateWindowAppearsActive() }
    func windowDidResignKey(_ notification: Notification) { updateWindowAppearsActive() }
    func windowDidBecomeMain(_ notification: Notification) { updateWindowAppearsActive() }
    func windowDidResignMain(_ notification: Notification) { updateWindowAppearsActive() }

    private func updateWindowAppearsActive() {
        let active = window.isKeyWindow || window.isMainWindow
        (window.contentViewController as? SettingsShellViewController)?.shell.setWindowAppearsActive(active)
        model.windowAppearsActive = active
    }
}

// MARK: - Shared model

enum SettingsSelection: Hashable {
    case general
    case module(String)
    case about
    /// On every build — the logging switch lives in this page, so gating the
    /// page would hide the control that turns the log on. Not a module: no
    /// store, no engine, no tour step, no place in `SidebarLayout`, and nothing
    /// counts it among the modules.
    case log
}

@MainActor final class SettingsModel: ObservableObject {
    let host: ModuleHost
    @Published var selection: SettingsSelection? = .general
    /// What the page on screen calls itself, for the window's title bar.
    @Published var pageTitle: String?
    /// `SettingsWindow.updateWindowAppearsActive()`'s reading, for the header row's and the sidebar rows' dimming
    /// (`\.helmWindowAppearsActive`). True until the window is first brought forward, which reads it
    /// (`SettingsWindow.bringForward()`); the window is built to be shown.
    @Published var windowAppearsActive = true
    /// Bumped when the module order changes, so the sidebar redraws with it —
    /// the order is read from settings, which SwiftUI cannot observe.
    @Published private(set) var orderRevision = 0

    /// Bumped when the interface language changes.
    ///
    /// Every label in this window is a computed property that reads
    /// `AppLanguage.current` at draw time, so the values are right the moment
    /// the override is set; what is missing is a reason to ask for them again.
    ///
    /// It lives here because this is the one object both panes observe (a
    /// `@State` reaches its own subtree and no further), and it is spent on
    /// `.id()` rather than on a plain dependency: a re-evaluated parent may
    /// hand a child the same inputs and SwiftUI will keep the view it built.
    @Published private(set) var languageRevision = 0
    private var liveWatch: AnyCancellable?

    /// Whether the page on screen declared tabs in its header row, mirrored from what the row draws
    /// (`HelmPageHeaderFactsKey`, through `mirrorsHeaderFacts`): a module's page declares its own (Homebrew's three,
    /// Leftovers' two only while its list is not empty), General, Log and About the settings tabs.
    @Published var pageHasTabs = false
    /// Whether it declared a search (`HelmPageHeaderFactsKey`): the menu's Always Collapse Search is offered only then.
    @Published var pageHasSearch = false

    init(host: ModuleHost) {
        self.host = host
        // A module switched off while the window is open leaves the selection
        // on a page no row leads to. The sink reads the store through
        // `enabledModuleIDs`, not `host.live`: `@Published` publishes in
        // `willSet`, so `live` still holds the old set inside it. Between the
        // store write (`ModuleHost.setEnabled`) and `live[key] = nil`
        // (`ModuleHost.disable`) the page already draws General while the bar
        // still reads the raw selection; this closes that gap.
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
            // sheet's live preview, and it must animate with the list in front.
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
/// The controller assigns the window no toolbar itself: only the row's tabs are handed to the window's
/// toolbar under Glass (`SettingsToolbar`, through `tabs`).
@MainActor final class SettingsShellViewController: NSViewController {
    private let model: SettingsModel
    /// The window's own band decision, handed down rather than read again —
    /// no default, so the pane cannot be built on one system's decision
    /// under a title bar set from another's.
    private let band: HelmBandChoice
    /// Where the row's tabs go under Glass (`SettingsToolbar`).
    private let tabs: HelmTabsSink

    private let fold = SidebarFold()

    /// Where the fold state is remembered (`AppSettings.sidebarCollapsed(in:)`).
    private let store = AppSettings.store

    init(model: SettingsModel, band: HelmBandChoice, tabs: HelmTabsSink) {
        self.model = model
        self.band = band
        self.tabs = tabs
        super.init(nibName: nil, bundle: nil)
        fold.collapsed = AppSettings.sidebarCollapsed(in: store)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// The view the controller shows, built on first use.
    private(set) lazy var shell: ShellContentView = makeShell()

    override func loadView() {
        view = shell
        shell.fold(to: width(collapsed: fold.collapsed), animated: false)
    }

    /// A person's flip of the sidebar, from the sidebar's own control: the state is written to the
    /// store first, then the width travels (`ShellContentView.fold(to:animated:)`) and the rows'
    /// flag changes inside the animation that goes with it; where the width was cut, the flag is
    /// written plainly.
    func flipSidebar() {
        let collapsed = !fold.collapsed
        AppSettings.setSidebarCollapsed(collapsed, in: store)
        if shell.fold(to: width(collapsed: collapsed), animated: true) {
            withAnimation(HelmMotion.sidebarFold) { fold.collapsed = collapsed }
        } else {
            fold.collapsed = collapsed
        }
    }

    private func width(collapsed: Bool) -> CGFloat {
        collapsed ? ShellGeometry.railWidth : ShellGeometry.defaultSidebarWidth
    }

    private func makeShell() -> ShellContentView {
        // The window's size belongs to the user. By default NSHostingController
        // feeds SwiftUI's ideal size into auto layout, and any pane whose ideal
        // height is unbounded (Spacer-centred empty states, plain VStacks
        // without a Form) grows the WINDOW to the full screen. Turning the
        // sizing options off makes every pane fill whatever the window gives
        // it and never the other way around.
        let sidebar = NSHostingController(
            rootView: SidebarInTheShell(model: model, fold: fold) { [weak self] in self?.flipSidebar() }
                .safeAreaPadding(.top, ShellGeometry.titleBand)
                .modifier(RebuiltOnLanguageChange(model: model))
                // Its own hosting controller, its own root: the pane's environment stops at the pane.
                .helmRoot()
                // The window survives closing (`isReleasedWhenClosed = false`),
                // so without this both panes would go on re-rendering, and
                // keeping memory, for every engine event (`OffScreenIdle`).
                .helmIdlesOffScreen())
        sidebar.sizingOptions = []
        // The toolbar grows the title bar's safe area, and the sidebar would start lower: it takes none
        // from the title bar and holds the title bar's own band instead, the same under both looks.
        sidebar.safeAreaRegions = []

        let detail = NSHostingController(
            rootView: SettingsDetail(model: model)
                // The look of the header row's tabs and actions, from the stored choice and live
                // (`HelmBarAppearance`).
                .helmTracksBarAppearance { AppSettings.barAppearance }
                // How the row names its page and labels its tabs, from the stored choices and live
                // (`HelmHeaderChoices`).
                .helmTracksHeaderChoices { AppSettings.headerChoices }
                // Whether the row wears Helm's band at all, as the system's decision.
                .environment(\.helmBandChoice, band)
                .environment(\.helmTabsSink, tabs)
                .modifier(TellsWindowActivity(model: model))
                .onPreferenceChange(HelmPageTitleKey.self) { [model] title in
                    model.pageTitle = title
                }
                .mirrorsHeaderFacts(into: model)
                .environment(\.helmHeaderInCard, true)
                .modifier(RebuiltOnLanguageChange(model: model))
                .helmRoot()
                // Same reason as the sidebar's, and this pane is the expensive
                // one: it holds whichever module page was open, and LogView's
                // live tail, when the window was closed.
                .helmIdlesOffScreen())
        // **The pane takes no safe area from the title bar**: the header row starts at the card's top edge,
        // and the inset above the page is the row's own (`helmCardHeader`). A page says what it wants in
        // the row through `helmHeaderContent`, a preference in this same hosting view.
        detail.sizingOptions = []
        detail.safeAreaRegions = []
        addChild(sidebar)
        addChild(detail)
        return ShellContentView(sidebar: sidebar.view, pane: detail.view) { AppSettings.barAppearance }
    }
}

/// Whether the sidebar is folded to the rail, held by the shell's controller (which reads it from
/// the store when it is built and writes it on a person's flip) and read by the one hosting view
/// of the sidebar: it is never rebuilt for a fold, so a permission state it has probed stays.
@MainActor private final class SidebarFold: ObservableObject {
    @Published var collapsed = false
}

private struct SidebarInTheShell: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var fold: SidebarFold
    let flip: () -> Void

    var body: some View {
        ShellSidebar(model: model, collapsed: fold.collapsed, toggleCollapsed: flip)
            // The sidebar is a hosting controller of its own: an environment set on the pane's root
            // does not reach it, so it tells the rows the window's state itself.
            .modifier(TellsWindowActivity(model: model))
    }
}

// MARK: - Detail

private struct SettingsDetail: View {
    @ObservedObject var model: SettingsModel

    /// Bumped when the module on screen says its state moved; the status is read off an object this view does
    /// not observe, so without this it is right once per visit and stale after.
    @State private var activityRevision = 0
    @State private var activityWatch: AnyCancellable?

    private var settled: SettingsSelection? {
        ShellSidebarRows.settled(model.selection, enabled: model.host.enabledModuleIDs)
    }

    var body: some View {
        let _ = activityRevision
        let identity = ShellPageIdentity.of(settled, host: model.host)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .helmCardHeader(symbol: identity.symbol, tint: identity.tint, title: identity.title,
                            status: identity.status)
            .onAppear(perform: watchActivity)
            .onChange(of: settled) { watchActivity() }
    }

    /// Follows the selected module's own «my state moved» signal, replacing the one of the page left.
    /// `body` reads `activityRevision`, so writing it asks for the status again.
    private func watchActivity() {
        activityWatch = nil
        guard case .module(let id) = settled,
              let live = model.host.liveModule(id), let changes = live.statusChanges() else { return }
        activityWatch = changes.sink { _ in activityRevision &+= 1 }
    }

    @ViewBuilder
    private var content: some View {
        let tabs = HelmHeaderContent(tabs: SettingsTabs.all,
                                          selectedTab: SettingsTabs.binding($model.selection))
        // A module that is off reads as General, as it does in the sidebar,
        // whatever the selection still says.
        switch ShellSidebarRows.settled(model.selection, enabled: model.host.enabledModuleIDs) {
        case .none, .general:
            // General and About put nothing in the row but the tabs.
            MenuBarSettingsView()
                .helmHeaderContent(tabs)
        case .about:
            AboutHelmView()
                .helmHeaderContent(tabs)
        case .log:
            LogView(settingsTabs: tabs)
        case .module(let id):
            if let descriptor = ModuleRegistry.descriptor(id) {
                ModuleDetailView(host: model.host, descriptor: descriptor, id: id)
            } else {
                // A selection can outlive its module (removed build, stale
                // state). Falling back beats showing an empty pane.
                MenuBarSettingsView()
            }
        }
    }
}

/// **The symbol, tint, name and status of the page on screen, for the header row**: a module's are its
/// descriptor's symbol, tint and name (`ModuleDescriptor.moduleMetadata`, `moduleTint`; the sidebar's row draws
/// the glyph and short name untinted, `ShellSidebar`), and General, Log and About share Settings' — one name
/// over the three tabs, so the plate stays put under them.
struct ShellPageIdentity {
    let symbol: String
    let tint: Color
    let title: String
    let status: HelmHeaderStatus?

    /// `selection` is the settled one (`ShellSidebarRows.settled`).
    @MainActor static func of(_ selection: SettingsSelection?, host: ModuleHost) -> ShellPageIdentity {
        let settings = ShellPageIdentity(symbol: "gearshape", tint: ModuleTint.hostColour, title: AppStr.settingsPane, status: nil)
        guard case .module(let id) = selection, let descriptor = ModuleRegistry.descriptor(id) else {
            return settings
        }
        return ShellPageIdentity(symbol: descriptor.moduleMetadata.sfSymbol, tint: descriptor.moduleTint.colour,
                                 title: descriptor.moduleMetadata.name,
                                 status: status(id, host: host))
    }

    /// nil where the module answers nil, which is most of them.
    @MainActor static func status(_ id: String, host: ModuleHost) -> HelmHeaderStatus? {
        guard let live = host.liveModule(id), let activity = live.activity() else { return nil }
        switch activity {
        case .active: return HelmHeaderStatus(word: AppStr.moduleActive, active: true)
        case .idle: return HelmHeaderStatus(word: AppStr.moduleIdle, active: false)
        }
    }
}

private struct ModuleDetailView: View {
    @ObservedObject var host: ModuleHost
    let descriptor: any ModuleDescriptor
    let id: String

    var body: some View {
        // The header lies over the page, and the page scrolls under it, which
        // is where the strip's material and its scroll-edge rule come from.
        // `safeAreaInset` reserves the strip's own height, so no page here
        // reserves it.
        page
            // Leading, not centre. This alignment governs only content that
            // does not fill the pane: a capped column centres itself, and every
            // header here is the card's, which bleeds. What it does govern is a
            // row that wants more than the pane: centred, the overflow is split
            // between the two edges, hiding a clipped toolbar's path under the
            // sidebar and its buttons off the right. Pinned leading, an
            // overflow spills one way and reads as one.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .helmPageHeader(symbol: descriptor.moduleMetadata.sfSymbol,
                            tint: descriptor.moduleTint.colour,
                            title: descriptor.moduleMetadata.name)
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
            live.page()
        } else {
            Color.clear
        }
    }
}

/// Hands the window's key or main state to the header row and the sidebar's rows, which dim with it.
private struct TellsWindowActivity: ViewModifier {
    @ObservedObject var model: SettingsModel

    func body(content: Content) -> some View {
        content.environment(\.helmWindowAppearsActive, model.windowAppearsActive)
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

extension View {
    /// Keeps `model.pageHasTabs` and `model.pageHasSearch` equal to what the page on screen declared for the row.
    func mirrorsHeaderFacts(into model: SettingsModel) -> some View {
        onPreferenceChange(HelmPageHeaderFactsKey.self) { [model] facts in
            model.pageHasTabs = facts?.hasTabs ?? false
            model.pageHasSearch = facts?.hasSearch ?? false
        }
    }
}
