import SwiftUI
import HelmContract
import HelmUI
import Module_VPN_Engine

@MainActor public final class VPNViewModel: ObservableObject {
    @Published public private(set) var connections: [VPNConnection] = []
    @Published public private(set) var autoConnected: Set<String> = []
    @Published public private(set) var defaultName: String?

    private let transport: EngineTransport
    private var eventsTask: Task<Void, Never>?

    public init(transport: EngineTransport) {
        self.transport = transport
        let events = transport.events
        eventsTask = Task { [weak self] in
            for await e in events {
                guard let self else { break }
                self.handle(e)
            }
        }
        // Ask the engine to publish current state.
        send("refresh")
    }

    /// Ends the event loop, which unregisters the transport subscriber.
    deinit { eventsTask?.cancel() }

    /// Re-reads the system's answer.
    ///
    /// The engine is asked once in `init` and then only after Helm itself
    /// connects or disconnects, so a tunnel raised from the macOS menu bar,
    /// from System Settings, or one that simply dropped, left this showing
    /// yesterday's state for as long as the app ran.
    public func refresh() { send("refresh") }
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
