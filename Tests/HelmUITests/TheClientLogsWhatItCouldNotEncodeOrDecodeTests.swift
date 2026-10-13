import Foundation
import HelmContract
import HelmRuntime
import HelmUI
import XCTest

/// The screen's side of the wire, and what it does with bytes it cannot read.
///
/// `TransportClient` spelled `(try? JSONEncoder().encode(payload)) ?? Data()` three
/// times and `try? JSONDecoder().decode(…)` once. A payload that would not encode
/// went out as empty `Data`, and a reply that would not decode came back as
/// `nil`, which a screen reads as "the module could not answer". The client wrote
/// neither down. The engine's half (`EngineReply`) writes down a payload it
/// cannot read, an empty one included, and a reply it cannot encode; its line
/// names the engine's arm and not the screen that sent the payload.
///
/// **What is pinned, and what is not.** A refusal leaves exactly one `error` line
/// under the category `client`, and the line holds the command's name and the
/// type's name. It holds no payload byte and no reply byte: a payload and a reply
/// name somebody's files. The wording after the type's name is not pinned, but
/// nothing the failure carries from the wire may be in it — each reply
/// `refuseTheReply` is handed under (B), the throwing payload under (A) and every
/// row under (E) hold a recognisable token in the place the failure could copy it
/// from; the `nan` payload, the typed rows under (C) and the `null` rows under (D)
/// hold none.
///
/// **What does not move:** the bytes on the wire and the return value. A payload
/// that did not encode is sent as empty `Data`, and a reply that did not decode
/// is `nil`. Two replies leave no line: an empty one — what an engine answers
/// when it has nothing to say and when it declined, and the client cannot tell
/// which — and the four bytes `null` asked as a type that cannot be read from
/// them. Both are `nil`. `null` is what `EngineReply.encode` writes for an
/// optional that is `nil`; asked as a type that decodes from it, it returns what
/// it decodes to. The client's line records its own refusal, not an absence.
///
/// **The control matters as much as the assertion.** The log is off in a test
/// process, so a row that only checked that a line was absent would pass on a log
/// nobody wrote. Each row that expects no line then writes one on purpose and
/// reads it back.
///
/// The transport is a real `LocalTransport` whose handler answers bytes, so a
/// payload is sent over the wire the screens use and a reply is decoded from what
/// a handler sent, never from a value the test built for the decoder. No window is
/// ordered: this family stays outside `--tier windows`.
@MainActor
final class TheClientLogsWhatItCouldNotEncodeOrDecodeTests: XCTestCase {

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

    // MARK: - what a row is fed

    /// A payload JSON cannot hold: `JSONEncoder` refuses a non-conforming float,
    /// and a `TimeInterval` is one division away from `nan`.
    fileprivate struct ClientNonFiniteRatio: Encodable { let ratio: Double }

    /// What a type's own `encode(to:)` may throw: an error that carries a value
    /// of its own. The line about it must not copy that value.
    fileprivate struct ClientLeakyFailure: Error { let detail: String }

    fileprivate struct ClientThrowingValue: Encodable {
        let detail: String
        func encode(to encoder: Encoder) throws { throw ClientLeakyFailure(detail: detail) }
    }

    /// A payload that encodes, for the controls.
    fileprivate struct ClientPlainPayload: Codable, Equatable { let path: String }

    /// What a call site asks the reply to be.
    fileprivate struct ClientVerdict: Codable, Equatable { let ok: Bool; let count: Int }

    /// A reply keyed by something the sender chose — a table keyed by path is an
    /// ordinary shape here, so its keys are somebody's file names.
    fileprivate struct ClientTable: Decodable { let sizes: [String: Int] }

    // MARK: - the wire

    /// A real `LocalTransport` whose handler records what it received, calls
    /// `onSend` and answers `reply`.
    private func wire(answering reply: Data = Data(),
                      onSend: (@Sendable () -> Void)? = nil) -> (client: TransportClient, seen: ClientArrivals) {
        let transport = LocalTransport()
        let seen = ClientArrivals()
        transport.setHandler { command in
            seen.record(command)
            onSend?()
            return reply
        }
        return (TransportClient(transport), seen)
    }

    /// A command name no other row sends, so that "the lines about it" is one
    /// row's lines and not another's.
    private func command(_ label: String) -> String { "client-probe-\(label)-\(UUID().uuidString)" }

    private func token() -> String { "TOKEN-\(UUID().uuidString)" }

    // MARK: - the log

    private func lines(about command: String) -> [LogEntry] {
        HelmLog.shared.recentEntries().filter { $0.message.contains(command) }
    }

    /// The contract: exactly one line, level `error`, category `client`, holding
    /// the command's name and the type's name, on one line, and none of `tokens`
    /// anywhere in what would be written to the file.
    private func assertOneRefusal(about command: String, type: Any.Type, tokens: [String] = [],
                                  file: StaticString = #filePath, line: UInt = #line) {
        let found = lines(about: command)
        XCTAssertEqual(found.count, 1,
                       "a refusal must leave exactly one line about \(command): \(found.map(\.message))",
                       file: file, line: line)
        guard let entry = found.first else { return }
        XCTAssertEqual(entry.category, "client", "\(entry.message)", file: file, line: line)
        XCTAssertEqual(entry.level, .error, "\(entry.message)", file: file, line: line)
        XCTAssertTrue(entry.message.contains("\(type)"),
                      "the line must name the type \(type): \(entry.message)", file: file, line: line)
        XCTAssertFalse(entry.message.contains("\n") || entry.message.contains("\r"),
                       "the line is more than one line: \(entry.message.debugDescription)",
                       file: file, line: line)
        let written = LogLine.line(entry)
        for token in tokens {
            XCTAssertFalse(written.contains(token),
                           "the line carries bytes the failure got from the wire: \(written)",
                           file: file, line: line)
        }
    }

