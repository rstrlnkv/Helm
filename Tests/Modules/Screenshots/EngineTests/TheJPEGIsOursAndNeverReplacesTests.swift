import CoreGraphics
import Foundation
import HelmTestSupport
import ImageIO
import XCTest
@testable import Module_Screenshots_Engine

/// **A JPEG is encoded and written by Helm, with the real writer, and it takes
/// the same never-replace ladder a PNG does.** ScreenCaptureKit can write the
/// file itself when asked for a type, and a file it writes is a file no ladder
/// saw. The clipboard gets a PNG whatever the file is.
final class TheJPEGIsOursAndNeverReplacesTests: XCTestCase {

    private let fixed = Date(timeIntervalSince1970: 1_790_000_000)

    private func liveSession(home: URL, settings: ScreenshotsSettings) -> (CaptureSession, FakeCapture, FakePasteboard) {
        let capture = FakeCapture(), board = FakePasteboard()
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        let fixed = fixed
        let session = CaptureSession(capture: capture, writer: FileShotWriter(), trash: FakeTrash(folder: FakeWriter()), pasteboard: board,
                                     preferences: FakePreferences(), shutter: FakeShutter(), textReader: FakeTextReader(),
                                     settings: { settings }, naming: { .english }, now: { fixed },
                                     locations: ScreenshotsLocations(home: home, desktop: desktop))
        return (session, capture, board)
    }

    private func type(of data: Data) -> String? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    /// Two captures in one second, and a file already there: three names, none replaced.
    func testAJPEGNeverReplacesAFile() async throws {
        let home = scratchDirectory("shots-jpeg-ladder")
        let (session, capture, _) = liveSession(home: home, settings: ScreenshotsSettings(saveTarget: .desktop, format: .jpeg))
        capture.outcome = .frozen(Freeze(displays: [Rig.display(1)], windows: []))
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let base = ShotNames.base(date: fixed, naming: .english)
        let precious = Data("somebody's own file".utf8)
        let taken = desktop.appendingPathComponent(base + ".jpg")
        try precious.write(to: taken)

        let first = await session.captureScreens()
        let second = await session.captureScreens()

        XCTAssertEqual(try Data(contentsOf: taken), precious, "an existing .jpg was replaced")
        XCTAssertEqual(first.files.map(\.lastPathComponent), [base + " (1).jpg"])
        XCTAssertEqual(second.files.map(\.lastPathComponent), [base + " (2).jpg"])
        for file in first.files + second.files { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path)) }
    }

    /// A PNG at the same name is a different file: the ladder is per extension.
    func testAPNGAtTheSameNameDoesNotTakeAJPEGsName() async throws {
        let home = scratchDirectory("shots-jpeg-png")
        let (session, capture, _) = liveSession(home: home, settings: ScreenshotsSettings(saveTarget: .desktop, format: .jpeg))
        capture.outcome = .frozen(Freeze(displays: [Rig.display(1)], windows: []))
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let base = ShotNames.base(date: fixed, naming: .english)
        try Data("png".utf8).write(to: desktop.appendingPathComponent(base + ".png"))

        let delivery = await session.captureScreens()

        XCTAssertEqual(delivery.files.map(\.lastPathComponent), [base + ".jpg"])
    }

    /// The clipboard is a PNG whatever the file is, and both come from one capture.
    func testTheClipboardIsAlwaysAPNG() async throws {
        let home = scratchDirectory("shots-jpeg-board")
        let (session, _, board) = liveSession(home: home, settings: ScreenshotsSettings(saveTarget: .desktop, format: .jpeg))

        let delivery = await session.deliver(makeImage(width: 16, height: 16, red: 255), saves: true, copies: true)

        let copied = try XCTUnwrap(board.copies.first)
        XCTAssertEqual(type(of: copied), "public.png", "the clipboard took something other than a PNG")
        let file = try XCTUnwrap(delivery.files.first)
        XCTAssertEqual(type(of: try Data(contentsOf: file)), "public.jpeg")

        // And the clipboard target under JPEG is a PNG too, with no file at all.
        let (onlyBoard, _, board2) = liveSession(home: home, settings: ScreenshotsSettings(saveTarget: .clipboard, format: .jpeg))
        let second = await onlyBoard.deliver(makeImage(width: 16, height: 16), saves: true, copies: true)
        XCTAssertEqual(second.files, [])
        XCTAssertEqual(type(of: try XCTUnwrap(board2.copies.first)), "public.png")
    }

    func testAPNGSettingStillWritesAPNG() async throws {
        let home = scratchDirectory("shots-png-still")
        let (session, capture, _) = liveSession(home: home, settings: ScreenshotsSettings(saveTarget: .desktop))
        capture.outcome = .frozen(Freeze(displays: [Rig.display(1)], windows: []))
        let delivery = await session.captureScreens()
        let file = try XCTUnwrap(delivery.files.first)
        XCTAssertEqual(file.pathExtension, "png")
        XCTAssertEqual(type(of: try Data(contentsOf: file)), "public.png")
    }
}
