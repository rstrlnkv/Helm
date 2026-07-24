import Foundation

public final class LocalTransport: EngineTransport, @unchecked Sendable {
    public typealias Handler = @Sendable (EngineCommand) async throws -> Data
    private var handler: Handler = { _ in Data() }
    private let continuation: AsyncStream<EngineEvent>.Continuation
    public let events: AsyncStream<EngineEvent>
    public init() {
        var cont: AsyncStream<EngineEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }
    public func setHandler(_ h: @escaping Handler) { handler = h }
    public func emit(_ e: EngineEvent) { continuation.yield(e) }
    public func send(_ c: EngineCommand) async throws -> Data { try await handler(c) }
}
