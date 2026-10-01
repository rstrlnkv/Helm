import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The grant can go between the preflight and the capture,** and what the
/// system hands back after that is a picture of nothing. It is a refusal:
/// counted as an ordinary failure it becomes an empty file on the Desktop that
/// reads as a capture.
final class APermissionTakenMidFreezeIsARefusalTests: XCTestCase {
    override func setUp() { super.setUp(); ScreenshotsLog.begin() }
    override func tearDown() { ScreenshotsLog.end(); super.tearDown() }

    func testADeniedFreezeIsANoPermissionRefusalAndNotAFailure() async throws {
        let rig = Rig(home: scratchDirectory("shots-midfreeze"))
        ScreenshotsLog.proveTheLogIsOn()
        rig.capture.outcome = .denied

        let result = await rig.session.begin()

        guard case .refused(let reason) = result else { return XCTFail("a denied freeze produced a freeze") }
        XCTAssertEqual(reason, .noPermission, "a grant withdrawn mid-freeze was reported as \(reason)")
        XCTAssertTrue(ScreenshotsLog.lines.contains { $0.contains("withdrawn") }, "\(ScreenshotsLog.lines)")
    }

    func testADeniedFreezeWritesNoFile() async throws {
        let rig = Rig(home: scratchDirectory("shots-midfreeze-files"))
        rig.capture.outcome = .denied

        let delivery = await rig.session.captureScreens()

        XCTAssertEqual(delivery.refusals, [.noPermission])
        XCTAssertEqual(rig.writer.written.count, 0, "an empty picture was written")
        XCTAssertEqual(rig.pasteboard.copies.count, 0)
    }

    func testAFreezeThatFailedIsNotAPermissionRefusal() async throws {
        let rig = Rig(home: scratchDirectory("shots-failed"))
        rig.capture.outcome = .failed
        guard case .refused(let reason) = await rig.session.begin() else { return XCTFail("a failed freeze came back ready") }
        XCTAssertEqual(reason, .captureFailed, "the two refusals are acted on differently")
    }
}
