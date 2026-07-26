import Foundation
import HelmContract
import HelmRuntime
import HelmUI

/// Owns module lifecycle: per-module namespaced store, enabled flag, and
/// lazily-created engine + view model for every enabled module.
@MainActor final class ModuleHost: ObservableObject {
    static let shared = ModuleHost()

    struct Live {
        let descriptor: any ModuleDescriptor
        let engine: any ModuleEngine
        let vm: ModuleViewModel
        let store: NamespacedStore
    }

    /// Keyed by `ModuleID.rawValue`.
    @Published private(set) var live: [String: Live] = [:]

    private init() {}

    private func store(for d: any ModuleDescriptor) -> NamespacedStore {
        NamespacedStore(namespace: type(of: d).id.rawValue, backing: UserDefaults.standard)
    }

    func isEnabled(_ d: any ModuleDescriptor) -> Bool {
        store(for: d).bool("enabled", default: true)
    }

    func bootstrap() {
        ObsoleteDefaults.purge(from: UserDefaults.standard)
        for d in ModuleRegistry.all where isEnabled(d) { enable(d) }
    }

    func setEnabled(_ d: any ModuleDescriptor, _ on: Bool) {
        store(for: d).set(on, for: "enabled")
        if on {
            if live[type(of: d).id.rawValue] == nil { enable(d) }
        } else {
            disable(d)
        }
    }

    private func enable(_ d: any ModuleDescriptor) {
        HelmLog.shared.info("host", "enable \(type(of: d).id.rawValue)")
        let s = store(for: d)
        let engine = d.makeEngine(store: s)
        engine.activate()
        let vm = ModuleViewModel(transport: engine.transport)
        live[type(of: d).id.rawValue] = Live(descriptor: d, engine: engine, vm: vm, store: s)
    }

    private func disable(_ d: any ModuleDescriptor) {
        HelmLog.shared.info("host", "disable \(type(of: d).id.rawValue)")
        let key = type(of: d).id.rawValue
        live[key]?.engine.deactivate()
        live[key] = nil
    }

    func liveModule(_ id: String) -> Live? { live[id] }

    /// `live` entries in the user's chosen order (Settings → Panel), falling
    /// back to registry order for modules they never arranged.
    var enabledModules: [Live] {
        let registry = ModuleRegistry.all.map { type(of: $0).id.rawValue }
        return ModuleOrder.apply(saved: AppSettings.moduleOrder, to: registry)
            .compactMap { live[$0] }
    }

    /// Every module id in the user's order — the settings list reorders this.
    var orderedModuleIDs: [String] {
        ModuleOrder.apply(saved: AppSettings.moduleOrder,
                          to: ModuleRegistry.all.map { type(of: $0).id.rawValue })
    }
}
