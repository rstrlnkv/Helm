import AppKit
import SwiftUI
import Module_Island_Engine

/// Observable bridge between the controller and the SwiftUI content.
@MainActor public final class IslandModel: ObservableObject {
    @Published public internal(set) var state: IslandStateMachine.State = .hidden
    @Published public internal(set) var notchWidth: CGFloat = 200
    @Published public internal(set) var receivingDrag = false
    public internal(set) var dismiss: () -> Void = {}
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

    public init?(content: AnyView = AnyView(EmptyView())) {
        guard let screen = NSScreen.main,
              let metrics = NotchMetrics.compute(
                  screen: screen.frame,
                  topInset: screen.safeAreaInsets.top,
                  auxTopLeftWidth: screen.auxiliaryTopLeftArea?.width ?? 0)
        else { return nil }

        model.notchWidth = metrics.notchRect.width

        // Sensor: notch rect only, always present.
        let sensor = NSPanel(contentRect: metrics.notchRect,
                             styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered, defer: false)
        Self.configure(sensor)
        self.sensor = sensor

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

        island.contentView = NSHostingView(rootView: IslandView(model: model, content: content))
        island.setFrame(metrics.windowRect, display: true)

        model.dismiss = { [weak self] in self?.apply(.dismiss) }
        sensorView.onHover = { [weak self] inside in
            self?.apply(inside ? .hoverEntered : .hoverExited)
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

    /// Task 7 replaces this with the shelf store; the shell just pins open.
    var onDrop: ([URL]) -> Void = { _ in }

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
        if case .dragEntered = input { model.receivingDrag = true }
        if case .dragExited = input { model.receivingDrag = false }
        if case .dismiss = input { model.receivingDrag = false }
        model.state = machine.state
        syncWindows()
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

    private static func configure(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
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
