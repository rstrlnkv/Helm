import XCTest
@testable import HelmRuntime

final class LogPolicyTests: XCTestCase {
    func testDevBuildsLogByDefault() {
        XCTAssertTrue(LogPolicy.isEnabled(version: "0.7.0-dev.2", override: nil))
        XCTAssertTrue(LogPolicy.isEnabled(version: "1.0.0-dev", override: nil))
    }

    func testStableBuildsStaySilentUnlessAskedTo() {
        XCTAssertFalse(LogPolicy.isEnabled(version: "0.7.0", override: nil))
        XCTAssertTrue(LogPolicy.isEnabled(version: "0.7.0", override: true))
        // An explicit opt-out wins even on a dev build.
        XCTAssertFalse(LogPolicy.isEnabled(version: "0.7.0-dev.2", override: false))
    }
}

final class LogLineTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    func testLineCarriesTimeLevelCategoryAndMessage() {
        let line = LogLine.format(date: stamp, level: .error, category: "vpn",
                                  message: "connect failed", timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(line.hasSuffix("[error] [vpn] connect failed"), line)
        XCTAssertTrue(line.hasPrefix("2023-11-14 22:13:20"), line)
        XCTAssertFalse(line.contains("\n"))
    }

    /// Newlines would break one-line-per-event parsing when reading the file.
    func testMultilineMessagesAreFlattened() {
        let line = LogLine.format(date: stamp, level: .info, category: "brew",
                                  message: "line one\nline two", timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(line.hasSuffix("line one ⏎ line two"), line)
    }
}

final class LogRotationTests: XCTestCase {
    func testRotatesOnceOverTheSizeLimit() {
        XCTAssertFalse(LogRotation.shouldRotate(currentSize: 0, limit: 1024))
        XCTAssertFalse(LogRotation.shouldRotate(currentSize: 1023, limit: 1024))
        XCTAssertTrue(LogRotation.shouldRotate(currentSize: 1024, limit: 1024))
    }
}
