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

    // MARK: - a command name the enum cannot parse

    private enum Verb: String, Sendable { case ping, stop }

    /// What an arm of the test engine answers. Non-empty, so that "the arm ran"
    /// and "nothing answered" cannot be the same bytes.
    private static let armReply = Data("the arm ran".utf8)

    /// Where the `Verb` engine's handler is installed on a transport; every row
    /// that sends a `Verb` name goes through it, so those rows share one body
    /// that wires the prelude: it parses the name, and the closure switches over
    /// the parsed case with no `default` arm.
    private func wireTheTestEngine(_ transport: LocalTransport, module: String) {
        transport.setHandler(for: Verb.self, module: module) { verb, _ in
            switch verb {
            case .ping, .stop: return Self.armReply
            }
        }
    }

    /// A name the enum lacks is answered with empty `Data`, as it always was, and
    /// is now a line under `engine` that names the module and the command.
    func testACommandNameTheEnumLacksAnswersEmptyAndSaysSoUnderTheModuleAndTheName() async throws {
        let transport = LocalTransport()
        wireTheTestEngine(transport, module: "Widgets")

        let reply = try await transport.send(EngineCommand(name: "frobnicate"))

        XCTAssertTrue(reply.isEmpty, "the arm answered a name it does not have: \(reply)")
        let lines = engineLines
        XCTAssertEqual(lines.count, 1,
                       "an unknown command name must leave exactly one engine line: \(lines)")
        XCTAssertTrue(lines.contains { $0.contains("Widgets") && $0.contains("frobnicate") },
                      "the line must name both the module and the command name: \(lines)")
    }

    /// The control. A name the enum has reaches its arm and writes nothing — and
    /// the log is shown to be live in the same row, by a line that is written on
    /// purpose afterwards, so an empty list here is "no line" and not "no log".
    func testACommandNameTheEnumHasReachesItsArmAndWritesNoLine() async throws {
        let transport = LocalTransport()
        wireTheTestEngine(transport, module: "Widgets")

        let reply = try await transport.send(EngineCommand(name: "ping"))

        XCTAssertEqual(reply, Self.armReply, "the arm did not run")
        XCTAssertTrue(engineLines.isEmpty, "a known command is not an event: \(engineLines)")

        // The same seam, a line that must appear: a payload no `Request` can be
        // read from, under a name no other row in this class sends.
        XCTAssertNil(EngineReply.decode(Request.self, from: EngineCommand(name: "liveness-probe")))
        XCTAssertTrue(engineLines.contains { $0.contains("liveness-probe") },
                      "the log is not live, so the empty list above proved nothing: \(engineLines)")
        XCTAssertEqual(engineLines.count, 1, "\(engineLines)")
    }

    /// The line as it was written: category, level and message, nothing of the
    /// payload. Exact, where the rows above only look for words.
    func testTheLineIsAnErrorUnderEngineSpelledAsTheModuleAndTheQuotedName() async throws {
        let transport = LocalTransport()
        wireTheTestEngine(transport, module: "Widgets")

        _ = try await transport.send(EngineCommand(name: "frobnicate"))

        let entries = HelmLog.shared.recentEntries().filter { $0.category == "engine" }
        XCTAssertEqual(entries.map(\.message), ["Widgets: no command named \"frobnicate\""])
        XCTAssertEqual(entries.map(\.level), [.error])
    }

    /// An empty name is a name the enum cannot parse, and the line shows it as an
    /// empty pair of quotes rather than as a line that ends mid-sentence.
    func testAnEmptyNameIsRefusedAndWrittenAsAnEmptyPairOfQuotes() async throws {
        let transport = LocalTransport()
        wireTheTestEngine(transport, module: "Widgets")

        let reply = try await transport.send(EngineCommand(name: ""))

        XCTAssertTrue(reply.isEmpty, "\(reply)")
        XCTAssertEqual(engineLines, ["Widgets: no command named \"\""])
    }

    /// A name with a line break in it must not pass for two lines. The tail keeps
    /// the message raw, so the escaping is judged on the entry; the file flattens
    /// a real break to a marker on its own, so the file holds one line for this
    /// name with the escaping or without it. The file is read only to show the
    /// name arrived there as one line.
    func testANameWithALineBreakIsOneEntryAndTheBreakIsEscaped() async throws {
        let transport = LocalTransport()
        wireTheTestEngine(transport, module: "Widgets")
        let tag = UUID().uuidString

        let reply = try await transport.send(EngineCommand(name: "first\nsecond-\(tag)"))

        XCTAssertTrue(reply.isEmpty, "\(reply)")
        let entries = HelmLog.shared.recentEntries().filter { $0.category == "engine" }
        XCTAssertEqual(entries.count, 1, "\(entries.map(\.message))")
        let entry = try XCTUnwrap(entries.first)
        XCTAssertFalse(entry.message.contains("\n"),
                       "the entry holds a real line break: \(entry.message.debugDescription)")
        XCTAssertEqual(entry.message, "Widgets: no command named \"first\\nsecond-\(tag)\"")
        XCTAssertFalse(LogLine.line(entry).contains("\n"), "\(LogLine.line(entry).debugDescription)")

        // The test folder is shared by every run, so only this run's tag counts.
        // Both files, because a rollover may have moved the line to the older one;
        // `recentEntries()` above ran on the log's queue, after the append.
        let written = HelmLog.allFileURLs
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { $0.components(separatedBy: "\n") }
            .filter { $0.contains(tag) }
        XCTAssertEqual(written.count, 1, "the name is on \(written.count) lines of the file: \(written)")
        XCTAssertTrue(written.first?.contains("no command named") == true, "\(written)")
    }

    /// Case is part of a name. `Ping` is not `ping`, and neither is `STOP`; the
    /// control is the exact spelling, which reaches its arm.
    func testANameDifferingFromARealCaseOnlyInCaseIsNotThatCase() async throws {
        let transport = LocalTransport()
        wireTheTestEngine(transport, module: "Widgets")

        let wrong = try await transport.send(EngineCommand(name: "Ping"))
        let alsoWrong = try await transport.send(EngineCommand(name: "STOP"))
        let right = try await transport.send(EngineCommand(name: "stop"))

        XCTAssertTrue(wrong.isEmpty && alsoWrong.isEmpty, "\(wrong) \(alsoWrong)")
        XCTAssertEqual(right, Self.armReply)
        XCTAssertEqual(engineLines, ["Widgets: no command named \"Ping\"",
                                     "Widgets: no command named \"STOP\""])
    }

    /// An unknown name that comes with a payload naming somebody's file: the line
    /// carries the module and the name, never the bytes. The line is shown to
    /// exist first, so an empty list could not pass.
    func testAnUnknownNameWithAPayloadNamingAFileDoesNotCarryThePayload() async throws {
        let transport = LocalTransport()
        wireTheTestEngine(transport, module: "Widgets")
        let secret = "/Users/someone/Documents/tax-return-\(UUID().uuidString).pdf"

        let reply = try await transport.send(
            EngineCommand(name: "frobnicate", payload: Data("[\"\(secret)\"]".utf8)))

        XCTAssertTrue(reply.isEmpty, "\(reply)")
        XCTAssertEqual(engineLines.count, 1, "nothing was written, so this proves nothing: \(engineLines)")
        XCTAssertTrue(engineLines.contains { $0.contains("frobnicate") })
        XCTAssertFalse(engineLines.contains { $0.contains(secret) || $0.contains("tax-return") },
                       "the log carries the payload: \(engineLines)")
    }

    // MARK: - the two installs

    /// The transport has one handler slot. The older `setHandler(_:)` still works
    /// on its own, and whichever of the two is installed last is the one that
    /// answers: a later bare handler takes the parse and the line with it, and a
    /// later prelude takes the bare handler's place.
    func testTheOlderInstallStillWorksAndTheLastInstallAnswers() async throws {
        let bare = Data("the bare handler".utf8)

        let alone = LocalTransport()
        alone.setHandler { _ in bare }
        let aloneReply = try await alone.send(EngineCommand(name: "anything"))
        XCTAssertEqual(aloneReply, bare)
        XCTAssertTrue(engineLines.isEmpty, "\(engineLines)")

        let bareLast = LocalTransport()
        wireTheTestEngine(bareLast, module: "Widgets")
        bareLast.setHandler { _ in bare }
        let known = try await bareLast.send(EngineCommand(name: "ping"))
        let unknown = try await bareLast.send(EngineCommand(name: "frobnicate"))
        XCTAssertEqual(known, bare, "the earlier install answered")
        XCTAssertEqual(unknown, bare, "the earlier install answered")
        XCTAssertTrue(engineLines.isEmpty, "the replaced prelude still wrote: \(engineLines)")

        let preludeLast = LocalTransport()
        preludeLast.setHandler { _ in bare }
        wireTheTestEngine(preludeLast, module: "Widgets")
        let arm = try await preludeLast.send(EngineCommand(name: "ping"))
        let refused = try await preludeLast.send(EngineCommand(name: "frobnicate"))
        XCTAssertEqual(arm, Self.armReply, "the earlier install answered")
        XCTAssertTrue(refused.isEmpty, "\(refused)")
        XCTAssertEqual(engineLines.count, 1, "\(engineLines)")
    }

    // MARK: - the typed call, end to end

    private enum Calc: String, Sendable { case sum, reset }
    private struct Operands: Codable, Equatable { let numbers: [Int] }
    private struct Total: Codable, Equatable { let sum: Int; let count: Int }
    private struct Timing: Codable { let seconds: Double }

    /// Declared beside its enum, the place `EngineCall`'s doc comment gives a call.
    private static let sumCall = EngineCall<Calc, Operands, Total>(command: .sum)

    /// A test engine whose `sum` arm answers from what it was sent, through the
    /// typed overloads and nothing else. The reply is computed from the payload,
    /// so a handler that ignored the payload — or a `decode` that returned a
    /// fixed value — gives the wrong total for at least one of the calls below.
    private func wireTheCalculator(_ transport: LocalTransport) {
        transport.setHandler(for: Calc.self, module: "Calculator") { calc, command in
            switch calc {
            case .sum:
                guard let operands = EngineReply.decode(from: command, as: Self.sumCall)
                else { return Data() }
                return EngineReply.encode(
                    Total(sum: operands.numbers.reduce(0, +), count: operands.numbers.count),
                    for: command, as: Self.sumCall)
            case .reset:
                return Self.armReply
            }
        }
    }

    /// The caller's side, written by hand because the client has no typed
    /// overload: the name from the call, the payload encoded by the caller, the
    /// reply read as the call's `Reply`.
    private func ask(_ transport: LocalTransport, _ numbers: [Int]) async throws -> Total? {
        let payload = try JSONEncoder().encode(Operands(numbers: numbers))
        let bytes = try await transport.send(
            EngineCommand(name: Self.sumCall.command.rawValue, payload: payload))
        return try? JSONDecoder().decode(Total.self, from: bytes)
    }

    func testATypedCallRoundTripsThroughARealTransportAndTheReplyDependsOnThePayload() async throws {
        let transport = LocalTransport()
        wireTheCalculator(transport)

        let first = try await ask(transport, [1, 2, 3])
        let second = try await ask(transport, [10, 20])
        let none = try await ask(transport, [])

        XCTAssertEqual(first, Total(sum: 6, count: 3))
        XCTAssertEqual(second, Total(sum: 30, count: 2))
        XCTAssertEqual(none, Total(sum: 0, count: 0))
        XCTAssertTrue(engineLines.isEmpty, "a clean round trip is not an event: \(engineLines)")
        // The sibling case still reaches its own arm through the same handler.
        let reset = try await transport.send(EngineCommand(name: "reset"))
        XCTAssertEqual(reset, Self.armReply)
    }

    /// The refusal half: a payload the call's `Payload` cannot read gives `nil`
    /// through the typed overload, a line under the command's name and the type it
    /// wanted, and an empty reply — and the payload's bytes are not in the line.
    func testATypedCallGivenAPayloadItCannotReadAnswersEmptyAndSaysSo() async throws {
        let transport = LocalTransport()
        wireTheCalculator(transport)
        let secret = "/Users/someone/Documents/tax-return-\(UUID().uuidString).pdf"

        let reply = try await transport.send(
            EngineCommand(name: "sum", payload: Data("{\"numbers\":\"\(secret)\"}".utf8)))

        XCTAssertTrue(reply.isEmpty, "\(reply)")
        XCTAssertTrue(engineLines.contains { $0.contains("sum") && $0.contains("Operands") },
                      "the unreadable payload went by in silence: \(engineLines)")
        XCTAssertFalse(engineLines.contains { $0.contains(secret) }, "\(engineLines)")

        // The typed overload on its own, as an arm calls it.
        HelmLog.shared.clearTail()
        let direct: Operands? = EngineReply.decode(
            from: EngineCommand(name: "sum", payload: Data("{}".utf8)), as: Self.sumCall)
        XCTAssertNil(direct)
        XCTAssertEqual(engineLines.count, 1, "\(engineLines)")
    }

    /// The typed `encode` is the untyped one with the type fixed, so a reply JSON
    /// cannot hold is the same empty `Data` and the same line.
    func testATypedReplyJSONCannotHoldAnswersEmptyAndSaysSo() {
        let call = EngineCall<Calc, Operands, Timing>(command: .sum)
        let data = EngineReply.encode(Timing(seconds: .nan), for: EngineCommand(name: "sum"), as: call)

        XCTAssertTrue(data.isEmpty)
        XCTAssertTrue(engineLines.contains { $0.contains("sum") && $0.contains("Timing") },
                      "\(engineLines)")
    }
}
