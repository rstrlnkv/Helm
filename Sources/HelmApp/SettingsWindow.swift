import AppKit
import SwiftUI
import HelmContract
import HelmUI

/// System Settings-style window: a source-list sidebar (colored icon tiles, no
/// inline toggles, no collapse button) + a detail pane. The per-module enable
/// switch lives at the top of each module's detail page.
@MainActor final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow

    init(host: ModuleHost) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Helm Settings"
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        super.init()
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsRootView(host: host))
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Menu-bar app: drop back to accessory once the settings window closes.
        NSApp.setActivationPolicy(.accessory)
    }
}

private enum SettingsSelection: Hashable {
    case general
    case module(String)
    case about
}

/// Shared System Settings-style tint per module category (used by both the
/// sidebar tile and the module detail header so they match).
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

private struct SettingsRootView: View {
    @ObservedObject var host: ModuleHost
    @State private var selection: SettingsSelection? = .general

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selection) {
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
            .frame(width: 250)
            .frame(maxHeight: .infinity)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .none, .general:
            MenuBarSettingsView()
        case .about:
            AboutHelmView()
        case .module(let id):
            if let descriptor = ModuleRegistry.all.first(where: { $0.idRaw == id }) {
                ModuleDetailView(host: host, descriptor: descriptor, id: id)
            }
        }
    }
}

/// A module's detail page: header (icon, name, summary, enable switch) + the
/// module's own settings, shown only when enabled.
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
