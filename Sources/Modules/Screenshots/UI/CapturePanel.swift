import AppKit
import Combine
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

/// What the bar shows and writes. The options are the module's own settings, every change written to the store and
/// read back from it. Where it is saved, the thumbnail and the cursor are the keys the settings page writes too, so the
/// bar and the page cannot hold two answers; the mode, the timer, its length, remembering the selection and the
/// panel's place are the bar's alone, and the page reads none of them.
@MainActor final class CapturePanelModel: ObservableObject {
    @Published private(set) var settings: ScreenshotsSettings
    /// Seconds still to wait, while a countdown is running; nil otherwise.
    @Published var countdown: Int?
    /// The seconds the running countdown began with: the ring's whole turn.
    @Published var countdownLength = 0
    /// Something is chosen for Capture to take: a window under the pointer or an area drawn, on the overlay the
    /// panel opened. Set by the controller from the overlay; the whole screen is always a target and needs none.
    @Published var hasTarget = false
    private let store: NamespacedStore
    /// Capture in the mode shown; set by the controller.
    var capture: (PanelMode) -> Void = { _ in }
    /// A mode was pressed, the shown one too; set by the controller, which opens the overlay it selects on.
    var modeChosen: (PanelMode) -> Void = { _ in }
    /// Close the bar and everything behind it; set by the controller.
    var cancel: () -> Void = {}
    /// The panel stands in its place by default again; set by the panel, which owns the window.
    var placeAgain: () -> Void = {}

    private var storeChanged: AnyCancellable?
    /// A group of writes is under way (`writeTogether`).
    private var writing = false

    init(store: NamespacedStore) {
        self.store = store
        settings = ScreenshotsSettings.read(store)
        // The settings page writes the same keys while the bar is up; the bar
        // takes what the store holds now rather than what `show()` read.
        storeChanged = NotificationCenter.default.publisher(for: .helmStoreChanged)
            .sink { [weak self] _ in self?.reload() }
    }

    var mode: PanelMode { settings.panelMode }
    var counting: Bool { countdown != nil }
    var timerOn: Bool { settings.timer != .none }
    /// Capture is drawn only over something it would take. Return does not ask: on the panel it takes the target there
    /// is, and with no overlay open yet it opens one (`CaptureController.capture(from:)`).
    var showsCapture: Bool { mode == .screen || hasTarget }

    func choose(_ mode: PanelMode) {
        store.set(mode.rawValue, for: ScreenshotsSettings.Key.panelMode)
        reload()
        modeChosen(mode)
    }

    /// A length is also the one the cell switches on with next time. None is not a length: it keeps the one there was,
    /// **written out now**, because a store from before `timerLength` has only `timer`, and the zero this writes would
    /// leave nothing to say what the timer had been.
    func choose(_ timer: CaptureTimer) {
        // Read before the first write: a write announces itself and `reload` takes the half-written store as `settings`.
        let length = timer == .none ? settings.timerLength : timer
        store.set(length.seconds, for: ScreenshotsSettings.Key.timerLength)
        store.set(timer.seconds, for: ScreenshotsSettings.Key.timer)
        reload()
    }

    /// The timer cell's press while the timer is off: on with the last length. With it on the cell opens the lengths
    /// instead, and only «No timer» there (`choose(_:)`) switches it off.
    func toggleTimer() { choose(settings.timerLength) }

    /// «Put the Panel Back»: the stored move is forgotten, and so is the move the person has made since the panel
    /// opened, and the panel stands where it opens.
    func putBack() {
        writeTogether { PanelOffset.erase(from: store) }
        placeAgain()
    }

    /// Where the person left the panel, written when it closes.
    func remember(place offset: PanelOffset) {
        writeTogether { offset.write(to: store) }
    }

    /// Writes of several keys, one announcement each: the model hears none of them until the last, so what it reads
    /// is the store before or after the whole, never half a pair.
    private func writeTogether(_ writes: () -> Void) {
        writing = true
        writes()
        writing = false
        reload()
    }

    /// «Other…» asks for the folder, and the target is written only once there
    /// is one the capture will accept — the page's own judgement, from the same
    /// function.
    func choose(_ target: SaveTarget) {
        if target == .other {
            guard case .chosen(let path) = ScreenshotsSettingsPage.askForFolder() else { reload(); return }
            store.set(path, for: ScreenshotsSettings.Key.otherFolder)
        }
        store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        reload()
    }

    func setThumbnail(_ on: Bool) { store.set(on, for: ScreenshotsSettings.Key.thumbnail); reload() }
    func setRemember(_ on: Bool) { ScreenshotsSettings.setRememberSelection(on, in: store); reload() }
    func setCursor(_ on: Bool) { store.set(on, for: ScreenshotsSettings.Key.showCursor); reload() }

    /// What the settings are now, from the store: the page may have changed one.
    func reload() {
        guard !writing else { return }
        let now = ScreenshotsSettings.read(store)
        if now != settings { settings = now }
    }
}

