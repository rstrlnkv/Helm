import XCTest
@testable import Module_KeepAwake_Engine

/// `StatePayload.init(from:)` exists for one promise, and it keeps it for four
/// fields out of five.
///
/// The hand-written decoder was put there because five `defaulted` properties
/// did not decode an older document — a synthesised `Decodable` requires the
/// key whatever initial value the property has, and `JSONDecoder` then gives up
/// on the *whole* payload, so one missing key leaves every screen holding its
/// defaults for ever. Its own comment names the split it makes: «The six fields
/// that were there from the first version are decoded outright.»
///
/// There were five, not six. `git show v0.9.0:…/KeepAwakeEngine.swift` has the
/// released declaration — `isActive`, `conditions`, `clamshellActive`,
/// `endDate`, `startDate` — and `suppressed` arrived on 2026-08-09 in
/// «a suppressed rule says so instead of looking like a Mac that just slept»,
/// three weeks after that tag. It is decoded with `try decode`, so the payload
/// the last release actually spoke is the one document this decoder throws on:
/// the defect the decoder was written to end, surviving inside it, in the field
/// that was added at the same time as the repair.
///
/// The wire is in-process today, so nothing crosses builds *yet* — which is
/// exactly why this is a test rather than a bug report. The next field added
/// under the same comment is the one that costs something, and the second case
/// here fails on it mechanically rather than on somebody re-reading the list.
final class APayloadFromTheLastReleaseDecodesTests: XCTestCase {

    /// The five names v0.9.0 shipped. Anything else in the encoded payload
    /// arrived after the wire did and has to survive its own absence.
    private let shippedInTheLastRelease: Set<String> =
        ["isActive", "conditions", "clamshellActive", "endDate", "startDate"]

    private func fullPayloadKeys() throws -> (json: [String: Any], data: Data) {
        let payload = KeepAwakeEngine.StatePayload(
            isActive: true, conditions: ["manual"], clamshellActive: false,
            endDate: Date(timeIntervalSinceReferenceDate: 1000),
            startDate: Date(timeIntervalSinceReferenceDate: 0),
            suppressed: false, triggeredConditions: ["app"], holdingApps: ["com.example.render"],
            batteryStopped: false, lidRefused: false, lidGrantRemains: false)
        let data = try JSONEncoder().encode(payload)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (object, data)
    }

    /// The control, and it has to come first: the harness encodes something a
    /// decoder accepts at all. Every «this still decodes» below is worthless if
    /// the whole payload does not.
    func testTheWholePayloadDecodes() throws {
        let (_, data) = try fullPayloadKeys()
        let decoded = try JSONDecoder().decode(KeepAwakeEngine.StatePayload.self, from: data)
        XCTAssertTrue(decoded.isActive)
        XCTAssertEqual(decoded.holdingApps, ["com.example.render"])
    }

    /// The document v0.9.0 put on the wire, written out as that release wrote
    /// it. A build reading this one has to come back with a screen, not with
    /// nothing.
    func testThePayloadTheLastReleaseSpokeStillDecodes() throws {
        let released = Data("""
        {"isActive":true,"conditions":["manual"],"clamshellActive":false}
        """.utf8)

        let decoded = try JSONDecoder().decode(KeepAwakeEngine.StatePayload.self, from: released)

        XCTAssertTrue(decoded.isActive, "the whole payload was dropped over one absent key")
        XCTAssertEqual(decoded.conditions, ["manual"])
        // And the fields that release could not have meant read as «nothing to
        // report», which is the reading that shows no caption rather than the
        // wrong one.
        XCTAssertFalse(decoded.suppressed)
        XCTAssertFalse(decoded.batteryStopped)
        XCTAssertEqual(decoded.triggeredConditions, [])
    }

    /// Mechanical, so that a field added tomorrow needs no reader: every key in
    /// the encoded payload that v0.9.0 did not have is removed on its own, and
    /// the rest must still decode.
    func testEveryFieldAddedSinceThatReleaseDecodesWhenAbsent() throws {
        let (object, _) = try fullPayloadKeys()
        let late = object.keys.filter { !shippedInTheLastRelease.contains($0) }
        XCTAssertFalse(late.isEmpty, "the payload has gained nothing since v0.9.0, "
                       + "which would make this case vacuous")

        for key in late {
            var trimmed = object
            trimmed.removeValue(forKey: key)
            let data = try JSONSerialization.data(withJSONObject: trimmed)
            XCTAssertNoThrow(
                try JSONDecoder().decode(KeepAwakeEngine.StatePayload.self, from: data),
                "a payload without «\(key)» decodes to nothing at all, and every screen "
                + "keeps its defaults for ever")
        }
    }

    /// The other side of the same rule, so the repair cannot be «make
    /// everything optional»: a document without `isActive` is not an older
    /// payload, it is not this payload, and decoding it to a default would put
    /// «not holding» on screen for a Mac that is.
    func testAPayloadMissingOneOfTheOriginalFieldsIsStillRefused() throws {
        let (object, _) = try fullPayloadKeys()
        for key in shippedInTheLastRelease where key != "endDate" && key != "startDate" {
            var trimmed = object
            trimmed.removeValue(forKey: key)
            let data = try JSONSerialization.data(withJSONObject: trimmed)
            XCTAssertThrowsError(
                try JSONDecoder().decode(KeepAwakeEngine.StatePayload.self, from: data),
                "«\(key)» was there from the first version; a document without it is not "
                + "this payload")
        }
    }
}
