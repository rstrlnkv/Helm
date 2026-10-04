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

/// **A pin made through the real controller from a freeze whose display sits left of and above the primary at 2x,
/// and the limit asked twice in one turn.** The sibling controller file draws every fixture display at a
/// positive origin; the flip of the AppKit space is only right for a negative one if somebody feeds one.
///
/// Total failure of the subject prints: a pin on the wrong side of the flip (its y above or below the screen),
/// a pin at pixel size on a 2x display, a ninth pin from two Pin exits in one turn at seven.
@MainActor
final class ThePinThroughTheControllerOnADisplayNobodyHadTests: XCTestCase {

    private final class Count: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        var value: Int { lock.withLock { n } }
        func bump() { lock.withLock { n += 1 } }
    }
    private final class Board: ShotPasteboard, @unchecked Sendable {
        let count = Count()
        func copy(png: Data) -> PasteOutcome { count.bump(); return .accepted }
        func copy(text: String) -> PasteOutcome { .accepted }
    }
    private final class Disk: ShotWriting, @unchecked Sendable {
        let count = Count()
        func write(_ png: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            count.bump(); return .written(folder.appendingPathComponent(base + "." + pathExtension))
        }
    }
    private final class Shutter: ShutterPlaying, @unchecked Sendable {
        func play() {}
    }
    private struct Frames: ScreenCapturing {
        let freeze: Freeze
        func access() -> CaptureAccess { .granted }
        func requestAccess() {}
        func freeze(cursor: Bool) async -> FreezeOutcome { .frozen(freeze) }
        func window(_ id: UInt32, cursor: Bool) async -> WindowShot { .gone }
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

    private struct Rig {
        let controller: CaptureController
        let pins: PinBoard
        let box: Box
        let display: FrozenDisplay
        let disk: Disk, clipboard: Board
    }

    /// The first real screen is replaced by a 2x frame at CG (-1920, -200), 1000 x 800 points; the rest are blank.
    private func rig(origin: CGPoint) throws -> Rig {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let context = try XCTUnwrap(CGContext(data: nil, width: 2000, height: 1600, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let display = FrozenDisplay(id: DisplayID(number), frame: CGRect(origin: origin, size: CGSize(width: 1000, height: 800)),
                                    scale: 2, image: try XCTUnwrap(context.makeImage()))
        let freeze = Freeze(displays: [.image(display)] + TheOtherScreens.blankFrames(besides: display.id), windows: [])
        let disk = Disk(), clipboard = Board()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        let home = scratchDirectory("pin-negative")
        let session = CaptureSession(capture: Frames(freeze: freeze), writer: disk, pasteboard: clipboard,
                                     preferences: NoPreferences(), shutter: Shutter(), textReader: NoTextReader(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: home))
        let pins = PinBoard(present: { _ in }, screens: { [] })
        let box = Box()
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store, session: session,
                                           presentOverlay: { overlay in box.presented += 1; box.overlay = overlay; return overlay.build() },
                                           pins: pins)
        live.append(controller)
        return Rig(controller: controller, pins: pins, box: box, display: display, disk: disk, clipboard: clipboard)
    }

    private func press(_ rig: Rig, count: Int) async throws -> CaptureOverlay {
        rig.controller.begin(.area)
        await waitUntil("the press \(count) reached the overlay") { rig.box.presented == count }
        let overlay = try XCTUnwrap(rig.box.overlay)
        held = overlay
        let id = rig.display.id
        overlay.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: 500, y: 400), flags: [])
        overlay.mouseUp(on: id)
        return overlay
    }

    /// Worked by hand, no `ScreenSpace` on the expected side: the selection (100,100)-(500,400) from the display's
    /// top-left at CG origin (-1920,-200) is x -1820, CG top -100, 400 x 300 points; the AppKit y of its lower edge
    /// is the primary's height minus (CG top + height) = H - 200.
    func testAPinFromADisplayLeftOfAndAboveThePrimaryAtTwoXLandsWhereTheSelectionWas() async throws {
        let rig = try rig(origin: CGPoint(x: -1920, y: -200))
        let overlay = try await press(rig, count: 1)
        overlay.perform(.exit(.pin))
        await waitUntil("a pin opened") { rig.pins.pins.count == 1 }
        let primary = try XCTUnwrap(NSScreen.screens.first).frame.height
        let pin = try XCTUnwrap(rig.pins.pins.first)
        XCTAssertEqual(pin.frame.minX, -1820, accuracy: 0.01)
        XCTAssertEqual(pin.frame.minY, primary - 200, accuracy: 0.01, "the pin is on the wrong side of the flip")
        XCTAssertEqual(pin.frame.size, CGSize(width: 400, height: 300), "the pin is not the selection in points at 2x")
        XCTAssertEqual((try XCTUnwrap(pin.pinView.layer?.contents) as! CGImage).width, 800)
        XCTAssertEqual(rig.disk.count.value, 0)
        XCTAssertEqual(rig.clipboard.count.value, 0)
    }

    /// Seven pins are open; two Pin exits arrive in one turn (a repeat of the key that the overlay does not mark
    /// as a repeat, or the button and the key together). One pin may follow, never two.
    func testTwoPinExitsInOneTurnAtSevenOpenMakeAtMostEight() async throws {
        let rig = try rig(origin: .zero)
        for index in 0..<7 {
            rig.pins.open(rig.display.image, frame: CGRect(x: 10 * CGFloat(index), y: 10, width: 50, height: 50))
        }
        let overlay = try await press(rig, count: 1)
        overlay.perform(.exit(.pin))
        overlay.perform(.exit(.pin))
        await grace(0.6)
        XCTAssertLessThanOrEqual(rig.pins.pins.count, PinGeometry.limit, "two Pin exits in one turn opened pin number \(rig.pins.pins.count)")
        XCTAssertEqual(rig.pins.pins.count, 8)
    }

    /// A press that begins while the previous Pin delivery is still crossing its suspension is dropped by `busy`;
    /// the board is never asked for room twice for one press. Eight open: the exit is refused, nothing opens late.
    func testAtEightOpenARefusedExitOpensNothingLaterEither() async throws {
        let rig = try rig(origin: .zero)
        for index in 0..<8 {
            rig.pins.open(rig.display.image, frame: CGRect(x: 10 * CGFloat(index), y: 10, width: 50, height: 50))
        }
        let overlay = try await press(rig, count: 1)
        overlay.perform(.exit(.pin))
        await grace(0.5)
        XCTAssertEqual(rig.pins.pins.count, 8)
        XCTAssertEqual(rig.disk.count.value, 0, "the refused pin was saved")
        XCTAssertFalse(rig.controller.isBusy && rig.box.overlay == nil, "the controller is busy with no overlay")
    }
}
