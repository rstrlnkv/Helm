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

/// The log file was 0644 inside a 0700 folder, where ARCHITECTURE.md § Diagnostics
/// log describes the 0700 as the protection — measured on the owner's own Mac,
/// where the folder was doing all of it and the file none.
///
/// Two halves, because a file gets its mode from whoever created it: `append`
/// creates through `PrivateFile` now, and a file an *earlier build* created keeps
/// its 0644 for as long as it is appended to, so launch tightens what it finds.
final class TheLogFileIsAsPrivateAsItsFolderTests: XCTestCase {

    override func tearDown() {
        HelmLog.shared.setEnabled(false)
        HelmLog.shared.clearTail()
        super.tearDown()
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? Int)
    }

    /// A file this app writes itself. The destination is the test folder — the
    /// rule for that is `LogDestination`, and `TheSuiteDoesNotWriteTheUsersLog`
    /// holds it.
    func testALineWrittenIntoAFreshLogLeavesItPrivate() throws {
        try? FileManager.default.removeItem(at: HelmLog.fileURL)
        HelmLog.shared.setEnabled(true)

        HelmLog.shared.info("app", "a line \(UUID().uuidString)")
        _ = HelmLog.shared.recentEntries()   // drains the write queue

        XCTAssertTrue(FileManager.default.fileExists(atPath: HelmLog.fileURL.path),
                      "nothing was written, so the mode below is nobody's")
        XCTAssertEqual(try mode(of: HelmLog.fileURL), 0o600)
    }

    /// And one an older build left behind. `start` is what the app calls at
    /// launch; the marker is written first because the pre-redaction purge sits
    /// in the same method and would otherwise delete the fixture rather than
    /// tighten it.
    func testLaunchTightensALogAnEarlierBuildLeftReadableToEverybody() throws {
        let fm = FileManager.default
        XCTAssertTrue(PrivateFile.directory(at: HelmLog.directory))
        fm.createFile(atPath: HelmLog.resetMarkerURL.path, contents: Data())
        try? fm.removeItem(at: HelmLog.fileURL)
        fm.createFile(atPath: HelmLog.fileURL.path, contents: Data("old line\n".utf8),
                      attributes: [.posixPermissions: 0o644])
        XCTAssertEqual(try mode(of: HelmLog.fileURL), 0o644,
                       "the fixture is already private, so nothing below is a test")

        HelmLog.shared.start(version: "0.0.0", override: false)
        _ = HelmLog.shared.recentEntries()   // drains the queue the hardening is on

        XCTAssertEqual(try mode(of: HelmLog.fileURL), 0o600,
                       "a log an earlier build created stays readable by every account on "
                       + "the Mac for as long as it is appended to")
    }
}

final class LogRotationTests: XCTestCase {
    func testRotatesOnceOverTheSizeLimit() {
        XCTAssertFalse(LogRotation.shouldRotate(currentSize: 0, limit: 1024))
        XCTAssertFalse(LogRotation.shouldRotate(currentSize: 1023, limit: 1024))
        XCTAssertTrue(LogRotation.shouldRotate(currentSize: 1024, limit: 1024))
    }
}
