import Foundation
import HelmRuntime
import XCTest
@testable import Module_Uninstaller_Engine

/// `UninstallResult` carried the refused paths twice: `failed` as bare strings
/// and `failures` as the same paths with a reason. `trashSync` appends to both
/// on both of its refusal branches, in the same order, so they have never
/// disagreed — and the screens read one each. `TrashedLeftoversView` decides
/// which apps a removal answered for from `failed`, and the review report lists
/// `failures`.
///
/// Nothing kept them in step but the two lines being next to each other. A
/// result whose `failed` omitted a path its `failures` recorded would take an
/// app off every screen Helm has as the person's own "no", while the report
/// beside it said macOS had refused.
final class RefusedPathsAreOneListTests: XCTestCase {

    func testTheRefusedPathsAreExactlyTheFailures() {
        let result = UninstallResult(
            trashed: ["/moved"],
            freedBytes: 12,
            failures: [TrashFailureInfo(path: "/locked",
                                        reason: .needsFullDiskAccess),
                       TrashFailureInfo(path: "/outside",
                                        reason: .outOfScope)])

        XCTAssertEqual(result.failed, ["/locked", "/outside"])
    }

    /// Nothing refused is an empty list and not a missing one — the caller wraps
    /// it in a `Set` and asks the question of every app it has.
    func testNothingRefusedIsAnEmptyList() {
        XCTAssertEqual(UninstallResult(trashed: ["/a"], freedBytes: 1).failed, [])
    }

    /// And the order is the order the refusals were recorded in, because the log
    /// line and the report are read side by side.
    func testTheOrderIsTheOrderTheRefusalsCameIn() {
        let paths = ["/c", "/a", "/b"]
        let result = UninstallResult(
            trashed: [], freedBytes: 0,
            failures: paths.map { TrashFailureInfo(path: $0,
                                                   reason: .systemRefused) })

        XCTAssertEqual(result.failed, paths)
    }
}
