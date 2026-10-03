import CoreGraphics
import Foundation
import HelmTestSupport
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Module_Screenshots_Engine

/// **A press of Copy All while an earlier one is still reading ends the earlier pass at its next picture: it writes
/// nothing, refuses nothing, logs nothing; the later pass writes once, after the earlier has let go of the queue.**
/// Read here with `CaptureSession.copyAll` against a board that counts writes, and a first picture of the group so
/// big that its encode (`reference` below, measured on this Mac by the test itself and required to be long) is the
/// window in which the second press lands. No seam lets a test hold a pass between two pictures, so the pass is
/// held by the work it really does.
///
/// The inputs: a second press mid-pass; three presses; a cancelled task mid-pass (which is what the module going
/// off does: `ScreenshotsCapture.cancel` cancels the copy task); a press after a finished pass; a press that finds
/// the first stopped by a third.
///
/// Total failure of the subject prints: two writes, the earlier pass's pictures on the board, a refusal naming the
/// encoding for a pass that was only displaced, a second pass that does not wait for the first (two alive at once).
final class TheGroupCopyRunsOnePassAtATimeTests: XCTestCase {

    private func noise(_ side: Int) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side * 5 / 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        var generator = SystemRandomNumberGenerator()
        for i in 0..<(context.bytesPerRow * context.height) { data[i] = UInt8.random(in: 0...255, using: &generator) }
        return context.makeImage()!
    }

    private func seconds(_ work: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        work()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }

    /// A picture whose encode takes about this long on this Mac, and how long it took.
    private func slowPicture(about target: Double = 0.8) -> (image: CGImage, reference: Double) {
        var side = 1600
        var image = noise(side)
        var took = seconds { _ = CaptureSession.encode(image, as: .png) }
        if took < target {
            side = min(8000, Int(Double(side) * (target / max(took, 0.01)).squareRoot() * 1.1))
            image = noise(side)
            took = seconds { _ = CaptureSession.encode(image, as: .png) }
        }
        return (image, took)
    }

    private func width(of png: Data) throws -> Int {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)).width
    }

    private func small(_ widths: [Int]) -> [ShotSource] { widths.map { .picture(makeImage(width: $0, height: 6)) } }

    private func rig(_ name: String) -> Rig { Rig(home: scratchDirectory(name)) }

    func testASecondPressMidPassEndsTheFirstWithNothingAndWritesOnceAfterIt() async throws {
        ScreenshotsLog.begin()
        defer { ScreenshotsLog.end() }
        ScreenshotsLog.proveTheLogIsOn()
        let (big, reference) = slowPicture()
        XCTAssertGreaterThan(reference, 0.4, "the control: the first picture's encode is long enough to land a press in")
        let rig = rig("pass-second")
        let session = rig.session
        let group: [ShotSource] = [.picture(big), .picture(big), .picture(big)] + small([11, 12])
        let first = Task { await session.copyAll(group) }
        try await Task.sleep(for: .milliseconds(120))
        var second = Delivery()
        let later = small([21, 22])
        let waited = await timedAsync({ second = await session.copyAll(later) })
        let ended = await first.value

        XCTAssertFalse(ended.copied, "the displaced pass wrote")
        XCTAssertTrue(ended.refusals.isEmpty, "a displaced pass said \(ended.refusals): it was not a failure of the encoding")
        XCTAssertTrue(second.copied)
        XCTAssertTrue(second.refusals.isEmpty)
        XCTAssertEqual(rig.pasteboard.lists.count, 1, "two writes for two presses")
        XCTAssertEqual(try XCTUnwrap(rig.pasteboard.lists.first).map(width(of:)), [21, 22], "the board does not hold the later press")
        XCTAssertTrue(rig.pasteboard.copies.isEmpty)
        XCTAssertFalse(ScreenshotsLog.lines.contains { $0.contains("could not be read or encoded") },
                       "a displaced pass logged a failure: \(ScreenshotsLog.lines)")
        // The second pass waited behind the first's picture in hand: two passes are not alive at once. (A first
        // picture's encode started 0.12 s before the second press; a margin of the sleep's own slack on top.)
        XCTAssertGreaterThan(waited, reference - 0.12 - 0.35, "the second pass ran beside the first (\(waited) s of \(reference) s)")
        // ... and no longer than the picture in hand: the first pass had three big ones and stopped at the next
        // picture's check, not at the end.
        XCTAssertLessThan(waited, reference * 1.9, "the displaced pass went on past its next picture (\(waited) s of \(reference) s)")
    }

    func testThreePressesAreOneWriteAndItIsTheLast() async throws {
        let (big, reference) = slowPicture()
        XCTAssertGreaterThan(reference, 0.4)
        let rig = rig("pass-three")
        let session = rig.session
        let tailA = [ShotSource.picture(big)] + small([11]), tailB = [ShotSource.picture(big)] + small([12])
        let a = Task { await session.copyAll(tailA) }
        try await Task.sleep(for: .milliseconds(80))
        let b = Task { await session.copyAll(tailB) }
        try await Task.sleep(for: .milliseconds(80))
        let c = await session.copyAll(small([31, 32, 33]))
        let (ra, rb) = (await a.value, await b.value)
        XCTAssertTrue(c.copied)
        for (name, delivery) in [("first", ra), ("second", rb)] {
            XCTAssertFalse(delivery.copied, "the \(name) press wrote")
            XCTAssertTrue(delivery.refusals.isEmpty, "the \(name) press: \(delivery.refusals)")
        }
        XCTAssertEqual(rig.pasteboard.lists.count, 1, "three presses were \(rig.pasteboard.lists.count) writes")
        XCTAssertEqual(try XCTUnwrap(rig.pasteboard.lists.first).map(width(of:)), [31, 32, 33])
    }

    func testACancelledTaskMidPassWritesNothingAndRefusesNothing() async throws {
        let (big, reference) = slowPicture()
        XCTAssertGreaterThan(reference, 0.4)
        let rig = rig("pass-cancel")
        let session = rig.session
        let group = [ShotSource.picture(big)] + small([11, 12, 13])
        let pass = Task { await session.copyAll(group) }
        try await Task.sleep(for: .milliseconds(120))
        pass.cancel()
        let ended = await pass.value
        XCTAssertFalse(ended.copied)
        XCTAssertTrue(ended.refusals.isEmpty, "a cancelled pass said \(ended.refusals)")
        XCTAssertTrue(rig.pasteboard.lists.isEmpty, "a cancelled pass reached the board")
        // And the session is not left stopped: the next press writes.
        let next = await session.copyAll(small([41]))
        XCTAssertTrue(next.copied, "a press after a cancelled pass was refused or stopped")
        XCTAssertEqual(rig.pasteboard.lists.count, 1)
    }

    func testAPressAfterAFinishedPassIsAWriteOfItsOwn() async throws {
        let rig = rig("pass-after")
        let one = await rig.session.copyAll(small([11, 12]))
        let two = await rig.session.copyAll(small([21]))
        XCTAssertTrue(one.copied)
        XCTAssertTrue(two.copied)
        XCTAssertEqual(rig.pasteboard.lists.count, 2, "a finished pass was taken for a pass to stop")
        XCTAssertEqual(try rig.pasteboard.lists.map { try $0.map(width(of:)) }, [[11, 12], [21]])
    }

    /// A pass that is stopped before the pool has started it (queued behind another) is ended at its first picture.
    func testAPassStoppedWhileQueuedNeverEncodesAPicture() async throws {
        let (big, reference) = slowPicture()
        XCTAssertGreaterThan(reference, 0.4)
        let rig = rig("pass-queued")
        let session = rig.session
        let holder = Task { await session.copyAll([.picture(big)]) }
        try await Task.sleep(for: .milliseconds(100))
        let queued = Task { await session.copyAll([.picture(big), .picture(big)]) }
        try await Task.sleep(for: .milliseconds(100))
        queued.cancel()
        let started = DispatchTime.now().uptimeNanoseconds
        let ended = await queued.value
        _ = await holder.value
        let total = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
        XCTAssertFalse(ended.copied)
        XCTAssertTrue(ended.refusals.isEmpty)
        XCTAssertLessThan(total, reference * 1.5, "a pass cancelled in the queue still encoded (\(total) s)")
        XCTAssertLessThanOrEqual(rig.pasteboard.lists.count, 1)
    }
}

private func timedAsync(_ work: () async -> Void) async -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    await work()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
}