    /// No line about `command`, then the control for that absence.
    private func assertNoLine(about command: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(lines(about: command).isEmpty,
                      "an event was written: \(lines(about: command).map(\.message))",
                      file: file, line: line)
        assertTheLogIsLive(file: file, line: line)
    }

    /// The control for an absence: a line written on purpose is read back, so
    /// that an empty list is "no line" and not "no log".
    private func assertTheLogIsLive(file: StaticString = #filePath, line: UInt = #line) {
        let marker = "liveness-\(UUID().uuidString)"
        HelmLog.shared.info("test", marker)
        XCTAssertTrue(HelmLog.shared.recentEntries().contains { $0.message == marker },
                      "the log is not live, so the absence above proved nothing", file: file, line: line)
    }

    /// No line under `client` and none under `engine`, whatever command it is
    /// about, then the control for that absence. The tail is cleared before each
    /// row and nothing else in this class runs beside it.
    private func assertNoLineFromEitherHalf(file: StaticString = #filePath, line: UInt = #line) {
        let found = HelmLog.shared.recentEntries().filter { $0.category == "client" || $0.category == "engine" }
        XCTAssertTrue(found.isEmpty,
                      "a lane that should be silent wrote: \(found.map { "[\($0.category)] \($0.message)" })",
                      file: file, line: line)
        assertTheLogIsLive(file: file, line: line)
    }

    // MARK: - (A) a payload that cannot be encoded

    /// A payload that will not encode, and whether it holds the secret a row
    /// hands it in a place the failure could copy it from.
    private typealias Unencodable = (label: String, type: Any.Type, holdsTheSecret: Bool,
                                     make: (String) -> any Encodable)

    /// Two payloads that will not encode. The first holds nothing but a `nan` and
    /// ignores the secret; the second carries the secret in the error its own
    /// `encode(to:)` throws.
    private var unencodable: [Unencodable] {
        [("nan", ClientNonFiniteRatio.self, false, { _ in ClientNonFiniteRatio(ratio: .nan) }),
         ("throwing", ClientThrowingValue.self, true, { ClientThrowingValue(detail: $0) })]
    }

    private func assertARequestPayloadIsRefused(_ fed: Unencodable,
                                                file: StaticString = #filePath, line: UInt = #line) async {
        let secret = token()
        let name = command("request-\(fed.label)")
        let (client, seen) = wire()

        let payload = fed.make(secret)
        let reply: ClientVerdict? = await client.request(name, encoding: payload)

        XCTAssertNil(reply, "\(fed.label)", file: file, line: line)
        XCTAssertEqual(seen.all.map(\.name), [name], "the command never reached the handler: \(fed.label)",
                       file: file, line: line)
        assertOneRefusal(about: name, type: fed.type, tokens: fed.holdsTheSecret ? [secret] : [],
                         file: file, line: line)
    }

    private func assertAFirePayloadIsRefused(_ fed: Unencodable,
                                             file: StaticString = #filePath, line: UInt = #line) async {
        let secret = token()
        let name = command("fire-\(fed.label)")
        let sent = expectation(description: "the handler saw \(name)")
        let (client, seen) = wire(onSend: { sent.fulfill() })

        let payload = fed.make(secret)
        client.fire(name, encoding: payload)
        await fulfillment(of: [sent], timeout: 10)

        XCTAssertEqual(seen.all.map(\.name), [name], "\(fed.label)", file: file, line: line)
        assertOneRefusal(about: name, type: fed.type, tokens: fed.holdsTheSecret ? [secret] : [],
                         file: file, line: line)
    }

    private func assertASendPayloadIsRefused(_ fed: Unencodable,
                                             file: StaticString = #filePath, line: UInt = #line) async {
        let secret = token()
        let name = command("send-\(fed.label)")
        let (client, seen) = wire()

        let payload = fed.make(secret)
        await client.send(name, encoding: payload)

        XCTAssertEqual(seen.all.map(\.name), [name], "the command never reached the handler: \(fed.label)",
                       file: file, line: line)
        assertOneRefusal(about: name, type: fed.type, tokens: fed.holdsTheSecret ? [secret] : [],
                         file: file, line: line)
    }

    func testARequestPayloadThatCannotBeEncodedLeavesOneLineNamingTheCommandAndTheType() async {
        for fed in unencodable { await assertARequestPayloadIsRefused(fed) }
    }

    func testAFirePayloadThatCannotBeEncodedLeavesOneLineNamingTheCommandAndTheType() async {
        for fed in unencodable { await assertAFirePayloadIsRefused(fed) }
    }

    func testASendPayloadThatCannotBeEncodedLeavesOneLineNamingTheCommandAndTheType() async {
        for fed in unencodable { await assertASendPayloadIsRefused(fed) }
    }

    // MARK: - (A) what does not move: the empty Data goes out

