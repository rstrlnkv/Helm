import AppKit
import Combine
import SwiftUI
import HelmRuntime
import HelmContract
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
    func show(selecting moduleID: String? = nil) {
        if let moduleID { model.selection = .module(moduleID) }
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
            MainActor.assumeIsolated { self?.orderRevision += 1 }
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

        let sidebar = NSHostingController(rootView: SettingsSidebar(model: model))
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
        sidebarItem.minimumThickness = 250
        sidebarItem.maximumThickness = 250

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
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @ObservedObject var model: SettingsModel
    /// Re-read on notification rather than observed: the value lives in
    /// `UserDefaults` through `AppSettings`, which SwiftUI cannot watch.
    @State private var style = AppSettings.sidebarStyle

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 44)   // traffic-light strip + breathing room
            sidebarList
        }
    }

    /// The build, not the update channel: the channel is a picker anyone can
    /// move, and a shipped beta build must not grow a diagnostics pane because
    /// somebody wants updates sooner.
    private var isDevBuild: Bool {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "").contains("-dev")
    }

    /// Re-probed when the app comes forward: a grant is given in System
    /// Settings, which means this window is behind while it happens.
    @State private var diskAccess: PermissionState = .granted
    @State private var accessibility: PermissionState = .granted

    /// Whether a module has declared a permission macOS is currently withholding.
    ///
    /// Layout has been inert in every logged session on this machine — 84
    /// warnings of `no accessibility grant — not watching` — and the sidebar
    /// listed it exactly like the modules that work. The module's own page says
    /// so, but only once you are on it: from the outside a module that cannot do
    /// anything looks like a module with nothing to do.
    private func isBlocked(_ descriptor: any ModuleDescriptor) -> Bool {
        descriptor.moduleMetadata.permissions.contains { need in
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
    }
}

// MARK: - Detail

