import Foundation

public protocol EngineTransport: Sendable {
    func send(_ command: EngineCommand) async throws -> Data
    var events: AsyncStream<EngineEvent> { get }
}
