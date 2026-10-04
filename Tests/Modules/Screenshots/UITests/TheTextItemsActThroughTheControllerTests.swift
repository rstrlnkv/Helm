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

/// **The two reading items, end to end as the controller wires them:** the overlay the controller opens is handed the session's reader and
/// clipboard, a fake reader answers with set lines, and what comes out is read off the editor and off a real pasteboard of the test's own.
///
/// Blur Emails and Phone Numbers puts one ordinary blur layer in for each find, in one undo step, and the plate says how many; Copy Text
/// puts the lines, one to a line, on a clipboard that carries the two markers clipboard managers read, and the editor stays open.
@MainActor
final class TheTextItemsActThroughTheControllerTests: XCTestCase {

    private final class Reader: ScreenTextReading, @unchecked Sendable {
        private let lock = NSLock()
        private var _images: [CGImage] = []
        let lines: [RecognizedLine]
        init(_ lines: [RecognizedLine]) { self.lines = lines }
        var images: [CGImage] { lock.withLock { _images } }
        func read(_ image: CGImage) async -> TextReading {
            lock.withLock { _images.append(image) }
            return .read(lines)
        }
    }
    private struct Disk: ShotWriting {
        func write(_ data: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            .written(folder.appendingPathComponent(base + "." + pathExtension))
        }
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
    private struct NoShutter: ShutterPlaying { func play() {} }
    @MainActor private final class Opened { var overlays: [CaptureOverlay] = [] }

    private var board: NSPasteboard!
    private var controller: CaptureController?
    private var opened = Opened()

    override func setUp() {
        super.setUp()
        AppLanguage.override = .en
        board = NSPasteboard(name: NSPasteboard.Name("helm.test.textitems.\(UUID().uuidString)"))
    }

    override func tearDown() {
        opened.overlays.forEach { $0.close() }
        controller?.cancel()
        board.releaseGlobally()
        AppLanguage.override = nil
        super.tearDown()
    }

    private func line(_ string: String, y: CGFloat, _ kind: PrivateKind? = nil) -> RecognizedLine {
        let box = CGRect(x: 0.1, y: y, width: 0.5, height: 0.08)
        return RecognizedLine(string: string, box: box, matches: kind.map { [PrivateMatch(kind: $0, box: box)] } ?? [])
    }

    /// The controller over a real session whose reader is `reader`, its overlay open on the first display with the area (100,100)-(300,250) released.
    private func opening(_ reader: Reader) async throws -> (overlay: CaptureOverlay, view: OverlayView, display: DisplayID) {
        let frames = try OverlayRig.frames()
        let freeze = Freeze(displays: frames.map { .image($0) }, windows: [])
        let display = try XCTUnwrap(frames.first).id
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        let home = FileManager.default.temporaryDirectory
        let session = CaptureSession(capture: Frames(freeze: freeze), writer: Disk(), pasteboard: SystemShotPasteboard(named: board.name),
                                     preferences: NoPreferences(), shutter: NoShutter(), textReader: reader,
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: home))
        let opened = self.opened
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store, session: session,
                                           presentOverlay: { overlay in
                                               let built = overlay.build()
                                               if built { opened.overlays.append(overlay) }
                                               return built
                                           },
                                           presentBar: { _ in })
        self.controller = controller
        controller.begin(.area)
        await waitUntil("the overlay opened") { !opened.overlays.isEmpty }
        let overlay = try XCTUnwrap(opened.overlays.first)
        overlay.mouseDown(on: display, at: CGPoint(x: 100, y: 100), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 300, y: 250), flags: [])
        overlay.mouseUp(on: display)
        return (overlay, try XCTUnwrap(overlay.view(for: display)), display)
    }

    func testBlurPutsOneBlurLayerForEachFindInOneUndoStep() async throws {
        let reader = Reader([line("Write to me@example.com", y: 0.8, .emailAddress), line("Call +1 555 010 0199", y: 0.6, .phoneNumber),
                             line("just words", y: 0.4), line("https://example.com/a", y: 0.2, .link)])
        let (overlay, view, _) = try await opening(reader)
        XCTAssertEqual(overlay.editedLayers, [], "the control: nothing is drawn")
        overlay.perform(.blurPersonalText)
        await waitUntil("the plate said what was done") { !view.visiblePlates.isEmpty }
        XCTAssertEqual(reader.images.count, 1, "one reading")
        XCTAssertEqual([reader.images.first?.width, reader.images.first?.height], [200, 150], "the reader was handed the area's own pixels")
        XCTAssertEqual(overlay.editedLayers.map(\.tool), [.blur, .blur, .blur], "one blur layer for each of the three finds, and no other layer")
        XCTAssertEqual(Set(overlay.editedLayers.map(\.id)).count, 3)
        XCTAssertEqual(view.visiblePlates.compactMap(\.string), [ScStr.blurred(3)])
        overlay.perform(.undo)
        XCTAssertEqual(overlay.editedLayers, [], "the three layers are one undo step")
        overlay.perform(.redo)
        XCTAssertEqual(overlay.editedLayers.count, 3, "and one redo")
        XCTAssertNotNil(overlay.editedArea, "the editor stays open")
    }

    func testCopyPutsTheLinesOnAConcealedClipboardAndTheEditorStaysOpen() async throws {
        let reader = Reader([line("first line", y: 0.8), line("second line", y: 0.6)])
        let (overlay, view, _) = try await opening(reader)
        overlay.perform(.copyText)
        await waitUntil("the plate said what was done") { !view.visiblePlates.isEmpty }
        XCTAssertEqual(board.string(forType: .string), "first line\nsecond line", "the lines, one to a line, in the reader's order")
        let types = Set(board.types ?? [])
        XCTAssertTrue(types.contains(SystemShotPasteboard.concealedType) && types.contains(SystemShotPasteboard.transientType),
                      "a clipboard manager would record this text: \(types)")
        XCTAssertEqual(view.visiblePlates.compactMap(\.string), [ScStr.textCopied])
        XCTAssertNotNil(overlay.editedArea, "the editor stays open")
        XCTAssertEqual(overlay.editedLayers, [], "Copy Text draws nothing")
    }

    func testCopyOfAPictureWithNoTextSaysSoAndLeavesTheClipboardAlone() async throws {
        let (overlay, view, _) = try await opening(Reader([]))
        board.declareTypes([.string], owner: nil)
        board.setString("earlier", forType: .string)
        overlay.perform(.copyText)
        await waitUntil("the plate said what was found") { !view.visiblePlates.isEmpty }
        XCTAssertEqual(view.visiblePlates.compactMap(\.string), [ScStr.noTextFound])
        XCTAssertEqual(board.string(forType: .string), "earlier", "an empty reading replaced what the person had copied")
    }
}
