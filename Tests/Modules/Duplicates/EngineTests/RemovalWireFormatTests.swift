import XCTest
import HelmRuntime
@testable import Module_Duplicates_Engine

/// The same pin as `DiskRemovalWireFormatTests`, for the reply that says what a
/// removal did. It was a bare `HelmTrash.Result` until the removal learned to
/// stop: a stopped removal is a fourth outcome — not a success, not a refusal
/// and not silence — and it has to cross the wire as a named fact rather than
/// as zeroes a page reads as «nothing happened».
final class DuplicateRemovalWireFormatTests: XCTestCase {
    private let refusal = HelmTrash.Refusal(path: "/Users/me/Nope", reason: .outOfScope)

    func testEncodedKeysAreTheThreeThatWereAlwaysThereAndCancelled() throws {
        let data = try JSONEncoder().encode(
            DuplicateRemoval(removed: ["/a"], refused: [refusal], freedBytes: 42))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["removed", "refused", "freedBytes", "cancelled"])
        let refused = try XCTUnwrap(object["refused"] as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(refused.first).keys), ["path", "reason"])
    }

    /// A reply written before the removal could be stopped carries no
    /// `cancelled`, and a synthesised `Decodable` would refuse the whole
    /// document over the one missing key (CLAUDE.md § A `defaulted` property on
    /// a `Codable` payload). Missing means «it ran to the end».
    func testJSONFromBeforeTheCancelledFieldStillDecodes() throws {
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
        XCTAssertFalse(decoded.cancelled)
    }

    func testAStoppedRemovalSurvivesTheRoundTrip() throws {
        let stopped = DuplicateRemoval(removed: [], refused: [refusal],
                                       freedBytes: 0, cancelled: true)

        let decoded = try JSONDecoder().decode(
            DuplicateRemoval.self, from: JSONEncoder().encode(stopped))

        XCTAssertEqual(decoded, stopped)
        XCTAssertTrue(decoded.cancelled)
    }

    /// The engine builds this reply out of a `HelmTrash.Result`, and every field
    /// the result carries must arrive — a wrapper that drops a refusal on the
    /// way through is the silent discard the house rule forbids.
    func testEverythingTheTrashResultSaysSurvivesIntoTheRemoval() {
        let result = HelmTrash.Result(removed: ["/a"], refused: [refusal], freedBytes: 42)

        let removal = DuplicateRemoval(result, cancelled: false)

        XCTAssertEqual(removal.removed, result.removed)
        XCTAssertEqual(removal.refused, result.refused)
        XCTAssertEqual(removal.freedBytes, result.freedBytes)
        XCTAssertFalse(removal.cancelled)
    }
}
