import XCTest
@testable import HelmRuntime

/// What a logged failure has to carry to be worth writing down.
///
/// The log had thirteen error sites across seven modules, and most of them
/// recorded that something failed without recording anything you could act
/// on: "refused out-of-scope path" — which path? "the app refused the
/// replacement" — which app? `error.localizedDescription` — which for a
/// Cocoa error is usually "The operation couldn't be completed", with the
/// domain, the code and the underlying error all thrown away.
final class HelmFailureTests: XCTestCase {

    // MARK: - Cocoa errors

    func testAnNSErrorKeepsItsDomainAndCode() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 4,
                            userInfo: [NSLocalizedDescriptionKey: "No such file"])
        let described = HelmFailure.describe(error)
        XCTAssertTrue(described.contains("NSCocoaErrorDomain"), described)
        XCTAssertTrue(described.contains("4"), described)
        XCTAssertTrue(described.contains("No such file"), described)
    }

    /// The reason a Cocoa error is opaque is almost always one level down:
    /// "couldn't be completed" wrapping "No such file or directory".
    func testTheUnderlyingErrorSurvives() {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: 2,
                                 userInfo: [NSLocalizedDescriptionKey: "No such file or directory"])
        let outer = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [
            NSLocalizedDescriptionKey: "The operation couldn’t be completed.",
            NSUnderlyingErrorKey: underlying,
        ])
        let described = HelmFailure.describe(outer)
        XCTAssertTrue(described.contains("NSPOSIXErrorDomain"), described)
        XCTAssertTrue(described.contains("No such file or directory"), described)
    }

    /// A file path in the failing error is the single most useful fact in it,
    /// and the single most private. It goes in redacted, never raw.
    func testAPathInTheErrorIsRedactedNotDropped() {
        let home = NSHomeDirectory()
        let error = NSError(domain: NSCocoaErrorDomain, code: 4,
                            userInfo: [NSFilePathErrorKey: "\(home)/Documents/tax.pdf"])
        let described = HelmFailure.describe(error)
        XCTAssertTrue(described.contains("~/Documents/tax.pdf"), described)
        XCTAssertFalse(described.contains(home), "the real home path leaked: \(described)")
    }

    func testNoUserInfoStillGivesDomainAndCode() {
        let described = HelmFailure.describe(NSError(domain: "MyDomain", code: -42))
        XCTAssertTrue(described.contains("MyDomain"), described)
        XCTAssertTrue(described.contains("-42"), described)
    }

    // MARK: - OSStatus

    /// A bare integer is a number to paste into a search engine, not a fact.
    func testOSStatusCarriesItsMeaningWhereMacOSKnowsIt() {
        // errSecItemNotFound — one every keychain caller meets.
        let described = HelmFailure.osStatus(-25300)
        XCTAssertTrue(described.contains("-25300"), described)
        XCTAssertGreaterThan(described.count, "OSStatus -25300".count,
                             "no explanation was added: \(described)")
    }

    func testAnUnknownOSStatusStillReportsTheNumber() {
        XCTAssertTrue(HelmFailure.osStatus(999_999).contains("999999"))
    }

    func testSuccessIsNotAFailure() {
        XCTAssertNil(HelmFailure.osStatusIfFailed(0))
        XCTAssertNotNil(HelmFailure.osStatusIfFailed(-25300))
    }

    // MARK: - errno

    func testErrnoIsNamedNotNumbered() {
        let described = HelmFailure.posix(2)   // ENOENT
        XCTAssertTrue(described.contains("2"), described)
        XCTAssertTrue(described.lowercased().contains("no such file"), described)
    }

    // MARK: - The line the log writes

    /// Every failure says where it came from, so a report can be traced to a
    /// line without guessing which of four call sites produced the wording.
    func testTheSiteIsCarriedIntoTheMessage() {
        let line = LogLine.format(date: Date(), level: .error, category: "disk",
                                  message: "trash refused",
                                  site: LogSite(file: "DiskEngine.swift", line: 105,
                                                function: "trash(_:)"))
        XCTAssertTrue(line.contains("DiskEngine.swift:105"), line)
        XCTAssertTrue(line.contains("trash(_:)"), line)
        XCTAssertTrue(line.contains("trash refused"), line)
    }

    /// `#fileID` is "Module/File.swift"; the module is already the category.
    func testTheFileIDIsReducedToItsFilename() {
        XCTAssertEqual(LogSite(fileID: "Module_Disk_Engine/DiskEngine.swift",
                               line: 9, function: "f()").file, "DiskEngine.swift")
    }

    func testALineWithoutASiteIsUnchanged() {
        let line = LogLine.format(date: Date(), level: .info, category: "app",
                                  message: "started")
        XCTAssertTrue(line.hasSuffix("[info] [app] started"), line)
    }

    /// One event is one line: the file is triaged with grep.
    func testAMultiLineFailureStaysOneLine() {
        let error = NSError(domain: "D", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "first\nsecond"])
        let line = LogLine.format(date: Date(), level: .error, category: "x",
                                  message: HelmFailure.describe(error))
        XCTAssertFalse(line.contains("\n"), line)
    }
}
