import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Launchpad_Engine

/// The window's panel: borderless and non-activating over the whole screen, so Helm stays an accessory (no Dock icon, no
/// Space pulled) and the app in front stays the one in front.
///
/// The keys it acts on are taken here, by key code (Esc 53, Return 36 and 76, the arrows 123 to 126, Tab 48), before the
/// text field sees them: the layout of the keyboard does not matter, and the arrows move the choice instead of the caret,
/// except Left and Right while the search holds text, which stay the field's (caret movement); Up and Down are the grid's, Tab is taken and does nothing.
/// Nothing is taken while the field editor holds marked text (an input method's composition), and a key with Command,
/// Control or Option falls through. The wheel and the trackpad turn pages through `LaunchpadScrollPager`; with a folder's
/// card open they fall through, to the card's own scrolling. The rest, the typing included, is the text field's.
///
/// What was measured of menus and tooltips in a panel like this is `OverlayPanel`'s doc comment; this panel's own live
/// readings (typing, the context menu, closing on resign) are the owner's, in Helm Dev.
final class LaunchpadPanel: NSPanel {
    var state: LaunchpadScreenState?
    var onResignKey: (() -> Void)?
    private var pager = LaunchpadScrollPager()

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func sendEvent(_ event: NSEvent) {
        if !handle(event) { super.sendEvent(event) }
    }

    /// True when the event was this window's and goes no further.
    private func handle(_ event: NSEvent) -> Bool {
        guard let state else { return false }
        switch event.type {
        case .keyDown:
            if let editor = firstResponder as? NSTextView, editor.hasMarkedText() { return false }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
            if (event.keyCode == 123 || event.keyCode == 124), !state.search.isEmpty { return false }
            switch event.keyCode {
            case 53: state.escape()
            case 36, 76: state.activate()
            case 123: state.move(dx: -1, dy: 0)
            case 124: state.move(dx: 1, dy: 0)
            case 125: state.move(dx: 0, dy: 1)
            case 126: state.move(dx: 0, dy: -1)
            case 48: break
            default: return false
            }
            return true
        case .scrollWheel:
            guard state.openFolder == nil else { return false }
            if let step = pager.feed(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                                     phase: event.phase, momentum: event.momentumPhase, time: event.timestamp) {
                withAnimation(HelmMotion.interface) { state.turn(step) }
            }
            return true
        default:
            return false
        }
    }
}

/// What ends the window besides its own keys and clicks: another app coming forward, the Space changing, the screens changing.
/// Held by the window; the observers go with this object.
private final class LaunchpadWindowEnders {
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    @MainActor init(_ end: @escaping @MainActor () -> Void) {
        let workspace = NSWorkspace.shared.notificationCenter
        let mine = ProcessInfo.processInfo.processIdentifier
        tokens.append((workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.processIdentifier != mine { MainActor.assumeIsolated { end() } }
        }))
        tokens.append((workspace, workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { end() }
        }))
        let center = NotificationCenter.default
        tokens.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { end() }
        }))
    }

    deinit { for entry in tokens { entry.center.removeObserver(entry.token) } }
}

/// The Launchpad window: built when the person asks for it, gone when it closes, holding nothing in between.
///
/// **Level.** One below pop-up menus (`popUpMenu` is 101, so 100): above the menu bar (24), the Dock (20), status items
/// (25) and every window, and under a context menu opened from a tile, which would otherwise draw behind the panel
/// that opened it. Every Space and over full-screen apps, as `OverlayPanel`.
///
/// Built on the screen the pointer is on, its geometry worked out once. The model's `whileShown()` runs for as long as
/// the window is open, and its snapshot goes when the window does. It closes on Esc, a click on the empty background, an
/// app that opened, the panel losing key, another app coming forward, the Space or the screens changing, the model
/// stopping and the shortcut's second press.
@MainActor final class LaunchpadWindow: LaunchpadWindowHandle {
    /// One below the pop-up menu level.
    static let level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)

    var onClose: (@MainActor () -> Void)?
    private let panel: LaunchpadPanel
    private let state: LaunchpadScreenState
    private weak var model: LaunchpadViewModel?
    private var watchTask: Task<Void, Never>?
    private var enders: LaunchpadWindowEnders?
    private var closed = false
    private var opened = false
    private let footprintBefore = MemoryFootprint.current()

    init(model: LaunchpadViewModel) {
        self.model = model
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = screen?.frame ?? CGRect(origin: .zero, size: LaunchpadGeometry.fallback)
        let geometry = LaunchpadGeometry.make(for: frame.size, topSafe: screen?.safeAreaInsets.top ?? 0)
        state = LaunchpadScreenState(geometry: geometry)

        panel = LaunchpadPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = Self.level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.state = state

        let blur = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
        blur.blendingMode = .behindWindow
        blur.material = .fullScreenUI
        blur.state = .active
        let hosting = NSHostingView(rootView: LaunchpadScreen(vm: model, state: state))
        hosting.sizingOptions = []
        hosting.frame = blur.bounds
        hosting.autoresizingMask = [.width, .height]
        blur.addSubview(hosting)
        panel.contentView = blur
        panel.setFrame(frame, display: false)

        state.onLaunch = { [weak self, weak model] id, name in
            Task { @MainActor in
                if await model?.launch(id, name: name) == true { self?.close() }
            }
        }
        state.onHide = { [weak model] id in Task { @MainActor in await model?.hide(id) } }
        state.onClose = { [weak self] in self?.close() }
        state.onLoaded = { snapshot, state in
            HelmLog.shared.info("launchpad", "window: \(snapshot.apps.count) apps, \(state.geometry.columns)x\(state.geometry.rows) grid, \(state.pageCount) pages")
        }
        panel.onResignKey = { [weak self] in self?.close() }
    }

    func present() {
        guard !closed, !opened else { return }
        opened = true
        enders = LaunchpadWindowEnders { [weak self] in self?.close() }
        watchTask = Task { [weak model] in await model?.whileShown() }
        panel.makeKeyAndOrderFront(nil)
        report("module.launchpad.show", since: footprintBefore)
    }

    func bringForward() {
        guard !closed else { return }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard !closed else { return }
        closed = true
        let before = MemoryFootprint.current()
        watchTask?.cancel()
        watchTask = nil
        enders = nil
        state.onLaunch = nil
        state.onHide = nil
        state.onClose = nil
        state.onLoaded = nil
        panel.onResignKey = nil
        panel.state = nil
        panel.contentView = nil
        panel.orderOut(nil)
        report("module.launchpad.close", since: before)
        let done = onClose
        onClose = nil
        done?()
    }

    private func report(_ label: String, since before: Int?) {
        guard let before, let after = MemoryFootprint.current() else { return }
        HelmLog.shared.memory(label, grewBy: after - before)
    }
}
