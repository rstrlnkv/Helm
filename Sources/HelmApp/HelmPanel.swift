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
    @State private var utilitiesExpanded = false

    /// Modules split by how they present in the panel: interactive tiles stay
    /// visible, utilities collapse behind one row so the panel stays compact.
    private var tiles: [(live: ModuleHost.Live, view: AnyView)] {
        host.enabledModules.compactMap { live in
            guard let c = live.descriptor.menuBar(live.vm), !c.isUtility, let tile = c.panelTile else { return nil }
            return (live, tile)
        }
    }
    private var utilities: [ModuleHost.Live] {
        host.enabledModules.filter { $0.descriptor.menuBar($0.vm)?.isUtility == true }
    }

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
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, item in
                    item.view
                }
                if !utilities.isEmpty {
                    UtilitiesSection(modules: utilities, expanded: $utilitiesExpanded)
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

/// One collapsed row listing the modules whose UI lives in Settings. Expanding
/// reveals compact rows; clicking one opens Settings on that module.
private struct UtilitiesSection: View {
    let modules: [ModuleHost.Live]
    @Binding var expanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(AppStr.utilities).font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(modules.count)").font(.caption).foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStr.utilities)

            if expanded {
                VStack(spacing: 2) {
                    ForEach(modules, id: \.descriptor.idRaw) { live in
                        utilityRow(live)
                    }
                }
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .helmPanelCard()
    }

    private func utilityRow(_ live: ModuleHost.Live) -> some View {
        let meta = live.descriptor.moduleMetadata
        return Button {
            NotificationCenter.default.post(name: .helmOpenSettings, object: live.descriptor.idRaw)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: meta.sfSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.pink))
                Text(meta.name).font(.callout).lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
