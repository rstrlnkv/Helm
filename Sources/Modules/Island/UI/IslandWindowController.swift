import AppKit
import SwiftUI
import Module_Island_Engine

/// Observable bridge between the controller and the SwiftUI content.
@MainActor public final class IslandModel: ObservableObject {
    public enum Mode: Equatable { case controls, shelf }

    @Published public internal(set) var state: IslandStateMachine.State = .hidden
    @Published public internal(set) var mode: Mode = .controls
    @Published public internal(set) var notchWidth: CGFloat = 200
    @Published public internal(set) var notchHeight: CGFloat = 32
    @Published public var receivingDrag = false
    @Published public internal(set) var eventText: String?
    @Published public internal(set) var eventSymbol: String?
    @Published public internal(set) var eventIsVolume = false
    @Published public internal(set) var volume: Float = 0.5
    @Published public internal(set) var volumeAvailable = false
    @Published public internal(set) var nowPlayingTitle: String?
    @Published public internal(set) var nowPlayingPlaying = false
    public internal(set) var dismiss: () -> Void = {}
    /// Card hover feeds the same machine as the notch sensor, so moving the
    /// cursor from the notch down into the card keeps the island open.
    public internal(set) var hover: (Bool) -> Void = { _ in }
    public var setVolume: (Float) -> Void = { _ in }
    public var playPause: () -> Void = {}
}

/// The island shell. Two windows, per the spec's click-safety rule:
///  - a permanent, invisible SENSOR strictly over the notch rect (hover +
///    drag-in detection; the notch strip has no clickable content, so it can
///    safely own that area);
///  - the ISLAND window with one static frame (NotchMetrics.windowRect) that is
///    ordered in only while the state machine is not `.hidden`, so an idle
///    island never swallows clicks. All animation is SwiftUI inside the static
///    frame — the frame itself never moves (ARCHITECTURE.md panel rules).
@MainActor public final class IslandWindowController {
    private let sensor: NSPanel
    private let island: IslandKeyPanel
    private var machine = IslandStateMachine()
    private var graceTimer: Timer?
    public let model = IslandModel()

    /// Hover over the notch opens the island (user setting).
    public var hoverEnabled = true
    private var eventTimers: [String: Timer] = [:]
    /// Mirrors of the machine's drag/pin flags to derive the content mode.
    private var dragFlag = false
    private var pinFlag = false

    public init?(makeContent: ((IslandModel) -> AnyView)? = nil,
                 makeChips: ((IslandModel) -> AnyView)? = nil) {
        guard let screen = NSScreen.main,
              let metrics = NotchMetrics.compute(
                  screen: screen.frame,
                  topInset: screen.safeAreaInsets.top,
                  auxTopLeftWidth: screen.auxiliaryTopLeftArea?.width ?? 0)
        else { return nil }

        model.notchWidth = metrics.notchRect.width
        model.notchHeight = metrics.notchRect.height

        // Sensor: notch rect only, always present.
        let sensor = NSPanel(contentRect: metrics.notchRect,
                             styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered, defer: false)
        Self.configure(sensor, raised: true)   // stays above the island: no
        self.sensor = sensor                   // occlusion → no hover flicker

        // Island: static frame, hidden until needed.
        let island = IslandKeyPanel(contentRect: metrics.windowRect,
                                    styleMask: [.nonactivatingPanel, .borderless],
                                    backing: .buffered, defer: false)
        Self.configure(island)
        self.island = island

        let sensorView = IslandSensorView(frame: NSRect(origin: .zero, size: metrics.notchRect.size))
        sensor.contentView = sensorView
        sensor.setFrame(metrics.notchRect, display: true)
        sensor.orderFrontRegardless()

        let content = makeContent?(model) ?? AnyView(EmptyView())
        let chips = makeChips?(model) ?? AnyView(EmptyView())
        island.contentView = NSHostingView(rootView: IslandView(model: model, content: content, chips: chips))
        island.setFrame(metrics.windowRect, display: true)

        model.dismiss = { [weak self] in self?.apply(.dismiss) }
        model.hover = { [weak self] inside in
            self?.apply(inside ? .hoverEntered : .hoverExited)
        }
        sensorView.onHover = { [weak self] inside in
            guard let self else { return }
            // Ignore hover-enter when disabled; always deliver exit so an
            // already-open island still collapses.
            if inside && !self.hoverEnabled { return }
            self.apply(inside ? .hoverEntered : .hoverExited)
        }
        sensorView.onDrag = { [weak self] phase in
            switch phase {
            case .entered: self?.apply(.dragEntered)
            case .exited: self?.apply(.dragExited)
            case .dropped(let urls):
                self?.handleDrop(urls)
            }
        }
    }

