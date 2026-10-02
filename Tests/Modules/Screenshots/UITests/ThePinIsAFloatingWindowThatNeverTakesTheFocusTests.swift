import AppKit
import CoreGraphics
import HelmContract
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A pin is a borderless panel above ordinary windows and below Helm's own bars, built here and never ordered in.**
/// The board's `present:` seam stands where `orderFrontRegardless()` stands in the app, so nothing here reaches
/// anybody's screen, and events are made by hand and handed to the view or the panel directly.
///
/// Total failure of the subject prints: a pin that steals focus from the app the person was in (no
/// `.nonactivatingPanel`), one that sits over the capture overlay (level at or above `.statusBar`), one that
/// disappears on another Space or beside a full-screen app, one that cannot take Esc (`canBecomeKey` false),
/// an Esc that closes every pin or none or leaves the closed panel alive, a click that nudges the image by a
/// pixel, a scroll that moves the wrong pin, a screen change that leaves a pin where the display was, and an
/// observer that outlives the last pin.
///
/// Assumed spelling (the plan's): `PinBoard(present:screens:)`, `open(_:frame:)` returning the `PinPanel`
/// (`@discardableResult`), `pins: [PinPanel]`, `hasRoom`, `close(_:)`, `closeAll()`; `PinPanel.pinView: PinView`
/// (its content view); pointer positions are read from the event's `locationInWindow` through the view's own
/// window, never `NSEvent.mouseLocation` or `event.window`, so a synthetic event drives them; a positive
/// scroll delta enlarges and raises the opacity; the display a pin is scaled against is the one of the board's
/// `screens` holding most of it.
@MainActor
final class ThePinIsAFloatingWindowThatNeverTakesTheFocusTests: XCTestCase {

    private var desk: [(DisplayID, CGRect)] = [(DisplayID(1), CGRect(x: 0, y: 0, width: 4000, height: 3000))]
    private var shown = 0
    private var screenReads = 0

    private func board() -> PinBoard {
        PinBoard(present: { [weak self] _ in self?.shown += 1 },
                 screens: { [weak self] in
                     self?.screenReads += 1
                     return (self?.desk ?? []).map { ($0.0, $0.1) }
                 })
    }

