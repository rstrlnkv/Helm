import SwiftUI
import HelmContract

@MainActor public final class ModuleViewModel: ObservableObject {
    @Published public private(set) var isActive = false
    @Published public private(set) var activeConditions: Set<String> = []
    @Published public private(set) var clamshellActive = false
    @Published public private(set) var endDate: Date?

    private let transport: EngineTransport

    public init(transport: EngineTransport) {
        self.transport = transport
        let events = transport.events
        Task { [weak self] in
            for await e in events { await self?.handle(e) }
        }
    }

    private struct StatePayload: Codable {
        let isActive: Bool; let conditions: [String]
        let clamshellActive: Bool; let endDate: Date?
    }

    private func handle(_ e: EngineEvent) {
        guard e.name == "state",
              let p = try? JSONDecoder().decode(StatePayload.self, from: e.payload) else { return }
        isActive = p.isActive
        activeConditions = Set(p.conditions)
        clamshellActive = p.clamshellActive
        endDate = p.endDate
    }

    /// Fire-and-forget command to the engine.
    public func send(_ name: String, payload: Data = Data()) {
        Task { _ = try? await transport.send(EngineCommand(name: name, payload: payload)) }
    }
}
