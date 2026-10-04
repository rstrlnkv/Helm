import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A reading of the area's text belongs to the editor that asked, for the area it asked about, and an answer that finds either gone is
/// dropped:** nothing is inserted, nothing is copied, no plate is put up.
///
/// The overlay holds the task (`CaptureOverlay.beginReading`); `close` cancels it, and a change of the area under it ends it, since its boxes
/// were for the old area. The reader here is the overlay's own seam (`EditorTextTools`) answering when the test says, so each test has a
/// reading in flight at the moment it breaks the tie.
///
/// A dropped answer is asserted by what did not happen, so each such test ends with an answer of the same path that does act (the control):
/// the stale answer was resumed first, so a defect that acted on it would already have acted.
@MainActor
final class ARecognitionThatOutlivesTheEditorIsDroppedTests: XCTestCase {

    /// The reader the overlay is handed: every call waits for `answer`, and it counts what the cancellation reached.
    private final class Reader: @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: [CheckedContinuation<CaptureSession.AreaReading, Never>] = []
        private var _asked: [(DisplayID, CGRect)] = []
        private var _cancelled = 0
        private var _copied: [[RecognizedLine]] = []
        var copyAnswer = CaptureSession.TextCopy.copied

        var calls: Int { lock.withLock { _asked.count } }
        var asked: [(DisplayID, CGRect)] { lock.withLock { _asked } }
        var cancelled: Int { lock.withLock { _cancelled } }
        var copied: [[RecognizedLine]] { lock.withLock { _copied } }

