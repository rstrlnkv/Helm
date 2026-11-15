import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// The duplicate finder does not look inside an application's own database.
///
/// **The fixture uses `.fcpbundle`, and the choice was measured rather than
/// guessed.** `isPackage`, which the walk asks of a directory after the rule
/// by name, asks LaunchServices whether the type is registered on *this* Mac.
/// Probed 2026-08-03 by creating one directory per extension and reading
/// `isPackageKey`: `photoslibrary`, `photolibrary`, `migratedphotolibrary`,
/// `aplibrary`, `musiclibrary`, `tvlibrary`, `imovielibrary` and `theater` all
/// came back **true** — so a test written with any of them passes whether or
/// not this rule exists, which is a test that cannot fail. `fcpbundle` came
/// back **false**, because Final Cut is not installed here. That is precisely
/// the case the rule exists for: an application database whose application this
/// Mac has never seen — a library copied from another machine, or one whose app
/// was removed — is a plain directory to LaunchServices and a database to
/// everybody else.
final class WalkStopsAtApplicationLibrariesTests: XCTestCase {
    private var fixture: URL!

    override func setUpWithError() throws {
        fixture = scratchDirectory("dup-library")
        try FileManager.default.createDirectory(
            at: fixture.appendingPathComponent("Final Cut.fcpbundle/Masters"),
            withIntermediateDirectories: true)
        // Identical files above the 1 MB floor: two in the open, one inside the
        // library. The library one joins the group only if the library is walked.
        let payload = Data(repeating: 0x41, count: 1_200_000)
        try payload.write(to: fixture.appendingPathComponent("holiday.jpg"))
        try payload.write(to: fixture.appendingPathComponent("holiday copy.jpg"))
        try payload.write(to: fixture.appendingPathComponent("Final Cut.fcpbundle/Masters/holiday.jpg"))
    }

    func testAFileInsideALibraryIsNeverOfferedAsADuplicate() throws {
        let groups = try XCTUnwrap(DuplicateScanner().find(under: fixture.path, by: KeepRule(.standard)))
        let paths = groups.flatMap(\.paths)
        XCTAssertFalse(paths.contains { $0.contains(".fcpbundle/") },
                       "a path inside an application database reached the result: \(paths)")
        // The two copies in the open do form a pair, so a scanner that finds
        // nothing fails here instead of passing for the wrong reason.
        XCTAssertEqual(groups.count, 1, "groups: \(groups)")
        XCTAssertEqual(Set(paths),
                       Set(["holiday.jpg", "holiday copy.jpg"].map { fixture.appendingPathComponent($0).path }),
                       "groups: \(groups)")
    }
}
