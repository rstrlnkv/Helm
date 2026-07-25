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
    private var selectionCancellable: AnyCancellable?

    /// Standard size for toggle-style module pages; utilities (Uninstaller,
    /// Homebrew) show large data lists and get a roomier window.
    private static let standardSize = NSSize(width: 820, height: 580)
    private static let largeSize = NSSize(width: 1100, height: 740)

    init(host: ModuleHost) {
        let model = SettingsModel(host: host)
        self.model = model
        let split = SettingsSplitViewController(model: model)
        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "Helm Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(Self.standardSize)
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        super.init()
        window.delegate = self
        selectionCancellable = model.$selection.sink { [weak self] selection in
            Task { @MainActor in self?.adjustSize(for: selection) }
        }
    }

    /// Grow the window for list-heavy utility pages, return to the standard
    /// size elsewhere. The top-left corner stays put (origin is bottom-left).
    private func adjustSize(for selection: SettingsSelection?) {
        var large = false
        if case .module(let id)? = selection,
           let descriptor = ModuleRegistry.all.first(where: { $0.idRaw == id }),
           descriptor.moduleCategory == .utilities {
            large = true
        }
        let target = large ? Self.largeSize : Self.standardSize
        guard window.frame.size != target else { return }
        var frame = window.frame
        frame.origin.y = frame.maxY - target.height
        frame.size = target
        if let vis = window.screen?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, vis.minX), max(vis.maxX - frame.width, vis.minX))
            frame.origin.y = min(max(frame.origin.y, vis.minY), max(vis.maxY - frame.height, vis.minY))
        }
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    /// `selecting` opens the window on that module's page (used by panel utility rows).
    func show(selecting moduleID: String? = nil) {
        if let moduleID { model.selection = .module(moduleID) }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Debug harness entry point (env-gated in AppDelegate).
    func showAboutForDebug() {
        model.selection = .about
        show()
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
    init(host: ModuleHost) { self.host = host }
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
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 250
        sidebarItem.maximumThickness = 250

        let detail = NSHostingController(rootView: SettingsDetail(model: model))
        // fullSizeContentView + a transparent title bar makes AppKit inset the
        // detail pane by the title-bar height, leaving a dead gap above the
        // module header. The pane draws its own top padding, so drop the inset.
        detail.safeAreaRegions = []
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
                let modules = ModuleRegistry.all.filter { $0.moduleCategory == category }
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
            HStack(spacing: 12) {
                Image(systemName: descriptor.moduleMetadata.sfSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(categoryColor(descriptor.moduleCategory)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.moduleMetadata.name).font(.title2.bold())
                    Text(descriptor.moduleMetadata.summary)
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { host.isEnabled(descriptor) },
                    set: { host.setEnabled(descriptor, $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .padding(20)
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

    var body: some View {
        Form {
            Section(AppStr.general) {
                Toggle(AppStr.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in LoginItem.setEnabled(v) }
            }
            Section(AppStr.panel) {
                Toggle(AppStr.showSettingsButton, isOn: $showSettingsButton)
                    .onChange(of: showSettingsButton) { _, v in AppSettings.showSettingsButton = v }
                Toggle(AppStr.showQuitButton, isOn: $showQuitButton)
                    .onChange(of: showQuitButton) { _, v in AppSettings.showQuitButton = v }
                Text(AppStr.panelButtonsNote)
                    .font(.caption).foregroundStyle(.secondary)
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
        }
        .formStyle(.grouped)
    }

    private var currentStyle: MenuBarIconStyle {
        MenuBarIconStyle(rawValue: style) ?? .ring
    }
}

private struct AboutHelmView: View {
    @State private var showWhatsNew = false
    @State private var channel = UpdateService.channel
    @ObservedObject private var updater = UpdateService.shared
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
    private var moduleCount: Int { ModuleRegistry.all.count }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
            VStack(spacing: 4) {
                Text("Helm").font(.system(size: 30, weight: .bold))
                Text(L("Version", [.ru: "Версия", .es: "Versión", .fr: "Version", .de: "Version", .ja: "バージョン", .zh: "版本", .pt: "Versão"]) + " \(version)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text(L("Tools for your Mac.",
                   [.ru: "Инструменты для вашего Mac.",
                    .es: "Herramientas para tu Mac.",
                    .fr: "Des outils pour votre Mac.",
                    .de: "Werkzeuge für deinen Mac.",
                    .ja: "あなたの Mac のためのツール。",
                    .zh: "为你的 Mac 打造的工具。",
                    .pt: "Ferramentas para o seu Mac."]))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(L("\(moduleCount) modules",
                   [.ru: "Модулей: \(moduleCount)", .es: "\(moduleCount) módulos", .fr: "\(moduleCount) modules",
                    .de: "\(moduleCount) Module", .ja: "\(moduleCount) 個のモジュール", .zh: "\(moduleCount) 个模块",
                    .pt: "\(moduleCount) módulos"]))
                .font(.caption).foregroundStyle(.tertiary)
            updateArea
                .font(.callout)
            channelPicker
            HStack(spacing: 16) {
                Button(AppStr.whatsNew) { showWhatsNew = true }
                if let url = URL(string: "https://github.com/rstrlnkv/Helm") {
                    Link("GitHub", destination: url)
                }
            }
            .font(.callout)
            Spacer()
            Text("© 2026 Helm").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(onClose: { showWhatsNew = false })
        }
    }

    /// Update channel: stable releases only, or dev prereleases too.
    private var channelPicker: some View {
        VStack(spacing: 4) {
            Picker(AppStr.updateChannel, selection: $channel) {
                Text(AppStr.channelStable).tag(UpdateCheck.Channel.stable)
                Text(AppStr.channelDev).tag(UpdateCheck.Channel.dev)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .onChange(of: channel) { _, newValue in updater.setChannel(newValue) }
            Text(channel == .dev ? AppStr.channelDevNote : AppStr.channelStableNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }

    @ViewBuilder
    private var updateArea: some View {
        switch updater.installState {
        case .downloading:
            progressRow(AppStr.downloadingUpdate)
        case .installing:
            progressRow(AppStr.installingUpdate)
        case .failed:
            VStack(spacing: 6) {
                Text(AppStr.updateFailed).foregroundStyle(.red)
                if let rel = updater.available {
                    Button(AppStr.updateAndRelaunch) { updater.downloadAndInstall() }
                    Link(AppStr.download, destination: rel.downloadURL ?? rel.pageURL)
                        .font(.caption)
                }
            }
        case .idle:
            if updater.checking {
                progressRow(AppStr.checking)
            } else if let rel = updater.available {
                VStack(spacing: 6) {
                    Text(AppStr.updateAvailable(rel.version))
                    Button(AppStr.updateAndRelaunch) { updater.downloadAndInstall() }
                        .buttonStyle(.borderedProminent)
                }
            } else if updater.lastMessage == "up-to-date" {
                HStack(spacing: 10) {
                    Text(AppStr.upToDate).foregroundStyle(.secondary)
                    Button(AppStr.checkForUpdates) { updater.checkNow() }.controlSize(.small)
                }
            } else {
                Button(AppStr.checkForUpdates) { updater.checkNow() }.controlSize(.small)
            }
        }
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

/// Localized, structured changelog with New/Upd/Fix badges.
private struct WhatsNewView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(AppStr.whatsNew).font(.headline)
                Spacer()
                Button(AppStr.close, action: onClose)
            }
            .padding()
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
