import AppKit
import Combine
import SwiftUI
import HelmRuntime
import HelmUI

/// System Settings-style settings window built on AppKit `NSSplitViewController`
/// so the sidebar is a full-height vibrant source list (traffic lights float
/// over it, no title-bar strip). Each pane hosts a SwiftUI view; a shared
/// `SettingsModel` carries the selection between them.
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
    /// (`DiskLayout.barWithStatement`), and at 940 the pane is 690, so the
    /// statement never appeared out of the box and nothing suggested widening
    /// the window would reveal it. 1060 gives a 810 pt pane, which clears it.
    private static let defaultSize = NSSize(width: 1060, height: 700)
    /// Below this the list rows start truncating names and paths.
    private static let minSize = NSSize(width: 860, height: 540)

    init(host: ModuleHost) {
        let model = SettingsModel(host: host)
        self.model = model
        let split = SettingsSplitViewController(model: model)
        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = AppStr.settingsWindowTitle
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
            model.selection = .module(moduleID)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
    /// counts it among the nine.
    case log
}

@MainActor final class SettingsModel: ObservableObject {
    let host: ModuleHost
    @Published var selection: SettingsSelection? = .general
    /// Bumped when the module order changes, so the sidebar redraws with it —
    /// the order is read from settings, which SwiftUI cannot observe.
    @Published private(set) var orderRevision = 0
    init(host: ModuleHost) {
        self.host = host
        // The model lives as long as the settings window, so the observation
        // needs no teardown — and a deinit cannot touch main-actor state.
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

// MARK: - Split controller

final class SettingsSplitViewController: NSSplitViewController {
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebar = NSHostingController(rootView: SettingsSidebar(model: model, host: model.host))
        // Own the top strip ourselves: with the automatic titlebar safe area the
        // list scrolls under the traffic lights and gets the system scroll-edge
        // fade; dropping the safe area and reserving a fixed strip in the view
        // keeps the first row clear with no fade and no double inset.
        sidebar.safeAreaRegions = []
        // The window's size belongs to the user. By default NSHostingController
        // feeds SwiftUI's ideal size into auto layout, and any pane whose ideal
        // height is unbounded (Spacer-centred empty states, plain VStacks
        // without a Form) grows the WINDOW to the full screen. Turning the
        // sizing options off makes every pane fill whatever the window gives
        // it and never the other way around.
        sidebar.sizingOptions = []
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        // Narrower by default, and the person's to change.
        //
        // It was pinned at 250 from both sides, which is a sidebar nobody can
        // resize: the two thicknesses being equal is what made the divider
        // inert. 214 is the width the redesign draws every window at
        // (`--sidebar-w`), and the longest row Helm ships — «Удаление
        // приложений» — still sets in it; the floor and ceiling are there so a
        // drag cannot leave a column too narrow to read or wide enough to
        // starve the pane, whose own minimum is 420.
        sidebarItem.minimumThickness = Self.sidebarMinimum
        sidebarItem.maximumThickness = Self.sidebarMaximum

        let detail = NSHostingController(rootView: SettingsDetail(model: model))
        // fullSizeContentView + a transparent title bar makes AppKit inset the
        // detail pane by the title-bar height, leaving a dead gap above the
        // module header. The pane draws its own top padding, so drop the inset.
        detail.safeAreaRegions = []
        detail.sizingOptions = []
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 420

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)

        // AppKit remembers the divider itself, under this name, in the same
        // defaults the window frame already uses. Written by hand it would be
        // a third place storing a number the framework is already storing.
        splitView.autosaveName = Self.dividerAutosave
    }

    /// The divider is a hairline to look at and a band to grab.
    ///
    /// AppKit hands a thin divider a hit area barely wider than the line, and
    /// on a sidebar that is the difference between «resizable» and «resizable
    /// if you find it». The rectangle drawn stays one pixel; the rectangle the
    /// pointer is tested against is this one, and it is where the resize cursor
    /// appears too — both come from the same call.
    override func splitView(_ splitView: NSSplitView,
                            effectiveRect proposedEffectiveRect: NSRect,
                            forDrawnRect drawnRect: NSRect,
                            ofDividerAt dividerIndex: Int) -> NSRect {
        var grab = proposedEffectiveRect
        grab.origin.x -= Self.dividerGrab
        grab.size.width += Self.dividerGrab * 2
        return grab
    }

