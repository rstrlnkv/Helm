import AppKit
import SwiftUI
import HelmUI

/// Borderless, non-activating panel shown below the status item; stacks each
/// enabled module's panel tile (settings/quit live in the right-click menu).
/// Borderless panels can't normally become key; this one must, so its SwiftUI
/// controls (toggles, text fields) accept input.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor final class HelmPanel: NSObject {
    private let panel: NSPanel
    private let hosting: NSHostingView<HelmPanelContent>
    private var dismissMonitor: Any?
    private var statusButtonScreenFrame: NSRect = .zero
    /// Screen the panel was opened on; clamping target for repositioning.
    private var anchorScreen: NSScreen?

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

        // The window frame is OURS: the hosting view must not auto-resize the
        // window (its resize keeps the bottom edge, pushing the top under the
        // menu bar, and correcting afterwards reads as the panel sliding down).
        // Content reports its size; applySize sets the whole frame atomically
        // with the top edge anchored under the status item.
        let sizeBox = SizeRelay()
        let hosting = NSHostingView(rootView: HelmPanelContent(host: host, sizeRelay: sizeBox))
        hosting.sizingOptions = []
        self.hosting = hosting
        panel.contentView = hosting
        super.init()
        sizeBox.onChange = { [weak self] size in self?.applySize(size) }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo statusButton: NSStatusBarButton) {
        if panel.isVisible {
            hide()
            return
        }
        guard let buttonWindow = statusButton.window else { return }
        statusButtonScreenFrame = buttonWindow.convertToScreen(statusButton.frame)
        anchorScreen = buttonWindow.screen ?? NSScreen.main
        hosting.layoutSubtreeIfNeeded()
        applySize(hosting.fittingSize)
        panel.orderFrontRegardless()
        installDismissMonitor()
    }

    /// Single atomic frame update: top edge just below the status item, clamped
    /// into the screen so an edge-adjacent status item doesn't clip the panel.
    /// Growth therefore always extends DOWNWARD; the top never moves.
    private func applySize(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let visible = anchorScreen?.visibleFrame ?? .zero
        let margin: CGFloat = 8
        var x = statusButtonScreenFrame.midX - size.width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
        var y = statusButtonScreenFrame.minY - size.height - 4
        if y < visible.minY + margin { y = visible.minY + margin }
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height),
                       display: true, animate: false)
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

/// Bridges the SwiftUI content's measured size out to `HelmPanel`, which owns
/// the window frame (the hosting view's own auto-resizing is disabled).
@MainActor final class SizeRelay {
    var onChange: ((CGSize) -> Void)?
}

private struct HelmPanelContent: View {
    @ObservedObject var host: ModuleHost
    let sizeRelay: SizeRelay
    @State private var utilitiesExpanded = false

    private struct Tile { let view: AnyView; let span: PanelTileSpan }

    /// Modules split by how they present in the panel: interactive tiles stay
    /// visible, utilities collapse behind one row so the panel stays compact.
    /// One pass — `menuBar` builds a view, so it is asked once per module.
    private var split: (tiles: [Tile], utilities: [ModuleHost.Live]) {
        var tiles: [Tile] = []
        var utilities: [ModuleHost.Live] = []
        for live in host.enabledModules {
            guard let contribution = live.descriptor.menuBar(live.vm) else { continue }
            if contribution.isUtility {
                utilities.append(live)
            } else if let tile = contribution.panelTile {
                tiles.append(Tile(view: tile, span: contribution.span))
            }
        }
        return (tiles, utilities)
    }

    /// Mirrors the stored setting; the store isn't observable, so the panel
    /// re-reads it when the settings window announces a change.
    @State private var layoutRaw = AppSettings.panelLayout
    private var layout: PanelLayoutStyle {
        PanelLayoutStyle(rawValue: layoutRaw) ?? .list
    }

    /// Control-Centre style rows: compact tiles pair up, wide tiles take a row.
    @ViewBuilder
    private func gridTiles(_ tiles: [Tile]) -> some View {
        let rows = PanelGridLayout.rows(of: tiles.map(\.span))
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            HStack(alignment: .top, spacing: 8) {
                ForEach(row, id: \.self) { index in
                    tiles[index].view
                        .environment(\.helmTileSpan, tiles[index].span)
                        .frame(maxWidth: .infinity)
                }
                // A lone compact tile keeps its half width instead of stretching.
                if row.count == 1, tiles[row[0]].span == .compact {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
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
                let (tiles, utilities) = split
                if layout == .grid {
                    gridTiles(tiles)
                } else {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                        tile.view.environment(\.helmTileSpan, .wide)
                    }
                }
                if !utilities.isEmpty {
                    UtilitiesSection(modules: utilities, expanded: $utilitiesExpanded)
                }
            }
        }
        .padding(12)
        .frame(width: 300)
        .onReceive(NotificationCenter.default.publisher(for: .helmMenuBarStyleChanged)) { _ in
            layoutRaw = AppSettings.panelLayout
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        // Report every content size (including intermediate animation frames) so
        // the window tracks the disclosure smoothly, top edge pinned.
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            sizeRelay.onChange?(size)
        }
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
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(live.descriptor.moduleCategory.tint))
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