/// The glass bar, drawn as macOS's own: a close control, Screen, Window and Area, the timer, the gear and Capture.
/// **A non-activating key panel** — it reads Esc and Return without making Helm the active application, so the
/// person's own app keeps its focus and its menu bar — in every Space and over full-screen apps. It stands at the
/// level the toast uses, and **above the overlay while one is open under it** (`selecting`): the person picks a
/// window or an area on the frozen screen and presses Capture on this panel, so it cannot lie below that overlay. The
/// freeze excludes Helm's own windows, so the panel is in no shot.
///
/// It is dragged by its empty glass and stands where it was left, as a move from the place it opens in
/// (`PanelPlace`), written when it closes. **It ends at the gear while there is nothing to capture and is wider by
/// Capture when there is** (`CapturePanelView.trailing`): the window follows its content's width with its **leading
/// edge fixed**, because ✕ and the cells are under the pointer and only Capture is new, on the right; a fixed centre
/// would slide every cell by half of it. The move is stored against the panel at its width without Capture (`restWidth`),
/// so the place it opens in does not depend on the width it was left at.
@MainActor final class CapturePanel {
    let model: CapturePanelModel
    private let store: NamespacedStore
    private var panel: BarPanel?
    /// The overlay the person picks on is open: the panel stands above it.
    var selecting = false { didSet { panel?.level = Self.level(selecting: selecting) } }
    /// The person moved the panel since it was last placed; only then is its place written back.
    private var moved = false
    private var placing = false
    private var moveObserver: NSObjectProtocol?

    /// The width the content has with nothing to capture, measured once on a probe in Area mode: it does not depend on
    /// the timer, a countdown or the language of a run, and the place is judged at it whatever the panel's width now.
    private lazy var restWidth: CGFloat = {
        let probe = CapturePanelModel(store: NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore()))
        probe.choose(.area)
        return NSHostingView(rootView: CapturePanelView(model: probe)).fittingSize.width
    }()

    /// `.statusBar`, the toast's, and one above `.screenSaver`, the overlay's, while selecting. Not private: a test
    /// reads the ladder through it and puts no window on a screen.
    static func level(selecting: Bool) -> NSWindow.Level {
        selecting ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1) : .statusBar
    }

    init(store: NamespacedStore) {
        self.store = store
        model = CapturePanelModel(store: store)
        model.placeAgain = { [weak self] in
            guard let self, let panel = self.panel else { return }
            self.place(panel)
            self.moved = false
        }
    }

    /// Where it was left, on the screen the pointer is on: the move from the place by default, held inside it.
    func show() {
        model.reload()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.level = Self.level(selecting: selecting)
        place(panel)
        moved = false
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() {
        if let panel {
            rememberPlace(of: panel)
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panel = nil
        selecting = false
        model.countdown = nil
        model.hasTarget = false
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
    }

    /// Not private: a test reads the content view without ordering anything in.
    func makePanel() -> BarPanel {
        let panel = BarPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 56))
        panel.onCancel = { [weak self] in self?.model.cancel() }
        panel.onCapture = { [weak self] in
            guard let self, !self.model.counting else { return }
            self.model.capture(self.model.mode)
        }
        let host = FirstMouseHostingView(rootView: CapturePanelView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        host.sizeChanged = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.fit(panel)
        }
        panel.contentView = host
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel,
                                                              queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.placing == false { self?.moved = true } }
        }
        return panel
    }

    /// The place by default moved by what is stored, on the screen the pointer is on and inside its `visibleFrame` as it is now.
    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        if let host = panel.contentView { panel.setContentSize(host.fittingSize) }
        placing = true
        defer { placing = false }
        var origin = PanelPlace.origin(size: restSize(of: panel), offset: model.settings.panelOffset, in: visible)
        // Judged at the width without Capture; the panel as wide as it is now must still be whole on the screen.
        origin.x = min(origin.x, max(visible.minX, visible.maxX - panel.frame.width))
        panel.setFrameOrigin(origin)
    }

    /// The content's width changed (Capture came or went): the window takes it with its leading edge where it was, drawn
    /// inside the screen's `visibleFrame` if that edge would leave the right end of it. Not a move by the person.
    private func fit(_ panel: NSPanel) {
        guard let host = panel.contentView else { return }
        let width = host.fittingSize.width
        guard abs(width - panel.frame.width) > 0.5 else { return }
        placing = true
        defer { placing = false }
        var frame = panel.frame
        frame.size.width = width
        if let visible = panel.screen?.visibleFrame, frame.maxX > visible.maxX { frame.origin.x = max(visible.minX, visible.maxX - width) }
        panel.setFrame(frame, display: true)
    }

    /// The panel's size as the place is judged: its height, and the width it has without Capture.
    private func restSize(of panel: NSPanel) -> CGSize { CGSize(width: restWidth, height: panel.frame.height) }

    /// The panel's move from its place, on the screen it stands on, written once it has been dragged.
    private func rememberPlace(of panel: NSPanel) {
        guard moved, let visible = panel.screen?.visibleFrame else { return }
        model.remember(place: PanelPlace.offset(of: panel.frame.origin, size: restSize(of: panel), in: visible))
        moved = false
    }
}

/// The bar's content, which acts on the click that reaches it. The bar is a
/// non-activating panel and may not be key when the pointer comes (another app
/// holds the keyboard), and a view that refuses first mouse spends that click
/// on becoming key — so ✕ would need two presses while a countdown runs.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    /// The content's natural size changed; the panel that holds it follows (`CapturePanel.fit`).
    var sizeChanged: () -> Void = {}
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        sizeChanged()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class BarPanel: NSPanel {
    var onCancel: () -> Void = {}
    var onCapture: () -> Void = {}

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = CapturePanel.level(selecting: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc.
    override func cancelOperation(_ sender: Any?) { onCancel() }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onCapture()
        // Esc is also `cancelOperation`, but only when the responder chain gets that far.
        case 53: onCancel()
        default: super.keyDown(with: event)
        }
    }
}