    /// A refusal adds a line and moves no byte on the wire: the engine receives
    /// empty `Data` for a payload that did not encode, at all three sites.
    func testAPayloadThatCannotBeEncodedIsStillSentAsEmptyDataAtEachSite() async {
        let requested = command("empty-request")
        let (client, seen) = wire()
        let _: ClientVerdict? = await client.request(requested, encoding: ClientNonFiniteRatio(ratio: .nan))

        let sentName = command("empty-send")
        await client.send(sentName, encoding: ClientNonFiniteRatio(ratio: .infinity))

        let firedName = command("empty-fire")
        let fired = expectation(description: "the handler saw \(firedName)")
        let (firing, firedSeen) = wire(onSend: { fired.fulfill() })
        firing.fire(firedName, encoding: ClientThrowingValue(detail: token()))
        await fulfillment(of: [fired], timeout: 10)

        XCTAssertEqual(seen.all.map(\.name), [requested, sentName])
        XCTAssertEqual(seen.all.map(\.payload), [Data(), Data()],
                       "a payload that did not encode must still be sent as empty Data")
        XCTAssertEqual(firedSeen.all.map(\.name), [firedName])
        XCTAssertEqual(firedSeen.all.map(\.payload), [Data()])
    }

    /// The other direction of the same control: a payload that does encode reaches
    /// the handler as exactly its JSON, at all three sites, and writes no line.
    func testAPayloadThatEncodesReachesTheHandlerAsItsJSONAndLeavesNoLine() async throws {
        let value = ClientPlainPayload(path: "/tmp/\(UUID().uuidString)")
        let expected = try JSONEncoder().encode(value)

        let requested = command("plain-request")
        let (client, seen) = wire()
        let _: ClientVerdict? = await client.request(requested, encoding: value)
        let sentName = command("plain-send")
        await client.send(sentName, encoding: value)
        let firedName = command("plain-fire")
        let fired = expectation(description: "the handler saw \(firedName)")
        let (firing, firedSeen) = wire(onSend: { fired.fulfill() })
        firing.fire(firedName, encoding: value)
        await fulfillment(of: [fired], timeout: 10)

        XCTAssertEqual(seen.all.map(\.payload), [expected, expected])
        XCTAssertEqual(firedSeen.all.map(\.payload), [expected])
        assertNoLine(about: "client-probe-plain")
    }

    // MARK: - (B) a non-empty reply that cannot be decoded

    /// One refusal through a real handler: the reply is what the handler sent,
    /// the call is `request(_:as:)`, and the line must name the command and the
    /// asked-for type and hold none of `tokens`. The result is `nil`, as it was.
    private func refuseTheReply<T: Decodable>(_ reply: Data, as type: T.Type, label: String,
                                              tokens: [String],
                                              file: StaticString = #filePath, line: UInt = #line) async {
        let name = command("decode-\(label)")
        let (client, seen) = wire(answering: reply)

        let got = await client.request(name, as: type)

        XCTAssertNil(got, "the reply cannot be \(type): \(label)", file: file, line: line)
        XCTAssertEqual(seen.all.map(\.name), [name], "the command never reached the handler",
                       file: file, line: line)
        assertOneRefusal(about: name, type: type, tokens: tokens, file: file, line: line)
    }

    func testAReplyThatIsNotJSONAtAllLeavesOneLineWithoutItsBytes() async {
        let secret = token()
        await refuseTheReply(Data("this is not json \(secret) at all".utf8),
                             as: ClientVerdict.self, label: "text", tokens: [secret])
    }

    func testAReplyOfInvalidUTF8LeavesOneLineWithoutItsBytes() async {
        let secret = token()
        let reply = Data([0xFF, 0xFE, 0xC0, 0x80]) + Data(secret.utf8) + Data([0xF8, 0xA1])
        await refuseTheReply(reply, as: ClientVerdict.self, label: "bytes", tokens: [secret])
    }

    func testAReplyOfTheWrongShapeLeavesOneLineWithoutItsValues() async {
        let secret = token()
        await refuseTheReply(Data("{\"ok\":\"\(secret)\",\"count\":\"\(secret)\"}".utf8),
                             as: ClientVerdict.self, label: "values", tokens: [secret])
    }

    func testAReplyMissingAKeyLeavesOneLineWithoutTheKeysItDid() async {
        let secret = token()
        await refuseTheReply(Data("{\"\(secret)\":true}".utf8),
                             as: ClientVerdict.self, label: "keys", tokens: [secret])
    }

    /// The keys are the sender's: a table keyed by path puts somebody's file name
    /// in the coding path of the failure.
    func testAReplyWhoseKeysAreNamesAndWhoseValuesAreWrongLeavesOneLineWithoutThem() async {
        let secret = token()
        await refuseTheReply(Data("{\"sizes\":{\"/Users/x/\(secret).pdf\":\"large\"}}".utf8),
                             as: ClientTable.self, label: "table", tokens: [secret])
    }

    func testAReplyThatIsAnArrayWhereAnObjectIsAskedLeavesOneLineWithoutItsElements() async {
        let secret = token()
        await refuseTheReply(Data("[\"\(secret)\",\"\(secret)\"]".utf8),
                             as: ClientVerdict.self, label: "array", tokens: [secret])
    }

    /// Two megabytes of it, with the token in the middle: the line is one line and
    /// holds none of it.
    func testAHugeReplyThatIsNotJSONLeavesOneLineWithoutItsBytes() async {
        let secret = token()
        let half = Data(repeating: UInt8(ascii: "x"), count: 1_000_000)
        await refuseTheReply(half + Data(secret.utf8) + half,
                             as: ClientVerdict.self, label: "huge", tokens: [secret])
    }

