import AppKit
import CoreGraphics
import HelmTestSupport
import ImageIO
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A drag of a shot that is only on the clipboard hands the pasteboard a picture it encodes when a drop asks, not
/// when the drag begins.** `ShotDrag.writer()` makes a lazy `NSPasteboardItem`: a pile of twenty such shots starts
/// as cheaply as one, and only what a target takes is ever encoded. Read here: what building the writers costs
/// (the allocator's books and the clock, against the one encode they must not do), what a drop gets (the full-size
/// PNG, and the same bytes twice), that the item outlives the shot's place on the list, and which shots a pressed
/// sheet that is still being written carries.
///
/// No seam counts the encodes (`CaptureSession.encode` is static and `PictureProvider` private), so «nothing was
/// encoded» is read from what an encode costs: a noise picture of 1600 x 1000 is 6 MB of PNG and a second or so of
/// work, and the writers are measured against that, not against a number from this Mac.
///
/// That a real drop target gets the data from a drag session is not measured: no drag can be begun from a test.
/// The pasteboard here is a private one, a stand-in for the drag's.
///
/// Total failure of the subject prints: writers that cost an encode each (eager), an item that says nothing when
/// asked, a picture of another size, a pile that carries nothing, a pressed working sheet that carries a picture.
@MainActor
final class TheDragEncodesOnlyWhatADropAsksForTests: XCTestCase {

    private var boards: [NSPasteboard] = []

    override func tearDown() {
        for board in boards { board.releaseGlobally() }
        boards = []
        super.tearDown()
    }

