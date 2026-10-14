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

/// **The two reading items against everything a person can do while the reader is still working, and against every answer it can give.**
/// The tie-breaking ones (close, a moved area, a second choice) are in `ARecognitionThatOutlivesTheEditorIsDroppedTests`; these are the
/// others: each way out of the editor (held for a Blur reading, not held for a Copy Text one, Esc never held), Crop turned on while an
/// exit is held, the deadline and the failed or cancelled answer that drop a held exit, a tool or an undo or a text field taken up in
/// the meantime, a stroke or a move still open when a held exit's answer comes, the question Esc asks, the plate of a refused pin, a
/// Copy Text reader that never answers, and the plate each (item, answer) pair puts up.
@MainActor
final class TheTextReadingMeetsEveryInputWhileItRunsTests: XCTestCase {

    private final class Reader: @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: [CheckedContinuation<CaptureSession.AreaReading, Never>] = []
        private var _cancelled = 0
        private var _copied: [[RecognizedLine]] = []
        var copyAnswer = CaptureSession.TextCopy.copied
        var calls: Int { lock.withLock { waiting.count } }
        var cancelled: Int { lock.withLock { _cancelled } }
        var copied: [[RecognizedLine]] { lock.withLock { _copied } }

        func read(_ display: DisplayID, _ area: CGRect) async -> CaptureSession.AreaReading {
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<CaptureSession.AreaReading, Never>) in
                    lock.withLock { waiting.append(continuation) }
                }
            } onCancel: { lock.withLock { _cancelled += 1 } }
        }
        func copy(_ lines: [RecognizedLine]) -> CaptureSession.TextCopy {
            lock.withLock { _copied.append(lines) }
            return copyAnswer
        }
        func answer(_ index: Int, _ reading: CaptureSession.AreaReading) {
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
        results = []
    }

    override func tearDown() {
        rigged?.overlay.close()
        rigged = nil
        AppLanguage.override = nil
        super.tearDown()
    }

    /// `exitDeadline` is how long an exit may wait for a Blur reading before it is dropped.
    private func build(pinRoom: Bool = true, exitDeadline: Duration = CaptureOverlay.defaultExitDeadline) throws
        -> (overlay: CaptureOverlay, display: DisplayID, view: OverlayView) {
        reader = Reader()
        let tools = EditorTextTools(read: { [reader] in await reader.read($0, $1) }, copy: { [reader] in reader.copy($0) })
        // The controller closes the overlay inside the very call that delivers the result (`overlayFinished`); so does this.
        let built = try OverlayRig.overlay(scale: 1, area: area, pinRoom: { pinRoom }, textTools: tools,
                                       exitDeadline: exitDeadline) { [weak self] in
            self?.results.append($0)
            self?.rigged?.overlay.close()
        }
        rigged = built
        return built
    }

    private func source() -> RecognizedBoxes.Source { RecognizedBoxes.Source(pixels: area, scale: 1) }

    /// One e-mail address in the upper part of the area, and one more lower down.
    private func finds(_ count: Int = 1) -> CaptureSession.AreaReading {
        let matches = (0..<count).map {
            PrivateMatch(kind: .emailAddress, box: CGRect(x: 0.1, y: 0.8 - Double($0) * 0.2, width: 0.5, height: 0.06))
        }
        return .read([RecognizedLine(string: "me@example.com", box: CGRect(x: 0, y: 0, width: 1, height: 1), matches: matches)], source())
    }
    private let words = CaptureSession.AreaReading.read([RecognizedLine(string: "words", box: CGRect(x: 0, y: 0, width: 1, height: 1))],
                                                        RecognizedBoxes.Source(pixels: CGRect(x: 100, y: 100, width: 400, height: 300), scale: 1))

    private func plates(_ view: OverlayView) -> [String] { view.visiblePlates.compactMap(\.string) }

    /// Waits on the clock, not in yields: a deadline is a time, and a loop of yields can pass before it.
    private func waitSeconds(_ what: String, _ limit: TimeInterval = 5, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(limit)
        while !condition(), Date() < end { await grace(0.02) }
        XCTAssertTrue(condition(), "never reached: \(what)")
    }

    private func menuItem(_ overlay: CaptureOverlay, _ title: String) -> Bool? {
        for case .reading(let name, _, _, let enabled, _) in EditorMenu.items(for: overlay.palette) where name == title { return enabled }
        return nil
    }

    // MARK: Every way out

    /// Return, ⌘C, ⌘S and Share while Blur Emails and Phone Numbers reads: nothing leaves at the press. The answer lets the exit go, once, with the
    /// finds blurred in the picture and the exit that was pressed.
    func testAnExitWhileABlurReadingRunsLeavesWhenItAnswersWithTheBlursInIt() async throws {
        for how in [EditorExit.confirm, .copy, .save, .share] {
            results = []
            let (overlay, display, _) = try build()
            OverlayRig.drawAndSelect(in: overlay, on: display)
            let before = overlay.editedLayers
            XCTAssertEqual(before.count, 1, "the subject: one rectangle drawn")
            overlay.perform(.blurPersonalText)
            await waitUntil("\(how): asked") { reader.calls == 1 }
            overlay.perform(.exit(how))
            await grace()
            XCTAssertTrue(results.isEmpty, "\(how): the exit left at the press with the reading still running: \(results)")
            reader.answer(0, finds())
            await waitUntil("\(how): the exit was delivered") { !results.isEmpty }
            await grace()
            XCTAssertEqual(results.count, 1, "\(how): the exit delivered \(results.count) results")
            guard case .edited(_, _, let layers, let exit)? = results.first else { return XCTFail("\(how): \(results)") }
            XCTAssertEqual(exit, how, "\(how): the exit delivered is not the one pressed")
            XCTAssertEqual(layers.map(\.tool), [.rectangle, .blur], "\(how): the picture delivered does not hold the blurs")
            XCTAssertEqual(Array(layers.prefix(1)), before, "\(how): what was drawn changed on the way out")
            rigged?.overlay.close(); rigged = nil
        }
    }

    /// The same exit pressed twice while the reading runs (Return and then Done) is one exit.
    func testTheSameExitPressedTwiceWhileABlurReadingRunsLeavesOnce() async throws {
        let (overlay, display, _) = try build()
        OverlayRig.drawAndSelect(in: overlay, on: display)
        overlay.perform(.blurPersonalText)
        await waitUntil("asked") { reader.calls == 1 }
        overlay.perform(.exit(.confirm))
        overlay.perform(.exit(.confirm))
        await grace()
        XCTAssertTrue(results.isEmpty, "the exit left at a press with the reading still running: \(results)")
        reader.answer(0, finds())
        await waitUntil("the exit was delivered") { !results.isEmpty }
        await grace()
        XCTAssertEqual(results.count, 1, "two presses delivered \(results.count) results")
        guard case .edited(_, _, let layers, let exit)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(exit, .confirm)
        XCTAssertEqual(layers.map(\.tool), [.rectangle, .blur])
    }

    /// A second, different exit pressed while one is held starts nothing: the first one stands and is the one delivered.
    func testADifferentExitPressedWhileOneIsHeldIsNotTheOneDelivered() async throws {
        let (overlay, display, _) = try build()
        OverlayRig.drawAndSelect(in: overlay, on: display)
        overlay.perform(.blurPersonalText)
        await waitUntil("asked") { reader.calls == 1 }
        overlay.perform(.exit(.confirm))
        overlay.perform(.exit(.save))
        overlay.perform(.exit(.pin))
        await grace()
        XCTAssertTrue(results.isEmpty, "an exit left at a press with the reading still running: \(results)")
        reader.answer(0, finds())
        await waitUntil("the exit was delivered") { !results.isEmpty }
        await grace()
        XCTAssertEqual(results.count, 1, "three presses delivered \(results.count) results")
        guard case .edited(_, _, _, let exit)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(exit, .confirm, "the exit delivered is not the first one pressed")
    }

    /// Crop turned on while an exit is held: the exit is dropped, as for a change of the area, and the answer puts the blurs in and leaves nothing.
    /// Return then takes the crop, as it does with no reading.
    func testCropTurnedOnWhileAnExitIsHeldDropsTheExitAndTheAnswerLeavesNothing() async throws {
        for how in [EditorExit.confirm, .save] {
            results = []
            let (overlay, display, view) = try build()
            OverlayRig.drawAndSelect(in: overlay, on: display)
            overlay.perform(.blurPersonalText)
            await waitUntil("\(how): asked") { reader.calls == 1 }
            overlay.perform(.exit(how))
            overlay.perform(.crop)
            XCTAssertTrue(overlay.isCropping, "\(how): the subject: Crop is on")
            reader.answer(0, finds())
            await waitUntil("\(how): the answer was acted on") { !plates(view).isEmpty }
            await grace()
            XCTAssertTrue(results.isEmpty, "\(how): the held exit left after Crop was turned on: \(results)")
            XCTAssertEqual(overlay.editedLayers.map(\.tool), [.rectangle, .blur], "\(how): the answer did not put the blurs in")
            XCTAssertTrue(overlay.isCropping, "\(how): the answer ended Crop")
            overlay.perform(.exit(.confirm))
            XCTAssertFalse(overlay.isCropping, "\(how): Return did not take the crop")
            XCTAssertTrue(results.isEmpty, "\(how): Return left instead of taking the crop: \(results)")
            rigged?.overlay.close(); rigged = nil
        }
    }

    /// An answer that finds nothing to blur lets the exit go with the picture as it was.
    func testAnExitHeldForABlurReadingThatFindsNothingLeavesWithThePictureAsItWas() async throws {
        for how in [EditorExit.confirm, .save] {
            results = []
            let (overlay, display, _) = try build()
            OverlayRig.drawAndSelect(in: overlay, on: display)
            let before = overlay.editedLayers
            overlay.perform(.blurPersonalText)
            await waitUntil("\(how): asked") { reader.calls == 1 }
            overlay.perform(.exit(how))
            await grace()
            XCTAssertTrue(results.isEmpty, "\(how): the exit left at the press with the reading still running: \(results)")
            reader.answer(0, .read([], source()))
            await waitUntil("\(how): the exit was delivered") { !results.isEmpty }
            await grace()
            XCTAssertEqual(results.count, 1, "\(how): the exit delivered \(results.count) results")
            guard case .edited(_, _, let layers, let exit)? = results.first else { return XCTFail("\(how): \(results)") }
            XCTAssertEqual(exit, how)
            XCTAssertEqual(layers, before, "\(how): the picture differs from the one on the screen")
            rigged?.overlay.close(); rigged = nil
        }
    }

    /// The control for the hold: once the Blur reading has answered, the exit leaves at once, with the blurs in the picture.
    func testAnExitAfterTheBlurReadingAnsweredLeavesAtOnce() async throws {
        let (overlay, display, view) = try build()
        OverlayRig.drawAndSelect(in: overlay, on: display)
        overlay.perform(.blurPersonalText)
        await waitUntil("asked") { reader.calls == 1 }
        reader.answer(0, finds())
        await waitUntil("the answer was acted on") { !plates(view).isEmpty }
        overlay.perform(.exit(.save))
        XCTAssertEqual(results.count, 1, "an exit after the answer was held")
        guard case .edited(_, _, let layers, let exit)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(exit, .save)
        XCTAssertEqual(layers.map(\.tool), [.rectangle, .blur])
    }

    /// Copy Text holds nothing: Return, ⌘C, ⌘S and Share leave at once, with the picture as it is, and the reading is cancelled.
    func testEveryWayOutWithACopyReadingInFlightLeavesAtOnceAndCancelsIt() async throws {
        for how in [EditorExit.confirm, .copy, .save, .share] {
            results = []
            let (overlay, display, _) = try build()
            OverlayRig.drawAndSelect(in: overlay, on: display)
            let before = overlay.editedLayers
            XCTAssertEqual(before.count, 1, "the subject: one rectangle drawn")
            overlay.perform(.copyText)
            await waitUntil("\(how): asked") { reader.calls == 1 }
            overlay.perform(.exit(how))
            XCTAssertEqual(results.count, 1, "\(how): the exit was held for a reading that copies text")
            guard case .edited(_, _, let layers, let exit)? = results.first else { return XCTFail("\(how): \(results)") }
            XCTAssertEqual(exit, how)
            XCTAssertEqual(layers, before, "\(how): the picture delivered is not the one on the screen at the press")
            XCTAssertEqual(reader.cancelled, 1, "\(how): the reading was not cancelled")
            reader.answer(0, words)
            await grace()
            XCTAssertTrue(reader.copied.isEmpty, "\(how): text was copied after the editor closed")
            XCTAssertEqual(results.count, 1, "\(how): the answer delivered something more")
            rigged?.overlay.close(); rigged = nil
        }
    }

    // MARK: The way out that never waits

    /// Esc with nothing drawn and ✕: the editor closes at once, with a Copy Text reading or a Blur reading running.
    func testEscWithNothingDrawnClosesWhileAReadingRuns() async throws {
        for ask in [EditorAction.copyText, .blurPersonalText] {
            results = []
            let (overlay, _, _) = try build()
            overlay.perform(ask)
            await waitUntil("\(ask): asked") { reader.calls == 1 }
            overlay.perform(.close)
            XCTAssertEqual(results.count, 1, "\(ask)")
            if case .cancelled? = results.first {} else { XCTFail("\(ask): \(results)") }
            reader.answer(0, ask == .copyText ? words : finds())
            await grace()
            XCTAssertTrue(reader.copied.isEmpty, "\(ask): text was copied after the editor closed")
            XCTAssertEqual(reader.cancelled, 1, "\(ask)")
            XCTAssertEqual(results.count, 1, "\(ask): the answer delivered something more")
            rigged?.overlay.close(); rigged = nil
        }
    }

    /// Esc with layers asks first, and the press that answers its question leaves at once with a Blur reading running.
    func testEscWithLayersLeavesAtItsThirdPressWhileABlurReadingRuns() async throws {
        let (overlay, display, view) = try build()
        OverlayRig.drawAndSelect(in: overlay, on: display)
        overlay.perform(.blurPersonalText)
        await waitUntil("asked") { reader.calls == 1 }
        overlay.perform(.close)   // lets go of the selected rectangle
        overlay.perform(.close)   // asks
        XCTAssertEqual(plates(view), [ScStr.confirmClose], "the subject: the question is up")
        XCTAssertTrue(results.isEmpty, "the question closed the editor")
        overlay.perform(.close)
        XCTAssertEqual(results.count, 1)
        if case .cancelled? = results.first {} else { XCTFail("\(results)") }
        reader.answer(0, finds())
        await grace()
        XCTAssertEqual(results.count, 1, "the answer delivered something more")
    }

    /// Esc after an exit that waits for the Blur reading: the editor closes without delivering the picture, and the answer that comes after delivers nothing.
    func testEscAfterAnExitThatWaitsForTheBlurReadingDeliversNothingElse() async throws {
        let (overlay, _, _) = try build()
        overlay.perform(.blurPersonalText)
        await waitUntil("asked") { reader.calls == 1 }
        overlay.perform(.exit(.save))
        XCTAssertTrue(results.isEmpty, "the exit left at the press with the reading still running: \(results)")
        overlay.perform(.close)
        XCTAssertEqual(results.count, 1, "Esc did not leave at once")
        if case .cancelled? = results.first {} else { XCTFail("Esc after a held exit delivered \(results)") }
        reader.answer(0, finds())
        await grace()
        XCTAssertEqual(results.count, 1, "the answer delivered the held exit after Esc: \(results)")
    }

    // MARK: A reading that does not come back

    /// A Blur reading that never answers does not trap the person: at the deadline the held exit is dropped, the editor stays open and the plate says
    /// the text could not be read; the same exit pressed again leaves at once, with the picture as it was.
    func testAHeldExitIsDroppedAtTheDeadlineAndTheNextPressLeavesAtOnce() async throws {
        let (overlay, display, view) = try build(exitDeadline: .milliseconds(300))
        OverlayRig.drawAndSelect(in: overlay, on: display)
        let before = overlay.editedLayers
        overlay.perform(.blurPersonalText)
        await waitUntil("asked") { reader.calls == 1 }
        overlay.perform(.exit(.save))
        XCTAssertTrue(results.isEmpty, "the exit left at the press with the reading still running: \(results)")
        await waitSeconds("the plate said the text could not be read") { plates(view) == [ScStr.textUnreadable] }
        XCTAssertTrue(results.isEmpty, "the exit was delivered at the deadline: \(results)")
        XCTAssertNotNil(overlay.view(for: display), "the editor closed at the deadline")
        XCTAssertEqual(overlay.editedLayers, before, "the picture changed at the deadline")
        overlay.perform(.exit(.save))
        XCTAssertEqual(results.count, 1, "the press after the deadline was held again")
        guard case .edited(_, _, let layers, let exit)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(exit, .save)
        XCTAssertEqual(layers, before)
        reader.answer(0, finds())
        await grace()
        XCTAssertEqual(results.count, 1, "the late answer delivered something more")
    }

    /// A reading the port itself ends with `.cancelled` (the overlay did not cancel it) gives the held exit no picture to wait for: it is dropped
    /// with the same plate, and the next press leaves at once.
    func testACancelledBlurReadingDropsTheHeldExitAndTheNextPressLeavesAtOnce() async throws {
        let (overlay, display, view) = try build()
        OverlayRig.drawAndSelect(in: overlay, on: display)
        let before = overlay.editedLayers
        overlay.perform(.blurPersonalText)
        await waitUntil("asked") { reader.calls == 1 }
        overlay.perform(.exit(.save))
        reader.answer(0, .cancelled)
        await waitUntil("the plate") { !plates(view).isEmpty }
        XCTAssertEqual(plates(view), [ScStr.textUnreadable])
        XCTAssertTrue(results.isEmpty, "the exit was delivered after a cancelled reading: \(results)")
        overlay.perform(.exit(.save))
        XCTAssertEqual(results.count, 1, "the press after the cancelled reading was held again")
        guard case .edited(_, _, let layers, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(layers, before)
    }

    /// A Blur reading that fails: the held exit is not delivered, the editor stays with the plate that says so, and the same exit pressed again leaves at once.
    func testAFailedBlurReadingDropsTheHeldExitAndTheNextPressLeavesAtOnce() async throws {
        for how in [EditorExit.confirm, .copy, .save, .share] {
            results = []
            let (overlay, display, view) = try build()
            OverlayRig.drawAndSelect(in: overlay, on: display)
            let before = overlay.editedLayers
            overlay.perform(.blurPersonalText)
            await waitUntil("\(how): asked") { reader.calls == 1 }
            overlay.perform(.exit(how))
            XCTAssertTrue(results.isEmpty, "\(how): the exit left at the press with the reading still running: \(results)")
            reader.answer(0, .failed)
            await waitUntil("\(how): the plate") { !plates(view).isEmpty }
            await grace()
            XCTAssertEqual(plates(view), [ScStr.textUnreadable], "\(how)")
            XCTAssertTrue(results.isEmpty, "\(how): the exit was delivered after a failed reading: \(results)")
            XCTAssertNotNil(overlay.view(for: display), "\(how): the editor closed")
            XCTAssertEqual(overlay.editedLayers, before, "\(how)")
            overlay.perform(.exit(how))
            XCTAssertEqual(results.count, 1, "\(how): the press after the failure was held again")
            guard case .edited(_, _, let layers, let exit)? = results.first else { return XCTFail("\(how): \(results)") }
            XCTAssertEqual(exit, how)
            XCTAssertEqual(layers, before, "\(how)")
            rigged?.overlay.close(); rigged = nil
        }
    }

    /// A Copy Text reader that never answers: both items stay off, and nothing else does — the person can still leave with the picture.
    func testACopyReaderThatNeverAnswersHoldsNothingButTheTwoItems() async throws {
        let (overlay, display, view) = try build()
        OverlayRig.drawAndSelect(in: overlay, on: display)
        overlay.perform(.copyText)
        await waitUntil("asked") { reader.calls == 1 }
        await grace(0.5)
        XCTAssertEqual(menuItem(overlay, ScStr.blurPersonalText), false, "the control: off while it runs")
        XCTAssertEqual(menuItem(overlay, ScStr.copyText), false)
        XCTAssertTrue(plates(view).isEmpty, "a silent reader is not said to be silent")
        overlay.perform(.tool(.arrow))
        overlay.mouseDown(on: display, at: CGPoint(x: 150, y: 150), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 220, y: 190), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertEqual(overlay.editedLayers.count, 2, "drawing goes on with a reading running")
        overlay.perform(.exit(.save))
        XCTAssertEqual(results.count, 1, "the person cannot leave with a reading that never answers")
        rigged?.overlay.close(); rigged = nil
    }

    // MARK: Everything else the person does meanwhile

    /// A tool, the eraser, an undo, a colour: none is a change of the area, so the answer is acted on, in the editor as it is now.
    func testAnAnswerAfterAToolOrTheEraserOrAnUndoIsActedOnInTheEditorAsItIsNow() async throws {
        let inputs: [(String, EditorAction)] = [("tool", .tool(.arrow)), ("eraser", .erase), ("select", .select),
                                                ("undo", .undo), ("redo", .redo), ("colour", .color(.red)), ("ruler", .toggleRuler)]
        for (name, action) in inputs {
            let (overlay, display, view) = try build()
            OverlayRig.drawAndSelect(in: overlay, on: display)
            overlay.perform(.blurPersonalText)
            await waitUntil("\(name): asked") { reader.calls == 1 }
            overlay.perform(action)
            let layersNow = overlay.editedLayers
            reader.answer(0, finds())
            await waitUntil("\(name): the answer was acted on") { !plates(view).isEmpty }
            XCTAssertEqual(plates(view), [ScStr.blurred(1)], name)
            XCTAssertEqual(overlay.editedLayers.count, layersNow.count + 1, "\(name): one blur went in over what the editor held after the input")
            XCTAssertEqual(overlay.editedLayers.last?.tool, .blur, name)
            overlay.perform(.undo)
            XCTAssertEqual(overlay.editedLayers.count, layersNow.count, "\(name): the blur is one undo step of its own")
            rigged?.overlay.close(); rigged = nil
        }
    }

    /// A text field open when the answer comes is not ended by it, and what is typed lands over the blur.
    func testAnAnswerWhileTextIsBeingTypedLeavesTheFieldOpen() async throws {
        let (overlay, display, view) = try build()
        overlay.perform(.blurPersonalText)
        await waitUntil("asked") { reader.calls == 1 }
        overlay.perform(.tool(.text))
        overlay.mouseDown(on: display, at: CGPoint(x: 150, y: 350), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertTrue(overlay.isTyping, "the subject: a text field is open")
        reader.answer(0, finds())
        await waitUntil("the answer was acted on") { !plates(view).isEmpty }
        XCTAssertTrue(overlay.isTyping, "the answer ended what the person was typing")
        XCTAssertEqual(overlay.editedLayers.map(\.tool), [.blur])
    }

    /// A press that is still down (a drag in the middle of a stroke) when the answer comes: the blur is not put into a half-made edit.
    /// What the plate says then is what was done.
    func testAnAnswerInTheMiddleOfAStrokeBlursNothingAndSaysSo() async throws {
        let (overlay, display, view) = try build()
        overlay.perform(.blurPersonalText)
        await waitUntil("asked") { reader.calls == 1 }
        overlay.perform(.tool(.arrow))
        overlay.mouseDown(on: display, at: CGPoint(x: 150, y: 150), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 220, y: 190), flags: [])
        reader.answer(0, finds())
        await waitUntil("the answer was acted on") { !plates(view).isEmpty }
        let said = plates(view)
        overlay.mouseUp(on: display)
        XCTAssertEqual(overlay.editedLayers.map(\.tool), [.arrow], "no blur went into a stroke that was not finished")
        XCTAssertEqual(said, [ScStr.nothingBlurred], "the plate while a stroke was open")
        // The finds were there and are not now: a second press finds them.
        overlay.perform(.blurPersonalText)
        await waitUntil("asked again") { reader.calls == 2 }
        reader.answer(1, finds())
        await waitUntil("the second answer") { overlay.editedLayers.count == 2 }
        XCTAssertEqual(overlay.editedLayers.map(\.tool), [.arrow, .blur])
    }

    /// A held exit whose answer comes in the middle of a stroke: the stroke becomes a layer, as it does at an exit, and the blurs go in after
    /// it; the picture does not leave without them.
    func testAHeldExitAnsweredInTheMiddleOfAStrokeLeavesWithTheStrokeAndTheBlurs() async throws {
        for how in [EditorExit.confirm, .save] {
            results = []
            let (overlay, display, _) = try build()
            OverlayRig.drawAndSelect(in: overlay, on: display)
            overlay.perform(.blurPersonalText)
            await waitUntil("\(how): asked") { reader.calls == 1 }
            overlay.perform(.exit(how))
            overlay.perform(.tool(.arrow))
            overlay.mouseDown(on: display, at: CGPoint(x: 150, y: 150), flags: [])
            overlay.mouseDragged(on: display, at: CGPoint(x: 220, y: 190), flags: [])
            reader.answer(0, finds())
            await waitUntil("\(how): the exit was delivered") { !results.isEmpty }
            await grace()
            XCTAssertEqual(results.count, 1, "\(how): the exit delivered \(results.count) results")
            guard case .edited(_, _, let layers, let exit)? = results.first else { return XCTFail("\(how): \(results)") }
            XCTAssertEqual(exit, how)
            XCTAssertEqual(layers.map(\.tool), [.rectangle, .arrow, .blur], "\(how): the picture left without the stroke or without the blurs")
            rigged?.overlay.close(); rigged = nil
        }
    }

    /// The same for a move of the selected layer still under the pointer: the move is closed, and the blurs go in over the layer where it now is.
    func testAHeldExitAnsweredInTheMiddleOfAMoveLeavesWithTheMoveAndTheBlurs() async throws {
        let (overlay, display, _) = try build()
        OverlayRig.drawAndSelect(in: overlay, on: display)
        let before = try XCTUnwrap(overlay.editedLayers.first)
        overlay.perform(.blurPersonalText)
        await waitUntil("asked") { reader.calls == 1 }
        overlay.perform(.exit(.save))
        overlay.mouseDown(on: display, at: CGPoint(x: 200, y: 230), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 240, y: 270), flags: [])
        XCTAssertNotEqual(overlay.editedLayers.first, before, "the subject: the layer is being moved")
        reader.answer(0, finds())
        await waitUntil("the exit was delivered") { !results.isEmpty }
        await grace()
        XCTAssertEqual(results.count, 1, "the exit delivered \(results.count) results")
        guard case .edited(_, _, let layers, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(layers.map(\.tool), [.rectangle, .blur], "the picture left without the blurs")
        XCTAssertNotEqual(layers.first, before, "the move was lost on the way out")
    }

    // MARK: The plate

    /// The Esc question is up when a Copy Text answer comes: whichever plate is shown, a second Esc must not close the editor without the question on the screen.
    func testAnAnswerDoesNotHideTheEscQuestionThatIsStillAsked() async throws {
        let (overlay, display, view) = try build()
        OverlayRig.drawAndSelect(in: overlay, on: display)
        overlay.perform(.copyText)
        await waitUntil("asked") { reader.calls == 1 }
        overlay.perform(.close)   // the first Esc lets go of the selected rectangle
        overlay.perform(.close)   // the second asks
        XCTAssertEqual(plates(view), [ScStr.confirmClose], "the subject: the question is up")
        reader.answer(0, words)
        await waitUntil("the answer was acted on") { reader.copied.count == 1 }
        await grace()
        // The rule: the Esc question outranks the answer, which waits behind it. The question is what the next Esc answers.
        XCTAssertEqual(plates(view), [ScStr.confirmClose], "the answer replaced the question that is still asked: \(plates(view))")
        overlay.perform(.close)
        let closed = results.contains { if case .cancelled = $0 { true } else { false } }
        XCTAssertTrue(closed, "the Esc that answers the question on the screen confirms it")
    }

    /// The pin was refused and its plate is up when a Blur answer comes: the count and its warning must still reach the person.
    func testTheCountReachesThePersonWhileThePinRefusalIsUp() async throws {
        let (overlay, display, view) = try build(pinRoom: false)
        OverlayRig.drawAndSelect(in: overlay, on: display)
        overlay.perform(.blurPersonalText)
        await waitUntil("asked") { reader.calls == 1 }
        overlay.perform(.exit(.pin))
        XCTAssertEqual(plates(view), [ScStr.pinLimit], "the subject: the refusal is up")
        reader.answer(0, finds())
        await waitUntil("the blur went in") { overlay.editedLayers.count == 2 }
        await grace()
        XCTAssertTrue(plates(view).contains(ScStr.blurred(1)),
                      "a blur was added and the person was never told how many or to check the rest: \(plates(view))")
    }

    /// Each (item, answer) pair has its own plate or none.
    func testEveryItemAndAnswerPutsUpItsOwnPlate() async throws {
        let empty = CaptureSession.AreaReading.read([], source())
        let cases: [(EditorAction, CaptureSession.AreaReading, TestCopy, String?)] = [
            (.copyText, empty, .noText, ScStr.noTextFound),
            (.copyText, .failed, .copied, ScStr.textUnreadable),
            (.copyText, .cancelled, .copied, nil),
            (.copyText, words, .copied, ScStr.textCopied),
            (.copyText, words, .refused, ScStr.textUnreadable),
            (.copyText, words, .noText, ScStr.noTextFound),
            (.blurPersonalText, empty, .copied, ScStr.nothingBlurred),
            (.blurPersonalText, .failed, .copied, ScStr.textUnreadable),
            (.blurPersonalText, .cancelled, .copied, nil),
            (.blurPersonalText, finds(2), .copied, ScStr.blurred(2)),
        ]
        for (action, answer, copy, plate) in cases {
            let (overlay, _, view) = try build()
            reader.copyAnswer = copy.value
            overlay.perform(action)
            await waitUntil("\(action) \(answer): asked") { reader.calls == 1 }
            reader.answer(0, answer)
            if plate != nil {
                await waitUntil("\(action) \(answer): a plate") { !plates(view).isEmpty }
            } else {
                await waitUntil("\(action) \(answer): the items came back") { menuItem(overlay, ScStr.copyText) == true }
                await grace()
            }
            XCTAssertEqual(plates(view), plate.map { [$0] } ?? [], "\(action) with \(answer)")
            XCTAssertEqual(menuItem(overlay, ScStr.copyText), true, "\(action) with \(answer): the items stay off after the answer")
            XCTAssertEqual(menuItem(overlay, ScStr.blurPersonalText), true)
            rigged?.overlay.close(); rigged = nil
        }
    }

    private enum TestCopy {
        case copied, refused, noText
        var value: CaptureSession.TextCopy {
            switch self { case .copied: .copied; case .refused: .refused; case .noText: .noText }
        }
    }

    /// Blur pressed twice over the same finds: the second finds all of them under the first's blurs and puts nothing in. What its plate says
    /// is a thing the owner should know: «Nothing was blurred» reads as a picture with nothing to blur.
    func testASecondBlurOverTheSameFindsAddsNothingAndItsPlateIsKnown() async throws {
        let (overlay, _, view) = try build()
        overlay.perform(.blurPersonalText)
        await waitUntil("asked") { reader.calls == 1 }
        reader.answer(0, finds(2))
        await waitUntil("first plate") { !plates(view).isEmpty }
        XCTAssertEqual(plates(view), [ScStr.blurred(2)])
        overlay.perform(.blurPersonalText)
        await waitUntil("asked again") { reader.calls == 2 }
        reader.answer(1, finds(2))
        await waitUntil("second plate") { !plates(view).isEmpty }
        XCTAssertEqual(overlay.editedLayers.count, 2, "nothing was added the second time")
        XCTAssertEqual(plates(view), [ScStr.nothingBlurred], "owner's call: what the second press says when the first press already did it all")
    }

    /// The count, in every language, for the counts a reading can give (up to the 500 that make a find list) and one beyond.
    func testTheCountPlateReadsRightInEveryLanguageAtEveryCount() {
        AppLanguage.each { language in
            for count in [1, 2, 5, 21, 500, 1000] {
                let plate = ScStr.blurred(count)
                let number = HelmBytes.grouped(count, language: language.rawValue)
                XCTAssertTrue(plate.contains(number), "\(language) \(count): «\(plate)» does not carry «\(number)»")
                XCTAssertFalse(plate.contains("%") || plate.contains("\\("), "\(language) \(count): «\(plate)» has a stray format")
                // The number is the one count: no other digit run on the plate.
                let digits = plate.split { !$0.isNumber }.map(String.init)
                XCTAssertEqual(digits.joined(), number.filter(\.isNumber), "\(language) \(count): «\(plate)»")
                // The independent oracle for the grouping: the system's formatter for the same language.
                let oracle = NumberFormatter()
                oracle.locale = Locale(identifier: language.rawValue)
                oracle.numberStyle = .decimal
                XCTAssertEqual(number, oracle.string(from: NSNumber(value: count)), "\(language) \(count)")
            }
        }
    }
}
