import CoreGraphics
import Foundation
import XCTest
@testable import Module_Screenshots_Engine

/// **Copy Text puts the text and only the text on the clipboard,** and nothing when there is nothing; a refused copy
/// is a refusal and its words are in no log line; a reader that failed is a failure, and a reading cancelled in flight
/// answers nothing.
final class CopiedTextKeepsTheReadingOrderTests: XCTestCase {

    private func line(_ string: String, y: CGFloat = 0.5, x: CGFloat = 0.1) -> RecognizedLine {
        RecognizedLine(string: string, box: CGRect(x: x, y: y, width: 0.3, height: 0.05))
    }

    // MARK: Through the session

    private func makeRig() -> Rig { Rig(home: scratchDirectory("shots-text")) }

    func testTheClipboardTakesTheTextAndOnlyTheText() throws {
        let rig = makeRig()
        XCTAssertEqual(rig.session.copyText([line("one"), line("two")]), .copied)
        XCTAssertEqual(rig.pasteboard.texts, ["one\ntwo"])
        XCTAssertTrue(rig.pasteboard.copies.isEmpty, "no picture went with it")
    }

    func testNoTextLeavesTheClipboardAsItWas() throws {
        let rig = makeRig()
        XCTAssertEqual(rig.session.copyText([line("kept")]), .copied)
        XCTAssertEqual(rig.session.copyText([line(" ")]), .noText)
        XCTAssertEqual(rig.session.copyText([]), .noText)
        XCTAssertEqual(rig.pasteboard.texts, ["kept"], "an earlier copy is not replaced by an empty one")
    }

    func testARefusedCopyIsARefusalAndTheWordsAreInNoLogLine() throws {
        let rig = makeRig()
        ScreenshotsLog.begin()
        defer { ScreenshotsLog.end() }
        ScreenshotsLog.proveTheLogIsOn()
        rig.pasteboard.accepts = false
        XCTAssertEqual(rig.session.copyText([line("a secret sentence")]), .refused)
        XCTAssertFalse(ScreenshotsLog.lines.isEmpty, "the refusal is said, or an absence below proves nothing")
        XCTAssertFalse(ScreenshotsLog.lines.contains { $0.contains("secret") }, "\(ScreenshotsLog.lines)")
    }

    // MARK: The reading

    private func freeze(shot: DisplayShot) -> Freeze { Freeze(displays: [shot], windows: []) }
    private let area = CGRect(x: 10, y: 10, width: 50, height: 20)

    func testAReaderThatFailedIsAFailureNotAnEmptyReading() async throws {
        let rig = makeRig()
        rig.reader.reading = .failed
        let failed = await rig.session.readText(freeze(shot: Rig.display(1)), display: DisplayID(1), local: area)
        XCTAssertEqual(failed, .failed)
        rig.reader.reading = .read([])
        let empty = await rig.session.readText(freeze(shot: Rig.display(1)), display: DisplayID(1), local: area)
        XCTAssertEqual(empty, .read([], RecognizedBoxes.Source(pixels: CGRect(x: 20, y: 20, width: 100, height: 40), scale: 2)),
                       "found nothing, which is not the same answer")
    }

    /// The task is the editor's: cancelled while the reader works, the answer is dropped and not returned.
    @MainActor
    func testAReadingCancelledInFlightIsDropped() async throws {
        let rig = makeRig()
        rig.reader.reading = .read([line("late")])
        rig.reader.held = true
        let session = rig.session, frozen = freeze(shot: Rig.display(1)), area = area
        let task = Task { await session.readText(frozen, display: DisplayID(1), local: area) }
        await waitUntil("the reader was asked") { rig.reader.calls == 1 }
        task.cancel()
        rig.reader.release()
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(rig.reader.calls, 1, "the subject: the reader was asked and did answer")
    }

    func testATaskCancelledBeforeItAsksNeverAsks() async throws {
        let rig = makeRig()
        let session = rig.session, frozen = freeze(shot: Rig.display(1)), area = area
        let task = Task { () -> CaptureSession.AreaReading in
            // Parked until cancelled: a sleep that is cancelled ends at once, so the task is cancelled when it asks.
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            return await session.readText(frozen, display: DisplayID(1), local: area)
        }
        task.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(rig.reader.calls, 0)
    }
}
