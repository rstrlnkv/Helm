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
                sidebarRow(AppStr.menuBar, "menubar.rectangle", .gray)
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

    var body: some View {
        Form {
            Section(AppStr.general) {
                Toggle(AppStr.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in LoginItem.setEnabled(v) }
            }
            Section(AppStr.iconShape) {
                HStack(spacing: 14) {
                    ForEach(MenuBarIconStyle.allCases, id: \.rawValue) { s in
                        styleTile(s)
                    }
                }
                .padding(.vertical, 4)
            }
            Section(AppStr.iconSize) {
                Picker(AppStr.size, selection: $size) {
                    ForEach(MenuBarIconSize.allCases, id: \.rawValue) { sz in
                        Text(sz.label).tag(sz.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: size) { _, v in AppSettings.menuBarIconSize = v }
            }
            Section {
                Text(AppStr.menuBarNote)
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
            Text(s.label)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(height: 26)
        }
        .frame(width: 76, height: 66)
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
    @State private var showWhatsNew = false
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
            Text(L("A menu-bar suite of macOS utilities.",
                   [.ru: "Набор macOS-утилит в строке меню.",
                    .es: "Un conjunto de utilidades de macOS en la barra de menús.",
                    .fr: "Une suite d’utilitaires macOS dans la barre des menus.",
                    .de: "Eine Menüleisten-Sammlung von macOS-Werkzeugen.",
                    .ja: "メニューバーの macOS ユーティリティ集。",
                    .zh: "菜单栏中的 macOS 实用工具套件。",
                    .pt: "Um conjunto de utilitários do macOS na barra de menus."]))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(L("\(moduleCount) modules",
                   [.ru: "Модулей: \(moduleCount)", .es: "\(moduleCount) módulos", .fr: "\(moduleCount) modules",
                    .de: "\(moduleCount) Module", .ja: "\(moduleCount) 個のモジュール", .zh: "\(moduleCount) 个模块",
                    .pt: "\(moduleCount) módulos"]))
                .font(.caption).foregroundStyle(.tertiary)
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
}

/// Renders the bundled CHANGELOG.md with light block styling.
private struct WhatsNewView: View {
    let onClose: () -> Void

    private var lines: [String] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n")
    }

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
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        lineView(line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .frame(width: 480, height: 440)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.hasPrefix("### ") {
            Text(line.dropFirst(4)).font(.subheadline.bold()).padding(.top, 4)
        } else if line.hasPrefix("## ") {
            Text(line.dropFirst(3)).font(.headline).padding(.top, 6)
        } else if line.hasPrefix("# ") {
            Text(line.dropFirst(2)).font(.title3.bold())
        } else if line.hasPrefix("- ") {
            Text("•  " + line.dropFirst(2)).font(.callout).foregroundStyle(.secondary)
        } else if line.hasPrefix("  ") && !line.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(line.trimmingCharacters(in: .whitespaces)).font(.callout).foregroundStyle(.secondary)
        } else if !line.isEmpty {
            Text(line).font(.callout).foregroundStyle(.secondary)
        }
    }
}
