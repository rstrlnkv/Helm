import AppKit
import CoreGraphics
import Foundation
import HelmTestSupport
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Module_Screenshots_Engine

private func png(width: Int, height: Int = 6) throws -> Data {
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, makeImage(width: width, height: height, red: UInt8(width % 250)), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
}

private func file(_ folder: URL, width: Int) throws -> URL {
    let url = folder.appendingPathComponent("shot-\(width).png")
    try png(width: width).write(to: url)
    return url
}

/// **A group goes to the clipboard in one write: all the shots that are found, or none.** A group copied picture by picture is as many
/// writes, each taking the board from the one before, and only the last would be there to paste. Read here: the
/// session's `copyAll` against a board that counts writes (`FakePasteboard.lists`, one entry a write), and the real
/// port against a pasteboard of the test's own, whose items are counted and whose change count says how many
/// writes it was.
///
/// The inputs nobody fed: a file that is gone, that is no picture, that is another picture since; an empty list; a board
/// that refuses; a task that was cancelled before the write.
///
/// Total failure of the subject prints: a write a picture, a board that holds the first nine of twenty because the tenth
/// file was unreadable, a refusal that says the clipboard when it was the file, an empty group that reports a copy.
///
/// Mutant, red here: `copyAll` writes each PNG separately.
final class TheGroupIsCopiedInOneWriteTests: XCTestCase {

    private func rig(_ name: String) -> Rig { Rig(home: scratchDirectory(name)) }

    // MARK: What is written and what is told

    func testAFileThatIsGoneIsLeftOutNamedAndTheOthersAreOnTheBoardInOneWrite() async throws {
        let rig = rig("group-gone")
        let folder = scratchDirectory("group-gone-files")
        let gone = try file(folder, width: 12)
        try FileManager.default.removeItem(at: gone)
        let kept = try file(folder, width: 14)
        let delivery = await rig.session.copyAll([.picture(makeImage(width: 11, height: 6)), .file(gone), .file(kept),
                                                   .picture(makeImage(width: 13, height: 6))])
        XCTAssertEqual(delivery.refusals, [.filesGone([1])], "the person is told which picture was not there")
        XCTAssertTrue(delivery.copied)
        XCTAssertEqual(rig.pasteboard.lists.count, 1)
        XCTAssertEqual(try XCTUnwrap(rig.pasteboard.lists.first).map(width(of:)), [11, 14, 13], "not the three that were found, in the list's order")
        XCTAssertTrue(rig.pasteboard.copies.isEmpty)
    }

    func testAFileThatIsNoPictureAnyMoreRefusesTheWholeGroupToo() async throws {
        let rig = rig("group-garbage")
        let folder = scratchDirectory("group-garbage-files")
        let changed = try file(folder, width: 12)
        try Data("not a picture, not any more".utf8).write(to: changed)
        let late = try file(folder, width: 19)
        try Data().write(to: late)
        for bad in [changed, late] {
            let delivery = await rig.session.copyAll([.file(bad), .picture(makeImage(width: 11, height: 6))])
            XCTAssertEqual(delivery.refusals, [.encoding], "\(bad.lastPathComponent)")
            XCTAssertFalse(delivery.copied)
        }
        XCTAssertTrue(rig.pasteboard.lists.isEmpty)
    }

    /// A file that is another picture since is copied as it is now: the copy asks the file, as the single shot's Copy does.
    func testAFileThatIsAnotherPictureSinceIsCopiedAsItIsNow() async throws {
        let rig = rig("group-changed")
        let folder = scratchDirectory("group-changed-files")
        let url = try file(folder, width: 12)
        try png(width: 31).write(to: url)
        let delivery = await rig.session.copyAll([.file(url)])
        XCTAssertTrue(delivery.copied)
        XCTAssertEqual(try XCTUnwrap(rig.pasteboard.lists.first).map(width(of:)), [31])
    }

    func testAnEmptyGroupIsRefusedAndWritesNothing() async throws {
        let rig = rig("group-empty")
        let delivery = await rig.session.copyAll([])
        XCTAssertFalse(delivery.copied, "an empty group was reported as copied")
        XCTAssertFalse(delivery.refusals.isEmpty, "an empty group was neither copied nor refused")
        XCTAssertTrue(rig.pasteboard.lists.isEmpty)
        XCTAssertTrue(rig.pasteboard.copies.isEmpty)
    }

