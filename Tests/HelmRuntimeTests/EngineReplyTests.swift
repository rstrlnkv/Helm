import Foundation
import HelmContract
import XCTest
@testable import HelmRuntime

/// The engine side of the transport's JSON, and what it does when the JSON
/// fails.
///
/// The failure is the point. An arm that spells `(try? JSONEncoder().encode(x)) ?? Data()`
/// or `guard let y = try? JSONDecoder().decode(…) else { return Data() }` by hand
/// answers a payload it could not read and a refusal with the same empty reply
/// and the same silence. The calls of `Sources/HelmRuntime/EngineReply.swift`
/// write one `error` line under `engine` for each failure: a payload that will
/// not decode, a reply that will not encode, an event that will not encode, a
/// command name the enum cannot parse, and a typed call whose case is not the
/// command that arrived. What goes back is the same `nil` or empty `Data`,
/// except that an event that will not encode is not emitted, a typed `decode`
/// given the call of another case reads nothing, and a typed `encode` given the
/// call of another case still hands the reply's bytes.
///
/// **What a line holds is pinned whole.** The rows that judge a line through
/// `assertTheEngineLines`, or compare `engineLines` with an array of messages,
/// compare the message to its exact text, so a line that grew a hash, a
/// shortened form or the error's own words is red as well as one that carries
/// the payload; a row that looks with `contains` judges only the words it names.
/// A failure of the coding itself is written as its case and, where the case
/// carries one, the type asked for or the type of the value
/// (`DecodingError.keyNotFound`, `DecodingError.typeMismatch String`,
/// `EncodingError.invalidValue Double`); any other error as the name of its
/// type. The probe rows plant a token in one field of an error at a time (an
/// underlying error's description, failure reason, file path, domain or Swift
/// text, the coding error's debug description, a coding-path key, the value or
/// the key the error names, and the same fields of an error that is no coding
/// error) and look for it in the line of each place that writes that error: the
/// payload read, the reply written and the event written.
///
/// **The control matters as much as the assertion.** The log is off in a test
/// process (`HelmLog` starts disabled), so `setUp` switches it on. A row that
/// judges a word absent from a line asserts the line exists first, and a control
/// that expects no line (`testACommandNameTheEnumHasReachesItsArmAndWritesNoLine`,
/// `testAnArmGivenItsOwnCaseCallReadsAndAnswersAndWritesNoLine`) writes one on
/// purpose afterwards to show the log live.
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

    /// The caller's side, written by hand: the name from the call, the payload
    /// encoded by the caller, the reply read as the call's `Reply`.
    /// `TransportClient`, which has typed overloads for a call, is in `HelmUI`,
    /// and `Package.swift` does not list that target among this one's
    /// dependencies; no file of this target imports it.
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

    /// The typed `encode` given the call's own case answers a reply JSON cannot
    /// hold with the same empty `Data` and the same line as the untyped one: the
    /// command's name, the reply's type and no other line.
    func testATypedReplyJSONCannotHoldAnswersEmptyAndSaysSo() {
        let call = EngineCall<Calc, Operands, Timing>(command: .sum)
        let data = EngineReply.encode(Timing(seconds: .nan), for: EngineCommand(name: "sum"), as: call)

        XCTAssertTrue(data.isEmpty)
        XCTAssertEqual(engineLines, ["sum: reply of Timing not encoded — EncodingError.invalidValue Double"])
    }

    // MARK: - a typed call of another case

    private struct Memo: Codable, Equatable { let text: String }

    private static let sumMemo = EngineCall<Calc, Memo, Memo>(command: .sum)
    private static let resetMemo = EngineCall<Calc, Memo, Memo>(command: .reset)

    private var engineEntries: [LogEntry] {
        HelmLog.shared.recentEntries().filter { $0.category == "engine" }
    }

    /// A test engine whose `sum` arm reads its payload through `readCall` and
    /// answers through `answerCall`. Both are calls with the same payload and
    /// reply types, so every combination compiles; only the case they name differs.
    private func wireTheArm(_ transport: LocalTransport,
                            readsThrough readCall: EngineCall<Calc, Memo, Memo>,
                            answersThrough answerCall: EngineCall<Calc, Memo, Memo>) {
        transport.setHandler(for: Calc.self, module: "Calculator") { calc, command in
            switch calc {
            case .sum:
                guard let memo = EngineReply.decode(from: command, as: readCall)
                else { return Data() }
                return EngineReply.encode(Memo(text: "heard " + memo.text),
                                          for: command, as: answerCall)
            case .reset:
                return Self.armReply
            }
        }
    }

    private func sumCommand(carrying text: String) throws -> EngineCommand {
        EngineCommand(name: "sum", payload: try JSONEncoder().encode(Memo(text: text)))
    }

    /// The control: an arm that reads and answers through its own case's call
    /// writes no line, and the log is shown live in the same row.
    func testAnArmGivenItsOwnCaseCallReadsAndAnswersAndWritesNoLine() async throws {
        let transport = LocalTransport()
        wireTheArm(transport, readsThrough: Self.sumMemo, answersThrough: Self.sumMemo)
        let secret = "/Users/someone/Documents/tax-return-\(UUID().uuidString).pdf"

        let reply = try await transport.send(try sumCommand(carrying: secret))

        XCTAssertEqual(try JSONDecoder().decode(Memo.self, from: reply), Memo(text: "heard " + secret))
        XCTAssertTrue(engineLines.isEmpty, "a call of its own case is not an event: \(engineLines)")

        XCTAssertNil(EngineReply.decode(Memo.self, from: EngineCommand(name: "liveness-probe")))
        XCTAssertEqual(engineLines.count, 1,
                       "the log is not live, so the empty list above proved nothing: \(engineLines)")
    }

    /// The one line a mismatch writes, for a `sum` command met by the call of
    /// `reset`: the name that arrived, then the name the call is for, each as a
    /// Swift string literal.
    private static let sumMetByResetLine = "command \"sum\" does not match the call of \"reset\""

    /// Judges every entry under `engine` whole: as many entries as messages
    /// expected, each at level `error`, each message equal to the expected text.
    /// The count comes out of the comparison, so a second line is a failure and
    /// so is a missing one.
    private func assertTheEngineLines(_ expected: [String], _ context: String = "",
                                      file: StaticString = #filePath, line: UInt = #line) {
        let entries = engineEntries
        XCTAssertEqual(entries.map(\.message), expected, context, file: file, line: line)
        XCTAssertEqual(entries.map(\.level), Array(repeating: LogLevel.error, count: expected.count),
                       context, file: file, line: line)
    }

    /// An arm that reads its payload through another case's call gets `nil`, so
    /// it answers empty, and the refusal is the mismatch line and nothing else:
    /// no byte of the payload, and no second line from a read of it.
    func testAnArmGivenTheCallOfAnotherCaseReadsNothingAndSaysSo() async throws {
        let transport = LocalTransport()
        wireTheArm(transport, readsThrough: Self.resetMemo, answersThrough: Self.sumMemo)
        let secret = "/Users/someone/Documents/tax-return-\(UUID().uuidString).pdf"

        let reply = try await transport.send(try sumCommand(carrying: secret))

        XCTAssertTrue(reply.isEmpty,
                      "the arm read a payload through another case's call: \(String(decoding: reply, as: UTF8.self))")
        assertTheEngineLines([Self.sumMetByResetLine])
        XCTAssertFalse(engineLines.contains { $0.contains(secret) || $0.contains("tax-return") },
                       "the log carries the payload: \(engineLines)")
    }

    /// The reply half. The bytes are still handed: the call names the wrong case
    /// but the reply is the arm's own and the caller can read it. The line is the
    /// one the read half writes.
    func testAnArmAnsweringThroughTheCallOfAnotherCaseStillAnswersAndSaysSo() async throws {
        let transport = LocalTransport()
        wireTheArm(transport, readsThrough: Self.sumMemo, answersThrough: Self.resetMemo)
        let secret = "/Users/someone/Documents/tax-return-\(UUID().uuidString).pdf"

        let reply = try await transport.send(try sumCommand(carrying: secret))

        XCTAssertEqual(try JSONDecoder().decode(Memo.self, from: reply), Memo(text: "heard " + secret),
                       "the reply was withheld or changed")
        assertTheEngineLines([Self.sumMetByResetLine])
        XCTAssertFalse(engineLines.contains { $0.contains(secret) || $0.contains("tax-return") },
                       "the log carries the payload: \(engineLines)")
    }

    /// The overload on its own, as an arm calls it, handed a payload that does
    /// not decode as `Memo`. Nothing is decoded for a command of another
    /// case, so the one line is the mismatch and there is no second one about the
    /// payload. The same payload through the command's own case is what the
    /// mismatch spared: a line about the payload.
    func testAMismatchedDecodeOfAPayloadThatWouldNotDecodeLeavesOnlyTheMismatchLine() {
        let command = EngineCommand(name: "sum", payload: Data("{}".utf8))

        let memo: Memo? = EngineReply.decode(from: command, as: Self.resetMemo)

        XCTAssertNil(memo)
        assertTheEngineLines([Self.sumMetByResetLine])

        HelmLog.shared.clearTail()
        let own: Memo? = EngineReply.decode(from: command, as: Self.sumMemo)
        XCTAssertNil(own)
        assertTheEngineLines(["sum: payload not read as Memo — DecodingError.keyNotFound"])
    }

    /// The mirror. A mismatched `encode` of a reply JSON cannot hold: the
    /// mismatch is written first, the bytes are still attempted, and the failure
    /// of the encoding is its own second line, so the arm gets empty `Data` and
    /// both lines.
    func testAMismatchedEncodeOfAReplyJSONCannotHoldLeavesTheMismatchLineAndTheEncodingLine() {
        let call = EngineCall<Calc, Operands, Timing>(command: .reset)

        let data = EngineReply.encode(Timing(seconds: .nan), for: EngineCommand(name: "sum"), as: call)

        XCTAssertTrue(data.isEmpty)
        assertTheEngineLines([Self.sumMetByResetLine,
                              "sum: reply of Timing not encoded — EncodingError.invalidValue Double"])
    }

    /// A name that arrives with a line break in it is one entry with the break
    /// escaped, at both overloads, as the unknown-name rows above judge their
    /// line. The tag keeps the name this run's own.
    func testANameWithALineBreakInTheMismatchLineIsOneEntryAndTheBreakIsEscaped() throws {
        let tag = UUID().uuidString
        let name = "a\nb-\(tag)"
        let expected = "command \"a\\nb-\(tag)\" does not match the call of \"sum\""

        let memo: Memo? = EngineReply.decode(from: EngineCommand(name: name, payload: Data("{}".utf8)),
                                             as: Self.sumMemo)
        XCTAssertNil(memo)
        assertTheEngineLines([expected], "decode")
        let decodeEntry = try XCTUnwrap(engineEntries.first)
        XCTAssertFalse(decodeEntry.message.contains("\n"), "\(decodeEntry.message.debugDescription)")
        XCTAssertFalse(LogLine.line(decodeEntry).contains("\n"), "\(LogLine.line(decodeEntry).debugDescription)")

        HelmLog.shared.clearTail()
        let bytes = EngineReply.encode(Memo(text: "x"), for: EngineCommand(name: name), as: Self.sumMemo)
        XCTAssertEqual(try JSONDecoder().decode(Memo.self, from: bytes), Memo(text: "x"))
        assertTheEngineLines([expected], "encode")
        let encodeEntry = try XCTUnwrap(engineEntries.first)
        XCTAssertFalse(encodeEntry.message.contains("\n"), "\(encodeEntry.message.debugDescription)")
    }

    /// An empty name is not the name the call is for, and the line shows it as an
    /// empty pair of quotes, at both overloads, rather than as nothing between two
    /// spaces.
    func testAnEmptyNameInTheMismatchLineIsAnEmptyPairOfQuotes() throws {
        let expected = "command \"\" does not match the call of \"sum\""

        let memo: Memo? = EngineReply.decode(from: EngineCommand(name: "", payload: Data("{}".utf8)),
                                             as: Self.sumMemo)
        XCTAssertNil(memo)
        assertTheEngineLines([expected], "decode")

        HelmLog.shared.clearTail()
        let bytes = EngineReply.encode(Memo(text: "x"), for: EngineCommand(name: ""), as: Self.sumMemo)
        XCTAssertEqual(try JSONDecoder().decode(Memo.self, from: bytes), Memo(text: "x"))
        assertTheEngineLines([expected], "encode")
    }

    // MARK: - the line a coding failure writes

    /// A payload that cannot be read is written as the command, the type asked
    /// for and the case of the failure, one line per case `JSONDecoder` raises.
    func testAPayloadThatCannotBeReadIsWrittenAsTheCaseAndTheType() {
        let payloads: [(Data, String)] = [
            (Data("{}".utf8), "sum: payload not read as Memo — DecodingError.keyNotFound"),
            (Data("{\"text\":5}".utf8), "sum: payload not read as Memo — DecodingError.typeMismatch String"),
            (Data("{\"text\":null}".utf8), "sum: payload not read as Memo — DecodingError.valueNotFound String"),
            (Data("not json".utf8), "sum: payload not read as Memo — DecodingError.dataCorrupted"),
        ]
        for (payload, expected) in payloads {
            HelmLog.shared.clearTail()
            let memo: Memo? = EngineReply.decode(from: EngineCommand(name: "sum", payload: payload),
                                                 as: Self.sumMemo)
            XCTAssertNil(memo)
            assertTheEngineLines([expected], String(decoding: payload, as: UTF8.self))
        }
    }

    /// A reply JSON cannot hold, from the untyped overload, is the command, the
    /// type and the case of the failure.
    func testAReplyThatCannotBeWrittenIsWrittenAsTheCaseAndTheType() {
        let data = EngineReply.encode(Seconds(seconds: .nan), for: EngineCommand(name: "scan"))

        XCTAssertTrue(data.isEmpty)
        assertTheEngineLines(["scan: reply of Seconds not encoded — EncodingError.invalidValue Double"])
    }

    /// An event JSON cannot hold is the event's name, the type and the case of
    /// the failure.
    func testAnEventThatCannotBeWrittenIsWrittenAsTheCaseAndTheType() {
        LocalTransport().emit("state", encoding: Seconds(seconds: .infinity))

        assertTheEngineLines(["state: event of Seconds not encoded — EncodingError.invalidValue Double"])
    }

    /// An error that is no coding error is written as the name of its type and
    /// nothing it carries, at each place that writes one: the payload read, the
    /// reply written and the event written.
    func testAnErrorThatIsNoCodingErrorIsWrittenAsTheNameOfItsTypeAlone() {
        PlantedError.shared.error = SwiftFailure(note: "carried-text")

        XCTAssertNil(EngineReply.decode(ThrowsWhenRead.self,
                                        from: EngineCommand(name: "probe", payload: Data("{}".utf8))))
        assertTheEngineLines(["probe: payload not read as ThrowsWhenRead — SwiftFailure"], "decode")

        HelmLog.shared.clearTail()
        XCTAssertTrue(EngineReply.encode(ThrowsWhenWritten(), for: EngineCommand(name: "probe")).isEmpty)
        assertTheEngineLines(["probe: reply of ThrowsWhenWritten not encoded — SwiftFailure"], "encode")

        HelmLog.shared.clearTail()
        LocalTransport().emit("probe", encoding: ThrowsWhenWritten())
        assertTheEngineLines(["probe: event of ThrowsWhenWritten not encoded — SwiftFailure"], "emit")
    }

    // MARK: - what an error inside a coding error can put in the line

    /// The error the probe types below throw. A type's own `init(from:)` and
    /// `encode(to:)` are handed a decoder or an encoder and nothing of the row's,
    /// so the error comes from here.
    private final class PlantedError: @unchecked Sendable {
        static let shared = PlantedError()
        private let lock = NSLock()
        private var stored: Error = CocoaError(.fileReadUnknown)
        var error: Error {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    private struct ThrowsWhenRead: Decodable {
        init(from decoder: Decoder) throws { throw PlantedError.shared.error }
    }

    private struct ThrowsWhenWritten: Encodable {
        func encode(to encoder: Encoder) throws { throw PlantedError.shared.error }
    }

    private struct SwiftFailure: Error { let note: String }
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// What is thrown for one planted token: the error `init(from:)` throws and
    /// the one `encode(to:)` throws. A side that is `nil` plants nothing there,
    /// and the entry points that side feeds are not driven: the token is a field
    /// of an error only one side can raise.
    private struct Planting {
        let whenRead: ((String) -> Error)?
        let whenWritten: ((String) -> Error)?
    }

    /// A coding error of each side carrying `underlying`, `debug` and `path`.
    private func coding(underlying: @escaping (String) -> Error? = { _ in nil },
                        debug: @escaping (String) -> String = { _ in "not valid" },
                        path: @escaping (String) -> [CodingKey] = { _ in [] }) -> Planting {
        Planting(
            whenRead: { token in
                DecodingError.dataCorrupted(.init(codingPath: path(token),
                                                  debugDescription: debug(token),
                                                  underlyingError: underlying(token)))
            },
            whenWritten: { token in
                EncodingError.invalidValue("value", .init(codingPath: path(token),
                                                          debugDescription: debug(token),
                                                          underlyingError: underlying(token)))
            })
    }

    /// An error that is no coding error, thrown as it is.
    private func thrown(_ make: @escaping (String) -> Error) -> Planting {
        Planting(whenRead: make, whenWritten: make)
    }

    /// The token as the value an `EncodingError.invalidValue` carries, the one
    /// field of the error that names what was being written.
    private func codingValue(_ value: @escaping (String) -> Any) -> Planting {
        Planting(whenRead: nil,
                 whenWritten: { token in
                     EncodingError.invalidValue(value(token),
                                                .init(codingPath: [], debugDescription: "not valid"))
                 })
    }

    /// The token as the key of a `DecodingError.keyNotFound`, the one field of
    /// the error that names what was being read.
    private func missingKey(_ key: @escaping (String) -> CodingKey) -> Planting {
        Planting(whenRead: { token in
                     DecodingError.keyNotFound(key(token),
                                               .init(codingPath: [], debugDescription: "not valid"))
                 },
                 whenWritten: nil)
    }

    private func described(_ token: String) -> Error {
        NSError(domain: "Probe", code: 7, userInfo: [NSLocalizedDescriptionKey: token])
    }

    private func withReason(_ token: String) -> Error {
        NSError(domain: "Probe", code: 7, userInfo: [NSLocalizedFailureReasonErrorKey: token])
    }

    private func withPath(_ token: String) -> Error {
        NSError(domain: "Probe", code: 7,
                userInfo: [NSFilePathErrorKey: "/Users/someone/Documents/\(token).pdf"])
    }

    private func inDomain(_ token: String) -> Error {
        NSError(domain: token, code: 7)
    }

    /// Feeds the planting through the places that write an error into the log
    /// that its sides name — the payload read, the reply written and the event
    /// written — and judges each line on its own. The line is shown to exist
    /// before the token is judged absent, so a log nobody wrote could not pass.
    private func assertTheTokenStaysOutOfTheLine(of planting: Planting,
                                                 file: StaticString = #filePath, line: UInt = #line) {
        let token = UUID().uuidString

        func judge(_ entryPoint: String) {
            let lines = engineLines
            XCTAssertEqual(lines.count, 1, "\(entryPoint): the line does not exist, so absence proves "
                           + "nothing: \(lines)", file: file, line: line)
            XCTAssertFalse(lines.contains { $0.range(of: token, options: .caseInsensitive) != nil },
                           "\(entryPoint): the token reached the line: \(lines)", file: file, line: line)
            HelmLog.shared.clearTail()
        }

        HelmLog.shared.clearTail()
        if let whenRead = planting.whenRead {
            PlantedError.shared.error = whenRead(token)
            XCTAssertNil(EngineReply.decode(ThrowsWhenRead.self,
                                            from: EngineCommand(name: "probe", payload: Data("{}".utf8))),
                         file: file, line: line)
            judge("decode")
        }

        if let whenWritten = planting.whenWritten {
            PlantedError.shared.error = whenWritten(token)
            XCTAssertTrue(EngineReply.encode(ThrowsWhenWritten(), for: EngineCommand(name: "probe")).isEmpty,
                          file: file, line: line)
            judge("encode")

            LocalTransport().emit("probe", encoding: ThrowsWhenWritten())
            judge("emit")
        }
    }

    func testATokenInAnUnderlyingErrorsDescriptionStaysOutOfTheLine() {
        assertTheTokenStaysOutOfTheLine(of: coding(underlying: described))
    }

    func testATokenInAnUnderlyingErrorsFailureReasonStaysOutOfTheLine() {
        assertTheTokenStaysOutOfTheLine(of: coding(underlying: withReason))
    }

    func testATokenInAnUnderlyingErrorsFilePathStaysOutOfTheLine() {
        assertTheTokenStaysOutOfTheLine(of: coding(underlying: withPath))
    }

    func testATokenInAnUnderlyingSwiftErrorStaysOutOfTheLine() {
        assertTheTokenStaysOutOfTheLine(of: coding(underlying: { SwiftFailure(note: $0) }))
    }

    func testATokenInACodingErrorsDebugDescriptionStaysOutOfTheLine() {
        assertTheTokenStaysOutOfTheLine(of: coding(debug: { "no value for \($0)" }))
    }

    func testATokenInACodingPathKeyStaysOutOfTheLine() {
        assertTheTokenStaysOutOfTheLine(of: coding(path: { [Key(stringValue: $0)] }))
    }

    func testATokenInAThrownSwiftErrorThatIsNoCodingErrorStaysOutOfTheLine() {
        assertTheTokenStaysOutOfTheLine(of: thrown { SwiftFailure(note: $0) })
    }

    func testATokenInAThrownErrorsDescriptionStaysOutOfTheLine() {
        assertTheTokenStaysOutOfTheLine(of: thrown(described))
    }

    func testATokenInAThrownErrorsFailureReasonStaysOutOfTheLine() {
        assertTheTokenStaysOutOfTheLine(of: thrown(withReason))
    }

    func testATokenInAThrownErrorsFilePathStaysOutOfTheLine() {
        assertTheTokenStaysOutOfTheLine(of: thrown(withPath))
    }

    func testATokenAsTheValueOfAnEncodingErrorStaysOutOfTheLine() {
        assertTheTokenStaysOutOfTheLine(of: codingValue { $0 })
    }

    func testATokenAsTheKeyOfAMissingKeyStaysOutOfTheLine() {
        assertTheTokenStaysOutOfTheLine(of: missingKey { Key(stringValue: $0) })
    }

    func testATokenAsAThrownErrorsDomainStaysOutOfTheLine() {
        assertTheTokenStaysOutOfTheLine(of: thrown(inDomain))
    }

    func testATokenAsAnUnderlyingErrorsDomainStaysOutOfTheLine() {
        assertTheTokenStaysOutOfTheLine(of: coding(underlying: inDomain))
    }
}
