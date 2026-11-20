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
/// Control or Option falls through. A trackpad swipe with fingers on it drags the page and settles it (`LaunchpadSwipe`), the wheel and a device with no phases turn pages through `LaunchpadScrollPager`; with a folder's
/// card open they fall through, to the card's own scrolling. The rest, the typing included, is the text field's.
///
/// What was measured of menus and tooltips in a panel like this is `OverlayPanel`'s doc comment; this panel's own live
/// readings (typing, the context menu, closing on resign) are the owner's, in Helm Dev.
final class LaunchpadPanel: NSPanel {
    var state: LaunchpadScreenState?
    var onResignKey: (() -> Void)?
    /// Set when the window has begun to fade out: the picture stays up for the fade and answers nothing.
    var isClosing = false
    private var pager = LaunchpadScrollPager()
    private var swipe = LaunchpadSwipe()

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func sendEvent(_ event: NSEvent) {
        if isClosing {
            switch event.type {
            case .keyDown, .keyUp, .flagsChanged: return
            default: break
            }
        }
        if !handle(event) { super.sendEvent(event) }
    }

    /// An arrow key's step: the choice and, past the page's edge, the page, on the interface curve.
    private func moveChoice(dx: Int, dy: Int, _ state: LaunchpadScreenState) {
        withAnimation(HelmMotion.interface) { state.move(dx: dx, dy: dy) }
    }

    /// Where the pointer is in the window's coordinates, from the top left (the panel's own are from the bottom left).
    private func point(of event: NSEvent, _ state: LaunchpadScreenState) -> CGPoint {
        CGPoint(x: event.locationInWindow.x, y: state.geometry.size.height - event.locationInWindow.y)
    }

