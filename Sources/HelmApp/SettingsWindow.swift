import AppKit
import SwiftUI
import HelmContract
import HelmUI

/// System Settings-style settings window built on AppKit `NSSplitViewController`
/// so the sidebar is a full-height vibrant source list (traffic lights float
/// over it, no title-bar strip). Each pane hosts a SwiftUI view; a shared
/// `SettingsModel` carries the selection between them.
@MainActor final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let model: SettingsModel

    init(host: ModuleHost) {
        let model = SettingsModel(host: host)
        self.model = model
        let split = SettingsSplitViewController(model: model)
        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "Helm Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 820, height: 580))
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        super.init()
        window.delegate = self
    }

    func show() {
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
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 250
        sidebarItem.maximumThickness = 250

        let detail = NSHostingController(rootView: SettingsDetail(model: model))
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 420

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
    }
}

// MARK: - Category tint

private func categoryColor(_ category: ModuleCategory) -> Color {
    switch category {
    case .power: return .orange
    case .network: return .indigo
    case .clipboard: return .blue
    case .window: return .green
    case .media: return .pink
    case .files: return .cyan
    case .appearance: return .purple
    case .misc: return .gray
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        List(selection: $model.selection) {
            Section {
                sidebarRow("Menu Bar", "menubar.rectangle", .gray)
                    .tag(SettingsSelection.general)
            }
            ForEach(ModuleCategory.allCases, id: \.self) { category in
                let modules = ModuleRegistry.all.filter { $0.moduleCategory == category }
                if !modules.isEmpty {
                    Section(category.rawValue.capitalized) {
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
                sidebarRow("About Helm", "info.circle", .gray)
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
                    Text("Turn on \(descriptor.moduleMetadata.name) to configure it.")
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

    var body: some View {
        Form {
            Section("Icon shape") {
                HStack(spacing: 14) {
                    ForEach(MenuBarIconStyle.allCases, id: \.rawValue) { s in
                        styleTile(s)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Icon size") {
                Picker("Size", selection: $size) {
                    ForEach(MenuBarIconSize.allCases, id: \.rawValue) { sz in
                        Text(sz.label).tag(sz.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: size) { _, v in AppSettings.menuBarIconSize = v }
            }
            Section {
                Text("The Helm ring turns your Keep Awake color while active, white when idle.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func styleTile(_ s: MenuBarIconStyle) -> some View {
        let selected = style == s.rawValue
        return VStack(spacing: 6) {
            Image(nsImage: RingIcon.make(style: s, size: .large, tintToken: "blue"))
                .frame(width: 24, height: 24)
            Text(s.label).font(.caption2)
        }
        .frame(width: 68, height: 58)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            style = s.rawValue
            AppSettings.menuBarIconStyle = s.rawValue
        }
    }
}

private struct AboutHelmView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: RingIcon.make(style: .ring, size: .large, tintToken: "blue"))
                .resizable().frame(width: 64, height: 64)
            Text("Helm").font(.largeTitle.bold())
            Text("A lightweight menu-bar module host for macOS.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