    /// A refusal is an event and not a state: the same bad reply twice is two
    /// lines, so a second failure is not hidden behind the first.
    func testTheSameRefusalTwiceLeavesTwoLines() async {
        let name = command("twice")
        let (client, _) = wire(answering: Data("nope".utf8))

        let first: ClientVerdict? = await client.request(name)
        let second: ClientVerdict? = await client.request(name)

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(lines(about: name).count, 2, "\(lines(about: name).map(\.message))")
    }

    // MARK: - (B) what does not move

    /// An engine answers empty for "nothing to say", so an empty reply is `nil`
    /// and is not an event — through the three string forms of `request`, which
    /// every other form calls. The second silent case, the four bytes `null`, is
    /// under (D).
    func testAnEmptyReplyIsNilAndLeavesNoLine() async {
        let name = command("empty-reply")
        let (client, seen) = wire(answering: Data())

        let bare: ClientVerdict? = await client.request(name)
        let encoded: ClientVerdict? = await client.request(name, encoding: ClientPlainPayload(path: "/tmp"))
        let raw: ClientVerdict? = await client.request(name, payload: Data("raw".utf8))

        XCTAssertNil(bare)
        XCTAssertNil(encoded)
        XCTAssertNil(raw)
        XCTAssertEqual(seen.all.count, 3, "the empty reply was never asked for")
        assertNoLine(about: name)
    }

    func testAReplyThatDecodesComesBackAndLeavesNoLine() async throws {
        let name = command("decodes")
        let expected = ClientVerdict(ok: true, count: 7)
        let (client, seen) = wire(answering: try JSONEncoder().encode(expected))

        let got: ClientVerdict? = await client.request(name)

        XCTAssertEqual(got, expected)
        XCTAssertEqual(seen.all.map(\.name), [name])
        assertNoLine(about: name)
    }

    /// The result of a failed decode is `nil`, whatever a log holds.
    func testAReplyThatCannotBeDecodedIsStillNil() async {
        let (client, seen) = wire(answering: Data("{\"ok\":1}".utf8))
        let name = command("still-nil")

        let got: ClientVerdict? = await client.request(name)

        XCTAssertNil(got)
        XCTAssertEqual(seen.all.map(\.name), [name], "the handler was never asked")
    }

    // MARK: - (C) the typed calls over a handler installed with `setHandler(for:module:_:)`

    /// A real `LocalTransport` whose handler is installed with
    /// `setHandler(for:module:_:)` over `TripCommand`. `scale`, `note` and `maybe`
    /// read their payload with `EngineReply.decode(from:as:)`, and the arms that
    /// answer a value encode it with `EngineReply.encode`; no fake encodes a reply.
    /// `scale` and `maybe` compute theirs from the payload they decoded, `status`
    /// from the command as it arrived, and `mismatch` and `nothing` answer the same
    /// thing every time. `onArrival` runs when an arm has finished, which is what a
    /// `fire` row waits for.
    private func typedWire(onArrival: (@Sendable () -> Void)? = nil)
        -> (client: TransportClient, transport: LocalTransport, arrivals: ClientArrivals) {
        let transport = LocalTransport()
        let arrivals = ClientArrivals()
        transport.setHandler(for: TripCommand.self, module: "client-roundtrip") { command, raw in
            arrivals.record(raw)
            defer { onArrival?() }
            switch command {
            case .scale:
                guard let request = EngineReply.decode(from: raw, as: TripCommand.scaled)
                else { return Data() }
                let scaled = request.values.map { $0 * request.factor }
                return EngineReply.encode(TripScaleReply(scaled: scaled, total: scaled.reduce(0, +)),
                                          for: raw, as: TripCommand.scaled)
            case .status:
                return EngineReply.encode(TripStatusReply(command: raw.name, payloadBytes: raw.payload.count),
                                          for: raw, as: TripCommand.reported)
            case .note:
                guard let note = EngineReply.decode(from: raw, as: TripCommand.noted)
                else { return Data() }
                arrivals.note(note)
                return Data()
            case .ping, .ratio:
                return Data()
            case .mismatch:
                return EngineReply.encode(ClientVerdict(ok: true, count: 3), for: raw)
            case .nothing:
                let none: TripScaleReply? = nil
                return EngineReply.encode(none, for: raw)
            case .maybe:
                guard let request = EngineReply.decode(from: raw, as: TripCommand.maybeScaled)
                else { return Data() }
                let scaled = request.values.map { $0 * request.factor }
                let answer: TripScaleReply? = request.values.isEmpty
                    ? nil : TripScaleReply(scaled: scaled, total: scaled.reduce(0, +))
                return EngineReply.encode(answer, for: raw)
            }
        }
        return (TransportClient(transport), transport, arrivals)
    }

    // MARK: - (C) the six overloads

    func testATypedRequestWithAPayloadReturnsTheReplyTheArmComputedFromIt() async throws {
        let (client, _, arrivals) = typedWire()
        let first = TripScaleRequest(values: [1, 2, 3], factor: 4)
        let second = TripScaleRequest(values: [5, -7], factor: -2)

        let one = await client.request(TripCommand.scaled, first)
        let two = await client.request(TripCommand.scaled, second)

        XCTAssertEqual(one, TripScaleReply(scaled: [4, 8, 12], total: 24))
        XCTAssertEqual(two, TripScaleReply(scaled: [-10, 14], total: 4))
        XCTAssertEqual(arrivals.all.map(\.name), [TripCommand.scale.rawValue, TripCommand.scale.rawValue])
        let sent = try arrivals.all.map { try JSONDecoder().decode(TripScaleRequest.self, from: $0.payload) }
        XCTAssertEqual(sent, [first, second], "the arm must have been handed the payloads that were sent")
        assertNoLineFromEitherHalf()
    }