    /// True when the event was this window's and goes no further.
    private func handle(_ event: NSEvent) -> Bool {
        guard let state else { return false }
        switch event.type {
        case .keyDown:
            // A carried tile: Esc is the state's (it ends the lift, not the window), every other key waits.
            if state.pointerBusy && event.keyCode != 53 { return true }
            if let editor = firstResponder as? NSTextView, editor.hasMarkedText() { return false }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
            // The folder's name field has the keyboard: Return and Esc are its, and every other key (the caret, the arrows) goes on to it.
            if state.renaming { return state.handleNameKey(event.keyCode) }
            if (event.keyCode == 123 || event.keyCode == 124), !state.search.isEmpty { return false }
            switch event.keyCode {
            case 53: state.escape()
            case 36, 76: state.activate()
            case 123: moveChoice(dx: -1, dy: 0, state)
            case 124: moveChoice(dx: 1, dy: 0, state)
            case 125: moveChoice(dx: 0, dy: 1, state)
            case 126: moveChoice(dx: 0, dy: -1, state)
            case 48: break
            default: return false
            }
            return true
        case .leftMouseDown:
            return state.pointerDown(point(of: event, state), time: event.timestamp)
        case .leftMouseDragged:
            guard state.pointerBusy else { return false }
            state.pointerMoved(point(of: event, state), time: event.timestamp)
            return true
        case .leftMouseUp:
            guard state.pointerBusy else { return false }
            state.pointerUp(point(of: event, state), time: event.timestamp)
            return true
        case .rightMouseDown:
            return state.pointerBusy
        case .scrollWheel:
            if state.pointerBusy { return true }
            guard state.openFolder == nil else { return false }
            if event.hasPreciseScrollingDeltas, !event.phase.isEmpty || !event.momentumPhase.isEmpty {
                swipe.width = state.geometry.pageWidth
                swipe.reduceMotion = HelmMotion.reduceMotion
                switch swipe.feed(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, phase: event.phase,
                                  momentum: event.momentumPhase, time: event.timestamp) {
                case .none: break
                case .drag(let raw): state.drag(raw: raw)
                case .release(let step, let velocity): state.settle(step: step, velocity: velocity)
                }
            } else if let step = pager.feed(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                                            time: event.timestamp) {
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
            // The Dock helper's click is the toggle that closes the window itself; it is no other app coming forward.
            if app?.processIdentifier != mine, app?.bundleIdentifier != AppBuild.pairedLaunchpadHelperIdentifier {
                MainActor.assumeIsolated { end() }
            }
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
/// **Level.** One below the Dock's (20, so 19): above every ordinary window, under the Dock, which stays drawn and
/// clickable over the panel, as macOS's own Launchpad leaves it; a click on the pinned Dock helper then reaches
/// it. The frame is still the whole screen. Every Space and over full-screen apps, as `OverlayPanel`.
///
/// Built on the screen the pointer is on, its geometry worked out from the grid then in force (`regrid` makes it again). The model's `whileShown()` runs for as long as
/// the window is open, and its snapshot goes when the window does. It closes on Esc, a click on the empty background, an
/// app that opened, the panel losing key, another app coming forward, the Space or the screens changing, the model
/// stopping and the shortcut's second press.
@MainActor final class LaunchpadWindow: LaunchpadWindowHandle {
    /// One below the Dock's level.
    static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)

    var onClose: (@MainActor () -> Void)?
    private let panel: LaunchpadPanel
    private let state: LaunchpadScreenState
    private weak var model: LaunchpadViewModel?
    private var watchTask: Task<Void, Never>?
    private var enders: LaunchpadWindowEnders?
    private var closed = false
    private var opened = false
    private var finished = false
    /// The window whose picture is still fading out; a new window cuts it before it opens.
    private static var lingering: LaunchpadWindow?
    private let footprintBefore = MemoryFootprint.current()

    init(model: LaunchpadViewModel) {
        Self.lingering?.finish()
        self.model = model
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = screen?.frame ?? CGRect(origin: .zero, size: LaunchpadGeometry.fallback)
        let geometry = LaunchpadGeometry.make(for: frame.size, topSafe: screen?.safeAreaInsets.top ?? 0, settings: model.grid)
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
                self?.state.launched(id)
                if await model?.launch(id, name: name) == true { self?.close() } else { self?.state.launchFailed() }
            }
        }
        state.onHide = { [weak model] id in Task { @MainActor in await model?.hide(id) } }
        state.onPlace = { [weak model] edit in await model?.place(edit) }
        state.onRename = { [weak model] id, name in Task { @MainActor in await model?.rename(id, to: name) } }
        state.onClose = { [weak self] in self?.close() }
        let asked = model.grid
        let grid = asked.automatic ? "automatic" : "\(asked.rows) rows asked, \(geometry.rows) fit"
        state.onLoaded = { snapshot, state in
            HelmLog.shared.info("launchpad", "window: \(snapshot.apps.count) apps, \(state.geometry.columns)x\(state.geometry.rows) grid (\(grid)), icon \(Int(state.geometry.icon)), \(state.pageCount) pages")
        }
        panel.onResignKey = { [weak self] in self?.close() }
    }

    func present() {
        guard !closed, !opened else { return }
        opened = true
        enders = LaunchpadWindowEnders { [weak self] in self?.close() }
        watchTask = Task { [weak model] in await model?.whileShown() }
        let fades = HelmMotion.moves(reduceMotion: HelmMotion.reduceMotion)
        if fades { panel.alphaValue = 0 }
        panel.makeKeyAndOrderFront(nil)
        if fades { fade(to: 1, duration: HelmMotion.windowZoomDuration) {} }
        Task { await LaunchpadGlow.prepare() }
        report("module.launchpad.show", since: footprintBefore)
    }

    /// The panel's alpha, moved by the window server along the interface curve: the blur, the scrim and the grid fade as one.
    private func fade(to alpha: CGFloat, duration: TimeInterval, then done: @escaping @MainActor () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = HelmMotion.interfaceCurve
            panel.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { done() }
        }
    }

    func bringForward() {
        guard !closed else { return }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Ends the window for the model at once, and takes the picture down: faded out over `interfaceDuration` and answering
    /// nothing, or cut when motion is reduced.
    func close() {
        guard !closed else { return }
        closed = true
        watchTask?.cancel()
        watchTask = nil
        enders = nil
        state.shutdown()
        state.onLaunch = nil
        state.onPlace = nil
        state.onRename = nil
        state.onHide = nil
        state.onClose = nil
        state.onLoaded = nil
        panel.onResignKey = nil
        panel.state = nil
        let done = onClose
        onClose = nil
        done?()
        guard HelmMotion.moves(reduceMotion: HelmMotion.reduceMotion), opened else { finish(); return }
        panel.ignoresMouseEvents = true
        panel.isClosing = true
        Self.lingering = self
        state.setShown(false)
        fade(to: 0, duration: HelmMotion.interfaceDuration) { [weak self] in self?.finish() }
    }

    /// Takes the picture down: the panel's content and the panel itself. Once, from the fade's end or from a window that
    /// opens over it.
    private func finish() {
        guard !finished else { return }
        finished = true
        let before = MemoryFootprint.current()
        panel.contentView = nil
        panel.orderOut(nil)
        if Self.lingering === self { Self.lingering = nil }
        report("module.launchpad.close", since: before)
    }

    private func report(_ label: String, since before: Int?) {
        guard let before, let after = MemoryFootprint.current() else { return }
        HelmLog.shared.memory(label, grewBy: after - before)
    }
}
