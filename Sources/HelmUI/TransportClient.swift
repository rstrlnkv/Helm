import Foundation
import HelmContract

/// Typed request/fire facade over an `EngineTransport`: JSON payloads in, JSON
/// replies out. Module view models were each re-implementing this plumbing.
@MainActor public struct TransportClient {
    private let transport: EngineTransport

    public init(_ transport: EngineTransport) { self.transport = transport }

    /// Request/response with no payload.
    public func request<T: Decodable>(_ name: String, as type: T.Type = T.self) async -> T? {
        await request(name, payload: Data(), as: type)
    }

    /// Request/response with a JSON-encoded payload.
    public func request<T: Decodable, P: Encodable>(_ name: String, encoding payload: P,
                                                    as type: T.Type = T.self) async -> T? {
        await request(name, payload: (try? JSONEncoder().encode(payload)) ?? Data(), as: type)
    }

    /// Request/response with a raw payload (e.g. a plain UTF-8 string).
    public func request<T: Decodable>(_ name: String, payload: Data, as type: T.Type = T.self) async -> T? {
        guard let data = try? await transport.send(EngineCommand(name: name, payload: payload)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Fire-and-forget command (progress, if any, arrives via transport events).
    public func fire(_ name: String, payload: Data = Data()) {
        Task { _ = try? await transport.send(EngineCommand(name: name, payload: payload)) }
    }

    public func fire<P: Encodable>(_ name: String, encoding payload: P) {
        fire(name, payload: (try? JSONEncoder().encode(payload)) ?? Data())
    }

    /// Awaitable command whose reply carries no data.
    public func send<P: Encodable>(_ name: String, encoding payload: P) async {
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
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

/// The same four calls, taking a module's own command enum instead of a string.
///
/// **A command name is a string on both sides and nothing checked that they
/// agreed.** A name the engine does not know falls to its `default`, the caller
/// decodes nothing and reads `nil`, which this codebase spells "the module could
/// not answer" — so a typo is indistinguishable from a refusal, and the only
/// symptom is a feature that quietly does nothing. Each module now declares its
/// commands as an enum its engine switches over exhaustively; these overloads
/// are what let the call site name the same enum rather than retyping the
/// string.
///
/// Generic over `RawRepresentable` rather than a protocol of our own: the enums
/// live in nine engine targets and this one knows about none of them, which is
/// the point — `HelmUI` is below every module, not beside them.
public extension TransportClient {
    func request<C: RawRepresentable, T: Decodable>(_ command: C, as type: T.Type = T.self) async -> T?
    where C.RawValue == String {
        await request(command.rawValue, as: type)
    }

    func request<C: RawRepresentable, T: Decodable, P: Encodable>(
        _ command: C, encoding payload: P, as type: T.Type = T.self) async -> T?
    where C.RawValue == String {
        await request(command.rawValue, encoding: payload, as: type)
    }

    func request<C: RawRepresentable, T: Decodable>(_ command: C, payload: Data,
                                                    as type: T.Type = T.self) async -> T?
    where C.RawValue == String {
        await request(command.rawValue, payload: payload, as: type)
    }

    func fire<C: RawRepresentable>(_ command: C, payload: Data = Data()) where C.RawValue == String {
        fire(command.rawValue, payload: payload)
    }

    func fire<C: RawRepresentable, P: Encodable>(_ command: C, encoding payload: P)
    where C.RawValue == String {
        fire(command.rawValue, encoding: payload)
    }

    func send<C: RawRepresentable, P: Encodable>(_ command: C, encoding payload: P) async
    where C.RawValue == String {
        await send(command.rawValue, encoding: payload)
    }

    func send<C: RawRepresentable>(_ command: C, payload: Data = Data()) async
    where C.RawValue == String {
        await send(command.rawValue, payload: payload)
    }
}
