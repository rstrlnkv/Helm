import XCTest
@testable import HelmRuntime

/// **Any program on the Mac can open any URL at Helm.** The Launchpad link is input from outside the process,
/// so only the one spelling the Dock helper sends opens the window; every near miss is refused and spends no
/// throttle.
final class TheLaunchpadLinkTakesOnlyTheExactLinkTests: XCTestCase {
    private let scheme = "helm-launchpad"

    private func accepts(_ text: String, scheme: String? = nil) -> Bool {
        guard let url = URL(string: text) else { return false }
        return LaunchpadLink.accepts(url, scheme: scheme ?? self.scheme)
    }

    func testTheExactLinkIsTakenOnEachBuildsOwnScheme() {
        XCTAssertTrue(accepts("helm-launchpad://toggle"))
        XCTAssertTrue(accepts("helm-dev-launchpad://toggle", scheme: "helm-dev-launchpad"))
    }

    func testAnythingElseIsRefused() {
        let refused = [
            "helm-dev-launchpad://toggle",       // another build's scheme: a dev helper never opens the release
            "HELM-LAUNCHPAD://toggle", "https://toggle", "helm-launchpad:toggle", "helm-launchpad:///toggle",
            "helm-launchpad://Toggle", "helm-launchpad://toggle.example", "helm-launchpad://open", "helm-launchpad://",
            "helm-launchpad://toggle/", "helm-launchpad://toggle/x", "helm-launchpad://toggle?", "helm-launchpad://toggle?a=1",
            "helm-launchpad://toggle#", "helm-launchpad://toggle#x", "helm-launchpad://user@toggle",
            "helm-launchpad://user:pw@toggle", "helm-launchpad://toggle:80", "helm-launchpad://toggle:",
            "file:///Users/someone/toggle", "",
        ]
        for text in refused { XCTAssertFalse(accepts(text), text.debugDescription) }
    }

    func testAnEmptySchemeTakesNothing() {
        XCTAssertFalse(accepts("helm-launchpad://toggle", scheme: ""))
    }

    func testTwoLinksInOneHalfSecondAreOnePress() {
        var throttle = LaunchpadLink.Throttle()
        XCTAssertTrue(throttle.admits(at: 100))
        XCTAssertFalse(throttle.admits(at: 100.2), "a double click")
        XCTAssertFalse(throttle.admits(at: 100.4), "measured from the last one that counted, not the last that came")
        XCTAssertTrue(throttle.admits(at: 100.6))
    }

    /// Spellings that parse to the same URL as the exact link, or that a looser parser would trim: all refused.
    func testEncodedUppercasedPaddedAndOtherSpellingsAreRefused() {
        let refused = [
            "helm-launchpad://%74oggle", "helm-launchpad://toggle%00", "helm-launchpad://toggle%0A", "helm-launchpad://toggle%20",
            "helm-launchpad://TOGGLE", "HELM-LAUNCHPAD://TOGGLE", "helm-launchpad://toggle ", " helm-launchpad://toggle",
            "helm-launchpad://toggle\n", "helm-launchpad://toggle\t", "helm-launchpad://tog\u{0301}gle",
            "helm-launchpad://toggle//", "helm-launchpad://toggle/%2e%2e", "helm-launchpad://toggle;x", "helm-launchpad://@toggle",
            "helm-launchpad://toggle@", "helm-launchpad://toggle@toggle", "helm-launchpad:/toggle", "helm-launchpad:toggle",
            "helm-launchpad://toggle.", "helm-launchpad://toggle:0", "helm-launchpad://toggle?#", "helm-launchpad://toggle/#",
            "helm-launchpad://toggle\\", "helm-launchpad://[toggle]", "helm-launchpad://toggle?toggle", "helm-launchpad+x://toggle",
            "helm-launchpad://toggle" + String(repeating: "a", count: 1_000_000),
            String(repeating: "helm-launchpad://toggle", count: 1000),
        ]
        for text in refused { XCTAssertFalse(accepts(text), String(text.prefix(60)).debugDescription) }
    }

    /// A URL made from parts, not parsed from the exact string, is judged by what it reads as.
    func testAURLBuiltFromPartsIsJudgedByItsSpelling() {
        var parts = URLComponents()
        parts.scheme = "helm-launchpad"; parts.host = "toggle"
        XCTAssertTrue(LaunchpadLink.accepts(parts.url!, scheme: scheme))
        parts.path = "/"
        XCTAssertFalse(LaunchpadLink.accepts(parts.url!, scheme: scheme))
        parts.path = ""; parts.percentEncodedQuery = ""
        XCTAssertFalse(LaunchpadLink.accepts(parts.url!, scheme: scheme), "an empty query is still a query")
        let relative = URL(string: "//toggle", relativeTo: URL(string: "helm-launchpad:")!)!
        XCTAssertTrue(LaunchpadLink.accepts(relative, scheme: scheme), "resolved, it is the exact link")
        XCTAssertFalse(LaunchpadLink.accepts(URL(string: "toggle", relativeTo: URL(string: "helm-launchpad://toggle/")!)!, scheme: scheme))
    }

    func testTheThrottleBoundariesAndANonsenseClock() {
        var t = LaunchpadLink.Throttle()
        XCTAssertTrue(t.admits(at: 0), "the first link counts at any time, zero included")
        XCTAssertFalse(t.admits(at: 0), "equal timestamps are one press")
        XCTAssertTrue(t.admits(at: LaunchpadLink.throttleInterval), "exactly the interval apart is a second press")
        var u = LaunchpadLink.Throttle()
        XCTAssertTrue(u.admits(at: 1_000))
        XCTAssertFalse(u.admits(at: 1_000.4999))
        XCTAssertTrue(u.admits(at: 1_000.5))
    }

    func testANonFiniteClockLeavesTheThrottleWorking() {
        var t = LaunchpadLink.Throttle()
        _ = t.admits(at: .nan)
        XCTAssertTrue(t.admits(at: 50))
        XCTAssertFalse(t.admits(at: 50.1), "a NaN once seen must not turn the throttle off for good")
    }
}
