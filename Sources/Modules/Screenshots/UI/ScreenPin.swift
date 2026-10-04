import AppKit
import Module_Screenshots_Engine

/// Whether a person is offered a pin anywhere. The pin is outside v1 (owner's decision, 2026-10-02): every
/// place that would let someone ask for one builds its entry only when this is true (today the Pin item of the ⋯ menu, `EditorMenu`). To bring it back, set it to `true`
/// and delete this paragraph.
enum PinEntry {
    static let isOffered = false
}

/// A pinned picture: a borderless panel that stays above ordinary windows, in every Space and
/// beside full-screen apps, and **never takes the focus it is opened with**.
///
/// The level is the bottom of the ladder `Architecture/Screenshots.md` gives: a pin sits below the menu bar
/// and below the capture bar, the toast and the overlay, so a new capture lies over every pin
/// (and photographs none: Helm's own windows are left out of a freeze). It is key only after a
/// click on itself (`takesKey`), which is how Esc reaches the one pin the person last touched:
/// when a capture's bar or overlay goes, AppKit offers key to the next window that can take it,
/// and a pin that could would take the person's typing and Esc from the app they are in.
final class PinPanel: NSPanel {
    /// The picture's own size in points: what scale 1 means for this pin.
    let native: CGSize
    let pinView: PinView
    /// Closes this pin on the board that holds it.
    var onClose: () -> Void = {}
    /// The displays, in the space of this panel's frame; the board's reading.
    var screens: () -> [(id: DisplayID, frame: CGRect)] = { [] }

    init(image: CGImage, frame: CGRect) {
        native = frame.size
        pinView = PinView(image: image, scale: frame.width > 0 ? CGFloat(image.width) / frame.width : 1)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        // The only thing that tells a pin from a picture of the same colour under it; no border,
        // which a borderless picture would have to draw over its own edge.
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = pinView
    }

    /// The pin's last-known display, kept for the moments when none is listed.
    private var lastDisplay: CGRect?
    /// The scale a scroll has reached before the frame is snapped to whole points: a one-pixel
    /// step of a trackpad is far below half a point, and a scale read back from the snapped
    /// frame would round every such step away. Valid only while the frame is the one it made.
    private var held: (scale: CGFloat, width: CGFloat)?

    override var canBecomeKey: Bool { PinPanel.takesKey(from: NSApp.currentEvent, windowNumber: windowNumber) }

    /// Key only for a left mouse down on this very window: not when AppKit passes key on from a
    /// window that closed, nor for another window's click, nor with no event under way.
    static func takesKey(from event: NSEvent?, windowNumber: Int) -> Bool {
        guard let event else { return false }
        return event.type == .leftMouseDown && event.windowNumber == windowNumber
    }
    override var canBecomeMain: Bool { false }

    /// Esc.
    override func cancelOperation(_ sender: Any?) { onClose() }

    override func keyDown(with event: NSEvent) {
        // Esc is also `cancelOperation`, but only when the responder chain gets that far.
        if event.keyCode == 53 { onClose() } else { super.keyDown(with: event) }
    }

    func move(by delta: CGPoint) {
        setFrameOrigin(CGPoint(x: frame.minX + delta.x, y: frame.minY + delta.y))
    }

    /// The display this pin is on: the one holding most of it, else the first listed, else the last one it knew.
    func currentDisplay() -> CGRect? {
        let displays = screens()
        let home = WindowPick.home(of: frame, among: displays).flatMap { home in displays.first { $0.id == home.id } }
        if let found = (home ?? displays.first)?.frame { lastDisplay = found }
        return lastDisplay
    }

    /// A scroll: scaled against the display `currentDisplay` names.
    func scale(delta: CGFloat, precise: Bool, about: CGPoint) {
        guard let display = currentDisplay() else { return }
        let now = held.flatMap { $0.width == frame.width ? $0.scale : nil }
        guard let next = PinGeometry.scaled(frame: frame, native: native, delta: delta, precise: precise,
                                            about: about, display: display, scale: now) else { return }
        held = (next.width / native.width, 0)
        pinView.resampled()
        // Whole points, with the height from the width: AppKit snaps each side of a frame on its own,
        // and snapping a 2:1 pin's sides separately made it 245:123.
        let width = next.width.rounded()
        let size = CGSize(width: width, height: (width * native.height / native.width).rounded())
        let ratio = width / frame.width
        let origin = CGPoint(x: about.x - (about.x - frame.minX) * ratio, y: about.y - (about.y - frame.minY) * ratio)
        setFrame(CGRect(origin: origin, size: size), display: false)
        held?.width = frame.width
    }

