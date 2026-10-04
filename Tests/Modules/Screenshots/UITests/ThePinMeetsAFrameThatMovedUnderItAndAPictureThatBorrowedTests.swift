import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Two things the first pin files left unfed:** the scale a slow scroll keeps between events is valid only while
/// the frame is the one it made (a rehome onto a smaller display changes the frame under it), and the picture a
/// pin holds, when it is made through the real controller, is the selection's own bitmap and not a crop that keeps
/// the whole frozen display alive (the crop keeps its parent's row length; a bitmap of the cut's own does not).
///
/// Total failure of the subject prints: a pin that springs back to the size it had before a display shrank it,
/// a pin whose picture still has the frozen display's row length.
@MainActor
final class ThePinMeetsAFrameThatMovedUnderItAndAPictureThatBorrowedTests: XCTestCase {

    private var desk: [(DisplayID, CGRect)] = []

    private func picture(_ width: Int, _ height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    private func scroll(_ delta: Int32) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    // MARK: The scale kept between slow scrolls

    /// Forty one-pixel scrolls up leave a scale the snapped frame cannot show. A display change then shrinks the
    /// frame; the next scroll up starts from the frame it has, never from the scale kept for the frame it had.
    func testARehomeOntoASmallerDisplayDropsTheScaleKeptForTheOldFrame() async throws {
        desk = [(DisplayID(1), CGRect(x: 0, y: 0, width: 4000, height: 3000))]
        let board = PinBoard(present: { _ in }, screens: { [weak self] in self?.desk ?? [] })
        let pin = board.open(try picture(200, 100), frame: CGRect(x: 100, y: 100, width: 200, height: 100))
        let up = try scroll(1)
        for _ in 0..<60 { pin.pinView.scrollWheel(with: up) }
        XCTAssertGreaterThan(pin.frame.width, 210, "the control: the scrolls grew the pin")
        let grown = pin.frame.width

        desk = [(DisplayID(1), CGRect(x: 0, y: 0, width: 150, height: 150))]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await waitUntil("the pin was fitted to the smaller display") { pin.frame.width <= 150 }
        XCTAssertLessThan(pin.frame.width, grown, "the control: the display shrank the pin")
        let fitted = pin.frame.width

        pin.pinView.scrollWheel(with: up)
        XCTAssertLessThanOrEqual(pin.frame.width, fitted, "a scroll up after the rehome sprang back to \(pin.frame.width) from \(fitted)")
        pin.pinView.scrollWheel(with: try scroll(-1))
        XCTAssertLessThanOrEqual(pin.frame.width, fitted)
        XCTAssertEqual(pin.frame.height / pin.frame.width, 0.5, accuracy: 0.02, "the proportions went")
    }

    /// A display that goes away and returns at another size, with a scroll between: the pin is judged against the
    /// display it is on now.
    func testADisplayThatReturnsSmallerBoundsTheNextScroll() async throws {
        desk = [(DisplayID(1), CGRect(x: 0, y: 0, width: 4000, height: 3000))]
        let board = PinBoard(present: { _ in }, screens: { [weak self] in self?.desk ?? [] })
        let pin = board.open(try picture(200, 100), frame: CGRect(x: 100, y: 100, width: 200, height: 100))
        let up = try scroll(20)
        for _ in 0..<10 { pin.pinView.scrollWheel(with: up) }
        desk = []
        pin.pinView.scrollWheel(with: up)
        let big = pin.frame.width
        XCTAssertGreaterThan(big, 300, "the control: the pin is large")
        desk = [(DisplayID(1), CGRect(x: 0, y: 0, width: 500, height: 500))]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await waitUntil("the pin fitted to the returned display") { pin.frame.width <= 500 }
        let fitted = pin.frame.width
        pin.pinView.scrollWheel(with: up)
        XCTAssertLessThanOrEqual(pin.frame.width, max(fitted, 500), "a pin on a 500-point display scrolled up to \(pin.frame.width)")
    }

    // MARK: The picture a pin holds

    private final class Count: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        var value: Int { lock.withLock { n } }
        func bump() { lock.withLock { n += 1 } }
    }
    private final class Board: ShotPasteboard, @unchecked Sendable {
        let count = Count()
        func copy(png: Data) -> PasteOutcome { count.bump(); return .accepted }
        func copy(pngs: [Data]) -> PasteOutcome { XCTFail("this test's board was never taught a group"); return .refused }
        func copy(text: String) -> PasteOutcome { .accepted }
    }
    private final class Disk: ShotWriting, @unchecked Sendable {
        let count = Count()
        // A disk that counts its writes and keeps no file: nothing is read at any path and no name is claimed.
        func reading(of url: URL) -> ShotReading? { nil }
        func claim(_ written: URL, as name: URL) -> Bool { false }
        func write(_ png: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            count.bump(); return .written(WrittenShot(url: folder.appendingPathComponent(base + "." + pathExtension), reading: NoFile.reading))
        }
    }
    private final class Shutter: ShutterPlaying, @unchecked Sendable { func play() {} }
    private struct Frames: ScreenCapturing {
        let freeze: Freeze
        func access() -> CaptureAccess { .granted }
        func requestAccess() {}
        func freeze(cursor: Bool) async -> FreezeOutcome { .frozen(freeze) }
        func window(_ id: UInt32, cursor: Bool, shadow: Bool) async -> WindowShot { .gone }
    }
    private struct NoPreferences: CapturePreferences {
        func location() -> RawSetting { RawSetting(nil) }
        func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
        func uiSounds() -> RawSetting { RawSetting(nil) }
    }
    private final class Box { var overlay: CaptureOverlay?; var presented = 0 }

