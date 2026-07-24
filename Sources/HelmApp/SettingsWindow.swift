import AppKit
import SwiftUI
import HelmContract
import HelmUI

/// Standard titled settings window: sidebar of modules grouped by category
/// (with enable toggles) + an "About Helm" entry, detail shows the selected
/// module's settings page.
@MainActor final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow

    init(host: ModuleHost) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
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
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Menu-bar app: drop back to accessory once the last regular window closes.
        NSApp.setActivationPolicy(.accessory)
    }
}

private enum SettingsSelection: Hashable {
    case module(String)
    case about
}

private struct SettingsRootView: View {
    @ObservedObject var host: ModuleHost
    @State private var selection: SettingsSelection?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(ModuleCategory.allCases, id: \.self) { category in
                    let modules = ModuleRegistry.all.filter { $0.moduleCategory == category }
                    if !modules.isEmpty {
                        Section(category.rawValue.capitalized) {
                            ForEach(modules, id: \.idRaw) { descriptor in
                                moduleRow(descriptor)
                                    .tag(SettingsSelection.module(descriptor.idRaw))
                            }
                        }
                    }
                }
                Section {
                    Label("About Helm", systemImage: "info.circle")
                        .tag(SettingsSelection.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
        }
    }

    @ViewBuilder
    private func moduleRow(_ descriptor: any ModuleDescriptor) -> some View {
        HStack {
            Label(descriptor.moduleMetadata.name, systemImage: descriptor.moduleMetadata.sfSymbol)
            Spacer()
            Toggle("", isOn: Binding(
                get: { host.isEnabled(descriptor) },
                set: { host.setEnabled(descriptor, $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .none:
            Text("Select a module")
                .foregroundStyle(.secondary)
        case .about:
            AboutHelmView()
        case .module(let id):
            if let descriptor = ModuleRegistry.all.first(where: { $0.idRaw == id }) {
                if let live = host.liveModule(id) {
                    descriptor.settingsPage(live.vm)
                } else {
                    Text("Enable \(descriptor.moduleMetadata.name) to configure it.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AboutHelmView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Helm")
                .font(.largeTitle.bold())
            Text("A lightweight menu-bar module host for macOS.")
                .foregroundStyle(.secondary)
        }
    }
}