    func testATypedRequestWithoutAPayloadReturnsTheReplyAndTheArmSawNoBytes() async {
        let (client, _, arrivals) = typedWire()

        let got = await client.request(TripCommand.reported)

        XCTAssertEqual(got, TripStatusReply(command: TripCommand.status.rawValue, payloadBytes: 0))
        XCTAssertEqual(arrivals.all.map(\.name), [TripCommand.status.rawValue])
        XCTAssertEqual(arrivals.all.map(\.payload), [Data()], "a call with no payload must send empty bytes")
        assertNoLineFromEitherHalf()
    }

    func testATypedSendWithAPayloadHandsTheArmThePayloadItWasSent() async {
        let (client, _, arrivals) = typedWire()
        let note = TripNote(text: "/tmp/\(UUID().uuidString)", count: 9)

        await client.send(TripCommand.noted, note)

        XCTAssertEqual(arrivals.noted, [note])
        assertNoLineFromEitherHalf()
    }

    func testATypedFireWithAPayloadHandsTheArmThePayloadItWasSent() async {
        let arrived = expectation(description: "the arm finished")
        let (client, _, arrivals) = typedWire(onArrival: { arrived.fulfill() })
        let note = TripNote(text: "/tmp/\(UUID().uuidString)", count: 11)

        client.fire(TripCommand.noted, note)
        await fulfillment(of: [arrived], timeout: 10)

        XCTAssertEqual(arrivals.noted, [note])
        assertNoLineFromEitherHalf()
    }

    func testATypedSendWithoutAPayloadRunsTheArmWithNoBytes() async {
        let (client, _, arrivals) = typedWire()

        await client.send(TripCommand.pinged)

        XCTAssertEqual(arrivals.all.map(\.name), [TripCommand.ping.rawValue])
        XCTAssertEqual(arrivals.all.map(\.payload), [Data()])
        assertNoLineFromEitherHalf()
    }

    func testATypedFireWithoutAPayloadRunsTheArmWithNoBytes() async {
        let arrived = expectation(description: "the arm finished")
        let (client, _, arrivals) = typedWire(onArrival: { arrived.fulfill() })

        client.fire(TripCommand.pinged)
        await fulfillment(of: [arrived], timeout: 10)

        XCTAssertEqual(arrivals.all.map(\.name), [TripCommand.ping.rawValue])
        XCTAssertEqual(arrivals.all.map(\.payload), [Data()])
        assertNoLineFromEitherHalf()
    }

    // MARK: - (C) the typed refusals

    /// The arm answers bytes of another shape than the call declares — an engine
    /// and a call site that disagree. The line names the command and the call's
    /// `Reply`.
    func testATypedRequestWhoseArmAnswersAnotherShapeLeavesOneLineNamingTheCallsReplyType() async {
        let (client, _, arrivals) = typedWire()

        let got = await client.request(TripCommand.mismatched, TripScaleRequest(values: [1], factor: 1))

        XCTAssertNil(got)
        XCTAssertEqual(arrivals.all.map(\.name), [TripCommand.mismatch.rawValue])
        assertOneRefusal(about: TripCommand.mismatch.rawValue, type: TripScaleReply.self)
    }

    func testATypedRequestWhosePayloadCannotBeEncodedLeavesOneLineNamingThePayloadType() async {
        let (client, _, arrivals) = typedWire()

        let got = await client.request(TripCommand.ratioed, TripRatio(ratio: .nan))

        XCTAssertNil(got)
        XCTAssertEqual(arrivals.all.map(\.payload), [Data()], "the empty bytes still went out")
        assertOneRefusal(about: TripCommand.ratio.rawValue, type: TripRatio.self)
    }

    func testATypedSendWhosePayloadCannotBeEncodedLeavesOneLineNamingThePayloadType() async {
        let (client, _, arrivals) = typedWire()

        await client.send(TripCommand.ratioed, TripRatio(ratio: .infinity))

        XCTAssertEqual(arrivals.all.map(\.payload), [Data()], "the empty bytes still went out")
        assertOneRefusal(about: TripCommand.ratio.rawValue, type: TripRatio.self)
    }

    func testATypedFireWhosePayloadCannotBeEncodedLeavesOneLineNamingThePayloadType() async {
        let arrived = expectation(description: "the arm finished")
        let (client, _, arrivals) = typedWire(onArrival: { arrived.fulfill() })

        client.fire(TripCommand.ratioed, TripRatio(ratio: .nan))
        await fulfillment(of: [arrived], timeout: 10)

        XCTAssertEqual(arrivals.all.map(\.payload), [Data()], "the empty bytes still went out")
        assertOneRefusal(about: TripCommand.ratio.rawValue, type: TripRatio.self)
    }

    // MARK: - (D) an arm that answers an optional nil

