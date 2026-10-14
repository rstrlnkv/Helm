import Foundation
import HelmContract

/// The engine side of the transport's JSON: payloads in, replies out.
///
/// `TransportClient` is the same thing for the caller's side of the wire. An
/// engine handler that spells `(try? JSONEncoder().encode(x)) ?? Data()` or
/// `guard let y = try? JSONDecoder().decode(T.self, from: cmd.payload) else { return Data() }`
/// by hand writes nothing down when it fails.
///
/// **A failure is written down, and that is the whole difference.** An empty
/// reply is how this codebase says "the module could not answer", so a payload
/// that would not decode, a reply that would not encode and an arm that
/// deliberately answers nothing all leave the same zero bytes. Spelled by hand
/// the first two leave no trace either: a typo is indistinguishable from a
/// refusal, and the only symptom is a feature that quietly does nothing. The two
/// untyped calls here answer empty `Data` or `nil` for a failure, and also log
/// it, at `error`, in one place for every engine. `#fileID` and `#line` default
/// in from the call site, so the line names the file and the line of the arm
/// that asked.
///
/// **A typed call names a case, and the command that arrived must be that
/// case.** The two typed overloads take an `EngineCall`, whose `command` is the
/// case the arm serves. When the name of the `EngineCommand` is not that case's
/// raw value, `decode(from:as:)` decodes nothing and answers `nil`, and
/// `encode(_:for:as:)` still hands the bytes; each writes the same one `error`
/// line under `engine`, naming both names. A command that is the call's own case
/// writes no such line.
///
/// **No line carries the payload or the error's own words.** A payload names
/// somebody's files; the log carries no names. The line of a coding failure
/// carries the command, the type the call site asked for and the kind of
/// failure; the mismatch line carries the two names. `kind(of:)` spells the case
/// of a `DecodingError` or an `EncodingError` itself, and for any other error the
/// name of its type, because a payload type's own `init(from:)` or a reply
/// type's own `encode(to:)` may throw an error that carries what it was handed.
///
/// Here rather than in `HelmContract`, which is where `EngineCommand` lives, for
/// one reason: this logs, `HelmLog` is in `HelmRuntime`, and `HelmRuntime`
/// depends on `HelmContract`, so pointing the contract at the runtime would close
/// a cycle. `HelmRuntime` is what every engine target shares, exactly as
/// `HelmUI` is what every UI target shares, so the mirror sits at the matching
/// altitude.
///
/// A handler's own `return Data()` stays as it is, deliberately. It is the reply
/// of an arm that has nothing to answer, and a constant named for it would be
/// longer to write while still claiming a distinction the wire cannot carry —
/// zero bytes are zero bytes whether the engine acknowledged, declined or could
/// not encode. The log is the only place those three can differ, which is why a
/// failure in any of these calls writes a line.
public enum EngineReply {

    /// A value as JSON, or empty `Data` with the reason logged.
    public static func encode<T: Encodable>(_ value: T, for command: EngineCommand,
                                            fileID: String = #fileID, line: Int = #line,
                                            function: String = #function) -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            // Reachable, not theoretical: `JSONEncoder` refuses a
            // non-conforming float, and a reply carrying a `TimeInterval` is one
            // division away from `nan`.
            HelmLog.shared.error("engine", "\(command.name): reply of \(T.self) not encoded — \(kind(of: error))",
                                 fileID: fileID, line: line, function: function)
            return Data()
        }
    }

    /// A command's payload as the type the arm needs, or `nil` with the reason
    /// logged. The caller decides what to answer.
    public static func decode<T: Decodable>(_ type: T.Type, from command: EngineCommand,
                                            fileID: String = #fileID, line: Int = #line,
                                            function: String = #function) -> T? {
        do {
            return try JSONDecoder().decode(type, from: command.payload)
        } catch {
            HelmLog.shared.error("engine", "\(command.name): payload not read as \(T.self) — \(kind(of: error))",
                                 fileID: fileID, line: line, function: function)
            return nil
        }
    }

    /// A reply of the call's own `Reply`: `encode(_:for:)`, which this calls, with
    /// the type fixed by the call, so a reply Swift cannot convert to the type the
    /// call declares does not compile, where the untyped overload takes whatever
    /// the arm hands it. A command that is not the call's own case writes the
    /// mismatch line first, and the bytes are still handed.
    public static func encode<Command, Payload, Reply>(
        _ reply: Reply, for command: EngineCommand,
        as call: EngineCall<Command, Payload, Reply>,
        fileID: String = #fileID, line: Int = #line, function: String = #function
    ) -> Data {
        _ = matches(command, caseNamed: call.command.rawValue,
                    fileID: fileID, line: line, function: function)
        return encode(reply, for: command, fileID: fileID, line: line, function: function)
    }

    /// A command's payload as the call's own `Payload`, or `nil` with the reason
    /// logged — `decode(_:from:)` with the type taken from the call, so the arm
    /// names no type of its own. A command that is not the call's own case is
    /// `nil` too, with the mismatch line, and nothing is decoded.
    public static func decode<Command, Payload, Reply>(
        from command: EngineCommand, as call: EngineCall<Command, Payload, Reply>,
        fileID: String = #fileID, line: Int = #line, function: String = #function
    ) -> Payload? {
        guard matches(command, caseNamed: call.command.rawValue,
                      fileID: fileID, line: line, function: function)
        else { return nil }
        return decode(Payload.self, from: command, fileID: fileID, line: line, function: function)
    }

    /// The only place a command that arrived under another case's name is written
    /// down: one `error` line under `engine` naming the name that arrived and the
    /// name the call is for, each as Swift spells a string literal, so an empty
    /// name reads as `""` and one with a line break cannot pass for two lines. No
    /// byte of the payload is read for it. `true`, with nothing written, when the
    /// command is the call's own case.
    private static func matches(_ command: EngineCommand, caseNamed expected: String,
                                fileID: String, line: Int, function: String) -> Bool {
        guard command.name != expected else { return true }
        HelmLog.shared.error("engine", "command \(command.name.debugDescription) does not match the call of "
                             + expected.debugDescription,
                             fileID: fileID, line: line, function: function)
        return false
    }

    /// What a line may say about a failure: for a `DecodingError` or an
    /// `EncodingError` the case and the type it names, spelled here, and for any
    /// other error its type's name alone. Nothing of the error's `context` is read,
    /// neither its `debugDescription`, nor its `codingPath`, whose keys on a
    /// payload are the sender's, nor its underlying error. `HelmFailure.describe`
    /// is not asked: it prints an underlying error's description, failure reason
    /// and path, and an error it does not know with `String(describing:)`, and a
    /// payload type's own `init(from:)` or a reply's or an event's own
    /// `encode(to:)` may throw one carrying what it was handed.
    fileprivate static func kind(of error: Error) -> String {
        switch error {
        case let error as DecodingError:
            switch error {
            case .typeMismatch(let asked, _): return "DecodingError.typeMismatch \(asked)"
            case .valueNotFound(let asked, _): return "DecodingError.valueNotFound \(asked)"
            case .keyNotFound: return "DecodingError.keyNotFound"
            case .dataCorrupted: return "DecodingError.dataCorrupted"
            @unknown default: return "DecodingError"
            }
        case let error as EncodingError:
            switch error {
            case .invalidValue(let value, _): return "EncodingError.invalidValue \(type(of: value))"
            @unknown default: return "EncodingError"
            }
        default: return "\(type(of: error))"
        }
    }
}

