import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// A file inside an application bundle is never offered as a duplicate.
///
/// **The promise was in prose and in a flag, and had no test under it.** The
/// walk's own documentation has said "package interiors are not entered —
/// offering half of an .app bundle as a duplicate invites breaking the app"
/// since it was written, and what enforced it was `.skipsPackageDescendants`
/// passed to `FileManager.enumerator`. When the walk moved to `BulkWalk` that
/// flag went with the enumerator, and nothing in the suite noticed: the whole
/// interior of every application under a scanned folder would have been offered
/// for deletion, with a green suite.
///
/// The sibling file next door covers the other half — an application *library*
/// this Mac has never registered a type for, which is judged by name because
/// LaunchServices cannot see it.
final class TheWalkDoesNotOpenAppBundlesTests: XCTestCase {

    func testAFileInsideAnApplicationBundleIsNeverOfferedAsADuplicate() throws {
        let root = scratchDirectory("dup-bundle")
        let payload = Data(repeating: 0x41, count: 1_200_000)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Thing.app/Contents/Resources"),
            withIntermediateDirectories: true)
        try payload.write(to: root.appendingPathComponent("holiday.jpg"))
        try payload.write(to: root.appendingPathComponent(
            "Thing.app/Contents/Resources/holiday.jpg"))

        // The precondition, stated: on a Mac where the system did not call this
        // a package the test would be measuring nothing.
        let bundle = root.appendingPathComponent("Thing.app")
        XCTAssertEqual(try bundle.resourceValues(forKeys: [.isPackageKey]).isPackage, true)

        let groups = try XCTUnwrap(DuplicateScanner().find(under: root.path,
                                                          by: KeepRule(.standard)))

        XCTAssertFalse(groups.flatMap(\.paths).contains { $0.contains(".app/") },
                       "a path inside an application bundle reached the result: \(groups)")
        // And the pair does not form at all, which is the honest outcome: the
        // copy in the open has nothing to be a duplicate of.
        XCTAssertTrue(groups.isEmpty, "groups: \(groups)")
    }
}
