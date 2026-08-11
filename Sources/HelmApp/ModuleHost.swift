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

    /// Idempotent, on the same test `setEnabled` has always made and this one
    /// had not: a module already live is left alone.
    ///
    /// It used to assign a second engine over the first without deactivating
    /// it, so every extra call orphaned one engine per enabled module — each
    /// still holding whatever it had registered, and each then freed with it
    /// still registered. For Layout that is a live `CGEvent` tap on the main
    /// run loop pointing at freed memory (`CGKeyTap`), which is a crash inside
    /// whatever the person is typing. The `deinit`s are the backstop for the
    /// routes nobody remembers; not building the orphan is the fix.
    func bootstrap() {
        ObsoleteDefaults.purge(from: UserDefaults.standard)
        for d in ModuleRegistry.all
        where isEnabled(d) && live[type(of: d).id.rawValue] == nil { enable(d) }
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

    /// Every live engine deactivated and dropped; nobody's enabled flag moves.
    ///
    /// This is quitting — or a test suite tidying up after `bootstrap()` — not
    /// somebody switching a module off: no store write, no `.helmModuleDisabled`
    /// post, and the next `bootstrap()` builds the same set again. `disable`
    /// stays the route for the person's own switch, with the persistence and
    /// the notification that act carries.
    func shutdown() {
        for key in live.keys.sorted() {
            live[key]?.engine.deactivate()
            live[key] = nil
            // The same sweep `disable` does: a scan task can outlive the
            // engine that started it.
            HelmActivity.sweep(module: key)
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
        // A scan task can outlive the engine that started it, and an interval
        // nobody closes would name a module that is no longer there.
        HelmActivity.sweep(module: key)
        // Whoever cached UI state for this module drops it, and then the pages
        // go back to the system rather than sitting in an emptied malloc zone.
        NotificationCenter.default.post(name: .helmModuleDisabled, object: key)
        // The reclaim comes first: freeing returns memory to malloc and not to
        // macOS, so a reading taken before it would report nothing given back
        // however much the teardown released.
        if let before, let after = MemoryFootprint.current() {
            HelmLog.shared.memory("module.\(key).disable", grewBy: after - before)
        }
    }

    func liveModule(_ id: String) -> Live? { live[id] }

    /// `live` entries in the arrangement the person composed.
    var enabledModules: [Live] { orderedModuleIDs.compactMap { live[$0] } }

    /// Every module id in the arrangement — one order for the sidebar, the
    /// panel and the icon menu.
    ///
    /// It used to be `AppSettings.moduleOrder`, and that key stopped being
    /// written when the «Module order» section was deleted: nothing in the tree
    /// assigned it, so the panel had been frozen in registry order for everyone
    /// while the composer quietly rearranged the settings sidebar alone. The
    /// person who wanted VPN above Keep Awake in the panel — the surface they
    /// open twenty times a day — had no control at all.
    ///
    /// `reconciled` runs on every read, so a module that arrived with this
    /// build is in the list without anything being rearranged first.
    var orderedModuleIDs: [String] {
        SidebarLayoutStore.read(from: AppSettings.store,
                                registry: SidebarLayoutStore.registry())
            .flattened.compactMap { row in
                if case .module(let id, _) = row { return id }
                return nil
            }
    }
}