    public var onDrop: ([URL]) -> Void = { _ in }

    /// Transient event from a source: peeks (or joins the expanded card) and
    /// expires after `ttl` seconds.
    public func showEvent(id: String, text: String?, symbol: String?, ttl: TimeInterval) {
        if id != "volume" { model.eventIsVolume = false }
        model.eventText = text
        model.eventSymbol = symbol
        apply(.event(id: id))
        eventTimers[id]?.invalidate()
        eventTimers[id] = Timer.scheduledTimer(withTimeInterval: ttl, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.eventTimers[id] = nil
                self.apply(.eventExpired(id: id))
                if self.model.state == .hidden {
                    self.model.eventText = nil; self.model.eventSymbol = nil
                    self.model.eventIsVolume = false
                }
            }
        }
    }

    public func teardown() {
        graceTimer?.invalidate()
        eventTimers.values.forEach { $0.invalidate() }
        eventTimers.removeAll()
        island.orderOut(nil)
        sensor.orderOut(nil)
    }

    private func handleDrop(_ urls: [URL]) {
        onDrop(urls)
        apply(.dropped)
        apply(.dragExited)
    }

    public func apply(_ input: IslandStateMachine.Input) {
        switch input {
        case .hoverExited, .dragExited: armGrace()
        case .hoverEntered, .dragEntered: graceTimer?.invalidate(); graceTimer = nil
        default: break
        }
        machine.apply(input)
        switch input {
        case .dragEntered: model.receivingDrag = true; dragFlag = true
        case .dragExited: model.receivingDrag = false; dragFlag = false
        case .dropped: pinFlag = true
        case .dismiss: model.receivingDrag = false; dragFlag = false; pinFlag = false
        default: break
        }
        // Shelf only while a file drag is in flight or right after a drop;
        // plain hover opens the horizontal controls pill.
        model.mode = (dragFlag || pinFlag) ? .shelf : .controls
        model.state = machine.state
        syncWindows()
    }

    /// Volume feedback (slider-style peek); also keeps the pill's slider live.
    public func showVolume(_ level: Float, ttl: TimeInterval = 1.6) {
        model.volume = level
        model.eventIsVolume = true
        showEvent(id: "volume", text: nil, symbol: nil, ttl: ttl)
    }

    private func armGrace() {
        graceTimer?.invalidate()
        graceTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.apply(.graceElapsed) }
        }
    }

    private func syncWindows() {
        switch machine.state {
        case .hidden:
            island.orderOut(nil)
        case .peek:
            island.orderFrontRegardless()
        case .expanded:
            island.orderFrontRegardless()
            island.makeKey()   // animations only tick while key (ARCHITECTURE.md)
        }
    }

    private static func configure(_ panel: NSPanel, raised: Bool = false) {
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + (raised ? 2 : 1))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }
}

/// Borderless panels can't normally become key; the island must, so its
/// SwiftUI controls and animations work while the app stays inactive.
final class IslandKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Sensor

enum IslandDragPhase {
    case entered, exited
    case dropped([URL])
}

/// Invisible view over the notch: mouse tracking + drag destination.
final class IslandSensorView: NSView {
    var onHover: (Bool) -> Void = { _ in }
    var onDrag: (IslandDragPhase) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDrag(.entered)
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDrag(.exited) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        onDrag(.dropped(urls))
        return !urls.isEmpty
    }
}
