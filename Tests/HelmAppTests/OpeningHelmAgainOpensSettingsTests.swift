import AppKit
import HelmUI
import XCTest
@testable import HelmApp

/// **A person who opens Helm while it runs gets Settings.**
///
/// Helm is an accessory app: no Dock icon, no window of its own until Settings
/// is opened. Finder, Spotlight, Launchpad and `open -a` do not start a second
/// copy of a running app, they send the running one the reopen event, and with no
/// `applicationShouldHandleReopen` the answer was nothing at all: no window, no
/// icon, no panel, an app that looked as if it had not started.
///
/// The seam is the one every other "open Settings" caller already uses, the
/// `.helmOpenSettings` notification (`StatusItemController` listens). Observing it
/// keeps this test off the real status item and off the screen: no
/// `StatusItemController` is built, no window is ordered in. A fake of the
/// status controller would stand for a side that does not exist as a port; the
/// notification is the boundary.
///
/// Asked through the `NSApplicationDelegate` protocol, so that a delegate with no
/// answer reads as `nil` and fails an assertion rather than a build.
@MainActor
final class OpeningHelmAgainOpensSettingsTests: XCTestCase {

    private func reopen(hasVisibleWindows: Bool) -> (answer: Bool?, openRequests: Int) {
        let delegate: NSApplicationDelegate = AppDelegate()
        var requests = 0
        let token = NotificationCenter.default.addObserver(
            forName: .helmOpenSettings, object: nil, queue: nil) { _ in requests += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        let answer = delegate.applicationShouldHandleReopen?(NSApplication.shared, hasVisibleWindows: hasVisibleWindows)
        return (answer, requests)
    }

    func testReopeningWithNoWindowOpensSettingsOnceAndLeavesTheRestToUs() {
        let result = reopen(hasVisibleWindows: false)
        XCTAssertEqual(result.openRequests, 1, "reopen with nothing on screen must ask for Settings")
        XCTAssertEqual(result.answer, false, "false: the default reopen has nothing more to do")
    }

    func testReopeningWithAWindowOpenAsksForNothingExtra() {
        let result = reopen(hasVisibleWindows: true)
        XCTAssertEqual(result.openRequests, 0, "a window is already there to come forward")
        XCTAssertEqual(result.answer, false)
    }
}