private struct SettingsDetail: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                           subtitle: descriptor.moduleMetadata.summary,
                           bleeds: descriptor.pageBleeds) {
                Toggle(descriptor.moduleMetadata.name, isOn: Binding(
                    get: { host.isEnabled(descriptor) },
                    set: { host.setEnabled(descriptor, $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct MenuBarSettingsView: View {
    @State private var style: String = AppSettings.menuBarIconStyle
    @State private var size: String = AppSettings.menuBarIconSize
    @State private var launchAtLogin: Bool = LoginItem.isEnabled
    @State private var appearance: AppAppearance = AppSettings.appearance
    @State private var sidebarStyle: SidebarStyle = AppSettings.sidebarStyle
    @State private var showSettingsButton = AppSettings.showSettingsButton
    @State private var showQuitButton = AppSettings.showQuitButton
    @State private var diskAccess: PermissionState = .granted
    @State private var accessibility: PermissionState = .granted
    @State private var confirmingReset = false
    private let adHocBuild = PermissionCheck.isAdHocSigned()

    /// The permissions an enabled module actually uses, in table order.
    private var neededPermissions: [PermissionNeed] {
        let declared = ModuleRegistry.all
            .filter { ModuleHost.shared.isEnabled($0) }
            .flatMap { $0.moduleMetadata.permissions }
        return PermissionNeed.allCases.filter { need in
            switch need {
            case .fullDiskAccess: return declared.contains(.fullDisk)
            case .accessibility: return declared.contains(.accessibility)
            }
        }
    }
    @State private var loggingOn = LogPolicy.isEnabled(
        version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
        override: AppSettings.loggingOverride)

    private var isDevBuild: Bool {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "").contains("-dev")
    }

    var body: some View {
        VStack(spacing: 0) {
            HelmPageHeader(symbol: "gearshape", tint: .gray,
                           title: AppStr.settingsPane, subtitle: AppStr.settingsPaneSummary)
            Divider()
            settingsForm
        }
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? HelmSignal.success : HelmSignal.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted {
                Button(AppStr.grant, action: action).controlSize(.small)
            }
        }
    }

    private var settingsForm: some View {
        Form {
            Section(AppStr.general) {
                Toggle(AppStr.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in LoginItem.setEnabled(v) }
                Picker(AppStr.appearance, selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { choice in
                        Text(AppStr.appearanceName(choice)).tag(choice)
                    }
                }
                .onChange(of: appearance) { _, choice in AppSettings.appearance = choice }
                // Worth offering only because the tint is the module's own: a
                // choice between four modules in one blue and grey is not one.
                Picker(AppStr.moduleIcons, selection: $sidebarStyle) {
                    Text(AppStr.moduleIconsColour).tag(SidebarStyle.colour)
                    Text(AppStr.moduleIconsPlain).tag(SidebarStyle.plain)
                }
                .pickerStyle(.segmented)
                .onChange(of: sidebarStyle) { _, choice in AppSettings.sidebarStyle = choice }
            }
            SidebarSettingsSection(host: ModuleHost.shared)
            Section(AppStr.menuBar) {
                LabeledContent(AppStr.iconShape) {
                    IconShapePicker(selection: $style)
                        .onChange(of: style) { _, v in AppSettings.menuBarIconStyle = v }
                }
                LabeledContent(AppStr.iconSize) {
                    IconSizePicker(selection: $size, style: currentStyle)
                        .onChange(of: size) { _, v in AppSettings.menuBarIconSize = v }
                }
                Text(AppStr.menuBarNote)
                    .font(.caption).foregroundStyle(HelmText.quiet)
            }
            Section(AppStr.panel) {
                Toggle(AppStr.showSettingsButton, isOn: $showSettingsButton)
                    .onChange(of: showSettingsButton) { _, v in AppSettings.showSettingsButton = v }
                Toggle(AppStr.showQuitButton, isOn: $showQuitButton)
                    .onChange(of: showQuitButton) { _, v in AppSettings.showQuitButton = v }
                Text(AppStr.panelButtonsNote)
                    .font(.caption).foregroundStyle(HelmText.quiet)
            }
            Section(AppStr.permissions) {
                // Driven by the table, so a new permission shows up here
                // without anyone remembering to add a row — but only the ones
                // an enabled module actually uses. Listing all of them asked
                // someone who has switched Keyboard and Keep Awake off to grant
                // Accessibility for nothing, which is how people learn to grant
                // everything without reading. `PermissionAudit.run()` already
                // filters this way; the two disagreed.
                ForEach(neededPermissions, id: \.self) { need in
                    let granted = need.state(accessibility: accessibility,
                                             fullDisk: diskAccess) == .granted
                    permissionRow(AppStr.permissionTitle(need),
                                  // Both, never one instead of the other: the
                                  // ad-hoc caveat used to replace the sentence
                                  // saying what the grant is for, and every build
                                  // anybody runs is ad-hoc — so the Accessibility
                                  // decision was made without the words "every
                                  // keystroke in every app" ever being shown.
                                  detail: !granted && adHocBuild
                                      ? AppStr.permissionWhy(need) + "\n"
                                          + AppStr.fullDiskAccessAdHoc
                                      : AppStr.permissionWhy(need),
                                  granted: granted) { need.openSettings() }
                }
            }
            Section(AppStr.resetSection) {
                // `role: .destructive` alone draws as an ordinary link in a
                // grouped Form on macOS — the role reaches menus and dialogs,
                // not form rows. The token, not SwiftUI's `.red`: HelmSignal
                // exists because literal colours measured under the 4.5:1
                // floor in light mode.
                Button(AppStr.resetAll, role: .destructive) { confirmingReset = true }
                    .foregroundStyle(HelmSignal.danger)
                Text(AppStr.resetNote)
                    .font(.caption)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        // A grouped Form caps its content at 704 pt and centres it, so past a
        // 994 pt window its leading edge walks away from everything Helm draws
        // itself — measured at 36 pt on a 1070 pt window, 181 pt on 1360.
        // Capping it at 704 + 2×20 keeps the system on the branch where the
        // inset is a constant 20, which is what the page header uses.
        .helmSettingsColumn()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user grants in System Settings and comes back; the row has
            // to notice without being told.
            diskAccess = PermissionCheck.currentFullDiskAccess()
            accessibility = PermissionCheck.currentAccessibility()
        }
        .task {
            diskAccess = PermissionCheck.currentFullDiskAccess()
            accessibility = PermissionCheck.currentAccessibility()
        }
        .confirmationDialog(AppStr.resetConfirmTitle, isPresented: $confirmingReset,
                            titleVisibility: .visible) {
            Button(AppStr.resetConfirmAction, role: .destructive) { ResetEverything.run() }
            Button(AppStr.cancel, role: .cancel) {}
        } message: {
            Text(AppStr.resetConfirmBody)
        }
    }

    private var currentStyle: MenuBarIconStyle {
        MenuBarIconStyle(rawValue: style) ?? .ring
    }
}

private struct AboutHelmView: View {
    @State private var showWhatsNew = false
    @State private var channel = UpdateService.channel
    @ObservedObject private var updater = UpdateService.shared

    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    private var moduleCount: Int { ModuleRegistry.all.count }

    var body: some View {
        // A ScrollView because the page grows by ~50 pt when an update is
        // available — a full-width prominent button — and it already measured
        // 617 pt against the 540 pt minimum window. It overflowed at the
        // default size precisely in the state that matters, dropping the
        // Update button off the bottom.
        ScrollView {
            VStack(spacing: 0) {
            Spacer(minLength: 12)
            hero
            Spacer(minLength: 22).frame(maxHeight: 30)
            instrumentRow
                .padding(.bottom, 20)
            updateCard
            HStack(spacing: 10) {
                Button {
                    showWhatsNew = true
                } label: {
                    Label(AppStr.whatsNew, systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    if let url = URL(string: "https://github.com/rstrlnkv/Helm") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("GitHub", systemImage: "arrow.up.forward.square")
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
            .padding(.top, 14)
            Spacer(minLength: 18)
            VStack(spacing: 3) {
                Text("© 2026 Helm · GPL-3.0")
                // CC BY 4.0 asks for attribution where the work is used, and
                // the flags are used in the menu bar — this is the page that
                // can carry it.
                Link(AppStr.flagCredit,
                     destination: URL(string: "https://github.com/lipis/flag-icons")!)
                    .foregroundStyle(HelmText.faint)
            }
            .padding(.top, 6)
            .font(.caption2)
            .foregroundStyle(HelmText.faint)
        }
            .frame(width: Self.column)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(onClose: { showWhatsNew = false })
        }
    }

    private static let column: CGFloat = 380

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                // No halo behind the mark: `HelmAppMark` casts its own shadow,
                // and a radial gradient on top of it was a second light source
                // with a visible rim where its ramp ended.
                // The bezel turns only while a check is running: motion here
                // means work, not decoration.
                HelmBezel(active: updater.checking)
                    .frame(width: 172, height: 172)
                HelmAppMark(size: 92)
            }
            .frame(height: 186)
            VStack(spacing: 5) {
                // The badges hang off the wordmark instead of sharing a row
                // with it. In an HStack the pair is centred together, so the
                // name sat left of centre by half the badges' width — under a
                // mark and above a tagline that are both centred on the column,
                // which is where the eye reads the axis from. As an overlay
                // they take no width, so "Helm" is centred on the same line
                // everything else is.
                //
                // Measured on the rendered pixels, not judged
                // (`Scripts/design/measure-wordmark.swift`): in the 380 pt
                // column the row put the word 42.2 pt left of the axis; the
                // overlay puts it at 189.8 against a centre of 190.
                Text("Helm")
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.4)
                    .overlay(alignment: .topTrailing) {
                        badge
                            .fixedSize()
                            // The overlay's own leading edge, placed 7 pt past
                            // the end of the word.
                            .alignmentGuide(.trailing) { $0[.leading] - 7 }
                            // The top of the capsule on the top of the H. Not a
                            // guess: at 34 pt semibold the cap starts exactly
                            // 9.00 pt below the line box's top, measured off
                            // the rendered pixels
                            // (Scripts/design/measure-wordmark.swift).
                            .alignmentGuide(.top) { $0[.top] - 9 }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(badgeAccessibilityLabel)
                Text(AppStr.tagline)
                    .font(.subheadline)
                    .foregroundStyle(HelmText.quiet)
            }
        }
    }

    /// One badge: what this copy *is*.
    ///
    /// It was two — BETA for the program and DEV for the channel — on the
    /// reasoning that both facts were true. They are, but they are not two
    /// things to the person reading: pre-1.0 and "on the early channel" both
    /// answer "how finished is what I am running", and a pair reading BETA DEV
    /// makes the reader work out which one wins.
    ///
    /// It then answered from the wrong fact. The badge read the *channel
    /// preference*, so switching the segmented control to Beta on a
    /// `0.7.2-dev.34` build relabelled the running build BETA — while the row
    /// above it went on offering dev releases, because a preference is not a
    /// binary. The badge describes the build; the picker below it describes
    /// what will be offered next, and those are allowed to differ.
    private var isDevBuild: Bool { shortVersion.contains("-dev") }

    private var badge: some View {
        HelmBadge(isDevBuild ? AppStr.devBadge : AppStr.betaBadge,
                  tint: isDevBuild ? .blue : .orange,
                  emphasis: .prominent)
            .help(isDevBuild ? AppStr.channelDevNote : AppStr.channelBetaNote)
    }

    private var badgeAccessibilityLabel: String {
        "Helm, \(isDevBuild ? AppStr.devBadge : AppStr.betaBadge)"
    }

    // MARK: - Instrument row

    private var instrumentRow: some View {
        HelmMetricStrip([
            .init(VersionLabel.split(shortVersion).figure,
                  VersionLabel.caption(AppStr.metricVersion, for: shortVersion)),
            .init(buildNumber, AppStr.metricBuild),
            .init("\(moduleCount)", AppStr.metricModules),
        ])
        .helmCard(padding: 12)
    }

    // MARK: - Update card

    private var updateCard: some View {
        VStack(spacing: 0) {
            updateRow
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            // The token, not a divider dimmed by eye: every other hairline in
            // the app is this colour, and 0.6 of a system divider is not a
            // value anybody can match on the next screen over.
            Rectangle()
                .fill(HelmSurface.hairline)
                .frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(AppStr.updateChannel)
                        .font(.callout)
                    Spacer()
                    Picker(AppStr.updateChannel, selection: $channel) {
                        Text(AppStr.channelBeta).tag(UpdateCheck.Channel.beta)
                        Text(AppStr.channelDev).tag(UpdateCheck.Channel.dev)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    // Its ideal width, not a reservation: at a fixed 170 the
                    // control drew itself narrower and centred, leaving its
                    // trailing edge short of the Check button directly above.
                    .fixedSize()
                    .onChange(of: channel) { _, newValue in updater.setChannel(newValue) }
                }
                Text(channel == .dev ? AppStr.channelDevNote : AppStr.channelBetaNote)
                    .font(.caption)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .helmCard(padding: 0)
    }

    @ViewBuilder
    private var updateRow: some View {
        switch updater.installState {
        case .downloading:
            statusLine(AppStr.downloadingUpdate, spinning: true)
        case .installing:
            statusLine(AppStr.installingUpdate, spinning: true)
        case .digestMismatch:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    statusIcon("exclamationmark.triangle.fill", HelmSignal.danger)
                    Text(AppStr.updateDigestMismatch).lineLimit(3)
                    Spacer()
                }
                // No Retry: downloading the same file again would produce the
                // same answer. The release page is where a person can see what
                // was published and decide.
                if let rel = updater.available {
                    Link(AppStr.download, destination: rel.pageURL)
                        .font(.callout)
                }
            }
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    statusIcon("exclamationmark.triangle.fill", HelmSignal.warning)
                    Text(AppStr.updateFailed).lineLimit(2)
                    Spacer()
                }
                if let rel = updater.available {
                    HStack(spacing: 10) {
                        Button(AppStr.retry) { updater.downloadAndInstall() }
                            .frame(maxWidth: .infinity)
                        Link(AppStr.download, destination: rel.downloadURL ?? rel.pageURL)
                            .font(.callout)
                    }
                }
            }
        case .idle:
            if updater.checking {
                statusLine(AppStr.checking, spinning: true)
            } else if let rel = updater.available {
                // The offer is the card's main action, so it gets full width
                // instead of being squeezed next to the label.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        statusIcon("arrow.down.circle.fill", .accentColor)
                        Text(AppStr.updateReady).lineLimit(1)
                        Spacer()
                        Text(rel.version)
                            .font(HelmText.figureFont)
                            .foregroundStyle(HelmText.quiet)
                    }
                    Button(AppStr.updateAndRelaunch) { updater.downloadAndInstall() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
            } else if updater.lastMessage == "manual-install" {
                HStack(spacing: 10) {
                    statusIcon("exclamationmark.triangle.fill", HelmSignal.warning)
                    Text(AppStr.updateManualInstall).lineLimit(3)
                    Spacer()
                }
            } else if updater.lastMessage == "error" {
                HStack(spacing: 10) {
                    statusIcon("exclamationmark.triangle.fill", HelmSignal.warning)
                    Text(AppStr.updateCheckFailed).lineLimit(1)
                    Spacer()
                    Button(AppStr.retry) { updater.checkNow() }
                }
            } else if let newest = updater.aheadOfChannel {
                // Before "up to date", which this state used to be read as: the
                // check reports both, and being ahead is the more specific
                // answer of the two.
                HStack(spacing: 10) {
                    statusIcon("arrow.up.circle.fill", HelmSignal.warning)
                    Text(AppStr.aheadOfChannel(newest))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(AppStr.checkNow) { updater.checkNow() }
                }
            } else if updater.lastMessage == "up-to-date" {
                HStack(spacing: 10) {
                    statusIcon("checkmark.circle.fill", HelmSignal.success)
                    Text(AppStr.upToDate).lineLimit(1)
                    Spacer()
                    Button(AppStr.checkNow) { updater.checkNow() }
                }
            } else {
                // Nothing has been checked in this session: report when the
                // last check happened rather than claiming to be current.
                HStack(spacing: 10) {
                    statusIcon("arrow.triangle.2.circlepath", .secondary)
                    Text(lastCheckedText).lineLimit(1).foregroundStyle(HelmText.quiet)
                    Spacer()
                    Button(AppStr.checkNow) { updater.checkNow() }
                }
            }
        }
    }

    /// "Checked 2 hours ago" from the stored timestamp, or a never-checked note.
    private var lastCheckedText: String {
        let stamp = AppSettings.store.int("lastUpdateCheck", default: 0)
        guard stamp > 0 else { return AppStr.neverChecked }
        let when = HelmDates.relative(Date(timeIntervalSince1970: TimeInterval(stamp)))
        return AppStr.lastChecked(when)
    }

    private func statusLine(_ text: String, spinning: Bool) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(HelmText.quiet)
            Spacer()
        }
    }

    private func statusIcon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 15))
            .foregroundStyle(color)
    }
}

