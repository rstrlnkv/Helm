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
            // Only from here, never from `bootstrap`: this is somebody switching
            // a module on, which is the moment a module may act unasked.
            NotificationCenter.default.post(name: .helmModuleEnabled,
                                            object: type(of: d).id.rawValue)
        } else {
            disable(d)
        }
    }

    /// Measured **around** the construction, which is the whole point.
    ///
    /// The reading used to be taken on the line before `makeEngine`, so
    /// `module.disk.enable: 9 MB` was the process total *before* Disk existed and
    /// said nothing whatever about Disk. Nine such lines at launch read like nine
    /// per-module costs and were nine consecutive totals.
    ///
    /// What this can and cannot answer, so nobody reads more into it than it holds:
    /// it is what switching the module on cost and what switching it off gave back.
    /// It is **not** how much the module holds while it runs — every module lives in
    /// one process and one malloc zone, and there is no per-subsystem accounting to
    /// ask. The pair is still the signal that matters: 3 MB on and nothing back off
    /// is the leak family `dropWhenDisabled` was written for.
    private func enable(_ d: any ModuleDescriptor) {
        let key = type(of: d).id.rawValue
        HelmLog.shared.info("host", "enable \(key)")
        let before = MemoryFootprint.current()
        let s = store(for: d)
        let engine = d.makeEngine(store: s)
        engine.activate()
        let vm = ModuleViewModel(transport: engine.transport)
        live[key] = Live(descriptor: d, engine: engine, vm: vm, store: s)
        if let before, let after = MemoryFootprint.current() {
            HelmLog.shared.memory("module.\(key).enable", grewBy: after - before)
        }
    }

    private func disable(_ d: any ModuleDescriptor) {
        let key = type(of: d).id.rawValue
        HelmLog.shared.info("host", "disable \(key)")
        let before = MemoryFootprint.current()
        live[key]?.engine.deactivate()
        live[key] = nil
        // Whoever cached UI state for this module drops it, and then the pages
        // go back to the system rather than sitting in an emptied malloc zone.
        NotificationCenter.default.post(name: .helmModuleDisabled, object: key)
        // The reclaim comes first: freeing returns memory to malloc and not to
        // macOS, so a reading taken before it would report nothing given back
        // however much the teardown released.
        MemoryReclaim.afterHeavyWork("module.\(key).disable")
        if let before, let after = MemoryFootprint.current() {
            HelmLog.shared.memory("module.\(key).disable", grewBy: after - before)
        }
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
