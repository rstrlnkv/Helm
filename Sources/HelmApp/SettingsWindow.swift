import AppKit
import Combine
import SwiftUI
import HelmRuntime
import HelmUI

/// The settings window: the ground of the stored look (`HelmBarAppearance`) with a column of module rows on it, and an opaque
/// card holding the page, built by `SettingsShellViewController` from
/// `ShellContentView`. Each of the two hosts a SwiftUI view; a shared
/// `SettingsModel` carries the selection between them.
///
/// **The window wears no `NSToolbar`.** The header row is the card's own, drawn at the top of the detail pane
/// by `SettingsDetail` (`helmCardHeader`): the page's name and status on the left, what the page declared
/// through `helmWindowToolbar` on the right. The title bar is transparent over it and the pane takes no safe
/// area from it, so the row starts at the card's top edge.
@MainActor final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let model: SettingsModel
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
    /// the window would reveal it. 1060 cleared it; the default is now `minSize` and a margin, because the
    /// Log page's header in German needs more than that (`minSize`).
    ///
    /// Not private: `SidebarComposerSheet` caps itself at this height, because
    /// a sheet is drawn inside this window and the window's own content is the
    /// ceiling. Two literal heights in one target, with a comment claiming they
    /// were the same number, is a comment.
    ///
    /// The height is 760 by the owner's decision, up from 700: the eleventh
    /// module (Screenshots, in Utilities) made the shipped composer measure 723,
    /// which 700 could not hold. With Hosts archived (the tag `archive/hosts`)
    /// there are ten, one 40 pt row fewer; the height was left at 760.
    nonisolated static let defaultSize = NSSize(width: 1100, height: 760)
    /// Below this the Log page's header row, the fullest one, no longer fits the card in German.
    ///
    /// **1096 is that row in German at the default sidebar** (`ShellGeometry.defaultSidebarWidth`, 200, which
    /// nothing in the window changes): «Einstellungen», the tabs «Grundlagen | Protokoll | Über Helm», five
    /// actions and the search at `HelmHeaderSearch.width`. Read from `HelmReadout ax` frames on Helm Dev at the
    /// old 1045 minimum, where the row overflowed and was centred, as the row width the frames add up to
    /// (the plate's left edge, 40 left of the name, to the search's right edge) — German 850, French 838,
    /// Spanish 810, Russian 805, English, Portuguese, Japanese and Chinese 801 (the room): 850 pt of row,
    /// 20 pt of gutter each side, 200 of sidebar and 4 of window inset: 1094, and 2 more for a frame rounded
    /// to whole points. The search could not give way instead: French's «Rechercher dans le journal»
    /// has about 8 pt to spare in the 200. A sidebar stored wider than the default
    /// (`ShellGeometry.sidebarRange` goes to 320) is not held by this number.
    private static let minSize = NSSize(width: 1096, height: 540)

    /// The header row's band is the running system's decision (`HelmBandChoice.running`), handed to the pane.
    init(host: ModuleHost) {
        let band = HelmBandChoice.running
        let model = SettingsModel(host: host)
        self.model = model
        let shell = SettingsShellViewController(model: model, band: band)
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
        // **The window's title is the page's name**, set here on the
        // `NSWindow` rather than through SwiftUI: the bridge that used to
        // carry a detail pane's toolbar into the window carried its subtitle
        // and dropped its title (measured on macOS 27 — «Untitled» over a
        // pane that had set one), and the window's title is still this class's to set. The
        // page says what it is called with `HelmPageTitleKey`; this is the
        // one place that listens.
        titleWatch = model.$pageTitle.sink { [weak self] title in
            self?.applyTitle(title)
        }
    }

    private var titleWatch: AnyCancellable?

    /// Writes what the page published as the window's title. `titleVisibility` is `.hidden`, written once by the
    /// initialiser: the card's header row draws the name, and the title stays the window's (the Window menu and
    /// Mission Control name the window by it).
    private func applyTitle(_ title: HelmPageTitle?) {
        window.title = title?.title ?? AppStr.settingsWindowTitle
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
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // A window ordered front without the app's activation gets no key or main notification until
        // one comes, so its chrome would not dim: read it now.
        updateWindowAppearsActive()
    }

    func windowWillClose(_ notification: Notification) {
        if counted {
            counted = false
            HostWindow.windowClosed()
        }
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
    /// notifications below.
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
    /// `didSet` announces the change a second time, after the value is stored. `@Published` announces in
    /// `willSet`, and a view that redraws synchronously inside that announcement reads the old selection.
    /// Assumed, not measured since the window lost its toolbar (the redraw it was written for was the
    /// toolbar's): that without this `didSet` the pane's update runs against the old selection, so a selection
    /// that leaves the log for a module page leaves the pane's page title the log's.
    @Published var selection: SettingsSelection? = .general {
        didSet { objectWillChange.send() }
    }
    /// What the page on screen calls itself, for the window's title bar.
    @Published var pageTitle: HelmPageTitle?
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
/// The controller assigns the window no toolbar: the header row is a view in the page's own hosting view.
@MainActor final class SettingsShellViewController: NSViewController {
    private let model: SettingsModel
    /// The window's own band decision, handed down rather than read again —
    /// no default, so the pane cannot be built on one system's decision
    /// under a title bar set from another's.
    private let band: HelmBandChoice

    private let fold = SidebarFold()

    /// Where the fold state is remembered (`AppSettings.sidebarCollapsed(in:)`).
    private let store = AppSettings.store

    /// The width the sidebar has when expanded, read from the store once, when the window is built.
    /// Nothing in the window changes it, so an unfold always ends here.
    private let expandedWidth: CGFloat

    init(model: SettingsModel, band: HelmBandChoice) {
        self.model = model
        self.band = band
        self.expandedWidth = AppSettings.sidebarWidth(in: store)
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
        collapsed ? ShellGeometry.railWidth : expandedWidth
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
                .modifier(RebuiltOnLanguageChange(model: model))
                // Its own hosting controller, its own root: the pane's environment stops at the pane.
                .helmRoot()
                // The window survives closing (`isReleasedWhenClosed = false`),
                // so without this both panes went on re-rendering — and keeping
                // memory — for every engine event for as long as the app ran.
                // `OffScreenIdle` in HelmUI has the measurements.
                .helmIdlesOffScreen())
        sidebar.sizingOptions = []

        let detail = NSHostingController(
            rootView: SettingsDetail(model: model)
                // The look of the header row's tabs and actions, from the stored choice and live
                // (`HelmBarAppearance`).
                .helmTracksBarAppearance { AppSettings.barAppearance }
                // Whether the row wears Helm's band at all, as the system's decision.
                .environment(\.helmBandChoice, band)
                .modifier(TellsWindowActivity(model: model))
                .onPreferenceChange(HelmPageTitleKey.self) { [model] title in
                    model.pageTitle = title
                }
                .environment(\.helmHeaderInCard, true)
                .modifier(RebuiltOnLanguageChange(model: model))
                // The pane, not the sidebar (its rows draw one look): a module
                // page's header plate and its empty state are module icons, and
                // «Module icons» is what the switch says.
                .helmTracksModuleIconStyle { AppSettings.sidebarStyle }
                .helmRoot()
                // Same reason as the sidebar's, and this pane is the expensive
                // one: it holds whichever module page was open, and LogView's
                // live tail, when the window was closed.
                .helmIdlesOffScreen())
        // **The pane takes no safe area from the title bar**: the header row starts at the card's top edge,
        // and the inset above the page is the row's own (`helmCardHeader`). A page says what it wants in
        // the row through `helmWindowToolbar`, a preference in this same hosting view.
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
        guard case .module(let id) = settled, let descriptor = ModuleRegistry.descriptor(id),
              let live = model.host.liveModule(id), let changes = descriptor.statusChanges(live.vm) else { return }
        activityWatch = changes.sink { _ in activityRevision &+= 1 }
    }

    @ViewBuilder
    private var content: some View {
        let tabs = HelmPageToolbarContent(tabs: SettingsTabs.all,
                                          selectedTab: SettingsTabs.binding($model.selection),
                                          reserves: LogView.trailingRun)
        // A module that is off reads as General, as it does in the sidebar,
        // whatever the selection still says.
        switch ShellSidebarRows.settled(model.selection, enabled: model.host.enabledModuleIDs) {
        case .none, .general:
            // General and About put nothing in the row but the tabs.
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
        let settings = ShellPageIdentity(symbol: "gearshape", tint: .gray, title: AppStr.settingsPane, status: nil)
        guard case .module(let id) = selection, let descriptor = ModuleRegistry.descriptor(id) else {
            return settings
        }
        return ShellPageIdentity(symbol: descriptor.moduleMetadata.sfSymbol, tint: descriptor.moduleTint.colour,
                                 title: descriptor.moduleMetadata.name,
                                 status: status(id, descriptor, host: host))
    }

    /// nil where the module answers nil, which is most of them.
    @MainActor static func status(_ id: String, _ descriptor: any ModuleDescriptor,
                                  host: ModuleHost) -> HelmHeaderStatus? {
        guard let live = host.liveModule(id), let activity = descriptor.activity(live.vm) else { return nil }
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
                            bleeds: descriptor.pageBleeds)
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