    func fade(delta: CGFloat, precise: Bool) {
        if let next = PinGeometry.opacity(alphaValue, delta: delta, precise: precise) { alphaValue = next }
    }
}

/// The picture, drawn once by the layer at the pixels it has: no redraw at any size, so a Retina
/// selection stays as sharp as it was cut. Positions are read from the event through this view's
/// own window, not from the global pointer.
final class PinView: NSView {
    private var grab: CGPoint?

    /// At 1:1 the layer shows the image's own pixels at the scale the picture was cut at, whatever the
    /// window does to a half-point frame; the first scroll scale is what makes it a stretch (`resampled`).
    init(image: CGImage, scale: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsScale = scale
        layer?.contentsGravity = .topLeft
        layer?.minificationFilter = .trilinear
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not decoded") }

    func resampled() { layer?.contentsGravity = .resize }

    /// A first click on a pin that is not key is a click on the pin, and not the one that makes it key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func screenPoint(_ event: NSEvent) -> CGPoint? {
        window?.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseDown(with event: NSEvent) { grab = screenPoint(event) }

    /// By the difference of two screen points, and nothing for a difference of none: a click
    /// is not a drag of a pixel.
    override func mouseDragged(with event: NSEvent) {
        guard let from = grab, let to = screenPoint(event), let pin = window as? PinPanel else { return }
        let delta = CGPoint(x: to.x - from.x, y: to.y - from.y)
        guard delta != .zero else { return }
        pin.move(by: delta)
        grab = to
    }

    override func mouseUp(with event: NSEvent) { grab = nil }

    /// Scale about the pointer, or with ⌥ the opacity; ⌥ is read from this scroll's own flags.
    override func scrollWheel(with event: NSEvent) {
        guard let pin = window as? PinPanel else { return }
        if event.modifierFlags.contains(.option) {
            pin.fade(delta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
        } else if let at = screenPoint(event) {
            pin.scale(delta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas, about: at)
        }
    }
}

/// The pins that are open, and the one observer of the displays they stand on.
///
/// The observer is installed with the first pin and removed with the last and in `closeAll`, as
/// the overlay's is removed in its `close`: a board with no pins listens to nothing.
@MainActor final class PinBoard {
    private(set) var pins: [PinPanel] = []
    private let present: (PinPanel) -> Void
    private let screens: () -> [(id: DisplayID, frame: CGRect)]
    private var observer: NSObjectProtocol?

    /// `present` and `screens` are seams for a test, which must not put a window on a screen.
    init(present: @escaping (PinPanel) -> Void = { $0.orderFrontRegardless() },
         screens: @escaping () -> [(DisplayID, CGRect)] = { PinBoard.liveScreens() }) {
        self.present = present
        self.screens = { screens().map { (id: $0.0, frame: $0.1) } }
    }

    /// The displays as AppKit frames them, in the space a panel's frame is in.
    static func liveScreens() -> [(DisplayID, CGRect)] {
        NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
                .map { (DisplayID($0), screen.frame) }
        }
    }

    var hasRoom: Bool { pins.count < PinGeometry.limit }

    @discardableResult
    func open(_ image: CGImage, frame: CGRect) -> PinPanel {
        let pin = PinPanel(image: image, frame: frame)
        pin.screens = screens
        _ = pin.currentDisplay()
        pin.onClose = { [weak self, weak pin] in
            if let self, let pin { self.close(pin) }
        }
        pin.setAccessibilityLabel(ScStr.pinnedScreenshot)
        pins.append(pin)
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rehome() }
            }
        }
        present(pin)
        return pin
    }

    func close(_ pin: PinPanel) {
        guard let index = pins.firstIndex(where: { $0 === pin }) else { return }
        pins.remove(at: index)
        pin.onClose = {}
        pin.orderOut(nil)
        pin.contentView = nil
        if pins.isEmpty { stopObserving() }
    }

    func closeAll() {
        for pin in pins { close(pin) }
    }

    private func stopObserving() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// A display came or went: a pin not wholly on one screen is moved to where it is.
    private func rehome() {
        let displays = screens()
        for pin in pins {
            _ = pin.currentDisplay()
            let home = PinGeometry.rehome(frame: pin.frame, native: pin.native, screens: displays)
            if home != pin.frame { pin.setFrame(home, display: false) }
        }
    }
}
