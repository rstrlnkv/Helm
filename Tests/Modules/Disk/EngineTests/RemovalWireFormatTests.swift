import XCTest
import HelmRuntime
@testable import Module_Disk_Engine

/// `DiskRemoval` crosses the transport as JSON — the engine encodes it, the view
/// model decodes it — so its field names are a wire format, not an
/// implementation detail. It became an alias for `HelmTrash.Result`, which it
/// had been a field-for-field copy of; these pin the thing that change was not
/// allowed to touch.
///
/// Asserting the *keys* rather than a size or a byte count: the point is which
/// names are on the wire, and a length would pass for the wrong reasons.
final class DiskRemovalWireFormatTests: XCTestCase {
    private let refusal = HelmTrash.Refusal(path: "/Volumes/Big/Nope", reason: .outOfScope)

    func testEncodedKeysAreExactlyTheThreeThatWereAlwaysThere() throws {
        let data = try JSONEncoder().encode(
            DiskRemoval(removed: ["/a"], refused: [refusal], freedBytes: 42))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["removed", "refused", "freedBytes"])
        let refused = try XCTUnwrap(object["refused"] as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(refused.first).keys), ["path", "reason"])
    }

    /// JSON written before the alias must still decode after it. The literal is
    /// spelled out rather than round-tripped from the type, so the type cannot
    /// quietly redefine what "unchanged" means.
    func testJSONFromBeforeTheAliasStillDecodes() throws {
        let json = Data("""
        {"removed":["/a","/b"],\
        "refused":[{"path":"/Volumes/Big/Nope","reason":"outOfScope"}],\
        "freedBytes":42}
        """.utf8)

        let decoded = try JSONDecoder().decode(DiskRemoval.self, from: json)

        XCTAssertEqual(decoded.removed, ["/a", "/b"])
        XCTAssertEqual(decoded.refused, [refusal])
        XCTAssertEqual(decoded.freedBytes, 42)
        XCTAssertEqual(decoded.failed, ["/Volumes/Big/Nope"])
    }

    /// The engine builds a `HelmTrash.Result` and hands it back as a
    /// `DiskRemoval`. If those two ever stop agreeing on the wire, the unwrap
    /// and re-wrap that used to sit between them was load-bearing after all.
    func testTheEngineResultAndTheRemovalEncodeAlike() throws {
        let result = HelmTrash.Result(removed: ["/a"], refused: [refusal], freedBytes: 42)
        let removal = DiskRemoval(removed: ["/a"], refused: [refusal], freedBytes: 42)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(result), try encoder.encode(removal))
    }
}
