import AppKit
import CoreGraphics
import HelmTestSupport
import ImageIO
import XCTest
@testable import Module_Screenshots_UI

/// **A thumbnail dragged out carries what the shot is: the file when one was written, the full picture as a PNG when
/// the shot is only on the clipboard, and nothing while the result is not in.** The thumbnail is a `ShotThumbnail.longestEdge`-pixel copy; a
/// drag that carried it would drop a reduced picture into somebody's document.
///
/// What is asked is what the pasteboard receives, from the drag's own writer, and what the view does with the mouse
/// without a window: the payload is asked when a drag begins and not before, once per press, and a drag is no click.
///
/// Total failure of the subject prints: a drag that carries the thumbnail's pixels (the width read back is `ShotThumbnail.longestEdge`), one
/// that carries a file nobody wrote, one that starts while the shot is still being written.
@MainActor
final class TheShotLeavesByDragAsWhatItSavedTests: XCTestCase {

    private var toast: ShotToast?
    private let clock = StepClock()

    override func tearDown() {
        toast?.dismiss()
        toast = nil
        clock.finish()
        super.tearDown()
    }

    private func made() -> ShotToast {
        let made = ShotToastRig.toast(clock)
        toast = made
        return made
    }

    private func pasteboard() -> NSPasteboard {
        let board = NSPasteboard.withUniqueName()
        addTeardownBlock { board.releaseGlobally() }
        return board
    }

    // MARK: What is carried

    func testASavedShotCarriesItsFileAndNoPicture() throws {
        let toast = made()
        let file = try ShotToastRig.realFile(self, "a-shot.png")
        toast.showDone(try ShotToastRig.picture(), caption: "Saved", file: file)
        guard case .file(let carried)? = toast.model.dragPayload else { return XCTFail("a saved shot does not drag as its file: \(String(describing: toast.model.dragPayload))") }
        XCTAssertEqual(carried, file)
        let board = pasteboard()
        board.clearContents()
        XCTAssertTrue(board.writeObjects([try XCTUnwrap(toast.model.dragPayload?.writer())]))
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(urls, [file], "the pasteboard does not hold the file's URL")
        XCTAssertNil(board.data(forType: .png), "a saved shot also put pixels on the pasteboard")
    }

    /// 1200 × 700 is above `ShotThumbnail.longestEdge`: the pixels that are read back are told apart from the reduced copy.
    func testAShotOnlyOnTheClipboardCarriesItsFullPictureAsAPNG() throws {
        let toast = made()
        toast.showDone(try ShotToastRig.picture(width: 1200, height: 700), caption: "Copied", file: nil)
        guard case .picture(let carried)? = toast.model.dragPayload else { return XCTFail("a clipboard-only shot has no picture to drag") }
        XCTAssertEqual(carried.width, 1200, "the drag carries the thumbnail's reduced copy")
        let board = pasteboard()
        board.clearContents()
        XCTAssertTrue(board.writeObjects([try XCTUnwrap(toast.model.dragPayload?.writer())]))
        let data = try XCTUnwrap(board.data(forType: .png), "no PNG reached the pasteboard")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.png")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1200)
        XCTAssertEqual(image.height, 700)
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        XCTAssertTrue(urls.isEmpty, "a clipboard-only shot dragged as a file nobody wrote: \(urls)")
    }

    /// While the write is in flight neither a file nor a full picture exists, and the working thumbnail may not leave.
    func testNothingLeavesWhileTheResultIsNotIn() throws {
        let toast = made()
        toast.showWorking(try ShotToastRig.picture())
        XCTAssertNil(toast.model.dragPayload, "a shot that is still being written can be dragged")
        toast.showDone(try ShotToastRig.picture(), caption: "Saved", file: try ShotToastRig.realFile(self, "b.png"))
        XCTAssertNotNil(toast.model.dragPayload, "the control: the same toast drags once the result is in")
    }

    /// The payload is read at the drag, so a file that arrives after the thumbnail was shown is what leaves.
    func testTheFileThatArrivesAfterTheThumbnailIsTheOneThatLeaves() throws {
        let toast = made()
        let image = try ShotToastRig.picture(width: 1200, height: 700)
        toast.showWorking(image)
        let asked = { toast.model.dragPayload }
        XCTAssertNil(asked())
        let file = try ShotToastRig.realFile(self, "c.png")
        toast.showDone(image, caption: "Saved", file: file)
        guard case .file(let carried)? = asked() else { return XCTFail("the file was not carried") }
        XCTAssertEqual(carried, file)
    }

    func testARefusalAndAnEmptyToastCarryNothing() throws {
        let toast = made()
        XCTAssertNil(toast.model.dragPayload, "a toast with nothing in it carries something")
        toast.showRefusal(.noPermission)
        XCTAssertNil(toast.model.dragPayload, "a refusal can be dragged")
        toast.showDone(try ShotToastRig.picture(), caption: "Saved", file: try ShotToastRig.realFile(self, "d.png"))
        toast.dismiss()
        XCTAssertNil(toast.model.dragPayload, "a dismissed toast still carries its shot")
    }