    /// A picture that does not compress: the cost of its PNG is real.
    private func noise(width: Int = 1600, height: Int = 1000) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var generator = SystemRandomNumberGenerator()
        for i in 0..<(context.bytesPerRow * height) { data[i] = UInt8.random(in: 0...255, using: &generator) }
        return try XCTUnwrap(context.makeImage())
    }

    private func seconds(_ work: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try work()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }

    private func drop(_ writer: NSPasteboardWriting?) throws -> Data? {
        let board = NSPasteboard.withUniqueName()
        boards.append(board)
        board.clearContents()
        XCTAssertTrue(board.writeObjects([try XCTUnwrap(writer)]))
        return board.data(forType: .png)
    }

    private func pixels(of png: Data) throws -> (Int, Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil), "not an image")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), "not a picture")
        return (image.width, image.height)
    }

    // MARK: Nothing is encoded until a drop asks

    func testTheWriterEncodesNothing() throws {
        let image = try noise()
        var encoded: Data?
        let reference = seconds { encoded = CaptureSession.encode(image, as: .png) }
        XCTAssertGreaterThan(encoded?.count ?? 0, 1_000_000, "the control: a noise picture is a big PNG")
        XCTAssertGreaterThan(reference, 0.05, "the control: encoding it takes time, or the clock below proves nothing")

        var writer: NSPasteboardWriting?
        let before = AllocatorBooks.allocatedBytes()
        let took = seconds { writer = ShotDrag.picture(image).writer() }
        let grew = AllocatorBooks.allocatedBytes() - before
        XCTAssertNotNil(writer)
        XCTAssertLessThan(grew, 256 * 1024, "the writer holds \(grew) bytes more: a PNG was encoded for it")
        XCTAssertLessThan(took, reference / 10, "the writer took \(took) s, an encode is \(reference) s")
    }

    func testAPileOfTwentyClipboardShotsStartsWithoutAnyPNG() throws {
        let image = try noise()
        let model = ShotToastModel()
        for i in 0..<ShotShelf.limit { model.add(try ShotToastRig.picture(), caption: "c\(i)", file: nil, full: image) }
        XCTAssertTrue(model.isPile)
        let newest = try XCTUnwrap(model.shots.last).id
        let before = AllocatorBooks.allocatedBytes()
        var writers: [NSPasteboardWriting] = []
        let took = seconds {
            writers = ([model.dragPayload] + model.othersDragged(with: newest).map { Optional($0) })
                .compactMap { $0?.writer() }
        }
        let grew = AllocatorBooks.allocatedBytes() - before
        XCTAssertEqual(writers.count, 20, "the pile did not leave as every shot it holds")
        XCTAssertLessThan(grew, 1024 * 1024, "twenty writers hold \(grew) bytes more: PNGs were encoded for them")
        // One encode of this picture is a second or so; twenty would be twenty.
        XCTAssertLessThan(took, 0.5, "twenty writers took \(took) s")
    }

    // MARK: What a drop gets

    func testADropGetsTheFullSizePNGAndTheSameBytesTwice() throws {
        let image = try noise(width: 1200, height: 700)
        let first = try XCTUnwrap(try drop(ShotDrag.picture(image).writer()), "a drop got nothing")
        XCTAssertEqual(try pixels(of: first).0, 1200)
        XCTAssertEqual(try pixels(of: first).1, 700)
        let item = try XCTUnwrap(ShotDrag.picture(image).writer() as? NSPasteboardItem)
        let one = try XCTUnwrap(item.data(forType: .png), "the item itself says nothing when asked")
        let two = try XCTUnwrap(item.data(forType: .png))
        XCTAssertEqual(one, two, "two asks of one item gave two different pictures")
        XCTAssertEqual(try pixels(of: one).0, 1200)
        XCTAssertEqual(one.count, first.count, "two items of one picture are not the same PNG")
    }

    func testAFileGoesByItsURLAndNotAsAPicture() throws {
        let url = URL(fileURLWithPath: "/tmp/helm-drag-not-a-file.png")
        let writer = try XCTUnwrap(ShotDrag.file(url).writer())
        XCTAssertEqual((writer as? NSURL)?.path, url.path)
    }

    /// The shot is pushed off the list while the drag is in the air: the item still gives its picture, because the
    /// provider holds the image itself and not the model's shot. (Not «says nothing»: it arrives.)
    func testTheItemOutlivesItsShotsPlaceOnTheList() throws {
        let image = try noise(width: 800, height: 600)
        let model = ShotToastModel()
        model.add(try ShotToastRig.picture(), caption: "first", file: nil, full: image)
        model.add(try ShotToastRig.picture(), caption: "second", file: nil, full: try ShotToastRig.picture())
        let firstID = try XCTUnwrap(model.shots.first).id
        let carried = model.othersDragged(with: try XCTUnwrap(model.shots.last).id)
        XCTAssertEqual(carried.count, 1)
        let item = try XCTUnwrap(carried.first?.writer() as? NSPasteboardItem)
        for i in 0..<ShotShelf.limit { model.add(try ShotToastRig.picture(), caption: "n\(i)", file: nil, full: try ShotToastRig.picture()) }
        XCTAssertNil(model.shots.first { $0.id == firstID }, "the control: the first shot was pushed out")
        model.content = nil
        let png = try XCTUnwrap(item.data(forType: .png), "the picture of a shot pushed out mid-drag did not arrive")
        XCTAssertEqual(try pixels(of: png).0, 800)
        XCTAssertEqual(try pixels(of: png).1, 600)
    }

    // MARK: A pressed sheet that is still being written

    func testAPressedWorkingSheetOverFinishedShotsCarriesTheFinishedOnes() throws {
        let model = ShotToastModel()
        for i in 0..<3 { model.add(try ShotToastRig.picture(), caption: "c\(i)", file: nil, full: try ShotToastRig.picture()) }
        let working = model.add(try ShotToastRig.picture(), caption: nil, file: nil)
        XCTAssertNil(model.dragPayload, "a shot still being written carries a picture")
        XCTAssertTrue(model.isPile)
        let others = model.othersDragged(with: working)
        XCTAssertEqual(others.count, 3, "the finished shots under the working one did not leave")
        for other in others {
            guard case .picture = other else { return XCTFail("a clipboard shot leaves as \(other)") }
            XCTAssertNotNil(other.writer())
        }
    }

    func testAPressedWorkingSheetOverNothingCarriesNothing() throws {
        let model = ShotToastModel()
        let working = model.add(try ShotToastRig.picture(), caption: nil, file: nil)
        XCTAssertNil(model.dragPayload)
        XCTAssertTrue(model.othersDragged(with: working).isEmpty)
    }
}
