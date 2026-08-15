import XCTest
@testable import Module_Duplicates_Engine

/// The duplicate finder does not look inside an application's own database.
///
/// **The fixture uses `.fcpbundle`, and the choice was measured rather than
/// guessed.** `.skipsPackageDescendants`, which this walk already passes to the
/// enumerator, asks LaunchServices whether the type is registered on *this*
/// Mac. Probed 2026-08-03 by creating one directory per extension and reading
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
        let fm = FileManager.default
        fixture = fm.temporaryDirectory
            .appendingPathComponent("helm-dup-library-\(UUID().uuidString)")
        try fm.createDirectory(at: fixture.appendingPathComponent("Final Cut.fcpbundle/Masters"),
                               withIntermediateDirectories: true)
        // Two identical files above the 1 MB floor: one in the open, one inside
        // the library. They are a pair only if the library is walked.
        let payload = Data(repeating: 0x41, count: 1_200_000)
        try payload.write(to: fixture.appendingPathComponent("holiday.jpg"))
        try payload.write(to: fixture.appendingPathComponent("Final Cut.fcpbundle/Masters/holiday.jpg"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
    }

    func testAFileInsideALibraryIsNeverOfferedAsADuplicate() throws {
        let groups = try XCTUnwrap(DuplicateScanner().find(under: fixture.path, by: KeepRule(.standard)))
        let paths = groups.flatMap(\.paths)
        XCTAssertFalse(paths.contains { $0.contains(".fcpbundle/") },
                       "a path inside an application database reached the result: \(paths)")
        // And the pair does not form at all, which is the honest outcome: the
        // copy in the open has nothing to be a duplicate of.
        XCTAssertTrue(groups.isEmpty, "groups: \(groups)")
    }
}