    private var held: CaptureOverlay?
    private var live: [CaptureController] = []
    override func tearDown() {
        held?.close(); held = nil
        for controller in live { controller.teardown() }
        live = []
        super.tearDown()
    }

    /// A Pin exit with no layers: the picture on the pin must not share the frozen display's rows.
    func testAPinMadeWithNoLayersIsNotACropOfTheFrozenDisplay() async throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let whole = try picture(2000, 1600)
        let display = FrozenDisplay(id: DisplayID(number), frame: CGRect(x: 0, y: 0, width: 1000, height: 800), scale: 2, image: whole)
        let freeze = Freeze(displays: [.image(display)] + TheOtherScreens.blankFrames(besides: display.id), windows: [])
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        let home = scratchDirectory("pin-detached-controller")
        let session = CaptureSession(capture: Frames(freeze: freeze), writer: Disk(), trash: NoTrash(), pasteboard: Board(),
                                     preferences: NoPreferences(), shutter: Shutter(), textReader: NoTextReader(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: home))
        let pins = PinBoard(present: { _ in }, screens: { [] })
        let box = Box()
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store, session: session,
                                           presentOverlay: { overlay in box.presented += 1; box.overlay = overlay; return overlay.build() },
                                           pins: pins)
        live.append(controller)
        controller.begin(.area)
        await waitUntil("the press reached the overlay") { box.presented == 1 }
        let overlay = try XCTUnwrap(box.overlay)
        held = overlay
        overlay.mouseDown(on: display.id, at: CGPoint(x: 100, y: 100), flags: [])
        overlay.mouseDragged(on: display.id, at: CGPoint(x: 500, y: 400), flags: [])
        overlay.mouseUp(on: display.id)
        overlay.perform(.exit(.pin))
        await waitUntil("a pin opened") { pins.pins.count == 1 }
        let image = try XCTUnwrap(pins.pins.first?.pinView.layer?.contents as! CGImage?)
        XCTAssertEqual(image.width, 800, "the control: the pin is the selection at its own pixels")
        XCTAssertLessThan(image.bytesPerRow, whole.bytesPerRow, "the pin's picture still has the frozen display's row length: it is a crop of it")
    }

    // MARK: Pixels to device pixels

    /// D3: at scale 1:1 the picture's pixels are the device's pixels. A 2x selection of an odd pixel height is a
    /// half-point frame; whatever the window does to that frame, what the layer draws on a 2x display must be
    /// the image's own pixels, never an image stretched over a rounded box.
    func testAnOddPixelSelectionIsDrawnOneToOneOnTheDevice() throws {
        let scale: CGFloat = 2
        for (w, h) in [(302, 201), (301, 200), (301, 201), (303, 303), (302, 200)] {
            let frame = PinGeometry.opening(local: CGRect(x: 10, y: 10, width: CGFloat(w) / scale, height: CGFloat(h) / scale),
                                            scale: scale, imageWidth: 2000, imageHeight: 2000,
                                            display: CGRect(x: 0, y: 0, width: 1000, height: 1000), primaryHeight: 1000)
            XCTAssertEqual(frame.width * scale, CGFloat(w), "the control: the opening is the image's pixels / scale (\(w)x\(h))")
            let panel = PinPanel(image: try picture(w, h), frame: frame)
            let layer = try XCTUnwrap(panel.pinView.layer)
            let box = panel.pinView.convert(panel.contentLayoutRect, from: nil).size
            let drawn: CGSize
            if layer.contentsGravity == .resize {
                drawn = CGSize(width: box.width * scale, height: box.height * scale)
            } else {
                // Not stretched: the layer shows the image at its own size at the scale it declares.
                drawn = CGSize(width: CGFloat(w), height: CGFloat(h))
            }
            if layer.contentsGravity == .resize {
                XCTAssertEqual(drawn, CGSize(width: w, height: h), "\(w)x\(h) px stretched over \(drawn) device px (frame \(panel.frame.size), native \(panel.native))")
            } else {
                XCTAssertEqual(layer.contentsScale, scale, "\(w)x\(h): an unstretched layer must declare the display's scale")
            }
        }
    }
}
