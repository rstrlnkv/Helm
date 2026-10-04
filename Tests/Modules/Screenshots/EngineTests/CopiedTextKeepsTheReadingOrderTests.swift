import CoreGraphics
import Foundation
import XCTest
@testable import Module_Screenshots_Engine

/// **Copy Text puts the lines on the clipboard in the order the reader read them,** one to a line, and nothing
/// when there is nothing; a refused copy is a refusal; and the words are in no log line. And **the area is read
/// from the frame the file is cut from,** by a task that can be cancelled and then answers nothing.
final class CopiedTextKeepsTheReadingOrderTests: XCTestCase {

    private func line(_ string: String, y: CGFloat = 0.5, x: CGFloat = 0.1) -> RecognizedLine {
        RecognizedLine(string: string, box: CGRect(x: x, y: y, width: 0.3, height: 0.05))
    }

    // MARK: The text

    func testTheLinesAreJoinedByNewlinesInTheOrderTheyCame() {
        XCTAssertEqual(CopiedText.text(of: [line("first"), line("second"), line("third")]), "first\nsecond\nthird")
    }

    /// The reader's order is the reading order and is kept: a second column that sits higher on the page than the
    /// end of the first is not moved up into it by a sort on position.
    func testALineIsNotMovedByWhereItSits() {
        let lines = [line("column one, low", y: 0.1, x: 0.1), line("column two, high", y: 0.9, x: 0.6),
                     line("column two, lower", y: 0.8, x: 0.6)]
        XCTAssertEqual(CopiedText.text(of: lines), "column one, low\ncolumn two, high\ncolumn two, lower")
    }

    func testBlankLinesAreLeftOut() {
        XCTAssertEqual(CopiedText.text(of: [line("a"), line(""), line("  \t "), line("b")]), "a\nb")
    }

    func testTheWordsOfAnyScriptAreKeptAsTheyWere() {
        XCTAssertEqual(CopiedText.text(of: [line("Звоните +7 (916) 123-45-67"), line("日本語の段落です。"), line("  indented")]),
                       "Звоните +7 (916) 123-45-67\n日本語の段落です。\n  indented")
    }

    func testNoTextIsNil() {
        XCTAssertNil(CopiedText.text(of: []))
        XCTAssertNil(CopiedText.text(of: [line(""), line(" ")]))
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

    /// A 2× display of 100 × 50 points: the area (10, 10, 50, 20) is 100 × 40 pixels at (20, 20).
    func testTheAreaIsReadAtNativeResolutionAndTheLinesComeBackWithWhereItLies() async throws {
        let rig = makeRig()
        let lines = [line("a line")]
        rig.reader.reading = .read(lines)
        let outcome = await rig.session.readText(freeze(shot: Rig.display(1)), display: DisplayID(1),
                                                 local: CGRect(x: 10, y: 10, width: 50, height: 20))
        XCTAssertEqual(outcome, .read(lines, RecognizedBoxes.Source(pixels: CGRect(x: 20, y: 20, width: 100, height: 40), scale: 2)))
        XCTAssertEqual(rig.reader.calls, 1)
        let image = try XCTUnwrap(rig.reader.images.first)
        XCTAssertEqual(image.width, 100, "native resolution: pixels, not points")
        XCTAssertEqual(image.height, 40)
    }

    /// The picture read is the one the file is cut from — the frame with the pointer in it when there is one —
    /// so a find and its blur land on one picture.
    func testTheReadPictureIsTheFramesShotTheFileIsCutFrom() async throws {
        let rig = makeRig()
        let withPointer = FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 50), scale: 2,
                                        image: makeImage(width: 200, height: 100, red: 255),
                                        withCursor: makeImage(width: 200, height: 100, green: 255))
        _ = await rig.session.readText(freeze(shot: .image(withPointer)), display: DisplayID(1), local: area)
        let read = try XCTUnwrap(rig.reader.images.first)
        let file = try XCTUnwrap(rig.session.crop(freeze(shot: .image(withPointer)), display: DisplayID(1), local: area))
        XCTAssertEqual(firstPixel(read).0, firstPixel(file).0)
        XCTAssertEqual(firstPixel(read).1, firstPixel(file).1)
        XCTAssertGreaterThan(firstPixel(read).1, 200, "the shot's own pixels: the green of the frame with the pointer")
        XCTAssertLessThan(firstPixel(read).0, 50, "not the red of the one without")
    }

    func testAnAreaNotOnTheFrameIsAFailureAndNothingIsAsked() async throws {
        let rig = makeRig()
        let outcome = await rig.session.readText(freeze(shot: Rig.display(1)), display: DisplayID(1),
                                                 local: CGRect(x: 500, y: 500, width: 10, height: 10))
        XCTAssertEqual(outcome, .failed)
        let other = await rig.session.readText(freeze(shot: Rig.display(1)), display: DisplayID(9),
                                               local: CGRect(x: 10, y: 10, width: 10, height: 10))
        XCTAssertEqual(other, .failed, "a display the freeze does not have")
        XCTAssertEqual(rig.reader.calls, 0)
    }

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
