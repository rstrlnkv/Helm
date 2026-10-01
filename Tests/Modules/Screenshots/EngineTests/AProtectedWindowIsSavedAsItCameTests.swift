import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A protected window comes back black for every program, and Helm does not
/// fight it.** The picture is saved as it came: no black detection, no refusal,
/// no retry from the freeze. Saying so in the log would be a line per capture of
/// a streaming window, about nothing having gone wrong.
final class AProtectedWindowIsSavedAsItCameTests: XCTestCase {
    override func setUp() { super.setUp(); ScreenshotsLog.begin() }
    override func tearDown() { ScreenshotsLog.end(); super.tearDown() }

    func testABlackWindowIsDeliveredAndSaved() async throws {
        ScreenshotsLog.proveTheLogIsOn()
        let rig = Rig(home: scratchDirectory("shots-protected"))
        rig.capture.windows = [5: .image(makeImage(width: 40, height: 30))]
        let freeze = Freeze(displays: [Rig.display(1)], windows: [])

        guard case .image(let image) = await rig.session.window(5, in: freeze) else { return XCTFail("a black window was refused") }
        let delivery = await rig.session.deliver(image, saves: true, copies: true)

        XCTAssertEqual(delivery.refusals, [], "a black window was turned into a refusal")
        XCTAssertEqual(delivery.files.count, 1)
        XCTAssertTrue(delivery.copied)
        XCTAssertEqual(rig.capture.freezeCalls, 0)
        XCTAssertEqual(ScreenshotsLog.lines, [], "a protected window was logged: \(ScreenshotsLog.lines)")
    }
}
