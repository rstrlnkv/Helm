import XCTest
@testable import Module_Duplicates_Engine

/// The search request gained a field, and a payload written before it existed
/// still has to arrive as a search.
///
/// The same pin as `DuplicateRemovalWireFormatTests`, for the other half of this
/// module's wire — and against the trap `DuplicateFindings` and
/// `KeepAwakeEngine.StatePayload` both fell into: a non-optional property with a
/// stored default does **not** make an older document decode. The synthesised
/// `Decodable` demands the key whatever the property's initial value is, and
/// `JSONDecoder` abandons the whole document rather than the one field — so a
/// search sent by a caller that predates the policy would arrive as no search at
/// all, which this module reads as a cancellation.
final class DuplicateSearchRequestWireFormatTests: XCTestCase {

    private let decoder = JSONDecoder()

    func testAPayloadFromBeforeThePolicyStillDecodesAsASearch() throws {
        let request = try decoder.decode(DuplicateSearchRequest.self,
                                         from: Data(#"{"path":"/Users/me/Pictures"}"#.utf8))

        XCTAssertEqual(request.path, "/Users/me/Pictures")
        XCTAssertNil(request.policy, "no policy is «the caller did not say»")
        XCTAssertNil(request.keepPolicy)
    }

    func testAPolicyOnTheWireArrivesAsTheOneItNames() throws {
        let request = try decoder.decode(
            DuplicateSearchRequest.self,
            from: Data(#"{"path":"/Users/me/Pictures","policy":"date"}"#.utf8))

        XCTAssertEqual(request.keepPolicy, .byDate)
    }

    /// A build that has never heard of the value falls back to what it knows,
    /// rather than throwing the search away. This is why the field is a string
    /// on the wire and an enum at both ends of it.
    func testASpellingThisBuildDoesNotKnowIsNoPolicyRatherThanNoSearch() throws {
        let request = try decoder.decode(
            DuplicateSearchRequest.self,
            from: Data(#"{"path":"/Users/me/Pictures","policy":"by-the-moon"}"#.utf8))

        XCTAssertEqual(request.path, "/Users/me/Pictures")
        XCTAssertNil(request.keepPolicy)
    }

    /// The caller names the policy, never its spelling: the encoded value is the
    /// enum's own, so a request cannot carry a word the engine will not
    /// recognise.
    func testWhatTheCallerEncodesIsTheStoredSpellingOfThePolicy() throws {
        let encoded = try JSONEncoder().encode(
            DuplicateSearchRequest(path: "/Users/me/Pictures", policy: .byPlace))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["policy"] as? String, KeepPolicy.byPlace.rawValue)
        XCTAssertEqual(Set(object.keys), ["path", "policy"])
    }

    func testARequestWithNoPolicyRoundTripsAsOne() throws {
        let encoded = try JSONEncoder().encode(DuplicateSearchRequest(path: "/x"))
        let decoded = try decoder.decode(DuplicateSearchRequest.self, from: encoded)

        XCTAssertNil(decoded.keepPolicy)
        XCTAssertEqual(decoded.path, "/x")
    }
}
