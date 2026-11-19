import AppKit
import HelmRuntime
import HelmUI
import XCTest
@testable import HelmApp

/// **The Dock helper's link reaches the Launchpad, or says why not.** Asked of the host with no window in play
/// (no module is live in a test, and `present` is nil in any case): a refused link does nothing, a link with the
/// module off logs one line and opens Settings on the Launchpad page through `.helmOpenSettings`, and links closer
/// than the throttle are one press. The notification is the boundary, as in `OpeningHelmAgainOpensSettingsTests`.
@MainActor
final class ALaunchpadLinkOpensTheWindowOrTheSettingsTests: XCTestCase {
    private let link = URL(string: "helm-launchpad://toggle")!

    /// What the link did and the module ids `.helmOpenSettings` was posted for.
    private func open(_ url: URL, at now: TimeInterval) -> (ModuleHost.LinkOutcome, [String?]) {
        var asked: [String?] = []
        let token = NotificationCenter.default.addObserver(forName: .helmOpenSettings, object: nil, queue: nil) {
            asked.append($0.object as? String)
        }
        defer { NotificationCenter.default.removeObserver(token) }
        return (ModuleHost.shared.openLaunchpadFromLink(url, now: now), asked)
    }

    func testALinkWithTheModuleOffOpensItsSettingsPage() {
        let (outcome, asked) = open(link, at: 10_000)
        XCTAssertEqual(outcome, .moduleOff)
        XCTAssertEqual(asked, ["launchpad"], "Settings opens on the Launchpad page, once")
    }

    func testAnotherLinkIsRefusedAndAsksForNothing() {
        for text in ["helm-launchpad://toggle/x", "helm-dev-launchpad://toggle", "https://toggle", "helm-launchpad://open"] {
            let (outcome, asked) = open(URL(string: text)!, at: 20_000)
            XCTAssertEqual(outcome, .refused, text)
            XCTAssertEqual(asked, [], text)
        }
    }

    func testARefusedLinkSpendsNoThrottle() {
        _ = open(URL(string: "helm-launchpad://toggle/x")!, at: 30_000)
        XCTAssertEqual(open(link, at: 30_000.1).0, .moduleOff)
    }

    func testTwoLinksInAHalfSecondAreOnePress() {
        XCTAssertEqual(open(link, at: 40_000).0, .moduleOff)
        let (outcome, asked) = open(link, at: 40_000.2)
        XCTAssertEqual(outcome, .throttled)
        XCTAssertEqual(asked, [])
    }

    /// A loop of refused links is one line in the log per throttle window, then another once the window is over.
    func testRefusedLinksWriteOneLogLinePerWindow() {
        let log = HelmLog.shared
        log.setEnabled(true)
        addTeardownBlock { log.setEnabled(false); log.clearTail() }
        log.clearTail()
        let bad = URL(string: "helm-launchpad://toggle/x")!
        for step in 0..<5 { XCTAssertEqual(open(bad, at: 60_000 + Double(step) * 0.05).0, .refused) }
        func refusals() -> Int { log.recentEntries().filter { $0.message == "link refused" }.count }
        XCTAssertEqual(refusals(), 1, "five refusals in a quarter second")
        _ = open(bad, at: 60_001)
        XCTAssertEqual(refusals(), 2, "the next window has its own line")
    }

    /// The two throttles are apart: a link that opened the window spends nothing of the refusal line's window, and the
    /// refusal line spends nothing of the open's, in either order.
    /// (`ModuleHost.shared` keeps both throttles between tests and a clock that runs backwards is throttled, so this test
    /// runs after the others by name and by the times it uses.)
    func testTwoThrottlesKeepTheirOwnWindows() {
        let log = HelmLog.shared
        log.setEnabled(true)
        addTeardownBlock { log.setEnabled(false); log.clearTail() }
        log.clearTail()
        let bad = URL(string: "helm-launchpad://toggle/x")!
        func refusals() -> Int { log.recentEntries().filter { $0.message == "link refused" }.count }
        XCTAssertEqual(open(link, at: 70_000).0, .moduleOff)
        XCTAssertEqual(open(bad, at: 70_000.1).0, .refused)
        XCTAssertEqual(refusals(), 1, "an open just before does not silence the first refusal line")
        XCTAssertEqual(open(bad, at: 70_001).0, .refused)
        XCTAssertEqual(open(link, at: 70_001.1).0, .moduleOff, "a refusal line just before does not throttle the open")
        XCTAssertEqual(refusals(), 2)
    }
}
