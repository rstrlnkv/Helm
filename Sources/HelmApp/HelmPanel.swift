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

/// Hosting view that lets clicks below the card fall through: the window spans a
/// transparent strip, so only the card itself should catch events. Pass-through
/// clicks reach the global outside-click monitor and dismiss the panel.
private final class PassThroughHostingView: NSHostingView<HelmPanelContent> {
    var cardHeight: () -> CGFloat = { .greatestFiniteMagnitude }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localY = isFlipped ? point.y : bounds.height - point.y
        guard localY <= cardHeight() else { return nil }
        return super.hitTest(point)
    }
}

@MainActor final class HelmPanel: NSObject {
    private let panel: NSPanel
    private let hosting: PassThroughHostingView
    private let sizeRelay: SizeRelay
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

        // Two facts drive this design, both established by measurement:
        //  1. Moving a transparent layer-backed window's origin shifts the
        //     composited surface before SwiftUI redraws, so a window that
        //     resizes per animation frame drags the card with it.
        //  2. A non-activating panel only ticks animations once it is key.
        // Hence: the window is sized ONCE per open (a transparent strip from the
        // status item to the screen bottom) and never moves; the card is
        // top-pinned inside it and animates purely in SwiftUI.
        let sizeBox = SizeRelay()
        let hosting = PassThroughHostingView(rootView: HelmPanelContent(host: host, sizeRelay: sizeBox))
        hosting.sizingOptions = []
        hosting.cardHeight = { [weak sizeBox] in sizeBox?.lastSize.height ?? .greatestFiniteMagnitude }
        self.hosting = hosting
        self.sizeRelay = sizeBox
        panel.contentView = hosting
        super.init()
        // The card's opaque shape changes inside a static window; keep the shadow
        // following it rather than lagging a size behind.
        sizeBox.onChange = { [weak self] _ in self?.panel.invalidateShadow() }
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
        let visible = anchorScreen?.visibleFrame ?? .zero
        let margin: CGFloat = 8
        let width: CGFloat = 300
        var x = statusButtonScreenFrame.midX - width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - width - margin)
        let top = statusButtonScreenFrame.minY - 4
        let bottom = visible.minY + margin
        panel.setFrame(NSRect(x: x, y: bottom, width: width, height: max(top - bottom, 100)),
                       display: true, animate: false)
        panel.orderFrontRegardless()
        // Key focus (without activating the app) is what makes animations tick.
        panel.makeKey()
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

/// Bridges the SwiftUI content's measured size out to `HelmPanel`, which owns
/// the window frame (the hosting view's own auto-resizing is disabled).
@MainActor final class SizeRelay {
    var onChange: ((CGSize) -> Void)?
    /// Last measured card size; `toggle` prefers it over `fittingSize`, which
    /// is unreliable once the root view is wrapped in an expanding frame.
    private(set) var lastSize: CGSize = .zero
    func report(_ size: CGSize) {
        lastSize = size
        onChange?(size)
    }
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
        // Report every content size so the window tracks height changes.
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            sizeRelay.report(size)
        }
        // Pin the card to the TOP of the hosting bounds: while window and content
        // sizes momentarily disagree, the slack stays at the transparent bottom
        // instead of the default centering, which read as the card dropping.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                withAnimation(.easeInOut(duration: 0.24)) { expanded.toggle() }
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
                    ForEach(Array(modules.enumerated()), id: \.element.descriptor.idRaw) { index, live in
                        utilityRow(live)
                            // Each row fades slightly after the previous one.
                            .transition(.opacity.animation(
                                .easeOut(duration: 0.18).delay(Double(index) * 0.06)))
                    }
                }
                .padding(.top, 8)
                // Fade only. `.move(edge: .top)` made the rows fly in from above
                // and paint OVER the header mid-animation; the card's own height
                // change (animated by the enclosing withAnimation) is what should
                // reveal them, growing downward.
                .transition(.opacity)
            }
        }
        // Clip so rows can never draw outside the card while it grows.
        .clipped()
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