    /// Engines hand an optional to `EngineReply.encode` where an arm may have
    /// nothing to answer — a walk that was cancelled, a search that was stopped, a
    /// background scan with no folder chosen;
    /// `command grep -rnE 'EngineReply\.encode\((await )?(self\.)?(scan|find|backgroundScan)' Sources/Modules`
    /// prints them among arms whose value is never absent. This is what the wire
    /// carries for it, measured through a real handler. The bytes are printed on a
    /// line starting `MEASURED`.
    func testWhatAnArmAnswersForAnOptionalNilIsMeasured() async throws {
        let (_, transport, _) = typedWire()

        let none = try await transport.send(EngineCommand(name: TripCommand.nothing.rawValue, payload: Data()))
        let some = try await transport.send(EngineCommand(
            name: TripCommand.maybe.rawValue,
            payload: try JSONEncoder().encode(TripScaleRequest(values: [2], factor: 3))))
        let engineLines = HelmLog.shared.recentEntries().filter { $0.category == "engine" }.map(\.message)
        let text = String(decoding: none, as: UTF8.self)
        print("MEASURED optional nil: \(none.count) bytes \(Array(none)) = \(text.debugDescription); "
              + "optional some: \(String(decoding: some, as: UTF8.self)); engine lines: \(engineLines)")

        XCTAssertEqual(none, Data("null".utf8),
                       "measured \(none.count) bytes \(Array(none)) = \(text.debugDescription)")
        XCTAssertEqual(try JSONDecoder().decode(TripScaleReply.self, from: some),
                       TripScaleReply(scaled: [6], total: 6), "a value still comes back as its own JSON")
        XCTAssertTrue(engineLines.isEmpty, "the engine wrote \(engineLines)")
        assertTheLogIsLive()
    }

    /// An arm that encodes an optional nil has nothing to say, and the log records
    /// a refusal, not an absence: the client returns `nil` and leaves no line.
    /// Bare form.
    func testAnArmThatEncodesAnOptionalNilIsNoAnswerAndLeavesNoLineWithoutAPayload() async {
        let (client, _, arrivals) = typedWire()

        let got = await client.request(TripCommand.nothing, as: TripScaleReply.self)

        XCTAssertNil(got)
        XCTAssertEqual(arrivals.all.map(\.name), [TripCommand.nothing.rawValue], "the arm was never asked")
        assertNoLineFromEitherHalf()
    }

    /// The same, through `request(_:encoding:as:)`, with the arm choosing from the
    /// payload: nothing to find for an empty request, a value for another.
    func testAnArmThatEncodesAnOptionalNilIsNoAnswerAndLeavesNoLineWithAPayload() async {
        let (client, _, arrivals) = typedWire()

        let got = await client.request(TripCommand.maybe, encoding: TripScaleRequest(values: [], factor: 3),
                                       as: TripScaleReply.self)

        XCTAssertNil(got)
        XCTAssertEqual(arrivals.all.map(\.name), [TripCommand.maybe.rawValue], "the arm was never asked")
        assertNoLineFromEitherHalf()
    }

    /// The control on the other side of the same arm: a value comes back, and
    /// leaves no line.
    func testAnArmThatEncodesAnOptionalValueComesBackAndLeavesNoLine() async {
        let (client, _, _) = typedWire()

        let got = await client.request(TripCommand.maybe, encoding: TripScaleRequest(values: [2, 3], factor: 5),
                                       as: TripScaleReply.self)

        XCTAssertEqual(got, TripScaleReply(scaled: [10, 15], total: 25))
        assertNoLineFromEitherHalf()
    }

    /// A call that declares its `Reply` as an optional: the facade's `R?` makes the
    /// result a double optional, and `null` decodes into the inner one, so a nil
    /// answer is `.some(nil)` and not `nil`, and leaves no line.
    func testACallDeclaredWithAnOptionalReplyLeavesNoLineForNullAndReturnsTheValueOtherwise() async {
        let (client, _, _) = typedWire()

        let nothing = await client.request(TripCommand.maybeScaled, TripScaleRequest(values: [], factor: 2))
        let something = await client.request(TripCommand.maybeScaled, TripScaleRequest(values: [4], factor: 2))

        let present: TripScaleReply?? = .some(nil)
        XCTAssertEqual(nothing, present, "a nil answer to an optional Reply is present and empty")
        XCTAssertEqual(something, .some(TripScaleReply(scaled: [8], total: 8)))
        assertNoLineFromEitherHalf()
    }

    // MARK: - (D) replies that are not the JSON null

    /// The JSON string `"null"` — six bytes, quotes included — is not the JSON null.
    func testAReplyThatIsTheJSONStringNullAskedAsAStructStillLeavesOneLine() async {
        let reply = Data("\"null\"".utf8)
        XCTAssertEqual(reply.count, 6)
        await refuseTheReply(reply, as: ClientVerdict.self, label: "null-string", tokens: [])
    }

    /// An array holding a null is not a null either.
    func testAReplyOfAnArrayHoldingNullAskedAsAStructStillLeavesOneLine() async {
        await refuseTheReply(Data("[null]".utf8), as: ClientVerdict.self, label: "null-array", tokens: [])
    }

    /// Bytes that only begin like `null`, or hold it, are refusals: a check for
    /// the word and not for the whole reply would swallow them.
    func testRepliesThatOnlyContainOrBeginWithNullAskedAsAStructStillLeaveOneLine() async {
        let replies = ["nullx", "nul", "null,", "{\"ok\":null,\"count\":null}", "{\"ok\":true,\"count\":null}"]
        for (index, text) in replies.enumerated() {
            await refuseTheReply(Data(text.utf8), as: ClientVerdict.self,
                                 label: "null-lookalike-\(index)", tokens: [])
        }
    }

