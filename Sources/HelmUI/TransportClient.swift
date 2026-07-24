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
}
