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

    /// **It crosses the transport as JSON**, and a computed property is not
    /// encoded — so the refused paths now travel inside `failures` and nowhere
    /// else. Both ends are this one type, which is what makes that safe, and
    /// this is the check that says so rather than the reasoning that says so.
    func testTheRefusedPathsSurviveTheJSONHop() throws {
        let sent = UninstallResult(
            trashed: ["/moved"], freedBytes: 12,
            failures: [TrashFailureInfo(path: "/locked",
                                        reason: .needsFullDiskAccess,
                                        message: "macOS said no")])

        let back = try JSONDecoder().decode(UninstallResult.self,
                                            from: try JSONEncoder().encode(sent))

        XCTAssertEqual(back, sent)
        XCTAssertEqual(back.failed, ["/locked"])
        XCTAssertEqual(back.failures.first?.message, "macOS said no")
    }

    /// The reason on the wire is the word, whether the field holds a string or
    /// the enum it was always the raw value of. This is the check that let that
    /// field become the enum: JSON written before it must still decode, and what
    /// goes out must still be the same three keys with the same word in them.
    func testTheReasonTravelsAsItsOwnWordEitherWay() throws {
        let json = Data("""
        {"trashed":["/moved"],"freedBytes":12,\
        "failures":[{"path":"/locked","reason":"needsFullDiskAccess","message":"macOS said no"}]}
        """.utf8)

        let decoded = try JSONDecoder().decode(UninstallResult.self, from: json)

        XCTAssertEqual(decoded.failures.map(\.reason), [.needsFullDiskAccess])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(decoded)) as? [String: Any])
        let failures = try XCTUnwrap(object["failures"] as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(failures.first).keys), ["path", "reason", "message"])
        XCTAssertEqual(failures.first?["reason"] as? String, "needsFullDiskAccess")
    }
}
