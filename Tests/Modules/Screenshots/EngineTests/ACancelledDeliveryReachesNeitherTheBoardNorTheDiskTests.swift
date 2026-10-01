import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A delivery whose task is cancelled reaches neither the clipboard nor the disk,
/// whichever wait the cancellation lands in.** The controller cancels the delivery
/// when the module is switched off; the session is the last place that can still
/// refuse, and it asks before each act. Each case cancels the task at a different
/// point and has a control that proves the act would otherwise have happened.
final class ACancelledDeliveryReachesNeitherTheBoardNorTheDiskTests: XCTestCase {

    /// A clipboard that takes the picture and then cancels the task that is
    /// delivering it: the cancellation lands after the copy and before the file.
    private final class CancellingBoard: ShotPasteboard, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var copies: Int { lock.withLock { count } }
        func copy(png: Data) -> PasteOutcome {
            lock.withLock { count += 1 }
            withUnsafeCurrentTask { $0?.cancel() }
            return .accepted
        }
    }

    /// Cancelled before the delivery began: nothing is copied and nothing is written.
    /// The control is the same delivery, not cancelled, which does both.
    func testADeliveryCancelledBeforeItBeganCopiesAndWritesNothing() async throws {
        let control = Rig(home: scratchDirectory("shots-cancel-control"))
        _ = await control.session.deliver(makeImage(width: 8, height: 8), saves: true, copies: true)
        XCTAssertEqual(control.pasteboard.copies.count, 1, "the control did not copy, so the absence below says nothing")
        XCTAssertEqual(control.writer.written.count, 1, "the control wrote no file, so the absence below says nothing")

        let rig = Rig(home: scratchDirectory("shots-cancel-before"))
        let delivery = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await rig.session.deliver(makeImage(width: 8, height: 8), saves: true, copies: true)
        }.value
        XCTAssertTrue(rig.pasteboard.copies.isEmpty, "a cancelled delivery took the clipboard")
        XCTAssertTrue(rig.writer.written.isEmpty, "a cancelled delivery wrote a file")
        XCTAssertTrue(delivery.files.isEmpty && !delivery.copied, "a cancelled delivery reported an act: \(delivery)")
    }

    /// Cancelled between the copy and the file — the wait for the folder: the copy
    /// stands, the file is not written.
    func testADeliveryCancelledAfterTheCopyWritesNoFile() async throws {
        let home = scratchDirectory("shots-cancel-after-copy")
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        let board = CancellingBoard(), writer = FakeWriter()
        let session = CaptureSession(
            capture: FakeCapture(), writer: writer, pasteboard: board, preferences: FakePreferences(),
            shutter: FakeShutter(), settings: { .defaults }, naming: { .english },
            now: { Date(timeIntervalSince1970: 1_790_000_000) },
            locations: ScreenshotsLocations(home: home, desktop: desktop))
        _ = await Task {
            await session.deliver(makeImage(width: 8, height: 8), saves: true, copies: true)
        }.value
        XCTAssertEqual(board.copies, 1, "the copy did not happen, so the cancellation never landed where this case says")
        XCTAssertTrue(writer.written.isEmpty, "a delivery cancelled after the copy still wrote the file")
    }
}