/// A compass/helm bezel: fine tick marks ringing the app icon, every fifth one
/// longer. It rotates only while an update check is in flight.
private struct HelmBezel: View {
    var active: Bool
    @State private var angle: Double = 0

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for tick in 0..<60 {
                let long = tick % 5 == 0
                let length: CGFloat = long ? 7 : 4
                let a = Double(tick) / 60 * 2 * .pi
                let outer = CGPoint(x: center.x + cos(a) * radius,
                                    y: center.y + sin(a) * radius)
                let inner = CGPoint(x: center.x + cos(a) * (radius - length),
                                    y: center.y + sin(a) * (radius - length))
                var path = Path()
                path.move(to: inner)
                path.addLine(to: outer)
                context.stroke(path,
                               with: .color(.primary.opacity(long ? 0.20 : 0.10)),
                               lineWidth: long ? 1.4 : 1)
            }
        }
        .rotationEffect(.degrees(angle))
        .onChange(of: active) { _, running in
            if running {
                withAnimation(HelmMotion.steadyRotation(seconds: 6)) {
                    angle += 360
                }
            } else {
                withAnimation(HelmMotion.interface) { angle = 0 }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Localized, structured changelog with New/Upd/Fix badges.
private struct WhatsNewView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HelmPageHeader(symbol: "sparkles", tint: .indigo,
                           title: AppStr.whatsNew, subtitle: AppStr.whatsNewSummary) {
                // Escape closes it, like every sheet on the machine.
                // `HelmHotkeyRecorder` special-cases Escape during capture and
                // explains why; that care never reached the sheets.
                Button(AppStr.close, action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Changelog.entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(entry.version).font(.title3.bold())
                                // The entry stores "2026-07-28" because that is
                                // what sorts; no language writes it that way.
                                Text(HelmDates.day(entry.date))
                                    .font(.caption).foregroundStyle(HelmText.faint)
                            }
                            ForEach(entry.items) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    badge(item.kind)
                                    Text(item.text).font(.callout).foregroundStyle(HelmText.quiet)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Matches the header plate above it, which sits at 20.
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
        }
        .frame(width: 520, height: 460)
    }

    private func badge(_ kind: ChangeKind) -> some View {
        // The one pill. This was the last hand-rolled one, and the worst:
        // orange text on orange fill at 11 pt is about 1.6:1, on the screen
        // every user sees right after an update.
        HelmBadge(kind.label, tint: kind.color)
            // Fixed width wrapped half the languages onto a second line.
            .fixedSize()
            .frame(minWidth: 44, alignment: .leading)
    }

}
