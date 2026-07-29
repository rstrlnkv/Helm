import XCTest
import HelmRuntime
@testable import Module_Duplicates_Engine

/// The same pin as `DiskRemovalWireFormatTests`, for the other engine that
/// built a `HelmTrash.Result` and re-wrapped it in a copy of itself.
final class DuplicateRemovalWireFormatTests: XCTestCase {
    private let refusal = HelmTrash.Refusal(path: "/Users/me/Nope", reason: .outOfScope)

    func testEncodedKeysAreExactlyTheThreeThatWereAlwaysThere() throws {
        let data = try JSONEncoder().encode(
            DuplicateRemoval(removed: ["/a"], refused: [refusal], freedBytes: 42))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["removed", "refused", "freedBytes"])
        let refused = try XCTUnwrap(object["refused"] as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(refused.first).keys), ["path", "reason"])
    }

    func testJSONFromBeforeTheAliasStillDecodes() throws {
        let json = Data("""
        {"removed":["/a","/b"],\
        "refused":[{"path":"/Users/me/Nope","reason":"outOfScope"}],\
        "freedBytes":42}
        """.utf8)

        let decoded = try JSONDecoder().decode(DuplicateRemoval.self, from: json)

        XCTAssertEqual(decoded.removed, ["/a", "/b"])
        XCTAssertEqual(decoded.refused, [refusal])
        XCTAssertEqual(decoded.freedBytes, 42)
        XCTAssertEqual(decoded.failed, ["/Users/me/Nope"])
    }

    func testTheEngineResultAndTheRemovalEncodeAlike() throws {
        let result = HelmTrash.Result(removed: ["/a"], refused: [refusal], freedBytes: 42)
        let removal = DuplicateRemoval(removed: ["/a"], refused: [refusal], freedBytes: 42)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(result), try encoder.encode(removal))
    }
}