    /// `null` asked as a type that decodes from it is an answer, not a refusal: no
    /// line. The asked type is `Int?`, so the facade's own `T?` makes the result
    /// `Int??`, and it is present and empty.
    func testAReplyOfNullAskedAsATypeThatDecodesFromItLeavesNoLine() async {
        let name = command("null-optional")
        let (client, seen) = wire(answering: Data("null".utf8))

        let got = await client.request(name, as: Int?.self)

        let present: Int?? = .some(nil)
        XCTAssertEqual(got, present, "null decoded as Int? is an answer that is empty")
        XCTAssertEqual(seen.all.map(\.name), [name], "the handler was never asked")
        assertNoLineFromEitherHalf()
    }

    // MARK: - (E) a coding error that carries text of its own

    /// A coding error built by hand, as a type's own `init(from:)` or `encode(to:)`
    /// may throw one: it holds the secret in its underlying error, in its
    /// description or in a key of its coding path. The line names the command and
    /// the type and copies none of it.
    private func assertTheReplyIsRefused<T: Decodable>(_ type: T.Type, label: String) async {
        let secret = token()
        await refuseTheReply(Data("\"\(secret)\"".utf8), as: type, label: label, tokens: [secret])
    }

    func testAReplyWhoseReaderThrowsWithAnUnderlyingLocalizedErrorLeavesOneLineWithoutIt() async {
        await assertTheReplyIsRefused(ClientReplyWithALocalizedCause.self, label: "underlying-localized")
    }

    func testAReplyWhoseReaderThrowsWithAnUnderlyingNSErrorLeavesOneLineWithoutIt() async {
        await assertTheReplyIsRefused(ClientReplyWithACocoaCause.self, label: "underlying-cocoa")
    }

    func testAReplyWhoseReaderThrowsWithTheSecretInItsDescriptionLeavesOneLineWithoutIt() async {
        await assertTheReplyIsRefused(ClientReplyWithTheSecretInItsDescription.self, label: "description")
    }

    func testAReplyWhoseReaderThrowsWithTheSecretAsACodingKeyLeavesOneLineWithoutIt() async {
        await assertTheReplyIsRefused(ClientReplyWithTheSecretAsAKey.self, label: "key")
    }

    /// Payloads that throw an `EncodingError` with an underlying error of the two
    /// kinds.
    private var unencodableByAnUnderlyingError: [Unencodable] {
        [("underlying-localized", ClientPayloadThatThrows.self, true, {
            ClientPayloadThatThrows(failure: .invalidValue(
                ClientPlainPayload(path: $0),
                .init(codingPath: [], debugDescription: "cannot encode",
                      underlyingError: ClientUnderlying.localized.make($0))))
        }),
         ("underlying-cocoa", ClientPayloadThatThrows.self, true, {
            ClientPayloadThatThrows(failure: .invalidValue(
                ClientPlainPayload(path: $0),
                .init(codingPath: [], debugDescription: "cannot encode",
                      underlyingError: ClientUnderlying.cocoa.make($0))))
        })]
    }

    /// Payloads that throw an `EncodingError` with the secret in its description,
    /// or as a key of its coding path.
    private var unencodableByItsDescriptionOrKey: [Unencodable] {
        [("description", ClientPayloadThatThrows.self, true, {
            ClientPayloadThatThrows(failure: .invalidValue(
                ClientPlainPayload(path: $0),
                .init(codingPath: [], debugDescription: "cannot encode \($0)")))
        }),
         ("key", ClientPayloadThatThrows.self, true, {
            ClientPayloadThatThrows(failure: .invalidValue(
                ClientPlainPayload(path: $0),
                .init(codingPath: [ClientAnyKey($0)], debugDescription: "cannot encode")))
        })]
    }

    func testARequestPayloadWhoseEncoderThrowsWithAnUnderlyingErrorLeavesOneLineWithoutIt() async {
        for fed in unencodableByAnUnderlyingError { await assertARequestPayloadIsRefused(fed) }
    }

    func testAFirePayloadWhoseEncoderThrowsWithAnUnderlyingErrorLeavesOneLineWithoutIt() async {
        for fed in unencodableByAnUnderlyingError { await assertAFirePayloadIsRefused(fed) }
    }

    func testASendPayloadWhoseEncoderThrowsWithAnUnderlyingErrorLeavesOneLineWithoutIt() async {
        for fed in unencodableByAnUnderlyingError { await assertASendPayloadIsRefused(fed) }
    }

    func testARequestPayloadWhoseEncoderThrowsWithTheSecretInItsDescriptionOrKeyLeavesOneLineWithoutIt() async {
        for fed in unencodableByItsDescriptionOrKey { await assertARequestPayloadIsRefused(fed) }
    }

    func testAFirePayloadWhoseEncoderThrowsWithTheSecretInItsDescriptionOrKeyLeavesOneLineWithoutIt() async {
        for fed in unencodableByItsDescriptionOrKey { await assertAFirePayloadIsRefused(fed) }
    }

    func testASendPayloadWhoseEncoderThrowsWithTheSecretInItsDescriptionOrKeyLeavesOneLineWithoutIt() async {
        for fed in unencodableByItsDescriptionOrKey { await assertASendPayloadIsRefused(fed) }
    }
}

