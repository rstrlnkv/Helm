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
    /// The store this view model was built with. `init(transport:store:)` takes
    /// it from the caller, and a caller that hands it the store
    /// `ModuleDescriptor.makeEngine(store:)` was handed gives a page and its
    /// engine the same keys. The host does not: `ModuleHost` hands its store to
    /// `makeEngine(store:)` and builds the view model through `init(transport:)`,
    /// so a live module's view model holds the empty store that initialiser
    /// builds, and a page that read this property would find none of its
    /// module's keys.
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
                  store: NamespacedStore(namespace: "unhosted",
                                         backing: InMemoryKeyValueStore()))
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
