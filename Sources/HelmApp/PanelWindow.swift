import AppKit
import SwiftUI
import HelmRuntime
import HelmUI

/// Borderless, non-activating panel shown below the status item; stacks each
/// enabled module's panel tile (settings/quit live in the right-click menu and, when
/// switched on, the panel's footer).
/// Borderless panels can't normally become key; this one must, so its SwiftUI
/// controls (toggles, text fields) accept input.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Escape closes it, as every menu and popover on the machine does, so a
    /// panel opened from the keyboard can be closed from it.
    ///
    /// `cancelOperation` rather than a key handler: it is what AppKit sends for
    /// Escape *and* for ⌘. , and it arrives after the responder chain has had
    /// its say — so a text field mid-edit or a `HelmHotkeyRecorder` capturing a
    /// shortcut still gets to take the key first. It goes out as the same
    /// notification the click-through path posts, so there is one way to close.
    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: .helmPanelDismissRequested, object: nil)
    }
}

/// One width for the strip window and the card content inside it.
///
/// Not a setting: a wider panel buys a third column, and three narrow columns
/// in a menu-bar panel are a grid nobody wants and a question everybody would
/// have to answer once.
///
/// **320** is two `PanelGrid.minimumTile` tiles of exactly 144, one
/// `PanelGrid.gap` and `PanelGrid.padding` either side: below the floor a
/// button already costs the figure it sits under.
let helmPanelWidth: CGFloat = PanelGrid.minimumTile * 2 + PanelGrid.gap + PanelGrid.padding * 2
/// Room on each side of the card for the glass to cast into.
///
/// Glass draws its shading inside the view, unlike a window shadow, so a strip
/// as wide as the card would cut the card's shadow off flat at the left and
/// right edges. The band is transparent and behaves like the rest of the strip
/// below the card: a click there dismisses the panel.
private let helmPanelShadowMargin: CGFloat = 28

@MainActor final class HelmPanel: NSObject {
    private let panel: NSPanel
    private var dismissMonitor: Any?
    /// The global monitor never sees a click into Helm's own windows (Settings);
    /// this one does.
    private var localDismissMonitor: Any?
    private var dismissObserver: NSObjectProtocol?
    private var statusButtonScreenFrame: NSRect = .zero
    /// Screen the panel was opened on; clamping target for repositioning.
    private var anchorScreen: NSScreen?

    init(host: ModuleHost) {
        // A placeholder (`reframe()` sets the real frame before every open),
        // spelled from the width so it cannot become a stale number.
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0,
                                width: helmPanelWidth + helmPanelShadowMargin * 2, height: 200),
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
        // disagree about what the silhouette is. Glass paints its backdrop
        // across the hosting view, a transparent strip from the status item to
        // the bottom of the screen, so a window shadow would trace the strip
        // rather than the card's edge.
        panel.hasShadow = false
        panel.isMovable = false
        self.panel = panel

        // Sized ONCE per open (a transparent strip from the status item to the
        // screen bottom) and never moved while visible: moving a transparent
        // layer-backed window drags its composited surface ahead of the SwiftUI
        // redraw, so an animating card would look like it slid. The card is
        // top-pinned and animates entirely inside the static window.
        // A plain NSHostingView, deliberately: a custom hitTest here swallows
        // every click.
        let hosting = NSHostingView(rootView: HelmPanelContent(host: host))
        hosting.sizingOptions = []
        panel.contentView = hosting
        super.init()
        dismissObserver = NotificationCenter.default.addObserver(
            forName: .helmPanelDismissRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func toggle(relativeTo statusButton: NSStatusBarButton) {
        if panel.isVisible {
            hide()
            return
        }
        guard let buttonWindow = statusButton.window else { return }
        statusButtonScreenFrame = buttonWindow.convertToScreen(statusButton.frame)
        anchorScreen = buttonWindow.screen ?? NSScreen.main
        reframe()
        panel.orderFrontRegardless()
        // Key focus (no app activation) is what makes SwiftUI animations tick.
        panel.makeKey()
        NotificationCenter.default.post(name: .helmPanelDidShow, object: nil)
        installDismissMonitor()
    }

    /// Whether the panel is on screen, for a caller that wants it open rather
    /// than toggled.
    var isShown: Bool { panel.isVisible }

    private func hide() {
        removeDismissMonitor()
        panel.orderOut(nil)
    }

    /// The strip, sized and clamped to the screen the panel was opened on.
    ///
    /// Called once per opening, before the panel is ordered front. Derived from
    /// the anchor, so it stays centred on the status item rather than growing
    /// off one edge.
    private func reframe() {
        let visible = anchorScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 8
        let width = helmPanelWidth + helmPanelShadowMargin * 2
        let leftmost = visible.minX + margin
        // Raised to the left edge before the range is formed: with no screen
        // attached `visible` is `.zero`, and a range whose upper bound is below
        // its lower one traps on its own initialiser. The panel then sits at the
        // left edge rather than off it.
        let rightmost = max(leftmost, visible.maxX - width - margin)
        let x = (statusButtonScreenFrame.midX - width / 2).clamped(to: leftmost...rightmost)
        let top = statusButtonScreenFrame.minY - 4
        let bottom = visible.minY + margin
        panel.setFrame(NSRect(x: x, y: bottom, width: width, height: max(top - bottom, 120)),
                       display: true, animate: false)
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
        localDismissMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window !== self.panel else { return event }
            if self.statusButtonScreenFrame.contains(NSEvent.mouseLocation) { return event }
            self.hide()
            return event
        }
    }

    private func removeDismissMonitor() {
        if let dismissMonitor {
            NSEvent.removeMonitor(dismissMonitor)
            self.dismissMonitor = nil
        }
        if let localDismissMonitor {
            NSEvent.removeMonitor(localDismissMonitor)
            self.localDismissMonitor = nil
        }
    }
}

extension Notification.Name {
    /// Posted when the transparent area under the card is clicked.
    static let helmPanelDismissRequested = Notification.Name("helmPanelDismissRequested")
    /// Posted by the icon's menu: open the panel and arrange it.
    static let helmPanelEditRequested = Notification.Name("helmPanelEditRequested")
    /// Posted when the panel is put on screen. The view is built once and
    /// stays, so there is no `onAppear` for a second opening — this is how it
    /// knows to play its entrance.
    static let helmPanelDidShow = Notification.Name("helmPanelDidShow")
}
