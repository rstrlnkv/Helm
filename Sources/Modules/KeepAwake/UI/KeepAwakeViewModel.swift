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
    /// The engine's own cases, not the strings they travel as. Held as
    /// `Set<String>`, every view that asked a question about them had to spell
    /// the wire names again — `["externalDisplay", "power", "app"]`, twice —
    /// and `KAStr` switched over five more literals to turn one back into a
    /// word. A name that stops matching is not an error anywhere; the row just
    /// goes quiet.
    @Published public private(set) var activeConditions: Set<ActiveCondition> = []
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
        ModuleUICache.dropWhenDisabled(KeepAwakeDescriptor.id.rawValue) { cached = nil }
        return created
    }

    private init(vm: ModuleViewModel) {
        self.vm = vm
        let events = vm.transport.events
        eventsTask = Task { [weak self] in
            for await event in events {
                guard let self else { break }
                self.handle(event)
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
        guard KeepAwakeEvent(rawValue: event.name) == .state,
              let p = try? JSONDecoder().decode(StatePayload.self, from: event.payload) else { return }
        isActive = p.isActive
        // A name this build does not know is dropped rather than carried as a
        // string nothing can match — the wire is the engine's enum either way.
        activeConditions = Set(p.conditions.compactMap(ActiveCondition.init(rawValue:)))
        clamshellActive = p.clamshellActive
        endDate = p.endDate
        startDate = p.startDate
    }

    /// Named by the engine's own enum, and only that.
    ///
    /// A `send(_ name: String, …)` sat beside this under a comment saying the
    /// string spelling stayed «for the panel tile's generic paths; nothing new
    /// should use it». There are no such paths left — every call site in both
    /// screens names `KeepAwakeCommand` — so what remained was a door back to
    /// the defect the enum was introduced to close, held open by its own
    /// promise not to be used.
    public func send(_ command: KeepAwakeCommand, payload: Data = Data()) {
        vm.send(command, payload: payload)
    }
}