    func testABoardThatRefusesIsToldAsTheBoardAndNothingIsHalfWritten() async throws {
        let rig = rig("group-refused")
        rig.pasteboard.accepts = false
        let delivery = await rig.session.copyAll((0..<3).map { .picture(makeImage(width: 10 + $0, height: 6)) })
        XCTAssertEqual(delivery.refusals, [.pasteboard])
        XCTAssertFalse(delivery.copied)
        XCTAssertTrue(rig.pasteboard.lists.isEmpty)
        XCTAssertTrue(rig.pasteboard.copies.isEmpty, "a refused group fell back to a write a picture")
        rig.pasteboard.accepts = true
        let again = await rig.session.copyAll([.picture(makeImage(width: 10, height: 6))])
        XCTAssertTrue(again.copied, "the control: the same group is copied by a board that takes it")
    }

    func testAGroupThatWasCancelledBeforeTheWriteReachesNoBoard() async throws {
        let rig = rig("group-cancelled")
        let control = await rig.session.copyAll([.picture(makeImage(width: 10, height: 6))])
        XCTAssertTrue(control.copied, "the control: the same call, not cancelled, writes")
        XCTAssertEqual(rig.pasteboard.lists.count, 1)
        let session = rig.session
        let delivery = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await session.copyAll((0..<3).map { .picture(makeImage(width: 10 + $0, height: 6)) })
        }.value
        XCTAssertFalse(delivery.copied)
        XCTAssertEqual(rig.pasteboard.lists.count, 1, "a cancelled group reached the board")
    }

    // MARK: The real port

    private var board: NSPasteboard!

    override func setUp() {
        super.setUp()
        board = NSPasteboard(name: NSPasteboard.Name("helm.test.group.\(UUID().uuidString)"))
    }

    override func tearDown() {
        board.releaseGlobally()
        super.tearDown()
    }

    private let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    func testTheRealBoardHoldsOneItemAPictureEachMarkedAndInTheListsOrder() throws {
        let port = SystemShotPasteboard(named: board.name)
        let pngs = try (0..<5).map { try png(width: 20 + $0) }
        XCTAssertEqual(port.copy(pngs: pngs), .accepted)
        let items = try XCTUnwrap(board.pasteboardItems)
        XCTAssertEqual(items.count, 5, "a picture is an item")
        XCTAssertEqual(items.map { $0.data(forType: .png) }, pngs.map { Optional($0) })
        for item in items {
            XCTAssertTrue(item.types.contains(concealed), "a clipboard manager would record this item: \(item.types)")
            XCTAssertTrue(item.types.contains(transient))
        }
    }

    func testTwentyItemsAreTheSameNumberOfWritesAsOne() throws {
        let port = SystemShotPasteboard(named: board.name)
        let one = try png(width: 20)
        let before = board.changeCount
        XCTAssertEqual(port.copy(pngs: [one]), .accepted)
        let forOne = board.changeCount - before
        let mid = board.changeCount
        XCTAssertEqual(port.copy(pngs: Array(repeating: one, count: 20)), .accepted)
        XCTAssertEqual(board.changeCount - mid, forOne, "twenty pictures took more writes than one")
        XCTAssertEqual(board.pasteboardItems?.count, 20)
    }

    func testAListReplacesWhatWasThereWholeAndAnEmptyOneLeavesItAlone() throws {
        let port = SystemShotPasteboard(named: board.name)
        XCTAssertEqual(port.copy(pngs: [try png(width: 20), try png(width: 21), try png(width: 22)]), .accepted)
        XCTAssertEqual(port.copy(pngs: [try png(width: 30)]), .accepted)
        XCTAssertEqual(board.pasteboardItems?.count, 1, "the second group left items of the first")
        XCTAssertEqual(port.copy(pngs: [try png(width: 40), try png(width: 41)]), .accepted)
        let kept = try XCTUnwrap(board.pasteboardItems).compactMap { $0.data(forType: .png) }
        XCTAssertEqual(try kept.map(width(of:)), [40, 41])
        let count = board.changeCount
        XCTAssertEqual(port.copy(pngs: []), .refused)
        XCTAssertEqual(board.changeCount, count, "an empty list touched the board")
        XCTAssertEqual(board.pasteboardItems?.count, 2, "an empty list cleared what was there")
        XCTAssertEqual(port.copy(png: try png(width: 50)), .accepted)
        XCTAssertEqual(board.pasteboardItems?.count, 1, "a single copy after a group left the group's items")
    }
}