        func read(_ display: DisplayID, _ area: CGRect) async -> CaptureSession.AreaReading {
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<CaptureSession.AreaReading, Never>) in
                    lock.withLock { waiting.append(continuation); _asked.append((display, area)) }
                }
            } onCancel: { lock.withLock { _cancelled += 1 } }
        }

        func copy(_ lines: [RecognizedLine]) -> CaptureSession.TextCopy {
            lock.withLock { _copied.append(lines) }
            return copyAnswer
        }

        /// Answers the `index`th call, in the order the calls came.
        func answer(_ index: Int, _ reading: CaptureSession.AreaReading) {
            // A missing call is a finding of its own, and not a crash that takes the other tests of the file with it.
            guard let continuation = lock.withLock({ waiting.indices.contains(index) ? waiting[index] : nil }) else {
                return XCTFail("the reader was never asked for call \(index)")
            }
            continuation.resume(returning: reading)
        }
    }

    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)
    private var results: [OverlayResult] = []
    private var rigged: (overlay: CaptureOverlay, display: DisplayID, view: OverlayView)?
    private var reader = Reader()

    override func setUp() {
        super.setUp()
        AppLanguage.override = .en
    }

    override func tearDown() {
        rigged?.overlay.close()
        rigged = nil
        AppLanguage.override = nil
        super.tearDown()
    }

    private func build() throws -> (overlay: CaptureOverlay, display: DisplayID, view: OverlayView) {
        reader = Reader()
        let tools = EditorTextTools(read: { [reader] in await reader.read($0, $1) }, copy: { [reader] in reader.copy($0) })
        let built = try OverlayRig.overlay(scale: 1, area: area, textTools: tools) { [weak self] in self?.results.append($0) }
        rigged = built
        return built
    }

    /// One e-mail address, on the upper part of the area as the reader sees it, and the part of the frame that was read.
    private var reading: CaptureSession.AreaReading {
        .read([RecognizedLine(string: "me@example.com", box: CGRect(x: 0.1, y: 0.6, width: 0.5, height: 0.1),
                              matches: [PrivateMatch(kind: .emailAddress, box: CGRect(x: 0.1, y: 0.6, width: 0.5, height: 0.1))])],
               RecognizedBoxes.Source(pixels: area, scale: 1))
    }

    private func plates(_ view: OverlayView) -> [String] { view.visiblePlates.compactMap(\.string) }

    // MARK: The control: an answer that finds everything as it was

    func testAnAnswerForTheSameEditorAndAreaActs() async throws {
        let (overlay, _, view) = try build()
        overlay.perform(.blurPersonalText)
        await waitUntil("the reader was asked") { reader.calls == 1 }
        reader.answer(0, reading)
        await waitUntil("the plate said what was done") { !plates(view).isEmpty }
        XCTAssertEqual(overlay.editedLayers.map(\.tool), [.blur], "the subject: one blur layer for the one find")
        XCTAssertEqual(plates(view), [ScStr.blurred(1)])
        overlay.perform(.undo)
        XCTAssertEqual(overlay.editedLayers, [], "the find is one undo step")
    }

    // MARK: The editor closed

    func testAnAnswerAfterTheEditorClosedInsertsNothingAndCopiesNothing() async throws {
        for ask in [EditorAction.blurPersonalText, .copyText] {
            let (overlay, display, _) = try build()
            overlay.perform(ask)
            await waitUntil("the reader was asked (\(ask))") { reader.calls == 1 }
            overlay.close()
            XCTAssertEqual(reader.cancelled, reader.calls, "\(ask): the close did not cancel the task that waits")
            reader.answer(0, reading)
            await grace()
            XCTAssertEqual(overlay.editedLayers, [], "\(ask): a layer went in after the editor closed")
            XCTAssertTrue(reader.copied.isEmpty, "\(ask): text was copied after the editor closed")
            XCTAssertNil(overlay.view(for: display), "\(ask): the control: the editor is gone")
            XCTAssertTrue(results.isEmpty, "\(ask): the close delivered something")
            rigged = nil
        }
    }

    // MARK: The area changed

    func testAnAnswerAfterTheAreaMovedIsDroppedAndTheItemsComeBack() async throws {
        let (overlay, _, view) = try build()
        overlay.perform(.blurPersonalText)
        await waitUntil("the reader was asked") { reader.calls == 1 }
        XCTAssertFalse(blurItemEnabled(overlay), "the control: the item is off while a reading runs")
        overlay.perform(.nudge(dx: 1, dy: 0, pixels: 10))
        XCTAssertNotEqual(overlay.editedArea, area, "the subject: the area moved under the reading")
        XCTAssertTrue(blurItemEnabled(overlay), "the reading of the old area still holds the items off")
        XCTAssertEqual(reader.cancelled, 1, "the reading of the old area was not cancelled")
        // Another reading begins on the new area; the old one answers first, then the new one.
        overlay.perform(.copyText)
        await waitUntil("the second reading asked") { reader.calls == 2 }
        XCTAssertEqual(reader.asked[1].1, overlay.editedArea, "the second reading is for the area the editor holds now")
        reader.answer(0, reading)
        reader.answer(1, .read([RecognizedLine(string: "words", box: CGRect(x: 0, y: 0, width: 1, height: 1))],
                               RecognizedBoxes.Source(pixels: area, scale: 1)))
        await waitUntil("the second answer was acted on") { !plates(view).isEmpty }
        XCTAssertEqual(overlay.editedLayers, [], "the answer for the old area inserted a layer")
        XCTAssertEqual(reader.copied.count, 1, "one copy: the second reading's, not the old one's")
        XCTAssertEqual(reader.copied.first?.first?.string, "words")
        XCTAssertEqual(plates(view), [ScStr.textCopied])
    }

    func testAnAnswerAfterACropTookANewAreaIsDropped() async throws {
        let (overlay, display, view) = try build()
        overlay.perform(.blurPersonalText)
        await waitUntil("the reader was asked") { reader.calls == 1 }
        overlay.perform(.crop)
        let handle = try XCTUnwrap(view.drawnAreaHandles[AreaHandle.allCases.firstIndex(of: .right)!])
        overlay.mouseDown(on: display, at: handle, flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: handle.x - 100, y: handle.y), flags: [])
        overlay.mouseUp(on: display)
        overlay.perform(.exit(.confirm))
        XCTAssertEqual(overlay.editedArea, CGRect(x: 100, y: 100, width: 300, height: 300), "the subject: the crop was taken")
        reader.answer(0, reading)
        overlay.perform(.blurPersonalText)
        await waitUntil("the reading of the cropped area asked") { reader.calls == 2 }
        reader.answer(1, .read([], RecognizedBoxes.Source(pixels: overlay.editedArea ?? .zero, scale: 1)))
        await waitUntil("the second answer was acted on") { !plates(view).isEmpty }
        XCTAssertEqual(overlay.editedLayers, [], "the answer for the uncropped area inserted a layer")
        XCTAssertEqual(plates(view), [ScStr.nothingBlurred])
    }

    // MARK: One at a time

    func testASecondChoiceWhileOneRunsStartsNothing() async throws {
        let (overlay, _, _) = try build()
        overlay.perform(.copyText)
        await waitUntil("the reader was asked") { reader.calls == 1 }
        for ask in [EditorAction.copyText, .blurPersonalText, .copyText] { overlay.perform(ask) }
        await grace()
        XCTAssertEqual(reader.calls, 1, "a second choice started another reading")
        XCTAssertFalse(blurItemEnabled(overlay))
        XCTAssertFalse(copyItemEnabled(overlay))
        reader.answer(0, .read([RecognizedLine(string: "a", box: CGRect(x: 0, y: 0, width: 1, height: 1))], RecognizedBoxes.Source(pixels: area, scale: 1)))
        await waitUntil("the answer was acted on") { reader.copied.count == 1 }
        XCTAssertTrue(blurItemEnabled(overlay) && copyItemEnabled(overlay), "the items stay off after the answer")
    }

    // MARK: What is read

    /// A crop that is still pending is the area as the screen shows it, which is what the editor holds (`editedArea`).
    func testAPendingCropIsReadAsTheScreenShowsIt() async throws {
        let (overlay, display, view) = try build()
        overlay.perform(.crop)
        let handle = try XCTUnwrap(view.drawnAreaHandles[AreaHandle.allCases.firstIndex(of: .right)!])
        overlay.mouseDown(on: display, at: handle, flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: handle.x - 100, y: handle.y), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertTrue(overlay.isCropping, "the control: the crop is still pending")
        overlay.perform(.copyText)
        await waitUntil("the reader was asked") { reader.calls == 1 }
        XCTAssertEqual(reader.asked.first?.0, display)
        XCTAssertEqual(reader.asked.first?.1, CGRect(x: 100, y: 100, width: 300, height: 300))
        XCTAssertEqual(reader.asked.first?.1, overlay.editedArea)
        XCTAssertTrue(overlay.isCropping, "reading took the pending crop")
    }

    // MARK: The menu

    private func readingItem(_ overlay: CaptureOverlay, _ title: String) -> Bool? {
        for case .reading(let name, _, _, let enabled, _) in EditorMenu.items(for: overlay.palette) where name == title { return enabled }
        return nil
    }
    private func blurItemEnabled(_ overlay: CaptureOverlay) -> Bool { readingItem(overlay, ScStr.blurPersonalText) ?? false }
    private func copyItemEnabled(_ overlay: CaptureOverlay) -> Bool { readingItem(overlay, ScStr.copyText) ?? false }
}
