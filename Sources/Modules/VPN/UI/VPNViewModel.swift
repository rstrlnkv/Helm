import SwiftUI
import HelmContract
import HelmUI
import Module_VPN_Engine

@MainActor public final class VPNViewModel: ObservableObject {
    @Published public private(set) var connections: [VPNConnection] = []
    @Published public private(set) var autoConnected: Set<String> = []
    @Published public private(set) var defaultName: String?

    private let transport: EngineTransport
    public init(transport: EngineTransport) {
        self.transport = transport
        let events = transport.events
        Task { [weak self] in for await e in events { await self?.handle(e) } }
        // Ask the engine to publish current state.
        send("refresh")
    }
    /// The engine's own declaration — see the note on KeepAwake's.
    private typealias StatePayload = VPNEngine.StatePayload
    private func handle(_ e: EngineEvent) {
        guard e.name == "state",
              let p = try? JSONDecoder().decode(StatePayload.self, from: e.payload) else { return }
        connections = p.connections
        autoConnected = Set(p.autoConnected)
        defaultName = p.defaultName
    }
    public func send(_ name: String, payload: Data = Data()) {
        Task { _ = try? await transport.send(EngineCommand(name: name, payload: payload)) }
    }
    public func connect(_ name: String) { send("connect", payload: nameData(name)) }
    public func disconnect(_ name: String) { send("disconnect", payload: nameData(name)) }
    public func toggleDefault() { send("toggle") }
    private func nameData(_ name: String) -> Data {
        struct P: Codable { let name: String }
        return (try? JSONEncoder().encode(P(name: name))) ?? Data()
    }
}
