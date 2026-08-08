import AppKit
import SwiftUI
import HelmUI

/// Borderless, non-activating panel shown below the status item; stacks each
/// enabled module's panel tile (settings/quit live in the right-click menu).
/// Borderless panels can't normally become key; this one must, so its SwiftUI
/// controls (toggles, text fields) accept input.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Escape closes it, as every menu and popover on the machine does.
    ///
    /// The panel took key focus so its controls would accept input, and then
    /// answered only the mouse: clicking outside dismissed it, Escape did
    /// nothing at all. Somebody who opened it from the keyboard shortcut had no
    /// way to close it from the keyboard.
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
/// It was briefly a setting, on the argument that the column count follows from
/// it. It does — 480 buys a third column — and that is not a reason to ask:
/// three columns of 147 pt in a menu-bar panel is a grid nobody wants and a
/// question everybody has to answer once.
///
/// **320, not the 300 it shipped at.** `PanelGrid.minimumTile` is 144 and the
/// prose under it argues the floor properly — «below it a button already costs
/// the figure it sits under» — and then 300 pt bought two columns of 134. Every
/// 1×1 in the app was 10 pt under a floor the app itself had written down. 320
/// is the width the mockups always used, and it makes the rule true: two tiles
/// of exactly 144.
///
/// Internal rather than `private` so `PanelWidthTests` can read it. Written out
/// as 300, that test went on passing after the panel moved to 320 — both answer
/// two columns — which is a check that cannot fail for the thing it is named
/// after.
let helmPanelWidth: CGFloat = 320
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
        // A placeholder — `reframe()` sets the real frame before every open —
        // but spelled from the width rather than left at the 300 the panel
        // shipped at before it went to 320. A stale number in a placeholder is
        // the next person's evidence about what the panel is.
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
    /// than toggled. The one accessor: a second one spelled `isVisible` sat
    /// beside this saying the same thing and was read by nobody.
    var isShown: Bool { panel.isVisible }

    private func hide() {
        removeDismissMonitor()
        panel.orderOut(nil)
    }

    /// The strip, sized and clamped to the screen the panel was opened on.
    ///
    /// Pulled out of `toggle` when the width became a setting: changing it
    /// while the panel is open has to move the window, and re-deriving the
    /// frame from the anchor is the only way that stays centred on the status
    /// item rather than growing off one edge.
    private func reframe() {
        let visible = anchorScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 8
        let width = helmPanelWidth + helmPanelShadowMargin * 2
        var x = statusButtonScreenFrame.midX - width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - width - margin)
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
    /// Posted by the icon's menu: open the panel and arrange it.
    static let helmPanelEditRequested = Notification.Name("helmPanelEditRequested")
    /// Posted when the panel is put on screen. The view is built once and
    /// stays, so there is no `onAppear` for a second opening — this is how it
    /// knows to play its entrance.
    static let helmPanelDidShow = Notification.Name("helmPanelDidShow")
}