    /// Either side of the hairline. Five is what a pointer finds without
    /// looking, and it is small enough that the first row of the pane, whose
    /// own inset is 20, is never inside it.
    private static let dividerGrab: CGFloat = 5

    /// The first run's width, set where the split view actually has one.
    ///
    /// Measured: doing this in `viewDidLoad` gives **180** — the minimum, not
    /// the 214 asked for. At that point the split has no width to divide, so
    /// the position clamps to the floor and the default silently becomes the
    /// smallest allowed. Here the geometry exists.
    ///
    /// Once, and only when nothing is stored: `autosaveName` restores what was
    /// dragged, and re-applying the default on every appearance would overwrite
    /// the person's own choice each time they opened the window.
    private var hasPlacedDivider = false
    override func viewDidAppear() {
        super.viewDidAppear()
        guard !hasPlacedDivider else { return }
        hasPlacedDivider = true
        guard !UserDefaults.standard.hasSavedSplitPosition(Self.dividerAutosave) else { return }
        splitView.setPosition(Self.sidebarDefault, ofDividerAt: 0)
    }

    /// The width the redesign draws, and the range a drag may reach.
    private static let sidebarDefault: CGFloat = 214
    private static let sidebarMinimum: CGFloat = 180
    private static let sidebarMaximum: CGFloat = 320
    /// Versioned, like `HelmSettingsWindow.v4` beside it: the day the range
    /// changes, a stored position from outside it should be forgotten rather
    /// than clamped in silence.
    private static let dividerAutosave = "HelmSettingsSidebar.v1"
}

