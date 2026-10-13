import Foundation
import HelmContract
import HelmRuntime

/// Typed request/fire facade over an `EngineTransport`: JSON payloads in, JSON
/// replies out. Module view models were each re-implementing this plumbing.
///
/// **What the client itself could not do is written down, and no byte or return
/// value moves for it.** A payload that will not encode is still sent as empty
/// `Data`, and a non-empty reply that will not decode is still `nil`; each also
/// leaves one `error` line under `client`, the screen's half of what
/// `EngineReply` does for the engine, except for a reply of exactly `null`. An
/// empty reply leaves no line, and neither does a reply of exactly `null`: an
/// engine answers empty when it has nothing to say and when it declined, the
/// client cannot tell which, and answers `null` when an arm encodes an optional
/// that is `nil`. The client reads each as `nil`, except that `null` asked as a
/// type that decodes from it returns what that type makes of it. The line
/// carries the command, the type and the kind of failure, never a payload byte
/// or a reply byte, and `#fileID` and `#line` default in from the call site so
/// it names the screen that asked.
@MainActor public struct TransportClient {
    private let transport: EngineTransport

    public init(_ transport: EngineTransport) { self.transport = transport }

    /// The only place a payload that will not encode is written down.
    private static func encoded<P: Encodable>(_ payload: P, for name: String,
                                              fileID: String, line: Int, function: String) -> Data {
        do {
            return try JSONEncoder().encode(payload)
        } catch {
            HelmLog.shared.error("client", "\(name): payload of \(P.self) not encoded — \(kind(of: error))",
                                 fileID: fileID, line: line, function: function)
            return Data()
        }
    }

    /// The only place a non-empty reply that will not decode is written down. The
    /// four bytes `null` are what `EngineReply.encode` writes for an optional that
    /// is `nil`: no answer, not a refusal, so they are `nil` with no line. They are
    /// looked for after the decode has failed, so a type that decodes from `null`
    /// still returns what it decodes to.
    private static func decoded<T: Decodable>(_ type: T.Type, from reply: Data, for name: String,
                                              fileID: String, line: Int, function: String) -> T? {
        guard !reply.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(type, from: reply)
        } catch {
            guard reply != Data("null".utf8) else { return nil }
            HelmLog.shared.error("client", "\(name): reply not read as \(T.self) — \(kind(of: error))",
                                 fileID: fileID, line: line, function: function)
            return nil
        }
    }

    /// What a line may say about a failure: for a `DecodingError` or an
    /// `EncodingError` the case and the type it names, spelled here, and for any
    /// other error its type's name alone. Nothing of the error's `context` is read,
    /// neither its `debugDescription`, nor its `codingPath`, whose keys are the
    /// sender's, nor its underlying error. `HelmFailure.describe` is not asked: it
    /// prints an underlying error's description, failure reason and path, and an
    /// error it does not know with `String(describing:)`, and a payload's own
    /// `encode(to:)` or a reply type's own `init(from:)` may throw one carrying
    /// what it was handed.
    private static func kind(of error: Error) -> String {
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

    /// Request/response with no payload.
    public func request<T: Decodable>(_ name: String, as type: T.Type = T.self,
                                      fileID: String = #fileID, line: Int = #line,
                                      function: String = #function) async -> T? {
        await request(name, payload: Data(), as: type, fileID: fileID, line: line, function: function)
    }

    /// Request/response with a JSON-encoded payload.
    public func request<T: Decodable, P: Encodable>(_ name: String, encoding payload: P,
                                                    as type: T.Type = T.self,
                                                    fileID: String = #fileID, line: Int = #line,
                                                    function: String = #function) async -> T? {
        await request(name, payload: Self.encoded(payload, for: name, fileID: fileID, line: line,
                                                  function: function),
                      as: type, fileID: fileID, line: line, function: function)
    }

    /// Request/response with a raw payload (e.g. a plain UTF-8 string).
    public func request<T: Decodable>(_ name: String, payload: Data, as type: T.Type = T.self,
                                      fileID: String = #fileID, line: Int = #line,
                                      function: String = #function) async -> T? {
        guard let data = try? await transport.send(EngineCommand(name: name, payload: payload)) else { return nil }
        return Self.decoded(type, from: data, for: name, fileID: fileID, line: line, function: function)
    }

    /// Fire-and-forget command (progress, if any, arrives via transport events).
    public func fire(_ name: String, payload: Data = Data()) {
        Task { _ = try? await transport.send(EngineCommand(name: name, payload: payload)) }
    }

    public func fire<P: Encodable>(_ name: String, encoding payload: P,
                                   fileID: String = #fileID, line: Int = #line,
                                   function: String = #function) {
        fire(name, payload: Self.encoded(payload, for: name, fileID: fileID, line: line, function: function))
    }

    /// Awaitable command whose reply carries no data.
    public func send<P: Encodable>(_ name: String, encoding payload: P,
                                   fileID: String = #fileID, line: Int = #line,
                                   function: String = #function) async {
        let data = Self.encoded(payload, for: name, fileID: fileID, line: line, function: function)
        _ = try? await transport.send(EngineCommand(name: name, payload: data))
    }

    /// The same, for a command whose payload is raw rather than JSON — a plain
    /// UTF-8 string, say. `fire` already takes one; awaiting it is what a caller
    /// needs when the command writes something that has to survive the next
    /// moment, and the window that sent it is about to close.
    public func send(_ name: String, payload: Data = Data()) async {
        _ = try? await transport.send(EngineCommand(name: name, payload: payload))
    }
}

