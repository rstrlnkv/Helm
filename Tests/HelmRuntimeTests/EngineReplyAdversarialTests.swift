import Foundation
import HelmContract
import XCTest
@testable import HelmRuntime

/// The wire's JSON meeting bytes nobody meant to send.
///
/// `EngineReplyTests` covers the two shapes the helper was written for: a
/// payload that is not JSON at all, and a reply JSON cannot hold. This file is
/// the middle ground, which is where a wire actually fails — bytes that *are*
/// valid JSON and are the wrong thing, an event whose encoding failed after the
/// good one it would have replaced, and what the log line is allowed to carry
/// when the payload is the thing that broke.
///
/// **The control matters as much as the assertion.** The log is off in a test
/// process, so a test that only checked for an absent word would pass on a log
/// nobody wrote. Every test below proves the line it judges exists before it
/// judges it.
final class EngineReplyAdversarialTests: XCTestCase {

    /// One test below reproduces a claim the code does not keep. It is gated
    /// rather than weakened: `HELM_PINNED_DEFECTS=1 swift test` runs it.
    static let pinnedDefectsRun =
        ProcessInfo.processInfo.environment["HELM_PINNED_DEFECTS"] == "1"

    override func setUp() {
        super.setUp()
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private var engineLines: [String] {
        HelmLog.shared.recentEntries().filter { $0.category == "engine" }.map(\.message)
    }

    /// Shaped like the payloads that really cross: a path and a scan number
    /// (`ScanRequest`), and a list of paths (`[String]`, which four modules'
    /// trash arms take).
    private struct Request: Codable, Equatable { let path: String; let scan: Int }

    // MARK: - Valid JSON of the wrong thing

    /// The failure a wire has that a parser does not: bytes that parse, and mean
    /// something else. Every one of these is well-formed JSON, and none of them
    /// is a `Request` — so each must come back `nil` with a line, not as a value
    /// built out of whatever happened to fit.
    ///
    /// Run as a table with the input in the message: the arms answer `nil` on
    /// every failure, so a single-input test cannot tell "refused this one" from
    /// "refuses everything".
    func testValidJSONThatIsNotTheAskedForTypeIsRefusedRatherThanImprovised() {
        let wrong: [(String, String)] = [
            ("a JSON null", "null"),
            ("a bare number", "7"),
            ("a bare string", "\"/tmp\""),
            ("an array where an object goes", "[\"/tmp\", 0]"),
            ("the right keys, wrong value types", "{\"path\": 5, \"scan\": \"1\"}"),
            ("a key missing", "{\"path\": \"/tmp\"}"),
            ("an object of objects", "{\"path\": {\"path\": \"/tmp\"}, \"scan\": 0}"),
        ]
        for (what, json) in wrong {
            HelmLog.shared.clearTail()
            let command = EngineCommand(name: "scan", payload: Data(json.utf8))

            XCTAssertNil(EngineReply.decode(Request.self, from: command),
                         "\(what) came back as a value")
            XCTAssertTrue(engineLines.contains { $0.contains("scan") && $0.contains("Request") },
                          "\(what) was refused in silence, which is the state this helper "
                          + "exists to end: \(engineLines)")
        }
    }

    /// And the other side of that line: JSON that carries *more* than the arm
    /// asked for still decodes. An older build's command reaching a newer engine
    /// is the ordinary case, and refusing it would break every rolling upgrade.
    func testAPayloadCarryingMoreThanTheArmAsksForStillReads() {
        let json = "{\"path\": \"/tmp\", \"scan\": 3, \"reason\": \"manual\"}"
        let command = EngineCommand(name: "scan", payload: Data(json.utf8))

        XCTAssertEqual(EngineReply.decode(Request.self, from: command),
                       Request(path: "/tmp", scan: 3))
        XCTAssertTrue(engineLines.isEmpty, "a readable payload is not an event: \(engineLines)")
    }

    /// A list arm (`[String]` — the trash arms of four modules) handed a list
    /// with one bad element refuses the **whole** list. Trashing the elements
    /// that did parse would be a partial removal nobody asked for and no screen
    /// could describe.
    func testAListWithOneBadElementIsRefusedWholeRatherThanInPart() {
        let json = "[\"/tmp/a.bin\", \"/tmp/b.bin\", 5]"
        let command = EngineCommand(name: "trash", payload: Data(json.utf8))

        XCTAssertNil(EngineReply.decode([String].self, from: command))
        XCTAssertFalse(engineLines.isEmpty, "nothing was written, so this proves nothing")
    }

    // MARK: - What the failure line may carry

    /// **The account name never reaches the log, whatever the payload is made
    /// of.** `HelmFailure.describe` puts `String(describing:)` of a Swift error
    /// into the line, and a `DecodingError`'s description contains its coding
    /// path — which for an object-shaped payload is a key the *sender* chose. A
    /// key that is an absolute path therefore arrives in the line, and the home
    /// directory is the one part of a path that is never allowed to.
    ///
    /// The real home is used, because that is the string the redaction knows;
    /// a made-up one would test nothing. The leaf is asserted present first, so
    /// "the account name is absent" cannot be green because the line is.
    func testTheAccountNameCannotReachTheLogThroughACodingPath() throws {
        let home = NSHomeDirectory()
        try XCTSkipIf(home.isEmpty || !home.hasPrefix("/Users/"),
                      "no ordinary home directory here to redact")
        let account = URL(fileURLWithPath: home).lastPathComponent
        let leaf = "tax-return-\(UUID().uuidString).pdf"
        let key = home + "/Documents/" + leaf
        let command = EngineCommand(name: "trash",
                                    payload: Data("{\"\(key)\": \"not-a-number\"}".utf8))

        XCTAssertNil(EngineReply.decode([String: Int].self, from: command))
        XCTAssertTrue(engineLines.contains { $0.contains(leaf) },
                      "the coding path did not reach the line at all, so the assertion "
                      + "below is about a line that says nothing: \(engineLines)")
        XCTAssertFalse(engineLines.contains { $0.contains("/Users/" + account) },
                       "the log carries the account name: \(engineLines)")
    }

    /// DEFECT (pinned, gated): `EngineReply`'s own doc comment states the rule
    /// absolutely — "The line carries the command and the type it wanted, never
    /// the payload." It does not. `HelmFailure.describe` appends
    /// `String(describing: error)` for any error that is not an `NSError`
    /// subclass, and `DecodingError`/`EncodingError` are Swift enums: their
    /// description carries the coding path, and for an object-shaped payload
    /// every key in that path came out of the bytes the sender sent.
    ///
    /// Latent rather than live — no arm decodes a `[String: T]` today, so what
    /// leaks now is only a key name a struct declared. It is one payload shape
    /// away from live, and the shape is an ordinary one (a table keyed by path
    /// is how `HashCache` and `appSizes` are already written), which is why the
    /// invariant is worth a test rather than a note.
    ///
    /// The redaction that does hold is `testTheAccountNameCannotReachTheLog…`
    /// above; this is the stronger claim the comment makes.
    func testTheRefusalCarriesNoPartOfThePayloadAtAll() throws {
        try XCTSkipUnless(EngineReplyAdversarialTests.pinnedDefectsRun,
                          "DEFECT: the decode-failure line carries the payload's own keys "
                          + "via String(describing: DecodingError) in HelmFailure.describe. "
                          + "Latent: no arm decodes a dictionary today.")

        let secret = "/Volumes/Backup/tax-return-\(UUID().uuidString).pdf"
        let command = EngineCommand(name: "trash",
                                    payload: Data("{\"\(secret)\": \"x\"}".utf8))

        XCTAssertNil(EngineReply.decode([String: Int].self, from: command))
        XCTAssertFalse(engineLines.isEmpty, "nothing was written, so this proves nothing")
        XCTAssertFalse(engineLines.contains { $0.contains(secret) },
                       "the refusal line carries the payload: \(engineLines)")
    }

    // MARK: - The replay slot

    /// The consequence the `emit` helper was written for, asserted where it is
    /// actually felt: **a page opened after the failure**.
    ///
    /// `LocalTransport` keeps the last event per name to replay to late
    /// subscribers, so an event whose payload would not encode must not reach
    /// that slot — the sixth engine's `?? Data()` put an undecodable event
    /// there, and the next page to open was handed a state it could not read.
    /// The existing test watches a live subscriber and sees the bad event never
    /// arrive; this one subscribes *afterwards*, which is the case the slot
    /// exists for and the one the defect broke.
    func testALateSubscriberIsReplayedTheLastGoodStateAndNotTheFailedOne() async throws {
        let transport = LocalTransport()

        transport.emit("state", encoding: Request(path: "/first", scan: 1))
        transport.emit("state", encoding: Request(path: "/second", scan: 2))
        transport.emit("state", encoding: Seconds(seconds: .nan))

        // Taken synchronously and after the emits: `AsyncStream`'s build closure
        // runs on construction and yields the replay under the transport's lock,
        // so the first element is the replayed slot and not a race.
        var replayed: EngineEvent?
        for await event in transport.events {
            replayed = event
            break
        }

        let event = try XCTUnwrap(replayed, "nothing was replayed, so this proves nothing")
        XCTAssertEqual(event.name, "state")
        XCTAssertEqual(try JSONDecoder().decode(Request.self, from: event.payload),
                       Request(path: "/second", scan: 2),
                       "the replay slot holds the event that failed to encode — every page "
                       + "opened from now on is handed a state it cannot read")
        XCTAssertTrue(engineLines.contains { $0.contains("state") && $0.contains("Seconds") },
                      "the failed encoding was not written down: \(engineLines)")
    }

    /// A second name must not be collateral. The failure is per event name, and
    /// an engine emitting two kinds — Homebrew's streaming `opLog` beside its
    /// level-triggered `opState` — must keep the other one's slot intact.
    func testAFailedEncodingDoesNotDisturbAnotherEventsSlot() async throws {
        let transport = LocalTransport()

        transport.emit("opState", encoding: Request(path: "/running", scan: 9))
        transport.emit("opLog", encoding: Seconds(seconds: .infinity))

        var byName: [String: EngineEvent] = [:]
        for await event in transport.events {
            byName[event.name] = event
            break
        }

        XCTAssertEqual(byName.keys.sorted(), ["opState"],
                       "the replay carries \(byName.keys.sorted()) — an event that was "
                       + "never emitted took a slot")
        XCTAssertEqual(try byName["opState"].map {
            try JSONDecoder().decode(Request.self, from: $0.payload)
        }, Request(path: "/running", scan: 9))
    }

    /// An empty reply is what an arm sends when it has nothing to say, and it
    /// has to survive the round trip as itself: `decode` of an empty payload is
    /// a refusal with a line, never a default-constructed value. Pinned beside
    /// the encode side, which answers those same zero bytes for a value JSON
    /// cannot hold — the two are indistinguishable on the wire by design, and
    /// the log is the only place they differ.
    func testTheTwoWaysZeroBytesHappenAreBothWrittenDown() {
        XCTAssertTrue(EngineReply.encode(Seconds(seconds: .nan),
                                         for: EngineCommand(name: "scan")).isEmpty)
        XCTAssertNil(EngineReply.decode(Request.self,
                                        from: EngineCommand(name: "scan", payload: Data())))
        XCTAssertEqual(engineLines.count, 2,
                       "one of the two zero-byte replies left no trace: \(engineLines)")
        XCTAssertTrue(engineLines.contains { $0.contains("not encoded") }, "\(engineLines)")
        XCTAssertTrue(engineLines.contains { $0.contains("not read as") }, "\(engineLines)")
    }

    private struct Seconds: Encodable { let seconds: Double }
}
