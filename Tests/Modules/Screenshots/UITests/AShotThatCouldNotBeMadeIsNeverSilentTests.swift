import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A shot the person asked for and the module could not make is said, in the log and on the toast; it is never a flash and
/// nothing.** The controller is driven as the running app drives it (an overlay built and never ordered in) and the
/// overlay is finished with the results that leave the engine no picture: an edit on a display the freeze does not hold, a
/// whole-display pick of one it does not hold, a box of one pixel. What is read afterwards is the board, the disk, the log
/// of this module and the toast. Every refusal the controller already makes (`showRefusal`) is the toast's signal, and
/// `captureFailed` is its word for a shot that was not made.
///
/// Total failure of the subject prints: a press that ends with no board, no file, no toast and no line.
@MainActor
final class AShotThatCouldNotBeMadeIsNeverSilentTests: XCTestCase {

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
    private struct Quiet: ShutterPlaying { func play() {} }
    @MainActor private final class Opened { var overlays: [CaptureOverlay] = [] }

    private struct Scene {
        let controller: CaptureController
        let toast: ShotToast
        let board: CountingBoard
        let disk: FakeWorkDisk
        let opened: Opened
        let display: DisplayID
    }

    private let clock = StepClock()
    private var controllers: [CaptureController] = []

    override func setUp() {
        super.setUp()
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        for controller in controllers { controller.teardown() }
        controllers = []
        clock.finish()
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private func scene() throws -> Scene {
        let frames = try OverlayRig.frames()
        let board = CountingBoard(), disk = FakeWorkDisk(), opened = Opened()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(SaveTarget.desktop.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let home = scratchDirectory("silent-shot")
        let session = CaptureSession(capture: Frames(freeze: Freeze(displays: frames.map { .image($0) }, windows: [])),
                                     writer: disk, trash: NoTrash(), pasteboard: board, preferences: NoPreferences(),
                                     shutter: Quiet(), textReader: NoTextReader(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: home))
        let toast = ShotToastRig.toast(clock)
        let controller = CaptureController(store: store, session: session,
                                           presentOverlay: { overlay in
                                               let built = overlay.build()
                                               if built { opened.overlays.append(overlay) }
                                               return built
                                           },
                                           presentBar: { _ in }, pins: PinBoard(present: { _ in }, screens: { [] }), toast: toast)
        controllers.append(controller)
        return Scene(controller: controller, toast: toast, board: board, disk: disk, opened: opened,
                     display: try XCTUnwrap(frames.first?.id))
    }

    /// A press of the area shortcut, its overlay open, and `result` as what the overlay finishes with; waits for the end.
    private func press(_ s: Scene, finishing result: (DisplayID) -> OverlayResult) async throws {
        s.controller.begin(.area)
        await waitUntil("the overlay opened") { !s.opened.overlays.isEmpty }
        let overlay = try XCTUnwrap(s.opened.overlays.first)
        overlay.finish(result(s.display))
        await waitUntil("the press ended") { !s.controller.isBusy }
    }

    private var log: [LogEntry] { HelmLog.shared.recentEntries().filter { $0.category == ScreenshotsEngine.moduleID } }

    private func refusal(_ s: Scene) -> String? {
        if case .refusal(let title, _, _)? = s.toast.model.content { title } else { nil }
    }

    private let unknown = DisplayID(0xDEAD_BEEF)
    private let area = CGRect(x: 100, y: 100, width: 200, height: 150)

    private func assertSaid(_ s: Scene, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.board.copies + s.disk.written, 0, "\(what): the subject: nothing was delivered", file: file, line: line)
        let said = log.filter { $0.level == .warn || $0.level == .error }
        XCTAssertFalse(said.isEmpty, "\(what): the press ended with no line in the log: the shot is lost and nobody is told", file: file, line: line)
        XCTAssertEqual(refusal(s), ScStr.failedTitle, "\(what): the person is not told on the toast (\(String(describing: s.toast.model.content)))",
                       file: file, line: line)
    }

    // MARK: M068: an edit that makes no picture

    func testAnEditOnADisplayThePictureIsNotOnIsSaidInTheLogAndOnTheToast() async throws {
        let s = try scene()
        try await press(s) { _ in .edited(display: unknown, local: area, layers: [], exit: .confirm) }
        assertSaid(s, "an edit on a display the freeze does not hold")
    }

    func testAnEditOfABoxOfOnePixelStillDeliversTheShot() async throws {
        let s = try scene()
        let box = Annotation(tool: .blur, start: CGPoint(x: 150, y: 150), end: CGPoint(x: 151, y: 151), style: AnnotationStyle())
        try await press(s) { display in .edited(display: display, local: area, layers: [box], exit: .confirm) }
        XCTAssertEqual(s.board.copies + s.disk.written, 2, "the shot with a box of one pixel was not delivered: a flash and no shot")
        XCTAssertNil(refusal(s), "a shot that was made was told as a refusal")
    }

    // MARK: wholeDisplay-silent

    func testAWholeDisplayPickOfADisplayTheFreezeDoesNotHoldIsSaidInTheLogAndOnTheToast() async throws {
        let s = try scene()
        try await press(s) { _ in .wholeDisplay(unknown) }
        assertSaid(s, "a whole display the freeze does not hold")
    }

    /// The control, so the absence above cannot be satisfied by a controller that delivers nothing.
    func testAWholeDisplayPickOfAHeldDisplayDeliversAndComplainsOfNothing() async throws {
        let s = try scene()
        try await press(s) { display in .wholeDisplay(display) }
        XCTAssertEqual(s.board.copies + s.disk.written, 2, "the control: a whole display is a copy and a file")
        XCTAssertNil(refusal(s))
        XCTAssertTrue(log.filter { $0.level == .warn || $0.level == .error }.isEmpty, "the control: an ordinary shot warned")
    }
}