    private func picture(_ width: Int = 200, _ height: Int = 100) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    @discardableResult
    private func pin(_ board: PinBoard, at origin: CGPoint = CGPoint(x: 100, y: 100)) throws -> PinPanel {
        board.open(try picture(), frame: CGRect(origin: origin, size: CGSize(width: 200, height: 100)))
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: code == 53 ? "\u{1b}" : "a", charactersIgnoringModifiers: code == 53 ? "\u{1b}" : "a",
                         isARepeat: false, keyCode: code)!
    }

    /// A pointer at a fixed screen point: the event's window-relative location is worked from the panel's
    /// frame *now*, as a real pointer's is, so a pin that has just moved under it sees the pointer where it was.
    private func mouse(_ type: NSEvent.EventType, at screen: CGPoint, in panel: PinPanel) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: screen), modifierFlags: [], timestamp: 0,
                           windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func scroll(_ delta: Int32, option: Bool = false) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
        if option { cg.flags.insert(.maskAlternate) }
        let event = try XCTUnwrap(NSEvent(cgEvent: cg))
        // The subject happened: a scroll that reads as zero would make every "changed nothing" below true.
        XCTAssertEqual(event.type, .scrollWheel)
        XCTAssertEqual(event.scrollingDeltaY > 0, delta > 0, "the synthetic scroll has the wrong sign")
        XCTAssertEqual(event.modifierFlags.contains(.option), option)
        return event
    }

    // MARK: What the window is

    func testThePanelIsBorderlessNonActivatingAndAboveOrdinaryWindows() throws {
        let board = board()
        let panel = try pin(board)
        XCTAssertTrue(panel.styleMask.contains(.borderless), "the pin has a frame of its own")
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel), "opening a pin would activate Helm and take the focus from the app in front")
        XCTAssertLessThan(panel.level.rawValue, NSWindow.Level.statusBar.rawValue, "a pin would sit over the capture bar and the overlay")
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.normal.rawValue, "a pin that is not above ordinary windows is not pinned")
        for behaviour: NSWindow.CollectionBehavior in [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle] {
            XCTAssertTrue(panel.collectionBehavior.contains(behaviour), "missing \(behaviour)")
        }
        XCTAssertFalse(panel.canBecomeKey, "a pin took key with no click on it (see ThePinTakesKeyOnlyFromAClickOnItselfTests)")
        XCTAssertFalse(panel.canBecomeMain, "a pin would take the main-window slot")
        XCTAssertFalse(panel.hidesOnDeactivate, "every pin would vanish when the person switched to another app")
        XCTAssertFalse(panel.isReleasedWhenClosed, "a closed pin would be released twice")
        XCTAssertEqual(panel.frame, CGRect(x: 100, y: 100, width: 200, height: 100), "the pin is not where it was opened")
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.0001)
        XCTAssertTrue(panel.pinView.acceptsFirstMouse(for: nil), "the first click on a pin would be spent on making it key")
        XCTAssertEqual(shown, 1, "the board did not hand the panel to its presenter exactly once")
        XCTAssertFalse(panel.isVisible, "the test put a window on the screen")
    }

    /// The view shows the image it was given, as its layer's contents (crisp on Retina: no redraw at a size).
    func testTheViewShowsTheImageItWasGiven() throws {
        let board = board()
        let image = try picture(400, 200)
        let panel = board.open(image, frame: CGRect(x: 100, y: 100, width: 200, height: 100))
        let contents = try XCTUnwrap(panel.pinView.layer?.contents, "the pin's layer holds nothing")
        XCTAssertTrue(CFEqual(contents as CFTypeRef, image), "the layer holds something other than the image the pin was opened with")
    }

    /// Opening never makes the panel key and never activates the app: read from the source, because no
    /// headless run can tell a panel ordered front from one made key. A scan that found no file would pass,
    /// so the file is asserted first.
    func testOpeningACallNeitherMakesKeyNorActivates() throws {
        let source = try RepoSource.text(of: "Sources/Modules/Screenshots/UI/ScreenPin.swift")
        XCTAssertTrue(source.contains("orderFrontRegardless"), "the file does not order a pin in the way the plan says")
        for forbidden in ["makeKeyAndOrderFront", "makeKey()", "NSApp.activate", "NSApplication.shared.activate", "orderFront(nil)"] {
            XCTAssertFalse(SwiftSource.code(source).contains(forbidden), "ScreenPin.swift calls \(forbidden), which takes the focus")
        }
    }

    // MARK: Esc

    func testEscClosesExactlyTheOnePinAndItsPanelIsFreed() throws {
        let board = board()
        let first = try pin(board), second = try pin(board, at: CGPoint(x: 400, y: 400))
        XCTAssertEqual(board.pins.count, 2)
        let secondFrame = second.frame
        first.keyDown(with: key(53))
        XCTAssertEqual(board.pins.count, 1, "Esc closed \(2 - board.pins.count) pins, not one")
        XCTAssertTrue(board.pins.first === second, "Esc closed the wrong pin")
        XCTAssertEqual(second.frame, secondFrame)
    }

    /// The same Esc through the responder chain's `cancelOperation`, which is how a text-less panel hears it.
    func testCancelOperationClosesExactlyOnePin() throws {
        let board = board()
        let first = try pin(board), second = try pin(board, at: CGPoint(x: 400, y: 400))
        second.cancelOperation(nil)
        XCTAssertEqual(board.pins.count, 1)
        XCTAssertTrue(board.pins.first === first, "cancelOperation closed the wrong pin")
    }

    /// Any other key is left alone: a pin that closed on every key would vanish under a person typing elsewhere.
    func testAnotherKeyClosesNothing() throws {
        let board = board()
        let panel = try pin(board)
        panel.keyDown(with: key(0))
        XCTAssertEqual(board.pins.count, 1)
    }

    /// The freed-panel proof, strict: the only strong reference the test holds is dropped inside a scope.
    func testAClosedPinsPanelDeallocates() async throws {
        let board = board()
        weak var weakPanel: PinPanel?
        try {
            let panel = try pin(board)
            weakPanel = panel
            XCTAssertNotNil(weakPanel, "the control: the panel exists while it is open")
            panel.cancelOperation(nil)
        }()
        await waitUntil("the closed pin's panel was freed") { weakPanel == nil }
        XCTAssertEqual(board.pins.count, 0)
    }

    // MARK: Pointer

    func testADragMovesThePinByTheScreenDifference() throws {
        let board = board()
        let panel = try pin(board)
        let start = CGPoint(x: 150, y: 150)
        panel.pinView.mouseDown(with: mouse(.leftMouseDown, at: start, in: panel))
        var pointer = start
        for step in [CGPoint(x: 10, y: 5), CGPoint(x: 30, y: 20)] {
            pointer = CGPoint(x: start.x + step.x, y: start.y + step.y)
            panel.pinView.mouseDragged(with: mouse(.leftMouseDragged, at: pointer, in: panel))
        }
        panel.pinView.mouseUp(with: mouse(.leftMouseUp, at: pointer, in: panel))
        XCTAssertEqual(panel.frame.origin.x, 130, accuracy: 0.001, "the pin did not follow the pointer across")
        XCTAssertEqual(panel.frame.origin.y, 120, accuracy: 0.001, "the pin did not follow the pointer up")
        XCTAssertEqual(panel.frame.size, CGSize(width: 200, height: 100), "a drag resized the pin")
    }

    /// A click, with or without a drag event of zero length, moves nothing: a pixel of drift on every
    /// click would make a pin impossible to click on.
    func testAClickWithoutMovementMovesNothing() throws {
        let board = board()
        let panel = try pin(board)
        let before = panel.frame
        let at = CGPoint(x: 150, y: 150)
        panel.pinView.mouseDown(with: mouse(.leftMouseDown, at: at, in: panel))
        panel.pinView.mouseUp(with: mouse(.leftMouseUp, at: at, in: panel))
        XCTAssertEqual(panel.frame, before, "a click moved the pin")
        panel.pinView.mouseDown(with: mouse(.leftMouseDown, at: at, in: panel))
        panel.pinView.mouseDragged(with: mouse(.leftMouseDragged, at: at, in: panel))
        panel.pinView.mouseUp(with: mouse(.leftMouseUp, at: at, in: panel))
        XCTAssertEqual(panel.frame, before, "a drag event of zero length moved the pin")
    }

    func testScrollScalesAndOptionScrollChangesTheOpacity() throws {
        let board = board()
        let panel = try pin(board)
        let before = panel.frame
        panel.pinView.scrollWheel(with: try scroll(40))
        XCTAssertGreaterThan(panel.frame.width, before.width, "a scroll up did not enlarge the pin")
        XCTAssertEqual(panel.frame.width / panel.frame.height, 2, accuracy: 0.001, "the scale changed the proportions")
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.0001, "a plain scroll changed the opacity")
        panel.pinView.scrollWheel(with: try scroll(-4000))
        XCTAssertLessThan(panel.frame.width, before.width, "a long scroll down did not shrink the pin")
        XCTAssertGreaterThanOrEqual(min(panel.frame.width, panel.frame.height), PinGeometry.minimumSide - 0.01,
                                    "the pin went under its floor")

        let kept = panel.frame
        panel.pinView.scrollWheel(with: try scroll(-4000, option: true))
        XCTAssertEqual(panel.frame, kept, "an Option scroll resized the pin")
        XCTAssertLessThan(panel.alphaValue, 1, "an Option scroll down did not make the pin more transparent")
        XCTAssertGreaterThanOrEqual(panel.alphaValue, PinGeometry.minimumOpacity - 0.0001, "the pin went under its opacity floor: it can no longer be seen")
        panel.pinView.scrollWheel(with: try scroll(4000, option: true))
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.0001, "an Option scroll up did not restore the opacity")
    }

    // MARK: Many

    func testTwoPinsAreIndependent() throws {
        let board = board()
        let one = try pin(board), two = try pin(board, at: CGPoint(x: 600, y: 600))
        let twoBefore = two.frame
        one.pinView.scrollWheel(with: try scroll(40))
        one.pinView.scrollWheel(with: try scroll(-4000, option: true))
        let at = CGPoint(x: one.frame.midX, y: one.frame.midY)
        one.pinView.mouseDown(with: mouse(.leftMouseDown, at: at, in: one))
        one.pinView.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: at.x + 50, y: at.y), in: one))
        one.pinView.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: at.x + 50, y: at.y), in: one))
        XCTAssertEqual(two.frame, twoBefore, "acting on one pin moved or scaled the other")
        XCTAssertEqual(two.alphaValue, 1, accuracy: 0.0001, "acting on one pin changed the other's opacity")
        one.cancelOperation(nil)
        XCTAssertTrue(board.pins.first === two, "Esc on one pin closed the other")
        XCTAssertEqual(two.frame, twoBefore)
    }

    func testTheBoardHasRoomForEightAndNoMore() throws {
        let board = board()
        XCTAssertTrue(board.hasRoom, "an empty board has no room")
        for index in 0..<PinGeometry.limit {
            XCTAssertTrue(board.hasRoom, "no room with \(index) of \(PinGeometry.limit) open")
            try pin(board, at: CGPoint(x: 10 * CGFloat(index), y: 10 * CGFloat(index)))
        }
        XCTAssertEqual(board.pins.count, PinGeometry.limit)
        XCTAssertFalse(board.hasRoom, "the board says it has room at the limit")
        try XCTUnwrap(board.pins.last).cancelOperation(nil)
        XCTAssertTrue(board.hasRoom, "closing a pin did not make room")
    }

    // MARK: A display leaves

    /// A pin on the second display, which is unplugged: the notification arrives, `screens` now lists one
    /// display, and the pin is moved home; one wholly on a display that stays is not touched.
    func testAPinOnADisplayThatLeftIsMovedHome() async throws {
        desk = [(DisplayID(1), CGRect(x: 0, y: 0, width: 1000, height: 800)), (DisplayID(2), CGRect(x: 1000, y: 0, width: 1000, height: 800))]
        let board = board()
        let stranded = try pin(board, at: CGPoint(x: 1500, y: 100))
        let safe = try pin(board, at: CGPoint(x: 100, y: 100))
        let safeFrame = safe.frame
        desk = [(DisplayID(1), CGRect(x: 0, y: 0, width: 1000, height: 800))]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await waitUntil("the stranded pin came home") { CGRect(x: 0, y: 0, width: 1000, height: 800).contains(stranded.frame) }
        XCTAssertEqual(stranded.frame.size, CGSize(width: 200, height: 100), "a pin that fits was resized")
        XCTAssertEqual(safe.frame, safeFrame, "a pin on a display that stayed was moved")
    }

    /// One observer per board: it answers while a pin is open, and answers no more after the last pin is
    /// gone or `closeAll` — read by whether the notification still reaches `screens`.
    func testTheObserverGoesWithTheLastPinAndWithCloseAll() async throws {
        let board = board()
        try pin(board)
        let before = screenReads
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await waitUntil("the control: an open pin answers a screen change") { screenReads > before }

        try XCTUnwrap(board.pins.first).cancelOperation(nil)
        await grace(0.2)
        let afterLast = screenReads
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await grace(0.3)
        XCTAssertEqual(screenReads, afterLast, "the observer outlived the last pin")

        try pin(board); try pin(board, at: CGPoint(x: 500, y: 500))
        let reopened = screenReads
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await waitUntil("the control: a board that reopened answers again") { screenReads > reopened }
        board.closeAll()
        XCTAssertEqual(board.pins.count, 0)
        await grace(0.2)
        let afterAll = screenReads
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await grace(0.3)
        XCTAssertEqual(screenReads, afterAll, "closeAll left the observer installed")
    }
}
