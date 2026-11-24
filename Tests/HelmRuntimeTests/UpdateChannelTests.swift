import XCTest
@testable import HelmRuntime

/// The channel was called "stable" in 0.7.0 and earlier, and that string is
/// sitting in the defaults of every installed copy. Reading it must not throw
/// those users onto the dev channel, and must not silently reset them either.
final class UpdateChannelMigrationTests: XCTestCase {
    func testLegacyStableReadsAsBeta() {
        XCTAssertEqual(UpdateCheck.Channel.stored("stable"), .beta)
    }

    func testBetaAndDevRoundTrip() {
        XCTAssertEqual(UpdateCheck.Channel.stored("beta"), .beta)
        XCTAssertEqual(UpdateCheck.Channel.stored("dev"), .dev)
    }

    func testUnsetOrUnknownIsTheSaferChannel() {
        XCTAssertEqual(UpdateCheck.Channel.stored(nil), .beta)
        XCTAssertEqual(UpdateCheck.Channel.stored("nightly"), .beta)
    }
}
