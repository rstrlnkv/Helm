import Foundation
import HelmContract
import XCTest
@testable import HelmRuntime

/// The engine side of the transport's JSON, and what it does when the JSON
/// fails.
///
/// The failure is the point. Every one of the nine engines spelled
/// `(try? JSONEncoder().encode(x)) ?? Data()` and
/// `guard let y = try? JSONDecoder().decode(…) else { return Data() }` by hand,
/// so a payload that could not be read and an arm that answers nothing left the
/// same empty reply and the same silence — `TransportClient`'s own doc
/// comment says a typo is then indistinguishable from a refusal, and the symptom
/// is a feature that quietly does nothing.
///
/// **The control matters as much as the assertion.** The log is off in a test
/// process (`LogPolicy` keeps it off for a build that is not `-dev`), so a test
/// that only checked a word was absent would pass on a log nobody wrote. Each
/// test below proves the line it judges exists.
final class EngineReplyTests: XCTestCase {

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

    private struct Request: Codable, Equatable { let path: String }
    private struct Seconds: Encodable { let seconds: Double }

    // MARK: - decode

    func testAPayloadOfTheAskedForTypeComesBack() throws {
        let command = EngineCommand(name: "scan",
                                   payload: try JSONEncoder().encode(Request(path: "/tmp")))

        XCTAssertEqual(EngineReply.decode(Request.self, from: command), Request(path: "/tmp"))
        XCTAssertTrue(engineLines.isEmpty, "a payload that read cleanly is not an event: \(engineLines)")
    }

    func testAPayloadThatCannotBeReadIsNilAndSaysSoUnderTheCommandsName() {
        let command = EngineCommand(name: "scan", payload: Data("{}".utf8))

        XCTAssertNil(EngineReply.decode(Request.self, from: command))
        XCTAssertTrue(engineLines.contains { $0.contains("scan") && $0.contains("Request") },
                      "nothing was written, so the refusal is still indistinguishable "
                      + "from a decline: \(engineLines)")
    }

    /// An empty payload is the ordinary shape of a command that carries none, so
    /// it is refused exactly like any other unreadable one — no special case that
    /// would let a missing payload through as a default value.
    func testAnEmptyPayloadIsRefusedLikeAnyOther() {
        XCTAssertNil(EngineReply.decode(Request.self, from: EngineCommand(name: "scan")))
        XCTAssertFalse(engineLines.isEmpty)
    }

    /// A payload names somebody's files. The log carries no names, so the line
    /// about it carries the command and the type it wanted — never the bytes.
    func testTheRefusalDoesNotCarryThePayload() {
        let secret = "/Users/someone/Documents/tax-return-\(UUID().uuidString).pdf"
        let command = EngineCommand(name: "trash", payload: Data("[\"\(secret)\"]".utf8))

        XCTAssertNil(EngineReply.decode(Request.self, from: command))
        XCTAssertFalse(engineLines.isEmpty, "nothing was written, so this proves nothing")
        XCTAssertFalse(engineLines.contains { $0.contains(secret) },
                       "the log carries the payload: \(engineLines)")
    }

    // MARK: - encode

    func testAValueComesBackAsItsJSON() throws {
        let data = EngineReply.encode(Request(path: "/tmp"), for: EngineCommand(name: "scan"))

        XCTAssertEqual(try JSONDecoder().decode(Request.self, from: data), Request(path: "/tmp"))
        XCTAssertTrue(engineLines.isEmpty, "\(engineLines)")
    }

    /// `JSONEncoder` refuses a non-conforming float, and `ScanResult.seconds` is
    /// a `TimeInterval` — this is reachable, not theoretical. The reply is the
    /// same empty `Data` a refusal sends, and the log is what tells them apart.
    func testAValueJSONCannotHoldAnswersEmptyAndSaysSoUnderTheCommandsName() {
        let data = EngineReply.encode(Seconds(seconds: .nan), for: EngineCommand(name: "scan"))

        XCTAssertTrue(data.isEmpty)
        XCTAssertTrue(engineLines.contains { $0.contains("scan") && $0.contains("Seconds") },
                      "an unencodable reply went out as silence: \(engineLines)")
    }

    // MARK: - events

    /// The other half of the same plumbing: five engines wrote
    /// `if let data = try? JSONEncoder().encode(x) { emit(EngineEvent(…)) }` and a
    /// sixth wrote `?? Data()` instead, which put an *undecodable* event in the
    /// replay slot for that name — so a page opened afterwards was handed a state
    /// it could not read.
    ///
    /// Arrival is asserted by name and in order, not by count: an assertion that
    /// something is absent passes when nothing happened at all, so the two events
    /// that must arrive are named beside the one that must not.
    func testAnEventCarriesItsValueAndAnUnencodableOneIsNotEmittedAtAll() async throws {
        let transport = LocalTransport()
        // Taken before the emits, and synchronously: `AsyncStream`'s build
        // closure runs on construction, so the subscriber is registered on this
        // line. Subscribing inside a `Task` would race the emits, and the replay
        // would then hand it only the last event of that name — the test would
        // hang waiting for a second one.
        let events = transport.events

        transport.emit("state", encoding: Request(path: "/first"))
        transport.emit("state", encoding: Seconds(seconds: .infinity))
        transport.emit("state", encoding: Request(path: "/second"))

        var received: [EngineEvent] = []
        for await event in events {
            received.append(event)
            if received.count == 2 { break }
        }

        XCTAssertEqual(received.map(\.name), ["state", "state"])
        XCTAssertEqual(try received.map { try JSONDecoder().decode(Request.self, from: $0.payload) },
                       [Request(path: "/first"), Request(path: "/second")],
                       "the event JSON cannot hold ±∞, so nothing should have gone out for it")
        XCTAssertTrue(engineLines.contains { $0.contains("state") && $0.contains("Seconds") },
                      "an event that could not be encoded vanished silently: \(engineLines)")
    }
}
