import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// The duplicate finder does not look inside an application's own database.
///
/// **The fixture uses `.fcpbundle`.** `isPackage`, which the walk asks of a
/// directory after the rule by name, asks LaunchServices whether the type is
/// registered on *this* Mac. Types whose apps ship with macOS, such as
/// `photoslibrary` or `musiclibrary`, read as packages, so a test written with
/// them passes whether or not the rule exists. `fcpbundle` reads as a plain
/// directory where Final Cut is not installed, which is the case the rule
/// exists for: an application database whose application this Mac has never
/// seen is a plain directory to LaunchServices and a database to everybody else.
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
