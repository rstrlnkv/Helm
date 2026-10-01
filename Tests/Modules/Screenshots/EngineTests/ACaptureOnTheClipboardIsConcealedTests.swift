import AppKit
import XCTest
@testable import Module_Screenshots_Engine

/// **A picture the capture puts on the clipboard carries the two markers
/// clipboard managers read** (`org.nspasteboard.ConcealedType`, and
/// `TransientType` beside it), and is still a picture that pastes. Read off a
/// real pasteboard of the test's own — a named one, never the general board —
/// because a fake that records what it was told would agree with any marking.
final class ACaptureOnTheClipboardIsConcealedTests: XCTestCase {

    private var board: NSPasteboard!

    override func setUp() {
        super.setUp()
        board = NSPasteboard(name: NSPasteboard.Name("helm.test.concealed.\(UUID().uuidString)"))
    }

    override func tearDown() {
        board.releaseGlobally()
        super.tearDown()
    }

    func testTheCopyIsMarkedConcealedAndTransientAndStillPastes() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let port = SystemShotPasteboard(named: board.name)
        XCTAssertEqual(port.copy(png: png), .accepted)
        let types = Set(try XCTUnwrap(board.types))
        XCTAssertEqual(board.data(forType: .png), png, "the subject: the picture is on the board")
        XCTAssertTrue(types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")),
                      "a clipboard manager would record this capture: \(types)")
        XCTAssertTrue(types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")), "\(types)")
    }

    /// A second copy replaces the first whole: no marker left over from nothing
    /// and no picture left from the last one.
    func testASecondCopyReplacesTheFirst() throws {
        let port = SystemShotPasteboard(named: board.name)
        XCTAssertEqual(port.copy(png: Data([1])), .accepted)
        XCTAssertEqual(port.copy(png: Data([2])), .accepted)
        XCTAssertEqual(board.data(forType: .png), Data([2]))
        XCTAssertEqual(board.pasteboardItems?.count, 1)
    }
}
