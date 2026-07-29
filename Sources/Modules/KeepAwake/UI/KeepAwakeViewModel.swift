import SwiftUI
import HelmContract
import HelmUI
import Module_KeepAwake_Engine

/// Keep Awake's own view state.
///
/// These five values used to live on `ModuleViewModel`, the type every module
/// is handed. `clamshellActive` is a notion that exists in exactly one module;
/// the decoder there expected this module's `state` payload, so VPN — which
/// emits an event of the same name and a different shape — failed to decode it
/// on every poll and left all five at their defaults forever. Every other
/// module carried five dead `@Published` properties and a task decoding
/// something it would never understand.
///
/// Cached per host view model, the way `VPNDescriptor` already caches its own:
/// the descriptor, the panel tile and the settings page must all see one object.
@MainActor public final class KeepAwakeViewModel: ObservableObject {
    @Published public private(set) var isActive = false
    @Published public private(set) var activeConditions: Set<String> = []
    @Published public private(set) var clamshellActive = false
    @Published public private(set) var endDate: Date?
    /// Start of the current timed session, for progress rendering.
    @Published public private(set) var startDate: Date?

    public let vm: ModuleViewModel

    private var eventsTask: Task<Void, Never>?

    private static var cached: KeepAwakeViewModel?

    public static func shared(vm: ModuleViewModel) -> KeepAwakeViewModel {
        // Keyed to the host view model: turning the module off and on builds a
        // new one, and the old cache would be talking to a dead engine.
        if let cached, cached.vm === vm { return cached }
        let created = KeepAwakeViewModel(vm: vm)
        cached = created
        ModuleUICache.dropWhenDisabled("keep-awake") { cached = nil }
        return created
    }

    private init(vm: ModuleViewModel) {
        self.vm = vm
        let events = vm.transport.events
        eventsTask = Task { [weak self] in
            for await event in events {
                guard let self else { break }
                await self.handle(event)
            }
        }
    }

    /// Ends the event loop, which unregisters the transport subscriber.
    /// `await self?.handle(…)` already let the view model itself go, but the
    /// task outlived it, and with it the registration.
    deinit { eventsTask?.cancel() }

    /// The engine's own declaration. There is no compiler between the two
    /// sides of a JSON hop, so a second copy here could drift silently.
    private typealias StatePayload = KeepAwakeEngine.StatePayload

    private func handle(_ event: EngineEvent) {
        guard event.name == "state",
              let p = try? JSONDecoder().decode(StatePayload.self, from: event.payload) else { return }
        isActive = p.isActive
        activeConditions = Set(p.conditions)
        clamshellActive = p.clamshellActive
        endDate = p.endDate
        startDate = p.startDate
    }

    public func send(_ name: String, payload: Data = Data()) { vm.send(name, payload: payload) }
}
