import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The thin decidable part of the preview: which file it would show. The panel
/// itself is AppKit responder-chain plumbing and is checked in the running app.
final class DuplicatePreviewTests: XCTestCase {
    private func group(_ paths: [String]) -> DuplicateGroup {
        DuplicateGroup(bytes: 1_000_000, paths: paths)
    }

    func testTheSelectedPathIsTheTarget() {
        let url = DuplicatePreview.target(selection: "/tmp/a2", in: [group(["/tmp/a1", "/tmp/a2"])])
        XCTAssertEqual(url?.path, "/tmp/a2")
    }

    func testNothingSelectedIsNothingToShow() {
        XCTAssertNil(DuplicatePreview.target(selection: nil, in: [group(["/tmp/a1"])]))
    }

    /// A copy that has just been trashed leaves the groups while the selection
    /// still names it. Opening a panel onto a file that is gone shows an empty
    /// frame with no explanation.
    func testAPathThatHasLeftTheGroupsIsNotShown() {
        XCTAssertNil(DuplicatePreview.target(selection: "/tmp/gone",
                                             in: [group(["/tmp/a1", "/tmp/a2"])]))
    }

    func testAnEmptyResultShowsNothing() {
        XCTAssertNil(DuplicatePreview.target(selection: "/tmp/a1", in: []))
    }
}
