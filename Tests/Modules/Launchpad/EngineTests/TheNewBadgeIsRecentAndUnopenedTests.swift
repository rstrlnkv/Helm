import XCTest
@testable import Module_Launchpad_Engine

/// "New" is added within `recentDays` and never opened from Launchpad; a date in the future or none is not new.
final class TheNewBadgeIsRecentAndUnopenedTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    func testRecentAndUnopenedIsNew() {
        XCTAssertTrue(LaunchpadCategories.isNew(added: ago(0), launches: 0, now: now))
        XCTAssertTrue(LaunchpadCategories.isNew(added: ago(Double(LaunchpadCategories.recentDays)), launches: 0, now: now), "the 30th day still counts")
    }

    func testOpenedOldFutureOrUndatedIsNot() {
        XCTAssertFalse(LaunchpadCategories.isNew(added: ago(1), launches: 1, now: now), "opened once")
        XCTAssertFalse(LaunchpadCategories.isNew(added: ago(31), launches: 0, now: now))
        XCTAssertFalse(LaunchpadCategories.isNew(added: ago(-1), launches: 0, now: now), "added in the future")
        XCTAssertFalse(LaunchpadCategories.isNew(added: nil, launches: 0, now: now))
    }
}
