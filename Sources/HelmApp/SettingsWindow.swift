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
/// **There is a title bar over the sidebar, and it is not in sections.** One
/// `NSTitlebarView` spans the whole window over one full-width `NSToolbarView`
/// (read on a split-view rig, not on this window), so there is no per-section surface in the bar for Helm or for the system to
/// light, which is why the band this window wears is drawn in the pane below.
/// The bar's first item is a spacer that carries the page's name over to the
/// card (`SettingsToolbar.Lead.spacer`), told where the card is.
@MainActor final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let model: SettingsModel
    /// What a page's toolbar content crosses into this target by
    /// (`HelmWindowToolbar.swift` in `HelmUI`) — handed to the detail pane's
    /// environment so a page never needs to import `HelmApp` to publish into
    /// it, and read by `settingsToolbar` on the other side.
    private let toolbarChannel = HelmWindowToolbarChannel()
    private let settingsToolbar: SettingsToolbar

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

    /// `band` is whose band lies under the toolbar — the running system's
    /// decision unless a test builds another system's window on this one; the
    /// same value sets the title bar below and reaches the pane's
    /// `helmToolbarBackdrop` (`HelmBandChoice`).
    init(host: ModuleHost, band: HelmBandChoice = .running) {
        let model = SettingsModel(host: host)
        self.model = model
        let shell = SettingsShellViewController(model: model, toolbarChannel: toolbarChannel,
                                                band: band)
        let toolbar = SettingsToolbar(model: model, channel: toolbarChannel, lead: .spacer,
                                      barAttached: { [weak shell] in shell?.barWasAttached() })
        settingsToolbar = toolbar
        shell.cardMoved = { [weak toolbar] frame in
            toolbar?.paneMoved(leading: frame.minX, width: frame.width)
        }
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
        window.titlebarAppearsTransparent = band.titlebarAppearsTransparent
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
        // The card's place is known to the bar before the bar is put on the
        // window: one layout, and the report it queued delivered here rather
        // than a turn of the main queue later.
        shell.view.layoutSubtreeIfNeeded()
        shell.deliverCard()
        // Assigning this is what puts the first toolbar on the window —
        // `SettingsToolbar` cannot do it itself at construction, since it is
        // built before this window exists (`init` above needs the toolbar
        // object to exist before there is anywhere to hang it).
        settingsToolbar.window = window
        // Seeds the toolbar with this window's own, freshly-created state —
        // neither key nor main yet — rather than leaving it at
        // `SettingsToolbar`'s own default until the first notification below
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

    /// Name and status in the title bar for the style that draws them there;
    /// for the style that draws the module's plate and name as a toolbar item
    /// the title stays the window's — the Window menu and Mission Control name
    /// the window by it — and is simply not drawn a second time.
    private func applyTitle(_ title: HelmPageTitle?) {
        let style = AppSettings.pageBarStyle
        window.title = title?.title ?? AppStr.settingsWindowTitle
        window.subtitle = style == .windowTitle ? (title?.subtitle ?? "") : ""
        window.titleVisibility = style == .windowTitle ? .visible : .hidden
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
        settingsToolbar.setWindowAppearsActive(window.isKeyWindow || window.isMainWindow)
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
    @Published var selection: SettingsSelection? = .general
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
/// **The card's place is reported outside the content's layout pass.** A flip
/// of the bar's spacer assigns `window.toolbar`, and that must not happen
/// inside `ShellContentView.layout()`; `cardWasLaidOut` keeps the newest frame
/// and `deliverCard()` hands it to `cardMoved` a turn of the main queue later
/// (the window delivers the first one itself, before the bar has a window).
@MainActor final class SettingsShellViewController: NSViewController {
    private let model: SettingsModel
    /// Handed to the detail pane's environment so a page can publish its
    /// toolbar content (`helmWindowToolbar`) without importing `HelmApp` —
    /// `SettingsToolbar`, on the other side of it, is `SettingsWindow`'s.
    private let toolbarChannel: HelmWindowToolbarChannel
    /// The window's own band decision, handed down rather than read again —
    /// no default, so the pane cannot be built on one system's decision
    /// under a title bar set from another's.
    private let band: HelmBandChoice

    /// Told where the card is; set by the window, which holds the toolbar.
    var cardMoved: (CGRect) -> Void = { _ in }
    private var pendingCard: CGRect?
    private var deliveryScheduled = false

    private let fold = SidebarFold()
    private var foldWatch: AnyCancellable?

    init(model: SettingsModel, toolbarChannel: HelmWindowToolbarChannel, band: HelmBandChoice) {
        self.model = model
        self.toolbarChannel = toolbarChannel
        self.band = band
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

    /// The toolbar assigned a bar to the window: ask the shell for a layout.
    /// Asks only, never forces one.
    func barWasAttached() {
        guard isViewLoaded else { return }
        shell.barWasAttached()
    }

    private func cardWasLaidOut(_ frame: CGRect) {
        pendingCard = frame
        guard !deliveryScheduled else { return }
        deliveryScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.deliverCard() }
        }
    }

    /// Hands the newest frame laid out, if any is waiting, to `cardMoved`.
    func deliverCard() {
        deliveryScheduled = false
        guard let frame = pendingCard else { return }
        pendingCard = nil
        cardMoved(frame)
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
                // never does leaves the window showing its name — plus a
                // status-bearing page's own status: `helm.status` under
                // `PageBarStyle.moduleName`, the window's subtitle under
                // `.windowTitle` — and nothing else (`SettingsToolbar.refresh`).
                // This is every page's own toolbar, including one with
                // nothing to put in it, since the toolbar exists whether or
                // not any page ever asks it for anything.
                .environment(\.helmWindowToolbarChannel, toolbarChannel)
                // The strip under the toolbar, lit once the page's content
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
        // **The pane keeps AppKit's safe area, which it used to drop.** It was
        // `safeAreaRegions = []`, because under a transparent title bar the
        // inset was a dead strip above a header each page drew for itself.
        // The inset is the toolbar now, `SettingsToolbar`'s, owned by
        // `SettingsWindow` and never SwiftUI's — no `sceneBridgingOptions` is
        // set on this controller, on purpose: every page now says what it
        // wants in its toolbar through `helmWindowToolbar`, which reaches
        // `SettingsToolbar` through `HelmWindowToolbarChannel` and needs no
        // bridge from this controller at all. A page that calls neither
        // `helmWindowToolbar` nor anything else toolbar-shaped shows the
        // window's name — plus a status-bearing page's own status:
        // `helm.status` under `PageBarStyle.moduleName`, the window's
        // subtitle under `.windowTitle` — and nothing else, which
        // is what "temporarily show only the name" (this migration's own
        // words, while some pages were still on the retired
        // `.toolbar`/`sceneBridgingOptions` route) means for a page with
        // genuinely nothing to declare.
        detail.sizingOptions = []
        addChild(sidebar)
        addChild(detail)
        return ShellContentView(sidebar: sidebar.view, pane: detail.view) { [weak self] frame in
            self?.cardWasLaidOut(frame)
        }
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
            // The keys are the ones `SettingsToolbar.pageKey` answers for the
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
    /// его в правую часть»; `SettingsToolbar.makeStatusItem` draws it now, at
    /// the bar's own trailing edge).
    ///
    /// `activity` reads a `@Published` on the module's view model — an object
    /// this view holds and does not observe — so measured, the badge this
    /// once fed changed exactly once per visit to the page: start a session
    /// from the hero, and the countdown ran while the badge two inches above
    /// it still said «Not active», until you left the page and came back.
    /// `statusWord` inherits the same publisher for the same reason, now
    /// feeding only the `.windowTitle` style's subtitle.
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

    /// The same status `SettingsToolbar`'s own `helm.status` item draws, said
    /// in words — for the `.windowTitle` style that puts it under the
    /// window's title, where that item does not apply (`PageBarContent`'s
    /// `.windowTitle` arm, `PageBarStyle.swift`). nil for a module with no
    /// notion of running, like that item.
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
