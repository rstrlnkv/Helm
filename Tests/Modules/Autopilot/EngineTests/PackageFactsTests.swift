import XCTest
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// A package — an `.app`, an `.rtfd`, a `.photoslibrary` — is a directory that
/// the system asks everyone to treat as one thing. `FolderReader` honours that
/// (`isDirectory` is deliberately false for one, so a rule cannot reach inside)
/// and then reports its size from `.fileSizeKey`, which a directory does not
/// have. The fact that comes out says: not a directory, zero bytes.
///
/// `RuleMatcher` already refuses to compare the size of a folder, and says why:
/// "a rule aimed at small files that quietly also took the folders they were
/// sorted into". A package is not a folder by that flag, so it walks straight
/// past the guard wearing a size nobody read.
///
/// The rules run unattended, on a timer, on `~/Downloads` — where a Mac user
/// keeps the applications they have just downloaded.
final class PackageFactsTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("package-facts")
        let bundle = root.appendingPathComponent("Downloaded.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        // Four megabytes inside the bundle, so "smaller than 1 MB" is a lie
        // about it by any reading of the word.
        try Data(repeating: 0x41, count: 4_000_000)
            .write(to: bundle.appendingPathComponent("Downloaded"))
    }

    private func fact(named name: String) throws -> FileFacts {
        let facts = FolderReader().facts(in: root.path, depth: 1)
        return try XCTUnwrap(facts.first { $0.name == name }, "\(name) was not read at all")
    }

    /// The fact itself. Either the package carries its real size or it must not
    /// claim to be a file with a size of zero — a size condition has no third
    /// answer to give.
    func testAPackageDoesNotReportItselfAsAZeroByteFile() throws {
        let app = try fact(named: "Downloaded.app")
        XCTAssertFalse(app.isDirectory, "a package is one thing, not a folder to descend into")
        XCTAssertGreaterThan(app.bytes, 0,
                             "zero is what `.fileSizeKey` answers for a directory, "
                             + "not what the bundle weighs")
    }

    /// The consequence, in the shape the person wrote it: a housekeeping rule
    /// for the small stuff.
    func testASmallerThanRuleDoesNotMatchAnApplicationBundle() throws {
        let app = try fact(named: "Downloaded.app")
        let tidyUp = Rule(name: "Small files", enabled: true,
                          conditions: [.size(.smallerThan, megabytes: 1)],
                          action: .trash)

        XCTAssertFalse(RuleMatcher.matches(app, tidyUp),
                       "a 4 MB application is not a file smaller than 1 MB; matching it "
                       + "means the hourly sweep trashes every app in the watched folder")
    }

    /// And the other direction, which costs nothing but is the same defect:
    /// a rule written to catch the big things never sees the biggest thing in
    /// the folder.
    func testALargerThanRuleStillFindsAnApplicationBundle() throws {
        let app = try fact(named: "Downloaded.app")
        let archive = Rule(name: "Big things", enabled: true,
                           conditions: [.size(.largerThan, megabytes: 1)],
                           action: .move(to: "/somewhere"))

        XCTAssertTrue(RuleMatcher.matches(app, archive),
                      "4 MB is larger than 1 MB, whatever shape the 4 MB is stored in")
    }
}
