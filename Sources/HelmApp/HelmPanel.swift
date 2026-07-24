import AppKit
import SwiftUI
import HelmUI

/// Borderless, non-activating panel shown below the status item. Stacks
/// each enabled module's panel tile, with a small Settings/Quit footer.
/// Borderless panel that can still become key so its SwiftUI controls work.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor final class HelmPanel: NSObject {
    private let panel: NSPanel
    private var dismissMonitor: Any?
    private var statusButtonScreenFrame: NSRect = .zero

    init(host: ModuleHost, onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        // NOT hidesOnDeactivate: the app is usually inactive when the panel is
        // shown from the menu bar, which would hide it instantly. We dismiss it
        // ourselves via an outside-click monitor.
        panel.hidesOnDeactivate = false
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
            hide()
            return
        }
        guard let buttonWindow = statusButton.window else { return }
        let buttonFrameInScreen = buttonWindow.convertToScreen(statusButton.frame)
        statusButtonScreenFrame = buttonFrameInScreen
        panel.layoutIfNeeded()
        let panelSize = panel.frame.size
        // Clamp into the button's screen so a status item near an edge doesn't
        // push the panel off-screen (right side clipped near the notch/corner).
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let margin: CGFloat = 8
        var x = buttonFrameInScreen.midX - panelSize.width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - panelSize.width - margin)
        var y = buttonFrameInScreen.minY - panelSize.height - 4
        if y < visible.minY + margin { y = visible.minY + margin }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
        installDismissMonitor()
    }

    private func hide() {
        removeDismissMonitor()
        panel.orderOut(nil)
    }

    /// Close the panel when the user clicks outside it (but not on the status
    /// item itself — that click re-toggles through the normal path).
    private func installDismissMonitor() {
        removeDismissMonitor()
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            if self.statusButtonScreenFrame.contains(loc) { return }
            self.hide()
        }
    }

    private func removeDismissMonitor() {
        if let dismissMonitor {
            NSEvent.removeMonitor(dismissMonitor)
            self.dismissMonitor = nil
        }
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(host.enabledModules.enumerated()), id: \.offset) { _, live in
                    if let tile = live.descriptor.menuBar(live.vm)?.panelTile {
                        tile
                    }
                }
            }

            Divider().padding(.horizontal, -2)

            HStack(spacing: 16) {
                footerButton("Settings", "gearshape", action: onOpenSettings)
                Spacer()
                footerButton("Quit", "power", action: onQuit)
            }
            .padding(.horizontal, 2)
        }
        .padding(12)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func footerButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