/// The underlying error of a coding error, built from the secret: one is a Swift
/// error whose description and failure reason hold it, the other a Cocoa error
/// whose description, failure reason and file path each do.
fileprivate enum ClientUnderlying {
    case localized, cocoa

    func make(_ secret: String) -> Error {
        switch self {
        case .localized:
            return ClientLocalizedLeak(detail: secret)
        case .cocoa:
            return NSError(domain: "client-probe", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "described \(secret)",
                NSLocalizedFailureReasonErrorKey: "reason \(secret)",
                NSFilePathErrorKey: "/Volumes/Work/\(secret).key"])
        }
    }
}

fileprivate struct ClientLocalizedLeak: LocalizedError {
    let detail: String
    var errorDescription: String? { "localized \(detail)" }
    var failureReason: String? { "reason \(detail)" }
}

/// A coding key spelled by whoever builds it, as the key of a table keyed by path
/// is.
fileprivate struct ClientAnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ text: String) { stringValue = text }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// A payload whose `encode(to:)` throws the coding error it was built with.
fileprivate struct ClientPayloadThatThrows: Encodable {
    let failure: EncodingError
    func encode(to encoder: Encoder) throws { throw failure }
}

/// Reads a reply that is one JSON string, the secret, and throws the coding error
/// `build` makes from it.
fileprivate func clientRefuse(_ decoder: Decoder,
                              _ build: (String) -> DecodingError) throws -> Never {
    let secret = try decoder.singleValueContainer().decode(String.self)
    throw build(secret)
}

fileprivate struct ClientReplyWithALocalizedCause: Decodable {
    init(from decoder: Decoder) throws {
        try clientRefuse(decoder) {
            .dataCorrupted(.init(codingPath: [], debugDescription: "the data is corrupt",
                                 underlyingError: ClientUnderlying.localized.make($0)))
        }
    }
}

fileprivate struct ClientReplyWithACocoaCause: Decodable {
    init(from decoder: Decoder) throws {
        try clientRefuse(decoder) {
            .dataCorrupted(.init(codingPath: [], debugDescription: "the data is corrupt",
                                 underlyingError: ClientUnderlying.cocoa.make($0)))
        }
    }
}

fileprivate struct ClientReplyWithTheSecretInItsDescription: Decodable {
    init(from decoder: Decoder) throws {
        try clientRefuse(decoder) {
            .dataCorrupted(.init(codingPath: [], debugDescription: "the data is corrupt: \($0)"))
        }
    }
}

fileprivate struct ClientReplyWithTheSecretAsAKey: Decodable {
    init(from decoder: Decoder) throws {
        try clientRefuse(decoder) {
            .dataCorrupted(.init(codingPath: [ClientAnyKey($0)], debugDescription: "the data is corrupt"))
        }
    }
}

/// A module's own command enum, as an engine declares one: custom raw values keep
/// every line these rows cause findable by `client-roundtrip`, and a handler
/// switches over the cases with no `default` arm.
fileprivate enum TripCommand: String, Sendable {
    case scale = "client-roundtrip-scale"
    case status = "client-roundtrip-status"
    case note = "client-roundtrip-note"
    case ping = "client-roundtrip-ping"
    case ratio = "client-roundtrip-ratio"
    case mismatch = "client-roundtrip-mismatch"
    case nothing = "client-roundtrip-nothing"
    case maybe = "client-roundtrip-maybe"
}

/// The calls, declared once beside the enum, where `EngineCall`'s doc comment
/// puts a call. A call is not spelled like a case of its enum: the compiler
/// refuses a redeclaration.
fileprivate extension TripCommand {
    static let scaled = EngineCall<TripCommand, TripScaleRequest, TripScaleReply>(command: .scale)
    static let reported = EngineCall<TripCommand, Never, TripStatusReply>(command: .status)
    static let noted = EngineCall<TripCommand, TripNote, Never>(command: .note)
    static let pinged = EngineCall<TripCommand, Never, Never>(command: .ping)
    static let ratioed = EngineCall<TripCommand, TripRatio, TripScaleReply>(command: .ratio)
    static let mismatched = EngineCall<TripCommand, TripScaleRequest, TripScaleReply>(command: .mismatch)
    static let maybeScaled = EngineCall<TripCommand, TripScaleRequest, TripScaleReply?>(command: .maybe)
}

fileprivate struct TripScaleRequest: Codable, Equatable { let values: [Int]; let factor: Int }
fileprivate struct TripScaleReply: Codable, Equatable { let scaled: [Int]; let total: Int }
fileprivate struct TripStatusReply: Codable, Equatable { let command: String; let payloadBytes: Int }
fileprivate struct TripNote: Codable, Equatable { let text: String; let count: Int }
fileprivate struct TripRatio: Codable, Equatable { let ratio: Double }

/// What the handler of a wire was handed, and what a `note` arm decoded, kept for
/// the row to read.
fileprivate final class ClientArrivals: @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [EngineCommand] = []
    private var notes: [TripNote] = []
    func record(_ command: EngineCommand) { lock.lock(); commands.append(command); lock.unlock() }
    func note(_ note: TripNote) { lock.lock(); notes.append(note); lock.unlock() }
    var all: [EngineCommand] { lock.lock(); defer { lock.unlock() }; return commands }
    var noted: [TripNote] { lock.lock(); defer { lock.unlock() }; return notes }
}
