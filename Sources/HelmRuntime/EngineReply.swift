import Foundation
import HelmContract

/// The engine side of the transport's JSON: payloads in, replies out.
///
/// `TransportClient` is the same thing for the caller's side of the wire, and it
/// exists because every view model was re-implementing the plumbing. The engines
/// never got the mirror: nine `wireTransport` handlers spelled
/// `(try? JSONEncoder().encode(x)) ?? Data()` and
/// `guard let y = try? JSONDecoder().decode(T.self, from: cmd.payload) else { return Data() }`
/// by hand, dozens of times, and one of them had grown a local `json(_:)` of its
/// own.
///
/// **A failure is written down, and that is the whole difference.** An empty
/// reply is how this codebase says "the module could not answer", so a payload
/// that would not decode, a reply that would not encode and an arm that
/// deliberately answers nothing all left the same zero bytes and no trace —
/// `TransportClient`'s own doc comment names the consequence: a typo is
/// indistinguishable from a refusal, and the only symptom is a feature that
/// quietly does nothing. Both calls here still answer the same bytes they always
/// did; they also log, at `error`, in one place, identically for all nine
/// engines. `#fileID` and `#line` default in from the call site, so the line
/// names the engine and the arm — a bare command name would not, since
/// `scan` and `trash` are spelled the same in three modules each.
///
/// **The line carries the command and the type it wanted, never the payload.**
/// A payload names somebody's files; the log carries no names.
///
/// Here rather than in `HelmContract`, which is where `EngineCommand` lives, for
/// one reason: this logs, `HelmLog` is in `HelmRuntime`, and pointing the
/// contract at the runtime would forbid the edge that runs the other way — the
/// one `ScanRunner.scannableModules` is waiting for the day it takes `ModuleID`
/// instead of strings. `HelmRuntime` is what every engine target shares, exactly
/// as `HelmUI` is what every UI target shares, so the mirror sits at the
/// matching altitude.
/// A handler's own `return Data()` stays as it is, deliberately. It is the reply
/// of an arm that has nothing to answer, and a constant named for it would be
/// longer to write while still claiming a distinction the wire cannot carry —
/// zero bytes are zero bytes whether the engine acknowledged, declined or could
/// not encode. The log is the only place those three can differ, which is why
/// both calls below write one.
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
            HelmLog.shared.error("engine", "\(command.name): reply of \(T.self) not encoded — "
                                 + HelmFailure.describe(error),
                                 fileID: fileID, line: line, function: function)
            return Data()
        }
    }

    /// A command's payload as the type the arm needs, or `nil` with the reason
    /// logged. The caller still decides what to answer — every arm today answers
    /// an empty reply.
    public static func decode<T: Decodable>(_ type: T.Type, from command: EngineCommand,
                                            fileID: String = #fileID, line: Int = #line,
                                            function: String = #function) -> T? {
        do {
            return try JSONDecoder().decode(type, from: command.payload)
        } catch {
            HelmLog.shared.error("engine", "\(command.name): payload not read as \(T.self) — "
                                 + HelmFailure.describe(error),
                                 fileID: fileID, line: line, function: function)
            return nil
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
            HelmLog.shared.error("engine", "\(name): event of \(T.self) not encoded — "
                                 + HelmFailure.describe(error),
                                 fileID: fileID, line: line, function: function)
        }
    }
}
