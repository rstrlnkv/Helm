import XCTest
import HelmTestSupport
@testable import Module_Duplicates_Engine

/// A duplicate search nobody is watching stops at `~/Library`; one a person
/// asked for goes wherever they pointed it.
///
/// The asymmetry is the whole rule, and both halves need a test or the next
/// person will "simplify" one of them away. The unattended half is the defect
/// this file was written for: the stored root is the home on the owner's Mac,
/// `ScanRoot.resolve` approves the home by design, and nothing then stopped the
/// walk one step later — the journal it writes at 0600 named 217 paths under
/// `~/Library`, which is a privilege the person granted Helm handed to every
/// process running as this user.
///
/// The home is injected, so the fixture is a scratch tree rather than the
/// owner's own `~/Library` — and so the unattended assertion can actually fail,
/// which it cannot if the fixture is somewhere the gate never looks.
final class TheTimersWalkStaysOutOfTheLibraryTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("dup-unattended-library")
        // One pair, above the 1 MB floor: a copy in the open and a copy inside
        // the Library. They are a group only if the Library was walked.
        let payload = Data(repeating: 0x41, count: 1_200_000)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Caches/com.acme.tool"),
            withIntermediateDirectories: true)
        try payload.write(to: home.appendingPathComponent("Downloads-holiday.jpg"))
        try payload.write(to: home.appendingPathComponent(
            "Library/Caches/com.acme.tool/holiday.jpg"))
    }

    func testTheTimersWalkNeverEntersTheLibrary() throws {
        let scanner = DuplicateScanner(unattended: true, home: home.path)
        let groups = try XCTUnwrap(scanner.find(under: home.path, by: KeepRule(.standard)))
        let paths = groups.flatMap(\.paths)
        XCTAssertFalse(paths.contains { $0.contains("/Library/") },
                       "a path under the Library reached the journal: \(paths)")
        // And the pair does not form at all, which is the honest outcome: the
        // copy in the open has nothing left to be a duplicate of.
        XCTAssertTrue(groups.isEmpty, "groups: \(groups)")
    }

    /// A person's own scan is not restricted. The distinction is unattended
    /// versus asked-for, never `~/Library` versus everything else: they picked
    /// the folder in an open panel and are watching the result.
    func testTheSearchAPersonAskedForFindsTheSamePair() throws {
        let scanner = DuplicateScanner(unattended: false, home: home.path)
        let groups = try XCTUnwrap(scanner.find(under: home.path, by: KeepRule(.standard)))
        XCTAssertEqual(groups.count, 1, "groups: \(groups)")
        XCTAssertTrue(groups.flatMap(\.paths).contains { $0.contains("/Library/") },
                      "the pair the person asked for is not there: \(groups)")
    }
}
