import XCTest
@testable import HelmRuntime

/// An update Helm found while nobody was looking is the one event the updater
/// has that happens to an empty chair — and until this existed it was drawn on
/// one page, behind two clicks, in a window a menu-bar app does not open by
/// itself.
final class UpdateNewsTests: XCTestCase {

    func testAVersionNobodyHasBeenToldAboutIsAnnounced() {
        XCTAssertEqual(UpdateNews.version(toAnnounce: "v0.12.0",
                                          lastAnnounced: nil,
                                          startedByHand: false),
                       "v0.12.0")
    }

    /// The launch check runs every day. The same offer arriving every morning is
    /// how a person learns to switch a channel off.
    func testTheSameVersionIsAnnouncedOnce() {
        XCTAssertNil(UpdateNews.version(toAnnounce: "v0.12.0",
                                        lastAnnounced: "v0.12.0",
                                        startedByHand: false))
    }

    func testTheNextVersionIsAnnouncedAgain() {
        XCTAssertEqual(UpdateNews.version(toAnnounce: "v0.12.1",
                                          lastAnnounced: "v0.12.0",
                                          startedByHand: false),
                       "v0.12.1")
    }

    /// A check somebody pressed answers on the card they pressed it on. A banner
    /// over the window they are looking at says the same thing twice.
    func testACheckSomebodyStartedSaysNothing() {
        XCTAssertNil(UpdateNews.version(toAnnounce: "v0.12.0",
                                        lastAnnounced: nil,
                                        startedByHand: true))
    }

    /// And it does not spend the announcement either: pressing Check for updates
    /// before the day's silent check must not be what makes the silent one quiet.
    func testAHandCheckLeavesTheAnnouncementForTheSilentOne() {
        XCTAssertNil(UpdateNews.version(toAnnounce: "v0.12.0",
                                        lastAnnounced: nil,
                                        startedByHand: true))
        XCTAssertEqual(UpdateNews.version(toAnnounce: "v0.12.0",
                                          lastAnnounced: nil,
                                          startedByHand: false),
                       "v0.12.0")
    }
}
