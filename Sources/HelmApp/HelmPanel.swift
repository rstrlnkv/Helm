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

    init(host: ModuleHost) {
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

        let hosting = NSHostingView(rootView: HelmPanelContent(host: host))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if host.enabledModules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text(AppStr.noModules).font(.headline)
                    Text(AppStr.noModulesHint)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(Array(host.enabledModules.enumerated()), id: \.offset) { _, live in
                    if let tile = live.descriptor.menuBar(live.vm)?.panelTile {
                        tile
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
