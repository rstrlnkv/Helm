import SwiftUI
import HelmContract
import Combine

/// What every module's UI is handed: a way to talk to its engine, and nothing
/// else.
///
/// It used to publish five values — `isActive`, `activeConditions`,
/// `clamshellActive`, `endDate`, `startDate` — and decode a `state` payload of
/// one specific shape. That shape was Keep Awake's. Every other module got five
/// properties that stayed at their defaults forever and a task that failed to
/// decode its own engine's events. A module that needs view state builds its
/// own, as `VPNDescriptor` and `KeepAwakeDescriptor` do.
@MainActor public final class ModuleViewModel: ObservableObject {
    public let transport: EngineTransport

    public init(transport: EngineTransport) {
        self.transport = transport
    }

    /// Fire-and-forget command to the engine.
    public func send(_ name: String, payload: Data = Data()) {
        Task { _ = try? await transport.send(EngineCommand(name: name, payload: payload)) }
    }

    /// The same, named by a module's own command enum rather than by a string
    /// the engine may or may not recognise. `TransportClient` carries the same
    /// pair of spellings and the same reason.
    public func send<C: RawRepresentable>(_ command: C, payload: Data = Data())
    where C.RawValue == String {
        send(command.rawValue, payload: payload)
    }
}
