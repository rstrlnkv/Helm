import AppKit
import SwiftUI
import HelmUI

/// Borderless, non-activating panel shown below the status item. Stacks
/// each enabled module's panel tile, with a small Settings/Quit footer.
@MainActor final class HelmPanel: NSObject {
    private let panel: NSPanel

    init(host: ModuleHost, onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        self.panel = panel
        super.init()

        let content = HelmPanelContent(host: host, onOpenSettings: { [weak self] in
            self?.panel.orderOut(nil)
            onOpenSettings()
        }, onQuit: onQuit)
        let hosting = NSHostingView(rootView: content)
        panel.contentView = hosting
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo statusButton: NSStatusBarButton) {
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        guard let buttonWindow = statusButton.window else { return }
        let buttonFrameInScreen = buttonWindow.convertToScreen(statusButton.frame)
        panel.layoutIfNeeded()
        let panelSize = panel.frame.size
        let x = buttonFrameInScreen.midX - panelSize.width / 2
        let y = buttonFrameInScreen.minY - panelSize.height - 4
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        // Activate so a non-activating panel with hidesOnDeactivate stays put
        // (otherwise it appears then vanishes because the app was never active);
        // clicking away then deactivates the app and dismisses the panel.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }
}

private struct HelmPanelContent: View {
    @ObservedObject var host: ModuleHost
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if host.enabledModules.isEmpty {
                Text("No modules enabled")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
            } else {
                ForEach(Array(host.enabledModules.enumerated()), id: \.offset) { _, live in
                    if let tile = live.descriptor.menuBar(live.vm)?.panelTile {
                        tile
                    }
                }
            }

            Divider()

            HStack {
                Button("Settings…", action: onOpenSettings)
                    .buttonStyle(.plain)
                Spacer()
                Button("Quit", action: onQuit)
                    .buttonStyle(.plain)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .padding(.top, 4)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
