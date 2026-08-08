import XCTest
import HelmRuntime
@testable import Module_Leftovers_Engine

/// `LeftoversRemoval` crosses the transport as JSON — the engine encodes it, the
/// view model decodes it — so its field names are a wire format, not an
/// implementation detail.
///
/// It was a copy of `HelmTrash.Result` with two renames: `failed` for `refused`,
/// and a `message` that carried `reason.rawValue`, which the page then handed to
/// `TrashReasonText.sentence` to turn back into words. The engine built the real
/// result and unpacked it field by field into that copy. Both ends of this wire
/// are in one build and the UI target imports the engine, so one declaration can
/// serve both — the rule CLAUDE.md states as payload-declared-once.
///
/// Asserting the *keys* rather than a size or a byte count: the point is which
/// names are on the wire, and a length would pass for the wrong reasons.
final class LeftoversRemovalWireFormatTests: XCTestCase {
    private let refusal = HelmTrash.Refusal(path: "/Users/x/Documents/thesis.txt",
                                            reason: .outOfScope)

    func testTheRemovalIsTheSharedResultRatherThanACopyOfIt() {
        XCTAssertTrue(LeftoversRemoval.self == HelmTrash.Result.self,
                      "the payload is declared twice, so the engine has to keep two "
                      + "shapes in step by hand")
    }

    func testEncodedKeysAreTheSharedOnes() throws {
        let data = try JSONEncoder().encode(
            LeftoversRemoval(removed: ["/a"], refused: [refusal], freedBytes: 42))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["removed", "refused", "freedBytes"])
        let refused = try XCTUnwrap(object["refused"] as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(refused.first).keys), ["path", "reason"])
    }

    /// One declaration means the round trip is exact rather than field-for-field
    /// hopeful: what the shared loop answered is what the view model reads.
    func testWhatTheSharedLoopAnsweredIsWhatArrives() throws {
        let result = HelmTrash.Result(removed: ["/a"], refused: [refusal], freedBytes: 42)

        let back = try JSONDecoder().decode(LeftoversRemoval.self,
                                           from: try JSONEncoder().encode(result))

        XCTAssertEqual(back, result)
        XCTAssertEqual(back.refused.map(\.reason), [.outOfScope])
        XCTAssertEqual(back.failed, ["/Users/x/Documents/thesis.txt"])
    }
}
