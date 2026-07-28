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

/// One width for the strip window and the card content inside it.
private let helmPanelWidth: CGFloat = 300
/// Room on each side of the card for the glass to cast into.
///
/// A window shadow is drawn by the window server *outside* the frame, so the
/// strip could be exactly as wide as the card. Glass draws its shading inside
/// the view, so with the two the same width the card's own shadow was cut off
/// flat at the left and right edges. The band is transparent and behaves like
/// the rest of the strip below the card: a click there dismisses the panel.
private let helmPanelShadowMargin: CGFloat = 28

@MainActor final class HelmPanel: NSObject {
    private let panel: NSPanel
    private let hosting: NSHostingView<HelmPanelContent>
    private var dismissMonitor: Any?
    private var dismissObserver: NSObjectProtocol?
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
        // The window draws no shadow: Liquid Glass carries its own, and the two
        // disagree about what the silhouette is. With `.regularMaterial` the
        // window's shadow was derived from the opaque part — the card — and
        // looked right. Glass paints its backdrop across the hosting view,
        // which is a transparent strip running from the status item to the
        // bottom of the screen, so AppKit started shading *that*: a hairline
        // tracing the shadow instead of the card's edge.
        panel.hasShadow = false
        panel.isMovable = false
        self.panel = panel

        // Sized ONCE per open (a transparent strip from the status item to the
        // screen bottom) and never moved while visible: moving a transparent
        // layer-backed window drags its composited surface ahead of the SwiftUI
        // redraw, which is what made an animating card look like it slid. The
        // card is top-pinned and animates entirely inside the static window.
        // A plain NSHostingView is used deliberately — a custom hitTest here
        // previously swallowed every click.
        let hosting = NSHostingView(rootView: HelmPanelContent(host: host))
        hosting.sizingOptions = []
        self.hosting = hosting
        panel.contentView = hosting
        super.init()
        dismissObserver = NotificationCenter.default.addObserver(
            forName: .helmPanelDismissRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
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
        let width = helmPanelWidth + helmPanelShadowMargin * 2
        var x = statusButtonScreenFrame.midX - width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - width - margin)
        let top = statusButtonScreenFrame.minY - 4
        let bottom = visible.minY + margin
        panel.setFrame(NSRect(x: x, y: bottom, width: width, height: max(top - bottom, 120)),
                       display: true, animate: false)
        panel.orderFrontRegardless()
        // Key focus (no app activation) is what makes SwiftUI animations tick.
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

extension Notification.Name {
    /// Posted when the transparent area under the card is clicked.
    static let helmPanelDismissRequested = Notification.Name("helmPanelDismissRequested")
}

private struct HelmPanelContent: View {
    @ObservedObject var host: ModuleHost
    @State private var utilitiesExpanded = false
    @State private var showSettingsButton = AppSettings.showSettingsButton
    @State private var showQuitButton = AppSettings.showQuitButton
    /// Bumped when the user reorders modules so the panel rebuilds its rows.
    @State private var orderTick = 0

    /// Optional shortcuts; both actions also live in the status item's
    /// right-click menu, so they stay off by default. Rendered as a card row so
    /// they read as part of the panel rather than loose text under it.
    private var footer: some View {
        HStack(spacing: 8) {
            if showSettingsButton {
                footerButton(AppStr.settingsPane, "gearshape") {
                    NotificationCenter.default.post(name: .helmOpenSettings, object: nil)
                }
            }
            if showSettingsButton && showQuitButton { Spacer() }
            if showQuitButton {
                footerButton(AppStr.quit, "power") { NSApp.terminate(nil) }
            }
        }
        .helmPanelCard()
    }

    private func footerButton(_ title: String, _ symbol: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title).font(.subheadline.weight(.medium))
            }
            .foregroundStyle(HelmText.quiet)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private struct Tile { let view: AnyView }

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
                tiles.append(Tile(view: tile))
            }
        }
        return (tiles, utilities)
    }

    var body: some View {
        VStack(spacing: 0) {
            card
                .id(orderTick)
            // Transparent filler: the window spans a strip, so a click below the
            // card should dismiss (a menu behaves the same way).
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    NotificationCenter.default.post(name: .helmPanelDismissRequested, object: nil)
                }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: .helmModuleOrderChanged)) { _ in
            orderTick &+= 1
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            if host.enabledModules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 30))
                        .foregroundStyle(HelmText.quiet)
                    Text(AppStr.noModules).font(.headline)
                    Text(AppStr.noModulesHint)
                        .font(.caption).foregroundStyle(HelmText.quiet)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                let (tiles, utilities) = split
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    tile.view
                }
                if !utilities.isEmpty {
                    UtilitiesSection(modules: utilities, expanded: $utilitiesExpanded)
                }
                if showSettingsButton || showQuitButton { footer }
            }
        }
        .padding(12)
        .frame(width: helmPanelWidth)
        .onReceive(NotificationCenter.default.publisher(for: .helmMenuBarStyleChanged)) { _ in
            showSettingsButton = AppSettings.showSettingsButton
            showQuitButton = AppSettings.showQuitButton
        }
        // Liquid Glass, and no border of our own: glass supplies its specular
        // edge, and a hand-drawn hairline on top of it doubles the line. 26 pt
        // rather than 20 so the radius is concentric with the 14 pt tile cards
        // inside at 12 pt of padding — that is what makes them read as nested
        // rather than merely stacked.
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .containerShape(.rect(cornerRadius: 26))
        // Centred in a strip that is wider than the card, so the glass has
        // somewhere to cast. This must come after the glass: applied before
        // it, the effect painted the whole strip and the card came out 56 pt
        // wider than the tiles inside it.
        .frame(maxWidth: .infinity)
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
    /// Natural height of the rows, measured so the disclosure animates between
    /// 0 and a concrete value.
    @State private var rowsHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(HelmMotion.disclosure) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HelmText.quiet)
                    Text(AppStr.utilities).font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(modules.count)").font(.caption).foregroundStyle(HelmText.faint)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HelmText.faint)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStr.utilities)

            // Measured height rather than `if expanded`: with the rows removed
            // from the hierarchy the card's background collapsed instantly
            // while the disappearing rows kept drawing over whatever sat
            // below. Keeping them mounted and clipping to an animated height
            // means the block's edge always contains its content — the same
            // pattern Keep Awake's inline block uses.
            VStack(spacing: 2) {
                ForEach(modules, id: \.descriptor.idRaw) { live in
                    utilityRow(live)
                }
            }
            .padding(.top, 8)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                if height > 0 { rowsHeight = height }
            }
            .frame(height: expanded ? rowsHeight : 0, alignment: .top)
            // Height + clipping only: fading would isolate these rows in their
            // own layer and their materials would stop blending with the card.
            .clipped()
            .allowsHitTesting(expanded)
        // `.clipped()` hides it from the eye, not from the accessibility tree.
        .accessibilityHidden(!expanded)
        }
        .helmPanelCard()
    }

    private func utilityRow(_ live: ModuleHost.Live) -> some View {
        let meta = live.descriptor.moduleMetadata
        return Button {
            NotificationCenter.default.post(name: .helmOpenSettings, object: live.descriptor.idRaw)
        } label: {
            HStack(spacing: 8) {
                HelmIconPlate(symbol: meta.sfSymbol,
                              tint: live.descriptor.moduleCategory.tint, size: 20)
                Text(meta.name).font(.callout).lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(HelmText.faint)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
