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

/// **Pin is a third way out of the editor, and it is not a save.** The exit writes no file, touches no clipboard,
/// plays no shutter and shows no toast; the picture arrives as a pin on the selection's own place at 1:1; the
/// controller is not busy afterwards and the next area press reaches the overlay. Turning the module off closes
/// every pin; Esc and ✕ on the capture bar (`cancel()`) close none.
///
/// Total failure of the subject prints: `.pin` falling through the delivery switch into the saving branch (a file on
/// the Desktop of somebody who asked for a pin, the very silent write the plan names), a controller left busy so
/// that the next ⇧⌘2 does nothing, a pin that opens on the wrong display or a pixel off or at the pixel count,
/// pins that survive the module, a pin that opens for a module that was switched off between the exit and the delivery.
///
/// The ports are named at the construction and are this file's own, as every sibling's are: the engine tests'
/// `Fakes.swift` is another target's. The board is given a `present:` that counts, so no pin reaches a screen;
/// the controller is given `pins:` for the same reason (assumed: `CaptureController.init(…, presentOverlay:, pins:, …)`
/// and `let pins: PinBoard` readable by a test, `func teardown()`).
@MainActor
final class ThePinExitLeavesNoFileAndNoTraceInTheControllerTests: XCTestCase {

    private typealias Board = CountingBoard
    private final class Disk: ShotWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var written: Int { lock.withLock { count } }
        // A disk that counts its writes and keeps no file: nothing is read at any path and no name is claimed.
        func reading(of url: URL) -> ShotReading? { nil }
        func claim(_ written: URL, as name: URL) -> Bool { false }
        func write(_ png: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            lock.withLock { count += 1 }
            return .written(WrittenShot(url: folder.appendingPathComponent(base + "." + pathExtension), reading: NoFile.reading))
        }
    }
    private final class Shutter: ShutterPlaying, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var plays: Int { lock.withLock { count } }
        func play() { lock.withLock { count += 1 } }
    }
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

    private final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var value: Int { lock.withLock { n } }
        func bump() { lock.withLock { n += 1 } }
    }

    private struct Rig {
        let controller: CaptureController
        let pins: PinBoard
        let disk: Disk, clipboard: Board, shutter: Shutter
        let freeze: Freeze
        let display: FrozenDisplay
        let overlays: Count
        let overlay: () -> CaptureOverlay?
    }

    private var held: CaptureOverlay?
    private var live: [CaptureController] = []

    override func tearDown() {
        held?.close()
        held = nil
        for controller in live { controller.teardown() }
        live = []
        super.tearDown()
    }

    /// Everything named: the thumbnail is off (the toast is a real panel), the save target is the Desktop
    /// (a file is what a wrongly routed pin would make), and the pins' presenter only counts.
    private func rig(scale: CGFloat = 1) throws -> Rig {
        let frames = try OverlayRig.frames(scale: scale)
        let freeze = Freeze(displays: frames.map { .image($0) }, windows: [])
        let disk = Disk(), clipboard = Board(), shutter = Shutter()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(SaveTarget.desktop.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let home = scratchDirectory("pin-exit")
        let session = CaptureSession(capture: Frames(freeze: freeze), writer: disk, trash: NoTrash(), pasteboard: clipboard,
                                     preferences: NoPreferences(), shutter: shutter,
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: home))
        let pins = PinBoard(present: { _ in }, screens: {
            NSScreen.screens.compactMap { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32).map { (DisplayID($0), screen.frame) }
            }
        })
        let overlays = Count()
        let box = OverlayBox()
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store, session: session,
                                           presentOverlay: { overlay in
                                               overlays.bump()
                                               box.overlay = overlay
                                               return overlay.build()
                                           },
                                           pins: pins)
        live.append(controller)
        return Rig(controller: controller, pins: pins, disk: disk, clipboard: clipboard, shutter: shutter, freeze: freeze,
                   display: try XCTUnwrap(frames.first), overlays: overlays, overlay: { box.overlay })
    }

    private final class OverlayBox { var overlay: CaptureOverlay? }

    /// A press to the editor with an area (100,100)-(500,400) released on the first display.
    private func press(_ rig: Rig, count expected: Int = 1) async throws -> CaptureOverlay {
        rig.controller.begin(.area)
        await waitUntil("the area press reached the overlay for the \(expected). time") { rig.overlays.value == expected }
        let overlay = try XCTUnwrap(rig.overlay())
        held = overlay
        let id = rig.display.id
        overlay.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: 500, y: 400), flags: [])
        overlay.mouseUp(on: id)
        return overlay
    }

    private func primaryHeight() throws -> CGFloat { try XCTUnwrap(NSScreen.screens.first).frame.height }

    // MARK: The exit

    /// At 1x and 2x: the pin is the selection's size in points, at the place `ScreenSpace` gives it, and the
    /// delivery that made it wrote and copied nothing, played no shutter, and left no overlay.
    func testThePinExitMakesAPinOnTheSelectionAndNothingElse() async throws {
        for scale in [CGFloat(1), 2] {
            let rig = try rig(scale: scale)
            let overlay = try await press(rig)
            overlay.perform(.exit(.pin))
            await waitUntil("a pin opened at scale \(scale)") { rig.pins.pins.count == 1 }
            await grace(0.3)
            XCTAssertEqual(rig.disk.written, 0, "a pin was saved as a file (scale \(scale))")
            XCTAssertEqual(rig.clipboard.copies, 0, "a pin touched the clipboard (scale \(scale))")
            XCTAssertEqual(rig.shutter.plays, 0, "a pin played the shutter (scale \(scale))")
            XCTAssertEqual(rig.pins.pins.count, 1)
            let expected = ScreenSpace.appKitRect(
                fromCG: ScreenSpace.global(CGRect(x: 100, y: 100, width: 400, height: 300), in: rig.display.frame),
                primaryHeight: try primaryHeight())
            let frame = try XCTUnwrap(rig.pins.pins.first).frame
            XCTAssertEqual(frame.width, 400, accuracy: 0.01, "the pin is not the selection's width in points (scale \(scale))")
            XCTAssertEqual(frame.height, 300, accuracy: 0.01, "the pin is not the selection's height in points (scale \(scale))")
            XCTAssertEqual(frame.minX, expected.minX, accuracy: 0.01, "the pin is not where the selection was (scale \(scale))")
            XCTAssertEqual(frame.minY, expected.minY, accuracy: 0.01, "the pin is not where the selection was (scale \(scale))")
            let image = try XCTUnwrap(rig.pins.pins.first?.pinView.layer?.contents, "the pin shows nothing")
            XCTAssertEqual((image as! CGImage).width, Int(400 * scale), "the pin's picture is not at the display's own resolution (scale \(scale))")
        }
    }

    /// The control that gives the absences above their meaning: the same press ended with Return does write.
    func testTheSameAreaEndedByReturnDoesWriteAndOpensNoPin() async throws {
        let rig = try rig()
        let overlay = try await press(rig)
        overlay.perform(.exit(.confirm))
        await waitUntil("the confirmed area was delivered") { rig.disk.written == 1 }
        XCTAssertEqual(rig.pins.pins.count, 0, "Return opened a pin")
    }

    /// Busy is released, and the next press reaches the overlay again.
    func testAfterAPinTheControllerIsFreeAndTheNextAreaPressReachesTheOverlay() async throws {
        let rig = try rig()
        let overlay = try await press(rig)
        overlay.perform(.exit(.pin))
        await waitUntil("a pin opened") { rig.pins.pins.count == 1 }
        await waitUntil("the controller let go of its busy flag") { !rig.controller.isBusy }
        let second = try await press(rig, count: 2)
        XCTAssertEqual(rig.overlays.value, 2, "the second area press did not reach the overlay")
        second.perform(.exit(.pin))
        await waitUntil("a second pin opened beside the first") { rig.pins.pins.count == 2 }
    }

    // MARK: Lifetime

    func testTheModulesTeardownClosesEveryPinAndCancelClosesNone() async throws {
        let rig = try rig()
        for _ in 0..<2 { try rig.pins.open(makePicture(), frame: CGRect(x: 100, y: 100, width: 50, height: 50)) }
        XCTAssertEqual(rig.pins.pins.count, 2)
        rig.controller.cancel()
        XCTAssertEqual(rig.pins.pins.count, 2, "cancel() — Esc or ✕ on the capture bar — closed a pin")
        rig.controller.teardown()
        XCTAssertEqual(rig.pins.pins.count, 0, "the module's teardown left a pin open")
    }

    /// The overlay left by the pin exit and the module switched off in the same turn, before the delivery
    /// runs: the delivery is cancelled and must open nothing. The control is the first test of this file.
    func testAPinDeliveredToAModuleThatWentOffOpensNothing() async throws {
        let rig = try rig()
        let overlay = try await press(rig)
        overlay.perform(.exit(.pin))
        rig.controller.teardown()
        await grace(0.5)
        XCTAssertEqual(rig.pins.pins.count, 0, "a pin opened for a module that was switched off")
        XCTAssertEqual(rig.disk.written, 0)
    }

    /// Both places that drop the controller (a new view model, the module switched off) must close the pins:
    /// read from the source because the controller they reach is private to `ScreenshotsCapture`.
    func testBothPlacesThatDropTheControllerCloseThePins() throws {
        let source = SwiftSource.code(try RepoSource.text(of: "Sources/Modules/Screenshots/UI/ScreenshotsCapture.swift"))
        XCTAssertFalse(source.isEmpty)
        XCTAssertEqual(source.components(separatedBy: "teardown()").count - 1, 3, "teardown() should be declared once and called twice")
        XCTAssertFalse(source.contains("controller?.cancel()"), "a place that drops the controller still only cancels, and leaves the pins")
    }

    private func makePicture() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
}