extension UserDefaults {
    /// Whether AppKit has a remembered divider for this autosave name.
    ///
    /// `NSSplitView` writes `NSSplitView Subview Frames <name>` and offers no
    /// public way to ask, so the question is asked of the same key it writes.
    /// Without it, a first launch and a hundredth are indistinguishable, and
    /// the default width would be re-applied over the person's own every time.
    func hasSavedSplitPosition(_ autosaveName: String) -> Bool {
        object(forKey: "NSSplitView Subview Frames \(autosaveName)") != nil
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @ObservedObject var model: SettingsModel
    /// Observed, not reached through the model.
    ///
    /// The list filters by `isEnabled`, and switching a module off in Settings
    /// calls `ModuleHost.setEnabled` directly — no `.helmModuleOrderChanged`,
    /// which is the only thing this view was listening for. `model.host` is a
    /// plain `let`, so nothing here heard the change and the row of a module
    /// that had just been switched off stayed in the sidebar until something
    /// else happened to invalidate the view.
    ///
    /// `isEnabled` reads the store rather than `live`, so this is not about
    /// where the value comes from — it is about being redrawn at all.
    @ObservedObject var host: ModuleHost
    /// Re-read on notification rather than observed: the value lives in
    /// `UserDefaults` through `AppSettings`, which SwiftUI cannot watch.
    @State private var style = AppSettings.sidebarStyle

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 44)   // traffic-light strip + breathing room
            sidebarList
        }
    }

    /// Re-probed when the app comes forward: a grant is given in System
    /// Settings, which means this window is behind while it happens.
    @State private var diskAccess: PermissionState = .granted
    @State private var accessibility: PermissionState = .granted

    /// Whether a module has declared it can do nothing without a permission
    /// macOS is currently withholding.
    ///
    /// Layout has been inert in every logged session on this machine — 84
    /// warnings of `no accessibility grant — not watching` — and the sidebar
    /// listed it exactly like the modules that work. The module's own page says
    /// so, but only once you are on it: from the outside a module that cannot do
    /// anything looks like a module with nothing to do.
    ///
    /// **`inertWithout`, not `permissions`.** Reading the wider list put the
    /// triangle on seven of the nine rows — the four Full Disk modules, which
    /// work and find less, and Keep Awake, which declares Accessibility for a
    /// pointer nudge that ships switched off and never asks for it otherwise.
    /// Seven marks are wallpaper; the row where the warning was true was the
    /// one nobody would read any more. And since an ad-hoc build loses its
    /// grants on every update, that sidebar was what every user saw after every
    /// update.
    private func isBlocked(_ descriptor: any ModuleDescriptor) -> Bool {
        descriptor.moduleMetadata.inertWithout.contains { need in
            switch need {
            case .fullDisk: return diskAccess == .denied
            case .accessibility: return accessibility == .denied
            // Not probeable, and not withheld in the same sense: screen
            // recording is asked for by the system at the moment it is needed,
            // and the admin helper is a password prompt, not a grant that can
            // silently go missing. A warning we cannot verify is worse than
            // none.
            case .screenRecording, .adminHelper: return false
            }
        }
    }

    private var sidebarList: some View {
        List(selection: $model.selection) {
            // The modules first. The sidebar is where you go to *use* one, and
            // the three pages under them are about Helm rather than about
            // anything it does — Settings was above the whole arrangement,
            // which put the least-visited page of the window in the first row
            // and pushed every module down by one.
            ForEach(layout.sections) { section in
                let modules = visibleModules(in: section)
                if !modules.isEmpty {
                    Section(AppStr.sectionTitle(section)) {
                        ForEach(modules, id: \.idRaw) { descriptor in
                            // The sidebar column is fixed, so it asks for the
                            // short name; everything else shows the full one.
                            sidebarRow(descriptor.moduleMetadata.shortName,
                                       descriptor.moduleMetadata.sfSymbol,
                                       descriptor.moduleTint.colour,
                                       blocked: isBlocked(descriptor))
                                .tag(SettingsSelection.module(descriptor.idRaw))
                        }
                    }
                }
            }
            // Helm itself, at the foot: settings, the log, and what this build
            // is. Three pages a person opens on purpose and rarely, kept
            // together and out of the way of the ones they came for.
            Section {
                sidebarRow(AppStr.settingsPane, "gearshape", .gray)
                    .tag(SettingsSelection.general)
                // Shown on every build. The live tail was dev-only while it was
                // a curiosity; now it is where the log itself is turned on,
                // read and copied, and that is the button somebody is told to
                // press when they report a problem.
                sidebarRow(AppStr.logPane, "text.alignleft", .gray)
                    .tag(SettingsSelection.log)
                sidebarRow(AppStr.aboutHelm, "info.circle", .gray)
                    .tag(SettingsSelection.about)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)   // let the AppKit sidebar material show
        .onReceive(NotificationCenter.default.publisher(for: .helmSidebarStyleChanged)) { _ in
            style = AppSettings.sidebarStyle
        }
        .task {
            diskAccess = PermissionCheck.currentFullDiskAccess()
            accessibility = PermissionCheck.currentAccessibility()
        }
        .helmOnAppActive {
            diskAccess = PermissionCheck.currentFullDiskAccess()
            accessibility = PermissionCheck.currentAccessibility()
        }
    }

    /// The arrangement the person composed. Read rather than cached: it is
    /// reconciled on every read, which is what keeps a module that arrived with
    /// this build from being missing until something else is rearranged.
    private var layout: SidebarLayout {
        _ = model.orderRevision                       // redraw when it changes
        return SidebarLayoutStore.read(from: AppSettings.store,
                                       registry: SidebarLayoutStore.registry())
    }

    /// The sidebar shows only what is on; Settings shows everything. The two
    /// answer different questions — this is where a module is used, and that is
    /// where it is decided which modules exist at all.
    private func visibleModules(in section: SidebarLayout.Section) -> [any ModuleDescriptor] {
        section.modules.compactMap { id in
            ModuleRegistry.all.first { $0.idRaw == id }
        }
        .filter { model.host.isEnabled($0) }
    }

    private func sidebarRow(_ title: String, _ symbol: String, _ color: Color,
                            blocked: Bool = false) -> some View {
        Label {
            HStack(spacing: 6) {
                Text(title)
                if blocked {
                    // The module is on and cannot act. Not a badge with a count
                    // and not a red dot — this is one fact, and the pane it
                    // sends you to is where it is fixed.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(HelmSignal.warning)
                        .help(AppStr.moduleBlockedByPermission)
                        .accessibilityLabel(AppStr.moduleBlockedByPermission)
                }
            }
        } icon: {
            switch style {
            case .colour:
                HelmIconPlate(symbol: symbol, tint: color, size: 22)
            case .plain:
                // Not the module's colour at a smaller dose: a tinted glyph on
                // the sidebar's own background reads as neither plate nor text.
                // The plain look is grey, and the shape does the distinguishing.
                //
                // Corrected by `SymbolInk`, as the plate is. Without it one point
                // size is 28% of visual size across this set — `keyboard` paints
                // 1,27 of its square and `lock.shield` 0,99 — and the row that
                // relies on shape alone is the row that can least afford the
                // shapes to be different sizes.
                //
                // The base is 13, not the 14 this row used before the correction
                // and not the 15 it was first given with it. Correction
                // normalises to the table's mean of 1,088, so every glyph paints
                // `base × 1,088` of ink: 14 reproduced the old *average* of 15,2
                // and 15 came out at 16,3 — bigger than most of these symbols had
                // ever been drawn, which is what "the same size, but too big"
                // was. 13 paints 14,1, near the smallest the old row had.
                Image(systemName: symbol)
                    .font(.system(size: 13 * SymbolInk.correction(for: symbol), weight: .medium))
                    .foregroundStyle(HelmText.quiet)
                    .frame(width: 22, height: 22)
            }
        }
        // The mockup's row is 28 tall around a 22 pt plate; `.sidebar` style
        // gives a taller one, and eleven rows of it is why the column read as
        // roomy rather than narrow. The height is set on the content, not the
        // row, so the selection capsule keeps its own inset.
        .frame(height: 28)
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
        switch model.selection {
        case .none, .general:
            MenuBarSettingsView()
        case .about:
            AboutHelmView()
        case .log:
            LogView()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HelmPageHeader(symbol: descriptor.moduleMetadata.sfSymbol,
                           tint: descriptor.moduleTint.colour,
                           title: descriptor.moduleMetadata.name,
                           bleeds: descriptor.pageBleeds) {
                // Only for a module that can say. Most answer nil, and nil
                // draws nothing rather than «Not active» for a module with no
                // notion of running at all.
                if let live = host.liveModule(id),
                   let activity = descriptor.activity(live.vm) {
                    switch activity {
                    case .active:
                        HelmBadge(AppStr.moduleActive, tint: HelmSignal.success)
                    case .idle:
                        // Quiet text, not a badge. «Not active» is the ordinary
                        // state, and a badge on every page for the ordinary
                        // state is a mark that means nothing.
                        Text(AppStr.moduleIdle)
                            .font(.system(size: 11))
                            .foregroundStyle(HelmText.quiet)
                    }
                }
            }
            // No switch here. It was the third one in the app for the same
            // fact — the composer sheet's column and the empty state's
            // «Включить» being the other two — and it was the only one that
            // could act on the page you were standing on: the sidebar lists
            // what is on, so switching a module off from its own header
            // removed its row, left the selection pointing at nothing, and
            // went on showing the module you had just turned off.
            //
            // Whether a module exists at all is a settings question, and it
            // is asked where the sidebar is arranged.
            Divider()
            if let live = host.liveModule(id) {
                descriptor.settingsPage(live.vm)
            } else {
                // A sentence pointing at a switch in the far corner was the
                // app's poorest screen: it said neither what the module does
                // nor where to turn it on. Say what it is, then offer the
                // action where the eye already is.
                HelmEmptyState(symbol: descriptor.moduleMetadata.sfSymbol,
                               tint: descriptor.moduleTint.colour,
                               title: descriptor.moduleMetadata.name,
                               message: descriptor.moduleMetadata.summary) {
                    Button(AppStr.turnOn) { host.setEnabled(descriptor, true) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.top, 4)
                }
            }
        }
        // Leading, not centre. This alignment governs only content that does
        // not fill the pane, and everything here fills it — a capped column
        // and a non-bleeding header each centre themselves, measured unmoved
        // at 610, 810 and 1400 pt. What it does govern is a row that wants
        // *more* than the pane: centred, the overflow was split between the
        // two edges, so a clipped toolbar hid its path under the sidebar and
        // its buttons off the right. Pinned leading, an overflow spills one
        // way and reads as one.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
