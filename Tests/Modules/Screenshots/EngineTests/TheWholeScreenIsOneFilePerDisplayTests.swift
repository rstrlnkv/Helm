import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The full-screen shortcut saves one file per display, and counts the files that exist.** A second
/// display that was listed and gone by the time it was captured is a refusal
/// and not a file: "saved 2" over a display that is not there tells a person
/// they have a picture of a screen they do not.
final class TheWholeScreenIsOneFilePerDisplayTests: XCTestCase {
    override func setUp() { super.setUp(); ScreenshotsLog.begin() }
    override func tearDown() { ScreenshotsLog.end(); super.tearDown() }

    func testTwoDisplaysAreTwoFiles() async throws {
        let rig = Rig(home: scratchDirectory("shots-screens"))
        rig.capture.outcome = .frozen(Freeze(
            displays: [Rig.display(1), Rig.display(2, origin: CGPoint(x: 100, y: 0), red: 255)], windows: []))

        let delivery = await rig.session.captureScreens()

        XCTAssertEqual(delivery.files.count, 2)
        XCTAssertEqual(Set(delivery.files.map(\.lastPathComponent)).count, 2, "two displays wrote one name")
        XCTAssertEqual(delivery.refusals, [])
        XCTAssertEqual(rig.pasteboard.copies.count, 0, "the default destination is the folder alone")
    }

    func testADisplayThatWentIsRefusedAndNotCounted() async throws {
        ScreenshotsLog.proveTheLogIsOn()
        let rig = Rig(home: scratchDirectory("shots-screens-gone"))
        rig.capture.outcome = .frozen(Freeze(displays: [Rig.display(1), .gone(DisplayID(2))], windows: []))

        let delivery = await rig.session.captureScreens()

        XCTAssertEqual(delivery.files.count, 1, "a display that was gone was counted as saved")
        XCTAssertEqual(delivery.refusals, [.displayGone])
        XCTAssertEqual(rig.writer.written.count, 1)
        XCTAssertTrue(ScreenshotsLog.lines.contains { $0.contains("display was gone") }, "\(ScreenshotsLog.lines)")
    }

    func testTheClipboardTakesTheMainDisplayOnlyOnce() async throws {
        let rig = Rig(home: scratchDirectory("shots-screens-clip"),
                      settings: ScreenshotsSettings(afterFullScreen: .both, thumbnail: true))
        rig.capture.outcome = .frozen(Freeze(
            displays: [Rig.display(1), Rig.display(2, origin: CGPoint(x: 100, y: 0), red: 255)], windows: []))

        let delivery = await rig.session.captureScreens()

        XCTAssertEqual(delivery.files.count, 2)
        XCTAssertEqual(rig.pasteboard.copies.count, 1, "the clipboard holds one picture and was written twice")
        XCTAssertTrue(delivery.copied)
    }

    func testClipboardOnlySavesNothing() async throws {
        let rig = Rig(home: scratchDirectory("shots-screens-clipboard"),
                      settings: ScreenshotsSettings(afterFullScreen: .clipboard, thumbnail: true))
        rig.capture.outcome = .frozen(Freeze(displays: [Rig.display(1)], windows: []))

        let delivery = await rig.session.captureScreens()

        XCTAssertEqual(delivery.files, [])
        XCTAssertEqual(rig.writer.written.count, 0)
        XCTAssertEqual(rig.pasteboard.copies.count, 1)
    }

    /// A first display that is gone must not use up the clipboard's one copy.
    func testAGoneFirstDisplayDoesNotCostTheClipboard() async throws {
        let rig = Rig(home: scratchDirectory("shots-screens-gonefirst"),
                      settings: ScreenshotsSettings(afterFullScreen: .clipboard, thumbnail: true))
        rig.capture.outcome = .frozen(Freeze(displays: [.gone(DisplayID(1)), Rig.display(2)], windows: []))

        let delivery = await rig.session.captureScreens()

        XCTAssertEqual(rig.pasteboard.copies.count, 1)
        XCTAssertTrue(delivery.copied)
    }
}