/// The same calls, taking a module's own command enum instead of a string.
///
/// **A command name is a string on both sides, and the enum is what keeps the two
/// spellings together.** A module declares its commands as an enum in its engine
/// target and its handler switches over them with no `default` arm. What a
/// handler does with a name its enum cannot parse depends on how it was
/// installed. `LocalTransport.setHandler(_:)` hands it the `EngineCommand` as it
/// arrived and the handler parses the name itself; this prints the handlers that
/// do, each of which answers empty `Data` and writes no line:
///
///     command grep -rnE 'Command\(rawValue: *[a-zA-Z]+\.name\)' Sources/Modules/*/Engine
///
/// `LocalTransport.setHandler(for:module:_:)` parses the name once, answers empty
/// `Data` for one it cannot parse and logs it under `engine`; this prints the
/// engines that install their handler that way:
///
///     command grep -rn 'setHandler(for' Sources/Modules
///
/// Either way the caller decodes nothing and reads `nil`, which this codebase
/// spells "the module could not answer", so a typo is indistinguishable from a
/// refusal on the screen's side. These overloads let the call site name the same
/// enum rather than retype the string.
///
/// Generic over `RawRepresentable` rather than a protocol of our own: the enums
/// live in the engine targets and this one knows about none of them, which is the
/// point — `HelmUI` is below every module, not beside them.
public extension TransportClient {
    func request<C: RawRepresentable, T: Decodable>(_ command: C, as type: T.Type = T.self,
                                                    fileID: String = #fileID, line: Int = #line,
                                                    function: String = #function) async -> T?
    where C.RawValue == String {
        await request(command.rawValue, as: type, fileID: fileID, line: line, function: function)
    }

    func request<C: RawRepresentable, T: Decodable, P: Encodable>(
        _ command: C, encoding payload: P, as type: T.Type = T.self,
        fileID: String = #fileID, line: Int = #line, function: String = #function) async -> T?
    where C.RawValue == String {
        await request(command.rawValue, encoding: payload, as: type,
                      fileID: fileID, line: line, function: function)
    }

    func request<C: RawRepresentable, T: Decodable>(_ command: C, payload: Data,
                                                    as type: T.Type = T.self,
                                                    fileID: String = #fileID, line: Int = #line,
                                                    function: String = #function) async -> T?
    where C.RawValue == String {
        await request(command.rawValue, payload: payload, as: type,
                      fileID: fileID, line: line, function: function)
    }

    func fire<C: RawRepresentable>(_ command: C, payload: Data = Data()) where C.RawValue == String {
        fire(command.rawValue, payload: payload)
    }

    func fire<C: RawRepresentable, P: Encodable>(_ command: C, encoding payload: P,
                                                 fileID: String = #fileID, line: Int = #line,
                                                 function: String = #function)
    where C.RawValue == String {
        fire(command.rawValue, encoding: payload, fileID: fileID, line: line, function: function)
    }

    func send<C: RawRepresentable, P: Encodable>(_ command: C, encoding payload: P,
                                                 fileID: String = #fileID, line: Int = #line,
                                                 function: String = #function) async
    where C.RawValue == String {
        await send(command.rawValue, encoding: payload, fileID: fileID, line: line, function: function)
    }

    func send<C: RawRepresentable>(_ command: C, payload: Data = Data()) async
    where C.RawValue == String {
        await send(command.rawValue, payload: payload)
    }
}

/// A call that carries its own types — an `EngineCall`, whose own doc comment
/// says where one is declared. The payload goes in as the call's `Payload` and
/// the reply comes back as its `Reply`, so a payload or a reply of another type
/// does not compile where the overloads above take whatever the call site
/// infers. `Never` in a position is a call with none there: a call with no
/// payload sends empty `Data`, and a call with no reply is one for `send` or
/// `fire`, though nothing stops `request` from taking it. `send` and `fire` do
/// not read the reply, so their `Reply` is whatever the call declares.
public extension TransportClient {
    func request<C, P, R>(_ call: EngineCall<C, P, R>, _ payload: P,
                          fileID: String = #fileID, line: Int = #line,
                          function: String = #function) async -> R? {
        await request(call.command, encoding: payload, as: R.self,
                      fileID: fileID, line: line, function: function)
    }

    func request<C, R>(_ call: EngineCall<C, Never, R>,
                       fileID: String = #fileID, line: Int = #line,
                       function: String = #function) async -> R? {
        await request(call.command, as: R.self, fileID: fileID, line: line, function: function)
    }

    func send<C, P, R>(_ call: EngineCall<C, P, R>, _ payload: P,
                       fileID: String = #fileID, line: Int = #line,
                       function: String = #function) async {
        await send(call.command, encoding: payload, fileID: fileID, line: line, function: function)
    }

    func send<C, R>(_ call: EngineCall<C, Never, R>) async {
        await send(call.command)
    }

    func fire<C, P, R>(_ call: EngineCall<C, P, R>, _ payload: P,
                       fileID: String = #fileID, line: Int = #line,
                       function: String = #function) {
        fire(call.command, encoding: payload, fileID: fileID, line: line, function: function)
    }

    func fire<C, R>(_ call: EngineCall<C, Never, R>) {
        fire(call.command)
    }
}
