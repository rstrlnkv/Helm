import SwiftUI
import HelmContract
import Combine
import HelmRuntime

/// What every module's UI is handed: a way to talk to its engine and a store,
/// and nothing else.
///
/// It used to publish five values — `isActive`, `activeConditions`,
/// `clamshellActive`, `endDate`, `startDate` — and decode a `state` payload of
/// one specific shape. That shape was Keep Awake's. Every other module got five
/// properties that stayed at their defaults forever and a task that failed to
/// decode its own engine's events. A module that needs view state builds its
/// own, as `VPNDescriptor` and `KeepAwakeDescriptor` do.
@MainActor public final class ModuleViewModel: ObservableObject {
    public let transport: EngineTransport
    /// The store this view model was built with. `init(transport:store:)` is how
    /// a page and its engine come to read the same keys: it takes the store
    /// `ModuleDescriptor.makeEngine(store:)` was handed. `init(transport:)` passes
    /// none, and the store is then the empty one that initialiser builds.
    public let store: NamespacedStore

    public init(transport: EngineTransport, store: NamespacedStore) {
        self.transport = transport
        self.store = store
    }

    /// A view model over a store of its own, which is empty and whose values
    /// nothing else reads: `InMemoryKeyValueStore`, built here for each view model,
    /// so two of them share no value and none reaches `UserDefaults`. Its namespace
    /// is no module's id, so nothing written here lands under a module's keys.
    public convenience init(transport: EngineTransport) {
        self.init(transport: transport,
                  store: NamespacedStore(namespace: Self.unhostedNamespace,
                                         backing: InMemoryKeyValueStore()))
    }

    private static let unhostedNamespace = "unhosted"

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
