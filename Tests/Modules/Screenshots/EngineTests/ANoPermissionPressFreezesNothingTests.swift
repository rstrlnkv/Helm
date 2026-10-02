import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A press without the grant freezes nothing.** Without Screen Recording a
/// freeze returns a desktop with no windows in it, and an overlay raised over
/// that looks like the feature working. The refusal is the one thing the log
/// says about it; a press that *is* granted says nothing at all.
final class ANoPermissionPressFreezesNothingTests: XCTestCase {
    override func setUp() { super.setUp(); ScreenshotsLog.begin() }
    override func tearDown() { ScreenshotsLog.end(); super.tearDown() }

    func testADeniedPressAsksForTheGrantAndFreezesNothing() async throws {
        let rig = Rig(home: scratchDirectory("shots-denied"))
        ScreenshotsLog.proveTheLogIsOn()
        rig.capture.grant = .denied
        rig.capture.outcome = .frozen(Freeze(displays: [Rig.display(1)], windows: []))

        let result = await rig.session.begin()

        guard case .refused(.noPermission) = result else {
            return XCTFail("a denied press did not come back as a permission refusal: \(result)")
        }
        XCTAssertEqual(rig.capture.freezeCalls, 0, "a press without the grant still froze the screen")
        XCTAssertEqual(rig.capture.requestCalls, 1, "the refusal did not ask macOS for the grant")
        XCTAssertEqual(ScreenshotsLog.lines.filter { $0.contains("no screen recording permission") }.count, 1,
                       "the refusal was not logged exactly once: \(ScreenshotsLog.lines)")
    }

    func testAGrantedPressFreezesOnceAndLogsNothing() async throws {
        let rig = Rig(home: scratchDirectory("shots-granted"))
        ScreenshotsLog.proveTheLogIsOn()
        rig.capture.outcome = .frozen(Freeze(displays: [Rig.display(1)], windows: []))

        let result = await rig.session.begin()

        guard case .ready(let freeze) = result else { return XCTFail("a granted press was refused: \(result)") }
        XCTAssertEqual(freeze.frames.count, 1)
        XCTAssertEqual(rig.capture.freezeCalls, 1)
        XCTAssertEqual(ScreenshotsLog.lines, [], "a capture that worked wrote a line: the log is for refusals")
    }

    func testAWholeScreenPressWithoutTheGrantSavesNothing() async throws {
        let rig = Rig(home: scratchDirectory("shots-denied-screens"))
        rig.capture.grant = .denied
        rig.capture.outcome = .frozen(Freeze(displays: [Rig.display(1)], windows: []))

        let delivery = await rig.session.captureScreens()

        XCTAssertEqual(delivery.refusals, [.noPermission])
        XCTAssertEqual(delivery.files, [])
        XCTAssertEqual(rig.writer.written.count, 0)
        XCTAssertEqual(rig.capture.freezeCalls, 0)
    }
}