    /// The shot after it: the next shot's payload is its own, and the previous clipboard picture is not held over.
    func testTheNextShotDoesNotCarryTheLastShotsPicture() throws {
        let toast = made()
        toast.showDone(try ShotToastRig.picture(width: 1200, height: 700), caption: "Copied", file: nil)
        let file = try ShotToastRig.realFile(self, "e.png")
        toast.showDone(try ShotToastRig.picture(width: 800, height: 600), caption: "Saved", file: file)
        guard case .file? = toast.model.dragPayload else { return XCTFail("the second shot did not drag as its file") }
        toast.showWorking(try ShotToastRig.picture())
        XCTAssertNil(toast.model.dragPayload, "the working thumbnail of the third shot dragged the second's picture")
    }

    /// A file that is no longer there is not a thing to hand to somebody's document. Expected: it does not leave as a
    /// dead path (a saved shot holds no picture to fall back on, so nothing leaves).
    func testAFileThatWentBeforeTheDragIsNotCarriedAsAPath() throws {
        let toast = made()
        let folder = scratchDirectory("drag-gone")
        let file = try ShotToastRig.writePNG(try ShotToastRig.picture(), in: folder)
        toast.showDone(try ShotToastRig.picture(), caption: "Saved", file: file)
        XCTAssertNotNil(toast.model.dragPayload, "the control: while the file is there it leaves")
        try FileManager.default.removeItem(at: file)
        if case .file(let url)? = toast.model.dragPayload {
            XCTFail("the file was deleted and the thumbnail still drags its path: \(url.path)")
        }
    }

    // MARK: What the view does with the mouse

    private func event(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                         context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private func dragView() -> (ShotDragView, asked: () -> Int, clicks: () -> Int) {
        let view = ShotDragView(frame: NSRect(x: 0, y: 0, width: 200, height: 126))
        final class Counts { var asked = 0, clicks = 0 }
        let counts = Counts()
        view.payload = { counts.asked += 1; return nil }
        view.onClick = { counts.clicks += 1 }
        return (view, { counts.asked }, { counts.clicks })
    }

    /// A press and release in place is a click; a press that moves under the slop is still one; the payload (which
    /// would encode a PNG) is not asked for either.
    func testAClickAsksForNoPayloadAndOpensOnce() throws {
        let (view, asked, clicks) = dragView()
        view.mouseDown(with: try event(.leftMouseDown, at: NSPoint(x: 50, y: 50)))
        view.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: 52, y: 51)))
        view.mouseUp(with: try event(.leftMouseUp, at: NSPoint(x: 52, y: 51)))
        XCTAssertEqual(clicks(), 1, "a press and release did not open the shot")
        XCTAssertEqual(asked(), 0, "a click encoded the shot for a drag")
    }

    /// Past the slop the payload is asked once however many more drag events come, and the release after it is not a
    /// click: the shot is not opened by the end of a drag. With a payload that is nil the drag does not begin.
    func testADragAsksOnceAndItsReleaseIsNoClick() throws {
        let (view, asked, clicks) = dragView()
        view.mouseDown(with: try event(.leftMouseDown, at: NSPoint(x: 50, y: 50)))
        for x in stride(from: 60.0, through: 100.0, by: 10) {
            view.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: x, y: 50)))
        }
        view.mouseUp(with: try event(.leftMouseUp, at: NSPoint(x: 100, y: 50)))
        XCTAssertEqual(asked(), 1, "the drag asked for its payload \(asked()) times")
        XCTAssertEqual(clicks(), 0, "the end of a drag opened the shot")
    }

    /// A release with no press (the press landed elsewhere), and a drag with no press, do nothing.
    func testAReleaseAndADragWithNoPressDoNothing() throws {
        let (view, asked, clicks) = dragView()
        view.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: 150, y: 50)))
        view.mouseUp(with: try event(.leftMouseUp, at: NSPoint(x: 150, y: 50)))
        XCTAssertEqual(clicks(), 0, "a release with no press opened the shot")
        XCTAssertEqual(asked(), 0)
    }

    /// The panel is never key and never moves with a drag of its picture: the two overrides that make the first
    /// click count and keep the window still.
    func testTheViewTakesTheFirstClickAndDoesNotMoveTheWindow() {
        let view = ShotDragView()
        XCTAssertTrue(view.acceptsFirstMouse(for: nil), "the first click on the never-key panel only made it key")
        XCTAssertFalse(view.mouseDownCanMoveWindow, "a drag of the picture moved the panel")
    }

    /// One tracking area, always active, in the visible rect: a second pass of `updateTrackingAreas` must not stack
    /// another (that two areas deliver every enter twice is not measured), and `.activeAlways` is what the panel's not being key asks for (not measured against a real panel).
    func testTheTrackingAreaIsOneAndAlwaysActiveAfterEveryUpdate() {
        let view = ShotDragView(frame: NSRect(x: 0, y: 0, width: 200, height: 126))
        for _ in 0..<3 { view.updateTrackingAreas() }
        XCTAssertEqual(view.trackingAreas.count, 1, "the tracking areas stack: \(view.trackingAreas.count)")
        let options = view.trackingAreas.first?.options ?? []
        XCTAssertTrue(options.contains(.mouseEnteredAndExited))
        XCTAssertTrue(options.contains(.activeAlways), "hover would be asked of a panel that is never key")
        XCTAssertTrue(options.contains(.inVisibleRect))
    }
}
