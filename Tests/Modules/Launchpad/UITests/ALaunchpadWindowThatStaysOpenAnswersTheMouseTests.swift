import AppKit
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A window that stays open must not stay deaf: `ignoresMouseEvents` is true while the fingers hold it or it settles in, and every way
/// that ends without taking the window down gives the mouse back. Runs the real panel (made tiny and far off the screens, so the run
/// does not flash a full-screen window) through the sequences the fake window cannot tell apart.
@MainActor
final class ALaunchpadWindowThatStaysOpenAnswersTheMouseTests: XCTestCase {
    private var windows: [LaunchpadWindow] = []

    override func setUp() async throws {
        _ = NSApplication.shared
        try XCTSkipIf(HelmMotionProbe.reduced, "needs motion on: the settle runs on its clock")
    }

    override func tearDown() async throws {
        for w in windows { w.close() }
        windows = []
        await settle(0.6)
    }

    private func make(_ label: String) -> (LaunchpadWindow, LaunchpadPanel) {
        let rig = LaunchpadRig(self, label: label)
        let before = Set(NSApp.windows.compactMap { $0 as? LaunchpadPanel }.map(ObjectIdentifier.init))
        let window = LaunchpadWindow(model: rig.model)
        windows.append(window)
        let panel = NSApp.windows.compactMap { $0 as? LaunchpadPanel }.first { !before.contains(ObjectIdentifier($0)) }!
        panel.setFrame(CGRect(x: -20000, y: -20000, width: 40, height: 40), display: false)
        return (window, panel)
    }

    private func settle(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
    /// Longer than the opening settle's own fallback timer (`windowZoomDuration + 0.3`).
    private let landed = 0.9

    func testAWindowPresentedThenLeftAloneAnswersTheMouseWhenItHasLanded() async {
        let (window, panel) = make("deaf-present")
        window.present()
        XCTAssertTrue(panel.ignoresMouseEvents, "the subject: the opening settle holds the mouse back")
        await settle(landed)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
    }

    func testAPinchCompletedAnswersTheMouseWhenItHasLanded() async {
        let (window, panel) = make("deaf-pinch")
        window.beginScrub(.pinch)
        window.scrub(to: 0.6)
        XCTAssertTrue(panel.ignoresMouseEvents, "the subject")
        window.endScrub(.complete)
        await settle(landed)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
    }

    func testASpreadRevertedAnswersTheMouseAtOnceAndStaysOpen() async {
        let (window, panel) = make("deaf-spread-revert")
        window.present()
        await settle(landed)
        window.beginScrub(.spread)
        window.scrub(to: 0.4)
        XCTAssertTrue(panel.ignoresMouseEvents, "the subject")
        window.endScrub(.revert)
        XCTAssertFalse(panel.ignoresMouseEvents, "a revert gives the mouse back at once, before its settle lands")
        await settle(landed)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
    }

    func testASpreadThatBeginsInsideTheOpeningSettleAndRevertsLeavesTheMouseBack() async {
        let (window, panel) = make("deaf-spread-in-settle")
        window.present()
        await settle(0.1)
        window.beginScrub(.spread)
        window.scrub(to: 0.3)
        window.endScrub(.revert)
        await settle(landed)
        XCTAssertFalse(panel.ignoresMouseEvents, "the opening settle was overtaken; the revert's own settle must give the mouse back")
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
    }

    func testBringForwardInsideTheOpeningSettleDoesNotStrandTheMouse() async {
        let (window, panel) = make("deaf-forward-settle")
        window.present()
        await settle(0.1)
        window.bringForward()
        await settle(landed)
        XCTAssertFalse(panel.ignoresMouseEvents)
    }

    func testBringForwardInsideAPinchScrubCompletesItAndGivesTheMouseBack() async {
        let (window, panel) = make("deaf-forward-scrub")
        window.beginScrub(.pinch)
        window.scrub(to: 0.2)
        window.bringForward()
        await settle(landed)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
    }

    func testBringForwardInsideASpreadScrubRevertsItAndGivesTheMouseBack() async {
        let (window, panel) = make("deaf-forward-spread")
        window.present()
        await settle(landed)
        window.beginScrub(.spread)
        window.scrub(to: 0.5)
        window.bringForward()
        await settle(landed)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
    }

    func testACloseInsideTheOpeningSettleThenANewWindowOpensAnswering() async {
        let (first, _) = make("deaf-close-settle-1")
        first.present()
        await settle(0.1)
        first.close()
        let (second, panel) = make("deaf-close-settle-2")
        second.present()
        await settle(landed)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
    }

    func testAPinchRevertedThenANewPinchCompletedAnswers() async {
        let (first, _) = make("deaf-revert-then-1")
        first.beginScrub(.pinch)
        first.endScrub(.revert)
        let (second, panel) = make("deaf-revert-then-2")
        second.beginScrub(.pinch)
        second.scrub(to: 0.9)
        second.endScrub(.complete)
        await settle(landed)
        XCTAssertFalse(panel.ignoresMouseEvents)
    }

    func testTwoCompletesInARowDoNotLeaveItDeaf() async {
        let (window, panel) = make("deaf-twice")
        window.beginScrub(.pinch)
        window.endScrub(.complete)
        window.endScrub(.complete)
        window.beginScrub(.pinch)
        await settle(landed)
        XCTAssertFalse(panel.ignoresMouseEvents)
    }
}

/// Reads the system's Reduce Motion the way the window does.
private enum HelmMotionProbe {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}
