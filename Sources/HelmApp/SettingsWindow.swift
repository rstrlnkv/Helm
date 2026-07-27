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
        window.title = "Helm Settings"
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

// MARK: - Category tint

private func categoryColor(_ category: ModuleCategory) -> Color { category.tint }

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 44)   // traffic-light strip + breathing room
            sidebarList
        }
    }

    private var sidebarList: some View {
        List(selection: $model.selection) {
            Section {
                sidebarRow(AppStr.settingsPane, "gearshape", .gray)
                    .tag(SettingsSelection.general)
            }
            ForEach(ModuleCategory.allCases, id: \.self) { category in
                let modules = orderedModules(in: category)
                if !modules.isEmpty {
                    Section(AppStr.categoryName(category)) {
                        ForEach(modules, id: \.idRaw) { descriptor in
                            sidebarRow(descriptor.moduleMetadata.name,
                                       descriptor.moduleMetadata.sfSymbol,
                                       categoryColor(category))
                                .tag(SettingsSelection.module(descriptor.idRaw))
                        }
                    }
                }
            }
            Section {
                sidebarRow(AppStr.aboutHelm, "info.circle", .gray)
                    .tag(SettingsSelection.about)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)   // let the AppKit sidebar material show
    }

    /// The user's order, applied inside a category. The stored order is one
    /// flat list; the sidebar shows groups, so each group is sorted by the same
    /// list and modules the user never dragged stay in registry order.
    private func orderedModules(in category: ModuleCategory) -> [any ModuleDescriptor] {
        _ = model.orderRevision                       // redraw when it changes
        return ModuleGrouping.ordered(in: category)
    }

    private func sidebarRow(_ title: String, _ symbol: String, _ color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            HelmIconPlate(symbol: symbol, tint: color, size: 22)
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
                           tint: categoryColor(descriptor.moduleCategory),
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
                HelmCenteredContent(spacing: 14) {
                    HelmIconPlate(symbol: descriptor.moduleMetadata.sfSymbol,
                                  tint: categoryColor(descriptor.moduleCategory),
                                  size: 56)
                    Text(descriptor.moduleMetadata.name)
                        .font(.system(size: 17, weight: .semibold))
                    Text(descriptor.moduleMetadata.summary)
                        .foregroundStyle(HelmText.quiet)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
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
    @State private var showSettingsButton = AppSettings.showSettingsButton
    @State private var showQuitButton = AppSettings.showQuitButton
    @State private var orderedModules: [String] = ModuleHost.shared.orderedModuleIDs
    /// The order is read far more often than it is changed, so the controls
    /// for changing it are not on screen by default: eight rows of handles and
    /// arrow pairs read as a list of controls rather than a list of modules.
    @State private var editingOrder = false
    @State private var diskAccess: PermissionState = .granted
    @State private var accessibility: PermissionState = .granted
    private let adHocBuild = PermissionCheck.isAdHocSigned()
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
        .onAppear { orderedModules = ModuleHost.shared.orderedModuleIDs }
    }

    private func move(_ id: String, by offset: Int) {
        guard let index = orderedModules.firstIndex(of: id) else { return }
        let target = index + offset
        guard orderedModules.indices.contains(target) else { return }
        withAnimation(HelmMotion.interface) {
            orderedModules = ModuleOrder.move(orderedModules, from: IndexSet(integer: index),
                                              to: offset > 0 ? target + 1 : target)
        }
        AppSettings.moduleOrder = orderedModules
    }


    /// One module in the order list.
    ///
    /// Reading the order and rearranging it are different tasks, so the handle
    /// and the arrows appear only while the section is being edited; otherwise
    /// the row is the module and nothing else. The drag itself belongs to the
    /// `List` — see `moduleOrderList` for why that matters.
    @ViewBuilder
    private func moduleOrderRow(_ id: String,
                                _ descriptor: any ModuleDescriptor) -> some View {
        HStack(spacing: 10) {
            if editingOrder {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(HelmText.faint)
                    .accessibilityHidden(true)
            }
            HelmIconPlate(symbol: descriptor.moduleMetadata.sfSymbol,
                          tint: descriptor.moduleCategory.tint, size: 20)
            Text(descriptor.moduleMetadata.name)
            Spacer()
            if editingOrder {
                // The arrows are what a keyboard has instead of a drag.
                Button {
                    move(id, by: -1)
                } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(HelmA11y.moveUp), \(descriptor.moduleMetadata.name)")
                .disabled(orderedModules.first == id)
                Button {
                    move(id, by: 1)
                } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(HelmA11y.moveDown), \(descriptor.moduleMetadata.name)")
                .disabled(orderedModules.last == id)
            }
        }
        // A floor rather than a fixed height: the list's total is computed
        // from this number, so it has to stay nominal — but a row that cannot
        // grow clips the module name outright at larger text sizes.
        .frame(minHeight: Self.orderRowHeight)
        .contentShape(Rectangle())
        // A `List` row is its content plus the style's own vertical inset, so
        // the height set above is not the height that lands: at eight modules
        // the guessed total was two rows short and the list clipped them.
        // Zeroing the inset makes `count × orderRowHeight` exact.
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
    }

    /// The order list, and the reason it is a `List` rather than rows in the
    /// `Form` around it.
    ///
    /// `.onMove` is inert outside a `List`, so the first version carried its own
    /// `.onDrag`/`.onDrop` with an `NSItemProvider` of the row's id. That
    /// reorders, but it is not the system's drag: no lift, no gap opening under
    /// the cursor, no drop animation — the row simply appeared somewhere else
    /// on release. A `List` gives all of it for free and is what every other
    /// reorderable list on the machine does.
    ///
    /// It costs a fixed height: a `List` inside a `Form` would otherwise take
    /// whatever it is offered and scroll inside it, which is a second scroll
    /// view inside the page's own. Rows are a fixed height for the same reason,
    /// so the arithmetic is exact rather than a guess.
    private static let orderRowHeight: CGFloat = 28

    private var moduleOrderList: some View {
        // Spelled out rather than inlined: the ternary is an optional closure,
        // which the type checker cannot infer inside a `List` builder.
        var onMove: ((IndexSet, Int) -> Void)?
        if editingOrder { onMove = { moveRows(from: $0, to: $1) } }
        return List {
            ForEach(orderedModules, id: \.self) { id in
                if let descriptor = ModuleRegistry.all.first(where: { $0.idRaw == id }) {
                    moduleOrderRow(id, descriptor)
                }
            }
            .onMove(perform: onMove)
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, Self.orderRowHeight)
        .frame(height: CGFloat(orderedModules.count) * Self.orderRowHeight)
        .animation(HelmMotion.interface, value: orderedModules)
    }

    private func moveRows(from source: IndexSet, to destination: Int) {
        orderedModules = ModuleOrder.move(orderedModules, from: source, to: destination)
        AppSettings.moduleOrder = orderedModules
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
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
            }
            Section {
                Text(editingOrder ? AppStr.moduleOrderEditNote : AppStr.moduleOrderNote)
                    .font(.caption).foregroundStyle(.secondary)
                moduleOrderList
            } header: {
                HStack {
                    Text(AppStr.moduleOrderSection)
                    Spacer()
                    Button(editingOrder ? AppStr.done : AppStr.edit) {
                        withAnimation(HelmMotion.interface) {
                            editingOrder.toggle()
                        }
                    }
                    .buttonStyle(.borderless)
                    // A Form section header is styled secondary and small; a
                    // control inside it inherits that and stops reading as a
                    // control. The button says what it is instead.
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .textCase(nil)
                }
            }
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
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(AppStr.panel) {
                Toggle(AppStr.showSettingsButton, isOn: $showSettingsButton)
                    .onChange(of: showSettingsButton) { _, v in AppSettings.showSettingsButton = v }
                Toggle(AppStr.showQuitButton, isOn: $showQuitButton)
                    .onChange(of: showQuitButton) { _, v in AppSettings.showQuitButton = v }
                Text(AppStr.panelButtonsNote)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(AppStr.permissions) {
                // Driven by the table, so a new permission shows up here
                // without anyone remembering to add a row.
                ForEach(PermissionNeed.allCases, id: \.self) { need in
                    let granted = need.state(accessibility: accessibility,
                                             fullDisk: diskAccess) == .granted
                    permissionRow(AppStr.permissionTitle(need),
                                  // The ad-hoc caveat applies to every grant:
                                  // macOS ties them to the exact binary, so a
                                  // new build is a different app to it.
                                  detail: !granted && adHocBuild
                                      ? AppStr.fullDiskAccessAdHoc
                                      : AppStr.permissionWhy(need),
                                  granted: granted) { need.openSettings() }
                }
            }
            Section(AppStr.diagnostics) {
                Toggle(AppStr.writeLog, isOn: $loggingOn)
                    .onChange(of: loggingOn) { _, v in
                        AppSettings.loggingOverride = v
                        HelmLog.shared.setEnabled(v)
                    }
                Text(isDevBuild ? AppStr.logNoteDev : AppStr.logNoteStable)
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([HelmLog.fileURL])
                    } label: {
                        Label(AppStr.revealLog, systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(HelmLog.shared.currentText(), forType: .string)
                    } label: {
                        Label(AppStr.copyLog, systemImage: "doc.on.doc")
                    }
                    Button(AppStr.clearLog) { HelmLog.shared.clear() }
                }
                .controlSize(.small)
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
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One badge: which builds this copy takes.
    ///
    /// It was two — BETA for the program and DEV for the channel — on the
    /// reasoning that both facts were true. They are, but they are not two
    /// things to the person reading: pre-1.0 and "on the early channel" both
    /// answer "how finished is what I am running", and a pair reading BETA DEV
    /// makes the reader work out which one wins. The channel is the stronger
    /// claim and it subsumes the other, so it is the one shown.
    private var badge: some View {
        HelmBadge(channel == .dev ? AppStr.devBadge : AppStr.betaBadge,
                  tint: channel == .dev ? .blue : .orange,
                  emphasis: .prominent)
            .help(channel == .dev ? AppStr.channelDevNote : AppStr.channelBetaNote)
            // The badge changes with the segmented control below it; a swap
            // with no transition reads as a glitch at this size.
            .transition(.opacity)
            .animation(HelmMotion.interface, value: channel)
    }

    private var badgeAccessibilityLabel: String {
        "Helm, \(channel == .dev ? AppStr.devBadge : AppStr.betaBadge)"
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
            Divider().opacity(0.6)
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
                    .foregroundStyle(.secondary)
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
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    statusIcon("exclamationmark.triangle.fill", .orange)
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
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Button(AppStr.updateAndRelaunch) { updater.downloadAndInstall() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
            } else if updater.lastMessage == "manual-install" {
                HStack(spacing: 10) {
                    statusIcon("exclamationmark.triangle.fill", .orange)
                    Text(AppStr.updateManualInstall).lineLimit(2)
                    Spacer()
                }
            } else if updater.lastMessage == "error" {
                HStack(spacing: 10) {
                    statusIcon("exclamationmark.triangle.fill", .orange)
                    Text(AppStr.updateCheckFailed).lineLimit(1)
                    Spacer()
                    Button(AppStr.retry) { updater.checkNow() }
                }
            } else if updater.lastMessage == "up-to-date" {
                HStack(spacing: 10) {
                    statusIcon("checkmark.circle.fill", .green)
                    Text(AppStr.upToDate).lineLimit(1)
                    Spacer()
                    Button(AppStr.checkNow) { updater.checkNow() }
                }
            } else {
                // Nothing has been checked in this session: report when the
                // last check happened rather than claiming to be current.
                HStack(spacing: 10) {
                    statusIcon("arrow.triangle.2.circlepath", .secondary)
                    Text(lastCheckedText).lineLimit(1).foregroundStyle(.secondary)
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
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let when = formatter.localizedString(for: Date(timeIntervalSince1970: TimeInterval(stamp)),
                                             relativeTo: Date())
        return AppStr.lastChecked(when)
    }

    private func statusLine(_ text: String, spinning: Bool) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
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
                Button(AppStr.close, action: onClose)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Changelog.entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(entry.version).font(.title3.bold())
                                Text(entry.date).font(.caption).foregroundStyle(HelmText.faint)
                            }
                            ForEach(entry.items) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    badge(item.kind)
                                    Text(item.text).font(.callout).foregroundStyle(.secondary)
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