/// The event side of the same plumbing, and the same rule about failure.
///
/// Five engines spelled `if let data = try? JSONEncoder().encode(x) { emit(…) }`
/// and a sixth spelled `?? Data()`, which is worse than it looks: `emit` keeps
/// the last event **per name** to replay to late subscribers, so an event whose
/// payload failed to encode took the slot a good one was holding, and a page
/// opened afterwards was handed a state it could not decode. One spelling now,
/// and the failed encoding is a line in the log rather than an event nobody can
/// read.
public extension LocalTransport {

    /// Emits `event` carrying `value` as JSON — or emits nothing, and says why.
    ///
    /// Retroactive on `HelmContract`'s class rather than declared beside it,
    /// because this logs and the log is here. Takes the module's own event enum,
    /// as `TransportClient.fire` takes its command enum: the name is a string on
    /// both sides of the wire and nothing but the enum checks that the two agree.
    func emit<E: RawRepresentable, T: Encodable>(_ event: E, encoding value: T,
                                                 fileID: String = #fileID, line: Int = #line,
                                                 function: String = #function)
    where E.RawValue == String {
        emit(event.rawValue, encoding: value, fileID: fileID, line: line, function: function)
    }

    func emit<T: Encodable>(_ name: String, encoding value: T,
                            fileID: String = #fileID, line: Int = #line,
                            function: String = #function) {
        do {
            emit(EngineEvent(name: name, payload: try JSONEncoder().encode(value)))
        } catch {
            HelmLog.shared.error("engine", "\(name): event of \(T.self) not encoded — \(EngineReply.kind(of: error))",
                                 fileID: fileID, line: line, function: function)
        }
    }
}

/// The command side of the same plumbing, and the same rule about failure.
///
/// A handler that parses the name by hand, with
/// `guard let name = XCommand(rawValue: command.name) else { return Data() }`,
/// writes nothing when the parse fails: a name the enum cannot parse — a caller
/// that spelled a literal, an enum that lost a case — gets the same zero bytes
/// as an arm that answers nothing, and the only symptom is a feature that
/// quietly does nothing. Here the parse is written once, where the log is, and
/// this prints the handlers that parse by hand:
///
///     command grep -rnE 'Command\(rawValue: *[a-zA-Z]+\.name\)' Sources/Modules/*/Engine
public extension LocalTransport {

    /// Installs a handler that receives the command already parsed into the
    /// module's own enum, beside the `EngineCommand` for its payload.
    ///
    /// A name the enum cannot parse is answered with empty `Data`, as it always
    /// was, and now leaves one line under `engine` naming `module` and the name,
    /// never the payload. `module` is the engine's `moduleID`, which every engine
    /// already holds as a `String`. A name that parses reaches `handler` and
    /// writes nothing. The handler is the engine's closure with its own guard
    /// taken out: the parsed case is the first parameter, and the switch over it
    /// still has no `default` arm.
    ///
    /// The name is written as Swift spells a string literal, so an empty name
    /// reads as `""` and one with a line break cannot pass for two lines.
    func setHandler<Command: RawRepresentable & Sendable>(
        for commands: Command.Type, module: String,
        _ handler: @escaping @Sendable (Command, EngineCommand) async throws -> Data
    ) where Command.RawValue == String {
        setHandler { command in
            guard let parsed = Command(rawValue: command.name) else {
                HelmLog.shared.error("engine",
                                     "\(module): no command named \(command.name.debugDescription)")
                return Data()
            }
            return try await handler(parsed, command)
        }
    }
}
