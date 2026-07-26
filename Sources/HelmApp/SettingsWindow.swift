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
    /// 1040 was chosen against the densest page (Homebrew: name, kind badge,
    /// version, description and an action button on one row) — narrower
    /// crowds it, wider only adds empty gutter.
    /// Measured against the densest page (a Homebrew row carries name, kind
    /// badge, version, description and an action button): at 940 the longest
    /// descriptions still fit on one line with no idle gutter to spare.
    private static let defaultSize = NSSize(width: 940, height: 660)
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
        window.setFrameAutosaveName("HelmSettingsWindow.v3")
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
        let inCategory = ModuleRegistry.all.filter { $0.moduleCategory == category }
        let ordered = ModuleOrder.apply(saved: AppSettings.moduleOrder,
                                        to: inCategory.map(\.idRaw))
        return ordered.compactMap { id in inCategory.first { $0.idRaw == id } }
    }

    private func sidebarRow(_ title: String, _ symbol: String, _ color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color))
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
                           subtitle: descriptor.moduleMetadata.summary) {
                Toggle("", isOn: Binding(
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
                VStack {
                    Spacer()
                    Text(AppStr.turnOnToConfigure(descriptor.moduleMetadata.name))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct MenuBarSettingsView: View {
    @State private var style: String = AppSettings.menuBarIconStyle
    @State private var size: String = AppSettings.menuBarIconSize
    @State private var launchAtLogin: Bool = LoginItem.isEnabled
    @State private var showSettingsButton = AppSettings.showSettingsButton
    @State private var showQuitButton = AppSettings.showQuitButton
    @State private var orderedModules: [String] = ModuleHost.shared.orderedModuleIDs
    @State private var dragging: String?
    @State private var diskAccess: PermissionState = .denied
    @State private var accessibility: PermissionState = .granted
    private let adHocBuild = PermissionCheck.isAdHocSigned()
    @State private var extensions: [SystemExtensionInfo] = []
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
        .onAppear {
            orderedModules = ModuleHost.shared.orderedModuleIDs
            dragging = nil
        }
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
            }
            Section(AppStr.moduleOrderSection) {
                Text(AppStr.moduleOrderNote)
                    .font(.caption).foregroundStyle(.secondary)
                // `.onMove` only works inside an editable List; in a Form it is
                // inert, so rows carry their own drag and drop.
                ForEach(orderedModules, id: \.self) { id in
                    if let descriptor = ModuleRegistry.all.first(where: { $0.idRaw == id }) {
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(dragging == id ? .secondary : .tertiary)
                            Image(systemName: descriptor.moduleMetadata.sfSymbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(descriptor.moduleCategory.tint))
                            Text(descriptor.moduleMetadata.name)
                            Spacer()
                            // Dragging is fiddly inside a Form; the arrows are
                            // the reliable path and keyboard-reachable.
                            Button {
                                move(id, by: -1)
                            } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(orderedModules.first == id)
                            Button {
                                move(id, by: 1)
                            } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(orderedModules.last == id)
                        }
                        .contentShape(Rectangle())
                        .opacity(dragging == id ? 0.4 : 1)
                        .onDrag {
                            dragging = id
                            return NSItemProvider(object: id as NSString)
                        }
                        // NSItemProvider(object: NSString) registers
                        // public.utf8-plain-text; accepting only `.text` meant
                        // the drop was never offered and nothing moved.
                        .onDrop(of: [.utf8PlainText, .plainText, .text],
                                delegate: ModuleDropDelegate(item: id,
                                                             order: $orderedModules,
                                                             dragging: $dragging))
                    }
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
                                  detail: need == .fullDiskAccess && !granted && adHocBuild
                                      ? AppStr.fullDiskAccessAdHoc
                                      : AppStr.permissionWhy(need),
                                  granted: granted) { need.openSettings() }
                }
                HStack {
                    Text(AppStr.systemExtensionsTitle)
                    Spacer()
                    Text(extensions.isEmpty ? AppStr.noExtensions : AppStr.extensionCount(extensions.count))
                        .foregroundStyle(.secondary)
                    Button(AppStr.manage) { PermissionCheck.openExtensionSettings() }
                        .controlSize(.small)
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
        .task {
            diskAccess = PermissionCheck.currentFullDiskAccess()
            accessibility = PermissionCheck.currentAccessibility()
            extensions = await SystemExtensionQuery.installed()
        }
    }

    private var currentStyle: MenuBarIconStyle {
        MenuBarIconStyle(rawValue: style) ?? .ring
    }
}

/// Reorders on hover while a row is being dragged, and persists on drop —
/// the pattern SwiftUI lists use, done by hand because Form has no edit mode.
private struct ModuleDropDelegate: DropDelegate {
    let item: String
    @Binding var order: [String]
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item,
              let from = order.firstIndex(of: dragging),
              let to = order.firstIndex(of: item) else { return }
        withAnimation(HelmMotion.interface) {
            order = ModuleOrder.move(order, from: IndexSet(integer: from),
                                     to: to > from ? to + 1 : to)
        }
        // Persist as it moves. A drag released outside the list never reaches
        // `performDrop`, and saving only there left the list showing an order
        // the panel and sidebar knew nothing about.
        AppSettings.moduleOrder = order
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func dropExited(info: DropInfo) { dragging = nil }

    func performDrop(info: DropInfo) -> Bool {
        AppSettings.moduleOrder = order
        dragging = nil
        return true
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
            Text("© 2026 Helm · GPL-3.0")
                .padding(.top, 6)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(width: Self.column)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(onClose: { showWhatsNew = false })
        }
    }

    private static let column: CGFloat = 380

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                RadialGradient(colors: [Color.primary.opacity(0.10), .clear],
                               center: .center, startRadius: 2, endRadius: 100)
                    .frame(width: 200, height: 200)
                // The bezel turns only while a check is running: motion here
                // means work, not decoration.
                HelmBezel(active: updater.checking)
                    .frame(width: 172, height: 172)
                HelmAppMark(size: 92)
            }
            .frame(height: 186)
            VStack(spacing: 5) {
                Text("Helm")
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.4)
                Text(AppStr.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
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
                        Text(AppStr.channelStable).tag(UpdateCheck.Channel.stable)
                        Text(AppStr.channelDev).tag(UpdateCheck.Channel.dev)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170)
                    .onChange(of: channel) { _, newValue in updater.setChannel(newValue) }
                }
                Text(channel == .dev ? AppStr.channelDevNote : AppStr.channelStableNote)
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
                                Text(entry.date).font(.caption).foregroundStyle(.tertiary)
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
                .padding()
            }
        }
        .frame(width: 520, height: 460)
    }

    private func badge(_ kind: ChangeKind) -> some View {
        Text(kind.label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(kind.color.opacity(0.2)))
            .foregroundStyle(kind.color)
            .frame(width: 44)
    }
}
